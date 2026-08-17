//
//  SACellFilterMenuBuilderTests.swift
//  Unit Tests
//
//  Created by Sequel-Ace contributors on 2026.05.23.
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import XCTest

final class SACellFilterMenuBuilderTests: XCTestCase {

    /// Verifies unknown type groupings do not produce a cell-filter menu.
    func testUnknownTypeGroupingReturnsNoMenu() {
        let menu = SACellFilterMenuBuilder.filterMenu(
            column: ["name": "payload", "typegrouping": "unknown_type_group"],
            value: "abc",
            isNull: false
        )

        XCTAssertNil(menu)
    }

    /// Verifies NULL cell values only expose NULL and NOT NULL menu items.
    func testNullValueOnlyShowsNullOperators() throws {
        let menu = try XCTUnwrap(SACellFilterMenuBuilder.filterMenu(
            column: ["name": "payload", "typegrouping": "string"],
            value: "NULL",
            isNull: true
        ))

        XCTAssertEqual(menu.items.map(\.title), ["IS NULL", "IS NOT NULL"])
    }

    /// Verifies non-empty string cells expose the advertised string operators plus NULL operators.
    func testStringValueMenuUsesAdvertisedOperators() throws {
        let menu = try XCTUnwrap(SACellFilterMenuBuilder.filterMenu(
            column: ["name": "payload", "typegrouping": "string"],
            value: "abc",
            isNull: false
        ))

        // Non-NULL cells keep IS NULL / IS NOT NULL alongside value operators so
        // the user can pivot to "find other rows where this column is empty" from
        // the same context menu without re-opening the rule editor.
        XCTAssertEqual(menu.items.map(\.title), ["=", "≠", "LIKE", "NOT LIKE", "contains", "does not contain", "IS NULL", "IS NOT NULL"])
    }

    /// Verifies empty string cells are limited to NULL operators to avoid placeholder filters.
    func testEmptyStringValueOnlyShowsNullOperators() throws {
        // An empty-string cell value cannot be persisted as a value-bearing rule because
        // SPRuleFilterController's starter detection treats filterValues=[""] as a
        // disposable placeholder. Cell-filter therefore restricts the menu to NULL
        // operators for empty strings, matching the NULL-cell handling.
        let menu = try XCTUnwrap(SACellFilterMenuBuilder.filterMenu(
            column: ["name": "payload", "typegrouping": "string"],
            value: "",
            isNull: false
        ))

        XCTAssertEqual(menu.items.map(\.title), ["IS NULL", "IS NOT NULL"])
    }

    /// Verifies empty numeric cells are also limited to NULL operators.
    func testEmptyStringValueOnNumberColumnOnlyShowsNullOperators() throws {
        // Same reasoning as the string case — applies across all type groupings.
        let menu = try XCTUnwrap(SACellFilterMenuBuilder.filterMenu(
            column: ["name": "qty", "typegrouping": "integer"],
            value: "",
            isNull: false
        ))

        XCTAssertEqual(menu.items.map(\.title), ["IS NULL", "IS NOT NULL"])
    }

    /// Verifies non-NULL binary and blob values still expose NULL operators (the
    /// only operators their catalog advertises) instead of returning no menu at all.
    func testBinaryAndBlobNonNullValuesShowNullOperators() throws {
        // The catalog for binary / blobdata / geometry is NULL-only on purpose
        // (hex/empty value handling for `=` is unsafe). Before this fix, the
        // menu was empty for non-NULL cells of these types, hiding the still-
        // valid IS NULL / IS NOT NULL filter. Now they remain available so the
        // feature is usable on these columns.
        let binaryMenu = try XCTUnwrap(SACellFilterMenuBuilder.filterMenu(
            column: ["name": "payload", "typegrouping": "binary"],
            value: "0xdeadbeef",
            isNull: false
        ))
        XCTAssertEqual(binaryMenu.items.map(\.title), ["IS NULL", "IS NOT NULL"])

        let blobMenu = try XCTUnwrap(SACellFilterMenuBuilder.filterMenu(
            column: ["name": "payload", "typegrouping": "blobdata"],
            value: "0xdeadbeef",
            isNull: false
        ))
        XCTAssertEqual(blobMenu.items.map(\.title), ["IS NULL", "IS NOT NULL"])
    }

    /// Verifies non-NULL geometry cells also expose IS NULL / IS NOT NULL.
    func testGeometryNonNullValueShowsNullOperators() throws {
        let menu = try XCTUnwrap(SACellFilterMenuBuilder.filterMenu(
            column: ["name": "shape", "typegrouping": "geometry"],
            value: "POINT(1 1)",
            isNull: false
        ))
        XCTAssertEqual(menu.items.map(\.title), ["IS NULL", "IS NOT NULL"])
    }

    /// Verifies NULL binary values still expose NULL-safe menu items.
    func testBinaryNullValueOnlyShowsNullOperators() throws {
        let menu = try XCTUnwrap(SACellFilterMenuBuilder.filterMenu(
            column: ["name": "payload", "typegrouping": "binary"],
            value: "NULL",
            isNull: true
        ))

        XCTAssertEqual(menu.items.map(\.title), ["IS NULL", "IS NOT NULL"])
    }

    /// Verifies non-NULL descriptors carry the selected column, operator, and value.
    func testDescriptorsCarryFilterPayload() throws {
        let descriptors = SACellFilterMenuBuilder.menuItemDescriptors(
            columnName: "payload",
            typeGrouping: "string",
            value: "abc",
            isNull: false
        )

        let first = try XCTUnwrap(descriptors.first)
        XCTAssertEqual(first.title, "=")
        XCTAssertEqual(first.columnName, "payload")
        XCTAssertEqual(first.operatorName, "=")
        XCTAssertEqual(first.values, ["abc"])
        XCTAssertFalse(first.isNull)
    }

    /// Verifies NULL descriptors do not carry the selected display value.
    func testNullDescriptorsDoNotCarrySelectedValue() throws {
        let descriptors = SACellFilterMenuBuilder.menuItemDescriptors(
            columnName: "payload",
            typeGrouping: "string",
            value: "NULL",
            isNull: true
        )

        XCTAssertEqual(descriptors.map(\.values), [[], []])
        XCTAssertEqual(descriptors.map(\.isNull), [true, true])
    }

    /// Verifies empty string descriptors serialize as zero-argument NULL payloads.
    func testEmptyStringDescriptorsAreMarkedAsNullPayload() throws {
        // Empty-string cells must produce zero-argument NULL descriptors so the
        // downstream applyCellFilter path serializes filterValues:[] (not [""]).
        let descriptors = SACellFilterMenuBuilder.menuItemDescriptors(
            columnName: "payload",
            typeGrouping: "string",
            value: "",
            isNull: false
        )

        XCTAssertEqual(descriptors.map(\.title), ["IS NULL", "IS NOT NULL"])
        XCTAssertEqual(descriptors.map(\.values), [[], []])
        XCTAssertEqual(descriptors.map(\.isNull), [true, true])
    }

    /// Verifies nil non-NULL values route to NULL descriptors instead of empty value rules.
    func testNilNonNullValueProducesNullDescriptorsNotEmptyValueRules() throws {
        // SPCopyTable.displayStringForRow may return nil for stale / out-of-range
        // cells (see SPCopyTable.h:112-115). The menu builder must NOT fall through
        // to value operators with `[""]`; it must route to NULL operators with
        // filterValues:[] like the empty-string case.
        let descriptors = SACellFilterMenuBuilder.menuItemDescriptors(
            columnName: "payload",
            typeGrouping: "string",
            value: nil,
            isNull: false
        )

        XCTAssertEqual(descriptors.map(\.title), ["IS NULL", "IS NOT NULL"])
        XCTAssertEqual(descriptors.map(\.values), [[], []])
        XCTAssertEqual(descriptors.map(\.isNull), [true, true])
    }
}

final class SACellValueCopyMenuBuilderTests: XCTestCase {

    func testSingleValueBuildsRawAndSQLColumnValueItems() {
        let items = SACellValueCopyMenuBuilder.menuItemDescriptors(
            columnName: "name",
            rawValues: ["Ada"],
            sqlLiterals: ["'Ada'"]
        )

        XCTAssertEqual(items.map(\.title), ["Copy 'name' Value", "Copy 'name' Value as SQL"])
        XCTAssertEqual(items.map(\.text), ["Ada", "'Ada'"])
        XCTAssertEqual(items.map(\.isSQL), [false, true])
        XCTAssertTrue(items.allSatisfy(\.isEnabled))
    }

    func testMultipleValuesPreserveOrderDuplicatesAndNull() {
        let items = SACellValueCopyMenuBuilder.menuItemDescriptors(
            columnName: "serial",
            rawValues: ["A", "A", "NULL", "B"],
            sqlLiterals: ["'A'", "'A'", "NULL", "'B'"]
        )

        XCTAssertEqual(items.map(\.title), ["Copy 'serial' Values", "Copy 'serial' Values as SQL"])
        XCTAssertEqual(items[0].text, "A\nA\nNULL\nB")
        XCTAssertEqual(items[1].text, "'A', 'A', NULL, 'B'")
    }

    func testUnavailableSQLLiteralDisablesOnlySQLCopy() {
        let items = SACellValueCopyMenuBuilder.menuItemDescriptors(
            columnName: "payload",
            rawValues: ["(not loaded)"],
            sqlLiterals: nil
        )

        XCTAssertTrue(items[0].isEnabled)
        XCTAssertFalse(items[1].isEnabled)
        XCTAssertEqual(items[1].text, "")
        XCTAssertFalse(SACellValueCopyAction(descriptor: items[1]).validateMenuItem(NSMenuItem()))
    }

    func testEmptySelectionBuildsNoItems() {
        XCTAssertTrue(
            SACellValueCopyMenuBuilder.menuItemDescriptors(columnName: "serial", rawValues: [], sqlLiterals: []).isEmpty
        )
    }

    func testClickOutsideSelectionReplacesItAndClickInsidePreservesIt() {
        let selected = IndexSet([1, 2, 3])

        XCTAssertEqual(SACellValueCopyMenuBuilder.selectedRows(current: selected, clickedRow: 2), selected)
        XCTAssertEqual(
            SACellValueCopyMenuBuilder.selectedRows(current: selected, clickedRow: 4),
            IndexSet(integer: 4)
        )
    }

    func testSQLLiteralFormatsNullNumericStringAndBinaryValues() {
        let quoteString: (String) -> String? = { "quoted<\($0)>" }
        let quoteData: (Data) -> String? = { "binary<\($0.map { String(format: "%02x", $0) }.joined())>" }

        XCTAssertEqual(SACellValueCopyMenuBuilder.sqlLiteral(
            value: NSNull(), typeGrouping: "string", fieldType: "VARCHAR",
            quoteString: quoteString, quoteData: quoteData
        ), "NULL")
        XCTAssertEqual(SACellValueCopyMenuBuilder.sqlLiteral(
            value: 42, typeGrouping: "integer", fieldType: "INT",
            quoteString: quoteString, quoteData: quoteData
        ), "42")
        XCTAssertEqual(SACellValueCopyMenuBuilder.sqlLiteral(
            value: "O'Brien", typeGrouping: "string", fieldType: "VARCHAR",
            quoteString: quoteString, quoteData: quoteData
        ), "quoted<O'Brien>")
        XCTAssertEqual(SACellValueCopyMenuBuilder.sqlLiteral(
            value: Data([0xde, 0xad]), typeGrouping: "blobdata", fieldType: "BLOB",
            quoteString: quoteString, quoteData: quoteData
        ), "binary<dead>")
    }

    func testSQLLiteralDecodesTextDataAsUTF8() {
        XCTAssertEqual(SACellValueCopyMenuBuilder.sqlLiteral(
            value: Data("é".utf8), typeGrouping: "textdata", fieldType: "TEXT",
            quoteString: { "'\($0)'" }, quoteData: { _ in nil }
        ), "'é'")
        XCTAssertNil(SACellValueCopyMenuBuilder.sqlLiteral(
            value: Data([0xff]), typeGrouping: "textdata", fieldType: "TEXT",
            quoteString: { "'\($0)'" }, quoteData: { _ in nil }
        ))
    }
}
