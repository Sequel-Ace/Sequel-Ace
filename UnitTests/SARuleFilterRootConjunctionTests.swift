//
//  SARuleFilterRootConjunctionTests.swift
//  Unit Tests
//
//  Created by Sequel-Ace contributors on 2026.08.27.
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import Cocoa
import XCTest

final class SARuleFilterRootConjunctionTests: XCTestCase {

    // MARK: - serializedRoot

    /// Verifies a single top-level expression under AND is serialized as itself (unchanged legacy shape).
    func testSingleExpressionUnderAndIsReturnedAsItself() {
        let rule = expression(column: "name", values: ["Alice"])

        XCTAssertEqual(dictionary(SARuleFilterRootConjunction.serializedRoot(items: [rule], isConjunction: true)), dictionary(rule))
    }

    /// Verifies a single expression with OR selected is wrapped so the popup choice survives a restore.
    func testSingleExpressionUnderOrIsWrappedInRootGroup() {
        let rule = expression(column: "name", values: ["Alice"])

        let root = SARuleFilterRootConjunction.serializedRoot(items: [rule], isConjunction: false)

        XCTAssertEqual(root["isConjunction"] as? Bool, false)
        XCTAssertEqual(root["rootGroup"] as? Bool, true)
        XCTAssertEqual(children(of: root).map(dictionary), [dictionary(rule)])

        let plan = SARuleFilterRootConjunction.restorePlan(for: root)
        XCTAssertFalse(plan.isConjunction, "the OR choice survives the round trip")
        XCTAssertEqual(plan.items.map(dictionary), [dictionary(rule)])
    }

    /// Verifies a single top-level group is wrapped in the root group so the root conjunction is not lost.
    func testSingleNestedGroupIsWrappedInRootGroup() {
        let nested = group(children: [expression(column: "a", values: ["1"]), expression(column: "b", values: ["2"])], isConjunction: false)

        let root = SARuleFilterRootConjunction.serializedRoot(items: [nested], isConjunction: true)

        XCTAssertEqual(root["isConjunction"] as? Bool, true)
        XCTAssertEqual(root["rootGroup"] as? Bool, true)
        XCTAssertEqual(children(of: root).map(dictionary), [dictionary(nested)])
    }

    /// Verifies an AND root holding one OR subgroup survives a round trip and a later append keeps the AND.
    func testRoundTripOfAndRootWithSingleOrSubgroupThenAppend() {
        let nested = group(children: [expression(column: "a", values: ["1"]), expression(column: "b", values: ["2"])], isConjunction: false)
        let c = expression(column: "c", values: ["3"])

        let serialized = SARuleFilterRootConjunction.serializedRoot(items: [nested], isConjunction: true)
        let plan = SARuleFilterRootConjunction.restorePlan(for: serialized)
        XCTAssertTrue(plan.isConjunction)
        XCTAssertEqual(plan.items.map(dictionary), [dictionary(nested)])

        let reserialized = SARuleFilterRootConjunction.serializedRoot(items: plan.items, isConjunction: plan.isConjunction)
        let appended = SARuleFilterRootConjunction.appending(rule: c, to: reserialized, rootIsConjunction: plan.isConjunction)

        XCTAssertEqual(appended["isConjunction"] as? Bool, true, "(a OR b) AND c, not a OR b OR c")
        XCTAssertEqual(children(of: appended).map(dictionary), [dictionary(nested), dictionary(c)])
    }

    /// Verifies several top-level rows are wrapped in a group carrying the root conjunction.
    func testMultipleItemsAreWrappedWithRootConjunction() {
        let a = expression(column: "a", values: ["1"])
        let b = expression(column: "b", values: ["2"])

        let andRoot = SARuleFilterRootConjunction.serializedRoot(items: [a, b], isConjunction: true)
        XCTAssertEqual(andRoot["filterClass"] as? String, "groupNode")
        XCTAssertEqual(andRoot["isConjunction"] as? Bool, true)
        XCTAssertEqual(andRoot["rootGroup"] as? Bool, true, "the root carries the marker that tells it apart from a nested row")
        XCTAssertEqual(children(of: andRoot).map(dictionary), [a, b].map(dictionary))

        let orRoot = SARuleFilterRootConjunction.serializedRoot(items: [a, b], isConjunction: false)
        XCTAssertEqual(orRoot["isConjunction"] as? Bool, false)
        XCTAssertEqual(children(of: orRoot).map(dictionary), [a, b].map(dictionary))
    }

    /// Verifies an empty editor still serializes to an (empty) group, as it always did.
    func testEmptyItemsProduceEmptyGroup() {
        let root = SARuleFilterRootConjunction.serializedRoot(items: [], isConjunction: true)

        XCTAssertEqual(root["filterClass"] as? String, "groupNode")
        XCTAssertEqual(root["isConjunction"] as? Bool, true)
        XCTAssertTrue(children(of: root).isEmpty)
    }

    // MARK: - restorePlan

    /// Verifies a marked root group is unpacked into top-level rows and its conjunction goes to the popup.
    func testRestorePlanUnpacksRootGroupIntoPopupAndRows() {
        let a = expression(column: "a", values: ["1"])
        let b = expression(column: "b", values: ["2"])
        let orRoot = rootGroup(children: [a, b], isConjunction: false)

        let plan = SARuleFilterRootConjunction.restorePlan(for: orRoot)

        XCTAssertFalse(plan.isConjunction)
        XCTAssertEqual(plan.items.map(dictionary), [a, b].map(dictionary))
    }

    /// Verifies a legacy (unmarked) OR group – written before the popup existed – stays one nested row under an AND root.
    func testRestorePlanKeepsLegacyOrGroupAsNestedRow() {
        let a = expression(column: "a", values: ["1"])
        let b = expression(column: "b", values: ["2"])
        let legacyOrGroup = group(children: [a, b], isConjunction: false)

        let plan = SARuleFilterRootConjunction.restorePlan(for: legacyOrGroup)

        XCTAssertTrue(plan.isConjunction, "legacy trees had an implicit AND root")
        XCTAssertEqual(plan.items.map(dictionary), [dictionary(legacyOrGroup)])
    }

    /// Verifies a legacy (unmarked) AND group at the root is unpacked, as the old restore code did.
    func testRestorePlanUnpacksLegacyAndGroup() {
        let a = expression(column: "a", values: ["1"])
        let b = expression(column: "b", values: ["2"])

        let plan = SARuleFilterRootConjunction.restorePlan(for: group(children: [a, b], isConjunction: true))

        XCTAssertTrue(plan.isConjunction)
        XCTAssertEqual(plan.items.map(dictionary), [a, b].map(dictionary))
    }

    /// Verifies a legacy OR group followed by an append still yields (a OR b) AND c.
    func testLegacyOrGroupThenAppendKeepsGroupBoundary() {
        let legacyOrGroup = group(children: [expression(column: "a", values: ["1"]), expression(column: "b", values: ["2"])], isConjunction: false)
        let c = expression(column: "c", values: ["3"])

        let plan = SARuleFilterRootConjunction.restorePlan(for: legacyOrGroup)
        let reserialized = SARuleFilterRootConjunction.serializedRoot(items: plan.items, isConjunction: plan.isConjunction)
        let appended = SARuleFilterRootConjunction.appending(rule: c, to: reserialized, rootIsConjunction: plan.isConjunction)

        XCTAssertEqual(appended["isConjunction"] as? Bool, true)
        XCTAssertEqual(children(of: appended).map(dictionary), [dictionary(legacyOrGroup), dictionary(c)])
    }

    /// Verifies a nested group inside the root group stays a nested group.
    func testRestorePlanKeepsNestedGroups() {
        let a = expression(column: "a", values: ["1"])
        let nested = group(children: [expression(column: "b", values: ["2"]), expression(column: "c", values: ["3"])], isConjunction: false)
        let root = rootGroup(children: [a, nested], isConjunction: true)

        let plan = SARuleFilterRootConjunction.restorePlan(for: root)

        XCTAssertTrue(plan.isConjunction)
        XCTAssertEqual(plan.items.count, 2)
        XCTAssertEqual(plan.items[1]["filterClass"] as? String, "groupNode")
    }

    /// Verifies a bare expression resets the popup to AND – a replacement filter (e.g. foreign-key
    /// navigation) must not inherit a stale OR, and the OR one-row shape is always written wrapped.
    func testRestorePlanResetsToAndForBareExpression() {
        let rule = expression(column: "a", values: ["1"])

        let plan = SARuleFilterRootConjunction.restorePlan(for: rule)

        XCTAssertTrue(plan.isConjunction)
        XCTAssertEqual(plan.items.map(dictionary), [dictionary(rule)])
    }

    // MARK: - extendingMarkedRoot

    /// Verifies only marked root groups are extended, keeping conjunction and marker.
    func testExtendingMarkedRootKeepsConjunction() throws {
        let a = expression(column: "a", values: ["1"])
        let rule = expression(column: "c", values: ["3"])

        XCTAssertNil(SARuleFilterRootConjunction.extendingMarkedRoot(a, withRule: rule))
        XCTAssertNil(SARuleFilterRootConjunction.extendingMarkedRoot(group(children: [a], isConjunction: false), withRule: rule), "legacy groups keep the old merge path")

        let extended = try XCTUnwrap(SARuleFilterRootConjunction.extendingMarkedRoot(rootGroup(children: [a, expression(column: "b", values: ["2"])], isConjunction: false), withRule: rule))
        XCTAssertEqual(extended["isConjunction"] as? Bool, false)
        XCTAssertEqual(extended["rootGroup"] as? Bool, true)
        XCTAssertEqual(children(of: extended).map { $0["column"] as? String }, ["a", "b", "c"])
    }

    /// Verifies seeded starter children are dropped, and a starter-only root collapses to the rule.
    func testExtendingMarkedRootDropsSeededRows() {
        let starter = expression(column: "a", values: [""])
        let rule = expression(column: "c", values: ["3"])

        let replaced = SARuleFilterRootConjunction.extendingMarkedRoot(rootGroup(children: [starter], isConjunction: false), withRule: rule)
        XCTAssertEqual(replaced?["isConjunction"] as? Bool, false, "the OR wrapper survives")
        XCTAssertEqual(replaced.map(children)?.map(dictionary), [dictionary(rule)])
        let mixed = SARuleFilterRootConjunction.extendingMarkedRoot(rootGroup(children: [starter, expression(column: "b", values: ["2"])], isConjunction: false), withRule: rule)
        XCTAssertEqual(mixed.map(children)?.map { $0["column"] as? String }, ["b", "c"])
    }

    // MARK: - appending

    /// Verifies a missing or untouched starter tree is replaced by the new rule.
    func testAppendingReplacesMissingOrStarterTree() {
        let rule = expression(column: "a", values: ["1"])
        let starter = expression(column: "a", values: [""])

        XCTAssertEqual(dictionary(SARuleFilterRootConjunction.appending(rule: rule, to: nil, rootIsConjunction: true)), dictionary(rule))
        XCTAssertEqual(dictionary(SARuleFilterRootConjunction.appending(rule: rule, to: starter, rootIsConjunction: false)), dictionary(rule))
    }

    /// Verifies appending to a single expression combines both under the root conjunction.
    func testAppendingToSingleExpressionUsesRootConjunction() {
        let a = expression(column: "a", values: ["1"])
        let b = expression(column: "b", values: ["2"])

        let combined = SARuleFilterRootConjunction.appending(rule: b, to: a, rootIsConjunction: false)

        XCTAssertEqual(combined["isConjunction"] as? Bool, false)
        XCTAssertEqual(children(of: combined).map(dictionary), [a, b].map(dictionary))
    }

    /// Verifies appending to a root group with the same conjunction just adds a child.
    func testAppendingToMatchingRootGroupAddsChild() {
        let a = expression(column: "a", values: ["1"])
        let b = expression(column: "b", values: ["2"])
        let c = expression(column: "c", values: ["3"])

        let combined = SARuleFilterRootConjunction.appending(rule: c, to: rootGroup(children: [a, b], isConjunction: false), rootIsConjunction: false)

        XCTAssertEqual(combined["isConjunction"] as? Bool, false)
        XCTAssertEqual(combined["rootGroup"] as? Bool, true)
        XCTAssertEqual(children(of: combined).map(dictionary), [a, b, c].map(dictionary))
    }

    /// Verifies an unmarked (nested) group is never extended in place, even when its conjunction matches the root.
    func testAppendingWrapsUnmarkedGroupEvenWithMatchingConjunction() {
        let nestedOr = group(children: [expression(column: "a", values: ["1"]), expression(column: "b", values: ["2"])], isConjunction: false)
        let c = expression(column: "c", values: ["3"])

        let combined = SARuleFilterRootConjunction.appending(rule: c, to: nestedOr, rootIsConjunction: false)

        XCTAssertEqual(combined["rootGroup"] as? Bool, true)
        XCTAssertEqual(children(of: combined).map(dictionary), [dictionary(nestedOr), dictionary(c)])
    }

    /// Verifies a group with the other conjunction is nested under the root instead of being extended.
    func testAppendingWrapsMismatchedGroupUnderRoot() {
        let orGroup = group(children: [expression(column: "a", values: ["1"]), expression(column: "b", values: ["2"])], isConjunction: false)
        let c = expression(column: "c", values: ["3"])

        let combined = SARuleFilterRootConjunction.appending(rule: c, to: orGroup, rootIsConjunction: true)

        XCTAssertEqual(combined["isConjunction"] as? Bool, true)
        let kids = children(of: combined)
        XCTAssertEqual(kids.count, 2)
        XCTAssertEqual(dictionary(kids[0]), dictionary(orGroup))
        XCTAssertEqual(dictionary(kids[1]), dictionary(c))
    }

    /// Verifies an IS NULL rule (no values) is never mistaken for a starter row.
    func testAppendingPreservesZeroArgumentRule() {
        let isNull = expression(column: "deleted_at", comparison: "IS NULL", values: [])
        let b = expression(column: "b", values: ["2"])

        let combined = SARuleFilterRootConjunction.appending(rule: b, to: isNull, rootIsConjunction: true)

        XCTAssertEqual(children(of: combined).map(dictionary), [isNull, b].map(dictionary))
    }

    // MARK: - replacing

    /// Verifies row 0 of a single expression is replaced outright and other rows are rejected.
    func testReplacingSingleExpression() {
        let a = expression(column: "a", values: ["1"])
        let b = expression(column: "b", values: ["2"])

        XCTAssertEqual(SARuleFilterRootConjunction.replacing(rule: b, atRow: 0, in: a, rootIsConjunction: true).map(dictionary), dictionary(b))
        XCTAssertNil(SARuleFilterRootConjunction.replacing(rule: b, atRow: 1, in: a, rootIsConjunction: true))
        XCTAssertNil(SARuleFilterRootConjunction.replacing(rule: b, atRow: -1, in: a, rootIsConjunction: true))
    }

    /// Verifies a flat root group is addressed by row index and keeps its conjunction.
    func testReplacingRowInFlatRootGroup() {
        let a = expression(column: "a", values: ["1"])
        let b = expression(column: "b", values: ["2"])
        let c = expression(column: "c", values: ["3"])

        let combined = SARuleFilterRootConjunction.replacing(rule: c, atRow: 1, in: rootGroup(children: [a, b], isConjunction: false), rootIsConjunction: false)

        XCTAssertEqual(combined?["isConjunction"] as? Bool, false)
        XCTAssertEqual(combined?["rootGroup"] as? Bool, true)
        XCTAssertEqual(combined.map(children).map { $0.map(dictionary) }, [a, c].map(dictionary))
        XCTAssertNil(SARuleFilterRootConjunction.replacing(rule: c, atRow: 2, in: rootGroup(children: [a, b], isConjunction: false), rootIsConjunction: false))
    }

    /// Verifies a lone nested (unmarked) group cannot be replaced by row index.
    func testReplacingRejectsLoneNestedGroup() {
        let nestedOr = group(children: [expression(column: "a", values: ["1"])], isConjunction: false)
        let c = expression(column: "c", values: ["3"])

        XCTAssertNil(SARuleFilterRootConjunction.replacing(rule: c, atRow: 0, in: nestedOr, rootIsConjunction: true))
    }

    /// Verifies an expression beside a nested group can be replaced, while the group itself cannot.
    func testReplacingBesideNestedGroup() {
        let a = expression(column: "a", values: ["1"])
        let nested = group(children: [expression(column: "b", values: ["2"])], isConjunction: false)
        let c = expression(column: "c", values: ["3"])
        let tree = rootGroup(children: [a, nested], isConjunction: true)

        let replaced = SARuleFilterRootConjunction.replacing(rule: c, atRow: 0, in: tree, rootIsConjunction: true)
        XCTAssertEqual(replaced.map(children)?.first.map(dictionary), dictionary(c), "the expression child is replaceable")
        XCTAssertEqual(replaced.map(children)?.last?["filterClass"] as? String, "groupNode", "the nested group stays untouched")

        XCTAssertNil(SARuleFilterRootConjunction.replacing(rule: c, atRow: 1, in: tree, rootIsConjunction: true), "the group itself cannot be replaced by a single rule")
    }

    // MARK: - nestedGroup

    /// Verifies the added group uses the opposite of the root conjunction.
    func testNestedGroupUsesOppositeConjunction() {
        let starter = expression(column: "a", values: [""])

        let underAnd = SARuleFilterRootConjunction.nestedGroup(child: starter, rootIsConjunction: true)
        XCTAssertEqual(underAnd["isConjunction"] as? Bool, false)
        XCTAssertNil(underAnd["rootGroup"], "a nested group must not look like the root")
        XCTAssertEqual(children(of: underAnd).map(dictionary), [dictionary(starter)])

        let underOr = SARuleFilterRootConjunction.nestedGroup(child: starter, rootIsConjunction: false)
        XCTAssertEqual(underOr["isConjunction"] as? Bool, true)
    }

    // MARK: - isUntouchedStarterTree

    /// Verifies only a lone expression with all-empty arguments counts as the seeded starter row.
    func testUntouchedStarterTreeDetection() {
        XCTAssertFalse(SARuleFilterRootConjunction.isUntouchedStarterTree(nil))
        XCTAssertTrue(SARuleFilterRootConjunction.isUntouchedStarterTree(expression(column: "a", values: [""])))
        XCTAssertFalse(SARuleFilterRootConjunction.isUntouchedStarterTree(expression(column: "a", values: ["1"])))
        XCTAssertFalse(SARuleFilterRootConjunction.isUntouchedStarterTree(expression(column: "a", comparison: "IS NULL", values: [])), "zero-argument operators are real rules")
        XCTAssertTrue(SARuleFilterRootConjunction.isUntouchedStarterTree(rootGroup(children: [expression(column: "a", values: [""])], isConjunction: false)), "an OR-wrapped seeded row is still just the starter")
        XCTAssertFalse(SARuleFilterRootConjunction.isUntouchedStarterTree(rootGroup(children: [expression(column: "a", values: [""]), expression(column: "b", values: ["1"])], isConjunction: true)))
        XCTAssertFalse(SARuleFilterRootConjunction.isUntouchedStarterTree(rootGroup(children: [], isConjunction: true)))
    }

    /// Verifies appending strips seeded starter rows and keeps the OR wrapper when replacing the seeded row.
    func testAppendingReplacesStarterInsideOrRoot() {
        let starter = expression(column: "a", values: [""])
        let rule = expression(column: "b", values: ["2"])

        let replaced = SARuleFilterRootConjunction.appending(rule: rule, to: rootGroup(children: [starter], isConjunction: false), rootIsConjunction: false)
        XCTAssertEqual(replaced["isConjunction"] as? Bool, false, "the OR choice survives replacing the seeded row")
        XCTAssertEqual(replaced["rootGroup"] as? Bool, true)
        XCTAssertEqual(children(of: replaced).map(dictionary), [dictionary(rule)])

        // A bare starter (AND shape) is still replaced by the bare rule.
        XCTAssertEqual(dictionary(SARuleFilterRootConjunction.appending(rule: rule, to: starter, rootIsConjunction: true)), dictionary(rule))

        let mixed = SARuleFilterRootConjunction.appending(rule: rule, to: rootGroup(children: [starter, expression(column: "c", values: ["3"])], isConjunction: false), rootIsConjunction: false)
        XCTAssertEqual(children(of: mixed).map { $0["column"] as? String }, ["c", "b"])
    }

    // MARK: - treeAddingGroup

    /// Verifies an empty or seeded-only editor gets the nested group alone (root conjunction unchanged).
    func testAddingGroupReplacesStarterOnlyEditor() {
        let starter = expression(column: "a", values: [""])

        let tree = SARuleFilterRootConjunction.treeAddingGroup(starter: starter, to: expression(column: "a", values: [""]), rootIsConjunction: true)

        XCTAssertEqual(tree["isConjunction"] as? Bool, true)
        let kids = children(of: tree)
        XCTAssertEqual(kids.count, 1)
        XCTAssertEqual(kids.first?["isConjunction"] as? Bool, false)
        XCTAssertEqual(children(of: kids.first ?? [:]).map(dictionary), [dictionary(starter)])
    }

    /// Verifies the reported case: two OR rows + add group folds them and flips the root – "(a OR b) AND new".
    func testAddingGroupFoldsOrRowsUnderAndRoot() {
        let a = expression(column: "PLZ", values: ["77694"])
        let b = expression(column: "PLZ", values: ["40789"])
        let starter = expression(column: "NAME46", values: [""])

        let tree = SARuleFilterRootConjunction.treeAddingGroup(starter: starter, to: rootGroup(children: [a, b], isConjunction: false), rootIsConjunction: false)

        XCTAssertEqual(tree["isConjunction"] as? Bool, true, "root flips to AND")
        XCTAssertEqual(tree["rootGroup"] as? Bool, true)
        let kids = children(of: tree)
        XCTAssertEqual(kids.count, 2)
        XCTAssertEqual(kids.first?["isConjunction"] as? Bool, false, "the OR pair stays one nested group")
        XCTAssertNil(kids.first?["rootGroup"])
        XCTAssertEqual(children(of: kids.first ?? [:]).map(dictionary), [a, b].map(dictionary))
        XCTAssertEqual(dictionary(kids.last ?? [:]), dictionary(starter))
    }

    /// Verifies the mirrored case: two AND rows + add group yields "(a AND b) OR new".
    func testAddingGroupFoldsAndRowsUnderOrRoot() {
        let a = expression(column: "a", values: ["1"])
        let b = expression(column: "b", values: ["2"])

        let tree = SARuleFilterRootConjunction.treeAddingGroup(starter: expression(column: "c", values: [""]), to: rootGroup(children: [a, b], isConjunction: true), rootIsConjunction: true)

        XCTAssertEqual(tree["isConjunction"] as? Bool, false)
        XCTAssertEqual(children(of: tree).first?["isConjunction"] as? Bool, true)
    }

    /// Verifies a seeded row hiding among the top-level rows is dropped while folding.
    func testAddingGroupDropsSeededRowWhileFolding() {
        let a = expression(column: "a", values: ["1"])
        let b = expression(column: "b", values: ["2"])
        let seeded = expression(column: "a", values: [""])

        let tree = SARuleFilterRootConjunction.treeAddingGroup(starter: expression(column: "c", values: [""]), to: rootGroup(children: [seeded, a, b], isConjunction: false), rootIsConjunction: false)

        XCTAssertEqual(children(of: children(of: tree).first ?? [:]).map(dictionary), [a, b].map(dictionary))
    }

    /// Verifies a single real row keeps the old behaviour: a nested group with the opposite conjunction is appended.
    func testAddingGroupBesideSingleRowKeepsRoot() {
        let a = expression(column: "a", values: ["1"])
        let starter = expression(column: "b", values: [""])

        let tree = SARuleFilterRootConjunction.treeAddingGroup(starter: starter, to: a, rootIsConjunction: true)

        XCTAssertEqual(tree["isConjunction"] as? Bool, true, "root keeps AND")
        let kids = children(of: tree)
        XCTAssertEqual(kids.count, 2)
        XCTAssertEqual(dictionary(kids.first ?? [:]), dictionary(a))
        XCTAssertEqual(kids.last?["isConjunction"] as? Bool, false)
        XCTAssertEqual(children(of: kids.last ?? [:]).map(dictionary), [dictionary(starter)])
    }

    // MARK: - Persisted-format compatibility (fixtures)

    /// A verbatim `contentFilterV2` tree as pre-AND/OR-popup versions persisted it into `.spf`
    /// session plists: a lone OR compound row, no `rootGroup` marker.
    private static let legacyContentFilterV2Fixture = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>filterClass</key><string>groupNode</string>
            <key>isConjunction</key><false/>
            <key>children</key>
            <array>
                <dict>
                    <key>filterClass</key><string>expressionNode</string>
                    <key>column</key><string>PLZ</string>
                    <key>filterComparison</key><string>=</string>
                    <key>filterType</key><string>string</string>
                    <key>filterValues</key><array><string>77694</string></array>
                    <key>enabled</key><true/>
                </dict>
                <dict>
                    <key>filterClass</key><string>expressionNode</string>
                    <key>column</key><string>PLZ</string>
                    <key>filterComparison</key><string>=</string>
                    <key>filterType</key><string>string</string>
                    <key>filterValues</key><array><string>40789</string></array>
                    <key>enabled</key><true/>
                </dict>
            </array>
        </dict>
        </plist>
        """

    /// Verifies a legacy `.spf` fixture (persisted before the popup existed) decodes and keeps its
    /// old meaning: one nested OR row under the implicit AND root – not a flattened OR root.
    func testLegacyContentFilterV2FixtureKeepsItsMeaning() throws {
        let data = try XCTUnwrap(Self.legacyContentFilterV2Fixture.data(using: .utf8))
        let decoded = try XCTUnwrap(try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any])

        let plan = SARuleFilterRootConjunction.restorePlan(for: decoded)

        XCTAssertTrue(plan.isConjunction, "legacy trees restore under the implicit AND root")
        XCTAssertEqual(plan.items.count, 1, "the OR group stays one nested row")
        XCTAssertEqual(plan.items.first?["isConjunction"] as? Bool, false)
        XCTAssertEqual(children(of: plan.items.first ?? [:]).count, 2)
    }

    /// Verifies the new wire format is a plain plist that legacy readers can decode: it round-trips
    /// through PropertyListSerialization, and stripping the unknown `rootGroup` key (which old
    /// readers ignore) leaves exactly the tree shape they always understood.
    func testNewWireFormatStaysReadableByLegacyReaders() throws {
        let root = SARuleFilterRootConjunction.serializedRoot(items: [expression(column: "a", values: ["1"]), expression(column: "b", values: ["2"])], isConjunction: false)

        let data = try PropertyListSerialization.data(fromPropertyList: root, format: .xml, options: 0)
        var decoded = try XCTUnwrap(try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any])

        XCTAssertEqual(decoded["rootGroup"] as? Bool, true, "the marker survives the plist round trip")
        // A legacy reader only looks at filterClass/isConjunction/children and
        // ignores the marker – the remaining tree is the shape it always knew.
        decoded.removeValue(forKey: "rootGroup")
        XCTAssertEqual(decoded["filterClass"] as? String, "groupNode")
        XCTAssertEqual(decoded["isConjunction"] as? Bool, false)
        XCTAssertEqual((decoded["children"] as? [[String: Any]])?.count, 2)
    }

    // MARK: - Controller round trip

    /// Verifies the OR choice for a single-row filter survives serialize → setColumns-reset → restore.
    func testControllerKeepsOrChoiceForSingleRowAcrossRestore() throws {
        let controller = try makeController(columns: ["a", "b"])
        restore(expression(column: "a", values: ["1"]), into: controller)
        controller.setValue(false, forKey: "rootIsConjunction")

        let saved = try XCTUnwrap(serializedFilter(of: controller))
        XCTAssertEqual(saved["rootGroup"] as? Bool, true, "single row with OR is persisted wrapped")

        // Simulate a table reload: setColumns resets the popup to AND, then the saved filter is restored.
        controller.perform(NSSelectorFromString("setColumns:"), with: columnDefinitions(["a", "b"]))
        XCTAssertEqual(controller.value(forKey: "rootIsConjunction") as? Bool, true)
        restore(saved, into: controller)

        XCTAssertEqual(controller.value(forKey: "rootIsConjunction") as? Bool, false, "OR came back from the saved filter")
        let kids = children(of: try XCTUnwrap(serializedFilter(of: controller)))
        XCTAssertEqual(kids.count, 1)
        XCTAssertEqual(kids.first?["column"] as? String, "a")
    }

    /// Verifies an OR root survives restore → serialize through SPRuleFilterController and that the popup state drives serialization.
    func testControllerRoundTripsRootConjunction() throws {
        let controller = try makeController(columns: ["a", "b"])
        let a = expression(column: "a", values: ["1"])
        let b = expression(column: "b", values: ["2"])

        restore(rootGroup(children: [a, b], isConjunction: false), into: controller)

        XCTAssertEqual(controller.value(forKey: "rootIsConjunction") as? Bool, false)
        let serialized = try XCTUnwrap(serializedFilter(of: controller))
        XCTAssertEqual(serialized["isConjunction"] as? Bool, false)
        // The controller adds bookkeeping keys (filterType, enabled) on the
        // way out, so compare the user-visible parts of each row only.
        let kids = children(of: serialized)
        XCTAssertEqual(kids.map { $0["column"] as? String }, ["a", "b"])
        XCTAssertEqual(kids.map { $0["filterValues"] as? [String] }, [["1"], ["2"]])

        // Flipping the popup state is enough to change what gets serialized.
        controller.setValue(true, forKey: "rootIsConjunction")
        XCTAssertEqual(try XCTUnwrap(serializedFilter(of: controller))["isConjunction"] as? Bool, true)
    }

    /// Verifies reconfiguring the columns resets the popup to AND.
    func testControllerResetsRootConjunctionWhenColumnsChange() throws {
        let controller = try makeController(columns: ["a", "b"])
        controller.setValue(false, forKey: "rootIsConjunction")

        controller.perform(NSSelectorFromString("setColumns:"), with: columnDefinitions(["a"]))

        XCTAssertEqual(controller.value(forKey: "rootIsConjunction") as? Bool, true)
    }

    /// Verifies a legacy filter (single unmarked OR group, as older versions persisted it) restores as one nested row under an AND root.
    func testControllerRestoresLegacyOrGroupAsNestedRow() throws {
        let controller = try makeController(columns: ["a", "b"])
        let legacyOrGroup = group(children: [expression(column: "a", values: ["1"]), expression(column: "b", values: ["2"])], isConjunction: false)

        restore(legacyOrGroup, into: controller)

        XCTAssertEqual(controller.value(forKey: "rootIsConjunction") as? Bool, true)
        let serialized = try XCTUnwrap(serializedFilter(of: controller))
        XCTAssertEqual(serialized["isConjunction"] as? Bool, true)
        XCTAssertEqual(serialized["rootGroup"] as? Bool, true)
        let kids = children(of: serialized)
        XCTAssertEqual(kids.count, 1)
        XCTAssertEqual(kids.first?["isConjunction"] as? Bool, false)
        XCTAssertNil(kids.first?["rootGroup"])
        XCTAssertEqual(children(of: kids.first ?? [:]).count, 2)
    }

    /// Verifies a single nested OR group under an AND root keeps its shape through the controller's restore → serialize round trip.
    func testControllerKeepsSingleNestedGroupUnderAndRoot() throws {
        let controller = try makeController(columns: ["a", "b"])
        let nested = group(children: [expression(column: "a", values: ["1"]), expression(column: "b", values: ["2"])], isConjunction: false)

        restore(rootGroup(children: [nested], isConjunction: true), into: controller)

        XCTAssertEqual(controller.value(forKey: "rootIsConjunction") as? Bool, true)
        let serialized = try XCTUnwrap(serializedFilter(of: controller))
        XCTAssertEqual(serialized["isConjunction"] as? Bool, true)
        let kids = children(of: serialized)
        XCTAssertEqual(kids.count, 1)
        XCTAssertEqual(kids.first?["filterClass"] as? String, "groupNode")
        XCTAssertEqual(kids.first?["isConjunction"] as? Bool, false)
        XCTAssertEqual(children(of: kids.first ?? [:]).count, 2)
    }

    /// Verifies -addEmptyFilterGroup replaces the seeded starter row instead of leaving "a = ''" beside the new group.
    func testControllerReplacesUntouchedStarterWhenAddingGroup() throws {
        let controller = try makeController(columns: ["a", "b"])
        restore(expression(column: "a", values: [""]), into: controller)

        controller.perform(NSSelectorFromString("addEmptyFilterGroup"))

        let serialized = try XCTUnwrap(serializedFilter(of: controller))
        let kids = children(of: serialized)
        XCTAssertEqual(kids.count, 1, "the starter row is gone, only the group remains")
        XCTAssertEqual(kids.first?["filterClass"] as? String, "groupNode")
        XCTAssertEqual(kids.first?["isConjunction"] as? Bool, false)
    }

    /// Verifies the reported end-to-end case: two OR rows + add group + filled row give "(a OR b) AND c" through the controller.
    func testControllerFoldsOrRowsWhenAddingGroup() throws {
        let controller = try makeController(columns: ["PLZ", "NAME46"])
        restore(rootGroup(children: [expression(column: "PLZ", values: ["77694"]), expression(column: "PLZ", values: ["40789"])], isConjunction: false), into: controller)
        XCTAssertEqual(controller.value(forKey: "rootIsConjunction") as? Bool, false)

        controller.perform(NSSelectorFromString("addEmptyFilterGroup"))

        XCTAssertEqual(controller.value(forKey: "rootIsConjunction") as? Bool, true, "root flipped to AND")
        let serialized = try XCTUnwrap(serializedFilter(of: controller))
        let kids = children(of: serialized)
        XCTAssertEqual(kids.count, 2)
        XCTAssertEqual(kids.first?["isConjunction"] as? Bool, false)
        XCTAssertEqual(children(of: kids.first ?? [:]).count, 2)
        XCTAssertEqual(kids.last?["filterClass"] as? String, "expressionNode", "the new row sits at the top level")
    }

    /// Verifies -addEmptyFilterGroup beside a single row appends a visible group (with the opposite conjunction) and keeps the root.
    func testControllerAddsNestedGroupRow() throws {
        let controller = try makeController(columns: ["a", "b"])
        restore(expression(column: "a", values: ["1"]), into: controller)

        controller.perform(NSSelectorFromString("addEmptyFilterGroup"))

        let serialized = try XCTUnwrap(serializedFilter(of: controller))
        XCTAssertEqual(serialized["isConjunction"] as? Bool, true, "root stays AND")
        let kids = children(of: serialized)
        XCTAssertEqual(kids.count, 2)
        XCTAssertEqual(kids[1]["filterClass"] as? String, "groupNode")
        XCTAssertEqual(kids[1]["isConjunction"] as? Bool, false, "nested group is OR under an AND root")
        XCTAssertEqual(children(of: kids[1]).count, 1)
    }

    // MARK: - Helpers

    /// Builds a serialized expression node in the controller's dictionary shape.
    private func expression(column: String, comparison: String = "=", values: [String]) -> [String: Any] {
        return [
            "filterClass": "expressionNode",
            "column": column,
            "filterComparison": comparison,
            "filterValues": values,
        ]
    }

    /// Builds a serialized group node in the controller's dictionary shape – a nested compound row,
    /// or a legacy root written before the AND/OR popup existed (both carry no `rootGroup` marker).
    private func group(children: [[String: Any]], isConjunction: Bool) -> [String: Any] {
        return [
            "filterClass": "groupNode",
            "isConjunction": isConjunction,
            "children": children,
        ]
    }

    /// Builds the marked root group the current serializer writes for the AND/OR popup.
    private func rootGroup(children: [[String: Any]], isConjunction: Bool) -> [String: Any] {
        var node = group(children: children, isConjunction: isConjunction)
        node["rootGroup"] = true
        return node
    }

    /// The children of a serialized group, or an empty array for expressions.
    private func children(of filter: [String: Any]) -> [[String: Any]] {
        return filter["children"] as? [[String: Any]] ?? []
    }

    /// Bridges to `NSDictionary` so nested `[String: Any]` values can be compared with `XCTAssertEqual`.
    private func dictionary(_ filter: [String: Any]) -> NSDictionary {
        return filter as NSDictionary
    }

    /// Column definitions in the shape `-[SPRuleFilterController setColumns:]` expects (all string-typed).
    private func columnDefinitions(_ names: [String]) -> [[String: Any]] {
        return names.map { ["name": $0, "typegrouping": "string"] }
    }

    /// Creates an `SPRuleFilterController` with a bare rule editor and the given string columns, via KVC/selectors
    /// because the test target has no bridging header for the Objective-C class.
    private func makeController(columns: [String]) throws -> NSObject {
        let controllerClass = try XCTUnwrap(NSClassFromString("SPRuleFilterController") as? NSObject.Type)
        let controller = controllerClass.init()
        let ruleEditor = NSRuleEditor(frame: NSRect(x: 0, y: 0, width: 600, height: 120))
        ruleEditor.delegate = controller as? NSRuleEditorDelegate
        controller.setValue(ruleEditor, forKey: "filterRuleEditor")
        controller.perform(NSSelectorFromString("setColumns:"), with: columnDefinitions(columns))
        return controller
    }

    /// Calls `-restoreSerializedFilters:` on the controller.
    private func restore(_ filter: [String: Any], into controller: NSObject) {
        controller.perform(NSSelectorFromString("restoreSerializedFilters:"), with: filter)
    }

    /// Calls `-serializedFilter` on the controller and bridges the result.
    private func serializedFilter(of controller: NSObject) -> [String: Any]? {
        return controller.perform(NSSelectorFromString("serializedFilter"))?.takeUnretainedValue() as? [String: Any]
    }
}
