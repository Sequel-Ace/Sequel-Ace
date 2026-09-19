//
//  SASearchAllTablesTests.swift
//  Unit Tests
//
//  Created by Sequel-Ace contributors on 2026.09.19.
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import Cocoa
import XCTest

/// The `sqlWhereExpressionWithBinary:error:` signature of `SPRuleFilterController`, which `perform(_:)`
/// cannot call because it takes a `BOOL` and an `NSError **`.
@objc private protocol SASearchAllTablesRuleFilterSQLGenerating {
    @objc(sqlWhereExpressionWithBinary:error:)
    func sqlWhereExpression(withBinary isBinary: Bool, error: NSErrorPointer) -> String?
}

/// Covers the pure parts of Search in All Tables (issue #152).
final class SASearchAllTablesTests: XCTestCase {

    private typealias Builder = SASearchAllTablesQueryBuilder
    private typealias ColumnRow = (table: String, column: String, dataType: String, tableType: String)

    // MARK: - Column selection

    func testTextColumnsOnlySearchesCharacterAndTextTypes() {
        for type in ["char", "varchar", "tinytext", "text", "mediumtext", "longtext", "enum", "set", "json", "VARCHAR"] {
            XCTAssertEqual(Builder.columnKind(forDataType: type, textColumnsOnly: true), .text, type)
        }
        for type in ["int", "bigint", "decimal", "date", "datetime", "blob", "varbinary", "uuid", "bit", "geometry"] {
            XCTAssertNil(Builder.columnKind(forDataType: type, textColumnsOnly: true), type)
        }
    }

    func testAllColumnsScopeClassifiesOtherTypesAndSkipsBitAndSpatial() {
        XCTAssertEqual(Builder.columnKind(forDataType: "text", textColumnsOnly: false), .text)
        for type in ["tinyint", "int", "bigint", "decimal", "float", "double"] {
            XCTAssertEqual(Builder.columnKind(forDataType: type, textColumnsOnly: false), .numeric, type)
        }
        for type in ["date", "time", "datetime", "timestamp", "year"] {
            XCTAssertEqual(Builder.columnKind(forDataType: type, textColumnsOnly: false), .temporal, type)
        }
        for type in ["binary", "varbinary", "blob", "longblob", "uuid", "inet6"] {
            XCTAssertEqual(Builder.columnKind(forDataType: type, textColumnsOnly: false), .otherString, type)
        }
        for type in ["bit", "geometry", "point", "polygon", "geomcollection"] {
            XCTAssertNil(Builder.columnKind(forDataType: type, textColumnsOnly: false), type)
        }
    }

    func testTablesGroupsColumnsAndDropsTablesWithoutSearchableColumns() {
        let rows: [ColumnRow] = [
            ("customers", "id", "int", "BASE TABLE"),
            ("customers", "name", "varchar", "BASE TABLE"),
            ("customers", "notes", "text", "BASE TABLE"),
            ("measurements", "id", "int", "BASE TABLE"),
            ("measurements", "value", "double", "BASE TABLE"),
            ("seq", "next_not_cached_value", "bigint", "SEQUENCE"),
            ("versioned", "label", "char", "SYSTEM VERSIONED"),
            ("customer_names", "name", "varchar", "VIEW"),
        ]

        let tables = Builder.tables(fromColumnRows: rows, options: SASearchAllTablesOptions(searchText: "x"))

        XCTAssertEqual(tables, [
            SASearchAllTablesTable(name: "customers", isView: false, columns: [
                SASearchAllTablesColumn(name: "name", kind: .text),
                SASearchAllTablesColumn(name: "notes", kind: .text),
            ]),
            SASearchAllTablesTable(name: "versioned", isView: false, columns: [SASearchAllTablesColumn(name: "label", kind: .text)]),
        ])
    }

    func testTablesIncludesViewsAndNonTextColumnsWhenAsked() {
        let rows: [ColumnRow] = [
            ("customer_names", "name", "varchar", "VIEW"),
            ("measurements", "value", "double", "BASE TABLE"),
            ("measurements", "shape", "geometry", "BASE TABLE"),
        ]
        var options = SASearchAllTablesOptions(searchText: "x")
        options.includeViews = true
        options.textColumnsOnly = false

        let tables = Builder.tables(fromColumnRows: rows, options: options)

        XCTAssertEqual(tables, [
            SASearchAllTablesTable(name: "customer_names", isView: true, columns: [SASearchAllTablesColumn(name: "name", kind: .text)]),
            SASearchAllTablesTable(name: "measurements", isView: false, columns: [SASearchAllTablesColumn(name: "value", kind: .numeric)]),
        ])
    }

    func testTableNameFilterIsCaseInsensitiveSubstring() {
        let rows: [ColumnRow] = [
            ("Customers", "name", "varchar", "BASE TABLE"),
            ("orders", "ref", "varchar", "BASE TABLE"),
            ("old_customers", "name", "varchar", "BASE TABLE"),
        ]
        var options = SASearchAllTablesOptions(searchText: "x")
        options.tableNameFilter = " CUSTOMER "

        XCTAssertEqual(Builder.tables(fromColumnRows: rows, options: options).map(\.name), ["Customers", "old_customers"])
    }

    // MARK: - SQL

    func testLikeEscapingEscapesWildcardsAndBackslash() {
        XCTAssertEqual(Builder.likeEscaped(#"50%_off\x"#), #"50\%\_off\\x"#)
        XCTAssertEqual(Builder.likeEscaped("naïve 東京 😀"), "naïve 東京 😀")
        XCTAssertEqual(Builder.likeEscaped("it's"), "it's", "quotes are left to the connection's string quoting")
    }

    func testLikePatternWrapsContainsSearchesInWildcards() {
        XCTAssertEqual(Builder.likePattern(for: "a_b", mode: .contains), #"%a\_b%"#)
        XCTAssertEqual(Builder.likePattern(for: "a_b", mode: .exact), #"a\_b"#)
    }

    func testIdentifiersAreBacktickQuoted() {
        XCTAssertEqual(Builder.quoteIdentifier("order items"), "`order items`")
        XCTAssertEqual(Builder.quoteIdentifier("we`ird"), "`we``ird`")
    }

    func testColumnsQueryFiltersOnTheQuotedDatabase() {
        let sql = Builder.columnsQuery(quotedDatabase: "'shop'")
        XCTAssertTrue(sql.contains("WHERE c.TABLE_SCHEMA = 'shop'"), sql)
        XCTAssertTrue(sql.hasSuffix("ORDER BY c.TABLE_NAME, c.ORDINAL_POSITION"), sql)
    }

    func testCountQueryCountsRowsAndMatchesPerColumnInOneStatement() {
        let table = SASearchAllTablesTable(name: "we`ird", isView: false, columns: [
            SASearchAllTablesColumn(name: "name", kind: .text),
            SASearchAllTablesColumn(name: "e mail", kind: .text),
        ])

        let sql = Builder.countQuery(database: "shop", table: table, quotedPattern: #"'%50\\%%'"#)

        XCTAssertEqual(sql, #"SELECT COUNT(*), SUM(`name` LIKE '%50\\%%'), SUM(`e mail` LIKE '%50\\%%')"#
            + #" FROM `shop`.`we``ird` WHERE `name` LIKE '%50\\%%' OR `e mail` LIKE '%50\\%%'"#)
    }

    func testMatchReadsCountsInColumnOrderAndSkipsColumnsWithoutMatches() {
        let table = SASearchAllTablesTable(name: "customers", isView: false, columns: [
            SASearchAllTablesColumn(name: "name", kind: .text),
            SASearchAllTablesColumn(name: "notes", kind: .text),
            SASearchAllTablesColumn(name: "email", kind: .text),
        ])

        let match = Builder.match(fromCountRow: ["3", nil, "0".data(using: .utf8), NSNumber(value: 2)], table: table)

        XCTAssertEqual(match, SASearchAllTablesMatch(table: "customers", matchingRows: 3,
                                                     columnMatches: [(column: "email", rows: 2)]))
        XCTAssertNil(Builder.match(fromCountRow: ["0", nil, nil, nil], table: table))
        XCTAssertNil(Builder.match(fromCountRow: [], table: table))
    }

    // MARK: - Content filter

    func testFilterRowsUseAnOperatorEachColumnTypeOffers() {
        func row(_ kind: SASearchAllTablesColumnKind, _ mode: SASearchAllTablesMatchMode) -> [String: AnyHashable]? {
            SASearchAllTablesFilterBuilder.filterRow(column: SASearchAllTablesColumn(name: "c", kind: kind), text: #"5%_\"#, mode: mode)?
                .compactMapValues { $0 as? AnyHashable }
        }
        func expected(_ comparison: String, _ value: String) -> [String: AnyHashable] {
            ["filterClass": "expressionNode", "column": "c", "filterComparison": comparison, "filterValues": [value], "enabled": true]
        }

        XCTAssertEqual(row(.text, .contains), expected("contains", #"5\%\_\"#))
        XCTAssertEqual(row(.otherString, .contains), expected("contains", #"5\%\_\"#))
        XCTAssertEqual(row(.text, .exact), expected("LIKE", #"5\%\_\\"#))
        XCTAssertEqual(row(.numeric, .contains), expected("LIKE", #"%5\%\_\\%"#))
        XCTAssertEqual(row(.numeric, .exact), expected("LIKE", #"5\%\_\\"#))
        XCTAssertEqual(row(.temporal, .exact), expected("=", #"5%_\"#))
        XCTAssertNil(row(.temporal, .contains), "date filters have no contains operator")
    }

    func testTextWithBackslashEscapeSequenceGetsNoFilter() {
        // The rule filter would turn `\t` into a tab, so `C:\temp` could not be shown.
        for text in [#"C:\temp"#, #"a\nb"#, #"x\r"#] {
            for mode in SASearchAllTablesMatchMode.allCases {
                XCTAssertNil(SASearchAllTablesFilterBuilder.filterRow(column: SASearchAllTablesColumn(name: "c", kind: .text), text: text, mode: mode), text)
            }
        }
        XCTAssertNotNil(SASearchAllTablesFilterBuilder.filterRow(column: SASearchAllTablesColumn(name: "c", kind: .text), text: #"C:\Temp\x"#, mode: .contains))
    }

    func testSerializedFilterCombinesMatchedColumnsWithOr() throws {
        let table = SASearchAllTablesTable(name: "t", isView: false, columns: [
            SASearchAllTablesColumn(name: "a", kind: .text),
            SASearchAllTablesColumn(name: "b", kind: .text),
            SASearchAllTablesColumn(name: "d", kind: .temporal),
        ])

        let single = try XCTUnwrap(SASearchAllTablesFilterBuilder.serializedFilter(
            for: SASearchAllTablesMatch(table: "t", matchingRows: 1, columnMatches: [("b", 1)]), table: table, text: "x", mode: .contains))
        XCTAssertEqual(single["column"] as? String, "b", "a single column is a plain expression")

        let both = try XCTUnwrap(SASearchAllTablesFilterBuilder.serializedFilter(
            for: SASearchAllTablesMatch(table: "t", matchingRows: 2, columnMatches: [("a", 1), ("b", 1)]), table: table, text: "x", mode: .contains))
        XCTAssertEqual(both["filterClass"] as? String, "groupNode")
        XCTAssertEqual(both["isConjunction"] as? Bool, false)
        XCTAssertEqual((both["children"] as? [[String: Any]])?.compactMap { $0["column"] as? String }, ["a", "b"])

        XCTAssertNil(SASearchAllTablesFilterBuilder.serializedFilter(
            for: SASearchAllTablesMatch(table: "t", matchingRows: 2, columnMatches: [("a", 1), ("d", 1)]), table: table, text: "x", mode: .contains),
            "no filter rather than one that shows only some of the matching rows")
    }

    /// The filter shown for a result must select the same rows as the search:
    /// after the rule filter applies its own escaping, the LIKE pattern has to
    /// be the one the search sent (`%50\%\_off\\x%` for `50%_off\x`).
    func testRuleFilterGeneratesTheSearchPatterns() throws {
        let text = #"50%_off\x"#
        let cases: [(kind: SASearchAllTablesColumnKind, typegrouping: String, mode: SASearchAllTablesMatchMode, sql: String)] = [
            (.text, "string", .contains, #"`c` LIKE '%50\%\_off\\\\x%'"#),
            (.text, "string", .exact, #"`c` LIKE '50\\%\\_off\\\\x'"#),
            (.otherString, "blobdata", .contains, #"`c` LIKE '%50\%\_off\\\\x%'"#),
            (.numeric, "integer", .contains, #"`c` LIKE '%50\\%\\_off\\\\x%'"#),
        ]

        for testCase in cases {
            let match = SASearchAllTablesMatch(table: "t", matchingRows: 1, columnMatches: [("c", 1)])
            let table = SASearchAllTablesTable(name: "t", isView: false, columns: [SASearchAllTablesColumn(name: "c", kind: testCase.kind)])
            let filter = try XCTUnwrap(SASearchAllTablesFilterBuilder.serializedFilter(for: match, table: table, text: text, mode: testCase.mode))

            XCTAssertEqual(try whereClause(for: filter, columns: [("c", testCase.typegrouping)]), testCase.sql, "\(testCase.kind) \(testCase.mode)")

            // Both SQL strings must decode to the same LIKE pattern.
            let searchPattern = Builder.likePattern(for: text, mode: testCase.mode)
            XCTAssertEqual(likePattern(inSQL: testCase.sql), searchPattern, "\(testCase.kind) \(testCase.mode)")
        }
    }

    func testRuleFilterRestoresSeveralMatchedColumnsAsOr() throws {
        let table = SASearchAllTablesTable(name: "t", isView: false, columns: [
            SASearchAllTablesColumn(name: "a", kind: .text),
            SASearchAllTablesColumn(name: "b", kind: .text),
        ])
        let match = SASearchAllTablesMatch(table: "t", matchingRows: 2, columnMatches: [("a", 1), ("b", 1)])
        let filter = try XCTUnwrap(SASearchAllTablesFilterBuilder.serializedFilter(for: match, table: table, text: "東京", mode: .contains))

        XCTAssertEqual(try whereClause(for: filter, columns: [("a", "string"), ("b", "string")]),
                       "(`a` LIKE '%東京%') OR (`b` LIKE '%東京%')")
    }

    // MARK: - Helpers

    /// The WHERE expression the real `SPRuleFilterController` builds for a serialized filter,
    /// via KVC/selectors because the test target has no bridging header for the Objective-C class.
    private func whereClause(for filter: [String: Any], columns: [(name: String, typegrouping: String)]) throws -> String? {
        let controllerClass = try XCTUnwrap(NSClassFromString("SPRuleFilterController") as? NSObject.Type)
        let controller = controllerClass.init()
        let ruleEditor = NSRuleEditor(frame: NSRect(x: 0, y: 0, width: 600, height: 120))
        ruleEditor.delegate = controller as? NSRuleEditorDelegate
        controller.setValue(ruleEditor, forKey: "filterRuleEditor")
        controller.perform(NSSelectorFromString("setColumns:"), with: columns.map { ["name": $0.name, "typegrouping": $0.typegrouping] })
        controller.perform(NSSelectorFromString("restoreSerializedFilters:"), with: filter)

        var error: NSError?
        let sql = unsafeBitCast(controller, to: SASearchAllTablesRuleFilterSQLGenerating.self).sqlWhereExpression(withBinary: false, error: &error)
        XCTAssertNil(error)
        return sql
    }

    /// Decodes the single-quoted literal after LIKE the way MySQL reads a string
    /// literal: `\\` becomes `\`, while `\%` and `\_` keep their backslash.
    private func likePattern(inSQL sql: String) -> String? {
        guard let start = sql.range(of: "LIKE '")?.upperBound, sql.hasSuffix("'") else { return nil }
        let literal = sql[start..<sql.index(before: sql.endIndex)]
        var pattern = ""
        var iterator = literal.makeIterator()
        while let character = iterator.next() {
            guard character == "\\", let next = iterator.next() else {
                pattern.append(character)
                continue
            }
            if next != "%" && next != "_" { pattern.append(next); continue }
            pattern.append("\\")
            pattern.append(next)
        }
        return pattern
    }
}
