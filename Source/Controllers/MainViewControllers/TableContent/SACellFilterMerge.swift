//
//  SACellFilterMerge.swift
//  Sequel Ace
//
//  Created by Sequel-Ace contributors on 2026.05.23.
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import Foundation

@objcMembers public final class SACellFilterMerge: NSObject {

    public static func mergedFilter(currentFilter: [String: Any]?, newFilter: [String: Any]) -> [String: Any] {
        guard let currentFilter, !isEmpty(filter: currentFilter), !isUntouchedStarter(filter: currentFilter) else {
            return newFilter
        }

        if isConjunctionGroup(filter: currentFilter), var children = currentFilter["children"] as? [[String: Any]] {
            children.append(newFilter)
            return andGroup(children: children)
        }

        return andGroup(children: [currentFilter, newFilter])
    }

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

    public static func isUntouchedStarter(filter: [String: Any]?) -> Bool {
        guard let filter, filter["filterClass"] as? String == "expressionNode" else {
            return false
        }

        guard let values = filter["filterValues"] as? [Any] else {
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
