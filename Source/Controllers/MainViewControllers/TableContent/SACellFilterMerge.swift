//
//  SACellFilterMerge.swift
//  Sequel Ace
//
//  Created by Sequel-Ace contributors on 2026.05.23.
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import Foundation

/// Merges a newly requested cell filter into the rule-filter tree already
/// shown in the rule editor.
///
/// The helper understands the serialized dictionary shape produced by
/// `SPRuleFilterController` and keeps the merge logic testable outside the
/// Objective-C controller.
@objcMembers public final class SACellFilterMerge: NSObject {

    /// Appends a new filter rule while removing rule-editor placeholder rows.
    ///
    /// Existing real filters are combined with the new rule under an AND group.
    /// Only explicitly marked, unchecked starter rows are dropped. An empty
    /// argument is a valid user condition (`column = ''`), whether enabled or
    /// deliberately disabled, and must survive the merge.
    ///
    /// - Parameters:
    ///   - currentFilter: Serialized filter currently restored in the rule editor.
    ///   - newFilter: Serialized filter created from the clicked cell.
    /// - Returns: A serialized filter tree ready for `restoreSerializedFilters:`.
    public static func mergedFilter(currentFilter: [String: Any]?, newFilter: [String: Any]) -> [String: Any] {
        guard let currentFilter, !isEmpty(filter: currentFilter), !isUntouchedStarter(filter: currentFilter) else {
            return newFilter
        }

        // A marked root group (the shape the AND/OR popup writes) is extended
        // under its own conjunction, so "Filter by value" on an OR root yields
        // "a OR b OR cell" instead of flipping the popup to AND.
        if let extended = SARuleFilterRootConjunction.extendingMarkedRoot(currentFilter, withRule: newFilter) {
            return extended
        }

        if isConjunctionGroup(filter: currentFilter), let children = currentFilter["children"] as? [[String: Any]] {
            // Strip empty nodes and explicitly marked unchecked starter children before appending
            var realChildren = children.filter { !isEmpty(filter: $0) && !isUntouchedStarter(filter: $0) }
            realChildren.append(newFilter)
            if realChildren.count == 1 {
                return realChildren[0]
            }
            return andGroup(children: realChildren)
        }

        return andGroup(children: [currentFilter, newFilter])
    }

    /// Whether a serialized filter contributes no usable rule content.
    ///
    /// Empty AND groups and expression rows without a selected column are
    /// treated as empty. Unknown filter classes are considered empty so callers
    /// fail closed rather than preserving malformed state.
    ///
    /// - Parameter filter: Serialized filter dictionary to inspect.
    /// - Returns: `true` when the filter should be replaced by the new rule.
    public static func isEmpty(filter: [String: Any]?) -> Bool {
        guard let filter else {
            return true
        }

        if filter["filterClass"] as? String == "groupNode" {
            let children = filter["children"] as? [Any]
            return children?.isEmpty ?? true
        }

        if filter["filterClass"] as? String == "expressionNode" {
            return (filter["column"] as? String)?.isEmpty ?? true
        }

        return true
    }

    /// Whether the controller explicitly identifies an unchecked, untouched
    /// seeded row. Empty arguments alone never identify a placeholder: checked
    /// and deliberately disabled user predicates can both compare with ''.
    ///
    /// Zero-argument operators such as IS NULL remain real rules even if an
    /// obsolete starter marker is present. A checked row also remains real.
    ///
    /// - Parameter filter: Serialized expression-node dictionary to inspect.
    /// - Returns: `true` only for a marked, unchecked row with nonempty,
    ///   all-empty arguments.
    public static func isUntouchedStarter(filter: [String: Any]?) -> Bool {
        guard let filter,
              filter["filterClass"] as? String == "expressionNode",
              (filter["pendingStarter"] as? NSNumber)?.boolValue == true,
              (filter["enabled"] as? NSNumber)?.boolValue != true else {
            return false
        }

        guard let values = filter["filterValues"] as? [Any], !values.isEmpty else {
            return false
        }

        for value in values {
            guard let string = value as? String, string.isEmpty else {
                return false
            }
        }

        return true
    }

    private static func isConjunctionGroup(filter: [String: Any]) -> Bool {
        return filter["filterClass"] as? String == "groupNode" && filter["isConjunction"] as? Bool == true
    }

    private static func andGroup(children: [[String: Any]]) -> [String: Any] {
        return [
            "filterClass": "groupNode",
            "isConjunction": true,
            "children": children,
        ]
    }
}
