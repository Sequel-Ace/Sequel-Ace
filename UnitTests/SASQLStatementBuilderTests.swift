//
//  SASQLStatementBuilderTests.swift
//  Unit Tests
//
//  Created by Sequel-Ace contributors on 2026.09.20.
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import XCTest

final class SASQLStatementBuilderTests: XCTestCase {

    // MARK: - INSERT

    /// Pins the exact text the table view has always put on the pasteboard, down to the tab
    /// indent and the trailing newline, so extracting this out of `SPCopyTable` changed nothing.
    func testASingleRowBecomesOneInsertStatement() {
        let sql = SASQLStatementBuilder.insertStatements(
            table: "people",
            columns: ["id", "name"],
            rows: [["1", "'Ada'"]]
        )

        XCTAssertEqual(sql, "INSERT INTO `people` (`id`, `name`)\nVALUES\n\t(1, 'Ada');\n")
    }

    func testEveryRowBecomesOneEntryInASharedValuesList() {
        let sql = SASQLStatementBuilder.insertStatements(
            table: "people",
            columns: ["id", "name"],
            rows: [["1", "'Ada'"], ["2", "'Grace'"], ["3", "NULL"]]
        )

        XCTAssertEqual(
            sql,
            "INSERT INTO `people` (`id`, `name`)\nVALUES\n\t(1, 'Ada'),\n\t(2, 'Grace'),\n\t(3, NULL);\n"
        )
    }

    /// Nothing about `NULL` is special in an `INSERT`; it is only the `WHERE` clause of an
    /// `UPDATE` that has to treat it differently.
    func testNullIsInsertedAsAnOrdinaryLiteral() {
        let sql = SASQLStatementBuilder.insertStatements(table: "t", columns: ["a"], rows: [["NULL"]])

        XCTAssertEqual(sql, "INSERT INTO `t` (`a`)\nVALUES\n\t(NULL);\n")
    }

    /// Rows read from a join in the custom query editor have no single table behind them. The
    /// result is deliberately not runnable — it is a template the user finishes.
    func testRowsFromNoSingleTableGetAPlaceholderName() {
        let sql = SASQLStatementBuilder.insertStatements(table: nil, columns: ["a"], rows: [["1"]])

        XCTAssertEqual(sql, "INSERT INTO `<table>` (`a`)\nVALUES\n\t(1);\n")
        XCTAssertEqual(
            SASQLStatementBuilder.insertStatements(table: "", columns: ["a"], rows: [["1"]]),
            sql
        )
    }

    func testIdentifiersAreBacktickQuotedAndInternalBackticksDoubled() {
        let sql = SASQLStatementBuilder.insertStatements(
            table: "we`ird",
            columns: ["col`umn"],
            rows: [["1"]]
        )

        XCTAssertEqual(sql, "INSERT INTO `we``ird` (`col``umn`)\nVALUES\n\t(1);\n")
    }

    /// A `VALUES` list long enough to worry `max_allowed_packet` is split into several
    /// statements, each repeating the same header.
    func testALongValuesListIsSplitAcrossSeveralInsertStatements() {
        let wide = String(repeating: "x", count: 300_000)
        let sql = SASQLStatementBuilder.insertStatements(
            table: "t",
            columns: ["a"],
            rows: [["'\(wide)'"], ["'second'"], ["'third'"]]
        )

        let header = "INSERT INTO `t` (`a`)\nVALUES\n"
        XCTAssertEqual(sql?.components(separatedBy: header).count, 3, "expected two statements")
        XCTAssertTrue(sql?.hasSuffix("\t('second'),\n\t('third');\n") ?? false)
        XCTAssertTrue(sql?.contains("'\(wide)');\n\n\(header)") ?? false, "the oversized row ends its own statement")
    }

    func testNothingToInsertYieldsNoStatement() {
        XCTAssertNil(SASQLStatementBuilder.insertStatements(table: "t", columns: [], rows: [["1"]]))
        XCTAssertNil(SASQLStatementBuilder.insertStatements(table: "t", columns: ["a"], rows: []))
    }

    /// A row that does not line up with the column list would put values under the wrong names,
    /// which is worse than copying nothing.
    func testARowOfTheWrongWidthYieldsNoStatement() {
        XCTAssertNil(
            SASQLStatementBuilder.insertStatements(
                table: "t",
                columns: ["a", "b"],
                rows: [["1", "2"], ["3"]]
            )
        )
    }

    // MARK: - UPDATE

    func testEachRowBecomesItsOwnUpdateStatement() {
        let sql = SASQLStatementBuilder.updateStatements(
            table: "people",
            columns: ["id", "name"],
            keyColumnIndexes: IndexSet(integer: 0),
            rows: [["1", "'Ada'"], ["2", "'Grace'"]]
        )

        XCTAssertEqual(
            sql,
            "UPDATE `people` SET `name` = 'Ada'\nWHERE `id` = 1;\n"
                + "UPDATE `people` SET `name` = 'Grace'\nWHERE `id` = 2;\n"
        )
    }

    /// The key is what the statement matches on; assigning it its own value again is noise at
    /// best, and at worst rewrites a row's identity.
    func testKeyColumnsAreMatchedOnRatherThanAssigned() {
        let sql = SASQLStatementBuilder.updateStatements(
            table: "t",
            columns: ["id", "a", "b"],
            keyColumnIndexes: IndexSet(integer: 0),
            rows: [["1", "'x'", "'y'"]]
        )

        XCTAssertEqual(sql, "UPDATE `t` SET `a` = 'x', `b` = 'y'\nWHERE `id` = 1;\n")
    }

    func testACompositeKeyMatchesOnEveryKeyColumn() {
        let sql = SASQLStatementBuilder.updateStatements(
            table: "t",
            columns: ["tenant", "id", "a"],
            keyColumnIndexes: IndexSet([0, 1]),
            rows: [["7", "1", "'x'"]]
        )

        XCTAssertEqual(sql, "UPDATE `t` SET `a` = 'x'\nWHERE `tenant` = 7 AND `id` = 1;\n")
    }

    /// `= NULL` is never true in MySQL, so a naive `WHERE` would match no rows at all and the
    /// statement would run clean while doing nothing.
    func testANullKeyIsMatchedWithIsNull() {
        let sql = SASQLStatementBuilder.updateStatements(
            table: "t",
            columns: ["k", "a"],
            keyColumnIndexes: IndexSet(integer: 0),
            rows: [["NULL", "'x'"]]
        )

        XCTAssertEqual(sql, "UPDATE `t` SET `a` = 'x'\nWHERE `k` IS NULL;\n")
    }

    func testANullValueIsStillAssignedWithEquals() {
        let sql = SASQLStatementBuilder.updateStatements(
            table: "t",
            columns: ["id", "a"],
            keyColumnIndexes: IndexSet(integer: 0),
            rows: [["1", "NULL"]]
        )

        XCTAssertEqual(sql, "UPDATE `t` SET `a` = NULL\nWHERE `id` = 1;\n")
    }

    func testUpdateIdentifiersAreBacktickQuotedAndInternalBackticksDoubled() {
        let sql = SASQLStatementBuilder.updateStatements(
            table: "we`ird",
            columns: ["i`d", "a`b"],
            keyColumnIndexes: IndexSet(integer: 0),
            rows: [["1", "'x'"]]
        )

        XCTAssertEqual(sql, "UPDATE `we``ird` SET `a``b` = 'x'\nWHERE `i``d` = 1;\n")
    }

    func testUpdatesFromNoSingleTableGetAPlaceholderName() {
        let sql = SASQLStatementBuilder.updateStatements(
            table: nil,
            columns: ["id", "a"],
            keyColumnIndexes: IndexSet(integer: 0),
            rows: [["1", "'x'"]]
        )

        XCTAssertEqual(sql, "UPDATE `<table>` SET `a` = 'x'\nWHERE `id` = 1;\n")
    }

    /// Without a key there is no way to tell the intended row from any other, and an `UPDATE`
    /// with no `WHERE` would rewrite the whole table.
    func testRowsWithoutAKeyYieldNoStatement() {
        XCTAssertNil(
            SASQLStatementBuilder.updateStatements(
                table: "t",
                columns: ["a", "b"],
                keyColumnIndexes: IndexSet(),
                rows: [["'x'", "'y'"]]
            )
        )
    }

    func testAKeyIndexOutsideTheColumnListIsIgnored() {
        XCTAssertNil(
            SASQLStatementBuilder.updateStatements(
                table: "t",
                columns: ["a"],
                keyColumnIndexes: IndexSet(integer: 9),
                rows: [["'x'"]]
            )
        )
    }

    /// A table that is nothing but its primary key has nothing an `UPDATE` could set.
    func testColumnsThatAreAllKeyYieldNoStatement() {
        XCTAssertNil(
            SASQLStatementBuilder.updateStatements(
                table: "t",
                columns: ["tenant", "id"],
                keyColumnIndexes: IndexSet([0, 1]),
                rows: [["7", "1"]]
            )
        )
    }

    func testNothingToUpdateYieldsNoStatement() {
        XCTAssertNil(
            SASQLStatementBuilder.updateStatements(
                table: "t",
                columns: [],
                keyColumnIndexes: IndexSet(integer: 0),
                rows: [["1"]]
            )
        )
        XCTAssertNil(
            SASQLStatementBuilder.updateStatements(
                table: "t",
                columns: ["id", "a"],
                keyColumnIndexes: IndexSet(integer: 0),
                rows: []
            )
        )
    }

    func testAnUpdateRowOfTheWrongWidthYieldsNoStatement() {
        XCTAssertNil(
            SASQLStatementBuilder.updateStatements(
                table: "t",
                columns: ["id", "a"],
                keyColumnIndexes: IndexSet(integer: 0),
                rows: [["1", "'x'"], ["2"]]
            )
        )
    }
}
