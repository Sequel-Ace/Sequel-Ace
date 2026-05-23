//
//  SACellFilterMenuBuilder.swift
//  Sequel Ace
//
//  Created by Sequel-Ace contributors on 2026.05.23.
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import AppKit

@objcMembers public final class SACellFilterMenuItemDescriptor: NSObject {

    public let title: String
    public let columnName: String
    public let operatorName: String
    public let values: [String]
    public let isNull: Bool

    public init(title: String, columnName: String, operatorName: String, values: [String], isNull: Bool) {
        self.title = title
        self.columnName = columnName
        self.operatorName = operatorName
        self.values = values
        self.isNull = isNull
    }
}

@objcMembers public final class SACellFilterMenuBuilder: NSObject {

    public static func filterMenu(column: [String: Any], value: String?, isNull: Bool) -> NSMenu? {
        let descriptors = menuItemDescriptors(column: column, value: value, isNull: isNull)
        guard !descriptors.isEmpty else {
            return nil
        }

        let menu = NSMenu()
        for descriptor in descriptors {
            menu.addItem(NSMenuItem(title: descriptor.title, action: nil, keyEquivalent: ""))
        }

        return menu
    }

    public static func menuItemDescriptors(column: [String: Any], value: String?, isNull: Bool) -> [SACellFilterMenuItemDescriptor] {
        guard let columnName = column["name"] as? String,
              let typeGrouping = column["typegrouping"] as? String else {
            return []
        }

        return menuItemDescriptors(columnName: columnName, typeGrouping: typeGrouping, value: value, isNull: isNull)
    }

    @objc(menuItemDescriptorsWithColumnName:typeGrouping:value:isNull:)
    public static func menuItemDescriptors(columnName: String?, typeGrouping: String?, value: String?, isNull: Bool) -> [SACellFilterMenuItemDescriptor] {
        guard let columnName,
              let typeGrouping else {
            return []
        }

        // Treat an empty-string cell value the same as a NULL cell for menu purposes:
        // SPRuleFilterController's starter detection collapses any expression whose
        // filterValues are all empty strings into a placeholder (see SerIsUntouchedStarterRule
        // at SPRuleFilterController.m:1814-1829), so a value-bearing operator with `[""]`
        // cannot be persisted via the rule editor. Restrict the menu to NULL operators
        // for empty strings so the cell-filter feature never produces non-persistent rules.
        let effectiveIsNull = isNull || (value?.isEmpty ?? false)

        let operators = SACellFilterOperator.operators(for: typeGrouping, cellIsNull: effectiveIsNull)
        guard !operators.isEmpty else {
            return []
        }

        return operators.map { op in
            SACellFilterMenuItemDescriptor(
                title: op.menuTitle,
                columnName: columnName,
                operatorName: op.serializedName,
                values: op.valueCount == 0 ? [] : [value ?? ""],
                isNull: effectiveIsNull
            )
        }
    }
}
