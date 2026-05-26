//
//  SACellFilterMergeTests.swift
//  Unit Tests
//
//  Created by Sequel-Ace contributors on 2026.05.23.
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import XCTest

final class SACellFilterMergeTests: XCTestCase {

    /// Verifies a missing current filter is replaced by the new cell filter.
    func testNilCurrentFilterUsesNewFilter() {
        let newFilter = filter(column: "name", comparison: "=", values: ["Alice"])

        XCTAssertEqual(filterDictionary(SACellFilterMerge.mergedFilter(currentFilter: nil, newFilter: newFilter)), filterDictionary(newFilter))
    }

    /// Verifies an empty AND group collapses to the new cell filter.
    func testEmptyAndGroupUsesNewFilter() {
        let emptyGroup: [String: Any] = [
            "filterClass": "groupNode",
            "isConjunction": true,
            "children": [],
        ]
        let newFilter = filter(column: "name", comparison: "=", values: ["Alice"])

        XCTAssertEqual(filterDictionary(SACellFilterMerge.mergedFilter(currentFilter: emptyGroup, newFilter: newFilter)), filterDictionary(newFilter))
    }

    /// Verifies an untouched starter expression is replaced by the new cell filter.
    func testUntouchedStarterExpressionUsesNewFilter() {
        let starter = filter(column: "", comparison: "=", values: [""])
        let newFilter = filter(column: "name", comparison: "=", values: ["Alice"])

        XCTAssertEqual(filterDictionary(SACellFilterMerge.mergedFilter(currentFilter: starter, newFilter: newFilter)), filterDictionary(newFilter))
    }

    /// Verifies existing zero-argument NULL rules are preserved during merges.
    func testExistingZeroArgumentNullRuleIsPreserved() {
        let existing = filter(column: "deleted_at", comparison: "IS NULL", values: [])
        let newFilter = filter(column: "name", comparison: "=", values: ["Alice"])

        let merged = SACellFilterMerge.mergedFilter(currentFilter: existing, newFilter: newFilter)

        XCTAssertEqual(merged["filterClass"] as? String, "groupNode")
        XCTAssertEqual(merged["isConjunction"] as? Bool, true)
        XCTAssertEqual(filterChildren(from: merged), [filterDictionary(existing), filterDictionary(newFilter)])
    }

    /// Verifies a real expression and a new filter are wrapped in an AND group.
    func testRealExpressionWrapsInAndGroup() {
        let existing = filter(column: "id", comparison: "=", values: ["42"])
        let newFilter = filter(column: "name", comparison: "=", values: ["Alice"])

        let merged = SACellFilterMerge.mergedFilter(currentFilter: existing, newFilter: newFilter)

        XCTAssertEqual(merged["filterClass"] as? String, "groupNode")
        XCTAssertEqual(merged["isConjunction"] as? Bool, true)
        XCTAssertEqual(filterChildren(from: merged), [filterDictionary(existing), filterDictionary(newFilter)])
    }

    /// Verifies an existing AND group appends the new cell filter as another child.
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

    /// Verifies an existing OR group is preserved as one child of a new AND group.
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

    /// Verifies a half-touched single expression is treated as a placeholder.
    func testHalfTouchedSingleExpressionIsTreatedAsPlaceholder() {
        // User picked a column in the rule editor but never filled in a value.
        // Serialized as `Host = ""`. Merging a real cell filter must REPLACE
        // (not AND-append) so the result is not the impossible `Host="" AND Host="localhost"`.
        let halfTouched = filter(column: "Host", comparison: "=", values: [""])
        let newFilter = filter(column: "Host", comparison: "=", values: ["localhost"])

        let merged = SACellFilterMerge.mergedFilter(currentFilter: halfTouched, newFilter: newFilter)

        XCTAssertEqual(merged as NSDictionary, newFilter as NSDictionary)
    }

    /// Verifies half-touched placeholder children are stripped before AND merges.
    func testAndGroupStripsHalfTouchedChildrenWhenMerging() {
        let halfTouched = filter(column: "Host", comparison: "=", values: [""])
        let real = filter(column: "id", comparison: "=", values: ["42"])
        let newFilter = filter(column: "Host", comparison: "=", values: ["localhost"])
        let existing: [String: Any] = [
            "filterClass": "groupNode",
            "isConjunction": true,
            "children": [halfTouched, real],
        ]

        let merged = SACellFilterMerge.mergedFilter(currentFilter: existing, newFilter: newFilter)

        XCTAssertEqual(merged["filterClass"] as? String, "groupNode")
        XCTAssertEqual(merged["isConjunction"] as? Bool, true)
        // halfTouched stripped; real kept; newFilter appended → [real, newFilter]
        XCTAssertEqual(filterChildren(from: merged), [filterDictionary(real), filterDictionary(newFilter)])
    }

    /// Verifies an AND group containing only placeholders collapses to the new filter.
    func testAndGroupOfOnlyPlaceholdersCollapsesToNewFilter() {
        // All existing rules are unfilled placeholders → strip them all,
        // leaving only the new cell filter as a single leaf (not a group).
        let placeholder1 = filter(column: "Host", comparison: "=", values: [""])
        let placeholder2 = filter(column: "User", comparison: "=", values: [""])
        let newFilter = filter(column: "Host", comparison: "=", values: ["localhost"])
        let existing: [String: Any] = [
            "filterClass": "groupNode",
            "isConjunction": true,
            "children": [placeholder1, placeholder2],
        ]

        let merged = SACellFilterMerge.mergedFilter(currentFilter: existing, newFilter: newFilter)

        XCTAssertEqual(merged as NSDictionary, newFilter as NSDictionary)
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
