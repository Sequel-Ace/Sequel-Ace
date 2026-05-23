//
//  SACellFilterMergeTests.swift
//  Unit Tests
//
//  Created by Sequel-Ace contributors on 2026.05.23.
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import XCTest

final class SACellFilterMergeTests: XCTestCase {

    func testNilCurrentFilterUsesNewFilter() {
        let newFilter = filter(column: "name", comparison: "=", values: ["Alice"])

        XCTAssertEqual(filterDictionary(SACellFilterMerge.mergedFilter(currentFilter: nil, newFilter: newFilter)), filterDictionary(newFilter))
    }

    func testEmptyAndGroupUsesNewFilter() {
        let emptyGroup: [String: Any] = [
            "filterClass": "groupNode",
            "isConjunction": true,
            "children": [],
        ]
        let newFilter = filter(column: "name", comparison: "=", values: ["Alice"])

        XCTAssertEqual(filterDictionary(SACellFilterMerge.mergedFilter(currentFilter: emptyGroup, newFilter: newFilter)), filterDictionary(newFilter))
    }

    func testUntouchedStarterExpressionUsesNewFilter() {
        let starter = filter(column: "id", comparison: "=", values: [""])
        let newFilter = filter(column: "name", comparison: "=", values: ["Alice"])

        XCTAssertEqual(filterDictionary(SACellFilterMerge.mergedFilter(currentFilter: starter, newFilter: newFilter)), filterDictionary(newFilter))
    }

    func testRealExpressionWrapsInAndGroup() {
        let existing = filter(column: "id", comparison: "=", values: ["42"])
        let newFilter = filter(column: "name", comparison: "=", values: ["Alice"])

        let merged = SACellFilterMerge.mergedFilter(currentFilter: existing, newFilter: newFilter)

        XCTAssertEqual(merged["filterClass"] as? String, "groupNode")
        XCTAssertEqual(merged["isConjunction"] as? Bool, true)
        XCTAssertEqual(filterChildren(from: merged), [filterDictionary(existing), filterDictionary(newFilter)])
    }

    func testExistingAndGroupAppendsNewFilter() {
        let first = filter(column: "id", comparison: "=", values: ["42"])
        let second = filter(column: "state", comparison: "=", values: ["active"])
        let newFilter = filter(column: "name", comparison: "=", values: ["Alice"])
        let existing: [String: Any] = [
            "filterClass": "groupNode",
            "isConjunction": true,
            "children": [first, second],
        ]

        let merged = SACellFilterMerge.mergedFilter(currentFilter: existing, newFilter: newFilter)

        XCTAssertEqual(merged["filterClass"] as? String, "groupNode")
        XCTAssertEqual(merged["isConjunction"] as? Bool, true)
        XCTAssertEqual(filterChildren(from: merged), [filterDictionary(first), filterDictionary(second), filterDictionary(newFilter)])
    }

    func testExistingOrGroupIsWrappedAsOneAndChild() {
        let first = filter(column: "id", comparison: "=", values: ["42"])
        let second = filter(column: "state", comparison: "=", values: ["active"])
        let newFilter = filter(column: "name", comparison: "=", values: ["Alice"])
        let existing: [String: Any] = [
            "filterClass": "groupNode",
            "isConjunction": false,
            "children": [first, second],
        ]

        let merged = SACellFilterMerge.mergedFilter(currentFilter: existing, newFilter: newFilter)

        XCTAssertEqual(merged["filterClass"] as? String, "groupNode")
        XCTAssertEqual(merged["isConjunction"] as? Bool, true)
        XCTAssertEqual(filterChildren(from: merged), [filterDictionary(existing), filterDictionary(newFilter)])
    }

    private func filter(column: String, comparison: String, values: [String]) -> [String: AnyHashable] {
        return [
            "filterClass": "expressionNode",
            "column": column,
            "filterComparison": comparison,
            "filterValues": values,
            "enabled": true,
        ]
    }

    private func filterDictionary(_ filter: [String: Any]) -> NSDictionary {
        return filter as NSDictionary
    }

    private func filterChildren(from filter: [String: Any]) -> [NSDictionary]? {
        return (filter["children"] as? [[String: Any]])?.map { $0 as NSDictionary }
    }
}
