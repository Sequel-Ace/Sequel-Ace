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

        // stored libraries go with the database on DROP DATABASE as well
        let libraries = makePlan()
        libraries.recordLibraries([["jslib"], [NSNull()]])
        XCTAssertFalse(libraries.canStart)
        XCTAssertEqual(libraries.unsupportedObjects, ["library 'jslib'"])
        XCTAssertEqual(try XCTUnwrap(libraries.failureDescription), "The database contains objects that Rename Database cannot move: library 'jslib'. Nothing was changed.")

        // views in other databases reading from the source would stop working
        let external = makePlan()
        external.recordExternalViews(["`reporting`.`proxy`"])
        XCTAssertFalse(external.canStart)
        XCTAssertFalse(external.mayDropSourceDatabase)
        XCTAssertEqual(try XCTUnwrap(external.failureDescription), "Views in other databases read from 'shop' (`reporting`.`proxy`) and would stop working once it is renamed. Nothing was changed.")
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

    /// Verifies privileges granted on the source or its objects refuse the
    /// rename, naming at most five of them.
    func testObjectPrivilegesRefuseTheRename() throws {
        let plan = makePlan()
        plan.recordObjectPrivileges(["`shop%`.* for 'app'@'%'", "`orders` for 'app'@'%'", "partial revoke on `shop`.* for 'reader'@'%'"])
        XCTAssertFalse(plan.canStart)
        XCTAssertEqual(try XCTUnwrap(plan.failureDescription), "The database has privileges granted on it, its tables or its views, or partially revoked on it (`shop%`.* for 'app'@'%', `orders` for 'app'@'%', partial revoke on `shop`.* for 'reader'@'%'), which Rename Database cannot move. Nothing was changed.")

        let many = makePlan()
        many.recordObjectPrivileges((1...6).map { "`t\($0)` for 'u'@'%'" })
        XCTAssertTrue(try XCTUnwrap(many.failureDescription).contains("(`t1` for 'u'@'%', `t2` for 'u'@'%', `t3` for 'u'@'%', `t4` for 'u'@'%', `t5` for 'u'@'%', …)"))

        // grants that already exist for the new name refuse it too, named as such
        let target = makePlan()
        target.recordTargetPrivileges(["`st%`.* for 'app'@'%'", "partial revoke on `store`.* for 'reader'@'%'"])
        XCTAssertFalse(target.canStart)
        XCTAssertFalse(target.mayDropSourceDatabase)
        XCTAssertEqual(try XCTUnwrap(target.failureDescription), "Privileges are already granted or partially revoked for the new name 'store' (`st%`.* for 'app'@'%', partial revoke on `store`.* for 'reader'@'%'); the moved tables and views would come under them. Nothing was changed.")
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

    /// Verifies optimizer hints and other block comments are copied byte for
    /// byte and do not count as the token before the next one: a `select
    /// /*+ … */ straight_join` option stays a select option, so a column
    /// reference through a table alias named like the database is left
    /// alone; a SELECT after a parenthesis and a comment still opens a
    /// subquery; and quotes, backticks or parentheses inside a comment are
    /// not read as SQL.
    func testOptimizerHintsAndCommentsDoNotChangeTheContext() {
        let hint = "/*+ QB_NAME(`qb`) JOIN_ORDER(`t`@`qb`, `shop`)\n    SET_VAR(optimizer_switch = 'mrr=on') */"
        XCTAssertEqual(
            rewrite("CREATE VIEW `v` AS select \(hint) straight_join `shop`.`id` AS `id`,`shop`.`t`.`n` AS `n` from (`shop`.`t` join `shop`.`u` `shop` on((`shop`.`id` = `shop`.`t`.`id`)))"),
            "CREATE VIEW `store`.`v` AS select \(hint) straight_join `shop`.`id` AS `id`,`store`.`t`.`n` AS `n` from (`store`.`t` join `store`.`u` `shop` on((`shop`.`id` = `store`.`t`.`id`)))"
        )
        XCTAssertEqual(
            rewrite("CREATE VIEW `v` AS select (10 DIV (/* sub */ select /*+ NO_BKA(`b`) */ straight_join count(0) from `shop`.`b`)) AS `d` from `shop`.`t`"),
            "CREATE VIEW `store`.`v` AS select (10 DIV (/* sub */ select /*+ NO_BKA(`b`) */ straight_join count(0) from `store`.`b`)) AS `d` from `store`.`t`"
        )
        // a sequence function or a join is still recognised across a comment
        XCTAssertEqual(
            rewrite("CREATE VIEW `v` AS select nextval /* c */ (`shop`.`s`) AS `n` from `shop`.`t` straight_join /* c */ `shop`.`u`"),
            "CREATE VIEW `store`.`v` AS select nextval /* c */ (`store`.`s`) AS `n` from `store`.`t` straight_join /* c */ `store`.`u`"
        )
        // an unterminated comment is copied to the end and a literal-like text inside is no introducer
        XCTAssertEqual(
            rewrite("CREATE VIEW `v` AS select 1 AS `n` from `shop`.`t` /* `shop`.`x` ("),
            "CREATE VIEW `store`.`v` AS select 1 AS `n` from `store`.`t` /* `shop`.`x` ("
        )
        XCTAssertFalse(SADatabaseRenameViewRewriter.hasLiteralOutsideUTF8("CREATE VIEW `v` AS select /*+ _latin1'x' */ 1 AS `n`"))
        XCTAssertTrue(SADatabaseRenameViewRewriter.hasLiteralOutsideUTF8("CREATE VIEW `v` AS select _latin1 /* c */ 'x' AS `n`"))
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

    /// Verifies that where the server folds the case of names only ASCII
    /// letters are folded, as the server does: `Shop` names the source `shop`,
    /// `ẞhop` does not name `ßhop`.
    func testCaseFoldingIsASCIIOnly() {
        let ascii = SADatabaseRenameViewRewriter(sourceDatabase: "shop", targetDatabase: "store", caseInsensitiveNames: true)
        XCTAssertEqual(ascii.rewriteCreateStatement("CREATE VIEW `v` AS select 1 from `Shop`.`t`", forView: "v").statement, "CREATE VIEW `store`.`v` AS select 1 from `store`.`t`")

        let sharp = SADatabaseRenameViewRewriter(sourceDatabase: "\u{00DF}hop", targetDatabase: "store", caseInsensitiveNames: true)
        XCTAssertEqual(sharp.rewriteCreateStatement("CREATE VIEW `v` AS select 1 from `\u{1E9E}hop`.`t`", forView: "v").statement, "CREATE VIEW `store`.`v` AS select 1 from `\u{1E9E}hop`.`t`")
        XCTAssertEqual(sharp.rewriteCreateStatement("CREATE VIEW `v` AS select 1 from `\u{00DF}hop`.`t`", forView: "v").statement, "CREATE VIEW `store`.`v` AS select 1 from `store`.`t`")

        XCTAssertEqual(SADatabaseRenameViewRewriter.asciiLowercased(Array("ShOp_1\u{1E9E}".utf8)), Array("shop_1\u{1E9E}".utf8))

        // the server's own folded form is the reference: it folds letters
        // beyond ASCII too (`Àbc` to `àbc`), which the ASCII folding cannot know
        let folded = SADatabaseRenameViewRewriter(sourceDatabase: "\u{00C0}bc", targetDatabase: "store", caseInsensitiveNames: true, serverLoweredSource: "\u{00E0}bc")
        XCTAssertEqual(folded.rewriteCreateStatement("CREATE VIEW `v` AS select 1 from `\u{00E0}bc`.`t`", forView: "v").statement, "CREATE VIEW `store`.`v` AS select 1 from `store`.`t`")
        XCTAssertEqual(folded.rewriteCreateStatement("CREATE VIEW `v` AS select 1 from `\u{00C0}bc`.`t`", forView: "v").statement, "CREATE VIEW `store`.`v` AS select 1 from `store`.`t`")
        let unaware = SADatabaseRenameViewRewriter(sourceDatabase: "\u{00C0}bc", targetDatabase: "store", caseInsensitiveNames: true)
        XCTAssertEqual(unaware.rewriteCreateStatement("CREATE VIEW `v` AS select 1 from `\u{00E0}bc`.`t`", forView: "v").statement, "CREATE VIEW `store`.`v` AS select 1 from `\u{00E0}bc`.`t`")
        let exact = SADatabaseRenameViewRewriter(sourceDatabase: "\u{00C0}bc", targetDatabase: "store", caseInsensitiveNames: false, serverLoweredSource: "\u{00E0}bc")
        XCTAssertEqual(exact.rewriteCreateStatement("CREATE VIEW `v` AS select 1 from `\u{00E0}bc`.`t`", forView: "v").statement, "CREATE VIEW `store`.`v` AS select 1 from `\u{00E0}bc`.`t`", "the folded form counts only where the server folds case")
    }

    /// Verifies the objects a definition reads from in the source database
    /// are listed - qualified with the source, or unqualified as MariaDB
    /// prints them, in FROM lists and subqueries alike - while aliases,
    /// column references and objects of other databases are not, and a
    /// doubled backtick in a name is undone.
    func testListsTheSourceObjectsADefinitionReadsFrom() {
        let rewrite = rewriter.rewriteCreateStatement("CREATE VIEW `v` AS select `x`.`a` AS `a`,(select count(0) from `shop`.`s`) AS `c`,`shop`.`t`.`b` AS `b` from ((`shop`.`t` `x` join `u`) left join `other`.`w` on((`x`.`id` = `other`.`w`.`id`))) where exists(select 1 from `shop`.`it``s`)", forView: "v")
        XCTAssertEqual(rewrite.referencedObjects, ["s", "t", "u", "it`s"])
        XCTAssertEqual(rewriter.rewriteCreateStatement("CREATE VIEW `v` AS select 1 AS `n`", forView: "v").referencedObjects, [])
        XCTAssertEqual(rewriter.rewriteCreateStatement("select 1", forView: "v").referencedObjects, [])
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

        /// answers used only when no response above matches, so a test's own response wins
        var defaultResponses: [(prefix: String, result: SADatabaseRenameStatementResult)] = []
        /// values the quoting refuses, as a closed connection would
        var unquotable: Set<String> = []

        func respondByDefault(to prefix: String, rows: [[Any]]) {
            defaultResponses.append((prefix, SADatabaseRenameStatementResult(rows: rows)))
        }

        func run(_ statement: String) -> SADatabaseRenameStatementResult {
            statements.append(statement)
            if let response = responses.first(where: { $0.matches(statement) }) {
                return response.result
            }
            if let response = defaultResponses.first(where: { statement.utf8.starts(with: $0.prefix.utf8) }) {
                return response.result
            }
            return SADatabaseRenameStatementResult(rows: [])
        }

        func quote(_ value: String) -> String? {
            unquotable.contains(value) ? nil : "'" + value.replacingOccurrences(of: "'", with: "''") + "'"
        }

        var executor: SADatabaseRenameExecutor {
            SADatabaseRenameExecutor(run: { [unowned self] in run($0) }, quote: { [unowned self] in quote($0) })
        }
    }

    private let showCreateViewPrefix = "SHOW CREATE VIEW `shop`."

    private let sessionQuery = "SELECT @@sql_mode, @@collation_connection, @@sql_quote_show_create, CONNECTION_ID()"

    private let checkQuery = "SELECT DATABASE(), @@sql_mode, @@collation_connection, CONNECTION_ID()"

    private let restoreCheckQuery = "SELECT @@sql_mode, @@sql_quote_show_create, @@collation_connection"

    private let viewsQuery = "SELECT TABLE_NAME, CHARACTER_SET_CLIENT, HEX(VIEW_DEFINITION) FROM information_schema.VIEWS WHERE TABLE_SCHEMA = 'shop'"

    private let privilegesQuery = "SELECT PRIVILEGE_TYPE FROM information_schema.USER_PRIVILEGES"

    private let partialRevokesQuery = "SHOW VARIABLES LIKE 'partial_revokes'"

    private let librariesProbe = "SELECT TABLE_NAME FROM information_schema.TABLES WHERE UPPER(TABLE_SCHEMA) = 'INFORMATION_SCHEMA' AND UPPER(TABLE_NAME) = 'LIBRARIES'"

    private let librariesQuery = "SELECT LIBRARY_NAME FROM information_schema.LIBRARIES WHERE LIBRARY_SCHEMA = 'shop'"

    private let viewTableUsageProbe = "SELECT TABLE_NAME FROM information_schema.TABLES WHERE UPPER(TABLE_SCHEMA) = 'INFORMATION_SCHEMA' AND UPPER(TABLE_NAME) = 'VIEW_TABLE_USAGE'"

    private let viewTableUsageQuery = "SELECT VIEW_SCHEMA, VIEW_NAME, TABLE_SCHEMA FROM information_schema.VIEW_TABLE_USAGE WHERE LOWER(TABLE_SCHEMA) = LOWER('shop')"

    private let externalViewsQuery = "SELECT TABLE_SCHEMA, TABLE_NAME, HEX(VIEW_DEFINITION) FROM information_schema.VIEWS ORDER BY TABLE_SCHEMA, TABLE_NAME"

    /// `HEX()` of a definition body, as information_schema.VIEWS would print it.
    private func hex(_ text: String) -> String {
        text.utf8.map { String(format: "%02X", $0) }.joined()
    }

    private let totalsDefinition = "CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `totals` AS select sum(`shop`.`orders`.`total`) AS `t` from `shop`.`orders`"

    private func makeServer(tables: [[Any]] = [["orders", "BASE TABLE"], ["totals", "VIEW"]], lowerCaseTableNames: String = "2", sqlMode: String = "STRICT_TRANS_TABLES,NO_BACKSLASH_ESCAPES", collation: String = "utf8mb4_0900_ai_ci", quoteShowCreate: String = "1", viewCharacterSet: String = "utf8mb4", viewCollation: String = "utf8mb4_general_ci") -> FakeServer {
        let server = FakeServer()
        server.respond(to: "SELECT TABLE_NAME, TABLE_TYPE FROM information_schema.TABLES WHERE TABLE_SCHEMA = 'shop'", rows: tables)
        server.respond(to: "SELECT @@lower_case_table_names", rows: [[lowerCaseTableNames]])
        // the server's own folded forms of source and target, asked for where it folds case
        server.respond(to: "SELECT LOWER('shop'), LOWER('store')", rows: [["shop", "store"]])
        server.respond(to: viewsQuery, rows: tables.filter { ($0[1] as? String)?.uppercased() == "VIEW" }.map { [$0[0], viewCharacterSet, hex("select 1 AS `n`")] })
        server.respond(to: sessionQuery, rows: [[sqlMode, collation, quoteShowCreate, "42"]])
        // the settings read back after they were restored
        server.respond(to: restoreCheckQuery, rows: [[sqlMode, quoteShowCreate, collation]])
        // a MySQL 8 with information_schema.VIEW_TABLE_USAGE listing no view
        // elsewhere reading from the source, for an account with a global
        // SELECT and SHOW VIEW; a test's own responses take precedence
        server.respondByDefault(to: privilegesQuery, rows: [["SELECT"], ["SHOW VIEW"]])
        server.respondByDefault(to: viewTableUsageProbe, rows: [["VIEW_TABLE_USAGE"]])
        server.respondByDefault(to: viewTableUsageQuery, rows: [])
        // the session as the executor leaves it: the target selected, the settings restored, the same connection
        server.respond(to: checkQuery, rows: [["store", sqlMode, collation, "42"]])
        server.respond(to: showCreateViewPrefix + "`totals`", rows: [["totals", totalsDefinition, viewCharacterSet, viewCollation]])
        return server
    }

    private func statements(of server: FakeServer, from prefix: String) -> [String] {
        guard let start = server.statements.firstIndex(where: { $0.hasPrefix(prefix) }) else { return [] }
        return Array(server.statements[start...])
    }

    /// Whether the server saw nothing but the inspection queries.
    private func onlyInspected(_ server: FakeServer) -> Bool {
        server.statements.allSatisfy { $0.hasPrefix("SELECT ") || $0.hasPrefix("SHOW EVENTS ") || $0.hasPrefix("SHOW VARIABLES ") }
    }

    /// Verifies the whole sequence: the source is read from information_schema,
    /// the session's settings and every view definition (as raw bytes) are
    /// read before anything moves, the target is created with the source's
    /// defaults, every table renamed, every view recreated in the target as
    /// the default database, under the session's sql_mode minus the modes
    /// that misread the printed definition and under the collation the view
    /// was created with (all restored together after the last view), then
    /// the source dropped once the session proves restored. The client
    /// character set is never changed - it describes the connection's own
    /// encoding, not the view's.
    func testRenamesTablesRecreatesViewsAndDropsTheSource() {
        let server = makeServer()
        XCTAssertNil(server.executor.rename("shop", to: "store", encoding: "utf8mb4", collation: "utf8mb4_general_ci"))

        let inspection = server.statements.prefix(15)
        XCTAssertEqual(inspection.count, 15)
        XCTAssertTrue(inspection.allSatisfy { $0.hasPrefix("SELECT ") || $0.hasPrefix("SHOW EVENTS ") || $0.hasPrefix("SHOW VARIABLES ") }, inspection.joined(separator: "\n"))
        // a server without partial revokes is not asked for restrictions
        XCTAssertTrue(inspection.contains(partialRevokesQuery), inspection.joined(separator: "\n"))
        XCTAssertFalse(server.statements.contains { $0.contains("mysql.user") }, server.statements.joined(separator: "\n"))
        XCTAssertEqual(inspection.filter { $0.contains("information_schema.") && $0.contains("_SCHEMA = 'shop'") }.count, 3, inspection.joined(separator: "\n"))
        XCTAssertTrue(inspection.contains("SELECT name, type FROM mysql.proc WHERE LOWER(db) = LOWER('shop') ORDER BY name"), inspection.joined(separator: "\n"))
        XCTAssertTrue(inspection.contains("SELECT LOWER('shop'), LOWER('store')"), inspection.joined(separator: "\n"))
        XCTAssertTrue(inspection.contains("SHOW EVENTS FROM `shop`"), inspection.joined(separator: "\n"))
        XCTAssertTrue(inspection.contains("SELECT Db, User, Host FROM mysql.db WHERE LOWER('shop') LIKE LOWER(Db) ESCAPE '\\' ORDER BY Db, User, Host"), inspection.joined(separator: "\n"))
        XCTAssertTrue(inspection.contains("SELECT Table_name, User, Host FROM mysql.tables_priv WHERE LOWER(Db) = LOWER('shop') ORDER BY Table_name, User, Host"), inspection.joined(separator: "\n"))
        XCTAssertTrue(inspection.contains("SELECT Table_name, User, Host FROM mysql.columns_priv WHERE LOWER(Db) = LOWER('shop') ORDER BY Table_name, User, Host"), inspection.joined(separator: "\n"))
        // the new name is checked for grants the server kept for it
        XCTAssertTrue(inspection.contains("SELECT Db, User, Host FROM mysql.db WHERE LOWER('store') LIKE LOWER(Db) ESCAPE '\\' ORDER BY Db, User, Host"), inspection.joined(separator: "\n"))
        XCTAssertTrue(inspection.contains("SELECT Table_name, User, Host FROM mysql.tables_priv WHERE LOWER(Db) = LOWER('store') ORDER BY Table_name, User, Host"), inspection.joined(separator: "\n"))
        XCTAssertTrue(inspection.contains("SELECT Table_name, User, Host FROM mysql.columns_priv WHERE LOWER(Db) = LOWER('store') ORDER BY Table_name, User, Host"), inspection.joined(separator: "\n"))
        // a server without information_schema.LIBRARIES is not asked for libraries
        XCTAssertTrue(inspection.contains(librariesProbe), inspection.joined(separator: "\n"))
        XCTAssertFalse(server.statements.contains { $0.hasPrefix(librariesQuery) }, server.statements.joined(separator: "\n"))
        // views elsewhere reading from the source are looked for once the source is known to be movable
        let externalCheck = Array(server.statements.dropFirst(15).prefix(3))
        guard externalCheck.count == 3 else {
            return XCTFail(server.statements.joined(separator: "\n"))
        }
        XCTAssertEqual(externalCheck[0], viewTableUsageProbe)
        XCTAssertTrue(externalCheck[1].hasPrefix(privilegesQuery) && externalCheck[1].contains("'SHOW VIEW'"), externalCheck[1])
        XCTAssertEqual(externalCheck[2], viewTableUsageQuery + " ORDER BY VIEW_SCHEMA, VIEW_NAME")
        XCTAssertEqual(Array(server.statements.dropFirst(18)), [
            sessionQuery,
            "SET sql_mode = 'STRICT_TRANS_TABLES'",
            "SHOW CREATE VIEW `shop`.`totals`",
            "CREATE DATABASE `store` DEFAULT CHARACTER SET = `utf8mb4` DEFAULT COLLATE = `utf8mb4_general_ci`",
            "RENAME TABLE `shop`.`orders` TO `store`.`orders`",
            "USE `store`",
            "SET collation_connection = 'utf8mb4_general_ci'",
            "CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `store`.`totals` AS select sum(`store`.`orders`.`total`) AS `t` from `store`.`orders`",
            "SELECT 1 FROM `store`.`totals` LIMIT 0",
            "SET sql_mode = 'STRICT_TRANS_TABLES,NO_BACKSLASH_ESCAPES', collation_connection = 'utf8mb4_0900_ai_ci'",
            restoreCheckQuery,
            checkQuery,
            "DROP DATABASE `shop`"
        ])
        XCTAssertFalse(server.statements.contains { $0.hasPrefix("SET ") && $0.contains("character_set_client") })
    }

    /// Verifies the source is kept when the session turns out not to be the
    /// one set up for the views - a connection re-established meanwhile is
    /// another server session (CONNECTION_ID), which the framework brings
    /// back on its own default database with the server's default sql_mode,
    /// and a restore the server refused leaves sql_mode or the collation as
    /// the views needed them - since a view may then have been created
    /// against the source or the connection is not what the caller expects.
    func testSourceIsKeptWhenTheSessionWasReestablished() throws {
        let server = makeServer()
        server.responses.removeAll { $0.matches(checkQuery) }
        server.respond(to: checkQuery, rows: [["shop", "STRICT_TRANS_TABLES,NO_BACKSLASH_ESCAPES", "utf8mb4_0900_ai_ci", "42"]])
        let description = try XCTUnwrap(server.executor.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertTrue(description.contains("Moving view 'totals' failed: the connection was re-established while the views were recreated, so they may still point at the old database. The objects moved so far are in 'store'; 'shop' was not dropped."), description)
        XCTAssertFalse(server.statements.contains { $0.hasPrefix("DROP") })
        XCTAssertEqual(server.statements.last, "USE `shop`")

        // a reconnect that ends up on the target with the settings restored
        // (the framework re-selects the database, the restore resets the
        // rest) still shows as another connection
        let reconnected = makeServer()
        reconnected.responses.removeAll { $0.matches(checkQuery) }
        reconnected.respond(to: checkQuery, rows: [["store", "STRICT_TRANS_TABLES,NO_BACKSLASH_ESCAPES", "utf8mb4_0900_ai_ci", "43"]])
        let reason = try XCTUnwrap(reconnected.executor.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertTrue(reason.contains("Moving view 'totals' failed: the connection was re-established while the views were recreated, so they may still point at the old database."), reason)
        XCTAssertFalse(reconnected.statements.contains { $0.hasPrefix("DROP") }, reconnected.statements.joined(separator: "\n"))
        XCTAssertEqual(reconnected.statements.last, "USE `shop`")

        let intact = makeServer()
        intact.responses.removeAll { $0.matches(checkQuery) }
        intact.respond(to: checkQuery, rows: [["store", "STRICT_TRANS_TABLES,NO_BACKSLASH_ESCAPES", "utf8mb4_0900_ai_ci", "42"]])
        XCTAssertNil(intact.executor.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertEqual(intact.statements.last, "DROP DATABASE `shop`")

        // the restore is checked as well: sql_mode or collation still as
        // set for the views means it did not take
        for unrestored in [["store", "STRICT_TRANS_TABLES", "utf8mb4_0900_ai_ci", "42"], ["store", "STRICT_TRANS_TABLES,NO_BACKSLASH_ESCAPES", "utf8mb4_general_ci", "42"]] {
            let refused = makeServer()
            refused.fail("SET sql_mode = 'STRICT_TRANS_TABLES,NO_BACKSLASH_ESCAPES', collation_connection = 'utf8mb4_0900_ai_ci'", with: "Unknown collation")
            refused.responses.removeAll { $0.matches(checkQuery) }
            refused.respond(to: checkQuery, rows: [unrestored])
            let reason = try XCTUnwrap(refused.executor.rename("shop", to: "store", encoding: nil, collation: nil))
            XCTAssertTrue(reason.contains("the connection was re-established while the views were recreated"), reason)
            XCTAssertFalse(refused.statements.contains { $0.hasPrefix("DROP") }, refused.statements.joined(separator: "\n"))
            XCTAssertEqual(refused.statements.last, "USE `shop`")
        }

        // a server that folds case (lower_case_table_names = 1) reports the
        // selected database lowercased; one that keeps case must match exactly
        let folded = makeServer(lowerCaseTableNames: "1")
        folded.respond(to: "SELECT LOWER('shop'), LOWER('MixedName')", rows: [["shop", "mixedname"]])
        folded.responses.removeAll { $0.matches(checkQuery) }
        folded.respond(to: checkQuery, rows: [["mixedname", "STRICT_TRANS_TABLES,NO_BACKSLASH_ESCAPES", "utf8mb4_0900_ai_ci", "42"]])
        XCTAssertNil(folded.executor.rename("shop", to: "MixedName", encoding: nil, collation: nil))
        XCTAssertEqual(folded.statements.last, "DROP DATABASE `shop`")

        let exact = makeServer(lowerCaseTableNames: "0")
        exact.responses.removeAll { $0.matches(checkQuery) }
        exact.respond(to: checkQuery, rows: [["mixedname", "STRICT_TRANS_TABLES,NO_BACKSLASH_ESCAPES", "utf8mb4_0900_ai_ci", "42"]])
        XCTAssertNotNil(exact.executor.rename("shop", to: "MixedName", encoding: nil, collation: nil))
        XCTAssertFalse(exact.statements.contains { $0.hasPrefix("DROP") })

        // the server folds letters beyond ASCII too; its own folded form of
        // the target, read up front, is accepted as the selected database
        let accented = makeServer(lowerCaseTableNames: "2")
        accented.respond(to: "SELECT LOWER('shop'), LOWER('\u{00C0}bc')", rows: [["shop", "\u{00E0}bc"]])
        accented.responses.removeAll { $0.matches(checkQuery) }
        accented.respond(to: checkQuery, rows: [["\u{00E0}bc", "STRICT_TRANS_TABLES,NO_BACKSLASH_ESCAPES", "utf8mb4_0900_ai_ci", "42"]])
        XCTAssertNil(accented.executor.rename("shop", to: "\u{00C0}bc", encoding: nil, collation: nil))
        XCTAssertEqual(accented.statements.last, "DROP DATABASE `shop`")
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
        XCTAssertEqual(introducer.statements.suffix(2), ["SET sql_mode = 'STRICT_TRANS_TABLES,NO_BACKSLASH_ESCAPES'", restoreCheckQuery])

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
        incomplete.respond(to: sessionQuery, rows: [["STRICT_TRANS_TABLES", NSNull(), "1", "42"]])
        XCTAssertNotNil(incomplete.executor.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertFalse(incomplete.statements.contains(where: untouched))

        // the connection id is required as well: without it a reconnect could not be told
        let unidentified = makeServer()
        unidentified.responses.removeAll { $0.matches(sessionQuery) }
        unidentified.respond(to: sessionQuery, rows: [["STRICT_TRANS_TABLES", "utf8mb4_0900_ai_ci", "1"]])
        XCTAssertNotNil(unidentified.executor.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertFalse(unidentified.statements.contains(where: untouched))

        let unsettable = makeServer(quoteShowCreate: "0")
        unsettable.fail("SET sql_mode = 'STRICT_TRANS_TABLES', sql_quote_show_create = 1", with: "Variable 'sql_quote_show_create' is read only")
        let reason = try XCTUnwrap(unsettable.executor.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertTrue(reason.contains("Reading the objects of the database 'shop' failed: Variable 'sql_quote_show_create' is read only"), reason)
        XCTAssertEqual(unsettable.statements.suffix(2), ["SET sql_mode = 'STRICT_TRANS_TABLES,NO_BACKSLASH_ESCAPES', sql_quote_show_create = 0", restoreCheckQuery], "the assignments before the failing one are undone")
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
        utf8mb3.respond(to: "SELECT LOWER('shop'), LOWER('目标')", rows: [["shop", "目标"]])
        utf8mb3.responses.removeAll { $0.matches(checkQuery) }
        utf8mb3.respond(to: checkQuery, rows: [["目标", "STRICT_TRANS_TABLES,NO_BACKSLASH_ESCAPES", "utf8mb4_0900_ai_ci", "42"]])
        XCTAssertNil(utf8mb3.executor.rename("shop", to: "目标", encoding: nil, collation: nil))
        XCTAssertTrue(utf8mb3.statements.contains("SET collation_connection = 'utf8mb3_general_ci'"), utf8mb3.statements.joined(separator: "\n"))
        XCTAssertEqual(utf8mb3.statements.last, "DROP DATABASE `shop`")
    }

    /// Verifies sql_mode is left alone when the session already parses the
    /// printed definition as the server prints it, while the collation is
    /// set before every view even when it is the session's own - what the
    /// connection is on is never assumed - and restored once after the last.
    func testCollationIsSetForEveryViewWhileAMatchingSQLModeIsLeftAlone() throws {
        let server = makeServer(sqlMode: "STRICT_TRANS_TABLES", collation: "utf8mb4_general_ci")
        XCTAssertNil(server.executor.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertFalse(server.statements.contains { $0.hasPrefix("SET sql_mode") }, server.statements.joined(separator: "\n"))
        XCTAssertEqual(server.statements.filter { $0.hasPrefix("SET ") }, ["SET collation_connection = 'utf8mb4_general_ci'", "SET collation_connection = 'utf8mb4_general_ci'"], server.statements.joined(separator: "\n"))
        let create = try XCTUnwrap(server.statements.firstIndex { $0.hasPrefix("CREATE ALGORITHM") })
        XCTAssertEqual(server.statements[create - 1], "SET collation_connection = 'utf8mb4_general_ci'")
        XCTAssertEqual(server.statements.suffix(4), ["SET collation_connection = 'utf8mb4_general_ci'", restoreCheckQuery, checkQuery, "DROP DATABASE `shop`"])

        // a SET the server refuses fails the view instead of creating it under another collation
        let refused = makeServer()
        refused.fail("SET collation_connection = 'utf8mb4_general_ci'", with: "Unknown collation: 'utf8mb4_general_ci'")
        let description = try XCTUnwrap(refused.executor.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertTrue(description.contains("Moving view 'totals' failed: Unknown collation: 'utf8mb4_general_ci'"), description)
        XCTAssertFalse(refused.statements.contains { $0.hasPrefix("CREATE ALGORITHM") || $0.hasPrefix("DROP") }, refused.statements.joined(separator: "\n"))
        XCTAssertEqual(refused.statements.last, "USE `shop`")
    }

    /// Verifies identifier quoting is switched on before the first SHOW
    /// CREATE VIEW when the session has it off, together with the sql_mode,
    /// and both are switched back after the last view in one statement with
    /// the session's collation - also when a view could not be recreated, in
    /// which case the default database returns to the source as well.
    func testIdentifierQuotingIsForcedForShowCreateViewAndRestored() {
        let server = makeServer(quoteShowCreate: "0")
        XCTAssertNil(server.executor.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertEqual(statements(of: server, from: sessionQuery).prefix(3).map { $0 }, [sessionQuery, "SET sql_mode = 'STRICT_TRANS_TABLES', sql_quote_show_create = 1", "SHOW CREATE VIEW `shop`.`totals`"])
        XCTAssertEqual(server.statements.suffix(4), ["SET sql_mode = 'STRICT_TRANS_TABLES,NO_BACKSLASH_ESCAPES', sql_quote_show_create = 0, collation_connection = 'utf8mb4_0900_ai_ci'", restoreCheckQuery, checkQuery, "DROP DATABASE `shop`"])

        let failing = makeServer(quoteShowCreate: "0")
        failing.fail("CREATE ALGORITHM", with: "Access denied")
        XCTAssertNotNil(failing.executor.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertEqual(failing.statements.suffix(3), ["SET sql_mode = 'STRICT_TRANS_TABLES,NO_BACKSLASH_ESCAPES', sql_quote_show_create = 0, collation_connection = 'utf8mb4_0900_ai_ci'", restoreCheckQuery, "USE `shop`"])
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
        XCTAssertEqual(statements(of: server, from: "CREATE DATABASE"), [
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
        server.respond(to: privilegesQuery, rows: [])
        let description = try XCTUnwrap(server.executor.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertTrue(description.contains("Reading the objects of the database 'shop' failed: this account cannot list the database's routines completely (it needs SELECT on mysql.proc, or global SELECT or SHOW_ROUTINE). Nothing was changed."), description)
        XCTAssertTrue(onlyInspected(server), server.statements.joined(separator: "\n"))
        XCTAssertFalse(server.statements.contains { $0.hasPrefix("SELECT ROUTINE_NAME") }, "information_schema.ROUTINES is not trusted without the privilege")

        let denied = makeServer()
        denied.fail("SELECT name, type FROM mysql.proc", with: "SELECT command denied to user for table 'proc'")
        denied.respond(to: privilegesQuery, rows: [["SHOW_ROUTINE"]])
        denied.fail("SELECT ROUTINE_NAME", with: "SELECT command denied")
        let reason = try XCTUnwrap(denied.executor.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertTrue(reason.contains("Reading the objects of the database 'shop' failed: SELECT command denied Nothing"), reason)
        XCTAssertTrue(onlyInspected(denied), denied.statements.joined(separator: "\n"))

        // where the server folds case, its own folded names are needed to
        // recognise names it folds beyond ASCII; a failed or incomplete
        // answer refuses the rename instead of falling back to ASCII folding
        let unfolded = makeServer()
        unfolded.responses.removeAll { $0.matches("SELECT LOWER('shop'), LOWER('store')") }
        unfolded.fail("SELECT LOWER('shop'), LOWER('store')", with: "Lost connection to MySQL server during query")
        let unfoldedReason = try XCTUnwrap(unfolded.executor.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertTrue(unfoldedReason.contains("Reading the objects of the database 'shop' failed: Lost connection to MySQL server during query Nothing was changed."), unfoldedReason)
        XCTAssertTrue(onlyInspected(unfolded), unfolded.statements.joined(separator: "\n"))

        for incompleteRow in [[], ["shop", NSNull()]] as [[Any]] {
            let incomplete = makeServer()
            incomplete.responses.removeAll { $0.matches("SELECT LOWER('shop'), LOWER('store')") }
            incomplete.respond(to: "SELECT LOWER('shop'), LOWER('store')", rows: incompleteRow.isEmpty ? [] : [incompleteRow])
            let incompleteReason = try XCTUnwrap(incomplete.executor.rename("shop", to: "store", encoding: nil, collation: nil))
            XCTAssertTrue(incompleteReason.contains("Reading the objects of the database 'shop' failed: unknown error Nothing was changed."), incompleteReason)
            XCTAssertTrue(onlyInspected(incomplete), incomplete.statements.joined(separator: "\n"))
        }
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

    /// Verifies stored libraries (MySQL 9.2+, provided with the MLE
    /// component), which DROP DATABASE deletes with the source, refuse the
    /// rename: they are listed only where information_schema.LIBRARIES
    /// exists - looked up in information_schema.TABLES, not guessed from an
    /// error in the server's language - and trusted only for an account that
    /// sees every library (SHOW_ROUTINE, or a global SELECT without partial
    /// revokes); anything else, and a failing query, refuses before anything
    /// changes.
    func testLibrariesRefuseTheRenameOrFailClosed() throws {
        let listed = makeServer()
        listed.respond(to: librariesProbe, rows: [["LIBRARIES"]])
        listed.respond(to: privilegesQuery, rows: [["SHOW_ROUTINE"]])
        listed.respond(to: librariesQuery, rows: [["jslib"], ["mathlib"]])
        let description = try XCTUnwrap(listed.executor.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertTrue(description.contains("The database contains objects that Rename Database cannot move: library 'jslib', library 'mathlib'. Nothing was changed."), description)
        XCTAssertTrue(onlyInspected(listed), listed.statements.joined(separator: "\n"))
        XCTAssertTrue(listed.statements.contains("SELECT LIBRARY_NAME FROM information_schema.LIBRARIES WHERE LIBRARY_SCHEMA = 'shop' ORDER BY LIBRARY_NAME"), listed.statements.joined(separator: "\n"))

        for (partialRevokes, expected) in [("OFF", true), ("ON", false)] {
            let select = makeServer()
            select.respond(to: librariesProbe, rows: [["LIBRARIES"]])
            select.respond(to: privilegesQuery, rows: [["SELECT"]])
            select.respond(to: partialRevokesQuery, rows: [["partial_revokes", partialRevokes]])
            let outcome = select.executor.rename("shop", to: "store", encoding: nil, collation: nil)
            XCTAssertEqual(outcome == nil, expected, "partial_revokes = \(partialRevokes): \(outcome ?? "renamed")")
            XCTAssertEqual(select.statements.contains { $0.hasPrefix(librariesQuery) }, expected, select.statements.joined(separator: "\n"))
            if !expected {
                XCTAssertTrue(outcome?.contains("Reading the objects of the database 'shop' failed: this account cannot list the database's libraries completely (it needs global SELECT or SHOW_ROUTINE). Nothing was changed.") == true, outcome ?? "renamed")
                XCTAssertTrue(onlyInspected(select), select.statements.joined(separator: "\n"))
            }
        }

        let hidden = makeServer()
        hidden.respond(to: librariesProbe, rows: [["LIBRARIES"]])
        hidden.respond(to: privilegesQuery, rows: [])
        let hiddenReason = try XCTUnwrap(hidden.executor.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertTrue(hiddenReason.contains("cannot list the database's libraries completely"), hiddenReason)
        XCTAssertTrue(onlyInspected(hidden), hidden.statements.joined(separator: "\n"))

        let brokenProbe = makeServer()
        brokenProbe.fail(librariesProbe, with: "Lost connection to MySQL server during query")
        let probeReason = try XCTUnwrap(brokenProbe.executor.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertTrue(probeReason.contains("Reading the objects of the database 'shop' failed: Lost connection to MySQL server during query Nothing was changed."), probeReason)
        XCTAssertTrue(onlyInspected(brokenProbe), brokenProbe.statements.joined(separator: "\n"))

        let denied = makeServer()
        denied.respond(to: librariesProbe, rows: [["LIBRARIES"]])
        denied.respond(to: privilegesQuery, rows: [["SHOW_ROUTINE"]])
        denied.fail(librariesQuery, with: "SELECT command denied")
        let deniedReason = try XCTUnwrap(denied.executor.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertTrue(deniedReason.contains("Reading the objects of the database 'shop' failed: SELECT command denied Nothing was changed."), deniedReason)
        XCTAssertTrue(onlyInspected(denied), denied.statements.joined(separator: "\n"))
    }

    /// Verifies views in other databases that read from the source refuse
    /// the rename - they would stop working once it is dropped - found in
    /// information_schema.VIEW_TABLE_USAGE where the server has it (MySQL
    /// 8.0.13 and later) and by scanning the definitions in
    /// information_schema.VIEWS otherwise, and that the check fails closed
    /// for an account that cannot see every view or definition.
    func testViewsInOtherDatabasesReadingFromTheSourceRefuseTheRename() throws {
        let usage = makeServer()
        usage.respond(to: viewTableUsageQuery, rows: [["reporting", "proxy", "shop"], ["reporting", "proxy", "shop"], ["shop", "totals", "shop"], ["other", "folded", "SHOP"]])
        let description = try XCTUnwrap(usage.executor.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertEqual(description, "Views in other databases read from 'shop' (`reporting`.`proxy`, `other`.`folded`) and would stop working once it is renamed. Nothing was changed.")
        XCTAssertTrue(onlyInspected(usage), usage.statements.joined(separator: "\n"))
        XCTAssertFalse(usage.statements.contains(externalViewsQuery))

        // where the server keeps the case of names, another case is another database
        let exact = makeServer(lowerCaseTableNames: "0")
        exact.respond(to: viewTableUsageQuery, rows: [["other", "v", "SHOP"]])
        XCTAssertNil(exact.executor.rename("shop", to: "store", encoding: nil, collation: nil))

        // without VIEW_TABLE_USAGE (MariaDB, older MySQL) every definition is scanned
        let scan = makeServer()
        scan.respond(to: viewTableUsageProbe, rows: [])
        scan.respond(to: externalViewsQuery, rows: [
            ["reporting", "proxy", hex("select `shop`.`base`.`n` AS `n` from `shop`.`base`")],
            ["shop", "totals", hex("select sum(`shop`.`orders`.`total`) AS `t` from `shop`.`orders`")],
            ["clean", "near", hex("select `shopping`.`t`.`n` AS `n` from `shopping`.`t`")],
            ["hinted", "v", hex("select /*+ QB_NAME(`shop`.`x`) */ 'shop.x' AS `s`")]
        ])
        let scanned = try XCTUnwrap(scan.executor.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertEqual(scanned, "Views in other databases read from 'shop' (`reporting`.`proxy`) and would stop working once it is renamed. Nothing was changed.")
        XCTAssertTrue(onlyInspected(scan), scan.statements.joined(separator: "\n"))
        XCTAssertFalse(scan.statements.contains { $0.hasPrefix(viewTableUsageQuery) })

        let noHits = makeServer()
        noHits.respond(to: viewTableUsageProbe, rows: [])
        noHits.respond(to: externalViewsQuery, rows: [["clean", "near", hex("select 1 AS `n`")]])
        XCTAssertNil(noHits.executor.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertEqual(noHits.statements.last, "DROP DATABASE `shop`")

        let unlistable = "Reading the objects of the database 'shop' failed: this account cannot list the views of other databases completely (it needs global SELECT, and SHOW VIEW where information_schema.VIEW_TABLE_USAGE is missing). Nothing was changed."

        // the scan needs SHOW VIEW to see the definitions, and an empty one may be hidden
        let noShowView = makeServer()
        noShowView.respond(to: viewTableUsageProbe, rows: [])
        noShowView.respond(to: privilegesQuery, rows: [["SELECT"]])
        XCTAssertEqual(noShowView.executor.rename("shop", to: "store", encoding: nil, collation: nil), unlistable)
        XCTAssertFalse(noShowView.statements.contains(externalViewsQuery))

        let hidden = makeServer()
        hidden.respond(to: viewTableUsageProbe, rows: [])
        hidden.respond(to: externalViewsQuery, rows: [["reporting", "proxy", ""]])
        XCTAssertEqual(hidden.executor.rename("shop", to: "store", encoding: nil, collation: nil), unlistable)
        XCTAssertTrue(onlyInspected(hidden), hidden.statements.joined(separator: "\n"))

        // a global SELECT that partial revokes may limit, or none at all, proves nothing
        for (privileges, partialRevokes) in [([["SELECT"], ["SHOW VIEW"]], "ON"), ([["SHOW VIEW"]], "OFF")] as [([[Any]], String)] {
            let limited = makeServer()
            limited.respond(to: privilegesQuery, rows: privileges)
            limited.respond(to: partialRevokesQuery, rows: [["partial_revokes", partialRevokes]])
            XCTAssertEqual(limited.executor.rename("shop", to: "store", encoding: nil, collation: nil), unlistable, "partial_revokes = \(partialRevokes)")
            XCTAssertFalse(limited.statements.contains { $0.hasPrefix(viewTableUsageQuery) }, limited.statements.joined(separator: "\n"))
            XCTAssertTrue(onlyInspected(limited), limited.statements.joined(separator: "\n"))
        }

        let brokenProbe = makeServer()
        brokenProbe.fail(viewTableUsageProbe, with: "Lost connection to MySQL server during query")
        XCTAssertEqual(brokenProbe.executor.rename("shop", to: "store", encoding: nil, collation: nil), "Reading the objects of the database 'shop' failed: Lost connection to MySQL server during query Nothing was changed.")
        XCTAssertTrue(onlyInspected(brokenProbe), brokenProbe.statements.joined(separator: "\n"))
    }

    /// Verifies a value the connection cannot quote - it hands back none
    /// while closed or re-established - never goes into a statement: before
    /// anything changes it stops the rename as a failed inspection, a view
    /// whose collation cannot be quoted fails like a failed CREATE, and a
    /// session collation that cannot be quoted for its restore counts as not
    /// restored.
    func testValuesTheConnectionCannotQuoteAreNeverSent() throws {
        let quoteFailure = "the connection could not quote a value for a statement (it was closed or is being re-established)."

        let source = makeServer()
        source.unquotable = ["shop"]
        XCTAssertEqual(source.executor.rename("shop", to: "store", encoding: nil, collation: nil), "Reading the objects of the database 'shop' failed: \(quoteFailure) Nothing was changed.")
        XCTAssertEqual(source.statements, [])

        let escape = makeServer()
        escape.unquotable = ["\\"]
        let escapeReason = try XCTUnwrap(escape.executor.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertTrue(escapeReason.contains("failed: \(quoteFailure) Nothing was changed."), escapeReason)
        XCTAssertTrue(onlyInspected(escape), escape.statements.joined(separator: "\n"))

        let mode = makeServer()
        mode.unquotable = ["STRICT_TRANS_TABLES"]
        let modeReason = try XCTUnwrap(mode.executor.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertTrue(modeReason.contains("failed: \(quoteFailure) Nothing was changed."), modeReason)
        XCTAssertTrue(onlyInspected(mode), mode.statements.joined(separator: "\n"))

        let viewCollation = makeServer()
        viewCollation.unquotable = ["utf8mb4_general_ci"]
        let viewExecutor = viewCollation.executor
        let viewReason = try XCTUnwrap(viewExecutor.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertTrue(viewReason.contains("Moving view 'totals' failed: \(quoteFailure) The objects moved so far are in 'store'; 'shop' was not dropped."), viewReason)
        XCTAssertFalse(viewCollation.statements.contains { $0.hasPrefix("CREATE ALGORITHM") || $0.hasPrefix("DROP") }, viewCollation.statements.joined(separator: "\n"))
        XCTAssertFalse(viewExecutor.sessionSettingsNotRestored)

        let sessionCollation = makeServer()
        sessionCollation.unquotable = ["utf8mb4_0900_ai_ci"]
        let sessionExecutor = sessionCollation.executor
        _ = sessionExecutor.rename("shop", to: "store", encoding: nil, collation: nil)
        XCTAssertTrue(sessionExecutor.sessionSettingsNotRestored)
        XCTAssertTrue(sessionCollation.statements.contains("SET sql_mode = 'STRICT_TRANS_TABLES,NO_BACKSLASH_ESCAPES'"), sessionCollation.statements.joined(separator: "\n"))
        XCTAssertFalse(sessionCollation.statements.contains { $0.contains("utf8mb4_0900_ai_ci'") && $0.hasPrefix("SET ") }, sessionCollation.statements.joined(separator: "\n"))
    }

    /// Verifies routines come from mysql.proc where it exists - which lists
    /// every routine, also on a MariaDB whose data directory was never run
    /// through mysql_upgrade - and from information_schema.ROUTINES only on
    /// a server without that table (MySQL 8) for an account whose global
    /// privileges provably cover every routine: SHOW_ROUTINE, or SELECT
    /// unless the server has partial revokes on; a schema-level grant alone
    /// never counts. Events of an un-upgraded server come from mysql.event.
    /// Such a server neither blocks the rename nor loses a routine unseen.
    func testRoutinesComeFromMySQLProcOrACompleteInformationSchema() throws {
        let mysql8 = makeServer()
        mysql8.fail("SELECT name, type FROM mysql.proc", with: "Table 'mysql.proc' doesn't exist")
        mysql8.respond(to: privilegesQuery, rows: [["SHOW_ROUTINE"]])
        mysql8.respond(to: partialRevokesQuery, rows: [["partial_revokes", "ON"]])
        mysql8.respond(to: "SELECT ROUTINE_NAME, ROUTINE_TYPE FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA = 'shop'", rows: [["cleanup", "PROCEDURE"]])
        let refused = try XCTUnwrap(mysql8.executor.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertTrue(refused.contains("procedure 'cleanup'"), refused)
        XCTAssertTrue(onlyInspected(mysql8), mysql8.statements.joined(separator: "\n"))
        XCTAssertFalse(mysql8.statements.contains { $0.contains("SCHEMA_PRIVILEGES") }, "schema-level grants say nothing about which routines the server shows")

        // a global SELECT counts unless partial revokes are on; a server
        // without the variable (MariaDB, MySQL up to 5.7) has none
        for (partialRevokes, expected) in [("OFF", true), ("0", true), (nil, true), ("ON", false), ("1", false)] as [(String?, Bool)] {
            let select = makeServer()
            select.fail("SELECT name, type FROM mysql.proc", with: "Table 'mysql.proc' doesn't exist")
            select.respond(to: privilegesQuery, rows: [["SELECT"]])
            if let partialRevokes {
                select.respond(to: partialRevokesQuery, rows: [["partial_revokes", partialRevokes]])
            } else {
                select.respond(to: partialRevokesQuery, rows: [])
            }
            let outcome = select.executor.rename("shop", to: "store", encoding: nil, collation: nil)
            XCTAssertEqual(outcome == nil, expected, "partial_revokes = \(partialRevokes ?? "unknown"): \(outcome ?? "renamed")")
            XCTAssertEqual(select.statements.contains { $0.hasPrefix("SELECT ROUTINE_NAME") }, expected)
        }

        // only "unknown variable" means no partial revokes; any other failure
        // leaves the setting unknown, and a global SELECT is not trusted then
        let broken = makeServer()
        broken.fail("SELECT name, type FROM mysql.proc", with: "Table 'mysql.proc' doesn't exist")
        broken.respond(to: privilegesQuery, rows: [["SELECT"]])
        broken.fail(partialRevokesQuery, with: "Lost connection to MySQL server during query")
        let lost = try XCTUnwrap(broken.executor.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertTrue(lost.contains("Reading the objects of the database 'shop' failed: Lost connection to MySQL server during query Nothing was changed."), lost)
        XCTAssertTrue(onlyInspected(broken), broken.statements.joined(separator: "\n"))

        // SHOW_ROUTINE lists the routines without that setting; the partial
        // revokes themselves, checked with the grants, still need it, and the
        // setting is read once
        let routineViewer = makeServer()
        routineViewer.fail("SELECT name, type FROM mysql.proc", with: "Table 'mysql.proc' doesn't exist")
        routineViewer.respond(to: privilegesQuery, rows: [["SHOW_ROUTINE"]])
        routineViewer.fail(partialRevokesQuery, with: "Access denied")
        let unknown = try XCTUnwrap(routineViewer.executor.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertTrue(routineViewer.statements.contains { $0.hasPrefix("SELECT ROUTINE_NAME") }, routineViewer.statements.joined(separator: "\n"))
        XCTAssertTrue(unknown.contains("Reading the objects of the database 'shop' failed: Access denied Nothing was changed."), unknown)
        XCTAssertEqual(routineViewer.statements.filter { $0 == partialRevokesQuery }.count, 1)
        XCTAssertTrue(onlyInspected(routineViewer), routineViewer.statements.joined(separator: "\n"))

        // EXECUTE on the database alone says nothing about which routines the server shows
        let schemaGrant = makeServer()
        schemaGrant.fail("SELECT name, type FROM mysql.proc", with: "Table 'mysql.proc' doesn't exist")
        schemaGrant.respond(to: privilegesQuery, rows: [])
        let reason = try XCTUnwrap(schemaGrant.executor.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertTrue(reason.contains("cannot list the database's routines completely"), reason)
        XCTAssertTrue(onlyInspected(schemaGrant), schemaGrant.statements.joined(separator: "\n"))

        let mariadb = makeServer()
        mariadb.respond(to: "SELECT name, type FROM mysql.proc WHERE LOWER(db) = LOWER('shop')", rows: [["cleanup", "PROCEDURE"]])
        mariadb.fail("SHOW EVENTS FROM `shop`", with: "Column count of mysql.event is wrong")
        mariadb.respond(to: "SELECT db, name FROM mysql.event WHERE LOWER(db) = LOWER('shop')", rows: [["shop", "nightly"]])
        let description = try XCTUnwrap(mariadb.executor.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertTrue(description.contains("procedure 'cleanup', event 'nightly'"), description)
        XCTAssertTrue(onlyInspected(mariadb), mariadb.statements.joined(separator: "\n"))
        XCTAssertFalse(mariadb.statements.contains { $0.hasPrefix("SELECT ROUTINE_NAME") || $0.hasPrefix(privilegesQuery) }, "mysql.proc is authoritative where it can be read")

        let clean = makeServer()
        clean.respond(to: "SELECT name, type FROM mysql.proc WHERE LOWER(db) = LOWER('shop')", rows: [])
        XCTAssertNil(clean.executor.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertEqual(clean.statements.last, "DROP DATABASE `shop`")

        // a server that keeps the case of names stores them as given, so the
        // mysql tables are matched exactly and no folded form is asked for
        let exact = makeServer(lowerCaseTableNames: "0")
        XCTAssertNil(exact.executor.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertTrue(exact.statements.contains("SELECT name, type FROM mysql.proc WHERE db = 'shop' ORDER BY name"), exact.statements.joined(separator: "\n"))
        XCTAssertFalse(exact.statements.contains { $0.hasPrefix("SELECT LOWER(") }, exact.statements.joined(separator: "\n"))
        XCTAssertEqual(exact.statements.prefix(10).filter { $0.hasPrefix("SELECT ") || $0.hasPrefix("SHOW EVENTS ") || $0.hasPrefix("SHOW VARIABLES ") }.count, 10)
    }

    /// Verifies privileges granted on the source database or its tables or
    /// views - a database grant stays with the old name, and neither RENAME
    /// TABLE nor a recreated view carries a table grant along - refuse the
    /// rename before anything moves, naming grant and account (five at
    /// most); they come from mysql.db (whose Db column is a pattern the
    /// source is matched against, as the server does), mysql.tables_priv and
    /// mysql.columns_priv, or from information_schema for a global SELECT
    /// that no partial revoke limits, and anything else refuses the rename
    /// as well.
    func testPrivilegesGrantedOnTablesOrViewsRefuseTheRename() throws {
        let databasePriv = "SELECT Db, User, Host FROM mysql.db"
        let tablesPriv = "SELECT Table_name, User, Host FROM mysql.tables_priv"
        let columnsPriv = "SELECT Table_name, User, Host FROM mysql.columns_priv"

        let granted = makeServer()
        granted.respond(to: databasePriv, rows: [["shop", "app", "%"]])
        granted.respond(to: tablesPriv, rows: [["orders", "app", "%"], ["orders", "app", "%"], ["customer_totals", "reader", "localhost"]])
        let description = try XCTUnwrap(granted.executor.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertTrue(description.contains("The database has privileges granted on it, its tables or its views, or partially revoked on it (`shop`.* for 'app'@'%', `orders` for 'app'@'%', `customer_totals` for 'reader'@'localhost'), which Rename Database cannot move. Nothing was changed."), description)
        XCTAssertTrue(onlyInspected(granted), granted.statements.joined(separator: "\n"))

        // with partial revokes on, a restriction for the source - kept in
        // mysql.user's JSON attributes, nowhere in information_schema - refuses
        // as well, listed after the grants; the source is searched as an
        // exactly matching LIKE pattern
        let restrictionsQuery = "SELECT User, Host FROM mysql.user"
        let restricted = makeServer()
        restricted.respond(to: databasePriv, rows: [["shop", "app", "%"]])
        restricted.respond(to: partialRevokesQuery, rows: [["partial_revokes", "ON"]])
        restricted.respond(to: restrictionsQuery, rows: [["reader", "%"], ["reader", "%"], ["auditor", "localhost"]])
        let restrictedDescription = try XCTUnwrap(restricted.executor.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertTrue(restrictedDescription.contains("(`shop`.* for 'app'@'%', partial revoke on `shop`.* for 'reader'@'%', partial revoke on `shop`.* for 'auditor'@'localhost')"), restrictedDescription)
        XCTAssertTrue(restricted.statements.contains("SELECT User, Host FROM mysql.user WHERE JSON_SEARCH(User_attributes, 'one', 'shop', '!', '$.Restrictions[*].Database') IS NOT NULL ORDER BY User, Host"), restricted.statements.joined(separator: "\n"))
        XCTAssertTrue(onlyInspected(restricted), restricted.statements.joined(separator: "\n"))
        // with partial revokes on, `_` and `%` in a database grant are literal
        // characters, so the grant is compared for equality instead of as a pattern
        XCTAssertTrue(restricted.statements.contains("SELECT Db, User, Host FROM mysql.db WHERE LOWER(Db) = LOWER('shop') ORDER BY Db, User, Host"), restricted.statements.joined(separator: "\n"))

        // With partial revokes on, a global SELECT may itself be restricted,
        // so the views of other databases cannot be shown to be complete and
        // a rename that passes the privilege checks is still refused, before
        // anything changes, by the check for views reading from the source.
        let viewsUnlistable = "Reading the objects of the database 'shop' failed: this account cannot list the views of other databases completely (it needs global SELECT, and SHOW VIEW where information_schema.VIEW_TABLE_USAGE is missing). Nothing was changed."

        let literal = makeServer(lowerCaseTableNames: "0")
        literal.respond(to: partialRevokesQuery, rows: [["partial_revokes", "ON"]])
        XCTAssertEqual(literal.executor.rename("shop", to: "store", encoding: nil, collation: nil), viewsUnlistable)
        XCTAssertTrue(literal.statements.contains("SELECT Db, User, Host FROM mysql.db WHERE Db = 'shop' ORDER BY Db, User, Host"), literal.statements.joined(separator: "\n"))
        XCTAssertFalse(literal.statements.contains { $0.contains("LIKE Db") }, literal.statements.joined(separator: "\n"))

        let unrestricted = makeServer()
        unrestricted.respond(to: partialRevokesQuery, rows: [["partial_revokes", "ON"]])
        XCTAssertEqual(unrestricted.executor.rename("shop", to: "store", encoding: nil, collation: nil), viewsUnlistable)
        XCTAssertTrue(unrestricted.statements.contains { $0.hasPrefix(restrictionsQuery) }, unrestricted.statements.joined(separator: "\n"))
        XCTAssertTrue(onlyInspected(unrestricted), unrestricted.statements.joined(separator: "\n"))

        let unreadableUser = makeServer()
        unreadableUser.respond(to: partialRevokesQuery, rows: [["partial_revokes", "ON"]])
        unreadableUser.fail(restrictionsQuery, with: "SELECT command denied to user for table 'user'")
        let unreadableReason = try XCTUnwrap(unreadableUser.executor.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertTrue(unreadableReason.contains("Reading the objects of the database 'shop' failed: this account cannot list the privileges granted on the database, its tables and views (it needs SELECT on mysql.db, mysql.tables_priv and mysql.user, or global SELECT). Nothing was changed."), unreadableReason)
        XCTAssertTrue(onlyInspected(unreadableUser), unreadableUser.statements.joined(separator: "\n"))

        // off, or a server without the setting: no restrictions, nothing asked
        let off = makeServer()
        off.respond(to: partialRevokesQuery, rows: [["partial_revokes", "OFF"]])
        XCTAssertNil(off.executor.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertFalse(off.statements.contains { $0.contains("mysql.user") }, off.statements.joined(separator: "\n"))

        // where the server folds case, its own folded form of the source is searched too
        let foldedSource = makeServer()
        foldedSource.responses.removeAll { $0.matches("SELECT LOWER('shop'), LOWER('store')") }
        foldedSource.respond(to: "SELECT LOWER('shop'), LOWER('store')", rows: [["ſhop", "store"]])
        foldedSource.respond(to: partialRevokesQuery, rows: [["partial_revokes", "ON"]])
        XCTAssertEqual(foldedSource.executor.rename("shop", to: "store", encoding: nil, collation: nil), viewsUnlistable)
        XCTAssertTrue(foldedSource.statements.contains("SELECT User, Host FROM mysql.user WHERE JSON_SEARCH(User_attributes, 'one', 'shop', '!', '$.Restrictions[*].Database') IS NOT NULL OR JSON_SEARCH(User_attributes, 'one', 'ſhop', '!', '$.Restrictions[*].Database') IS NOT NULL ORDER BY User, Host"), foldedSource.statements.joined(separator: "\n"))

        XCTAssertEqual(SADatabaseRenameExecutor.likePattern(matchingExactly: "my_shop"), "my!_shop")
        XCTAssertEqual(SADatabaseRenameExecutor.likePattern(matchingExactly: "100%!"), "100!%!!")
        XCTAssertEqual(SADatabaseRenameExecutor.likePattern(matchingExactly: "shop"), "shop")

        // a grant on the database names a pattern; the source is the value it is matched against
        let pattern = makeServer()
        pattern.respond(to: databasePriv, rows: [["shop%", "app", "%"]])
        let patternDescription = try XCTUnwrap(pattern.executor.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertTrue(patternDescription.contains("(`shop%`.* for 'app'@'%')"), patternDescription)
        // the backslash is named as the escape character (the connection quotes
        // it for the session's sql_mode; the fake server just wraps it), so a
        // grant written `shop\_1` covers `shop_1` alone under every sql_mode -
        // only the statement's text can be checked here
        XCTAssertTrue(pattern.statements.contains("SELECT Db, User, Host FROM mysql.db WHERE LOWER('shop') LIKE LOWER(Db) ESCAPE '\\' ORDER BY Db, User, Host"), pattern.statements.joined(separator: "\n"))
        XCTAssertTrue(onlyInspected(pattern), pattern.statements.joined(separator: "\n"))

        let columns = makeServer()
        columns.respond(to: columnsPriv, rows: [["orders", "reader", "localhost"]])
        let columnDescription = try XCTUnwrap(columns.executor.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertTrue(columnDescription.contains("(`orders` for 'reader'@'localhost')"), columnDescription)

        let many = makeServer()
        many.respond(to: tablesPriv, rows: (1...6).map { ["t\($0)", "u", "%"] })
        let manyDescription = try XCTUnwrap(many.executor.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertTrue(manyDescription.contains("`t5` for 'u'@'%', …)"), manyDescription)
        XCTAssertFalse(manyDescription.contains("`t6`"), manyDescription)

        // without the mysql tables, information_schema stands in for a global SELECT
        let viaSchema = makeServer()
        viaSchema.fail(tablesPriv, with: "SELECT command denied to user for table 'tables_priv'")
        viaSchema.respond(to: privilegesQuery, rows: [["SELECT"]])
        viaSchema.respond(to: partialRevokesQuery, rows: [["partial_revokes", "OFF"]])
        viaSchema.respond(to: "SELECT TABLE_SCHEMA, GRANTEE FROM information_schema.SCHEMA_PRIVILEGES WHERE LOWER('shop') LIKE LOWER(TABLE_SCHEMA) ESCAPE '\\' ORDER BY TABLE_SCHEMA, GRANTEE", rows: [["shop%", "'app'@'%'"]])
        viaSchema.respond(to: "SELECT TABLE_NAME, GRANTEE FROM information_schema.TABLE_PRIVILEGES WHERE LOWER(TABLE_SCHEMA) = LOWER('shop')", rows: [["orders", "'app'@'%'"]])
        let schemaDescription = try XCTUnwrap(viaSchema.executor.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertTrue(schemaDescription.contains("(`shop%`.* for 'app'@'%', `orders` for 'app'@'%')"), schemaDescription)
        XCTAssertTrue(viaSchema.statements.contains { $0.hasPrefix("SELECT TABLE_NAME, GRANTEE FROM information_schema.COLUMN_PRIVILEGES") }, viaSchema.statements.joined(separator: "\n"))

        // mysql.db alone being unreadable takes the same way, and without a
        // global SELECT refuses; SHOW_ROUTINE says nothing about grants, and a
        // partial revoke may hide them from a global SELECT
        for (unreadable, privileges) in [(databasePriv, [["SELECT"]]), (tablesPriv, [["SHOW_ROUTINE"]]), (tablesPriv, [["SELECT"]])] {
            let refused = makeServer()
            refused.fail(unreadable, with: "SELECT command denied to user for table 'db'")
            refused.respond(to: privilegesQuery, rows: privileges)
            refused.respond(to: partialRevokesQuery, rows: [["partial_revokes", "ON"]])
            let reason = try XCTUnwrap(refused.executor.rename("shop", to: "store", encoding: nil, collation: nil))
            XCTAssertTrue(reason.contains("Reading the objects of the database 'shop' failed: this account cannot list the privileges granted on the database, its tables and views (it needs SELECT on mysql.db, mysql.tables_priv and mysql.user, or global SELECT). Nothing was changed."), reason)
            XCTAssertFalse(refused.statements.contains { $0.contains("information_schema.SCHEMA_PRIVILEGES") || $0.contains("information_schema.TABLE_PRIVILEGES") }, refused.statements.joined(separator: "\n"))
        }

        // a server that keeps the case of names is matched exactly
        let exact = makeServer(lowerCaseTableNames: "0")
        XCTAssertNil(exact.executor.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertTrue(exact.statements.contains("SELECT Db, User, Host FROM mysql.db WHERE 'shop' LIKE Db ESCAPE '\\' ORDER BY Db, User, Host"), exact.statements.joined(separator: "\n"))
        XCTAssertTrue(exact.statements.contains("SELECT Table_name, User, Host FROM mysql.tables_priv WHERE Db = 'shop' ORDER BY Table_name, User, Host"), exact.statements.joined(separator: "\n"))
    }

    /// Verifies privileges that already exist for the new name refuse the
    /// rename before anything changes: MySQL keeps grants for databases
    /// that do not exist (left by a dropped database of that name, or
    /// granted ahead of time), and they would cover the moved tables and
    /// views once the target is created. The new name goes through the same
    /// checks as the source - database patterns, table and column grants,
    /// partial revokes as given and as the server folds the name, and
    /// information_schema for a global SELECT without partial revokes.
    func testPrivilegesOnTheNewNameRefuseTheRename() throws {
        let pattern = makeServer()
        pattern.respond(to: "SELECT Db, User, Host FROM mysql.db WHERE LOWER('store') LIKE LOWER(Db) ESCAPE '\\'", rows: [["st%", "app", "%"]])
        let description = try XCTUnwrap(pattern.executor.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertEqual(description, "Privileges are already granted or partially revoked for the new name 'store' (`st%`.* for 'app'@'%'); the moved tables and views would come under them. Nothing was changed.")
        XCTAssertTrue(onlyInspected(pattern), pattern.statements.joined(separator: "\n"))

        let leftover = makeServer()
        leftover.respond(to: "SELECT Table_name, User, Host FROM mysql.columns_priv WHERE LOWER(Db) = LOWER('store')", rows: [["orders", "reader", "localhost"]])
        let leftoverDescription = try XCTUnwrap(leftover.executor.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertTrue(leftoverDescription.contains("the new name 'store' (`orders` for 'reader'@'localhost')"), leftoverDescription)
        XCTAssertTrue(onlyInspected(leftover), leftover.statements.joined(separator: "\n"))

        let restricted = makeServer()
        restricted.respond(to: "SELECT LOWER('shop'), LOWER('Store')", rows: [["shop", "store"]])
        restricted.respond(to: partialRevokesQuery, rows: [["partial_revokes", "ON"]])
        restricted.respond(to: "SELECT User, Host FROM mysql.user WHERE JSON_SEARCH(User_attributes, 'one', 'Store'", rows: [["reader", "%"]])
        let restrictedDescription = try XCTUnwrap(restricted.executor.rename("shop", to: "Store", encoding: nil, collation: nil))
        XCTAssertTrue(restrictedDescription.contains("the new name 'Store' (partial revoke on `Store`.* for 'reader'@'%')"), restrictedDescription)
        XCTAssertTrue(restricted.statements.contains("SELECT User, Host FROM mysql.user WHERE JSON_SEARCH(User_attributes, 'one', 'Store', '!', '$.Restrictions[*].Database') IS NOT NULL OR JSON_SEARCH(User_attributes, 'one', 'store', '!', '$.Restrictions[*].Database') IS NOT NULL ORDER BY User, Host"), restricted.statements.joined(separator: "\n"))
        // with partial revokes on, a database grant is literal for the new name as well
        XCTAssertTrue(restricted.statements.contains("SELECT Db, User, Host FROM mysql.db WHERE LOWER(Db) = LOWER('Store') ORDER BY Db, User, Host"), restricted.statements.joined(separator: "\n"))
        XCTAssertTrue(onlyInspected(restricted), restricted.statements.joined(separator: "\n"))

        let viaSchema = makeServer()
        viaSchema.fail("SELECT Db, User, Host FROM mysql.db", with: "SELECT command denied to user for table 'db'")
        viaSchema.respond(to: privilegesQuery, rows: [["SELECT"]])
        viaSchema.respond(to: partialRevokesQuery, rows: [["partial_revokes", "OFF"]])
        viaSchema.respond(to: "SELECT TABLE_SCHEMA, GRANTEE FROM information_schema.SCHEMA_PRIVILEGES WHERE LOWER('store') LIKE LOWER(TABLE_SCHEMA) ESCAPE '\\'", rows: [["store", "'app'@'%'"]])
        let schemaDescription = try XCTUnwrap(viaSchema.executor.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertTrue(schemaDescription.contains("the new name 'store' (`store`.* for 'app'@'%')"), schemaDescription)
        XCTAssertTrue(onlyInspected(viaSchema), viaSchema.statements.joined(separator: "\n"))

        // grants on the source are reported first; the new name is still asked
        let both = makeServer()
        both.respond(to: "SELECT Db, User, Host FROM mysql.db WHERE LOWER('shop') LIKE LOWER(Db) ESCAPE '\\'", rows: [["shop", "app", "%"]])
        both.respond(to: "SELECT Db, User, Host FROM mysql.db WHERE LOWER('store') LIKE LOWER(Db) ESCAPE '\\'", rows: [["store", "app", "%"]])
        let bothDescription = try XCTUnwrap(both.executor.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertTrue(bothDescription.hasPrefix("The database has privileges granted on it"), bothDescription)
        XCTAssertTrue(onlyInspected(both), both.statements.joined(separator: "\n"))
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
        XCTAssertEqual(server.statements.suffix(2), ["SET sql_mode = 'STRICT_TRANS_TABLES,NO_BACKSLASH_ESCAPES'", restoreCheckQuery])
    }

    /// Verifies the session's collation and sql_mode are restored together
    /// even when the CREATE VIEW fails, the default database returns to the
    /// source, and the failure is reported with the server's message.
    func testSessionIsRestoredAfterFailedCreateView() throws {
        let server = makeServer()
        server.fail("CREATE ALGORITHM", with: "Access denied for CREATE VIEW")
        let description = try XCTUnwrap(server.executor.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertTrue(description.contains("Moving view 'totals' failed: Access denied for CREATE VIEW"), description)
        XCTAssertEqual(server.statements.filter { $0.hasPrefix("SET ") }, [
            "SET sql_mode = 'STRICT_TRANS_TABLES'",
            "SET collation_connection = 'utf8mb4_general_ci'",
            "SET sql_mode = 'STRICT_TRANS_TABLES,NO_BACKSLASH_ESCAPES', collation_connection = 'utf8mb4_0900_ai_ci'"
        ])
        XCTAssertFalse(server.statements.contains { $0.hasPrefix("DROP") })
        XCTAssertEqual(server.statements.last, "USE `shop`")
    }

    /// Verifies the settings changed for the views are read back after every
    /// restore - on the early ways out too, where no later check runs - and
    /// that a restore the server refuses or does not show is tried once more
    /// and then reported, while one it shows keeps the report clear.
    func testSessionSettingsRestoreIsVerifiedOnEveryWayOut() throws {
        let restore = "SET sql_mode = 'STRICT_TRANS_TABLES,NO_BACKSLASH_ESCAPES'"
        let readBack = restoreCheckQuery

        // a failed SHOW CREATE VIEW whose restoring SET is refused
        let refused = makeServer()
        refused.responses.removeAll { $0.matches(showCreateViewPrefix + "`totals`") }
        refused.fail(showCreateViewPrefix, with: "SHOW VIEW command denied")
        refused.fail(restore, with: "Lost connection to MySQL server during query")
        let refusedExecutor = refused.executor
        XCTAssertNotNil(refusedExecutor.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertTrue(refusedExecutor.sessionSettingsNotRestored)
        XCTAssertEqual(refused.statements.filter { $0 == restore }.count, 2, refused.statements.joined(separator: "\n"))
        XCTAssertFalse(refused.statements.contains(restoreCheckQuery))

        // a failed CREATE DATABASE whose restore the server does not show
        let unshown = makeServer()
        unshown.fail("CREATE DATABASE", with: "Access denied")
        unshown.responses.insert(({ $0 == readBack }, SADatabaseRenameStatementResult(rows: [["STRICT_TRANS_TABLES", "1", "utf8mb4_0900_ai_ci"]])), at: 0)
        let unshownExecutor = unshown.executor
        XCTAssertNotNil(unshownExecutor.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertTrue(unshownExecutor.sessionSettingsNotRestored)
        XCTAssertEqual(unshown.statements.filter { $0 == restoreCheckQuery }.count, 2, unshown.statements.joined(separator: "\n"))

        // identifier quoting that stays on after the restore counts as well
        let quoting = makeServer(quoteShowCreate: "0")
        quoting.responses.removeAll { $0.matches(showCreateViewPrefix + "`totals`") }
        quoting.fail(showCreateViewPrefix, with: "SHOW VIEW command denied")
        quoting.responses.insert(({ $0 == readBack }, SADatabaseRenameStatementResult(rows: [["STRICT_TRANS_TABLES,NO_BACKSLASH_ESCAPES", "1", "utf8mb4_0900_ai_ci"]])), at: 0)
        let quotingExecutor = quoting.executor
        XCTAssertNotNil(quotingExecutor.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertTrue(quotingExecutor.sessionSettingsNotRestored)

        // a failed table move and a failed USE with the restore shown
        let table = makeServer(tables: [["a", "BASE TABLE"], ["b", "BASE TABLE"], ["totals", "VIEW"]])
        table.fail("RENAME TABLE `shop`.`b`", with: "Access denied")
        let tableExecutor = table.executor
        XCTAssertNotNil(tableExecutor.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertFalse(tableExecutor.sessionSettingsNotRestored)
        XCTAssertEqual(table.statements.suffix(2), [restore, restoreCheckQuery])

        let use = makeServer()
        use.fail("USE `store`", with: "Access denied")
        let useExecutor = use.executor
        XCTAssertNotNil(useExecutor.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertFalse(useExecutor.sessionSettingsNotRestored)
        XCTAssertEqual(use.statements.suffix(2), [restore, restoreCheckQuery])

        // a complete rename, and one without settings to restore
        let done = makeServer()
        let doneExecutor = done.executor
        XCTAssertNil(doneExecutor.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertFalse(doneExecutor.sessionSettingsNotRestored)

        let tablesOnly = makeServer(tables: [["orders", "BASE TABLE"]])
        tablesOnly.fail("CREATE DATABASE", with: "Access denied")
        let tablesOnlyExecutor = tablesOnly.executor
        XCTAssertNotNil(tablesOnlyExecutor.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertFalse(tablesOnlyExecutor.sessionSettingsNotRestored)
        XCTAssertFalse(tablesOnly.statements.contains(restoreCheckQuery))
    }

    /// Verifies a view selecting from a view listed after it is created after
    /// that view, in one pass and without a failed attempt: the definitions
    /// read up front tell which views each one reads from.
    func testViewsAreCreatedAfterTheViewsTheyReadFrom() {
        let server = makeServer(tables: [["orders", "BASE TABLE"], ["a_report", "VIEW"], ["z_base", "VIEW"]])
        server.respond(to: showCreateViewPrefix + "`a_report`", rows: [["a_report", "CREATE VIEW `a_report` AS select `shop`.`z_base`.`n` AS `n` from `shop`.`z_base`", "utf8mb4", "utf8mb4_general_ci"]])
        server.respond(to: showCreateViewPrefix + "`z_base`", rows: [["z_base", "CREATE VIEW `z_base` AS select count(0) AS `n` from `shop`.`orders`", "utf8mb4", "utf8mb4_general_ci"]])
        server.responses.insert(({ [unowned server] in $0.hasPrefix("CREATE VIEW `store`.`a_report`") && !server.createdViews.contains("z_base") }, SADatabaseRenameStatementResult(error: "Table 'store.z_base' doesn't exist")), at: 0)
        server.responses.append(({ [unowned server] statement in
            if statement.hasPrefix("CREATE VIEW `store`.`z_base`") { server.createdViews.insert("z_base") }
            return false
        }, SADatabaseRenameStatementResult(rows: [])))

        XCTAssertNil(server.executor.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertEqual(server.statements.filter { $0.hasPrefix("CREATE VIEW") }, [
            "CREATE VIEW `store`.`z_base` AS select count(0) AS `n` from `store`.`orders`",
            "CREATE VIEW `store`.`a_report` AS select `store`.`z_base`.`n` AS `n` from `store`.`z_base`"
        ])
        XCTAssertEqual(server.statements.last, "DROP DATABASE `shop`")

        // a chain in the reverse of information_schema's order, with
        // unqualified references as MariaDB prints them, takes one statement per view
        let chain = makeServer(tables: [["orders", "BASE TABLE"], ["a_top", "VIEW"], ["b_mid", "VIEW"], ["c_leaf", "VIEW"]])
        chain.respond(to: showCreateViewPrefix + "`a_top`", rows: [["a_top", "CREATE VIEW `a_top` AS select `b_mid`.`n` AS `n` from `b_mid`", "utf8mb4", "utf8mb4_general_ci"]])
        chain.respond(to: showCreateViewPrefix + "`b_mid`", rows: [["b_mid", "CREATE VIEW `b_mid` AS select `c_leaf`.`n` AS `n` from `c_leaf`", "utf8mb4", "utf8mb4_general_ci"]])
        chain.respond(to: showCreateViewPrefix + "`c_leaf`", rows: [["c_leaf", "CREATE VIEW `c_leaf` AS select count(0) AS `n` from `orders`", "utf8mb4", "utf8mb4_general_ci"]])
        XCTAssertNil(chain.executor.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertEqual(chain.statements.filter { $0.hasPrefix("CREATE VIEW") }, [
            "CREATE VIEW `store`.`c_leaf` AS select count(0) AS `n` from `orders`",
            "CREATE VIEW `store`.`b_mid` AS select `c_leaf`.`n` AS `n` from `c_leaf`",
            "CREATE VIEW `store`.`a_top` AS select `b_mid`.`n` AS `n` from `b_mid`"
        ])

        // where the server folds case, a reference differing in ASCII case
        // still finds its view; names differing beyond ASCII (`ẞ`, `ß`) stay
        // two views and are both created - Unicode folding would merge them
        let cased = makeServer(tables: [["orders", "BASE TABLE"], ["a_top", "VIEW"], ["Z_Base", "VIEW"]])
        cased.respond(to: showCreateViewPrefix + "`a_top`", rows: [["a_top", "CREATE VIEW `a_top` AS select `z_base`.`n` AS `n` from `z_base`", "utf8mb4", "utf8mb4_general_ci"]])
        cased.respond(to: showCreateViewPrefix + "`Z_Base`", rows: [["Z_Base", "CREATE VIEW `Z_Base` AS select count(0) AS `n` from `orders`", "utf8mb4", "utf8mb4_general_ci"]])
        XCTAssertNil(cased.executor.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertEqual(cased.statements.filter { $0.hasPrefix("CREATE VIEW") }, [
            "CREATE VIEW `store`.`Z_Base` AS select count(0) AS `n` from `orders`",
            "CREATE VIEW `store`.`a_top` AS select `z_base`.`n` AS `n` from `z_base`"
        ])

        let capitalSharpS = "\u{1E9E}"
        let sharpS = "\u{00DF}"
        let distinct = makeServer(tables: [["orders", "BASE TABLE"], [capitalSharpS, "VIEW"], [sharpS, "VIEW"]])
        distinct.respond(to: showCreateViewPrefix + "`\(capitalSharpS)`", rows: [[capitalSharpS, "CREATE VIEW `\(capitalSharpS)` AS select 1 AS `n`", "utf8mb4", "utf8mb4_general_ci"]])
        distinct.respond(to: showCreateViewPrefix + "`\(sharpS)`", rows: [[sharpS, "CREATE VIEW `\(sharpS)` AS select 2 AS `n`", "utf8mb4", "utf8mb4_general_ci"]])
        XCTAssertNil(distinct.executor.rename("shop", to: "store", encoding: nil, collation: nil))
        let creates = distinct.statements.filter { $0.hasPrefix("CREATE VIEW") }
        XCTAssertEqual(creates.count, 2, creates.joined(separator: "\n"))
        XCTAssertTrue(creates.contains { $0.utf8.elementsEqual("CREATE VIEW `store`.`\(capitalSharpS)` AS select 1 AS `n`".utf8) }, creates.joined(separator: "\n"))
        XCTAssertTrue(creates.contains { $0.utf8.elementsEqual("CREATE VIEW `store`.`\(sharpS)` AS select 2 AS `n`".utf8) }, creates.joined(separator: "\n"))
        XCTAssertEqual(distinct.statements.last, "DROP DATABASE `shop`")
    }

    /// Verifies a recreated view is opened once before it counts - the
    /// server checks the definer's privileges on the moved objects only then
    /// - and that one which cannot be opened is dropped again and reported
    /// like a failed CREATE, with the source kept.
    func testUnusableRecreatedViewIsDroppedAndReported() throws {
        let server = makeServer()
        server.fail("SELECT 1 FROM `store`.`totals` LIMIT 0", with: "View 'store.totals' references invalid table(s) or column(s) or function(s) or definer/invoker of view lack rights to use them")
        let description = try XCTUnwrap(server.executor.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertTrue(description.contains("Moving view 'totals' failed: View 'store.totals' references invalid table(s) or column(s) or function(s) or definer/invoker of view lack rights to use them The objects moved so far are in 'store'; 'shop' was not dropped."), description)
        let opened = try XCTUnwrap(server.statements.firstIndex(of: "SELECT 1 FROM `store`.`totals` LIMIT 0"))
        XCTAssertEqual(server.statements[opened + 1], "DROP VIEW `store`.`totals`")
        XCTAssertFalse(server.statements.contains { $0.hasPrefix("DROP DATABASE") })
        XCTAssertEqual(server.statements.last, "USE `shop`")
    }

    /// Verifies a definition the rewriter cannot handle stops the rename
    /// before anything moves, with its reason.
    func testDefinitionWithoutViewClauseStopsBeforeAnythingChanges() throws {
        let server = makeServer()
        server.responses.removeAll { $0.matches(showCreateViewPrefix + "`totals`") }
        server.respond(to: showCreateViewPrefix + "`totals`", rows: [["totals", "select 1", "utf8mb4", "utf8mb4_general_ci"]])
        let description = try XCTUnwrap(server.executor.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertTrue(description.contains("Reading the objects of the database 'shop' failed: its definition returned by SHOW CREATE VIEW has no VIEW clause. Nothing was changed."), description)
        XCTAssertFalse(server.statements.contains { $0.hasPrefix("CREATE DATABASE") || $0.hasPrefix("RENAME") || $0.hasPrefix("DROP") })
    }

    /// Verifies the executor tells whether the server was changed: not when
    /// the rename was refused or stopped before the target was created, but
    /// as soon as the target exists - also when a table or a view then fails.
    func testChangedServerTellsWhetherTheTargetWasCreated() {
        let refused = makeServer()
        refused.respond(to: "SELECT TRIGGER_NAME, EVENT_OBJECT_TABLE FROM information_schema.TRIGGERS WHERE TRIGGER_SCHEMA = 'shop'", rows: [["orders_audit", "orders"]])
        let refusedExecutor = refused.executor
        XCTAssertNotNil(refusedExecutor.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertFalse(refusedExecutor.changedServer)

        let unreadable = makeServer()
        unreadable.responses.removeAll { $0.matches(sessionQuery) }
        unreadable.fail(sessionQuery, with: "Unknown system variable")
        let unreadableExecutor = unreadable.executor
        XCTAssertNotNil(unreadableExecutor.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertFalse(unreadableExecutor.changedServer)

        let table = makeServer(tables: [["a", "BASE TABLE"], ["b", "BASE TABLE"]])
        table.fail("RENAME TABLE `shop`.`b`", with: "Access denied")
        let tableExecutor = table.executor
        XCTAssertNotNil(tableExecutor.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertTrue(tableExecutor.changedServer)

        let view = makeServer()
        view.fail("CREATE ALGORITHM", with: "Access denied for CREATE VIEW")
        let viewExecutor = view.executor
        XCTAssertNotNil(viewExecutor.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertTrue(viewExecutor.changedServer)

        let done = makeServer()
        let doneExecutor = done.executor
        XCTAssertNil(doneExecutor.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertTrue(doneExecutor.changedServer)
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

    /// Verifies a statement the connection returned no result for - which it
    /// does without flagging an error while disconnected or reconnecting,
    /// after a user disconnect or a failed connection check, whereas a
    /// statement without a result set still gets an empty result - counts as
    /// failed: an inventory query then stops the rename before anything
    /// changes, and a RENAME TABLE is not counted as moved, so the source
    /// is kept.
    func testStatementsWithoutAResultCountAsFailed() throws {
        let noResultReason = "the connection returned no result, so the statement may not have run (the connection was lost or closed, or the query was cancelled)."
        let noResult = SADatabaseRenameStatementResult(rows: [["ignored"]], resultReturned: false, errored: false, errorMessage: nil)
        XCTAssertNil(noResult.rows)
        XCTAssertEqual(noResult.error, noResultReason)

        let empty = SADatabaseRenameStatementResult(rows: [], resultReturned: true, errored: false, errorMessage: "an earlier statement's message")
        XCTAssertEqual(empty.rows?.count, 0)
        XCTAssertNil(empty.error)

        let failed = SADatabaseRenameStatementResult(rows: [], resultReturned: false, errored: true, errorMessage: "Lost connection to MySQL server during query")
        XCTAssertNil(failed.rows)
        XCTAssertEqual(failed.error, "Lost connection to MySQL server during query")

        let unexplained = SADatabaseRenameStatementResult(rows: [], resultReturned: true, errored: true, errorMessage: nil)
        XCTAssertNil(unexplained.rows)
        XCTAssertEqual(unexplained.error, "unknown error")

        let inventory = makeServer()
        inventory.responses.insert(({ $0.hasPrefix("SELECT TRIGGER_NAME") }, noResult), at: 0)
        let inventoryReason = try XCTUnwrap(inventory.executor.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertTrue(inventoryReason.contains("Reading the objects of the database 'shop' failed: \(noResultReason) Nothing was changed."), inventoryReason)
        XCTAssertTrue(onlyInspected(inventory), inventory.statements.joined(separator: "\n"))

        let moves = makeServer(tables: [["a", "BASE TABLE"], ["b", "BASE TABLE"], ["c", "BASE TABLE"]])
        moves.responses.insert(({ $0.hasPrefix("RENAME TABLE `shop`.`b`") }, noResult), at: 0)
        let movesReason = try XCTUnwrap(moves.executor.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertTrue(movesReason.contains("Moving table 'b' failed: \(noResultReason) The objects moved so far are in 'store'; 'shop' was not dropped."), movesReason)
        XCTAssertEqual(statements(of: moves, from: "RENAME"), [
            "RENAME TABLE `shop`.`a` TO `store`.`a`",
            "RENAME TABLE `shop`.`b` TO `store`.`b`"
        ])
        XCTAssertFalse(moves.statements.contains { $0.hasPrefix("DROP") }, moves.statements.joined(separator: "\n"))
    }

    // MARK: - Connection session

    /// A stand-in for the connection's encoding state in front of a
    /// FakeServer: `SET NAMES` works for `acceptedEncodings` (and ends latin1
    /// transport), the restore puts back what was stored unless
    /// `restoreWorks` is off, and a reconnect - which keeps the encoding the
    /// connection last recorded, as the framework does - works unless
    /// `reconnectWorks` is off.
    private final class FakeConnection {
        let server: FakeServer
        var encoding: String
        var usesLatin1Transport: Bool
        var acceptedEncodings: Set<String> = ["utf8mb4", "utf8"]
        var restoreWorks = true
        var reconnectWorks = true
        private var stored: (encoding: String, usesLatin1Transport: Bool)?
        private(set) var restoreCount = 0
        private(set) var reconnectCount = 0
        private(set) var statementCountAtReconnect: Int?
        private(set) var setEncodingCalls: [String] = []
        private(set) var setLatin1TransportCalls: [Bool] = []

        init(server: FakeServer, encoding: String, usesLatin1Transport: Bool = false) {
            self.server = server
            self.encoding = encoding
            self.usesLatin1Transport = usesLatin1Transport
        }

        func makeSession() -> SADatabaseRenameConnectionSession {
            SADatabaseRenameConnectionSession(
                run: { [unowned self] in self.server.run($0) },
                quote: { [unowned self] in self.server.quote($0) },
                encoding: { [unowned self] in self.encoding },
                usesLatin1Transport: { [unowned self] in self.usesLatin1Transport },
                setEncoding: { [unowned self] name in
                    self.setEncodingCalls.append(name)
                    guard self.acceptedEncodings.contains(name) else { return false }
                    self.encoding = name
                    self.usesLatin1Transport = false
                    return true
                },
                setLatin1Transport: { [unowned self] flag in
                    self.setLatin1TransportCalls.append(flag)
                    self.usesLatin1Transport = flag
                    return true
                },
                storeEncodingForRestoration: { [unowned self] in
                    self.stored = (self.encoding, self.usesLatin1Transport)
                },
                restoreStoredEncoding: { [unowned self] in
                    self.restoreCount += 1
                    guard self.restoreWorks, let stored = self.stored else { return }
                    self.encoding = stored.encoding
                    self.usesLatin1Transport = stored.usesLatin1Transport
                },
                reconnect: { [unowned self] in
                    self.reconnectCount += 1
                    self.statementCountAtReconnect = self.server.statements.count
                    return self.reconnectWorks
                })
        }
    }

    private let collationQuery = "SELECT @@collation_connection"

    private let restoredSettingsQuery = "SELECT @@character_set_client, @@character_set_connection, @@character_set_results, @@collation_connection"

    private let reestablishedWarning = "The connection's character set, collation or SQL mode could not be restored after Rename Database, so the connection was re-established."

    private let unusableWarning = "The connection's character set, collation or SQL mode could not be restored after Rename Database, and re-establishing it failed; reconnect before running further queries."

    /// A latin1 connection whose session collation is latin1_swedish_ci and
    /// whose server reports `restored` once the settings are put back.
    private func makeLatin1Connection(restored: [Any] = ["latin1", "latin1", "latin1", "latin1_swedish_ci"]) -> FakeConnection {
        let server = makeServer()
        server.respond(to: collationQuery, rows: [["latin1_swedish_ci"]])
        server.respond(to: restoredSettingsQuery, rows: [restored])
        let connection = FakeConnection(server: server, encoding: "latin1")
        connection.acceptedEncodings.insert("latin1")
        return connection
    }

    /// A utf8mb4 connection whose session collation is utf8mb4_bin and whose
    /// server reports `restored` once the collation is put back.
    private func makeUTF8MB4Connection(restored: [Any] = ["utf8mb4", "utf8mb4", "utf8mb4", "utf8mb4_bin"]) -> FakeConnection {
        let server = makeServer()
        server.respond(to: collationQuery, rows: [["utf8mb4_bin"]])
        server.respond(to: restoredSettingsQuery, rows: [restored])
        return FakeConnection(server: server, encoding: "utf8mb4")
    }

    /// A connection already on utf8mb4 keeps its encoding - nothing is
    /// switched, stored or restored, so another caller's stored encoding is
    /// never applied - but its collation, which recreating views changes, is
    /// still read up front, set again afterwards and verified.
    func testSessionOnUTF8MB4KeepsTheEncodingAndVerifiesTheCollation() {
        let connection = makeUTF8MB4Connection()
        let session = connection.makeSession()

        XCTAssertNil(session.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertTrue(session.changedServer)
        XCTAssertNil(session.warningDescription)
        XCTAssertEqual(connection.setEncodingCalls, [])
        XCTAssertEqual(connection.restoreCount, 0)
        XCTAssertEqual(connection.reconnectCount, 0)
        XCTAssertTrue(session.connectionUsable)
        XCTAssertEqual(connection.server.statements.first, collationQuery)
        XCTAssertEqual(Array(connection.server.statements.suffix(2)), [
            "SET collation_connection = 'utf8mb4_bin'",
            restoredSettingsQuery
        ])
    }

    /// On a utf8mb4 connection a collation left on a view's collation is
    /// retried once; then the connection is re-established and switched back
    /// to utf8mb4, which a new session's default collation matches.
    func testSessionOnUTF8MB4WarnsWhenTheCollationStaysChanged() {
        let connection = makeUTF8MB4Connection(restored: ["utf8mb4", "utf8mb4", "utf8mb4", "utf8mb4_general_ci"])
        let session = connection.makeSession()

        _ = session.rename("shop", to: "store", encoding: nil, collation: nil)
        XCTAssertEqual(session.warningDescription, reestablishedWarning)
        XCTAssertTrue(session.connectionUsable)
        XCTAssertEqual(connection.restoreCount, 0)
        XCTAssertEqual(connection.reconnectCount, 1)
        XCTAssertEqual(connection.setEncodingCalls, ["utf8mb4"])
        XCTAssertEqual(connection.server.statements.filter { $0 == "SET collation_connection = 'utf8mb4_bin'" }.count, 3)
        XCTAssertEqual(connection.server.statements.filter { $0 == restoredSettingsQuery }.count, 3)

        let unreadable = FakeConnection(server: makeServer(), encoding: "utf8mb4")
        unreadable.server.fail(collationQuery, with: "Lost connection to MySQL server during query")
        let unreadableSession = unreadable.makeSession()
        XCTAssertEqual(unreadableSession.rename("shop", to: "store", encoding: nil, collation: nil), "The connection's collation could not be read, so it could not be restored after the rename. Nothing was changed.")
        XCTAssertEqual(unreadable.server.statements, [collationQuery])
    }

    /// A latin1 connection is switched to utf8mb4 after its collation was
    /// read, renamed, and then put back: the stored encoding restored, the
    /// collation set again, and both checked against the server.
    func testSessionSwitchesToUTF8AndVerifiesTheRestore() {
        let connection = makeLatin1Connection()
        let session = connection.makeSession()

        XCTAssertNil(session.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertNil(session.warningDescription)
        XCTAssertTrue(session.changedServer)
        XCTAssertEqual(connection.setEncodingCalls, ["utf8mb4"])
        XCTAssertEqual(connection.restoreCount, 1)
        XCTAssertEqual(connection.encoding, "latin1")
        XCTAssertEqual(connection.reconnectCount, 0)
        XCTAssertEqual(connection.server.statements.first, collationQuery)
        XCTAssertEqual(Array(connection.server.statements.suffix(2)), [
            "SET collation_connection = 'latin1_swedish_ci'",
            restoredSettingsQuery
        ])
    }

    /// Under latin1 transport the server reports latin1 for the client and
    /// the results, and utf8 as utf8mb3; both count as restored.
    func testSessionAcceptsRestoredLatin1TransportAndUTF8MB3Names() {
        let server = makeServer()
        server.respond(to: collationQuery, rows: [["utf8mb3_general_ci"]])
        server.respond(to: restoredSettingsQuery, rows: [["latin1", "utf8mb3", "latin1", "utf8mb3_general_ci"]])
        let connection = FakeConnection(server: server, encoding: "utf8", usesLatin1Transport: true)
        let session = connection.makeSession()

        XCTAssertNil(session.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertNil(session.warningDescription)
        XCTAssertEqual(connection.restoreCount, 1)
        XCTAssertTrue(connection.usesLatin1Transport)
    }

    /// A restore that does not take - the connection stays on utf8mb4 - is
    /// tried once more; then the connection is re-established and switched
    /// back to latin1 before anything else is sent. The rename itself still
    /// succeeded. When re-establishing fails, nothing more is sent and the
    /// connection is not to be queried.
    func testSessionWarnsWhenTheRestoreDoesNotTake() {
        let connection = makeLatin1Connection()
        connection.restoreWorks = false
        let session = connection.makeSession()

        XCTAssertNil(session.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertEqual(session.warningDescription, reestablishedWarning)
        XCTAssertTrue(session.connectionUsable)
        XCTAssertEqual(connection.restoreCount, 2)
        XCTAssertEqual(connection.reconnectCount, 1)
        XCTAssertEqual(connection.setEncodingCalls, ["utf8mb4", "latin1"])
        XCTAssertEqual(connection.encoding, "latin1")
        let reconnectedAt = try? XCTUnwrap(connection.statementCountAtReconnect)
        XCTAssertEqual(Array(connection.server.statements.dropFirst(reconnectedAt ?? 0)), [
            "SET collation_connection = 'latin1_swedish_ci'",
            restoredSettingsQuery
        ])

        let lost = makeLatin1Connection()
        lost.restoreWorks = false
        lost.reconnectWorks = false
        let lostSession = lost.makeSession()
        XCTAssertNil(lostSession.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertEqual(lostSession.warningDescription, unusableWarning)
        XCTAssertFalse(lostSession.connectionUsable)
        XCTAssertEqual(lost.server.statements.count, lost.statementCountAtReconnect)
        XCTAssertEqual(lost.setEncodingCalls, ["utf8mb4"])
    }

    /// The server is the reference: another collation than the session had,
    /// another client character set, or a refused `SET` all count as not
    /// restored and re-establish the connection; one whose client character
    /// set still disagrees afterwards is not to be queried.
    func testSessionWarnsWhenTheServerDisagrees() {
        let collation = makeLatin1Connection(restored: ["latin1", "latin1", "latin1", "latin1_general_ci"])
        let collationSession = collation.makeSession()
        XCTAssertNil(collationSession.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertEqual(collationSession.warningDescription, reestablishedWarning)
        XCTAssertTrue(collationSession.connectionUsable)
        XCTAssertEqual(collation.restoreCount, 2)
        XCTAssertEqual(collation.reconnectCount, 1)
        XCTAssertEqual(collation.server.statements.filter { $0 == restoredSettingsQuery }.count, 3)

        let client = makeLatin1Connection(restored: ["utf8mb4", "latin1", "latin1", "latin1_swedish_ci"])
        let clientSession = client.makeSession()
        XCTAssertNil(clientSession.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertEqual(clientSession.warningDescription, unusableWarning)
        XCTAssertFalse(clientSession.connectionUsable)

        let refused = makeLatin1Connection()
        refused.server.responses.insert(({ $0 == "SET collation_connection = 'latin1_swedish_ci'" }, SADatabaseRenameStatementResult(error: "Lost connection to MySQL server during query")), at: 0)
        let refusedSession = refused.makeSession()
        XCTAssertNil(refusedSession.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertEqual(refusedSession.warningDescription, reestablishedWarning)
        XCTAssertTrue(refusedSession.connectionUsable)
        XCTAssertEqual(refused.server.statements.filter { $0 == restoredSettingsQuery }.count, 1)
    }

    /// Settings the executor could not put back - its restoring SET was
    /// refused on an early way out - re-establish the connection even when
    /// character set and collation are back, since sql_mode or quoting may
    /// not be. A connection that cannot be re-established is not sent
    /// anything more.
    func testSessionReconnectsWhenTheExecutorCouldNotRestoreItsSettings() throws {
        func makeConnection() -> FakeConnection {
            let connection = makeUTF8MB4Connection()
            connection.server.responses.removeAll { $0.matches(showCreateViewPrefix + "`totals`") }
            connection.server.fail(showCreateViewPrefix, with: "SHOW VIEW command denied")
            connection.server.fail("SET sql_mode = 'STRICT_TRANS_TABLES,NO_BACKSLASH_ESCAPES'", with: "Lost connection to MySQL server during query")
            return connection
        }

        let connection = makeConnection()
        let session = connection.makeSession()
        let failure = try XCTUnwrap(session.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertTrue(failure.contains("SHOW VIEW command denied"), failure)
        XCTAssertFalse(session.changedServer)
        XCTAssertEqual(session.warningDescription, reestablishedWarning)
        XCTAssertTrue(session.connectionUsable)
        XCTAssertEqual(connection.reconnectCount, 1)
        XCTAssertEqual(connection.setEncodingCalls, ["utf8mb4"])
        let reconnectedAt = try XCTUnwrap(connection.statementCountAtReconnect)
        XCTAssertEqual(Array(connection.server.statements.dropFirst(reconnectedAt)), [
            "SET collation_connection = 'utf8mb4_bin'",
            restoredSettingsQuery
        ])

        let lost = makeConnection()
        lost.reconnectWorks = false
        let lostSession = lost.makeSession()
        XCTAssertNotNil(lostSession.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertEqual(lostSession.warningDescription, unusableWarning)
        XCTAssertFalse(lostSession.connectionUsable)
        XCTAssertEqual(lost.server.statements.count, lost.statementCountAtReconnect)
        XCTAssertEqual(lost.setEncodingCalls, [])
    }

    /// Latin1 transport is switched on again after re-establishing a
    /// connection that used it.
    func testSessionReappliesLatin1TransportAfterReconnecting() {
        let server = makeServer()
        server.respond(to: collationQuery, rows: [["utf8mb3_general_ci"]])
        server.respond(to: restoredSettingsQuery, rows: [["latin1", "utf8mb3", "latin1", "utf8mb3_general_ci"]])
        let connection = FakeConnection(server: server, encoding: "utf8", usesLatin1Transport: true)
        connection.restoreWorks = false
        let session = connection.makeSession()

        XCTAssertNil(session.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertEqual(session.warningDescription, reestablishedWarning)
        XCTAssertTrue(session.connectionUsable)
        XCTAssertEqual(connection.setLatin1TransportCalls, [true])
        XCTAssertTrue(connection.usesLatin1Transport)
        XCTAssertEqual(connection.encoding, "utf8")
    }

    /// A collation that cannot be read stops the rename before anything is
    /// switched.
    func testSessionRefusesWhenTheCollationCannotBeRead() {
        let server = makeServer()
        server.fail(collationQuery, with: "Lost connection to MySQL server during query")
        let connection = FakeConnection(server: server, encoding: "latin1")
        let session = connection.makeSession()

        XCTAssertEqual(session.rename("shop", to: "store", encoding: nil, collation: nil), "The connection's collation could not be read, so it could not be restored after the rename. Nothing was changed.")
        XCTAssertEqual(server.statements, [collationQuery])
        XCTAssertEqual(connection.setEncodingCalls, [])
        XCTAssertEqual(connection.restoreCount, 0)
        XCTAssertNil(session.warningDescription)
        XCTAssertFalse(session.changedServer)
    }

    /// A connection that takes neither utf8mb4 nor utf8 is refused and put
    /// back - verified like after a rename, with a warning when that fails
    /// too.
    func testSessionRefusesWhenUTF8CannotBeSelected() {
        let refusal = "The connection could not be switched to UTF-8, which Rename Database needs to move view definitions without loss. Nothing was changed."

        let connection = makeLatin1Connection()
        connection.acceptedEncodings = []
        let session = connection.makeSession()
        XCTAssertEqual(session.rename("shop", to: "store", encoding: nil, collation: nil), refusal)
        XCTAssertEqual(connection.setEncodingCalls, ["utf8mb4", "utf8"])
        XCTAssertEqual(connection.restoreCount, 1)
        XCTAssertEqual(connection.server.statements, [
            collationQuery,
            "SET collation_connection = 'latin1_swedish_ci'",
            restoredSettingsQuery
        ])
        XCTAssertNil(session.warningDescription)
        XCTAssertFalse(session.changedServer)

        XCTAssertEqual(connection.reconnectCount, 0)

        // the restore does not show and latin1 cannot be selected after re-establishing either
        let broken = makeLatin1Connection(restored: ["latin1", "latin1", "latin1", "latin1_general_ci"])
        broken.acceptedEncodings = []
        let brokenSession = broken.makeSession()
        XCTAssertEqual(brokenSession.rename("shop", to: "store", encoding: nil, collation: nil), refusal)
        XCTAssertEqual(brokenSession.warningDescription, unusableWarning)
        XCTAssertFalse(brokenSession.connectionUsable)
        XCTAssertEqual(broken.reconnectCount, 1)
    }

    /// A collation the connection cannot quote for the restore counts as not
    /// restored and is never sent: the connection is re-established and
    /// switched back to its character set.
    func testSessionReconnectsWhenTheCollationCannotBeQuoted() {
        let connection = makeLatin1Connection()
        connection.server.unquotable = ["latin1_swedish_ci"]
        let session = connection.makeSession()

        XCTAssertNil(session.rename("shop", to: "store", encoding: nil, collation: nil))
        XCTAssertEqual(session.warningDescription, reestablishedWarning)
        XCTAssertTrue(session.connectionUsable)
        XCTAssertEqual(connection.restoreCount, 1)
        XCTAssertEqual(connection.reconnectCount, 1)
        XCTAssertEqual(connection.setEncodingCalls, ["utf8mb4", "latin1"])
        XCTAssertFalse(connection.server.statements.contains { $0.hasPrefix("SET collation_connection = 'latin1") }, connection.server.statements.joined(separator: "\n"))
    }

    /// Character set and collation names match across the utf8 spellings.
    func testSessionCharacterSetNames() {
        XCTAssertTrue(SADatabaseRenameConnectionSession.isSameCharacterSet("utf8", "UTF8MB3"))
        XCTAssertFalse(SADatabaseRenameConnectionSession.isSameCharacterSet("utf8", "utf8mb4"))
        XCTAssertTrue(SADatabaseRenameConnectionSession.collation("utf8mb3_general_ci", belongsTo: "utf8"))
        XCTAssertTrue(SADatabaseRenameConnectionSession.collation("utf8_general_ci", belongsTo: "utf8mb3"))
        XCTAssertFalse(SADatabaseRenameConnectionSession.collation("utf8mb4_general_ci", belongsTo: "utf8"))
        XCTAssertTrue(SADatabaseRenameConnectionSession.collation("binary", belongsTo: "binary"))
        XCTAssertFalse(SADatabaseRenameConnectionSession.collation("latin1_swedish_ci", belongsTo: "latin2"))
    }
}
