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

    /// The batch limit counts UTF-16 units, as the NSString length it replaced did, however the
    /// text is made up: 130,000 `é` stay under it (though they take 260,000 bytes in UTF-8), while
    /// 130,000 emoji, two UTF-16 units each, go over it.
    func testTheBatchLimitIsMeasuredInUTF16UnitsForNonASCIIText() {
        let header = "INSERT INTO `t` (`a`)\nVALUES\n"

        let accented = SASQLStatementBuilder.insertStatements(
            table: "t",
            columns: ["a"],
            rows: [["'\(String(repeating: "é", count: 130_000))'"], ["'next'"]]
        )
        XCTAssertEqual(accented?.components(separatedBy: header).count, 2, "expected one statement")

        let emoji = SASQLStatementBuilder.insertStatements(
            table: "t",
            columns: ["a"],
            rows: [["'\(String(repeating: "😀", count: 130_000))'"], ["'next'"]]
        )
        XCTAssertEqual(emoji?.components(separatedBy: header).count, 3, "expected two statements")
        XCTAssertTrue(emoji?.hasSuffix("\(header)\t('next');\n") ?? false)
    }

    /// A batch is closed off only once another row arrives, so an oversized last row ends the
    /// statement it joined rather than leaving an empty one behind it.
    func testAnOversizedLastRowOpensNoFurtherStatement() {
        let wide = String(repeating: "x", count: 300_000)
        let sql = SASQLStatementBuilder.insertStatements(
            table: "t",
            columns: ["a"],
            rows: [["'first'"], ["'\(wide)'"]]
        )

        let header = "INSERT INTO `t` (`a`)\nVALUES\n"
        XCTAssertEqual(sql?.components(separatedBy: header).count, 2, "expected one statement")
        XCTAssertTrue(sql?.hasSuffix("\t('first'),\n\t('\(wide)');\n") ?? false)
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

    // MARK: - Writers

    /// `SPCopyTable` hands rows to a writer one at a time and never keeps them. Once the writer
    /// has finished, it takes no more rows and gives nothing further back.
    func testAFinishedWriterTakesNoMoreRows() {
        let insert = SAInsertStatementWriter(table: "t", columns: ["a"])!
        XCTAssertTrue(insert.append(row: ["1"]))
        XCTAssertEqual(insert.finish(), "INSERT INTO `t` (`a`)\nVALUES\n\t(1);\n")
        XCTAssertFalse(insert.append(row: ["2"]))
        XCTAssertNil(insert.finish())

        let update = SAUpdateStatementWriter(database: "mydb", table: "people", columns: ["id", "a"],
                                             keyColumnIndexes: IndexSet(integer: 0), generatedColumnIndexes: IndexSet())!
        XCTAssertTrue(update.append(row: ["1", "2"]))
        XCTAssertEqual(update.finish(), "UPDATE `mydb`.`people` SET `a` = 2\nWHERE `id` = 1;\n")
        XCTAssertFalse(update.append(row: ["3", "4"]))
        XCTAssertNil(update.finish())
    }

    /// A writer refuses a row of the wrong width and appends nothing of it.
    func testAWriterRefusesARowOfTheWrongWidth() {
        let writer = SAInsertStatementWriter(table: "t", columns: ["a", "b"])!
        XCTAssertTrue(writer.append(row: ["1", "2"]))
        XCTAssertFalse(writer.append(row: ["3"]))
        XCTAssertEqual(writer.finish(), "INSERT INTO `t` (`a`, `b`)\nVALUES\n\t(1, 2);\n")
    }

    // MARK: - UPDATE

    func testEachRowBecomesItsOwnUpdateStatement() {
        let sql = SASQLStatementBuilder.updateStatements(
            database: nil,
            table: "people",
            columns: ["id", "name"],
            keyColumnIndexes: IndexSet(integer: 0),
            generatedColumnIndexes: IndexSet(),
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
            database: nil,
            table: "t",
            columns: ["id", "a", "b"],
            keyColumnIndexes: IndexSet(integer: 0),
            generatedColumnIndexes: IndexSet(),
            rows: [["1", "'x'", "'y'"]]
        )

        XCTAssertEqual(sql, "UPDATE `t` SET `a` = 'x', `b` = 'y'\nWHERE `id` = 1;\n")
    }

    func testACompositeKeyMatchesOnEveryKeyColumn() {
        let sql = SASQLStatementBuilder.updateStatements(
            database: nil,
            table: "t",
            columns: ["tenant", "id", "a"],
            keyColumnIndexes: IndexSet([0, 1]),
            generatedColumnIndexes: IndexSet(),
            rows: [["7", "1", "'x'"]]
        )

        XCTAssertEqual(sql, "UPDATE `t` SET `a` = 'x'\nWHERE `tenant` = 7 AND `id` = 1;\n")
    }

    /// `= NULL` is never true in MySQL, so a naive `WHERE` would match no rows at all and the
    /// statement would run clean while doing nothing.
    func testANullKeyIsMatchedWithIsNull() {
        let sql = SASQLStatementBuilder.updateStatements(
            database: nil,
            table: "t",
            columns: ["k", "a"],
            keyColumnIndexes: IndexSet(integer: 0),
            generatedColumnIndexes: IndexSet(),
            rows: [["NULL", "'x'"]]
        )

        XCTAssertEqual(sql, "UPDATE `t` SET `a` = 'x'\nWHERE `k` IS NULL;\n")
    }

    func testANullValueIsStillAssignedWithEquals() {
        let sql = SASQLStatementBuilder.updateStatements(
            database: nil,
            table: "t",
            columns: ["id", "a"],
            keyColumnIndexes: IndexSet(integer: 0),
            generatedColumnIndexes: IndexSet(),
            rows: [["1", "NULL"]]
        )

        XCTAssertEqual(sql, "UPDATE `t` SET `a` = NULL\nWHERE `id` = 1;\n")
    }

    func testUpdateIdentifiersAreBacktickQuotedAndInternalBackticksDoubled() {
        let sql = SASQLStatementBuilder.updateStatements(
            database: nil,
            table: "we`ird",
            columns: ["i`d", "a`b"],
            keyColumnIndexes: IndexSet(integer: 0),
            generatedColumnIndexes: IndexSet(),
            rows: [["1", "'x'"]]
        )

        XCTAssertEqual(sql, "UPDATE `we``ird` SET `a``b` = 'x'\nWHERE `i``d` = 1;\n")
    }

    func testUpdatesFromNoSingleTableGetAPlaceholderName() {
        let sql = SASQLStatementBuilder.updateStatements(
            database: nil,
            table: nil,
            columns: ["id", "a"],
            keyColumnIndexes: IndexSet(integer: 0),
            generatedColumnIndexes: IndexSet(),
            rows: [["1", "'x'"]]
        )

        XCTAssertEqual(sql, "UPDATE `<table>` SET `a` = 'x'\nWHERE `id` = 1;\n")
    }

    /// The statement keeps naming the database it was read from, so pasting it into a document
    /// on another database cannot silently retarget it to that database's table of the same
    /// name.
    func testAnUpdateNamesTheOriginDatabaseBesideTheOriginTable() {
        let sql = SASQLStatementBuilder.updateStatements(
            database: "B",
            table: "people",
            columns: ["id", "name"],
            keyColumnIndexes: IndexSet(integer: 0),
            generatedColumnIndexes: IndexSet(),
            rows: [["1", "'Ada'"]]
        )

        XCTAssertEqual(sql, "UPDATE `B`.`people` SET `name` = 'Ada'\nWHERE `id` = 1;\n")
    }

    /// Both halves of a qualified target are identifiers in their own right.
    func testBothPartsOfAQualifiedUpdateTargetAreBacktickQuoted() {
        let sql = SASQLStatementBuilder.updateStatements(
            database: "we`ird",
            table: "ta`ble",
            columns: ["id", "a"],
            keyColumnIndexes: IndexSet(integer: 0),
            generatedColumnIndexes: IndexSet(),
            rows: [["1", "'x'"]]
        )

        XCTAssertEqual(sql, "UPDATE `we``ird`.`ta``ble` SET `a` = 'x'\nWHERE `id` = 1;\n")
    }

    /// A database prefix on the placeholder would name a database the rows did not come from.
    func testAnUpdateTargetWithNoTableStaysThePlaceholder() {
        let sql = SASQLStatementBuilder.updateStatements(
            database: "mydb",
            table: nil,
            columns: ["id", "a"],
            keyColumnIndexes: IndexSet(integer: 0),
            generatedColumnIndexes: IndexSet(),
            rows: [["1", "'x'"]]
        )

        XCTAssertEqual(sql, "UPDATE `<table>` SET `a` = 'x'\nWHERE `id` = 1;\n")
    }

    /// Without a key there is no way to tell the intended row from any other, and an `UPDATE`
    /// with no `WHERE` would rewrite the whole table.
    func testRowsWithoutAKeyYieldNoStatement() {
        XCTAssertNil(
            SASQLStatementBuilder.updateStatements(
                database: nil,
                table: "t",
                columns: ["a", "b"],
                keyColumnIndexes: IndexSet(),
                generatedColumnIndexes: IndexSet(),
                rows: [["'x'", "'y'"]]
            )
        )
    }

    func testAKeyIndexOutsideTheColumnListIsIgnored() {
        XCTAssertNil(
            SASQLStatementBuilder.updateStatements(
                database: nil,
                table: "t",
                columns: ["a"],
                keyColumnIndexes: IndexSet(integer: 9),
                generatedColumnIndexes: IndexSet(),
                rows: [["'x'"]]
            )
        )
    }

    /// A table that is nothing but its primary key has nothing an `UPDATE` could set.
    func testColumnsThatAreAllKeyYieldNoStatement() {
        XCTAssertNil(
            SASQLStatementBuilder.updateStatements(
                database: nil,
                table: "t",
                columns: ["tenant", "id"],
                keyColumnIndexes: IndexSet([0, 1]),
                generatedColumnIndexes: IndexSet(),
                rows: [["7", "1"]]
            )
        )
    }

    func testNothingToUpdateYieldsNoStatement() {
        XCTAssertNil(
            SASQLStatementBuilder.updateStatements(
                database: nil,
                table: "t",
                columns: [],
                keyColumnIndexes: IndexSet(integer: 0),
                generatedColumnIndexes: IndexSet(),
                rows: [["1"]]
            )
        )
        XCTAssertNil(
            SASQLStatementBuilder.updateStatements(
                database: nil,
                table: "t",
                columns: ["id", "a"],
                keyColumnIndexes: IndexSet(integer: 0),
                generatedColumnIndexes: IndexSet(),
                rows: []
            )
        )
    }

    func testAnUpdateRowOfTheWrongWidthYieldsNoStatement() {
        XCTAssertNil(
            SASQLStatementBuilder.updateStatements(
                database: nil,
                table: "t",
                columns: ["id", "a"],
                keyColumnIndexes: IndexSet(integer: 0),
                generatedColumnIndexes: IndexSet(),
                rows: [["1", "'x'"], ["2"]]
            )
        )
    }

    // MARK: - UPDATE origin (the metadata the caller supplies)

    /// A query result field shaped as the server delivers it: `name` is whatever the SELECT
    /// wrote, `org_name` the column actually read, `org_table`/`db` where it lives, and
    /// `PRI_KEY_FLAG` whether it is part of the key.
    private func queryField(_ name: String, origin: String, table: String = "people", database: String = "mydb", keyFlagged: Bool = false) -> [String: Any] {
        [
            "name": name,
            "org_name": origin,
            "org_table": table,
            "db": database,
            "PRI_KEY_FLAG": keyFlagged ? 1 : 0,
        ]
    }

    /// A table content field shaped as the SHOW CREATE TABLE parse delivers it: the column is
    /// the table's own, and only key columns carry `isprimarykey`.
    private func contentField(_ name: String, keyFlagged: Bool = false) -> [String: Any] {
        var field: [String: Any] = ["name": name]
        if keyFlagged { field["isprimarykey"] = 1 }
        return field
    }

    /// The UPDATE path must follow where a column really came from — `org_name` — not the
    /// alias the SELECT gave it, which names no column to assign or match.
    func testFieldOriginsFollowTheServersOriginMetadataRatherThanAliases() {
        let origins = SASQLStatementBuilder.fieldOrigins(
            fromFieldDefinitions: [
                queryField("user_label", origin: "name"),
                queryField("The Key", origin: "id", keyFlagged: true),
            ],
            table: nil,
            database: nil
        )

        XCTAssertEqual(origins.map(\.name), ["name", "id"])
        XCTAssertEqual(origins.map(\.table), ["people", "people"])
        XCTAssertEqual(origins.map(\.database), ["mydb", "mydb"])
        XCTAssertEqual(origins.map(\.primaryKeyFlagged), [false, true])
    }

    /// Table content metadata carries no origin fields of its own — its columns belong to the
    /// table and database the caller passes in.
    func testFieldOriginsFallBackToTheTableMetadata() {
        let origins = SASQLStatementBuilder.fieldOrigins(
            fromFieldDefinitions: [
                contentField("tenant", keyFlagged: true),
                contentField("name"),
            ],
            table: "people",
            database: "mydb"
        )

        XCTAssertEqual(origins.map(\.name), ["tenant", "name"])
        XCTAssertEqual(origins.map(\.table), ["people", "people"])
        XCTAssertEqual(origins.map(\.database), ["mydb", "mydb"])
        XCTAssertEqual(origins.map(\.primaryKeyFlagged), [true, false])
    }

    /// An expression such as `SELECT COUNT(*)` read no column, so nothing in the row ties it
    /// to one to update through.
    func testFieldsWithoutAnOriginColumnExtractAnEmptyName() {
        let origins = SASQLStatementBuilder.fieldOrigins(
            fromFieldDefinitions: [queryField("COUNT(*)", origin: "")],
            table: nil,
            database: nil
        )

        XCTAssertEqual(origins.first?.name, "")
    }

    /// For a table keyed by (tenant, id), a projection carrying only tenant supplies tenant's
    /// key flag but not id — matching on tenant alone would update every row of that tenant.
    /// What counts is the origin table's complete key, and every part of it must be present.
    func testAPartiallyProjectedCompositeKeyYieldsNoUpdateOrigin() {
        let fields = SASQLStatementBuilder.fieldOrigins(
            fromFieldDefinitions: [
                queryField("tenant", origin: "tenant", keyFlagged: true),
                queryField("name", origin: "name"),
            ],
            table: nil,
            database: nil
        )

        XCTAssertNil(SASQLStatementBuilder.updateOrigin(forFields: fields, tableKeyColumns: ["tenant", "id"], generatedColumns: []))
    }

    func testACompleteCompositeKeyYieldsTheKeyIndexes() {
        let fields = SASQLStatementBuilder.fieldOrigins(
            fromFieldDefinitions: [
                queryField("name", origin: "name"),
                queryField("The Key", origin: "id", keyFlagged: true),
                queryField("tenant", origin: "tenant", keyFlagged: true),
            ],
            table: nil,
            database: nil
        )

        let origin = SASQLStatementBuilder.updateOrigin(forFields: fields, tableKeyColumns: ["tenant", "id"], generatedColumns: [])

        XCTAssertEqual(origin?.table, "people")
        XCTAssertEqual(origin?.columns, ["name", "id", "tenant"])
        XCTAssertEqual(origin?.keyColumnIndexes, IndexSet([1, 2]))
    }

    /// The whole point of the exercise: whatever the SELECT aliased columns to, the statement
    /// must update the origin table under its real column names.
    func testAnAliasedProjectionUpdatesOriginColumnsOfTheOriginTable() {
        let fields = SASQLStatementBuilder.fieldOrigins(
            fromFieldDefinitions: [
                queryField("user_label", origin: "name"),
                queryField("The Key", origin: "id", keyFlagged: true),
            ],
            table: nil,
            database: nil
        )
        let origin = SASQLStatementBuilder.updateOrigin(forFields: fields, tableKeyColumns: ["id"], generatedColumns: [])!

        XCTAssertEqual(origin.database, "mydb")

        let sql = SASQLStatementBuilder.updateStatements(
            database: nil,
            table: origin.table,
            columns: origin.columns,
            keyColumnIndexes: origin.keyColumnIndexes,
            generatedColumnIndexes: origin.generatedColumnIndexes,
            rows: [["'Ada'", "1"]]
        )

        XCTAssertEqual(sql, "UPDATE `people` SET `name` = 'Ada'\nWHERE `id` = 1;\n")
    }

    /// A document on database A reading `SELECT id, name FROM B.people`: the origin is B's
    /// people, and the statement must say so, or pasting it into the A document would resolve
    /// the unqualified name against A and update A.people.
    func testAResultFromAnotherDatabaseUpdatesThatDatabasesTable() {
        let fields = SASQLStatementBuilder.fieldOrigins(
            fromFieldDefinitions: [
                queryField("id", origin: "id", database: "B", keyFlagged: true),
                queryField("name", origin: "name", database: "B"),
            ],
            table: nil,
            database: nil
        )
        let origin = SASQLStatementBuilder.updateOrigin(forFields: fields, tableKeyColumns: ["id"], generatedColumns: [])!

        XCTAssertEqual(origin.database, "B")

        let sql = SASQLStatementBuilder.updateStatements(
            database: origin.database,
            table: origin.table,
            columns: origin.columns,
            keyColumnIndexes: origin.keyColumnIndexes,
            generatedColumnIndexes: origin.generatedColumnIndexes,
            rows: [["1", "'Ada'"]]
        )

        XCTAssertEqual(sql, "UPDATE `B`.`people` SET `name` = 'Ada'\nWHERE `id` = 1;\n")
    }

    /// Table content metadata decides by the same rules: its key columns are the table's own
    /// `isprimarykey` entries, projected in full.
    func testACompleteCompositeKeyFromTableMetadataYieldsTheKeyIndexes() {
        let fields = SASQLStatementBuilder.fieldOrigins(
            fromFieldDefinitions: [
                contentField("tenant", keyFlagged: true),
                contentField("name"),
                contentField("id", keyFlagged: true),
            ],
            table: "people",
            database: "mydb"
        )

        let origin = SASQLStatementBuilder.updateOrigin(forFields: fields, tableKeyColumns: ["tenant", "id"], generatedColumns: [])

        XCTAssertEqual(origin?.table, "people")
        XCTAssertEqual(origin?.columns, ["tenant", "name", "id"])
        XCTAssertEqual(origin?.keyColumnIndexes, IndexSet([0, 2]))
    }

    func testFieldsSpanningTablesYieldNoUpdateOrigin() {
        let fields = SASQLStatementBuilder.fieldOrigins(
            fromFieldDefinitions: [
                queryField("a", origin: "a", table: "people"),
                queryField("b", origin: "b", table: "orders"),
            ],
            table: nil,
            database: nil
        )

        XCTAssertNil(SASQLStatementBuilder.updateOrigin(forFields: fields, tableKeyColumns: ["a"], generatedColumns: []))
    }

    /// `SELECT id AS a, id AS b FROM people` would assign to the same column twice, which the
    /// server rejects.
    func testRepeatedOriginColumnsYieldNoUpdateOrigin() {
        let fields = SASQLStatementBuilder.fieldOrigins(
            fromFieldDefinitions: [
                queryField("a", origin: "id", keyFlagged: true),
                queryField("b", origin: "id", keyFlagged: true),
                queryField("c", origin: "name"),
            ],
            table: nil,
            database: nil
        )

        XCTAssertNil(SASQLStatementBuilder.updateOrigin(forFields: fields, tableKeyColumns: ["id"], generatedColumns: []))
    }

    /// A column named like a key part that the projection's own metadata did not flag means
    /// two sources disagree, which is not something to copy statements over.
    func testAKeyNameTheProjectionDidNotFlagYieldsNoUpdateOrigin() {
        let fields = SASQLStatementBuilder.fieldOrigins(
            fromFieldDefinitions: [
                queryField("id", origin: "id"),
                queryField("name", origin: "name"),
            ],
            table: nil,
            database: nil
        )

        XCTAssertNil(SASQLStatementBuilder.updateOrigin(forFields: fields, tableKeyColumns: ["id"], generatedColumns: []))
    }

    func testAProjectionOfNothingButTheKeyYieldsNoUpdateOrigin() {
        let fields = SASQLStatementBuilder.fieldOrigins(
            fromFieldDefinitions: [
                queryField("tenant", origin: "tenant", keyFlagged: true),
                queryField("id", origin: "id", keyFlagged: true),
            ],
            table: nil,
            database: nil
        )

        XCTAssertNil(SASQLStatementBuilder.updateOrigin(forFields: fields, tableKeyColumns: ["tenant", "id"], generatedColumns: []))
    }

    func testATableWithNoKeyYieldsNoUpdateOrigin() {
        let fields = SASQLStatementBuilder.fieldOrigins(
            fromFieldDefinitions: [queryField("a", origin: "a")],
            table: nil,
            database: nil
        )

        XCTAssertNil(SASQLStatementBuilder.updateOrigin(forFields: fields, tableKeyColumns: [], generatedColumns: []))
    }

    /// The caller produces the finished literal — quoting binary data needs the connection's
    /// character set — so the builder only has to match what it is given, as-is.
    func testABinaryKeyLiteralIsMatchedAsIs() {
        let sql = SASQLStatementBuilder.updateStatements(
            database: nil,
            table: "t",
            columns: ["id", "a"],
            keyColumnIndexes: IndexSet(integer: 0),
            generatedColumnIndexes: IndexSet(),
            rows: [["X'0a1b'", "'x'"]]
        )

        XCTAssertEqual(sql, "UPDATE `t` SET `a` = 'x'\nWHERE `id` = X'0a1b';\n")
    }

    // MARK: - UPDATE plausibility (menu validation)

    /// Menu items validate on every pass and must not talk to the server, so plausibility can
    /// only judge the projection's own shape. A partially-projected composite key looks
    /// plausible here and is refused at copy time, when the origin table's complete key is
    /// known.
    func testAPartialCompositeProjectionIsPlausibleForTheMenu() {
        let fields = SASQLStatementBuilder.fieldOrigins(
            fromFieldDefinitions: [
                queryField("tenant", origin: "tenant", keyFlagged: true),
                queryField("name", origin: "name"),
            ],
            table: nil,
            database: nil
        )

        XCTAssertTrue(SASQLStatementBuilder.updateCopyPlausible(forFields: fields))
    }

    func testWhatCouldNeverUpdateIsNotPlausibleForTheMenu() {
        // An expression carries no origin column.
        XCTAssertFalse(
            SASQLStatementBuilder.updateCopyPlausible(
                forFields: SASQLStatementBuilder.fieldOrigins(
                    fromFieldDefinitions: [
                        queryField("COUNT(*)", origin: ""),
                        queryField("name", origin: "name"),
                    ],
                    table: nil,
                    database: nil
                )
            )
        )

        // A join spans tables.
        XCTAssertFalse(
            SASQLStatementBuilder.updateCopyPlausible(
                forFields: SASQLStatementBuilder.fieldOrigins(
                    fromFieldDefinitions: [
                        queryField("a", origin: "a", table: "people"),
                        queryField("b", origin: "b", table: "orders"),
                    ],
                    table: nil,
                    database: nil
                )
            )
        )

        // No key part at all.
        XCTAssertFalse(
            SASQLStatementBuilder.updateCopyPlausible(
                forFields: SASQLStatementBuilder.fieldOrigins(
                    fromFieldDefinitions: [
                        queryField("a", origin: "a"),
                        queryField("b", origin: "b"),
                    ],
                    table: nil,
                    database: nil
                )
            )
        )

        // Nothing but the key to assign.
        XCTAssertFalse(
            SASQLStatementBuilder.updateCopyPlausible(
                forFields: SASQLStatementBuilder.fieldOrigins(
                    fromFieldDefinitions: [
                        queryField("id", origin: "id", keyFlagged: true),
                    ],
                    table: nil,
                    database: nil
                )
            )
        )
    }

    // MARK: - Generated columns

    /// The reported case, through the metadata shape a query result really carries:
    /// `CREATE TABLE t (id INT PRIMARY KEY, a INT, b INT GENERATED ALWAYS AS (a+1) STORED)`
    /// selected as `SELECT id, a, b`. Query metadata has no generated-column marker of its own,
    /// so `b` survives into the projection; assigning it is what the server refuses, and so the
    /// statement has to set `a` alone.
    func testAGeneratedColumnOfAQueryResultIsNotAssigned() {
        let fields = SASQLStatementBuilder.fieldOrigins(
            fromFieldDefinitions: [
                queryField("id", origin: "id", keyFlagged: true),
                queryField("a", origin: "a"),
                queryField("b", origin: "b"),
            ],
            table: nil,
            database: nil
        )
        let origin = SASQLStatementBuilder.updateOrigin(forFields: fields, tableKeyColumns: ["id"], generatedColumns: ["b"])!

        // The column stays in the projection, so the row literals stay parallel to it.
        XCTAssertEqual(origin.columns, ["id", "a", "b"])
        XCTAssertEqual(origin.generatedColumnIndexes, IndexSet(integer: 2))

        let sql = SASQLStatementBuilder.updateStatements(
            database: origin.database,
            table: origin.table,
            columns: origin.columns,
            keyColumnIndexes: origin.keyColumnIndexes,
            generatedColumnIndexes: origin.generatedColumnIndexes,
            rows: [["1", "2", "3"]]
        )

        XCTAssertEqual(sql, "UPDATE `mydb`.`people` SET `a` = 2\nWHERE `id` = 1;\n")
    }

    /// A STORED generated column is allowed to be part of the primary key. It must go on
    /// matching rows in `WHERE` — dropping it would widen the match — while still never being
    /// assigned.
    func testAGeneratedKeyColumnStillMatchesRowsWithoutBeingAssigned() {
        let fields = SASQLStatementBuilder.fieldOrigins(
            fromFieldDefinitions: [
                queryField("id", origin: "id", keyFlagged: true),
                queryField("a", origin: "a"),
            ],
            table: nil,
            database: nil
        )
        let origin = SASQLStatementBuilder.updateOrigin(forFields: fields, tableKeyColumns: ["id"], generatedColumns: ["id"])!

        let sql = SASQLStatementBuilder.updateStatements(
            database: origin.database,
            table: origin.table,
            columns: origin.columns,
            keyColumnIndexes: origin.keyColumnIndexes,
            generatedColumnIndexes: origin.generatedColumnIndexes,
            rows: [["1", "2"]]
        )

        XCTAssertEqual(sql, "UPDATE `mydb`.`people` SET `a` = 2\nWHERE `id` = 1;\n")
    }

    /// With the key on one side and generated columns on the other, there is no column left that
    /// anybody is allowed to assign. Refusing the copy is the honest answer; emitting a statement
    /// the server would reject is not.
    func testAProjectionOfNothingButTheKeyAndGeneratedColumnsYieldsNoUpdateOrigin() {
        let fields = SASQLStatementBuilder.fieldOrigins(
            fromFieldDefinitions: [
                queryField("id", origin: "id", keyFlagged: true),
                queryField("b", origin: "b"),
            ],
            table: nil,
            database: nil
        )

        XCTAssertNil(SASQLStatementBuilder.updateOrigin(forFields: fields, tableKeyColumns: ["id"], generatedColumns: ["b"]))
    }

    /// The origin table may generate a column the SELECT never asked for. It has no position in
    /// this projection, so it has nothing to exclude and must not shift the indexes of the
    /// columns that do.
    func testAGeneratedColumnTheProjectionLeftOutChangesNothing() {
        let fields = SASQLStatementBuilder.fieldOrigins(
            fromFieldDefinitions: [
                queryField("id", origin: "id", keyFlagged: true),
                queryField("a", origin: "a"),
            ],
            table: nil,
            database: nil
        )
        let origin = SASQLStatementBuilder.updateOrigin(forFields: fields, tableKeyColumns: ["id"], generatedColumns: ["c"])!

        XCTAssertEqual(origin.generatedColumnIndexes, IndexSet())

        let sql = SASQLStatementBuilder.updateStatements(
            database: origin.database,
            table: origin.table,
            columns: origin.columns,
            keyColumnIndexes: origin.keyColumnIndexes,
            generatedColumnIndexes: origin.generatedColumnIndexes,
            rows: [["1", "2"]]
        )

        XCTAssertEqual(sql, "UPDATE `mydb`.`people` SET `a` = 2\nWHERE `id` = 1;\n")
    }

    /// Table content metadata marks its generated columns, so they are dropped long before the
    /// builder sees them and no column name is ever passed in. That path must keep producing
    /// exactly what it did before generated columns were accounted for here at all.
    func testTableContentMetadataNeedsNoGeneratedColumnNames() {
        let fields = SASQLStatementBuilder.fieldOrigins(
            fromFieldDefinitions: [
                contentField("id", keyFlagged: true),
                contentField("a"),
            ],
            table: "people",
            database: "mydb"
        )
        let origin = SASQLStatementBuilder.updateOrigin(forFields: fields, tableKeyColumns: ["id"], generatedColumns: [])!

        XCTAssertEqual(origin.generatedColumnIndexes, IndexSet())

        let sql = SASQLStatementBuilder.updateStatements(
            database: origin.database,
            table: origin.table,
            columns: origin.columns,
            keyColumnIndexes: origin.keyColumnIndexes,
            generatedColumnIndexes: origin.generatedColumnIndexes,
            rows: [["1", "2"]]
        )

        XCTAssertEqual(sql, "UPDATE `mydb`.`people` SET `a` = 2\nWHERE `id` = 1;\n")
    }

    // MARK: - Origin resolution

    /// The reported case end to end, from the metadata a query result really carries: `SELECT id,
    /// a, b` from `CREATE TABLE people (id INT PRIMARY KEY, a INT, b INT GENERATED ALWAYS AS (a+1)
    /// STORED)`. Nothing in the fields marks `b`, so it is the origin table's columns, asked of
    /// the server, that keep it out of `SET`.
    func testAQueryResultsGeneratedColumnIsFoundOnTheServerAndNotAssigned() {
        let lookup = CannedOriginLookup(columns: [["id", ""], ["a", ""], ["b", "STORED GENERATED"]])

        let origin = SAUpdateCopyOriginResolver.origin(
            fieldDefinitions: [
                queryField("id", origin: "id", keyFlagged: true),
                queryField("a", origin: "a"),
                queryField("b", origin: "b"),
            ],
            table: nil,
            database: nil,
            tableColumnDefinitions: nil,
            lookup: lookup
        )!

        XCTAssertEqual(origin.generatedColumnIndexes, IndexSet(integer: 2))
        XCTAssertEqual(
            SASQLStatementBuilder.updateStatements(
                database: origin.database,
                table: origin.table,
                columns: origin.columns,
                keyColumnIndexes: origin.keyColumnIndexes,
                generatedColumnIndexes: origin.generatedColumnIndexes,
                rows: [["1", "2", "3"]]
            ),
            "UPDATE `mydb`.`people` SET `a` = 2\nWHERE `id` = 1;\n"
        )

        // Both lookups ask about the origin table, in its own database.
        XCTAssertEqual(lookup.queries.count, 2)
        XCTAssertTrue(lookup.queries.allSatisfy { $0.contains("TABLE_SCHEMA = 'mydb' AND TABLE_NAME = 'people'") })
    }

    /// MySQL 8 reports `DEFAULT_GENERATED` for a column with an expression default, such as a
    /// `TIMESTAMP DEFAULT CURRENT_TIMESTAMP`. That column is assignable like any other, so the
    /// copied UPDATE has to keep the value that was selected.
    func testADefaultGeneratedColumnIsStillAssigned() {
        let lookup = CannedOriginLookup(columns: [
            ["id", ""],
            ["created", "DEFAULT_GENERATED"],
            ["updated", "DEFAULT_GENERATED on update CURRENT_TIMESTAMP"],
        ])

        let origin = SAUpdateCopyOriginResolver.origin(
            fieldDefinitions: [
                queryField("id", origin: "id", keyFlagged: true),
                queryField("created", origin: "created"),
                queryField("updated", origin: "updated"),
            ],
            table: nil,
            database: nil,
            tableColumnDefinitions: nil,
            lookup: lookup
        )!

        XCTAssertEqual(origin.generatedColumnIndexes, IndexSet())
        XCTAssertEqual(
            SASQLStatementBuilder.updateStatements(
                database: origin.database,
                table: origin.table,
                columns: origin.columns,
                keyColumnIndexes: origin.keyColumnIndexes,
                generatedColumnIndexes: origin.generatedColumnIndexes,
                rows: [["1", "'2026-10-01 10:00:00'", "'2026-10-02 11:00:00'"]]
            ),
            "UPDATE `mydb`.`people` SET `created` = '2026-10-01 10:00:00', `updated` = '2026-10-02 11:00:00'\nWHERE `id` = 1;\n"
        )
    }

    /// Every EXTRA a supported server reports for a generated column, and the ones it reports
    /// for columns that are not generated, however much they look it.
    func testGeneratedColumnsAreToldApartByTheirExtraWords() {
        let generated = ["VIRTUAL GENERATED", "STORED GENERATED", "VIRTUAL", "PERSISTENT", "STORED GENERATED INVISIBLE"]
        let assignable = ["", "auto_increment", "DEFAULT_GENERATED", "DEFAULT_GENERATED on update CURRENT_TIMESTAMP",
                          "on update current_timestamp()", "INVISIBLE"]

        for extra in generated {
            XCTAssertTrue(SAUpdateCopyOriginResolver.isGeneratedColumn(extra: extra), "\(extra) is generated")
        }
        for extra in assignable {
            XCTAssertFalse(SAUpdateCopyOriginResolver.isGeneratedColumn(extra: extra), "\(extra) is assignable")
        }
    }

    /// A lookup the server cannot answer leaves the copy refused rather than guessed at, as does
    /// having no server to ask at all.
    func testAQueryResultWhoseLookupsFailYieldsNoUpdateOrigin() {
        let fields = [
            queryField("id", origin: "id", keyFlagged: true),
            queryField("a", origin: "a"),
        ]

        let keyFails = CannedOriginLookup(columns: [["id", ""], ["a", ""]])
        keyFails.keyColumns = nil
        XCTAssertNil(SAUpdateCopyOriginResolver.origin(fieldDefinitions: fields, table: nil, database: nil, tableColumnDefinitions: nil, lookup: keyFails))

        let columnsFail = CannedOriginLookup(columns: nil)
        XCTAssertNil(SAUpdateCopyOriginResolver.origin(fieldDefinitions: fields, table: nil, database: nil, tableColumnDefinitions: nil, lookup: columnsFail))

        XCTAssertNil(SAUpdateCopyOriginResolver.origin(fieldDefinitions: fields, table: nil, database: nil, tableColumnDefinitions: nil, lookup: nil))
    }

    /// Table content metadata covers the whole table, so its key comes from the table's own column
    /// definitions; only the generated columns are asked of the server.
    func testTableContentMetadataAsksTheServerOnlyForGeneratedColumns() {
        let lookup = CannedOriginLookup(columns: [["id", ""], ["a", ""], ["b", ""]])

        let origin = SAUpdateCopyOriginResolver.origin(
            fieldDefinitions: [contentField("id", keyFlagged: true), contentField("a")],
            table: "people",
            database: "mydb",
            tableColumnDefinitions: [contentField("id", keyFlagged: true), contentField("a"), contentField("b")],
            lookup: lookup
        )

        XCTAssertEqual(origin?.keyColumnIndexes, IndexSet(integer: 0))
        XCTAssertEqual(origin?.generatedColumnIndexes, IndexSet())
        XCTAssertEqual(lookup.queries.count, 1)
        XCTAssertTrue(lookup.queries.allSatisfy { $0.contains("information_schema.COLUMNS") && $0.contains("TABLE_SCHEMA = 'mydb' AND TABLE_NAME = 'people'") })
    }

    /// MariaDB before 10.2 writes generated columns as `AS (a+1) VIRTUAL` and
    /// `AS (a*2) PERSISTENT` in SHOW CREATE TABLE, without `GENERATED ALWAYS`, so the table
    /// definition parser leaves them unmarked and they reach the copy as ordinary content
    /// columns. The server's own EXTRA (`VIRTUAL`, `PERSISTENT` on 10.1) keeps them out of `SET`.
    func testTableContentGeneratedColumnsTheParserMissesAreFoundOnTheServer() {
        let lookup = CannedOriginLookup(columns: [["id", ""], ["a", ""], ["v", "VIRTUAL"], ["p", "PERSISTENT"]])

        let origin = SAUpdateCopyOriginResolver.origin(
            fieldDefinitions: [contentField("id", keyFlagged: true), contentField("a"), contentField("v"), contentField("p")],
            table: "people",
            database: "mydb",
            tableColumnDefinitions: [contentField("id", keyFlagged: true), contentField("a"), contentField("v"), contentField("p")],
            lookup: lookup
        )!

        XCTAssertEqual(origin.generatedColumnIndexes, IndexSet([2, 3]))
        XCTAssertEqual(
            SASQLStatementBuilder.updateStatements(
                database: origin.database,
                table: origin.table,
                columns: origin.columns,
                keyColumnIndexes: origin.keyColumnIndexes,
                generatedColumnIndexes: origin.generatedColumnIndexes,
                rows: [["1", "2", "3", "4"]]
            ),
            "UPDATE `mydb`.`people` SET `a` = 2\nWHERE `id` = 1;\n"
        )
    }

    /// Table content rows are refused too when the generated columns cannot be asked of the
    /// server, rather than copied with a `SET` the server may reject.
    func testTableContentWhoseGeneratedColumnLookupFailsYieldsNoUpdateOrigin() {
        let fields = [contentField("id", keyFlagged: true), contentField("a")]

        XCTAssertNil(SAUpdateCopyOriginResolver.origin(fieldDefinitions: fields, table: "people", database: "mydb",
                                                        tableColumnDefinitions: fields, lookup: CannedOriginLookup(columns: nil)))
        XCTAssertNil(SAUpdateCopyOriginResolver.origin(fieldDefinitions: fields, table: "people", database: "mydb",
                                                        tableColumnDefinitions: fields, lookup: nil))
    }
}

/// Answers the resolver's server lookups with canned rows, as `information_schema` would for
/// `mydb`.`people`, and records the queries it was asked.
private final class CannedOriginLookup: NSObject, SAUpdateOriginLookup {

    /// The primary key columns, or `nil` for a lookup that fails.
    var keyColumns: [String]? = ["id"]

    /// COLUMN_NAME and EXTRA of every column, or `nil` for a lookup that fails.
    let columns: [[String]]?

    private(set) var queries: [String] = []

    init(columns: [[String]]?) {
        self.columns = columns
    }

    func rows(forQuery query: String, database: String) -> [[Any]]? {
        queries.append(query)
        return query.contains("KEY_COLUMN_USAGE") ? keyColumns?.map { [$0] } : columns
    }

    func quotedString(_ value: String) -> String? {
        "'" + value.replacingOccurrences(of: "'", with: "''") + "'"
    }
}
