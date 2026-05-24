//
//  SACellFilterAction.swift
//  Sequel Ace
//
//  Created by Sequel-Ace contributors on 2026.05.23.
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import Foundation

/// Retains the data needed by one "Filter by Selected Value" menu item
/// and applies it back to the owning table-content controller.
///
/// `NSMenuItem` keeps its target weakly, so each item stores an instance
/// of this wrapper as its represented object. The wrapper keeps only a
/// weak reference to `SPTableContent`, matching menu lifetime rather than
/// extending the document/controller lifetime.
@objcMembers public final class SACellFilterAction: NSObject {
    private weak var tableContent: SPTableContent?

    /// Schema column name to filter, not the visible table-column title.
    public let columnName: String

    /// Serialized rule-filter operator name understood by `SPRuleFilterController`.
    public let operatorName: String

    /// Argument values to pass to the rule-filter serializer.
    ///
    /// Zero-argument operators such as `IS NULL` use an empty array.
    public let values: [String]

    /// Whether the selected cell should be serialized through the NULL path.
    ///
    /// When true, `SPTableContent` ignores `values` and writes
    /// `filterValues: []` so the rule editor restores a zero-argument rule.
    public let isNull: Bool

    /// Creates an action object for one menu item.
    ///
    /// - Parameters:
    ///   - tableContent: Table-content controller that owns the rule filter.
    ///   - columnName: Schema column name to filter.
    ///   - operatorName: Serialized operator name for the rule-filter controller.
    ///   - values: Operator arguments captured from the clicked cell.
    ///   - isNull: Whether the rule should be applied as a SQL NULL comparison.
    public init(tableContent: SPTableContent, columnName: String, operatorName: String, values: [String], isNull: Bool) {
        self.tableContent = tableContent
        self.columnName = columnName
        self.operatorName = operatorName
        self.values = values
        self.isNull = isNull
        super.init()
    }

    /// Applies the captured filter to the owning table-content controller.
    ///
    /// The sender is intentionally unused; AppKit supplies it when invoking
    /// the menu-item target action.
    @objc public func apply(_ sender: Any?) {
        tableContent?.applyCellFilter(forColumn: columnName, operator: operatorName, values: values, isNull: isNull)
    }
}
