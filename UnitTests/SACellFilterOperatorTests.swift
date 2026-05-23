//
//  SACellFilterOperatorTests.swift
//  Unit Tests
//
//  Created by Sequel-Ace contributors on 2026.05.23.
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import XCTest

final class SACellFilterOperatorTests: XCTestCase {

    func testUnknownAndMissingTypeGroupingReturnNoOperators() {
        XCTAssertTrue(SACellFilterOperator.operators(for: nil).isEmpty)
        XCTAssertTrue(SACellFilterOperator.operators(for: "unknown_type_group").isEmpty)
        XCTAssertTrue(SACellFilterOperator.operators(for: "").isEmpty)
    }

    func testNumberFamilyOperatorsUseExactSerializedNames() {
        let expected = ["=", "≠", ">", "<", "≥", "≤", "IS NULL", "IS NOT NULL"]

        XCTAssertEqual(serializedNames(for: "bit"), expected)
        XCTAssertEqual(serializedNames(for: "integer"), expected)
        XCTAssertEqual(serializedNames(for: "float"), expected)
    }

    func testDateOperatorsUseExactSerializedNames() {
        XCTAssertEqual(
            serializedNames(for: "date"),
            ["=", "≠", "is after", "is before", "is after or equal to", "is before or equal to", "IS NULL", "IS NOT NULL"]
        )
    }

    func testStringFamilyOperatorsUseExactSerializedNames() {
        let expected = ["=", "≠", "LIKE", "NOT LIKE", "contains", "does not contain", "IS NULL", "IS NOT NULL"]

        XCTAssertEqual(serializedNames(for: "string"), expected)
        XCTAssertEqual(serializedNames(for: "textdata"), expected)
        XCTAssertEqual(serializedNames(for: "enum"), expected)
    }

    func testBinaryAndBlobOnlyAdvertiseNullOperators() {
        XCTAssertEqual(serializedNames(for: "binary"), ["IS NULL", "IS NOT NULL"])
        XCTAssertEqual(serializedNames(for: "blobdata"), ["IS NULL", "IS NOT NULL"])
    }

    func testGeometryOnlyAdvertisesNullOperators() {
        XCTAssertEqual(serializedNames(for: "geometry"), ["IS NULL", "IS NOT NULL"])
    }

    func testNullCellOnlyShowsNullOperators() {
        XCTAssertEqual(SACellFilterOperator.operators(for: "string", cellIsNull: true).map(\.serializedName), ["IS NULL", "IS NOT NULL"])
        XCTAssertEqual(SACellFilterOperator.operators(for: "integer", cellIsNull: true).map(\.serializedName), ["IS NULL", "IS NOT NULL"])
    }

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
