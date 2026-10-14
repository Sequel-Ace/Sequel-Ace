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
}
