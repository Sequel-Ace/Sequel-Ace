//
//  SACellFilterMergeTests.swift
//  Unit Tests
//
//  Created by Sequel-Ace contributors on 2026.05.23.
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import XCTest

final class SACellFilterMergeTests: XCTestCase {

    /// Verifies a marked OR root (the AND/OR popup shape) is extended under OR instead of being AND-wrapped.
    func testMarkedOrRootIsExtendedKeepingOr() {
        let current: [String: Any] = [
            "filterClass": "groupNode",
            "isConjunction": false,
            "rootGroup": true,
            "children": [filter(column: "a", comparison: "=", values: ["1"]), filter(column: "b", comparison: "=", values: ["2"])],
        ]
        let newFilter = filter(column: "c", comparison: "=", values: ["3"])

        let merged = SACellFilterMerge.mergedFilter(currentFilter: current, newFilter: newFilter)

        XCTAssertEqual(merged["isConjunction"] as? Bool, false, "the popup stays on OR")
        XCTAssertEqual(merged["rootGroup"] as? Bool, true)
        XCTAssertEqual((merged["children"] as? [[String: Any]])?.count, 3)
    }

    /// Verifies a marked AND root is extended in place as well (marker preserved).
    func testMarkedAndRootIsExtendedKeepingMarker() {
        let current: [String: Any] = [
            "filterClass": "groupNode",
            "isConjunction": true,
            "rootGroup": true,
            "children": [filter(column: "a", comparison: "=", values: ["1"]), filter(column: "b", comparison: "=", values: ["2"])],
        ]

        let merged = SACellFilterMerge.mergedFilter(currentFilter: current, newFilter: filter(column: "c", comparison: "=", values: ["3"]))

        XCTAssertEqual(merged["isConjunction"] as? Bool, true)
        XCTAssertEqual(merged["rootGroup"] as? Bool, true)
        XCTAssertEqual((merged["children"] as? [[String: Any]])?.count, 3)
    }

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
        let starter = seededFilter(column: "name")
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

    /// A controller row that was enabled by choosing its column is a real
    /// empty-string predicate, not a placeholder inferred from its argument.
    func testCheckedEmptyExpressionSurvivesCellMerge() {
        let existing = filter(column: "Host", comparison: "=", values: [""])
        let newFilter = filter(column: "Host", comparison: "=", values: ["localhost"])

        let merged = SACellFilterMerge.mergedFilter(currentFilter: existing, newFilter: newFilter)

        XCTAssertEqual(filterChildren(from: merged), [filterDictionary(existing), filterDictionary(newFilter)])
    }

    func testOnlyExplicitPendingStartersAreRecognized() {
        let seeded = seededFilter(column: "Host")
        XCTAssertTrue(SACellFilterMerge.isUntouchedStarter(filter: seeded))
        XCTAssertFalse(SACellFilterMerge.isUntouchedStarter(filter: filter(column: "Host", comparison: "=", values: [""])))
        var disabled = filter(column: "Host", comparison: "=", values: [""])
        disabled["enabled"] = false
        XCTAssertFalse(SACellFilterMerge.isUntouchedStarter(filter: disabled))
        var checkedMarker = seeded
        checkedMarker["enabled"] = true
        XCTAssertFalse(SACellFilterMerge.isUntouchedStarter(filter: checkedMarker))
        var zeroArguments = seeded
        zeroArguments["filterComparison"] = "IS NULL"
        zeroArguments["filterValues"] = [String]()
        XCTAssertFalse(SACellFilterMerge.isUntouchedStarter(filter: zeroArguments))
        var editedStarter = seeded
        editedStarter["filterValues"] = ["value"]
        XCTAssertFalse(SACellFilterMerge.isUntouchedStarter(filter: editedStarter))
    }

    /// Covers marked AND/OR roots and legacy roots using the shapes produced
    /// by serializedFilter: enabled predicates, disabled user rows, and the
    /// enabled:false/pendingStarter:true seed. Only the seed is removed.
    func testCellMergePreservesEmptyPredicatesInCurrentAndLegacyRoots() {
        let checked = filter(column: "name", comparison: "=", values: [""])
        var disabled = filter(column: "archived_name", comparison: "=", values: [""])
        disabled["enabled"] = false
        let nullRule = filter(column: "deleted_at", comparison: "IS NULL", values: [])
        let real = [checked, disabled, nullRule]
        let newFilter = filter(column: "id", comparison: "=", values: ["42"])
        for isConjunction in [true, false] {
            for marked in [true, false] {
                var existing: [String: Any] = [
                    "filterClass": "groupNode",
                    "isConjunction": isConjunction,
                    "children": marked || isConjunction ? [seededFilter(column: "first")] + real : real,
                ]
                if marked { existing["rootGroup"] = true }
                let merged = SACellFilterMerge.mergedFilter(currentFilter: existing, newFilter: newFilter)
                if marked || isConjunction {
                    XCTAssertEqual(filterChildren(from: merged), (real + [newFilter]).map(filterDictionary))
                    XCTAssertEqual(merged["isConjunction"] as? Bool, isConjunction)
                } else {
                    XCTAssertEqual(filterChildren(from: merged), [filterDictionary(existing), filterDictionary(newFilter)])
                }
            }
        }
    }

    /// Older serialized rows without enabled/pendingStarter must keep their
    /// empty comparisons through a merge, including a deliberately disabled row.
    func testUnmarkedEmptyExpressionsSurviveCellMerge() {
        let newFilter = filter(column: "id", comparison: "=", values: ["42"])
        for enabled in [true, false] {
            var existing = filter(column: "name", comparison: "=", values: [""])
            existing["enabled"] = enabled
            let merged = SACellFilterMerge.mergedFilter(currentFilter: existing, newFilter: newFilter)
            XCTAssertEqual(filterChildren(from: merged), [filterDictionary(existing), filterDictionary(newFilter)])
        }
        var legacy = filter(column: "name", comparison: "=", values: [""])
        legacy.removeValue(forKey: "enabled")
        let merged = SACellFilterMerge.mergedFilter(currentFilter: legacy, newFilter: newFilter)
        XCTAssertEqual(filterChildren(from: merged), [filterDictionary(legacy), filterDictionary(newFilter)])
    }

    /// A legacy AND wrapper containing only the explicit unchecked seed can
    /// collapse to the requested cell filter; user empty predicates cannot.
    func testLegacyAndGroupOfExplicitSeedCollapsesToNewFilter() {
        let existing: [String: Any] = [
            "filterClass": "groupNode",
            "isConjunction": true,
            "children": [seededFilter(column: "name")],
        ]
        let newFilter = filter(column: "name", comparison: "=", values: ["Alice"])
        XCTAssertEqual(filterDictionary(SACellFilterMerge.mergedFilter(currentFilter: existing, newFilter: newFilter)), filterDictionary(newFilter))
    }

    private func seededFilter(column: String) -> [String: AnyHashable] {
        var seeded = filter(column: column, comparison: "=", values: [""])
        seeded["enabled"] = false
        seeded["pendingStarter"] = true
        return seeded
    }

    private func filter(column: String, comparison: String, values: [String]) -> [String: AnyHashable] {
        return [
            "filterClass": "expressionNode",
            "column": column,
            "filterComparison": comparison,
            "filterType": "string",
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

final class SARuleFilterVisibilityPolicyTests: XCTestCase {

    /// Regression coverage for #2516: refreshing a table rebuilds the filter
    /// model and reapplies `visible`, but that must not create a new rule.
    func testReapplyingVisibleStateDoesNotAddStarterRule() {
        XCTAssertFalse(SARuleFilterVisibilityPolicy.shouldAddStarterRule(
            visibilityWasApplied: true,
            wasVisible: true,
            willBeVisible: true,
            tableChanged: false,
            editorIsEmpty: true
        ))
    }

    func testSwitchingTablesWhileVisibleAddsStarterRule() {
        XCTAssertTrue(SARuleFilterVisibilityPolicy.shouldAddStarterRule(
            visibilityWasApplied: true,
            wasVisible: true,
            willBeVisible: true,
            tableChanged: true,
            editorIsEmpty: true
        ))
    }

    /// The saved preference is desired state, not proof that visibility has
    /// already been applied to a table after launch.
    func testApplyingSavedVisiblePreferenceAddsStarterRule() {
        XCTAssertTrue(SARuleFilterVisibilityPolicy.shouldAddStarterRule(
            visibilityWasApplied: false,
            wasVisible: true,
            willBeVisible: true,
            tableChanged: true,
            editorIsEmpty: true
        ))
    }

    /// Clearing the view invalidates the previous visibility application even
    /// if the same table name is selected again afterward.
    func testReselectingTableAfterBlankStateAddsStarterRule() {
        XCTAssertTrue(SARuleFilterVisibilityPolicy.shouldAddStarterRule(
            visibilityWasApplied: false,
            wasVisible: true,
            willBeVisible: true,
            tableChanged: false,
            editorIsEmpty: true
        ))
    }

    func testOpeningEmptyEditorAddsStarterRule() {
        XCTAssertTrue(SARuleFilterVisibilityPolicy.shouldAddStarterRule(
            visibilityWasApplied: true,
            wasVisible: false,
            willBeVisible: true,
            tableChanged: false,
            editorIsEmpty: true
        ))
    }

    func testOpeningPopulatedEditorDoesNotAddStarterRule() {
        XCTAssertFalse(SARuleFilterVisibilityPolicy.shouldAddStarterRule(
            visibilityWasApplied: true,
            wasVisible: false,
            willBeVisible: true,
            tableChanged: true,
            editorIsEmpty: false
        ))
    }

    func testHidingEditorDoesNotAddStarterRule() {
        XCTAssertFalse(SARuleFilterVisibilityPolicy.shouldAddStarterRule(
            visibilityWasApplied: true,
            wasVisible: true,
            willBeVisible: false,
            tableChanged: true,
            editorIsEmpty: true
        ))
    }
}

final class SARuleFilterDropZoneLayoutPolicyTests: XCTestCase {

    func testVisibleDropZonePreservesExistingPopulatedEditorLayout() {
        let metrics = SARuleFilterDropZoneLayoutPolicy.metrics(
            editorVisible: true,
            editorHasRows: true,
            requestedHeight: 72,
            dropZoneHeight: 40,
            showDropZonePreference: true
        )

        XCTAssertTrue(metrics.dropZoneVisible)
        XCTAssertEqual(metrics.dropZoneReservedHeight, 40)
        XCTAssertEqual(metrics.ruleEditorOriginY, 41)
        XCTAssertEqual(metrics.containerRequestedHeight, 113)
    }

    func testHiddenDropZoneStillReservesTheButtonBar() {
        // Since the rows span the full width, the button bar below them is
        // always reserved - with the drop zone hidden it shrinks to 31 pt.
        let metrics = SARuleFilterDropZoneLayoutPolicy.metrics(
            editorVisible: true,
            editorHasRows: true,
            requestedHeight: 72,
            dropZoneHeight: 40,
            showDropZonePreference: false
        )

        XCTAssertFalse(metrics.dropZoneVisible)
        XCTAssertEqual(metrics.dropZoneReservedHeight, 31)
        XCTAssertEqual(metrics.ruleEditorOriginY, 32)
        XCTAssertEqual(metrics.containerRequestedHeight, 104)
    }

    func testVisibleDropZoneOwnsEmptyEditorHeight() {
        let metrics = SARuleFilterDropZoneLayoutPolicy.metrics(
            editorVisible: true,
            editorHasRows: false,
            requestedHeight: 0,
            dropZoneHeight: 40,
            showDropZonePreference: true
        )

        XCTAssertTrue(metrics.dropZoneVisible)
        XCTAssertEqual(metrics.ruleEditorOriginY, 40)
        XCTAssertEqual(metrics.containerRequestedHeight, 40)
    }

    func testEmptyEditorRetainsButtonBarWhenDropZoneIsHidden() {
        // The Add Filter button lives in the always-reserved button bar, so
        // an empty editor with a hidden drop zone is exactly that bar.
        let metrics = SARuleFilterDropZoneLayoutPolicy.metrics(
            editorVisible: true,
            editorHasRows: false,
            requestedHeight: 0,
            dropZoneHeight: 40,
            showDropZonePreference: false
        )

        XCTAssertFalse(metrics.dropZoneVisible)
        XCTAssertEqual(metrics.ruleEditorOriginY, 31)
        XCTAssertEqual(metrics.containerRequestedHeight, 31)
    }

    func testHiddenEditorCollapsesRegardlessOfDropZonePreference() {
        for showDropZone in [false, true] {
            let metrics = SARuleFilterDropZoneLayoutPolicy.metrics(
                editorVisible: false,
                editorHasRows: true,
                requestedHeight: 72,
                dropZoneHeight: 40,
                showDropZonePreference: showDropZone
            )

            XCTAssertFalse(metrics.dropZoneVisible)
            XCTAssertEqual(metrics.dropZoneReservedHeight, 0)
            XCTAssertEqual(metrics.ruleEditorOriginY, 0)
            XCTAssertEqual(metrics.containerRequestedHeight, 0)
        }
    }

    func testMissingPreferenceDefaultsToVisibleForUpgradingUsers() {
        let suiteName = "SARuleFilterDropZoneLayoutPolicyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let metrics = SARuleFilterDropZoneLayoutPolicy.metrics(
            editorVisible: true,
            editorHasRows: true,
            requestedHeight: 29,
            dropZoneHeight: 40,
            userDefaults: defaults
        )

        XCTAssertEqual(SARuleFilterDropZoneLayoutPolicy.defaultsKey, "RuleFilterShowDropZone")
        XCTAssertTrue(metrics.dropZoneVisible)
    }
}
