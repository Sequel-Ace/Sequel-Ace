//
//  SACellFilterOperatorRoundTripTests.swift
//  Unit Tests
//
//  Created by Sequel-Ace contributors on 2026.05.23.
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import XCTest

final class SACellFilterOperatorRoundTripTests: XCTestCase {

    func testAllAdvertisedOperatorsRoundTripAgainstContentFiltersPlist() throws {
        let contentFilters = try loadContentFilters()

        for pair in SACellFilterOperator.allAdvertisedPairs() {
            let filterType = filterType(for: pair.typeGrouping)
            let definitions = try XCTUnwrap(contentFilters[filterType] as? [[String: Any]], "Missing filter definitions for \(filterType)")
            let definition = definitions.first { $0["MenuLabel"] as? String == pair.op.serializedName }

            XCTAssertNotNil(definition, "\(pair.op.serializedName) missing from ContentFilters.plist for typegrouping \(pair.typeGrouping)")
            XCTAssertEqual(definition?["MenuLabel"] as? String, pair.op.serializedName)
            XCTAssertEqual(definition?["NumberOfArguments"] as? Int, pair.op.valueCount)

            let leaf = serializedFilter(column: "\(pair.typeGrouping)_column", operatorName: pair.op.serializedName, values: values(for: pair.op))
            let restored = serializeRestoredFilter(leaf, filterDefinition: definition)

            XCTAssertEqual(restored["filterComparison"] as? String, pair.op.serializedName, "\(pair.op.serializedName) failed to round-trip for typegrouping \(pair.typeGrouping)")
        }
    }

    private func loadContentFilters() throws -> [String: Any] {
        let candidateBundles = [Bundle.main, Bundle(for: Self.self)] + Bundle.allBundles + Bundle.allFrameworks
        for bundle in candidateBundles {
            guard let path = bundle.path(forResource: "ContentFilters", ofType: "plist"),
                  let filters = NSDictionary(contentsOfFile: path) as? [String: Any] else {
                continue
            }
            return filters
        }

        XCTFail("Could not find ContentFilters.plist in any loaded bundle")
        return [:]
    }

    private func filterType(for typeGrouping: String) -> String {
        switch typeGrouping {
        case "bit", "integer", "float":
            return "number"
        case "geometry":
            return "spatial"
        case "string", "binary", "textdata", "blobdata", "enum":
            return "string"
        default:
            return typeGrouping
        }
    }

    private func values(for op: SACellFilterOperator) -> [String] {
        return Array(repeating: "sample", count: op.valueCount)
    }

    private func serializedFilter(column: String, operatorName: String, values: [String]) -> [String: Any] {
        return [
            "filterClass": "expressionNode",
            "column": column,
            "filterComparison": operatorName,
            "filterValues": values,
            "enabled": true,
        ]
    }

    private func serializeRestoredFilter(_ filter: [String: Any], filterDefinition: [String: Any]?) -> [String: Any] {
        var restored = filter
        restored["filterType"] = filterDefinition?["filterType"]
        return restored
    }
}
