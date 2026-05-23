//
//  SACellFilterMenuBuilderTests.swift
//  Unit Tests
//
//  Created by Sequel-Ace contributors on 2026.05.23.
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import XCTest

final class SACellFilterMenuBuilderTests: XCTestCase {

    func testUnknownTypeGroupingReturnsNoMenu() {
        let menu = SACellFilterMenuBuilder.filterMenu(
            column: ["name": "payload", "typegrouping": "unknown_type_group"],
            value: "abc",
            isNull: false
        )

        XCTAssertNil(menu)
    }

    func testNullValueOnlyShowsNullOperators() throws {
        let menu = try XCTUnwrap(SACellFilterMenuBuilder.filterMenu(
            column: ["name": "payload", "typegrouping": "string"],
            value: "NULL",
            isNull: true
        ))

        XCTAssertEqual(menu.items.map(\.title), ["IS NULL", "IS NOT NULL"])
    }

    func testStringValueMenuUsesAdvertisedOperators() throws {
        let menu = try XCTUnwrap(SACellFilterMenuBuilder.filterMenu(
            column: ["name": "payload", "typegrouping": "string"],
            value: "abc",
            isNull: false
        ))

        XCTAssertEqual(menu.items.map(\.title), ["=", "≠", "LIKE", "NOT LIKE", "contains", "does not contain"])
    }

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

    func testEmptyStringValueOnNumberColumnOnlyShowsNullOperators() throws {
        // Same reasoning as the string case — applies across all type groupings.
        let menu = try XCTUnwrap(SACellFilterMenuBuilder.filterMenu(
            column: ["name": "qty", "typegrouping": "integer"],
            value: "",
            isNull: false
        ))

        XCTAssertEqual(menu.items.map(\.title), ["IS NULL", "IS NOT NULL"])
    }

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

    func testBinaryNullValueOnlyShowsNullOperators() throws {
        let menu = try XCTUnwrap(SACellFilterMenuBuilder.filterMenu(
            column: ["name": "payload", "typegrouping": "binary"],
            value: "NULL",
            isNull: true
        ))

        XCTAssertEqual(menu.items.map(\.title), ["IS NULL", "IS NOT NULL"])
    }

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
}
