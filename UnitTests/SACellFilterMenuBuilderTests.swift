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

    /// Verifies non-empty string cells expose the advertised string operators.
    func testStringValueMenuUsesAdvertisedOperators() throws {
        let menu = try XCTUnwrap(SACellFilterMenuBuilder.filterMenu(
            column: ["name": "payload", "typegrouping": "string"],
            value: "abc",
            isNull: false
        ))

        XCTAssertEqual(menu.items.map(\.title), ["=", "≠", "LIKE", "NOT LIKE", "contains", "does not contain"])
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

    /// Verifies non-NULL binary and blob values do not produce unsupported value menus.
    func testBinaryAndBlobNonNullValuesReturnNoMenu() {
        XCTAssertNil(SACellFilterMenuBuilder.filterMenu(
            column: ["name": "payload", "typegrouping": "binary"],
            value: "0xdeadbeef",
            isNull: false
        ))
        XCTAssertNil(SACellFilterMenuBuilder.filterMenu(
            column: ["name": "payload", "typegrouping": "blobdata"],
            value: "0xdeadbeef",
            isNull: false
        ))
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
