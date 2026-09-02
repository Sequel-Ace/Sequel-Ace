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
///
/// Format note: the root group written by `serializedRoot(items:isConjunction:)`
/// carries the marker `rootGroup = true`. Trees written before the AND/OR popup
/// existed (older `.spf` sessions, query history, `contentFilterV2`) have no
/// marker; for those the old semantics apply – an AND group at the root is
/// unpacked into rows, any other group is one nested row under an implicit
/// AND root. Older readers ignore the marker and still restore the same SQL.
@objcMembers public final class SARuleFilterRootConjunction: NSObject {
    private static let filterClassKey = "filterClass"
    private static let groupClass = "groupNode"
    private static let isConjunctionKey = "isConjunction"
    private static let childrenKey = "children"
    /// Marks the group that represents the AND/OR popup, as opposed to a
    /// nested compound row. Only the root written by this type carries it.
    private static let rootGroupKey = "rootGroup"

    /// Builds the serialized root for the given top-level rows.
    ///
    /// A single expression under the default AND is returned as itself, which
    /// keeps the persisted shape of the common one-row filter unchanged. Any
    /// other case – several rows, no rows, a single nested group, or a single
    /// expression with OR selected – is wrapped in the marked root group so
    /// the popup choice survives a reload/restore. Wrapping a lone nested
    /// group matters for a second reason: without the wrapper, `AND[(a OR b)]`
    /// would be indistinguishable from an OR root with two rows, and
    /// `restorePlan(for:)` would flatten it into the
    /// popup, so a later append would produce `a OR b OR c` instead of
    /// `(a OR b) AND c`.
    ///
    /// - Parameters:
    ///   - items: Serialized top-level rows.
    ///   - isConjunction: `true` to combine them with AND, `false` for OR.
    /// - Returns: The serialized filter tree.
    @objc(serializedRootWithItems:isConjunction:)
    public static func serializedRoot(items: [[String: Any]], isConjunction: Bool) -> [String: Any] {
        if items.count == 1 && !isGroup(items[0]) && isConjunction {
            return items[0]
        }
        return group(children: items, isConjunction: isConjunction, isRoot: true)
    }

    /// Splits a serialized filter tree into the root conjunction and the
    /// top-level rows to show.
    ///
    /// A marked root group is unpacked into top-level rows and the popup takes
    /// over its conjunction. A group without the marker is a legacy tree: an
    /// AND group is unpacked as the old code did, anything else is kept as one
    /// nested compound row under an AND root – exactly what the old rule editor
    /// showed for it, so `(a OR b)` followed by an append still yields
    /// `(a OR b) AND c`. A bare expression resets the popup to AND: it is
    /// either the legacy one-row shape (implicit AND) or a freshly built
    /// replacement such as a foreign-key navigation filter – with OR selected
    /// the serializer always writes the marked wrapper, so a stale OR must not
    /// leak into a tree that never carried one.
    ///
    /// - Parameter serialized: The serialized filter tree.
    /// - Returns: The plan describing what to restore.
    @objc(restorePlanFor:)
    public static func restorePlan(for serialized: [String: Any]) -> SARuleFilterRootRestorePlan {
        guard isGroup(serialized) else {
            return SARuleFilterRootRestorePlan(isConjunction: true, items: [serialized])
        }
        let children = serialized[childrenKey] as? [[String: Any]] ?? []
        if isRootGroup(serialized) {
            return SARuleFilterRootRestorePlan(isConjunction: groupIsConjunction(serialized), items: children)
        }
        if groupIsConjunction(serialized) {
            return SARuleFilterRootRestorePlan(isConjunction: true, items: children)
        }
        return SARuleFilterRootRestorePlan(isConjunction: true, items: [serialized])
    }

    /// Appends a new rule to the existing tree as a further top-level row.
    ///
    /// Mirrors the drag-and-drop append flow: a missing or untouched starter
    /// tree is replaced outright, a marked root group with the current
    /// conjunction gains a child, and anything else – a single expression or a
    /// nested (unmarked) group – is wrapped together with the new rule under
    /// the root conjunction.
    ///
    /// - Parameters:
    ///   - rule: The serialized expression to append.
    ///   - existing: The serialized tree currently shown, if any.
    ///   - rootIsConjunction: The conjunction selected for the top level.
    /// - Returns: The serialized tree to restore.
    @objc(appendingRule:to:rootIsConjunction:)
    public static func appending(rule: [String: Any], to existing: [String: Any]?, rootIsConjunction: Bool) -> [String: Any] {
        guard let existing, !isUntouchedStarterTree(existing) else {
            // Replacing the seeded row must not lose the popup choice: with OR
            // selected the starter lives inside the marked wrapper, so put the
            // replacement into the same wrapper instead of returning it bare
            // (a bare expression restores as the default AND).
            if let existing, isRootGroup(existing) {
                return group(children: [rule], isConjunction: groupIsConjunction(existing), isRoot: true)
            }
            return rule
        }
        if isRootGroup(existing) && groupIsConjunction(existing) == rootIsConjunction {
            // Strip untouched starter children (the seeded empty row can sit
            // inside the root when the popup was flipped before typing), so
            // appending never produces "firstColumn = '' AND/OR dropped".
            var children = (existing[childrenKey] as? [[String: Any]] ?? [])
                .filter { !SACellFilterMerge.isUntouchedStarter(filter: $0) }
            children.append(rule)
            return group(children: children, isConjunction: rootIsConjunction, isRoot: true)
        }
        return group(children: [existing, rule], isConjunction: rootIsConjunction, isRoot: true)
    }

    /// Replaces the top-level row at `row` with a new rule.
    ///
    /// `row` addresses the root children (the caller maps visible rule-editor
    /// rows to this ordinal). The target child must be an expression – a
    /// nested group cannot be "replaced" by a single rule – but groups
    /// elsewhere in the tree are fine.
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
        if isRootGroup(existing) && groupIsConjunction(existing) == rootIsConjunction {
            var children = existing[childrenKey] as? [[String: Any]] ?? []
            guard row < children.count, !isGroup(children[row]) else {
                return nil
            }
            children[row] = rule
            return group(children: children, isConjunction: rootIsConjunction, isRoot: true)
        }
        return row == 0 && !isGroup(existing) ? rule : nil
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
        return group(children: [child], isConjunction: !rootIsConjunction, isRoot: false)
    }

    /// Builds the whole tree for the "Add AND/OR Group" action.
    ///
    /// The result depends on what the editor already shows:
    ///
    /// * empty, or only the seeded starter row → one nested group holding the
    ///   starter (the placeholder is replaced, the root keeps its conjunction);
    /// * a single top-level row (expression or one nested group) → a nested
    ///   group with the opposite conjunction is appended beside it, as before;
    /// * **two or more top-level rows** → the existing rows are folded into one
    ///   nested group keeping the current conjunction, the root flips to the
    ///   opposite, and the starter becomes a plain second row. Rows built with
    ///   OR therefore yield `(a OR b) AND new`, not `a OR b OR new` – adding a
    ///   group means "combine everything so far with something new", which is
    ///   what the popup + group UI suggests.
    ///
    /// Seeded starter rows hiding among real rows are dropped, so the result
    /// never contains a stray `column = ''` condition.
    ///
    /// - Parameters:
    ///   - starter: The serialized starter expression for the new group/row.
    ///   - existing: The serialized tree currently shown, if any.
    ///   - rootIsConjunction: The conjunction selected for the top level.
    /// - Returns: The serialized tree to restore.
    @objc(treeAddingGroupWithStarter:to:rootIsConjunction:)
    public static func treeAddingGroup(starter: [String: Any], to existing: [String: Any]?, rootIsConjunction: Bool) -> [String: Any] {
        guard let existing, !isUntouchedStarterTree(existing) else {
            return group(children: [nestedGroup(child: starter, rootIsConjunction: rootIsConjunction)], isConjunction: rootIsConjunction, isRoot: true)
        }
        if isRootGroup(existing) {
            let real = (existing[childrenKey] as? [[String: Any]] ?? [])
                .filter { !SACellFilterMerge.isUntouchedStarter(filter: $0) }
            if real.count >= 2 {
                let wrapped = group(children: real, isConjunction: groupIsConjunction(existing), isRoot: false)
                return group(children: [wrapped, starter], isConjunction: !groupIsConjunction(existing), isRoot: true)
            }
            return group(children: real + [nestedGroup(child: starter, rootIsConjunction: rootIsConjunction)], isConjunction: rootIsConjunction, isRoot: true)
        }
        return group(children: [existing, nestedGroup(child: starter, rootIsConjunction: rootIsConjunction)], isConjunction: rootIsConjunction, isRoot: true)
    }

    /// Whether the whole tree is nothing but the untouched starter row the
    /// rule editor seeds when it is first shown (one expression whose
    /// arguments are all empty). Such a row would contribute `column = ''`
    /// to the query, so callers that add a real rule or group replace it
    /// instead of appending beside it – the same rule the drag-and-drop
    /// append flow applies.
    ///
    /// - Parameter tree: The serialized tree currently shown, if any.
    /// - Returns: `true` when the tree is a lone untouched starter row.
    @objc(isUntouchedStarterTree:)
    public static func isUntouchedStarterTree(_ tree: [String: Any]?) -> Bool {
        guard let tree else { return false }
        if isRootGroup(tree) {
            // With OR selected, even a lone seeded row is wrapped in the root
            // group – look through the wrapper.
            let children = tree[childrenKey] as? [[String: Any]] ?? []
            return !children.isEmpty && children.allSatisfy { SACellFilterMerge.isUntouchedStarter(filter: $0) }
        }
        return SACellFilterMerge.isUntouchedStarter(filter: tree)
    }

    /// Whether the serialized node is a group (as opposed to an expression).
    private static func isGroup(_ filter: [String: Any]) -> Bool {
        return filter[filterClassKey] as? String == groupClass
    }

    /// The group's conjunction flag; `false` when missing, matching the
    /// Objective-C `boolValue` reading of the same key.
    private static func groupIsConjunction(_ filter: [String: Any]) -> Bool {
        return (filter[isConjunctionKey] as? NSNumber)?.boolValue ?? false
    }

    /// Extends the marked root group written by this type with one more rule,
    /// keeping its conjunction and marker; seeded starter children are dropped.
    /// Used by the cell-filter merge so "Filter by value" appends a row under
    /// the current popup conjunction instead of forcing an AND wrapper around
    /// an OR root.
    ///
    /// - Parameters:
    ///   - tree: The serialized tree currently shown.
    ///   - rule: The serialized expression to append.
    /// - Returns: The extended root, the rule alone when only seeded rows were
    ///   present, or `nil` when `tree` is not a marked root group (legacy
    ///   shapes keep their existing merge behaviour).
    @objc(extendingMarkedRoot:withRule:)
    public static func extendingMarkedRoot(_ tree: [String: Any], withRule rule: [String: Any]) -> [String: Any]? {
        guard isRootGroup(tree) else { return nil }
        let real = (tree[childrenKey] as? [[String: Any]] ?? [])
            .filter { !SACellFilterMerge.isUntouchedStarter(filter: $0) }
        // Even when only seeded rows were present, keep the marked wrapper so
        // the popup choice (e.g. OR) survives the restore.
        return group(children: real + [rule], isConjunction: groupIsConjunction(tree), isRoot: true)
    }

    /// Whether the serialized group carries the root marker written by
    /// `serializedRoot(items:isConjunction:)`.
    private static func isRootGroup(_ filter: [String: Any]) -> Bool {
        return isGroup(filter) && ((filter[rootGroupKey] as? NSNumber)?.boolValue ?? false)
    }

    /// Builds a serialized group node; `isRoot` adds the root marker.
    private static func group(children: [[String: Any]], isConjunction: Bool, isRoot: Bool) -> [String: Any] {
        var node: [String: Any] = [
            filterClassKey: groupClass,
            isConjunctionKey: isConjunction,
            childrenKey: children
        ]
        if isRoot {
            node[rootGroupKey] = true
        }
        return node
    }
}
