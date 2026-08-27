//
//  SARuleFilterRootConjunction.swift
//  Sequel Ace
//
//  Created by Sequel-Ace contributors on 2026.08.27.
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import Foundation

/// Result of splitting a serialized filter tree into the pieces the rule
/// editor shows: the root conjunction (the AND/OR popup next to the Apply
/// button) and the top-level rows.
@objc public final class SARuleFilterRootRestorePlan: NSObject {
    /// `true` when the top-level rows are combined with AND, `false` for OR.
    @objc public let isConjunction: Bool
    /// The serialized top-level rows to restore, in order.
    @objc public let items: [[String: Any]]

    fileprivate init(isConjunction: Bool, items: [[String: Any]]) {
        self.isConjunction = isConjunction
        self.items = items
    }
}

/// Pure helpers around the root of the rule-filter tree.
///
/// The rule editor keeps the top-level rows as a flat list; how they are
/// combined (AND / OR) is a single flag owned by `SPRuleFilterController`.
/// These helpers translate between that flat representation and the
/// serialized dictionary shape (`filterClass` / `isConjunction` / `children`)
/// used for persistence, drag-and-drop merges and SQL generation, and keep the
/// logic testable outside the Objective-C controller.
///
/// Serialized keys are inlined as private literals – keep in sync with
/// `SPRuleFilterController.m`.
@objcMembers public final class SARuleFilterRootConjunction: NSObject {
    private static let filterClassKey = "filterClass"
    private static let groupClass = "groupNode"
    private static let isConjunctionKey = "isConjunction"
    private static let childrenKey = "children"

    /// Builds the serialized root for the given top-level rows.
    ///
    /// A single row is returned as itself (its conjunction is irrelevant);
    /// any other count – including zero – is wrapped in a group carrying the
    /// root conjunction so it survives a round trip.
    ///
    /// - Parameters:
    ///   - items: Serialized top-level rows.
    ///   - isConjunction: `true` to combine them with AND, `false` for OR.
    /// - Returns: The serialized filter tree.
    @objc(serializedRootWithItems:isConjunction:)
    public static func serializedRoot(items: [[String: Any]], isConjunction: Bool) -> [String: Any] {
        if items.count == 1 {
            return items[0]
        }
        return group(children: items, isConjunction: isConjunction)
    }

    /// Splits a serialized filter tree into the root conjunction and the
    /// top-level rows to show.
    ///
    /// A group at the root is always unpacked into top-level rows: the popup
    /// takes over the group's conjunction, so a single top-level group would
    /// only duplicate what the popup already expresses. A single expression
    /// keeps whatever conjunction is currently selected, because a lone row
    /// carries no information about it.
    ///
    /// - Parameters:
    ///   - serialized: The serialized filter tree.
    ///   - currentIsConjunction: The conjunction currently shown in the popup.
    /// - Returns: The plan describing what to restore.
    @objc(restorePlanFor:currentIsConjunction:)
    public static func restorePlan(for serialized: [String: Any], currentIsConjunction: Bool) -> SARuleFilterRootRestorePlan {
        if isGroup(serialized) {
            let children = serialized[childrenKey] as? [[String: Any]] ?? []
            return SARuleFilterRootRestorePlan(isConjunction: groupIsConjunction(serialized), items: children)
        }
        return SARuleFilterRootRestorePlan(isConjunction: currentIsConjunction, items: [serialized])
    }

    /// Appends a new rule to the existing tree as a further top-level row.
    ///
    /// Mirrors the drag-and-drop append flow: a missing or untouched starter
    /// tree is replaced outright, a root group with the current conjunction
    /// gains a child, and anything else is wrapped together with the new rule
    /// under the root conjunction.
    ///
    /// - Parameters:
    ///   - rule: The serialized expression to append.
    ///   - existing: The serialized tree currently shown, if any.
    ///   - rootIsConjunction: The conjunction selected for the top level.
    /// - Returns: The serialized tree to restore.
    @objc(appendingRule:to:rootIsConjunction:)
    public static func appending(rule: [String: Any], to existing: [String: Any]?, rootIsConjunction: Bool) -> [String: Any] {
        guard let existing, !SACellFilterMerge.isUntouchedStarter(filter: existing) else {
            return rule
        }
        if isGroup(existing) && groupIsConjunction(existing) == rootIsConjunction {
            var children = existing[childrenKey] as? [[String: Any]] ?? []
            children.append(rule)
            return group(children: children, isConjunction: rootIsConjunction)
        }
        return group(children: [existing, rule], isConjunction: rootIsConjunction)
    }

    /// Replaces the top-level row at `row` with a new rule.
    ///
    /// Only a single expression (row 0) or a flat root group – one whose
    /// children are all expressions – can be addressed by row index; nested
    /// groups insert extra rule-editor rows for their own children and break
    /// the 1:1 mapping, so they are rejected.
    ///
    /// - Parameters:
    ///   - rule: The serialized expression to put at `row`.
    ///   - row: 0-based top-level row index.
    ///   - existing: The serialized tree currently shown, if any.
    ///   - rootIsConjunction: The conjunction selected for the top level.
    /// - Returns: The serialized tree to restore, or `nil` when `row` cannot
    ///   be mapped onto the tree.
    @objc(replacingRule:atRow:in:rootIsConjunction:)
    public static func replacing(rule: [String: Any], atRow row: Int, in existing: [String: Any]?, rootIsConjunction: Bool) -> [String: Any]? {
        guard row >= 0 else { return nil }
        guard let existing else {
            return rule
        }
        if isGroup(existing) && groupIsConjunction(existing) == rootIsConjunction {
            var children = existing[childrenKey] as? [[String: Any]] ?? []
            guard !children.contains(where: isGroup), row < children.count else {
                return nil
            }
            children[row] = rule
            return group(children: children, isConjunction: rootIsConjunction)
        }
        return row == 0 ? rule : nil
    }

    /// Builds a serialized group with a single child, used for the "Add
    /// AND/OR Group" affordance. The group uses the opposite of the root
    /// conjunction, because nesting the same conjunction would be a no-op.
    ///
    /// - Parameters:
    ///   - child: The serialized starter expression for the group.
    ///   - rootIsConjunction: The conjunction selected for the top level.
    /// - Returns: The serialized group.
    @objc(nestedGroupWithChild:rootIsConjunction:)
    public static func nestedGroup(child: [String: Any], rootIsConjunction: Bool) -> [String: Any] {
        return group(children: [child], isConjunction: !rootIsConjunction)
    }

    private static func isGroup(_ filter: [String: Any]) -> Bool {
        return filter[filterClassKey] as? String == groupClass
    }

    private static func groupIsConjunction(_ filter: [String: Any]) -> Bool {
        return (filter[isConjunctionKey] as? NSNumber)?.boolValue ?? false
    }

    private static func group(children: [[String: Any]], isConjunction: Bool) -> [String: Any] {
        return [
            filterClassKey: groupClass,
            isConjunctionKey: isConjunction,
            childrenKey: children,
        ]
    }
}
