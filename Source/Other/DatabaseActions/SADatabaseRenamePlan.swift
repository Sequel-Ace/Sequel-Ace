//
//  SADatabaseRenamePlan.swift
//  Sequel Ace
//
//  Created by Sequel-Ace contributors on 2026.09.14.
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import Foundation

/// The kinds of schema object "Rename Database" moves.
@objc public enum SADatabaseRenameObjectKind: Int {
    case table
    case view
}

/// Decides what "Rename Database" may do and explains why it stopped.
///
/// MySQL has no `RENAME DATABASE`, so the app creates the target database,
/// moves every table with `RENAME TABLE`, recreates every view and finally
/// drops the source database. Dropping is only safe once every object made
/// it across: a partial move followed by `DROP DATABASE` deletes whatever was
/// left behind. Triggers block `RENAME TABLE` across databases, and routines
/// and events are never moved, so a source database holding any of them is
/// refused before anything changes. The object lists come straight from
/// `information_schema`, not from the sidebar's table list, which carries
/// pinned tables twice and never loads events.
@objc public final class SADatabaseRenamePlan: NSObject {

    private let sourceDatabase: String
    private let targetDatabase: String

    /// The tables to move with `RENAME TABLE`, in `information_schema` order.
    @objc public let tables: [String]
    /// The views to recreate in the target, in `information_schema` order.
    @objc public let views: [String]
    /// Objects the rename cannot move, each named with its kind.
    @objc public let unsupportedObjects: [String]
    /// Whether the server compares schema names without regard to case
    /// (`lower_case_table_names` 1 or 2, the default on macOS and Windows).
    @objc public let caseInsensitiveNames: Bool

    private var inspectionFailureReason: String?
    private var unsupportedCharacterSet: (characterSet: String, view: String)?
    private var unsupportedDefinitionView: String?
    private var objectPrivileges: [String] = []
    private var createFailureReason: String?
    private var failedObject: String?
    private var failedObjectReason: String?
    private var dropFailureReason: String?

    /// Creates the plan for renaming `sourceDatabase` to `targetDatabase` from
    /// the source database's `information_schema` rows. The rows are taken as
    /// they are: the server lists each object once, and folding names further
    /// (Swift's `String` equality treats canonically equivalent names such as
    /// NFC and NFD `café` as equal, the server does not) could hide a table
    /// from the move and drop it with the source.
    ///
    /// - Parameters:
    ///   - sourceDatabase: The database being renamed.
    ///   - targetDatabase: The name it is renamed to.
    ///   - lowerCaseTableNames: The server's `@@lower_case_table_names`.
    ///   - tableRows: `TABLE_NAME, TABLE_TYPE` rows of `information_schema.TABLES`;
    ///     a `VIEW` row is a view, every other row a table.
    ///   - routineRows: `ROUTINE_NAME, ROUTINE_TYPE` rows of `information_schema.ROUTINES`.
    ///   - eventRows: `EVENT_NAME` rows of `information_schema.EVENTS`.
    ///   - triggerRows: `TRIGGER_NAME, EVENT_OBJECT_TABLE` rows of `information_schema.TRIGGERS`.
    @objc(initWithSourceDatabase:targetDatabase:lowerCaseTableNames:tableRows:routineRows:eventRows:triggerRows:)
    public init(sourceDatabase: String, targetDatabase: String, lowerCaseTableNames: Int, tableRows: [[Any]], routineRows: [[Any]], eventRows: [[Any]], triggerRows: [[Any]]) {
        self.sourceDatabase = sourceDatabase
        self.targetDatabase = targetDatabase
        caseInsensitiveNames = lowerCaseTableNames != 0

        let tableRows = Self.stringRows(tableRows, columns: 2)
        tables = tableRows.filter { $0[1].uppercased() != "VIEW" }.map { $0[0] }
        views = tableRows.filter { $0[1].uppercased() == "VIEW" }.map { $0[0] }

        let routines = Self.stringRows(routineRows, columns: 2)
        unsupportedObjects =
            Self.stringRows(triggerRows, columns: 2).map {
                String(format: NSLocalizedString("trigger '%@' on table '%@'", comment: "rename database: a trigger, by name and table; listed among the objects that block the rename"), $0[0], $0[1])
            }
            + routines.filter { $0[1].uppercased() == "PROCEDURE" }.map {
                String(format: NSLocalizedString("procedure '%@'", comment: "rename database: a stored procedure, by name; listed among the objects that block the rename"), $0[0])
            }
            + routines.filter { $0[1].uppercased() != "PROCEDURE" }.map {
                String(format: NSLocalizedString("function '%@'", comment: "rename database: a stored function, by name; listed among the objects that block the rename"), $0[0])
            }
            + Self.stringRows(eventRows, columns: 1).map {
                String(format: NSLocalizedString("event '%@'", comment: "rename database: a scheduled event, by name; listed among the objects that block the rename"), $0[0])
            }
    }

    /// Keeps the rows whose first `columns` values are strings; `information_schema`
    /// never returns NULL for the names and types read here.
    private static func stringRows(_ rows: [[Any]], columns: Int) -> [[String]] {
        rows.compactMap { row in
            let values = row.prefix(columns).compactMap { $0 as? String }
            return values.count == columns ? values : nil
        }
    }

    /// Records that reading the source database's objects failed; without a
    /// complete picture nothing is moved.
    ///
    /// - Parameter reason: The server's error message, if any.
    @objc(recordInspectionFailure:)
    public func recordInspectionFailure(_ reason: String?) {
        inspectionFailureReason = reason ?? Self.unknownReason
    }

    /// Records that a view was created through a character set other than
    /// UTF-8, so its definition could not be recreated faithfully through
    /// the connection's UTF-8 transport.
    ///
    /// - Parameters:
    ///   - characterSet: The view's `character_set_client`.
    ///   - view: The view.
    @objc(recordUnsupportedCharacterSet:ofView:)
    public func recordUnsupportedCharacterSet(_ characterSet: String, ofView view: String) {
        unsupportedCharacterSet = (characterSet, view)
    }

    /// Records that a view's definition holds bytes or a literal outside
    /// UTF-8, so it could not travel through the connection without change.
    ///
    /// - Parameter view: The view.
    @objc(recordUnsupportedDefinitionOfView:)
    public func recordUnsupportedDefinition(ofView view: String) {
        unsupportedDefinitionView = view
    }

    /// Records privileges granted on the source's tables or views. Such
    /// grants stay behind: `RENAME TABLE` does not carry them across
    /// databases and a recreated view has none, so the rename is refused.
    ///
    /// - Parameter descriptions: One entry per grant, as `` `table` for
    ///   'user'@'host' ``.
    @objc(recordObjectPrivileges:)
    public func recordObjectPrivileges(_ descriptions: [String]) {
        objectPrivileges = descriptions
    }

    /// Whether the rename may start: the source was inspected and holds
    /// nothing the rename cannot move.
    @objc public var canStart: Bool {
        inspectionFailureReason == nil && unsupportedObjects.isEmpty && unsupportedCharacterSet == nil && unsupportedDefinitionView == nil && objectPrivileges.isEmpty
    }

    /// Records that creating the target database failed.
    ///
    /// - Parameter reason: The server's error message, if any.
    @objc(recordCreateFailure:)
    public func recordCreateFailure(_ reason: String?) {
        createFailureReason = reason ?? Self.unknownReason
    }

    /// Records the outcome of moving one object and returns whether the
    /// caller may go on with the next one. After a failure nothing further is
    /// moved, so as few objects as possible end up split across two databases.
    ///
    /// - Parameters:
    ///   - name: The object's name.
    ///   - kind: Whether it is a table or a view.
    ///   - succeeded: Whether the move succeeded.
    ///   - reason: The server's error message when it failed.
    /// - Returns: `true` while every move so far succeeded.
    @objc(recordMoveOfObject:kind:succeeded:reason:)
    public func recordMove(of name: String, kind: SADatabaseRenameObjectKind, succeeded: Bool, reason: String?) -> Bool {
        guard !succeeded, failedObject == nil else {
            return succeeded && failedObject == nil
        }
        failedObject = Self.description(of: name, kind: kind)
        failedObjectReason = reason ?? Self.unknownReason
        return false
    }

    /// Records that dropping the source database failed after every object
    /// had moved.
    ///
    /// - Parameter reason: The server's error message, if any.
    @objc(recordDropFailure:)
    public func recordDropFailure(_ reason: String?) {
        dropFailureReason = reason ?? Self.unknownReason
    }

    /// Whether the source database may be dropped: the rename could start,
    /// the target exists and every object moved.
    @objc public var mayDropSourceDatabase: Bool {
        canStart && createFailureReason == nil && failedObject == nil
    }

    /// Why the rename stopped, for the alert, or `nil` while nothing went wrong.
    @objc public var failureDescription: String? {
        if let inspectionFailureReason {
            return String(
                format: NSLocalizedString("Reading the objects of the database '%@' failed: %@ Nothing was changed.", comment: "rename database: querying information_schema failed; %1$@ source database, %2$@ server error"),
                sourceDatabase, inspectionFailureReason
            )
        }
        if !unsupportedObjects.isEmpty {
            return String(
                format: NSLocalizedString("The database contains objects that Rename Database cannot move: %@. Nothing was changed.", comment: "rename database refused because the source holds triggers, routines or events; %@ lists them"),
                unsupportedObjects.joined(separator: ", ")
            )
        }
        if !objectPrivileges.isEmpty {
            let shown = objectPrivileges.prefix(5) + (objectPrivileges.count > 5 ? ["…"] : [])
            return String(
                format: NSLocalizedString("The database has privileges granted on it, its tables or its views, or partially revoked on it (%@), which Rename Database cannot move. Nothing was changed.", comment: "rename database refused because GRANTs on the source database or its tables or views, or a partial revoke for the database, would be lost; %@ lists them as `db`.* or `table` for 'user'@'host', or partial revoke on `db`.* for 'user'@'host'"),
                shown.joined(separator: ", ")
            )
        }
        if let unsupportedCharacterSet {
            return String(
                format: NSLocalizedString("The view '%@' was created through the character set '%@'; Rename Database can only recreate views created through UTF-8. Nothing was changed.", comment: "rename database refused because a view's client character set is not UTF-8; %1$@ view, %2$@ character set"),
                unsupportedCharacterSet.view, unsupportedCharacterSet.characterSet
            )
        }
        if let unsupportedDefinitionView {
            return String(
                format: NSLocalizedString("The definition of the view '%@' holds a string outside UTF-8; Rename Database cannot recreate it faithfully. Nothing was changed.", comment: "rename database refused because a view definition holds bytes or a literal (e.g. _latin1'…', _binary'…') outside UTF-8; %@ view"),
                unsupportedDefinitionView
            )
        }
        if let createFailureReason {
            return String(
                format: NSLocalizedString("Creating the database '%@' failed: %@", comment: "rename database: creating the target database failed; %1$@ target name, %2$@ server error"),
                targetDatabase, createFailureReason
            )
        }
        if let failedObject, let failedObjectReason {
            return String(
                format: NSLocalizedString("Moving %@ failed: %@ The objects moved so far are in '%@'; '%@' was not dropped.", comment: "rename database: moving one object failed; %1$@ object, %2$@ server error, %3$@ target database, %4$@ source database"),
                failedObject, failedObjectReason, targetDatabase, sourceDatabase
            )
        }
        if let dropFailureReason {
            return String(
                format: NSLocalizedString("Every object was moved to '%@', but dropping '%@' failed: %@", comment: "rename database: dropping the emptied source database failed; %1$@ target, %2$@ source, %3$@ server error"),
                targetDatabase, sourceDatabase, dropFailureReason
            )
        }
        return nil
    }

    static var unknownReason: String {
        NSLocalizedString("unknown error", comment: "rename database: the server reported no error message")
    }

    private static func description(of name: String, kind: SADatabaseRenameObjectKind) -> String {
        switch kind {
        case .table:
            return String(format: NSLocalizedString("table '%@'", comment: "rename database: a table, by name"), name)
        case .view:
            return String(format: NSLocalizedString("view '%@'", comment: "rename database: a view, by name"), name)
        }
    }
}

/// The outcome of rewriting a view's `CREATE` statement for the target database.
@objc public final class SADatabaseRenameViewRewrite: NSObject {

    /// The statement to run, or `nil` when it could not be rewritten.
    @objc public let statement: String?
    /// Why it could not be rewritten, phrased to follow "Moving view 'x' failed:".
    @objc public let failureReason: String?
    /// The names, unquoted, of the objects the definition reads from that
    /// live in the source database - references qualified with it and
    /// unqualified ones, in the order they appear - so the views can be
    /// created after the views they select from. Aliases and CTE names in
    /// object position may be among them; they match no view and do no harm.
    @objc public let referencedObjects: [String]

    init(statement: String, referencedObjects: [String]) {
        self.statement = statement
        self.referencedObjects = referencedObjects
        failureReason = nil
    }

    init(failureReason: String) {
        statement = nil
        referencedObjects = []
        self.failureReason = failureReason
    }
}

/// Rewrites the definition `SHOW CREATE VIEW` returns so it creates the view
/// in the target database and reads from the target's objects.
///
/// The server prints the definition in a normalised form: every identifier
/// is backticked, every object reference is qualified with its database, and
/// column references are `db`.`object`.`column` or `alias`.`column`. The
/// rewriter tokenises that text and follows the clause structure, so it knows
/// which dotted names are object references (after `FROM`, `JOIN` and the
/// commas of a `FROM` list) and which are column references (everywhere
/// else, including `ON`, `WHERE` and the select list, also inside nested
/// subqueries): only the database part of object references, of three-part
/// column references and of the `VIEW` clause changes. Table aliases, column
/// aliases, columns qualified with a view or alias named like the database,
/// the `FROM` inside `EXTRACT(… FROM …)`-style function calls and string
/// literals are left alone. Database names are compared byte for byte, or
/// without regard to case when the server does so.
@objc public final class SADatabaseRenameViewRewriter: NSObject {

    private enum Context {
        case expression
        case objectReferences
    }

    private enum Token {
        case name([String])
        case word(String)
        case literal(String)
        case symbol(Character)
        case whitespace(String)
    }

    private let sourceDatabase: String
    private let serverLoweredSource: String?
    private let quotedTarget: String
    private let caseInsensitiveNames: Bool

    /// Creates a rewriter for views moving from `sourceDatabase` to `targetDatabase`.
    ///
    /// - Parameters:
    ///   - sourceDatabase: The database the views live in.
    ///   - targetDatabase: The database they are recreated in.
    ///   - caseInsensitiveNames: Whether the server compares database names
    ///     without regard to case (`lower_case_table_names` 1 or 2).
    ///   - serverLoweredSource: The source's name as the server folds it
    ///     (`SELECT LOWER(…)`), which is how it prints the name where it
    ///     folds case; the server also folds letters beyond ASCII, so this
    ///     form is the reference and the client's ASCII folding only an
    ///     approximation for when it could not be read.
    @objc(initWithSourceDatabase:targetDatabase:caseInsensitiveNames:serverLoweredSource:)
    public init(sourceDatabase: String, targetDatabase: String, caseInsensitiveNames: Bool, serverLoweredSource: String?) {
        self.sourceDatabase = sourceDatabase
        self.serverLoweredSource = serverLoweredSource
        quotedTarget = Self.backtickQuoted(targetDatabase)
        self.caseInsensitiveNames = caseInsensitiveNames
    }

    /// Creates a rewriter without the server-folded form of the source.
    @objc(initWithSourceDatabase:targetDatabase:caseInsensitiveNames:)
    public convenience init(sourceDatabase: String, targetDatabase: String, caseInsensitiveNames: Bool) {
        self.init(sourceDatabase: sourceDatabase, targetDatabase: targetDatabase, caseInsensitiveNames: caseInsensitiveNames, serverLoweredSource: nil)
    }

    /// Rewrites one view definition.
    ///
    /// - Parameters:
    ///   - statement: The `Create View` column of `SHOW CREATE VIEW`.
    ///   - view: The view's name.
    /// - Returns: The rewritten statement, or the reason it could not be rewritten.
    @objc(rewriteCreateStatement:forView:)
    public func rewriteCreateStatement(_ statement: String, forView view: String) -> SADatabaseRenameViewRewrite {
        var output = ""
        var context = Context.expression
        // one entry per open parenthesis: the context to restore and whether
        // the parenthesis belongs to a function call, whose FROM is an argument
        var stack: [(context: Context, isFunctionCall: Bool)] = []
        var expectingAlias = false
        var awaitingViewName = false
        var viewClauseRewritten = false
        var referencedObjects: [String] = []
        var previous: Token?

        for token in Self.tokens(of: statement) {
            defer {
                if case .whitespace = token {} else { previous = token }
            }

            switch token {
            case .whitespace(let text), .literal(let text):
                output += text

            case .word(let word):
                let keyword = word.uppercased()
                // A SELECT (or a WITH introducing one) right after a parenthesis
                // makes it a subquery, however the word before the parenthesis
                // was read (`DIV (select …)`, `x REGEXP (select …)`,
                // `INTERVAL (select …) DAY`, `DIV (with … select …)`).
                if keyword == "SELECT" || keyword == "WITH", case .symbol("(") = previous, !stack.isEmpty {
                    stack[stack.count - 1].isFunctionCall = false
                }
                let insideFunctionCall = stack.last?.isFunctionCall == true
                if keyword == "VIEW", !viewClauseRewritten {
                    awaitingViewName = true
                } else if keyword == "FROM" || Self.isJoin(keyword, after: previous) {
                    if !insideFunctionCall {
                        context = .objectReferences
                        expectingAlias = false
                    }
                } else if Self.expressionKeywords.contains(keyword) {
                    context = .expression
                }
                output += word

            case .symbol(let symbol):
                switch symbol {
                case "(":
                    let isFunctionCall = Self.opensFunctionCall(after: previous)
                    stack.append((context, isFunctionCall))
                    // The server wraps a FROM list in parentheses and a derived
                    // table starts with SELECT, which switches to expressions
                    // itself; function arguments and any other parenthesis
                    // open an expression - except the argument of a sequence
                    // function, which names a sequence and moves with the tables.
                    if Self.takesSequenceArgument(previous) {
                        context = .objectReferences
                        expectingAlias = false
                    } else if isFunctionCall || context != .objectReferences || expectingAlias {
                        context = .expression
                    }
                case ")":
                    context = stack.popLast()?.context ?? .expression
                    // a closing parenthesis in a FROM list ends a derived table, whose alias follows
                    expectingAlias = context == .objectReferences
                case ",":
                    if context == .objectReferences {
                        expectingAlias = false
                        // only the first argument of a sequence function names
                        // a sequence; the remaining ones are expressions
                        if stack.last?.isFunctionCall == true {
                            context = .expression
                        }
                    }
                default:
                    break
                }
                output.append(symbol)

            case .name(let parts):
                var rewritten = parts
                if awaitingViewName {
                    awaitingViewName = false
                    viewClauseRewritten = true
                    if parts.count == 1 {
                        rewritten = [quotedTarget, parts[0]]
                    } else if parts.count == 2, isSourceDatabase(parts[0]) {
                        rewritten[0] = quotedTarget
                    }
                } else if context == .objectReferences, !expectingAlias {
                    // `db`.`object` after FROM/JOIN/comma: the first part is the database
                    if parts.count == 2, isSourceDatabase(parts[0]) {
                        rewritten[0] = quotedTarget
                        referencedObjects.append(Self.unquoted(parts[1]))
                    } else if parts.count == 1 {
                        referencedObjects.append(Self.unquoted(parts[0]))
                    }
                    expectingAlias = true
                } else if context == .objectReferences {
                    // the alias of the object reference just seen
                    expectingAlias = false
                } else if parts.count == 3, isSourceDatabase(parts[0]) {
                    // `db`.`object`.`column`; a two-part name here is `object`.`column`
                    rewritten[0] = quotedTarget
                }
                output += rewritten.joined(separator: ".")
            }
        }

        guard viewClauseRewritten else {
            return SADatabaseRenameViewRewrite(failureReason: NSLocalizedString("its definition returned by SHOW CREATE VIEW has no VIEW clause.", comment: "rename database: why a view was not recreated"))
        }
        return SADatabaseRenameViewRewrite(statement: output, referencedObjects: referencedObjects)
    }

    /// Keywords after which dotted names are column references again.
    private static let expressionKeywords: Set<String> = [
        "SELECT", "ON", "USING", "WHERE", "GROUP", "HAVING", "WINDOW", "ORDER", "LIMIT", "UNION", "EXCEPT", "INTERSECT", "SET", "WITH"
    ]

    /// Keywords that precede a parenthesis without calling a function, so the
    /// parenthesis opens a subquery, a nested join or a grouped expression.
    private static let nonFunctionKeywords: Set<String> = [
        "SELECT", "FROM", "JOIN", "LATERAL", "WHERE", "AND", "OR", "NOT", "ON", "IN", "EXISTS", "ANY", "ALL", "SOME", "USING", "VALUES", "AS",
        "THEN", "ELSE", "WHEN", "CASE", "BY", "HAVING", "LIMIT", "UNION", "EXCEPT", "INTERSECT", "SET", "WITH", "DISTINCT",
        "BETWEEN", "LIKE", "IS", "OVER", "ORDER", "GROUP", "WINDOW", "RETURNING"
    ]

    /// Words after which `STRAIGHT_JOIN` is a select option (`select
    /// straight_join …`), not a join between two object references.
    private static let selectOptionPredecessors: Set<String> = ["SELECT", "ALL", "DISTINCT", "DISTINCTROW", "HIGH_PRIORITY"]

    /// Whether the keyword joins two object references: `JOIN` with any
    /// prefix (`LEFT JOIN`, `NATURAL JOIN`, `STRAIGHT_JOIN`), except the
    /// `STRAIGHT_JOIN` that follows `SELECT` as a select option.
    private static func isJoin(_ keyword: String, after token: Token?) -> Bool {
        guard keyword.hasSuffix("JOIN") else { return false }
        if case .word(let word) = token, selectOptionPredecessors.contains(word.uppercased()) {
            return false
        }
        return true
    }

    /// MariaDB's sequence functions, whose first argument is a sequence:
    /// `NEXT VALUE FOR s` is printed as `nextval(`db`.`s`)`, and a sequence is
    /// listed as a table in `information_schema`, so it moves with the tables.
    private static let sequenceFunctions: Set<String> = ["NEXTVAL", "LASTVAL", "SETVAL"]

    /// Whether the parenthesis after this token opens a sequence function call.
    private static func takesSequenceArgument(_ token: Token?) -> Bool {
        if case .word(let word) = token {
            return sequenceFunctions.contains(word.uppercased())
        }
        return false
    }

    /// Whether a parenthesis following this token opens a function call: a
    /// word that is neither one of the keywords above nor a join, or a
    /// (possibly qualified) stored function name.
    private static func opensFunctionCall(after token: Token?) -> Bool {
        switch token {
        case .word(let word):
            let keyword = word.uppercased()
            return !nonFunctionKeywords.contains(keyword) && !keyword.hasSuffix("JOIN")
        case .name:
            return true
        default:
            return false
        }
    }

    /// Whether a backticked identifier names the source database, compared
    /// the way the server compares database names: byte for byte, or - where
    /// the server folds case - equal to the source's server-folded form or
    /// to it under ASCII folding.
    private func isSourceDatabase(_ quotedIdentifier: String) -> Bool {
        let name = Self.unquoted(quotedIdentifier)
        if name.utf8.elementsEqual(sourceDatabase.utf8) {
            return true
        }
        guard caseInsensitiveNames else { return false }
        if let serverLoweredSource, name.utf8.elementsEqual(serverLoweredSource.utf8) {
            return true
        }
        return Self.asciiLowercased(Array(name.utf8)) == Self.asciiLowercased(Array(sourceDatabase.utf8))
    }

    /// The bytes of a name with the ASCII letters folded to lower case - an
    /// approximation of the folding the server applies to database and
    /// table names under `lower_case_table_names`, for when the server's own
    /// folded form is not at hand. Unicode case folding is not applied on
    /// purpose: it would merge names the server keeps apart (`ẞ` and `ß`,
    /// say), and a merged name could hide a view from the rename.
    static func asciiLowercased(_ bytes: [UInt8]) -> [UInt8] {
        bytes.map { (0x41...0x5A).contains($0) ? $0 + 0x20 : $0 }
    }

    /// The name inside a backticked identifier, with doubled backticks undone.
    private static func unquoted(_ quotedIdentifier: String) -> String {
        // scalars, not Characters: a combining mark after the opening backtick
        // would otherwise be dropped together with it
        String(String.UnicodeScalarView(quotedIdentifier.unicodeScalars.dropFirst().dropLast())).replacingOccurrences(of: "``", with: "`")
    }

    static func backtickQuoted(_ name: String) -> String {
        "`" + name.replacingOccurrences(of: "`", with: "``") + "`"
    }

    /// Whether the definition holds a string literal the server printed with
    /// a character set introducer other than UTF-8 - `_latin1'…'`,
    /// `_binary'…'`, `_latin1 0xE9`, `_latin1 X'E9'`. The server prints an
    /// introducer exactly when a literal's character set differs from the
    /// connection's, so such a literal's bytes are not UTF-8 and would be
    /// altered on the way through the connection's UTF-8 transport; the
    /// introducer itself is ASCII and survives any decoding.
    ///
    /// - Parameter statement: The `Create View` column of `SHOW CREATE VIEW`.
    static func hasLiteralOutsideUTF8(_ statement: String) -> Bool {
        let tokens = tokens(of: statement).filter {
            if case .whitespace = $0 { return false }
            return true
        }
        for (index, token) in tokens.enumerated() {
            guard case .word(let word) = token, word.count > 1, word.hasPrefix("_"), index + 1 < tokens.count else { continue }
            let introducesLiteral: Bool
            switch tokens[index + 1] {
            case .literal:
                introducesLiteral = true
            case .word(let next):
                let lowered = next.lowercased()
                if lowered.hasPrefix("0x") || lowered.hasPrefix("0b") {
                    introducesLiteral = true
                } else if lowered == "x" || lowered == "b", index + 2 < tokens.count, case .literal = tokens[index + 2] {
                    introducesLiteral = true
                } else {
                    introducesLiteral = false
                }
            default:
                introducesLiteral = false
            }
            if introducesLiteral, !SADatabaseRenameExecutor.isUTF8(String(word.dropFirst())) {
                return true
            }
        }
        return false
    }

    /// Splits the definition into string literals (copied verbatim, honouring
    /// backslash and doubled-quote escapes), dotted backticked names, words,
    /// whitespace and single symbols. It works on Unicode scalars, not
    /// Characters: a combining mark right after a quote would otherwise merge
    /// with it into one Character and hide the delimiter.
    private static func tokens(of statement: String) -> [Token] {
        let scalars = Array(statement.unicodeScalars)
        var tokens: [Token] = []
        var index = 0

        func text(_ range: Range<Int>) -> String {
            var view = String.UnicodeScalarView()
            view.append(contentsOf: scalars[range])
            return String(view)
        }

        func readQuotedIdentifier() -> String? {
            guard index < scalars.count, scalars[index] == "`" else { return nil }
            var end = index + 1
            while end < scalars.count {
                if scalars[end] == "`" {
                    if end + 1 < scalars.count, scalars[end + 1] == "`" {
                        end += 2
                        continue
                    }
                    break
                }
                end += 1
            }
            let identifier = text(index..<min(end + 1, scalars.count))
            index = end + 1
            return identifier
        }

        while index < scalars.count {
            let scalar = scalars[index]

            if scalar == "'" || scalar == "\"" {
                var end = index + 1
                while end < scalars.count {
                    let next = scalars[end]
                    end += 1
                    if next == "\\", end < scalars.count {
                        end += 1
                    } else if next == scalar {
                        if end < scalars.count, scalars[end] == scalar {
                            end += 1
                        } else {
                            break
                        }
                    }
                }
                tokens.append(.literal(text(index..<end)))
                index = end
                continue
            }

            if scalar == "`" {
                var parts: [String] = []
                while let identifier = readQuotedIdentifier() {
                    parts.append(identifier)
                    guard index + 1 < scalars.count, scalars[index] == ".", scalars[index + 1] == "`" else {
                        break
                    }
                    index += 1
                }
                tokens.append(.name(parts))
                continue
            }

            if Self.isWordScalar(scalar) {
                var end = index
                while end < scalars.count, Self.isWordScalar(scalars[end]) {
                    end += 1
                }
                tokens.append(.word(text(index..<end)))
                index = end
                continue
            }

            if scalar.properties.isWhitespace {
                var end = index
                while end < scalars.count, scalars[end].properties.isWhitespace {
                    end += 1
                }
                tokens.append(.whitespace(text(index..<end)))
                index = end
                continue
            }

            tokens.append(.symbol(Character(scalar)))
            index += 1
        }

        return tokens
    }

    /// The scalars of an unquoted identifier or keyword as the server reads
    /// them: ASCII letters, digits, `_`, `$` and anything beyond ASCII.
    private static func isWordScalar(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x30...0x39, 0x41...0x5A, 0x61...0x7A, 0x5F, 0x24:
            return true
        default:
            return scalar.value >= 0x80 && !scalar.properties.isWhitespace
        }
    }
}

/// Retries the recreation of views that failed while others succeeded: a
/// `CREATE VIEW` that reads from a view not yet present in the target fails,
/// so failed views are retried after the others. The views arrive here
/// already ordered by their references (see `SADatabaseRenameExecutor`), so
/// a retry is only needed for a dependency the rewriter could not see. A
/// pass in which no view could be created means the remaining failures are
/// real, and the first of them is reported.
@objc public final class SADatabaseRenameViewQueue: NSObject {

    private var pending: [String]
    private var failedThisPass: [(view: String, reason: String?)] = []
    private var createdThisPass = 0
    private var position = 0

    /// The first view whose creation failed for a reason other than ordering,
    /// with the reason.
    @objc public private(set) var stuckView: String?
    @objc public private(set) var stuckReason: String?

    /// Creates the queue for `views`.
    @objc(initWithViews:)
    public init(views: [String]) {
        pending = views
    }

    /// The next view to create, or `nil` when every view was created or the
    /// queue is stuck.
    @objc public var next: String? {
        guard stuckView == nil else { return nil }
        if position == pending.count {
            guard !failedThisPass.isEmpty else { return nil }
            if createdThisPass == 0 {
                stuckView = failedThisPass[0].view
                stuckReason = failedThisPass[0].reason
                return nil
            }
            pending = failedThisPass.map(\.view)
            failedThisPass = []
            createdThisPass = 0
            position = 0
        }
        return pending[position]
    }

    /// Records the outcome of creating the view returned by `next`.
    ///
    /// - Parameters:
    ///   - view: The view that was attempted.
    ///   - created: Whether the server created it.
    ///   - reason: Why it was not created.
    @objc(recordView:created:reason:)
    public func record(_ view: String, created: Bool, reason: String?) {
        position += 1
        if created {
            createdThisPass += 1
        } else {
            failedThisPass.append((view, reason))
        }
    }
}

/// The outcome of running one statement for `SADatabaseRenameExecutor`.
@objc public final class SADatabaseRenameStatementResult: NSObject {

    /// The result rows, or `nil` when the statement failed.
    @objc public let rows: [[Any]]?
    /// The server's message when the statement failed.
    @objc public let error: String?

    /// A successful statement with its rows (empty for statements without a result).
    @objc(initWithRows:)
    public init(rows: [[Any]]) {
        self.rows = rows
        error = nil
    }

    /// A failed statement.
    @objc(initWithError:)
    public init(error: String?) {
        rows = nil
        self.error = error ?? SADatabaseRenamePlan.unknownReason
    }
}

/// Runs "Rename Database" from the inspection of the source to the drop of
/// its emptied remains, issuing every statement through one closure so the
/// whole workflow is testable without a server. The decisions are the
/// plan's; this type only sequences the statements.
@objc public final class SADatabaseRenameExecutor: NSObject {

    public typealias Run = (String) -> SADatabaseRenameStatementResult
    public typealias Quote = (String) -> String

    private let run: Run
    private let quote: Quote

    /// Whether the last rename changed anything on the server: the target
    /// database exists, and tables or views may have moved into it. The
    /// caller refreshes what it shows when a rename stopped after this point.
    @objc public private(set) var changedServer = false

    /// Creates an executor. The connection is expected to transport
    /// statements and results in UTF-8 (`SPDatabaseRename` switches it to
    /// utf8mb4 for the duration of the rename), so that view definitions
    /// travel without loss.
    ///
    /// - Parameters:
    ///   - run: Runs one statement on the connection.
    ///   - quote: Turns a value into a quoted SQL string literal, escaped for
    ///     the connection.
    @objc(initWithRun:quote:)
    public init(run: @escaping Run, quote: @escaping Quote) {
        self.run = run
        self.quote = quote
    }

    /// Renames `source` to `target`.
    ///
    /// When the source holds views, the connection's default database is the
    /// target while they are recreated and, after a successful rename, stays
    /// there for the caller to select the renamed database; whenever the
    /// source survives, the default database is switched back to it.
    ///
    /// - Parameters:
    ///   - source: The database to rename.
    ///   - target: Its new name; the database must not exist yet.
    ///   - encoding: The default character set for the new database, if any.
    ///   - collation: The default collation for the new database, if any.
    /// - Returns: `nil` on success, otherwise the explanation for the user.
    @objc(renameDatabase:to:encoding:collation:)
    public func rename(_ source: String, to target: String, encoding: String?, collation: String?) -> String? {
        changedServer = false
        globalVisibility = nil
        partialRevokes = nil
        let quotedSource = SADatabaseRenameViewRewriter.backtickQuoted(source)
        let quotedTarget = SADatabaseRenameViewRewriter.backtickQuoted(target)
        let schema = quote(source)

        // The plan needs the source's objects from the server; a failed query
        // leaves the picture incomplete and stops the rename. Events are read
        // with SHOW EVENTS, which fails without the EVENT privilege where
        // information_schema.EVENTS would quietly list nothing. SHOW EVENTS
        // goes through the server's routine cache, which a MariaDB data
        // directory that was never run through mysql_upgrade refuses
        // ("Column count of mysql.event is wrong"); the underlying table still
        // lists the events, so it is read directly then.
        var inspectionError: String?
        func rows(_ statement: String, fallback: String? = nil) -> [[Any]] {
            guard inspectionError == nil else { return [] }
            let result = run(statement)
            if let rows = result.rows {
                return rows
            }
            if let fallback, let rows = run(fallback).rows {
                return rows
            }
            inspectionError = result.error
            return []
        }
        let tableRows = rows("SELECT TABLE_NAME, TABLE_TYPE FROM information_schema.TABLES WHERE TABLE_SCHEMA = \(schema) ORDER BY TABLE_NAME")
        // Read first: where the server folds the case of names (1 or 2), it
        // stores them folded in mysql.proc and mysql.event and prints them
        // folded, so the queries below must fold too - and the server's own
        // folded forms of source and target are the reference for that,
        // since the server also folds letters beyond ASCII.
        let lowerCaseTableNames = Int(Self.text(rows("SELECT @@lower_case_table_names").first?.first) ?? "") ?? 0
        let caseInsensitiveNames = lowerCaseTableNames != 0
        var serverLoweredSource: String?
        var serverLoweredTarget: String?
        if caseInsensitiveNames, inspectionError == nil, let lowered = run("SELECT LOWER(\(schema)), LOWER(\(quote(target)))").rows?.first, lowered.count >= 2 {
            serverLoweredSource = Self.text(lowered[0])
            serverLoweredTarget = Self.text(lowered[1])
        }
        let routineRows = routineRowsForInspection(schema: schema, caseInsensitiveNames: caseInsensitiveNames, inspectionError: &inspectionError)
        // both forms list the database first and the event's name second
        let eventRows = rows(
            "SHOW EVENTS FROM \(quotedSource)",
            fallback: "SELECT db, name FROM mysql.event WHERE \(Self.schemaMatch(column: "db", schema: schema, caseInsensitiveNames: caseInsensitiveNames)) ORDER BY name"
        ).map { Array($0.dropFirst()) }
        let triggerRows = rows("SELECT TRIGGER_NAME, EVENT_OBJECT_TABLE FROM information_schema.TRIGGERS WHERE TRIGGER_SCHEMA = \(schema) ORDER BY TRIGGER_NAME")
        let objectPrivileges = objectPrivilegeDescriptions(source: source, serverLoweredSource: serverLoweredSource, caseInsensitiveNames: caseInsensitiveNames, inspectionError: &inspectionError)
        let viewRows = rows("SELECT TABLE_NAME, CHARACTER_SET_CLIENT, HEX(VIEW_DEFINITION) FROM information_schema.VIEWS WHERE TABLE_SCHEMA = \(schema) ORDER BY TABLE_NAME")

        let plan = SADatabaseRenamePlan(sourceDatabase: source, targetDatabase: target, lowerCaseTableNames: lowerCaseTableNames, tableRows: tableRows, routineRows: routineRows, eventRows: eventRows, triggerRows: triggerRows)
        if let inspectionError {
            plan.recordInspectionFailure(inspectionError)
        }
        plan.recordObjectPrivileges(objectPrivileges)
        // A view's definition travels through the connection's UTF-8
        // transport, in and out, so it must be UTF-8 to arrive unchanged:
        // the view must have been written through UTF-8 (the client's
        // conversions into other character sets are not byte-compatible with
        // the server's), and the bytes the server holds - seen here in hex,
        // which travels as ASCII - must decode as UTF-8, which a `_binary`
        // literal need not. Either refuses the rename before anything moves.
        for row in viewRows {
            guard row.count >= 3, let view = Self.text(row[0]), let characterSet = Self.text(row[1]) else { continue }
            if !Self.isUTF8(characterSet) {
                plan.recordUnsupportedCharacterSet(characterSet, ofView: view)
                break
            }
            guard let hex = Self.text(row[2]), let bytes = Self.bytes(fromHex: hex), String(bytes: bytes, encoding: .utf8) != nil else {
                plan.recordUnsupportedDefinition(ofView: view)
                break
            }
        }
        guard plan.canStart else {
            return plan.failureDescription
        }

        var create = "CREATE DATABASE \(quotedTarget)"
        if let encoding, !encoding.isEmpty {
            create += " DEFAULT CHARACTER SET = \(SADatabaseRenameViewRewriter.backtickQuoted(encoding))"
        }
        if let collation, !collation.isEmpty {
            create += " DEFAULT COLLATE = \(SADatabaseRenameViewRewriter.backtickQuoted(collation))"
        }

        // Everything the views need is read before anything moves: the
        // session's settings and every definition, already rewritten for the
        // target. The session's sql_mode and identifier quoting are switched
        // for the reading and the replaying (ANSI_QUOTES would print
        // double-quoted identifiers, NO_BACKSLASH_ESCAPES would misread the
        // printed escapes; without quoting SHOW CREATE VIEW prints bare
        // names) and restored on every way out. The definitions are kept by
        // the bytes of the view's name: the server keeps names apart that
        // Swift's String would fold (NFC and NFD `café`).
        var settings: [(set: String, restore: String)] = []
        // the session's collation, once a view has been created under another
        var collationToRestore: String?
        func restoreSettings() {
            let restores = settings.map(\.restore) + (collationToRestore.map { ["collation_connection = \(quote($0))"] } ?? [])
            if !restores.isEmpty {
                _ = run("SET " + restores.joined(separator: ", "))
            }
        }
        var session: SessionSettings?
        var definitions: [[UInt8]: ViewDefinition] = [:]
        let rewriter = SADatabaseRenameViewRewriter(sourceDatabase: source, targetDatabase: target, caseInsensitiveNames: plan.caseInsensitiveNames, serverLoweredSource: serverLoweredSource)
        if !plan.views.isEmpty {
            let sessionResult = run("SELECT @@sql_mode, @@collation_connection, @@sql_quote_show_create, CONNECTION_ID()")
            guard let current = SessionSettings(row: sessionResult.rows?.first) else {
                plan.recordInspectionFailure(sessionResult.error)
                return plan.failureDescription
            }
            session = current
            let mode = Self.sqlMode(forViewDefinitions: current.sqlMode)
            if mode != current.sqlMode {
                settings.append(("sql_mode = \(quote(mode))", "sql_mode = \(quote(current.sqlMode))"))
            }
            if current.quoteShowCreate != "1" {
                settings.append(("sql_quote_show_create = 1", "sql_quote_show_create = 0"))
            }
            if !settings.isEmpty, let error = run("SET " + settings.map(\.set).joined(separator: ", ")).error {
                // the server applies the assignments in order, so the ones before the failing one are in place
                restoreSettings()
                plan.recordInspectionFailure(error)
                return plan.failureDescription
            }
            for view in plan.views {
                let shown = run("SHOW CREATE VIEW \(quotedSource).\(SADatabaseRenameViewRewriter.backtickQuoted(view))")
                if let error = shown.error {
                    restoreSettings()
                    plan.recordInspectionFailure(error)
                    return plan.failureDescription
                }
                // A literal printed with an introducer other than UTF-8
                // (`_latin1'…'`, `_binary'…'`) holds bytes that arrived here
                // through a lossy fallback and would go back changed.
                let row = shown.rows?.first ?? []
                guard row.count > 1, let statement = Self.text(row[1]), !SADatabaseRenameViewRewriter.hasLiteralOutsideUTF8(statement) else {
                    restoreSettings()
                    plan.recordUnsupportedDefinition(ofView: view)
                    return plan.failureDescription
                }
                let rewrite = rewriter.rewriteCreateStatement(statement, forView: view)
                guard let rewritten = rewrite.statement else {
                    restoreSettings()
                    plan.recordInspectionFailure(rewrite.failureReason)
                    return plan.failureDescription
                }
                definitions[Array(view.utf8)] = ViewDefinition(statement: rewritten, references: rewrite.referencedObjects, collation: row.count > 3 ? Self.text(row[3]) : nil)
            }
        }

        if let error = run(create).error {
            restoreSettings()
            plan.recordCreateFailure(error)
            return plan.failureDescription
        }
        changedServer = true

        for table in plan.tables {
            let quotedTable = SADatabaseRenameViewRewriter.backtickQuoted(table)
            let result = run("RENAME TABLE \(quotedSource).\(quotedTable) TO \(quotedTarget).\(quotedTable)")
            guard plan.recordMove(of: table, kind: .table, succeeded: result.error == nil, reason: result.error) else {
                restoreSettings()
                return plan.failureDescription
            }
        }

        // The connection's default database becomes the target while the
        // views are recreated (see below) and is switched back whenever the
        // source survives; after a successful rename the caller selects the
        // renamed database itself.
        var defaultDatabaseSwitched = false
        func restoreDefaultDatabase() {
            if defaultDatabaseSwitched {
                _ = run("USE \(quotedSource)")
            }
        }

        if let session {
            // a view is created after the views it selects from; the queue
            // still retries for a dependency the rewriter could not see
            let queue = SADatabaseRenameViewQueue(views: Self.orderedByReferences(plan.views, definitions: definitions, caseInsensitiveNames: plan.caseInsensitiveNames))

            // MariaDB prints references to the view's own database without
            // the database name when that database is the connection's
            // default - and the renamed database is the selected one. With
            // the target as the default such names resolve to the moved objects.
            if let error = run("USE \(quotedTarget)").error {
                restoreSettings()
                _ = plan.recordMove(of: plan.views[0], kind: .view, succeeded: false, reason: error)
                return plan.failureDescription
            }
            defaultDatabaseSwitched = true

            // each view sets the collation it needs; the session's comes
            // back once, with the other settings, after the last one
            collationToRestore = session.collation
            while let view = queue.next {
                let outcome = recreate(view, definition: definitions[Array(view.utf8)], quotedTarget: quotedTarget, session: session)
                queue.record(view, created: outcome == nil, reason: outcome)
            }
            restoreSettings()
            if let stuckView = queue.stuckView {
                restoreDefaultDatabase()
                _ = plan.recordMove(of: stuckView, kind: .view, succeeded: false, reason: queue.stuckReason)
                return plan.failureDescription
            }

            // The session is checked before the source may be dropped. A
            // connection that was re-established meanwhile is another
            // server session: the framework brings it back on its own idea
            // of the default database and with the server's default
            // sql_mode, so a view may have been created against the source
            // or under another sql_mode or collation - and since the
            // framework re-selects the database and the restore above
            // resets the settings, neither would show; CONNECTION_ID() does.
            // A restore that did not take (the server refused it, say) would
            // leave the session as the views needed it. Either way the
            // source stays. The name comes back the way the server keeps
            // it: lowercased where it folds case (lower_case_table_names =
            // 1), as given otherwise.
            let check = run("SELECT DATABASE(), @@sql_mode, @@collation_connection, CONNECTION_ID()").rows?.first ?? []
            let selected = check.count >= 4 ? Self.text(check[0]) ?? "" : ""
            let targetSelected = selected.utf8.elementsEqual(target.utf8)
                || (plan.caseInsensitiveNames && serverLoweredTarget != nil && selected.utf8.elementsEqual(serverLoweredTarget!.utf8))
                || (plan.caseInsensitiveNames && SADatabaseRenameViewRewriter.asciiLowercased(Array(selected.utf8)) == SADatabaseRenameViewRewriter.asciiLowercased(Array(target.utf8)))
            let sessionIntact = check.count >= 4 && targetSelected
                && Self.text(check[1]) == session.sqlMode && Self.text(check[2]) == session.collation
                && Self.text(check[3]) == session.connectionID
            if !sessionIntact {
                restoreDefaultDatabase()
                _ = plan.recordMove(of: plan.views[plan.views.count - 1], kind: .view, succeeded: false, reason: NSLocalizedString("the connection was re-established while the views were recreated, so they may still point at the old database.", comment: "rename database: why the views are not trusted and the source is kept"))
                return plan.failureDescription
            }
        }

        guard plan.mayDropSourceDatabase else {
            restoreDefaultDatabase()
            return plan.failureDescription
        }
        if let error = run("DROP DATABASE \(quotedSource)").error {
            plan.recordDropFailure(error)
            restoreDefaultDatabase()
        }
        return plan.failureDescription
    }

    /// The routines of the source database as `name, type` rows, or an empty
    /// list with `inspectionError` set when they cannot be listed completely.
    ///
    /// `information_schema.ROUTINES` quietly leaves out every routine the
    /// account has no privilege on, and a routine the plan never sees is
    /// dropped with the source. So the table behind it, `mysql.proc`, is
    /// read first: it lists everything, where it exists (MariaDB, MySQL up to
    /// 5.7 - even a data directory never run through mysql_upgrade) and is
    /// readable. Where it is not, `information_schema.ROUTINES` is trusted
    /// only for an account whose global privileges provably cover every
    /// routine: SHOW_ROUTINE (a dynamic privilege, which cannot be partially
    /// revoked) or SELECT - the latter not on a MySQL 8 with partial revokes
    /// on, where a global SELECT may exclude this very database while
    /// USER_PRIVILEGES still lists it. Schema-level grants are not consulted
    /// at all: an exact grant shadows a matching wildcard grant, and neither
    /// says which routines the server shows. Privileges that come through a
    /// role are not seen here either. Anything else fails closed.
    private func routineRowsForInspection(schema: String, caseInsensitiveNames: Bool, inspectionError: inout String?) -> [[Any]] {
        guard inspectionError == nil else { return [] }
        if let rows = run("SELECT name, type FROM mysql.proc WHERE \(Self.schemaMatch(column: "db", schema: schema, caseInsensitiveNames: caseInsensitiveNames)) ORDER BY name").rows {
            return rows
        }
        let visibility = globalVisibilityForInspection()
        if !visibility.privileges.contains("SHOW_ROUTINE"),
           let reason = Self.reasonGlobalSelectDoesNotCoverEverything(visibility, otherwise: NSLocalizedString("this account cannot list the database's routines completely (it needs SELECT on mysql.proc, or global SELECT or SHOW_ROUTINE).", comment: "rename database: why the source could not be inspected; shown after 'Reading the objects of the database … failed:'")) {
            inspectionError = reason
            return []
        }
        let routines = run("SELECT ROUTINE_NAME, ROUTINE_TYPE FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA = \(schema) ORDER BY ROUTINE_NAME")
        guard let rows = routines.rows else {
            inspectionError = routines.error
            return []
        }
        return rows
    }

    /// The privileges granted on the source database, its tables and views,
    /// and the partial revokes for the database, each as `` `pattern`.* for
    /// 'user'@'host' ``, `` `table` for 'user'@'host' `` or `` partial revoke
    /// on `db`.* for 'user'@'host' ``, or an empty list with
    /// `inspectionError` set when they cannot be listed completely.
    ///
    /// A grant on the database stays with the old name, `RENAME TABLE` does
    /// not carry grants on tables across databases and a recreated view has
    /// none, so a database holding any is refused. They are read from
    /// `mysql.db`, `mysql.tables_priv` and `mysql.columns_priv`, which list
    /// every grant where readable; otherwise `information_schema`'s
    /// `SCHEMA_PRIVILEGES`, `TABLE_PRIVILEGES` and `COLUMN_PRIVILEGES` stand
    /// in, which show every account's grants only to a global SELECT that no
    /// partial revoke limits. Anything else fails closed. A grant on a
    /// database names a pattern (`shop%` covers `shop`), so the source is
    /// matched against it with `LIKE`, the way the server does - exactly
    /// where partial revokes are on, since the server reads the grant
    /// literally then.
    ///
    /// A partial revoke (MySQL 8 with `partial_revokes` on: `REVOKE SELECT
    /// ON shop.*` from an account holding a global SELECT) is the reverse
    /// case: the restriction stays with the old name and the global
    /// privilege then covers the renamed database. Restrictions live in the
    /// JSON of `mysql.user.User_attributes` only - no `information_schema`
    /// view shows them - so that is searched for the source's name, as
    /// given and as the server folds it. A server without partial revokes
    /// has none; one whose setting or `mysql.user` cannot be read fails
    /// closed.
    private func objectPrivilegeDescriptions(source: String, serverLoweredSource: String?, caseInsensitiveNames: Bool, inspectionError: inout String?) -> [String] {
        guard inspectionError == nil else { return [] }
        let unlistable = NSLocalizedString("this account cannot list the privileges granted on the database, its tables and views (it needs SELECT on mysql.db, mysql.tables_priv and mysql.user, or global SELECT).", comment: "rename database: why the source could not be inspected; shown after 'Reading the objects of the database … failed:'")
        let schema = quote(source)
        // with partial revokes on, `_` and `%` in a database grant are
        // literal characters, not wildcards; the setting, read once, is
        // needed for the restrictions below anyway
        let literalGrants: Bool
        if case .on = partialRevokesForInspection() {
            literalGrants = true
        } else {
            literalGrants = false
        }
        let databaseMatch = databaseGrantMatch(column: "Db", schema: schema, caseInsensitiveNames: caseInsensitiveNames, literal: literalGrants)
        let match = Self.schemaMatch(column: "Db", schema: schema, caseInsensitiveNames: caseInsensitiveNames)
        let databases = run("SELECT Db, User, Host FROM mysql.db WHERE \(databaseMatch) ORDER BY Db, User, Host")
        let tables = run("SELECT Table_name, User, Host FROM mysql.tables_priv WHERE \(match) ORDER BY Table_name, User, Host")
        let columns = run("SELECT Table_name, User, Host FROM mysql.columns_priv WHERE \(match) ORDER BY Table_name, User, Host")
        if let databaseRows = databases.rows, let tableRows = tables.rows, let columnRows = columns.rows {
            let onDatabase = Self.grantDescriptions(databaseRows) { row in
                guard row.count >= 3, let pattern = Self.text(row[0]), let user = Self.text(row[1]), let host = Self.text(row[2]) else { return nil }
                return Self.databaseGrantDescription(pattern: pattern, grantee: "'\(user)'@'\(host)'")
            }
            let onObjects = Self.grantDescriptions(tableRows + columnRows) { row in
                guard row.count >= 3, let table = Self.text(row[0]), let user = Self.text(row[1]), let host = Self.text(row[2]) else { return nil }
                return Self.objectGrantDescription(object: table, grantee: "'\(user)'@'\(host)'")
            }
            var restrictions: [String] = []
            switch partialRevokesForInspection() {
            case .off:
                break
            case .unknown(let error):
                inspectionError = error
                return []
            case .on:
                // JSON_SEARCH compares exactly, so both forms of the name are
                // searched where the server folds case; its search string is
                // a LIKE pattern, hence the escaping
                var names = [source]
                if let serverLoweredSource, !serverLoweredSource.utf8.elementsEqual(source.utf8) {
                    names.append(serverLoweredSource)
                }
                let restrictionMatch = names
                    .map { "JSON_SEARCH(User_attributes, 'one', \(quote(Self.likePattern(matchingExactly: $0))), '!', '$.Restrictions[*].Database') IS NOT NULL" }
                    .joined(separator: " OR ")
                guard let restrictedRows = run("SELECT User, Host FROM mysql.user WHERE \(restrictionMatch) ORDER BY User, Host").rows else {
                    inspectionError = unlistable
                    return []
                }
                restrictions = Self.grantDescriptions(restrictedRows) { row in
                    guard row.count >= 2, let user = Self.text(row[0]), let host = Self.text(row[1]) else { return nil }
                    return Self.restrictionDescription(database: source, grantee: "'\(user)'@'\(host)'")
                }
            }
            return onDatabase + onObjects + restrictions
        }
        if let reason = Self.reasonGlobalSelectDoesNotCoverEverything(globalVisibilityForInspection(), otherwise: unlistable) {
            inspectionError = reason
            return []
        }
        let schemaGrantMatch = databaseGrantMatch(column: "TABLE_SCHEMA", schema: schema, caseInsensitiveNames: caseInsensitiveNames, literal: literalGrants)
        let schemas = run("SELECT TABLE_SCHEMA, GRANTEE FROM information_schema.SCHEMA_PRIVILEGES WHERE \(schemaGrantMatch) ORDER BY TABLE_SCHEMA, GRANTEE")
        guard let schemaRows = schemas.rows else {
            inspectionError = schemas.error
            return []
        }
        let schemaMatch = Self.schemaMatch(column: "TABLE_SCHEMA", schema: schema, caseInsensitiveNames: caseInsensitiveNames)
        var rows: [[Any]] = []
        for view in ["TABLE_PRIVILEGES", "COLUMN_PRIVILEGES"] {
            let result = run("SELECT TABLE_NAME, GRANTEE FROM information_schema.\(view) WHERE \(schemaMatch) ORDER BY TABLE_NAME, GRANTEE")
            guard let found = result.rows else {
                inspectionError = result.error
                return []
            }
            rows += found
        }
        let onDatabase = Self.grantDescriptions(schemaRows) { row in
            guard row.count >= 2, let pattern = Self.text(row[0]), let grantee = Self.text(row[1]) else { return nil }
            return Self.databaseGrantDescription(pattern: pattern, grantee: grantee)
        }
        return onDatabase + Self.grantDescriptions(rows) { row in
            guard row.count >= 2, let table = Self.text(row[0]), let grantee = Self.text(row[1]) else { return nil }
            return Self.objectGrantDescription(object: table, grantee: grantee)
        }
    }

    /// The distinct descriptions of grant rows, in the order they were listed.
    private static func grantDescriptions(_ rows: [[Any]], describe: ([Any]) -> String?) -> [String] {
        var seen: Set<[UInt8]> = []
        return rows.compactMap(describe).filter { seen.insert(Array($0.utf8)).inserted }
    }

    /// One grant on a database, for the refusal: `pattern` is the grant's
    /// database pattern, `grantee` the account as `'user'@'host'`.
    private static func databaseGrantDescription(pattern: String, grantee: String) -> String {
        String(format: NSLocalizedString("`%@`.* for %@", comment: "rename database: one privilege granted on a database, listed in the refusal; %1$@ the grant's database pattern, %2$@ the account as 'user'@'host'"), pattern, grantee)
    }

    /// One grant on a table, view or column, for the refusal: `object` is
    /// the table or view, `grantee` the account as `'user'@'host'`.
    private static func objectGrantDescription(object: String, grantee: String) -> String {
        String(format: NSLocalizedString("`%@` for %@", comment: "rename database: one privilege granted on a table, view or column, listed in the refusal; %1$@ the table or view, %2$@ the account as 'user'@'host'"), object, grantee)
    }

    /// One partial revoke for the database, for the refusal: `grantee` is
    /// the restricted account as `'user'@'host'`.
    private static func restrictionDescription(database: String, grantee: String) -> String {
        String(format: NSLocalizedString("partial revoke on `%@`.* for %@", comment: "rename database: one partial revoke restricting an account for the database, listed in the refusal; %1$@ the database, %2$@ the account as 'user'@'host'"), database, grantee)
    }

    /// `name` as a `LIKE` pattern that matches exactly that name, with `!`
    /// as the escape character: `%`, `_` and `!` in the name are escaped.
    static func likePattern(matchingExactly name: String) -> String {
        var pattern = ""
        for scalar in name.unicodeScalars {
            if scalar == "%" || scalar == "_" || scalar == "!" {
                pattern.unicodeScalars.append("!")
            }
            pattern.unicodeScalars.append(scalar)
        }
        return pattern
    }

    /// The account's global privileges that decide what `information_schema`
    /// shows of other accounts' objects, with the server's partial-revoke
    /// setting, read once per rename.
    private struct GlobalVisibility {
        enum PartialRevokes {
            case off
            case on
            /// the setting could not be read; the server's message
            case unknown(String)
        }
        let privileges: Set<String>
        let partialRevokes: PartialRevokes
    }

    private var globalVisibility: GlobalVisibility?

    private func globalVisibilityForInspection() -> GlobalVisibility {
        if let globalVisibility {
            return globalVisibility
        }
        // the account as the privilege tables spell it, 'user'@'host'; the
        // user name may itself contain '@', the host follows the last one
        let host = "SUBSTRING_INDEX(CURRENT_USER(), '@', -1)"
        let user = "SUBSTRING(CURRENT_USER(), 1, CHAR_LENGTH(CURRENT_USER()) - CHAR_LENGTH(\(host)) - 1)"
        let grantee = "CONCAT('''', \(user), '''@''', \(host), '''')"
        let privileges = Set((run("SELECT PRIVILEGE_TYPE FROM information_schema.USER_PRIVILEGES WHERE GRANTEE = \(grantee) AND PRIVILEGE_TYPE IN ('SELECT', 'SHOW_ROUTINE')").rows ?? [])
            .compactMap { Self.text($0.first)?.uppercased() })
        let visibility = GlobalVisibility(privileges: privileges, partialRevokes: partialRevokesForInspection())
        globalVisibility = visibility
        return visibility
    }

    private var partialRevokes: GlobalVisibility.PartialRevokes?

    /// The server's partial-revoke setting, read once per rename. A server
    /// that does not know the variable (MariaDB, MySQL up to 5.7) has no
    /// partial revokes; a failure leaves the setting unknown, and neither a
    /// global SELECT nor the absence of restrictions can be trusted then.
    private func partialRevokesForInspection() -> GlobalVisibility.PartialRevokes {
        if let partialRevokes {
            return partialRevokes
        }
        // SHOW VARIABLES lists nothing for a variable the server does not
        // know, where `SELECT @@partial_revokes` would fail with a message
        // in the server's language - error texts are localised
        let revokes = run("SHOW VARIABLES LIKE 'partial_revokes'")
        let setting: GlobalVisibility.PartialRevokes
        if let error = revokes.error {
            setting = .unknown(error)
        } else {
            let row = revokes.rows?.first ?? []
            let value = row.count >= 2 ? Self.text(row[1])?.uppercased() : nil
            setting = (value == "ON" || value == "1") ? .on : .off
        }
        partialRevokes = setting
        return setting
    }

    /// Why a global SELECT does not let the account see every row of an
    /// `information_schema` privilege view - `reason` when it is missing or
    /// partial revokes may limit it, the server's message when that could
    /// not be read - or `nil` when it does.
    private static func reasonGlobalSelectDoesNotCoverEverything(_ visibility: GlobalVisibility, otherwise reason: String) -> String? {
        guard visibility.privileges.contains("SELECT") else { return reason }
        switch visibility.partialRevokes {
        case .off:
            return nil
        case .on:
            return reason
        case .unknown(let error):
            return error
        }
    }

    /// The condition matching a schema-name column of the `mysql` tables
    /// against the source. With `lower_case_table_names` 1 or 2 the server
    /// stores database names folded to lower case in those binary-collated
    /// columns, so an exact comparison would find nothing - and routines or
    /// events it did not find would be dropped with the source; the server
    /// folds both sides then.
    private static func schemaMatch(column: String, schema: String, caseInsensitiveNames: Bool) -> String {
        caseInsensitiveNames ? "LOWER(\(column)) = LOWER(\(schema))" : "\(column) = \(schema)"
    }

    /// The condition under which a database grant in a schema-name column
    /// (`mysql.db`, `SCHEMA_PRIVILEGES`) covers the source. A grant names a
    /// `LIKE` pattern, so the source is the value and the column the
    /// pattern, as the server applies such grants; both are folded where
    /// the server folds the case of names. Grant patterns escape a literal
    /// `_` or `%` with a backslash, and `LIKE` has no default escape
    /// character under `NO_BACKSLASH_ESCAPES`, so the backslash is named -
    /// quoted by the connection, which knows the mode (`'\\'`, or `'\'`
    /// under that mode). With partial revokes on the server reads `_` and
    /// `%` in database grants literally; `literal` compares for equality
    /// then.
    private func databaseGrantMatch(column: String, schema: String, caseInsensitiveNames: Bool, literal: Bool) -> String {
        if literal {
            return Self.schemaMatch(column: column, schema: schema, caseInsensitiveNames: caseInsensitiveNames)
        }
        let escape = "ESCAPE \(quote("\\"))"
        return caseInsensitiveNames ? "LOWER(\(schema)) LIKE LOWER(\(column)) \(escape)" : "\(schema) LIKE \(column) \(escape)"
    }

    /// One view's definition, rewritten for the target, with the source
    /// objects it reads from and the collation it was created under.
    private struct ViewDefinition {
        let statement: String
        let references: [String]
        let collation: String?
    }

    /// The views in an order that creates every view after the views it
    /// selects from, keeping `information_schema`'s order otherwise. Every
    /// view is kept by the exact bytes of its name, so no entry of the
    /// inventory can vanish behind another; only the lookup of a reference
    /// folds ASCII case where the server folds the case of names, and an
    /// exact match wins. A reference that names no view, or that closes a
    /// cycle, is left to the queue's retry.
    private static func orderedByReferences(_ views: [String], definitions: [[UInt8]: ViewDefinition], caseInsensitiveNames: Bool) -> [String] {
        let exact = Dictionary(views.map { (Array($0.utf8), $0) }, uniquingKeysWith: { first, _ in first })
        let folded = caseInsensitiveNames
            ? Dictionary(views.map { (SADatabaseRenameViewRewriter.asciiLowercased(Array($0.utf8)), $0) }, uniquingKeysWith: { first, _ in first })
            : [:]
        func referencedView(_ reference: String) -> String? {
            let bytes = Array(reference.utf8)
            return exact[bytes] ?? folded[SADatabaseRenameViewRewriter.asciiLowercased(bytes)]
        }

        var ordered: [String] = []
        var done: Set<[UInt8]> = []
        var visiting: Set<[UInt8]> = []

        func visit(_ view: String) {
            let viewKey = Array(view.utf8)
            guard !done.contains(viewKey), !visiting.contains(viewKey) else { return }
            visiting.insert(viewKey)
            for reference in definitions[viewKey]?.references ?? [] {
                if let referenced = referencedView(reference) {
                    visit(referenced)
                }
            }
            visiting.remove(viewKey)
            done.insert(viewKey)
            ordered.append(view)
        }

        for view in views {
            visit(view)
        }
        return ordered
    }

    /// The text of a result value: a string as it is, a number as the server
    /// prints it, bytes only when they are UTF-8.
    static func text(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            return string
        case let data as Data:
            return String(data: data, encoding: .utf8)
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
    }

    /// The session variables that decide how the server prints and reads a
    /// view definition, as they were before the views are recreated, and
    /// the server's id of the session they were read on.
    private struct SessionSettings {
        let sqlMode: String
        let collation: String
        let quoteShowCreate: String
        /// `CONNECTION_ID()`: another value later means a re-established connection
        let connectionID: String

        /// Fails unless the row holds all four values.
        init?(row: [Any]?) {
            guard let row, row.count >= 4,
                  let sqlMode = SADatabaseRenameExecutor.text(row[0]), let collation = SADatabaseRenameExecutor.text(row[1]),
                  let quoteShowCreate = SADatabaseRenameExecutor.text(row[2]), let connectionID = SADatabaseRenameExecutor.text(row[3]) else {
                return nil
            }
            self.sqlMode = sqlMode
            self.collation = collation
            self.quoteShowCreate = quoteShowCreate
            self.connectionID = connectionID
        }
    }

    /// The bytes a hex string (as `HEX()` prints them) stands for, or `nil`
    /// when it is not one.
    static func bytes(fromHex hex: String) -> [UInt8]? {
        let digits = Array(hex.utf8)
        guard digits.count % 2 == 0 else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(digits.count / 2)
        var index = 0
        while index < digits.count {
            guard let high = Self.nibble(digits[index]), let low = Self.nibble(digits[index + 1]) else { return nil }
            bytes.append(high << 4 | low)
            index += 2
        }
        return bytes
    }

    private static func nibble(_ digit: UInt8) -> UInt8? {
        switch digit {
        case 0x30...0x39: return digit - 0x30
        case 0x41...0x46: return digit - 0x41 + 10
        case 0x61...0x66: return digit - 0x61 + 10
        default: return nil
        }
    }

    /// Whether a MySQL character set is one of the UTF-8 encodings, which
    /// the connection's UTF-8 transport carries without conversion.
    static func isUTF8(_ characterSet: String) -> Bool {
        ["utf8", "utf8mb3", "utf8mb4"].contains(characterSet.lowercased())
    }

    /// SQL modes that change how a statement is parsed. `SHOW CREATE VIEW`
    /// prints the definition in the server's canonical syntax (backslash
    /// escapes, single-quoted strings, backticked identifiers), which the
    /// server itself parses with the first four switched off when it opens a
    /// view; the compound modes expand to them, and MariaDB's
    /// `EMPTY_STRING_IS_NULL` would turn a printed `''` into NULL.
    private static let parsingSQLModes: Set<String> = [
        "PIPES_AS_CONCAT", "ANSI_QUOTES", "IGNORE_SPACE", "NO_BACKSLASH_ESCAPES", "EMPTY_STRING_IS_NULL",
        "ANSI", "DB2", "MAXDB", "MSSQL", "ORACLE", "POSTGRESQL"
    ]

    /// The session's `sql_mode` without the modes that would misread a view
    /// definition printed by `SHOW CREATE VIEW`: under `NO_BACKSLASH_ESCAPES`
    /// a printed `'a\\b'` would become two backslashes, under `ANSI_QUOTES` a
    /// double-quoted string an identifier. Everything else stays, so the
    /// recreated view keeps the modes stored with it as close as possible.
    ///
    /// - Parameter mode: The value of `@@sql_mode`.
    /// - Returns: The mode to create views under.
    static func sqlMode(forViewDefinitions mode: String) -> String {
        mode.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !parsingSQLModes.contains($0.uppercased()) }
            .joined(separator: ",")
    }

    /// Recreates one view in the target from the definition read up front
    /// and returns why that failed, or `nil`.
    ///
    /// The definition goes back through the connection's UTF-8 transport
    /// without loss (its bytes were checked to be UTF-8, and views created
    /// through another character set were refused up front). The statement
    /// runs under the `collation_connection` the view was created with,
    /// which `SHOW CREATE VIEW` reports, so string comparisons in its
    /// definition keep their semantics. That collation is set before every
    /// view, the session's own included: what the connection is on after the
    /// view before is never assumed, and a `SET` the server refuses fails
    /// the view instead of leaving it under the previous one. The caller
    /// restores the session's collation once after the last view.
    /// `character_set_client` is left alone on purpose: it tells the server
    /// how to read the bytes the connection sends, and those are UTF-8.
    ///
    /// A created view is opened once before it counts: the server checks the
    /// creator's privileges when it runs `CREATE VIEW`, but the definer's -
    /// on the moved objects - when the view is opened, so a `SQL SECURITY
    /// DEFINER` view can be created and still be unusable. One that cannot
    /// be opened is dropped again and reported like a failed `CREATE`.
    private func recreate(_ view: String, definition: ViewDefinition?, quotedTarget: String, session: SessionSettings) -> String? {
        guard let definition else {
            return SADatabaseRenamePlan.unknownReason
        }

        if let error = run("SET collation_connection = \(quote(definition.collation ?? session.collation))").error {
            return error
        }
        if let error = run(definition.statement).error {
            return error
        }

        let qualifiedView = "\(quotedTarget).\(SADatabaseRenameViewRewriter.backtickQuoted(view))"
        if let error = run("SELECT 1 FROM \(qualifiedView) LIMIT 0").error {
            _ = run("DROP VIEW \(qualifiedView)")
            return error
        }
        return nil
    }
}
