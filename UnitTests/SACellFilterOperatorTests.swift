//
//  SACellFilterOperatorTests.swift
//  Unit Tests
//
//  Created by Sequel-Ace contributors on 2026.05.23.
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import XCTest

final class SACellFilterOperatorTests: XCTestCase {

    /// Verifies missing, empty, and unknown type groupings return no filter operators.
    func testUnknownAndMissingTypeGroupingReturnNoOperators() {
        XCTAssertTrue(SACellFilterOperator.operators(for: nil).isEmpty)
        XCTAssertTrue(SACellFilterOperator.operators(for: "unknown_type_group").isEmpty)
        XCTAssertTrue(SACellFilterOperator.operators(for: "").isEmpty)
    }

    /// Verifies numeric type groupings expose the exact serialized operator names.
    func testNumberFamilyOperatorsUseExactSerializedNames() {
        let expected = ["=", "≠", ">", "<", "≥", "≤", "IS NULL", "IS NOT NULL"]

        XCTAssertEqual(serializedNames(for: "bit"), expected)
        XCTAssertEqual(serializedNames(for: "integer"), expected)
        XCTAssertEqual(serializedNames(for: "float"), expected)
    }

    /// Verifies date type groupings expose the exact date comparison labels.
    func testDateOperatorsUseExactSerializedNames() {
        XCTAssertEqual(
            serializedNames(for: "date"),
            ["=", "≠", "is after", "is before", "is after or equal to", "is before or equal to", "IS NULL", "IS NOT NULL"]
        )
    }

    /// Verifies string-like type groupings expose equality, pattern, contains, and NULL operators.
    func testStringFamilyOperatorsUseExactSerializedNames() {
        let expected = ["=", "≠", "LIKE", "NOT LIKE", "contains", "does not contain", "IS NULL", "IS NOT NULL"]

        XCTAssertEqual(serializedNames(for: "string"), expected)
        XCTAssertEqual(serializedNames(for: "textdata"), expected)
        XCTAssertEqual(serializedNames(for: "enum"), expected)
    }

    /// Verifies binary and blob columns only advertise NULL-safe operators.
    func testBinaryAndBlobOnlyAdvertiseNullOperators() {
        XCTAssertEqual(serializedNames(for: "binary"), ["IS NULL", "IS NOT NULL"])
        XCTAssertEqual(serializedNames(for: "blobdata"), ["IS NULL", "IS NOT NULL"])
    }

    /// Verifies geometry columns only advertise NULL-safe operators.
    func testGeometryOnlyAdvertisesNullOperators() {
        XCTAssertEqual(serializedNames(for: "geometry"), ["IS NULL", "IS NOT NULL"])
    }

    /// Verifies NULL cells suppress value-bearing operators for any type grouping.
    func testNullCellOnlyShowsNullOperators() {
        XCTAssertEqual(SACellFilterOperator.operators(for: "string", cellIsNull: true).map(\.serializedName), ["IS NULL", "IS NOT NULL"])
        XCTAssertEqual(SACellFilterOperator.operators(for: "integer", cellIsNull: true).map(\.serializedName), ["IS NULL", "IS NOT NULL"])
    }

    /// Verifies non-NULL cells hide NULL-only operators while keeping value comparisons.
    func testNonNullCellHidesNullOnlyOperators() {
        XCTAssertEqual(SACellFilterOperator.operators(for: "geometry", cellIsNull: false).map(\.serializedName), [])
        XCTAssertEqual(SACellFilterOperator.operators(for: "binary", cellIsNull: false).map(\.serializedName), [])
        XCTAssertEqual(SACellFilterOperator.operators(for: "blobdata", cellIsNull: false).map(\.serializedName), [])
        XCTAssertEqual(SACellFilterOperator.operators(for: "date", cellIsNull: false).map(\.serializedName), [
            "=",
            "≠",
            "is after",
            "is before",
            "is after or equal to",
            "is before or equal to",
        ])
    }

    /// Verifies advertised operator pairs cover only concrete catalog entries.
    func testAdvertisedPairsCoverEveryCatalogEntry() {
        let pairs = SACellFilterOperator.allAdvertisedPairs()
        XCTAssertEqual(pairs.count, 62)
        XCTAssertFalse(pairs.contains { $0.typeGrouping.isEmpty })
        XCTAssertFalse(pairs.contains { $0.typeGrouping == "unknown_type_group" })
    }

    private func serializedNames(for typeGrouping: String) -> [String] {
        return SACellFilterOperator.operators(for: typeGrouping).map(\.serializedName)
    }
}
