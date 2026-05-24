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
    /// Empty starter rows and half-touched rows are dropped so right-clicking a
    /// cell after choosing a column in the rule editor does not produce an
    /// impossible `column = "" AND column = value` expression.
    ///
    /// - Parameters:
    ///   - currentFilter: Serialized filter currently restored in the rule editor.
    ///   - newFilter: Serialized filter created from the clicked cell.
    /// - Returns: A serialized filter tree ready for `restoreSerializedFilters:`.
    public static func mergedFilter(currentFilter: [String: Any]?, newFilter: [String: Any]) -> [String: Any] {
        guard let currentFilter, !isEmpty(filter: currentFilter), !isUntouchedStarter(filter: currentFilter) else {
            return newFilter
        }

        if isConjunctionGroup(filter: currentFilter), let children = currentFilter["children"] as? [[String: Any]] {
            // Strip placeholder children (empty starter or value-empty half-touched rows) before appending
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

    /// A "starter" or "half-touched placeholder" row that the user added to the rule editor
    /// but never filled in. Two shapes are recognized:
    ///   - Original starter: empty column + empty filterValues entries.
    ///   - Half-touched: column was picked but every filterValues entry is still an empty string.
    /// In both cases the row contributes nothing to the query and should be stripped during merge
    /// so that AND-appending a new cell filter does not produce an impossible WHERE clause.
    ///
    /// Zero-argument real operators (IS NULL / IS NOT NULL) serialize with `filterValues: []`
    /// (count == 0) so the `!values.isEmpty` guard keeps them out of the placeholder bucket.
    ///
    /// - Parameter filter: Serialized expression-node dictionary to inspect.
    /// - Returns: `true` when every stored argument is an empty string.
    public static func isUntouchedStarter(filter: [String: Any]?) -> Bool {
        guard let filter, filter["filterClass"] as? String == "expressionNode" else {
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
