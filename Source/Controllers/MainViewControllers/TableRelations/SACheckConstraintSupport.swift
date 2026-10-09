import Foundation

/// Pure helpers for CHECK constraints: parsing the definition lines of
/// `SHOW CREATE TABLE`, gating on server support and building the
/// `ALTER TABLE` statements used by the Relations tab.
///
/// Kept free of project ObjC types so the Unit Tests target can compile it.
@objc final class SACheckConstraintSupport: NSObject {

    // Keys of the dictionaries returned by `parseDefinition(_:)`.
    // Keep in sync with the keys read in SPTableRelations.m.
    @objc static let nameKey = "name"
    @objc static let expressionKey = "expression"
    @objc static let enforcedKey = "enforced"

    // MARK: - Server support

    /// CHECK constraints are enforced from MySQL 8.0.16 and MariaDB 10.2.1.
    /// Older servers parse the clause and silently ignore it.
    @objc(serverSupportsCheckConstraintsWithMariaDB:major:minor:release:)
    static func serverSupportsCheckConstraints(isMariaDB: Bool, major: Int, minor: Int, release: Int) -> Bool {
        if isMariaDB {
            return isVersion(major, minor, release, atLeast: (10, 2, 1))
        }
        return isVersion(major, minor, release, atLeast: (8, 0, 16))
    }

    /// `NOT ENFORCED` is a MySQL 8.0.16+ feature; MariaDB has no equivalent.
    @objc(serverSupportsNotEnforcedWithMariaDB:major:minor:release:)
    static func serverSupportsNotEnforced(isMariaDB: Bool, major: Int, minor: Int, release: Int) -> Bool {
        !isMariaDB && isVersion(major, minor, release, atLeast: (8, 0, 16))
    }

    /// The real [major, minor, release] of the server.
    ///
    /// MariaDB 10+ announces itself as `5.5.5-10.11.19-MariaDB` in the handshake and
    /// the MySQL client library reads the leading 5.5.5, so the connection's
    /// major/minor/release numbers are wrong for every MariaDB 10.x and 11.x server.
    /// For MariaDB the version is therefore read from the version string; MySQL's
    /// own numbers are right and are returned unchanged.
    @objc(effectiveVersionForServerVersionString:mariaDB:major:minor:release:)
    static func effectiveVersion(serverVersionString: String?, isMariaDB: Bool, major: Int, minor: Int, release: Int) -> [NSNumber] {
        let reported = [major, minor, release].map { NSNumber(value: $0) }
        guard isMariaDB, var text = serverVersionString else { return reported }

        let replicationPrefix = "5.5.5-"
        if text.hasPrefix(replicationPrefix) {
            text.removeFirst(replicationPrefix.count)
        }

        let parts = text.prefix { $0.isNumber || $0 == "." }.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 3, let first = Int(parts[0]), let second = Int(parts[1]), let third = Int(parts[2]) else {
            return reported
        }
        return [first, second, third].map { NSNumber(value: $0) }
    }

    // MARK: - Statements

    @objc(addStatementForTable:name:expression:enforced:)
    static func addStatement(table: String, name: String, expression: String, enforced: Bool = true) -> String {
        "ALTER TABLE \(quoted(table)) \(addClause(name: name, expression: expression, enforced: enforced))"
    }

    @objc(dropStatementForTable:name:mariaDB:)
    static func dropStatement(table: String, name: String, isMariaDB: Bool) -> String {
        "ALTER TABLE \(quoted(table)) \(dropClause(name: name, isMariaDB: isMariaDB))"
    }

    /// The `ADD ... CHECK` part of an ALTER TABLE, so it can be combined with other clauses.
    @objc(addClauseForName:expression:enforced:)
    static func addClause(name: String, expression: String, enforced: Bool = true) -> String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let constraint = trimmedName.isEmpty ? "" : "CONSTRAINT \(quoted(trimmedName)) "
        let body = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        let suffix = enforced ? "" : " NOT ENFORCED"

        return "ADD \(constraint)CHECK (\(body))\(suffix)"
    }

    /// The `DROP CHECK` / `DROP CONSTRAINT` part of an ALTER TABLE.
    ///
    /// MySQL always gets the constraint-specific `DROP CHECK`. A check can share its name
    /// with a unique key or a foreign key of the same table, and the generic
    /// `DROP CONSTRAINT` then fails with error 3939 because the name is ambiguous. MariaDB
    /// has no `DROP CHECK` and uses `DROP CONSTRAINT`.
    @objc(dropClauseForName:mariaDB:)
    static func dropClause(name: String, isMariaDB: Bool) -> String {
        "\(isMariaDB ? "DROP CONSTRAINT" : "DROP CHECK") \(quoted(name))"
    }

    /// Whether a name (compared case-insensitively) is already used, so the
    /// add sheet can reject duplicates before the server does.
    @objc(isName:takenInNames:)
    static func isName(_ name: String, takenIn names: [String]) -> Bool {
        let lowered = name.lowercased()
        return names.contains { $0.lowercased() == lowered }
    }

    // MARK: - Parsing

    /// Parses one comma-separated element of the `CREATE TABLE` body.
    ///
    /// Accepts `CONSTRAINT [`name`] CHECK (expr) [NOT ENFORCED]` as well as a
    /// bare `CHECK (expr)`. Returns nil for anything else (foreign keys,
    /// indexes, column definitions), so callers can try this first.
    ///
    /// The string must be the raw element, before comments are stripped:
    /// MySQL marks non-enforced checks with `/*!80016 NOT ENFORCED */`.
    ///
    /// Returned dictionary: name (String, empty when unnamed), expression
    /// (String, one redundant outer pair of parentheses removed) and
    /// enforced (NSNumber bool).
    @objc(parseDefinition:)
    static func parseDefinition(_ definition: String) -> [String: Any]? {
        let chars = Array(definition)
        var index = skipWhitespace(chars, from: 0)
        var name = ""

        if matchKeyword("CONSTRAINT", in: chars, at: index) {
            index = skipWhitespace(chars, from: index + "CONSTRAINT".count)

            if index < chars.count, chars[index] == "`" {
                guard let (identifier, next) = readQuotedIdentifier(chars, from: index) else { return nil }
                name = identifier
                index = skipWhitespace(chars, from: next)
            }
        }

        guard matchKeyword("CHECK", in: chars, at: index) else { return nil }
        index = skipWhitespace(chars, from: index + "CHECK".count)

        guard index < chars.count, chars[index] == "(",
              let close = matchingParenthesis(chars, openAt: index) else { return nil }

        let inner = String(chars[(index + 1)..<close]).trimmingCharacters(in: .whitespacesAndNewlines)
        let trailer = String(chars[(close + 1)...]).uppercased()

        return [
            nameKey: name,
            expressionKey: strippingRedundantParentheses(inner),
            enforcedKey: NSNumber(value: !trailer.contains("NOT ENFORCED"))
        ]
    }

    // MARK: - Column references in expressions

    /// Whether `expression` mentions `column`. Only backtick-quoted identifiers outside
    /// string literals count, which is how the server writes every expression it returns.
    @objc(expression:referencesColumn:)
    static func expression(_ expression: String, referencesColumn column: String) -> Bool {
        var found = false
        _ = rewriteIdentifiers(in: expression) { name in
            if isSameColumn(name, column) { found = true }
            return nil
        }
        return found
    }

    /// `expression` with every reference to `column` renamed to `newName`.
    @objc(renamingColumn:to:inExpression:)
    static func renamingColumn(_ column: String, to newName: String, inExpression expression: String) -> String {
        rewriteIdentifiers(in: expression) { isSameColumn($0, column) ? newName : nil }
    }

    // MARK: - Inline checks in column details (MariaDB)

    // MariaDB keeps a check declared on a column inside the column's definition. The
    // Structure tab carries unrecognised definition text along in its `unparsed` value,
    // so that text has to follow a rename too or the server rejects the old name.

    /// `details` with `column` renamed to `newName` inside its `CHECK (...)` groups only.
    @objc(renamingColumn:to:inColumnDetails:)
    static func renamingColumn(_ column: String, to newName: String, inColumnDetails details: String) -> String {
        var chars = Array(details)

        for group in inlineCheckGroups(in: chars).reversed() {
            let inner = String(chars[group.inner])
            let renamed = renamingColumn(column, to: newName, inExpression: inner)
            chars.replaceSubrange(group.inner, with: Array(renamed))
        }
        return String(chars)
    }

    @objc(columnDetails:referencesColumn:)
    static func columnDetails(_ details: String, referencesColumn column: String) -> Bool {
        let chars = Array(details)

        return inlineCheckGroups(in: chars).contains { expression(String(chars[$0.inner]), referencesColumn: column) }
    }

    /// `details` without the `CHECK (...)` groups that reference `column`, and the
    /// whitespace in front of each, for when that column is being dropped.
    @objc(strippingChecksReferencing:fromColumnDetails:)
    static func strippingChecks(referencing column: String, fromColumnDetails details: String) -> String {
        var chars = Array(details)

        for group in inlineCheckGroups(in: chars).reversed() where expression(String(chars[group.inner]), referencesColumn: column) {
            var start = group.clause.lowerBound
            while start > 0, chars[start - 1].isWhitespace { start -= 1 }
            chars.removeSubrange(start..<group.clause.upperBound)
        }
        return String(chars)
    }

    // MARK: - Table-level checks around a column change

    /// The parsed checks (see `parseDefinition`) whose expression mentions `column`.
    @objc(checksReferencingColumn:inChecks:)
    static func checks(referencing column: String, in checks: [[String: Any]]) -> [[String: Any]] {
        checks.filter { check in
            guard let expression = check[expressionKey] as? String else { return false }
            return self.expression(expression, referencesColumn: column)
        }
    }

    /// Whether the server rewrites the column names inside a check when a column is renamed.
    /// MariaDB only does from 10.2.13 (MDEV-13508): before that, `CHANGE` left the old name
    /// in every check and the rename failed. MySQL refuses the rename outright.
    @objc(serverRewritesChecksOnRenameWithMariaDB:major:minor:release:)
    static func serverRewritesChecksOnRename(isMariaDB: Bool, major: Int, minor: Int, release: Int) -> Bool {
        isMariaDB && isVersion(major, minor, release, atLeast: (10, 2, 13))
    }

    /// ALTER TABLE clauses that keep table-level checks valid when `column` is renamed.
    /// Returns `["drop": [...], "add": [...]]`: the drop clauses go before the column
    /// change and the add clauses after it, in the same statement.
    ///
    /// Where the server won't do it (MySQL, and MariaDB before 10.2.13), each such check
    /// is dropped and re-added with the new name. Elsewhere nothing is needed. Checks
    /// without a name cannot be dropped and are skipped.
    @objc(renameClausesRenamingColumn:to:checks:mariaDB:major:minor:release:)
    static func renameClauses(renamingColumn column: String, to newName: String, checks: [[String: Any]], isMariaDB: Bool, major: Int, minor: Int, release: Int) -> [String: [String]] {
        var drop: [String] = []
        var add: [String] = []

        guard !serverRewritesChecksOnRename(isMariaDB: isMariaDB, major: major, minor: minor, release: release) else {
            return ["drop": drop, "add": add]
        }

        for check in self.checks(referencing: column, in: checks) {
            guard let name = check[nameKey] as? String, !name.isEmpty,
                  let expression = check[expressionKey] as? String else { continue }

            let enforced = (check[enforcedKey] as? NSNumber)?.boolValue ?? true
            drop.append(dropClause(name: name, isMariaDB: isMariaDB))
            add.append(addClause(name: name, expression: renamingColumn(column, to: newName, inExpression: expression), enforced: enforced))
        }
        return ["drop": drop, "add": add]
    }

    /// Drop clauses for the table-level checks that use `column`, which the server
    /// won't let go of until those checks are gone. Applies to every server.
    @objc(dropClausesRemovingColumn:checks:mariaDB:)
    static func dropClauses(removingColumn column: String, checks: [[String: Any]], isMariaDB: Bool) -> [String] {
        self.checks(referencing: column, in: checks).compactMap { check in
            guard let name = check[nameKey] as? String, !name.isEmpty else { return nil }
            return dropClause(name: name, isMariaDB: isMariaDB)
        }
    }

    // MARK: - Helpers

    private static func isSameColumn(_ lhs: String, _ rhs: String) -> Bool {
        lhs.caseInsensitiveCompare(rhs) == .orderedSame
    }

    /// Calls `transform` with each backtick-quoted identifier outside string literals and
    /// returns the text with the identifiers it returned a replacement for swapped in.
    private static func rewriteIdentifiers(in text: String, _ transform: (String) -> String?) -> String {
        let chars = Array(text)
        var output = ""
        var index = 0

        while index < chars.count {
            if chars[index] == "`", let (identifier, next) = readQuotedIdentifier(chars, from: index) {
                if let replacement = transform(identifier) {
                    output += quoted(replacement)
                } else {
                    output += String(chars[index..<next])
                }
                index = next
            } else if let next = endOfQuotedSection(chars, at: index) {
                output += String(chars[index..<next])
                index = next
            } else {
                output.append(chars[index])
                index += 1
            }
        }
        return output
    }

    /// Index just past a string literal (plain or in MySQL's escaped `\'...\'` form)
    /// that starts at `index`, or nil when none starts there.
    private static func endOfQuotedSection(_ chars: [Character], at index: Int) -> Int? {
        switch chars[index] {
        case "'", "\"":
            return endOfQuoted(chars, openAt: index).map { $0 + 1 }
        case "\\":
            guard index + 1 < chars.count, chars[index + 1] == "'" || chars[index + 1] == "\"" else { return nil }
            return endOfEscapedQuoted(chars, openAt: index).map { $0 + 1 }
        default:
            return nil
        }
    }

    /// The `CHECK (...)` groups in a column definition tail: the range of the whole clause
    /// and of the expression inside the parentheses. Quoted text is skipped, so a
    /// literal that merely contains the word CHECK does not count.
    private static func inlineCheckGroups(in chars: [Character]) -> [(clause: Range<Int>, inner: Range<Int>)] {
        var groups: [(clause: Range<Int>, inner: Range<Int>)] = []
        var index = 0

        while index < chars.count {
            if chars[index] == "`", let (_, next) = readQuotedIdentifier(chars, from: index) {
                index = next
            } else if let next = endOfQuotedSection(chars, at: index) {
                index = next
            } else if isWordStart(chars, at: index), matchKeyword("CHECK", in: chars, at: index) {
                let open = skipWhitespace(chars, from: index + "CHECK".count)
                if open < chars.count, chars[open] == "(", let close = matchingParenthesis(chars, openAt: open) {
                    groups.append((clause: index..<(close + 1), inner: (open + 1)..<close))
                    index = close + 1
                } else {
                    index += "CHECK".count
                }
            } else {
                index += 1
            }
        }
        return groups
    }

    private static func isWordStart(_ chars: [Character], at index: Int) -> Bool {
        guard index > 0 else { return true }
        let previous = chars[index - 1]
        return !(previous.isLetter || previous.isNumber || previous == "_")
    }

    private static func isVersion(_ major: Int, _ minor: Int, _ release: Int, atLeast minimum: (Int, Int, Int)) -> Bool {
        (major, minor, release) >= minimum
    }

    private static func quoted(_ identifier: String) -> String {
        "`" + identifier.replacingOccurrences(of: "`", with: "``") + "`"
    }

    private static func skipWhitespace(_ chars: [Character], from start: Int) -> Int {
        var index = start
        while index < chars.count, chars[index].isWhitespace { index += 1 }
        return index
    }

    /// Case-insensitive keyword match that must end at a word boundary, so
    /// `CHECKSUM` or `CONSTRAINTS` are not mistaken for keywords.
    private static func matchKeyword(_ keyword: String, in chars: [Character], at start: Int) -> Bool {
        let end = start + keyword.count
        guard end <= chars.count else { return false }
        guard String(chars[start..<end]).uppercased() == keyword else { return false }
        guard end < chars.count else { return true }

        let next = chars[end]
        return !(next.isLetter || next.isNumber || next == "_")
    }

    /// Reads a backtick-quoted identifier (`` `` `` escapes a backtick) and
    /// returns it with the index just past the closing backtick.
    private static func readQuotedIdentifier(_ chars: [Character], from start: Int) -> (String, Int)? {
        var result = ""
        var index = start + 1

        while index < chars.count {
            if chars[index] == "`" {
                if index + 1 < chars.count, chars[index + 1] == "`" {
                    result.append("`")
                    index += 2
                    continue
                }
                return (result, index + 1)
            }
            result.append(chars[index])
            index += 1
        }
        return nil
    }

    /// Index of the parenthesis closing the one at `openAt`, ignoring any
    /// parentheses inside quoted strings or identifiers.
    private static func matchingParenthesis(_ chars: [Character], openAt: Int) -> Int? {
        var depth = 0
        var index = openAt

        while index < chars.count {
            let char = chars[index]

            switch char {
            case "'", "\"", "`":
                guard let next = endOfQuoted(chars, openAt: index) else { return nil }
                index = next
            case "\\":
                // MySQL writes string literals inside a CHECK as \'...\' in SHOW CREATE TABLE
                guard index + 1 < chars.count, chars[index + 1] == "'" || chars[index + 1] == "\"" else { break }
                guard let next = endOfEscapedQuoted(chars, openAt: index) else { return nil }
                index = next
            case "(":
                depth += 1
            case ")":
                depth -= 1
                if depth == 0 { return index }
            default:
                break
            }
            index += 1
        }
        return nil
    }

    /// Index of the closing quote for the quote at `openAt`. Handles doubled
    /// quotes, and backslash escapes in string literals.
    private static func endOfQuoted(_ chars: [Character], openAt: Int) -> Int? {
        let quote = chars[openAt]
        var index = openAt + 1

        while index < chars.count {
            let char = chars[index]

            if char == "\\", quote != "`" {
                index += 2
                continue
            }
            if char == quote {
                if index + 1 < chars.count, chars[index + 1] == quote {
                    index += 2
                    continue
                }
                return index
            }
            index += 1
        }
        return nil
    }

    /// Index of the closing `\'` for the escaped quote starting at the backslash
    /// at `openAt`. Inside, a backslash pair (`\\`) is skipped as a unit.
    private static func endOfEscapedQuoted(_ chars: [Character], openAt: Int) -> Int? {
        let quote = chars[openAt + 1]
        var index = openAt + 2

        while index < chars.count {
            if chars[index] == "\\" {
                guard index + 1 < chars.count else { return nil }
                if chars[index + 1] == quote { return index + 1 }
                index += 2
                continue
            }
            index += 1
        }
        return nil
    }

    /// MySQL stores `CHECK (a > 0)` as `CHECK ((a > 0))`. Remove one layer when
    /// a single pair of parentheses encloses the whole expression, leaving
    /// `(a > 0) AND (b > 0)` untouched.
    private static func strippingRedundantParentheses(_ expression: String) -> String {
        let chars = Array(expression)

        guard chars.first == "(", matchingParenthesis(chars, openAt: 0) == chars.count - 1 else {
            return expression
        }
        return String(chars[1..<(chars.count - 1)]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
