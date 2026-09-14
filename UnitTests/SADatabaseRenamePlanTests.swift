//
//  SADatabaseRenamePlanTests.swift
//  Unit Tests
//
//  Created by Sequel-Ace contributors on 2026.09.14.
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import XCTest

final class SADatabaseRenamePlanTests: XCTestCase {

    private func makePlan(
        lowerCaseTableNames: Int = 0,
        tableRows: [[Any]] = [["orders", "BASE TABLE"], ["order_totals", "VIEW"]],
        routineRows: [[Any]] = [],
        eventRows: [[Any]] = [],
        triggerRows: [[Any]] = []
    ) -> SADatabaseRenamePlan {
        SADatabaseRenamePlan(sourceDatabase: "shop", targetDatabase: "store", lowerCaseTableNames: lowerCaseTableNames, tableRows: tableRows, routineRows: routineRows, eventRows: eventRows, triggerRows: triggerRows)
    }

    /// Verifies tables and views come from the information_schema rows as
    /// they are - every non-VIEW type is a table, malformed rows are dropped,
    /// and names the server keeps apart (NFC and NFD `café`) both stay.
    func testTablesAndViewsAreClassifiedFromInformationSchemaRows() {
        let nfc = "caf\u{00E9}"
        let nfd = "cafe\u{0301}"
        let plan = makePlan(tableRows: [
            ["orders", "BASE TABLE"], ["history", "SYSTEM VERSIONED"], [nfc, "BASE TABLE"], [nfd, "BASE TABLE"],
            ["totals", "view"], ["broken"], [NSNull(), "VIEW"]
        ])
        XCTAssertEqual(plan.tables.count, 4)
        XCTAssertEqual(plan.tables.prefix(2), ["orders", "history"])
        XCTAssertTrue(plan.tables[2].utf8.elementsEqual(nfc.utf8))
        XCTAssertTrue(plan.tables[3].utf8.elementsEqual(nfd.utf8))
        XCTAssertEqual(plan.views, ["totals"])
        XCTAssertTrue(plan.canStart)
        XCTAssertFalse(plan.caseInsensitiveNames)
        XCTAssertTrue(makePlan(lowerCaseTableNames: 2).caseInsensitiveNames)
    }

    /// Verifies a database without triggers, routines or events is renamed
    /// and, once every object moved, may be dropped.
    func testCompleteMoveAllowsDrop() {
        let plan = makePlan()
        XCTAssertTrue(plan.canStart)
        XCTAssertTrue(plan.recordMove(of: "orders", kind: .table, succeeded: true, reason: nil))
        XCTAssertTrue(plan.recordMove(of: "order_totals", kind: .view, succeeded: true, reason: nil))
        XCTAssertTrue(plan.mayDropSourceDatabase)
        XCTAssertNil(plan.failureDescription)
    }

    /// Verifies a failed move stops the rename and keeps the source database:
    /// dropping it would delete the objects that did not move.
    func testFailedMoveStopsTheRenameAndKeepsTheSource() throws {
        let plan = makePlan()
        XCTAssertTrue(plan.recordMove(of: "customers", kind: .table, succeeded: true, reason: nil))
        XCTAssertFalse(plan.recordMove(of: "orders", kind: .table, succeeded: false, reason: "Access denied"))
        XCTAssertFalse(plan.recordMove(of: "invoices", kind: .table, succeeded: true, reason: nil), "nothing more is moved after a failure")
        XCTAssertFalse(plan.mayDropSourceDatabase)

        let description = try XCTUnwrap(plan.failureDescription)
        XCTAssertTrue(description.contains("table 'orders'"), description)
        XCTAssertTrue(description.contains("Access denied"), description)
        XCTAssertTrue(description.contains("'store'"), description)
        XCTAssertTrue(description.contains("'shop' was not dropped"), description)
    }

    /// Verifies triggers (which block RENAME TABLE across databases), routines
    /// and events (which are never moved) refuse the rename before anything
    /// changes - they would otherwise vanish with the source.
    func testTriggersRoutinesAndEventsRefuseTheRename() throws {
        let plan = makePlan(
            routineRows: [["cleanup", "PROCEDURE"], ["tax", "FUNCTION"]],
            eventRows: [["nightly"]],
            triggerRows: [["orders_audit", "orders"]]
        )
        XCTAssertFalse(plan.canStart)
        XCTAssertFalse(plan.mayDropSourceDatabase)
        XCTAssertEqual(plan.unsupportedObjects, ["trigger 'orders_audit' on table 'orders'", "procedure 'cleanup'", "function 'tax'", "event 'nightly'"])

        let description = try XCTUnwrap(plan.failureDescription)
        XCTAssertTrue(description.contains("trigger 'orders_audit' on table 'orders', procedure 'cleanup', function 'tax', event 'nightly'"), description)
        XCTAssertTrue(description.contains("Nothing was changed"), description)
    }

    /// Verifies a failed information_schema query refuses the rename: without
    /// the full picture an object could be dropped unseen.
    func testInspectionFailureRefusesTheRename() throws {
        let plan = makePlan()
        plan.recordInspectionFailure("SELECT command denied")
        XCTAssertFalse(plan.canStart)
        XCTAssertFalse(plan.mayDropSourceDatabase)
        let description = try XCTUnwrap(plan.failureDescription)
        XCTAssertTrue(description.contains("'shop' failed: SELECT command denied"), description)
        XCTAssertTrue(description.contains("Nothing was changed"), description)
    }

    /// Verifies a view created through a character set other than UTF-8
    /// refuses the rename, naming the view and the character set.
    func testUnsupportedCharacterSetOrDefinitionRefusesTheRename() throws {
        let plan = makePlan()
        plan.recordUnsupportedCharacterSet("hp8", ofView: "order_totals")
        XCTAssertFalse(plan.canStart)
        XCTAssertFalse(plan.mayDropSourceDatabase)
        XCTAssertEqual(try XCTUnwrap(plan.failureDescription), "The view 'order_totals' was created through the character set 'hp8'; Rename Database can only recreate views created through UTF-8. Nothing was changed.")

        let definition = makePlan()
        definition.recordUnsupportedDefinition(ofView: "order_totals")
        XCTAssertFalse(definition.canStart)
        XCTAssertEqual(try XCTUnwrap(definition.failureDescription), "The definition of the view 'order_totals' holds a string outside UTF-8; Rename Database cannot recreate it faithfully. Nothing was changed.")
    }

    /// Verifies a failed CREATE DATABASE and a failed DROP DATABASE are
    /// reported with the server's message, and a missing message is not
    /// shown as an empty string.
    func testCreateAndDropFailuresAreReported() throws {
        let createFailed = makePlan()
        createFailed.recordCreateFailure("Access denied")
        XCTAssertFalse(createFailed.mayDropSourceDatabase)
        XCTAssertTrue(try XCTUnwrap(createFailed.failureDescription).contains("Creating the database 'store' failed: Access denied"))

        let dropFailed = makePlan()
        XCTAssertTrue(dropFailed.recordMove(of: "orders", kind: .table, succeeded: true, reason: nil))
        XCTAssertTrue(dropFailed.mayDropSourceDatabase)
        dropFailed.recordDropFailure(nil)
        let description = try XCTUnwrap(dropFailed.failureDescription)
        XCTAssertTrue(description.contains("dropping 'shop' failed: unknown error"), description)
    }

    /// Verifies a view that selects from a view listed after it is retried
    /// once the other view exists, and that the queue ends without a stuck view.
    func testViewQueueRetriesViewsThatDependOnLaterOnes() {
        let queue = SADatabaseRenameViewQueue(views: ["a_report", "z_base"])
        XCTAssertEqual(queue.next, "a_report")
        queue.record("a_report", created: false, reason: "Table 'store.z_base' doesn't exist")
        XCTAssertEqual(queue.next, "z_base")
        queue.record("z_base", created: true, reason: nil)
        XCTAssertEqual(queue.next, "a_report", "retried after the pass created something")
        queue.record("a_report", created: true, reason: nil)
        XCTAssertNil(queue.next)
        XCTAssertNil(queue.stuckView)
    }

    /// Verifies a pass without progress stops the queue and reports the first
    /// remaining failure with its reason.
    func testViewQueueReportsAViewThatKeepsFailing() {
        let queue = SADatabaseRenameViewQueue(views: ["v1", "v2"])
        XCTAssertEqual(queue.next, "v1")
        queue.record("v1", created: false, reason: "Access denied")
        XCTAssertEqual(queue.next, "v2")
        queue.record("v2", created: false, reason: "Access denied too")
        XCTAssertNil(queue.next)
        XCTAssertEqual(queue.stuckView, "v1")
        XCTAssertEqual(queue.stuckReason, "Access denied")
        XCTAssertNil(queue.next, "a stuck queue stays stuck")
    }
}

final class SADatabaseRenameViewRewriterTests: XCTestCase {

    private let rewriter = SADatabaseRenameViewRewriter(sourceDatabase: "shop", targetDatabase: "store", caseInsensitiveNames: false)

    private func rewrite(_ statement: String, view: String = "v", rewriter: SADatabaseRenameViewRewriter? = nil) -> String? {
        (rewriter ?? self.rewriter).rewriteCreateStatement(statement, forView: view).statement
    }

    /// Verifies only the view's own name, the database part of object
    /// references and of three-part column references change: a view named
    /// like its database keeps its name, as do its columns.
    func testRewritesViewClauseObjectReferencesAndThreePartColumns() {
        let statement = "CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `shop` AS select `shop`.`shop`.`shop` AS `shop`,`shop`.`t`.`id` AS `id` from (`shop`.`shop` join `shop`.`t`)"
        XCTAssertEqual(
            rewrite(statement, view: "shop"),
            "CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `store`.`shop` AS select `store`.`shop`.`shop` AS `shop`,`store`.`t`.`id` AS `id` from (`store`.`shop` join `store`.`t`)"
        )
        let escaped = SADatabaseRenameViewRewriter(sourceDatabase: "my`db", targetDatabase: "tgt", caseInsensitiveNames: false)
        XCTAssertEqual(
            rewrite("CREATE VIEW `v` AS select `my``db`.`t`.`a` AS `a` from `my``db`.`t`", rewriter: escaped),
            "CREATE VIEW `tgt`.`v` AS select `tgt`.`t`.`a` AS `a` from `tgt`.`t`"
        )
    }

    /// Verifies two-part column references are never touched, whether they
    /// go through a table alias named like the database or through a view
    /// named like it, while the object reference behind FROM is.
    func testLeavesAliasAndViewQualifiedColumnsAlone() {
        XCTAssertEqual(
            rewrite("CREATE VIEW `v` AS select `shop`.`id` AS `id` from `shop`.`t` `shop`"),
            "CREATE VIEW `store`.`v` AS select `shop`.`id` AS `id` from `store`.`t` `shop`"
        )
        XCTAssertEqual(
            rewrite("CREATE VIEW `v` AS select `shop`.`id` AS `id` from `shop`.`shop`"),
            "CREATE VIEW `store`.`v` AS select `shop`.`id` AS `id` from `store`.`shop`"
        )
        XCTAssertEqual(
            rewrite("CREATE VIEW `v` AS select `x`.`c` AS `shop` from `shop`.`t` `x`"),
            "CREATE VIEW `store`.`v` AS select `x`.`c` AS `shop` from `store`.`t` `x`"
        )
    }

    /// Verifies the clause structure is followed through joins, ON, WHERE and
    /// nested subqueries: object references after FROM/JOIN and in a scalar
    /// subquery are rewritten, column references and aliases are not.
    func testFollowsJoinsConditionsAndSubqueries() {
        XCTAssertEqual(
            rewrite("CREATE VIEW `v` AS select `x`.`id` AS `id`,`shop`.`b`.`n` AS `n` from (`shop`.`a` `x` left join `shop`.`b` on((`x`.`id` = `shop`.`b`.`id`))) where (`x`.`z` = 1) order by `x`.`id`"),
            "CREATE VIEW `store`.`v` AS select `x`.`id` AS `id`,`store`.`b`.`n` AS `n` from (`store`.`a` `x` left join `store`.`b` on((`x`.`id` = `store`.`b`.`id`))) where (`x`.`z` = 1) order by `x`.`id`"
        )
        XCTAssertEqual(
            rewrite("CREATE VIEW `v` AS select (select count(0) from `shop`.`t`) AS `shop`,`d`.`n` AS `n` from (select 1 AS `n`) `d`,`shop`.`u` `shop`"),
            "CREATE VIEW `store`.`v` AS select (select count(0) from `store`.`t`) AS `shop`,`d`.`n` AS `n` from (select 1 AS `n`) `d`,`store`.`u` `shop`"
        )
    }

    /// Verifies string literals are copied as they are and names are compared
    /// byte for byte unless the server folds case: an NFD table named like
    /// the NFC database stays, and `shopcase` matches `ShopCase` only with
    /// lower_case_table_names set.
    func testLiteralsByteComparisonAndServerCaseRules() {
        XCTAssertEqual(
            rewrite("CREATE VIEW `v` AS select `shop`.`t`.`a` AS `a`,'from `shop`.`t` it''s \\'x\\'' AS `lit`,\"`shop`.\" AS `lit2` from `shop`.`t`"),
            "CREATE VIEW `store`.`v` AS select `store`.`t`.`a` AS `a`,'from `shop`.`t` it''s \\'x\\'' AS `lit`,\"`shop`.\" AS `lit2` from `store`.`t`"
        )

        let nfc = "caf\u{00E9}"
        let nfd = "cafe\u{0301}"
        let accented = SADatabaseRenameViewRewriter(sourceDatabase: nfc, targetDatabase: "store", caseInsensitiveNames: false)
        XCTAssertEqual(
            rewrite("CREATE VIEW `v` AS select `\(nfd)`.`a` AS `a` from `\(nfc)`.`\(nfd)`", rewriter: accented),
            "CREATE VIEW `store`.`v` AS select `\(nfd)`.`a` AS `a` from `store`.`\(nfd)`"
        )

        let sensitive = SADatabaseRenameViewRewriter(sourceDatabase: "ShopCase", targetDatabase: "store", caseInsensitiveNames: false)
        let insensitive = SADatabaseRenameViewRewriter(sourceDatabase: "ShopCase", targetDatabase: "store", caseInsensitiveNames: true)
        XCTAssertEqual(rewrite("CREATE VIEW `v` AS select 1 from `shopcase`.`t`", rewriter: sensitive), "CREATE VIEW `store`.`v` AS select 1 from `shopcase`.`t`")
        XCTAssertEqual(rewrite("CREATE VIEW `v` AS select 1 from `shopcase`.`t`", rewriter: insensitive), "CREATE VIEW `store`.`v` AS select 1 from `store`.`t`")
    }

    /// Verifies the FROM inside EXTRACT, TRIM and similar function calls does
    /// not start an object list: the column references after it stay column
    /// references, while a subquery passed to a function is still followed.
    func testFunctionInternalFromStaysInExpressionContext() {
        XCTAssertEqual(
            rewrite("CREATE VIEW `v` AS select extract(year from `shop`.`t`.`d`) AS `y`,trim(both 'x' from `shop`.`c`) AS `c`,`shop`.`t`.`n` AS `n` from `shop`.`t` `shop`"),
            "CREATE VIEW `store`.`v` AS select extract(year from `store`.`t`.`d`) AS `y`,trim(both 'x' from `shop`.`c`) AS `c`,`store`.`t`.`n` AS `n` from `store`.`t` `shop`"
        )
        XCTAssertEqual(
            rewrite("CREATE VIEW `v` AS select coalesce((select max(`shop`.`u`.`n`) from `shop`.`u`),0) AS `m` from `shop`.`t` where exists(select 1 from `shop`.`w` where (`shop`.`w`.`id` = `shop`.`t`.`id`))"),
            "CREATE VIEW `store`.`v` AS select coalesce((select max(`store`.`u`.`n`) from `store`.`u`),0) AS `m` from `store`.`t` where exists(select 1 from `store`.`w` where (`store`.`w`.`id` = `store`.`t`.`id`))"
        )
    }

    /// Verifies the parenthesis after STRAIGHT_JOIN or LATERAL opens a nested
    /// join or derived table whose object references are rewritten, while a
    /// `select straight_join` option leaves the select list an expression.
    func testStraightJoinAndLateralOpenObjectReferences() {
        XCTAssertEqual(
            rewrite("CREATE VIEW `v` AS select `va`.`n` AS `n` from (`shop`.`va` straight_join (`shop`.`vb` join `shop`.`vc` on(`vb`.`n` = `vc`.`n`)) on(`va`.`n` = `vb`.`n`))"),
            "CREATE VIEW `store`.`v` AS select `va`.`n` AS `n` from (`store`.`va` straight_join (`store`.`vb` join `store`.`vc` on(`vb`.`n` = `vc`.`n`)) on(`va`.`n` = `vb`.`n`))"
        )
        XCTAssertEqual(
            rewrite("CREATE VIEW `v` AS select straight_join `shop`.`t`.`a` AS `a`,`shop`.`u`.`b` AS `b` from (`shop`.`t` join `shop`.`u`)"),
            "CREATE VIEW `store`.`v` AS select straight_join `store`.`t`.`a` AS `a`,`store`.`u`.`b` AS `b` from (`store`.`t` join `store`.`u`)"
        )
        XCTAssertEqual(
            rewrite("CREATE VIEW `v` AS select `l`.`n` AS `n` from (`shop`.`t` join lateral (select `shop`.`u`.`n` AS `n` from `shop`.`u` where (`shop`.`u`.`id` = `shop`.`t`.`id`)) `l`)"),
            "CREATE VIEW `store`.`v` AS select `l`.`n` AS `n` from (`store`.`t` join lateral (select `store`.`u`.`n` AS `n` from `store`.`u` where (`store`.`u`.`id` = `store`.`t`.`id`)) `l`)"
        )
    }

    /// Verifies a scalar subquery is followed whatever precedes its
    /// parenthesis - an operator word such as DIV, MOD, REGEXP or INTERVAL is
    /// not a function whose arguments hide the subquery's FROM.
    func testSubqueriesAfterOperatorWordsAreFollowed() {
        XCTAssertEqual(
            rewrite("CREATE VIEW `v` AS select (10 DIV (select count(0) from `shop`.`b`)) AS `d`,(`shop`.`t`.`n` MOD (select max(`shop`.`b`.`n`) from `shop`.`b`)) AS `m`,(`shop`.`t`.`s` regexp (select `shop`.`p`.`re` from `shop`.`p` limit 1)) AS `r`,(`shop`.`t`.`d` + interval (select 1 from `shop`.`b`) day) AS `i` from `shop`.`t`"),
            "CREATE VIEW `store`.`v` AS select (10 DIV (select count(0) from `store`.`b`)) AS `d`,(`store`.`t`.`n` MOD (select max(`store`.`b`.`n`) from `store`.`b`)) AS `m`,(`store`.`t`.`s` regexp (select `store`.`p`.`re` from `store`.`p` limit 1)) AS `r`,(`store`.`t`.`d` + interval (select 1 from `store`.`b`) day) AS `i` from `store`.`t`"
        )
    }

    /// Verifies a subquery introduced by WITH is followed like one introduced
    /// by SELECT, and that a combining mark right after a quote or backtick
    /// does not hide the delimiter (Swift would merge the two into one
    /// Character): the literal is copied, the names after it are rewritten.
    func testWithSubqueriesAndCombiningMarksAfterDelimiters() {
        XCTAssertEqual(
            rewrite("CREATE VIEW `v` AS select (10 DIV (with `c` as (select 2 AS `n`) select count(0) from `shop`.`z`)) AS `d` from `shop`.`t`"),
            "CREATE VIEW `store`.`v` AS select (10 DIV (with `c` as (select 2 AS `n`) select count(0) from `store`.`z`)) AS `d` from `store`.`t`"
        )
        let mark = "\u{301}"
        XCTAssertEqual(
            rewrite("CREATE VIEW `v` AS select '\(mark)x' AS `a`,`\(mark)b`.`c` AS `c`,`shop`.`\(mark)t`.`d` AS `d` from (`shop`.`\(mark)t` join `shop`.`u` `\(mark)b`)"),
            "CREATE VIEW `store`.`v` AS select '\(mark)x' AS `a`,`\(mark)b`.`c` AS `c`,`store`.`\(mark)t`.`d` AS `d` from (`store`.`\(mark)t` join `store`.`u` `\(mark)b`)"
        )
        let marked = SADatabaseRenameViewRewriter(sourceDatabase: "\(mark)shop", targetDatabase: "store", caseInsensitiveNames: false)
        XCTAssertEqual(
            rewrite("CREATE VIEW `v` AS select 1 from `\(mark)shop`.`t`", rewriter: marked),
            "CREATE VIEW `store`.`v` AS select 1 from `store`.`t`"
        )
    }

    /// Verifies the sequence named by MariaDB's nextval/lastval/setval moves
    /// with the tables: its database part is rewritten although it sits in an
    /// expression, and the remaining arguments stay expressions.
    func testSequenceFunctionArgumentsAreObjectReferences() {
        XCTAssertEqual(
            rewrite("CREATE VIEW `v` AS select nextval(`shop`.`numbers`) AS `n`,lastval(`shop`.`numbers`) AS `l`,setval(`shop`.`numbers`,`shop`.`t`.`a`,0) AS `s` from `shop`.`t`"),
            "CREATE VIEW `store`.`v` AS select nextval(`store`.`numbers`) AS `n`,lastval(`store`.`numbers`) AS `l`,setval(`store`.`numbers`,`store`.`t`.`a`,0) AS `s` from `store`.`t`"
        )
    }

    /// Verifies literals the server printed with a character set introducer
    /// other than UTF-8 are recognised in any of their forms, while UTF-8
    /// introducers, plain literals and names starting with an underscore
    /// are not.
    func testDetectsLiteralsOutsideUTF8() {
        XCTAssertTrue(SADatabaseRenameViewRewriter.hasLiteralOutsideUTF8("CREATE VIEW `v` AS select _latin1'\u{E9}' AS `s`"))
        XCTAssertTrue(SADatabaseRenameViewRewriter.hasLiteralOutsideUTF8("CREATE VIEW `v` AS select _binary 0xFF AS `b`"))
        XCTAssertTrue(SADatabaseRenameViewRewriter.hasLiteralOutsideUTF8("CREATE VIEW `v` AS select _latin1 X'E9' AS `s`,1 AS `n`"))
        XCTAssertTrue(SADatabaseRenameViewRewriter.hasLiteralOutsideUTF8("CREATE VIEW `v` AS select _ucs2 b'01' AS `s`"))
        XCTAssertFalse(SADatabaseRenameViewRewriter.hasLiteralOutsideUTF8("CREATE VIEW `v` AS select _utf8mb4'x' AS `s`,_utf8'y' AS `t`,'_latin1' AS `u` from `shop`.`t`"))
        XCTAssertFalse(SADatabaseRenameViewRewriter.hasLiteralOutsideUTF8("CREATE VIEW `v` AS select `shop`.`_t`.`_c` AS `_c`,0xFF AS `h` from `shop`.`_t`"))
    }

    /// Verifies a statement without the view's clause is refused with a
    /// reason, as is a definition printed without identifier quoting
    /// (`sql_quote_show_create` off), which the rewriter cannot follow.
    func testRefusesStatementWithoutViewClause() throws {
        let result = rewriter.rewriteCreateStatement("select 1", forView: "v")
        XCTAssertNil(result.statement)
        XCTAssertTrue(try XCTUnwrap(result.failureReason).contains("no VIEW clause"))

        let unquoted = rewriter.rewriteCreateStatement("CREATE VIEW v AS select shop.t.a AS a from shop.t", forView: "v")
        XCTAssertNil(unquoted.statement)
        XCTAssertNotNil(unquoted.failureReason)
    }
}

final class SADatabaseRenameExecutorTests: XCTestCase {

    /// A stand-in for the connection: records every statement and answers
    /// from a table of responses, treating anything else as a statement
    /// without a result set.
    private final class FakeServer {
        var statements: [String] = []
        var responses: [(matches: (String) -> Bool, result: SADatabaseRenameStatementResult)] = []
        var createdViews: Set<String> = []

        // prefixes are compared byte for byte, as the server would: String's
        // hasPrefix treats NFC and NFD names as equal
        func respond(to prefix: String, rows: [[Any]]) {
            responses.append(({ $0.utf8.starts(with: prefix.utf8) }, SADatabaseRenameStatementResult(rows: rows)))
        }

        func fail(_ prefix: String, with error: String) {
            responses.append(({ $0.utf8.starts(with: prefix.utf8) }, SADatabaseRenameStatementResult(error: error)))
        }

        func run(_ statement: String) -> SADatabaseRenameStatementResult {
            statements.append(statement)
            if let response = responses.first(where: { $0.matches(statement) }) {
                return response.result
            }
            return SADatabaseRenameStatementResult(rows: [])
        }

        var executor: SADatabaseRenameExecutor {
            SADatabaseRenameExecutor(run: { [unowned self] in run($0) }, quote: { "'" + $0.replacingOccurrences(of: "'", with: "''") + "'" })
        }
    }

    private let showCreateViewPrefix = "SHOW CREATE VIEW `shop`."

    private let sessionQuery = "SELECT @@sql_mode, @@collation_connection, @@sql_quote_show_create"

    private let viewsQuery = "SELECT TABLE_NAME, CHARACTER_SET_CLIENT, HEX(VIEW_DEFINITION) FROM information_schema.VIEWS WHERE TABLE_SCHEMA = 'shop'"

    /// `HEX()` of a definition body, as information_schema.VIEWS would print it.
    private func hex(_ text: String) -> String {
        text.utf8.map { String(format: "%02X", $0) }.joined()
    }

    private let totalsDefinition = "CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `totals` AS select sum(`shop`.`orders`.`total`) AS `t` from `shop`.`orders`"

    private func makeServer(tables: [[Any]] = [["orders", "BASE TABLE"], ["totals", "VIEW"]], lowerCaseTableNames: String = "2", sqlMode: String = "STRICT_TRANS_TABLES,NO_BACKSLASH_ESCAPES", collation: String = "utf8mb4_0900_ai_ci", quoteShowCreate: String = "1", viewCharacterSet: String = "utf8mb4", viewCollation: String = "utf8mb4_general_ci") -> FakeServer {
        let server = FakeServer()
        server.respond(to: "SELECT TABLE_NAME, TABLE_TYPE FROM information_schema.TABLES WHERE TABLE_SCHEMA = 'shop'", rows: tables)
        server.respond(to: "SELECT @@lower_case_table_names", rows: [[lowerCaseTableNames]])
        server.respond(to: viewsQuery, rows: tables.filter { ($0[1] as? String)?.uppercased() == "VIEW" }.map { [$0[0], viewCharacterSet, hex("select 1 AS `n`")] })
        server.respond(to: sessionQuery, rows: [[sqlMode, collation, quoteShowCreate]])
        // the session as the executor left it: the target selected, the parsing modes off
        server.respond(to: "SELECT DATABASE(), @@sql_mode", rows: [["store", SADatabaseRenameExecutor.sqlMode(forViewDefinitions: sqlMode)]])
        server.respond(to: showCreateViewPrefix + "`totals`", rows: [["totals", totalsDefinition, viewCharacterSet, viewCollation]])
        return server
    }

    private func statements(of server: FakeServer, from prefix: String) -> [String] {
        guard let start = server.statements.firstIndex(where: { $0.hasPrefix(prefix) }) else { return [] }
        return Array(server.statements[start...])
    }

    /// Whether the server saw nothing but the inspection queries.
    private func onlyInspected(_ server: FakeServer) -> Bool {
        server.statements.allSatisfy { $0.hasPrefix("SELECT ") || $0.hasPrefix("SHOW EVENTS ") }
    }

    /// Verifies the whole sequence: the source is read from information_schema,
    /// the session's settings and every view definition (as raw bytes) are
    /// read before anything moves, the target is created with the source's
    /// defaults, every table renamed, every view recreated in the target as
    /// the default database, under the session's sql_mode minus the modes
    /// that misread the printed definition and under the collation the view
    /// was created with (all restored), then the source dropped. The client
    /// character set is never changed - it describes the connection's own
    /// encoding, not the view's.
    func testRenamesTablesRecreatesViewsAndDropsTheSource() {
        let server = makeServer()
        XCTAssertNil(server.executor.rename("shop", to: "store", encoding: "utf8mb4", collation: "utf8mb4_general_ci"))

        let inspection = server.statements.prefix(6)
        XCTAssertEqual(inspection.count, 6)
        XCTAssertTrue(inspection.allSatisfy { $0.hasPrefix("SELECT ") || $0.hasPrefix("SHOW EVENTS ") }, inspection.joined(separator: "\n"))
        XCTAssertEqual(inspection.filter { $0.contains("information_schema.") && $0.contains("_SCHEMA = 'shop'") }.count, 3, inspection.joined(separator: "\n"))
        XCTAssertTrue(inspection.contains("SELECT name, type FROM mysql.proc WHERE db = 'shop' ORDER BY name"), inspection.joined(separator: "\n"))
        XCTAssertTrue(inspection.contains("SHOW EVENTS FROM `shop`"), inspection.joined(separator: "\n"))
        XCTAssertEqual(Array(server.statements.dropFirst(6)), [
            sessionQuery,
            "SET sql_mode = 'STRICT_TRANS_TABLES'",
            "SHOW CREATE VIEW `shop`.`totals`",
            "CREATE DATABASE `store` DEFAULT CHARACTER SET = `utf8mb4` DEFAULT COLLATE = `utf8mb4_general_ci`",
            "RENAME TABLE `shop`.`orders` TO `store`.`orders`",
            "USE `store`",
            "SET collation_connection = 'utf8mb4_general_ci'",
            "CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `store`.`totals` AS select sum(`store`.`orders`.`total`) AS `t` from `store`.`orders`",
            "SET collation_connection = 'utf8mb4_0900_ai_ci'",
            "SELECT DATABASE(), @@sql_mode",
            "SET sql_mode = 'STRICT_TRANS_TABLES,NO_BACKSLASH_ESCAPES'",
            "DROP DATABASE `shop`"
        ])
        XCTAssertFalse(server.statements.contains { $0.hasPrefix("SET ") && $0.contains("character_set_client") })
    }

    /// Verifies the source is kept when the session turns out not to be the
    /// one set up for the views - a connection re-established meanwhile
    /// comes back on the framework's default database and without the
    /// sql_mode - since a view may then have been created against the source.
    func testSourceIsKeptWhenTheSessionWasReestablished() throws {
        let server = makeServer()
        server.responses.removeAll { $0.matches("SELECT DATABASE(), @@sql_mode") }
        server.respond(to: "SELECT DATABASE(), @@sql_mode", rows: [["shop", "STRICT_TRANS_TABLES,NO_BACKSLASH_ESCAPES"]])
        let description = try XCTUnwrap(server.executor.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertTrue(description.contains("Moving view 'totals' failed: the connection was re-established while the views were recreated, so they may still point at the old database. The objects moved so far are in 'store'; 'shop' was not dropped."), description)
        XCTAssertFalse(server.statements.contains { $0.hasPrefix("DROP") })
        XCTAssertEqual(server.statements.last, "USE `shop`")

        let intact = makeServer()
        intact.respond(to: "SELECT DATABASE(), @@sql_mode", rows: [["store", "STRICT_TRANS_TABLES"]])
        XCTAssertNil(intact.executor.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertEqual(intact.statements.last, "DROP DATABASE `shop`")

        // a server that folds case (lower_case_table_names = 1) reports the
        // selected database lowercased; one that keeps case must match exactly
        let folded = makeServer(lowerCaseTableNames: "1")
        folded.responses.removeAll { $0.matches("SELECT DATABASE(), @@sql_mode") }
        folded.respond(to: "SELECT DATABASE(), @@sql_mode", rows: [["mixedname", "STRICT_TRANS_TABLES"]])
        XCTAssertNil(folded.executor.rename("shop", to: "MixedName", encoding: nil, collation: nil))
        XCTAssertEqual(folded.statements.last, "DROP DATABASE `shop`")

        let exact = makeServer(lowerCaseTableNames: "0")
        exact.responses.removeAll { $0.matches("SELECT DATABASE(), @@sql_mode") }
        exact.respond(to: "SELECT DATABASE(), @@sql_mode", rows: [["mixedname", "STRICT_TRANS_TABLES"]])
        XCTAssertNotNil(exact.executor.rename("shop", to: "MixedName", encoding: nil, collation: nil))
        XCTAssertFalse(exact.statements.contains { $0.hasPrefix("DROP") })
    }

    /// Verifies a definition whose bytes, as information_schema prints them
    /// in hex, are not UTF-8 - a `_binary` literal, say, which could not
    /// travel through the connection unchanged - refuses the rename before
    /// anything moves, while numbers and bytes the server delivers are read
    /// as text, and names the server keeps apart (NFC and NFD `café`) keep
    /// their own definitions.
    func testDefinitionsMustBeUTF8AndNamesStayDistinct() throws {
        let invalid = makeServer()
        invalid.responses.removeAll { $0.matches(viewsQuery) }
        invalid.respond(to: viewsQuery, rows: [["totals", "utf8mb4", hex("select _binary'") + "FF" + hex("' AS `b`")]])
        let description = try XCTUnwrap(invalid.executor.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertTrue(description.contains("The definition of the view 'totals' holds a string outside UTF-8; Rename Database cannot recreate it faithfully. Nothing was changed."), description)
        XCTAssertTrue(onlyInspected(invalid), invalid.statements.joined(separator: "\n"))

        let introducer = makeServer()
        introducer.responses.removeAll { $0.matches(showCreateViewPrefix + "`totals`") }
        introducer.respond(to: showCreateViewPrefix + "`totals`", rows: [["totals", "CREATE VIEW `totals` AS select _latin1'\u{E9}' AS `s` from `shop`.`orders`", "utf8mb4", "utf8mb4_general_ci"]])
        let reason = try XCTUnwrap(introducer.executor.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertTrue(reason.contains("The definition of the view 'totals' holds a string outside UTF-8"), reason)
        XCTAssertFalse(introducer.statements.contains { $0.hasPrefix("CREATE DATABASE") || $0.hasPrefix("RENAME") || $0.hasPrefix("DROP") }, introducer.statements.joined(separator: "\n"))
        XCTAssertEqual(introducer.statements.last, "SET sql_mode = 'STRICT_TRANS_TABLES,NO_BACKSLASH_ESCAPES'")

        let numbers = makeServer()
        numbers.responses.removeAll { $0.matches("SELECT @@lower_case_table_names") }
        numbers.respond(to: "SELECT @@lower_case_table_names", rows: [[NSNumber(value: 2)]])
        XCTAssertNil(numbers.executor.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertEqual(numbers.statements.last, "DROP DATABASE `shop`")

        let nfc = "caf\u{00E9}"
        let nfd = "cafe\u{0301}"
        let distinct = makeServer(tables: [["orders", "BASE TABLE"], [nfc, "VIEW"], [nfd, "VIEW"]])
        distinct.respond(to: showCreateViewPrefix + "`\(nfc)`", rows: [[nfc, "CREATE VIEW `\(nfc)` AS select 1 AS `n`", "utf8mb4", "utf8mb4_0900_ai_ci"]])
        distinct.respond(to: showCreateViewPrefix + "`\(nfd)`", rows: [[nfd, "CREATE VIEW `\(nfd)` AS select 2 AS `n`", "utf8mb4", "utf8mb4_0900_ai_ci"]])
        XCTAssertNil(distinct.executor.rename("shop", to: "store", encoding: nil, collation: nil))
        let creates = distinct.statements.filter { $0.hasPrefix("CREATE VIEW") }
        XCTAssertEqual(creates.count, 2)
        XCTAssertTrue(creates.contains { $0.utf8.elementsEqual("CREATE VIEW `store`.`\(nfc)` AS select 1 AS `n`".utf8) }, creates.joined(separator: "\n"))
        XCTAssertTrue(creates.contains { $0.utf8.elementsEqual("CREATE VIEW `store`.`\(nfd)` AS select 2 AS `n`".utf8) }, creates.joined(separator: "\n"))

        XCTAssertEqual(SADatabaseRenameExecutor.text(NSNumber(value: 1)), "1")
        XCTAssertEqual(SADatabaseRenameExecutor.text(Data("é".utf8)), "é")
        XCTAssertNil(SADatabaseRenameExecutor.text(Data([0xFF])))
        XCTAssertNil(SADatabaseRenameExecutor.text(NSNull()))
        XCTAssertEqual(SADatabaseRenameExecutor.bytes(fromHex: "c3A9"), [0xC3, 0xA9])
        XCTAssertEqual(SADatabaseRenameExecutor.bytes(fromHex: ""), [])
        XCTAssertNil(SADatabaseRenameExecutor.bytes(fromHex: "C3A"))
        XCTAssertNil(SADatabaseRenameExecutor.bytes(fromHex: "ZZ"))
    }

    /// Verifies a definition MariaDB prints without database names (the
    /// view's database being the connection's default) is created with the
    /// target as the default database, so the bare names resolve to the
    /// moved objects; after a successful rename the default stays there for
    /// the caller to select the renamed database.
    func testUnqualifiedReferencesResolveInTheTarget() {
        let server = makeServer()
        server.responses.removeAll { $0.matches(showCreateViewPrefix + "`totals`") }
        server.respond(to: showCreateViewPrefix + "`totals`", rows: [["totals", "CREATE VIEW `totals` AS select sum(`orders`.`total`) AS `t` from `orders`", "utf8mb4", "utf8mb4_0900_ai_ci"]])
        XCTAssertNil(server.executor.rename("shop", to: "store", encoding: nil, collation: nil))
        let use = server.statements.firstIndex(of: "USE `store`")
        let create = server.statements.firstIndex(of: "CREATE VIEW `store`.`totals` AS select sum(`orders`.`total`) AS `t` from `orders`")
        XCTAssertNotNil(use)
        XCTAssertNotNil(create)
        XCTAssertLessThan(use ?? .max, create ?? .min)
        XCTAssertFalse(server.statements.contains("USE `shop`"))
    }

    /// Verifies nothing moves when the session's settings cannot be read or
    /// put in place: a definition could otherwise be read or replayed
    /// differently from how the server meant it.
    func testNothingMovesWhenSessionSetupFails() throws {
        let untouched: (String) -> Bool = { $0.hasPrefix("SHOW CREATE VIEW") || $0.hasPrefix("CREATE DATABASE") || $0.hasPrefix("RENAME") || $0.hasPrefix("USE ") || $0.hasPrefix("DROP") }

        let unreadable = makeServer()
        unreadable.responses.removeAll { $0.matches(sessionQuery) }
        unreadable.fail(sessionQuery, with: "Unknown system variable")
        let description = try XCTUnwrap(unreadable.executor.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertTrue(description.contains("Reading the objects of the database 'shop' failed: Unknown system variable Nothing was changed."), description)
        XCTAssertFalse(unreadable.statements.contains(where: untouched), unreadable.statements.joined(separator: "\n"))

        let incomplete = makeServer()
        incomplete.responses.removeAll { $0.matches(sessionQuery) }
        incomplete.respond(to: sessionQuery, rows: [["STRICT_TRANS_TABLES", NSNull(), "1"]])
        XCTAssertNotNil(incomplete.executor.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertFalse(incomplete.statements.contains(where: untouched))

        let unsettable = makeServer(quoteShowCreate: "0")
        unsettable.fail("SET sql_mode = 'STRICT_TRANS_TABLES', sql_quote_show_create = 1", with: "Variable 'sql_quote_show_create' is read only")
        let reason = try XCTUnwrap(unsettable.executor.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertTrue(reason.contains("Reading the objects of the database 'shop' failed: Variable 'sql_quote_show_create' is read only"), reason)
        XCTAssertEqual(unsettable.statements.last, "SET sql_mode = 'STRICT_TRANS_TABLES,NO_BACKSLASH_ESCAPES', sql_quote_show_create = 0", "the assignments before the failing one are undone")
        XCTAssertFalse(unsettable.statements.contains(where: untouched))
    }

    /// Verifies a view created through a character set other than UTF-8 -
    /// whose definition could not be sent back faithfully through the
    /// connection's UTF-8 transport - refuses the rename before anything
    /// moves, while a view in the UTF-8 family is recreated under its own
    /// collation, and a Unicode target name passes for such a view.
    func testViewsCreatedThroughOtherCharacterSetsAreRefused() throws {
        let latin1 = makeServer(viewCharacterSet: "latin1", viewCollation: "latin1_swedish_ci")
        let description = try XCTUnwrap(latin1.executor.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertTrue(description.contains("The view 'totals' was created through the character set 'latin1'; Rename Database can only recreate views created through UTF-8. Nothing was changed."), description)
        XCTAssertTrue(onlyInspected(latin1), latin1.statements.joined(separator: "\n"))

        let utf8mb3 = makeServer(viewCharacterSet: "utf8mb3", viewCollation: "utf8mb3_general_ci")
        utf8mb3.responses.removeAll { $0.matches("SELECT DATABASE(), @@sql_mode") }
        utf8mb3.respond(to: "SELECT DATABASE(), @@sql_mode", rows: [["目标", "STRICT_TRANS_TABLES"]])
        XCTAssertNil(utf8mb3.executor.rename("shop", to: "目标", encoding: nil, collation: nil))
        XCTAssertTrue(utf8mb3.statements.contains("SET collation_connection = 'utf8mb3_general_ci'"), utf8mb3.statements.joined(separator: "\n"))
        XCTAssertEqual(utf8mb3.statements.last, "DROP DATABASE `shop`")
    }

    /// Verifies neither sql_mode nor collation is set when the session
    /// already parses the printed definition as the server prints it and
    /// uses the view's collation.
    func testSessionIsLeftAloneWhenItAlreadyMatches() {
        let server = makeServer(sqlMode: "STRICT_TRANS_TABLES", collation: "utf8mb4_general_ci")
        XCTAssertNil(server.executor.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertFalse(server.statements.contains { $0.hasPrefix("SET sql_mode") || $0.hasPrefix("SET collation_connection") }, server.statements.joined(separator: "\n"))
    }

    /// Verifies identifier quoting is switched on before the first SHOW
    /// CREATE VIEW when the session has it off, together with the sql_mode,
    /// and both are switched back after the last view - also when a view
    /// could not be recreated, in which case the default database returns
    /// to the source as well.
    func testIdentifierQuotingIsForcedForShowCreateViewAndRestored() {
        let server = makeServer(quoteShowCreate: "0")
        XCTAssertNil(server.executor.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertEqual(statements(of: server, from: sessionQuery).prefix(3).map { $0 }, [sessionQuery, "SET sql_mode = 'STRICT_TRANS_TABLES', sql_quote_show_create = 1", "SHOW CREATE VIEW `shop`.`totals`"])
        XCTAssertEqual(server.statements.suffix(2), ["SET sql_mode = 'STRICT_TRANS_TABLES,NO_BACKSLASH_ESCAPES', sql_quote_show_create = 0", "DROP DATABASE `shop`"])

        let failing = makeServer(quoteShowCreate: "0")
        failing.fail("CREATE ALGORITHM", with: "Access denied")
        XCTAssertNotNil(failing.executor.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertEqual(failing.statements.suffix(2), ["SET sql_mode = 'STRICT_TRANS_TABLES,NO_BACKSLASH_ESCAPES', sql_quote_show_create = 0", "USE `shop`"])
    }

    /// Verifies the three UTF-8 character sets, in any case, are the ones a
    /// UTF-8 transport carries as they are.
    func testIsUTF8() {
        XCTAssertTrue(SADatabaseRenameExecutor.isUTF8("utf8mb4"))
        XCTAssertTrue(SADatabaseRenameExecutor.isUTF8("utf8mb3"))
        XCTAssertTrue(SADatabaseRenameExecutor.isUTF8("UTF8"))
        XCTAssertFalse(SADatabaseRenameExecutor.isUTF8("latin1"))
        XCTAssertFalse(SADatabaseRenameExecutor.isUTF8("utf16"))
    }

    /// Verifies the parsing modes and the compound modes that expand to them
    /// are dropped from the session's sql_mode, and everything else kept.
    func testSQLModeForViewDefinitionsDropsOnlyParsingModes() {
        XCTAssertEqual(SADatabaseRenameExecutor.sqlMode(forViewDefinitions: "REAL_AS_FLOAT,PIPES_AS_CONCAT,ANSI_QUOTES,IGNORE_SPACE,ONLY_FULL_GROUP_BY,ANSI"), "REAL_AS_FLOAT,ONLY_FULL_GROUP_BY")
        XCTAssertEqual(SADatabaseRenameExecutor.sqlMode(forViewDefinitions: "STRICT_TRANS_TABLES, no_backslash_escapes ,ERROR_FOR_DIVISION_BY_ZERO"), "STRICT_TRANS_TABLES,ERROR_FOR_DIVISION_BY_ZERO")
        XCTAssertEqual(SADatabaseRenameExecutor.sqlMode(forViewDefinitions: "EMPTY_STRING_IS_NULL,SIMULTANEOUS_ASSIGNMENT"), "SIMULTANEOUS_ASSIGNMENT", "MariaDB's EMPTY_STRING_IS_NULL would turn a printed '' into NULL")
        XCTAssertEqual(SADatabaseRenameExecutor.sqlMode(forViewDefinitions: "NO_BACKSLASH_ESCAPES"), "")
        XCTAssertEqual(SADatabaseRenameExecutor.sqlMode(forViewDefinitions: ""), "")
    }

    /// Verifies a database without defaults is created without clauses and a
    /// database without views goes straight from the renames to the drop.
    func testCreatesWithoutDefaultsAndSkipsViewHandlingWithoutViews() {
        let server = makeServer(tables: [["a", "BASE TABLE"], ["b", "BASE TABLE"]])
        XCTAssertNil(server.executor.rename("shop", to: "store", encoding: nil, collation: ""))
        XCTAssertEqual(Array(server.statements.dropFirst(6)), [
            "CREATE DATABASE `store`",
            "RENAME TABLE `shop`.`a` TO `store`.`a`",
            "RENAME TABLE `shop`.`b` TO `store`.`b`",
            "DROP DATABASE `shop`"
        ])
    }

    /// Verifies a trigger in the source refuses the rename before the target
    /// is created: RENAME TABLE across databases fails on triggered tables.
    func testTriggerRefusesTheRenameBeforeAnythingChanges() throws {
        let server = makeServer()
        server.respond(to: "SELECT TRIGGER_NAME, EVENT_OBJECT_TABLE FROM information_schema.TRIGGERS WHERE TRIGGER_SCHEMA = 'shop'", rows: [["orders_audit", "orders"]])
        let description = try XCTUnwrap(server.executor.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertTrue(description.contains("trigger 'orders_audit' on table 'orders'"), description)
        XCTAssertTrue(onlyInspected(server), server.statements.joined(separator: "\n"))
    }

    /// Verifies a failed information_schema query stops the inspection and
    /// the rename, so no object can be dropped unseen: an account that can
    /// read neither mysql.proc nor, for want of a global SELECT or
    /// SHOW_ROUTINE privilege, every routine through information_schema is
    /// refused with that reason, and a failing information_schema query with
    /// the server's message.
    func testInspectionFailureStopsBeforeAnythingChanges() throws {
        let server = makeServer()
        server.fail("SELECT name, type FROM mysql.proc", with: "SELECT command denied to user for table 'proc'")
        server.respond(to: "SELECT (SELECT COUNT(*) FROM information_schema.USER_PRIVILEGES", rows: [["0"]])
        let description = try XCTUnwrap(server.executor.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertTrue(description.contains("Reading the objects of the database 'shop' failed: this account cannot list the database's routines completely"), description)
        XCTAssertTrue(onlyInspected(server), server.statements.joined(separator: "\n"))
        XCTAssertFalse(server.statements.contains { $0.hasPrefix("SELECT ROUTINE_NAME") }, "information_schema.ROUTINES is not trusted without the privilege")

        let denied = makeServer()
        denied.fail("SELECT name, type FROM mysql.proc", with: "SELECT command denied to user for table 'proc'")
        denied.respond(to: "SELECT (SELECT COUNT(*) FROM information_schema.USER_PRIVILEGES", rows: [["1"]])
        denied.fail("SELECT ROUTINE_NAME", with: "SELECT command denied")
        let reason = try XCTUnwrap(denied.executor.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertTrue(reason.contains("Reading the objects of the database 'shop' failed: SELECT command denied Nothing"), reason)
        XCTAssertTrue(onlyInspected(denied), denied.statements.joined(separator: "\n"))
    }

    /// Verifies events are listed with SHOW EVENTS, which a user without the
    /// EVENT privilege cannot run - where information_schema.EVENTS would
    /// quietly list nothing and the events would vanish with the source - and
    /// that such a refusal, once mysql.event cannot be read either, stops the
    /// rename before anything changes.
    func testEventsAreListedWithShowEventsAndHiddenEventsFailClosed() throws {
        let events = makeServer()
        events.respond(to: "SHOW EVENTS FROM `shop`", rows: [["shop", "nightly", "root@localhost", "SYSTEM", "RECURRING"]])
        let description = try XCTUnwrap(events.executor.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertTrue(description.contains("event 'nightly'"), description)
        XCTAssertTrue(onlyInspected(events), events.statements.joined(separator: "\n"))

        let denied = makeServer()
        denied.fail("SHOW EVENTS FROM `shop`", with: "Access denied; you need (at least one of) the EVENT privilege(s) for this operation")
        denied.fail("SELECT db, name FROM mysql.event", with: "SELECT command denied to user for table 'event'")
        let reason = try XCTUnwrap(denied.executor.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertTrue(reason.contains("Reading the objects of the database 'shop' failed: Access denied; you need (at least one of) the EVENT privilege(s)"), reason)
        XCTAssertTrue(onlyInspected(denied), denied.statements.joined(separator: "\n"))
    }

    /// Verifies routines come from mysql.proc where it exists - which lists
    /// every routine, also on a MariaDB whose data directory was never run
    /// through mysql_upgrade - and from information_schema.ROUTINES only on
    /// a server without that table (MySQL 8) for an account whose privilege
    /// makes the server show every routine; events of an un-upgraded server
    /// come from mysql.event. Such a server neither blocks the rename nor
    /// loses a routine unseen.
    func testRoutinesComeFromMySQLProcOrACompleteInformationSchema() throws {
        let mysql8 = makeServer()
        mysql8.fail("SELECT name, type FROM mysql.proc", with: "Table 'mysql.proc' doesn't exist")
        mysql8.respond(to: "SELECT (SELECT COUNT(*) FROM information_schema.USER_PRIVILEGES", rows: [["1"]])
        mysql8.respond(to: "SELECT ROUTINE_NAME, ROUTINE_TYPE FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA = 'shop'", rows: [["cleanup", "PROCEDURE"]])
        let refused = try XCTUnwrap(mysql8.executor.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertTrue(refused.contains("procedure 'cleanup'"), refused)
        XCTAssertTrue(onlyInspected(mysql8), mysql8.statements.joined(separator: "\n"))

        let mariadb = makeServer()
        mariadb.respond(to: "SELECT name, type FROM mysql.proc WHERE db = 'shop'", rows: [["cleanup", "PROCEDURE"]])
        mariadb.fail("SHOW EVENTS FROM `shop`", with: "Column count of mysql.event is wrong")
        mariadb.respond(to: "SELECT db, name FROM mysql.event WHERE db = 'shop'", rows: [["shop", "nightly"]])
        let description = try XCTUnwrap(mariadb.executor.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertTrue(description.contains("procedure 'cleanup', event 'nightly'"), description)
        XCTAssertTrue(onlyInspected(mariadb), mariadb.statements.joined(separator: "\n"))
        XCTAssertFalse(mariadb.statements.contains { $0.hasPrefix("SELECT ROUTINE_NAME") || $0.hasPrefix("SELECT (SELECT COUNT(*) FROM information_schema.USER_PRIVILEGES") }, "mysql.proc is authoritative where it can be read")

        let clean = makeServer()
        clean.respond(to: "SELECT name, type FROM mysql.proc WHERE db = 'shop'", rows: [])
        XCTAssertNil(clean.executor.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertEqual(clean.statements.last, "DROP DATABASE `shop`")
    }

    /// Verifies a failed RENAME TABLE stops the moves and keeps the source:
    /// the tables not yet moved would otherwise be dropped with it.
    func testFailedRenameStopsTheMovesAndKeepsTheSource() throws {
        let server = makeServer(tables: [["a", "BASE TABLE"], ["b", "BASE TABLE"], ["c", "BASE TABLE"]])
        server.fail("RENAME TABLE `shop`.`b`", with: "Access denied")
        let description = try XCTUnwrap(server.executor.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertTrue(description.contains("Moving table 'b' failed: Access denied"), description)
        XCTAssertTrue(description.contains("'shop' was not dropped"), description)
        XCTAssertEqual(statements(of: server, from: "RENAME"), [
            "RENAME TABLE `shop`.`a` TO `store`.`a`",
            "RENAME TABLE `shop`.`b` TO `store`.`b`"
        ])
    }

    /// Verifies a failed SHOW CREATE VIEW is reported with the server's
    /// message and stops the rename before anything moves, with the results
    /// character set and the settings restored.
    func testShowCreateViewFailureStopsBeforeAnythingChanges() throws {
        let server = makeServer()
        server.responses.removeAll { $0.matches(showCreateViewPrefix + "`totals`") }
        server.fail(showCreateViewPrefix, with: "SHOW VIEW command denied")
        let description = try XCTUnwrap(server.executor.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertTrue(description.contains("Reading the objects of the database 'shop' failed: SHOW VIEW command denied Nothing was changed."), description)
        XCTAssertFalse(server.statements.contains { $0.hasPrefix("CREATE DATABASE") || $0.hasPrefix("RENAME") || $0.hasPrefix("DROP") })
        XCTAssertEqual(server.statements.last, "SET sql_mode = 'STRICT_TRANS_TABLES,NO_BACKSLASH_ESCAPES'")
    }

    /// Verifies the session's collation and sql_mode are restored even when
    /// the CREATE VIEW fails, the default database returns to the source, and
    /// the failure is reported with the server's message.
    func testSessionIsRestoredAfterFailedCreateView() throws {
        let server = makeServer()
        server.fail("CREATE ALGORITHM", with: "Access denied for CREATE VIEW")
        let description = try XCTUnwrap(server.executor.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertTrue(description.contains("Moving view 'totals' failed: Access denied for CREATE VIEW"), description)
        XCTAssertEqual(server.statements.filter { $0.hasPrefix("SET ") }, [
            "SET sql_mode = 'STRICT_TRANS_TABLES'",
            "SET collation_connection = 'utf8mb4_general_ci'",
            "SET collation_connection = 'utf8mb4_0900_ai_ci'",
            "SET sql_mode = 'STRICT_TRANS_TABLES,NO_BACKSLASH_ESCAPES'"
        ])
        XCTAssertFalse(server.statements.contains { $0.hasPrefix("DROP") })
        XCTAssertEqual(server.statements.last, "USE `shop`")
    }

    /// Verifies a view selecting from a view listed after it is created on a
    /// later pass, once the view it needs exists in the target.
    func testViewDependingOnALaterViewIsRetried() {
        let server = makeServer(tables: [["orders", "BASE TABLE"], ["a_report", "VIEW"], ["z_base", "VIEW"]])
        server.respond(to: showCreateViewPrefix + "`a_report`", rows: [["a_report", "CREATE VIEW `a_report` AS select `shop`.`z_base`.`n` AS `n` from `shop`.`z_base`", "utf8mb4", "utf8mb4_general_ci"]])
        server.respond(to: showCreateViewPrefix + "`z_base`", rows: [["z_base", "CREATE VIEW `z_base` AS select count(0) AS `n` from `shop`.`orders`", "utf8mb4", "utf8mb4_general_ci"]])
        server.responses.insert(({ [unowned server] in $0.hasPrefix("CREATE VIEW `store`.`a_report`") && !server.createdViews.contains("z_base") }, SADatabaseRenameStatementResult(error: "Table 'store.z_base' doesn't exist")), at: 0)
        server.responses.append(({ [unowned server] statement in
            if statement.hasPrefix("CREATE VIEW `store`.`z_base`") { server.createdViews.insert("z_base") }
            return false
        }, SADatabaseRenameStatementResult(rows: [])))

        XCTAssertNil(server.executor.rename("shop", to: "store", encoding: nil, collation: nil))
        let creates = server.statements.filter { $0.hasPrefix("CREATE VIEW") }
        XCTAssertEqual(creates, [
            "CREATE VIEW `store`.`a_report` AS select `store`.`z_base`.`n` AS `n` from `store`.`z_base`",
            "CREATE VIEW `store`.`z_base` AS select count(0) AS `n` from `store`.`orders`",
            "CREATE VIEW `store`.`a_report` AS select `store`.`z_base`.`n` AS `n` from `store`.`z_base`"
        ])
        XCTAssertEqual(server.statements.last, "DROP DATABASE `shop`")
    }

    /// Verifies a failed DROP DATABASE after a complete move is reported as
    /// such - the objects are in the target, only the empty source remains -
    /// and the default database returns to the surviving source.
    func testDropFailureIsReported() throws {
        let server = makeServer()
        server.fail("DROP DATABASE", with: "Access denied for DROP")
        let description = try XCTUnwrap(server.executor.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertTrue(description.contains("Every object was moved to 'store', but dropping 'shop' failed: Access denied for DROP"), description)
        XCTAssertEqual(server.statements.last, "USE `shop`")
    }
}
