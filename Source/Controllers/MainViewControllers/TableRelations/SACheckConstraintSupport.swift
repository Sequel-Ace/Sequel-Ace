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

    // MARK: - Statements

    @objc(addStatementForTable:name:expression:)
    static func addStatement(table: String, name: String, expression: String) -> String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let constraint = trimmedName.isEmpty ? "" : "CONSTRAINT \(quoted(trimmedName)) "
        let body = expression.trimmingCharacters(in: .whitespacesAndNewlines)

        return "ALTER TABLE \(quoted(table)) ADD \(constraint)CHECK (\(body))"
    }

    /// MySQL 8.0.16 - 8.0.18 only knows `DROP CHECK`; 8.0.19+ and MariaDB use
    /// the generic `DROP CONSTRAINT`.
    @objc(dropStatementForTable:name:mariaDB:major:minor:release:)
    static func dropStatement(table: String, name: String, isMariaDB: Bool, major: Int, minor: Int, release: Int) -> String {
        let usesDropCheck = !isMariaDB && !isVersion(major, minor, release, atLeast: (8, 0, 19))
        let verb = usesDropCheck ? "DROP CHECK" : "DROP CONSTRAINT"

        return "ALTER TABLE \(quoted(table)) \(verb) \(quoted(name))"
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

    // MARK: - Helpers

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
