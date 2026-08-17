//
//  SACellFilterAction.swift
//  Sequel Ace
//
//  Created by Sequel-Ace contributors on 2026.05.23.
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import AppKit

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

/// Adds value-oriented copy actions to Content and Custom Query result tables.
@objcMembers public final class SACellValueCopyCoordinator: NSObject {
    private static let rawMenuTag = 1_945_002
    private static let sqlMenuTag = 1_945_003

    @objc(appendItemsToMenu:event:table:tableStorage:columnDefinitions:connection:)
    public static func appendItems(
        to menu: NSMenu,
        event: NSEvent,
        table: SPCopyTable,
        tableStorage: SPDataStorage,
        columnDefinitions: [NSDictionary]?,
        connection: SPMySQLConnection?
    ) {
        removeItems(from: menu)
        if let customQuery = table.delegate as? SPCustomQuery, customQuery.isWorking {
            return
        }

        let point = table.convert(event.locationInWindow, from: nil)
        let clickedRow = table.row(at: point)
        let visibleColumn = table.column(at: point)
        guard clickedRow >= 0, clickedRow < table.numberOfRows, visibleColumn >= 0 else { return }

        let selectedRows = SACellValueCopyMenuBuilder.selectedRows(
            current: table.selectedRowIndexes,
            clickedRow: clickedRow
        )
        if selectedRows != table.selectedRowIndexes {
            table.selectRowIndexes(selectedRows, byExtendingSelection: false)
            table.window?.makeFirstResponder(table)
        }

        guard let tableColumn = table.tableColumns[safe: visibleColumn],
              let storageColumnNumber = SACellFilterColumnIdentifier.storageIndex(from: tableColumn.identifier) else {
            return
        }
        let storageColumn = storageColumnNumber.intValue
        guard storageColumn >= 0,
              UInt(storageColumn) < tableStorage.columnCount() else {
            return
        }

        let columnDefinition = columnDefinitions?[safe: storageColumn]
        var rawValues: [String] = []
        var sqlLiterals: [String]? = columnDefinition != nil && connection != nil ? [] : nil
        for row in selectedRows {
            guard UInt(row) < tableStorage.count(),
                  let displayValue = table.displayString(forRow: row, column: visibleColumn) else {
                return
            }
            rawValues.append(displayValue)

            if sqlLiterals != nil,
               let columnDefinition,
               let connection {
                guard let value = tableStorage.cellData(atRow: UInt(row), column: UInt(storageColumn)),
                      !(value is SPNotLoaded),
                      let literal = sqlLiteral(value: value, columnDefinition: columnDefinition, connection: connection) else {
                    sqlLiterals = nil
                    continue
                }
                sqlLiterals?.append(literal)
            }
        }

        let descriptors = SACellValueCopyMenuBuilder.menuItemDescriptors(
            columnName: columnDefinition?["name"] as? String ?? tableColumn.headerCell.stringValue,
            rawValues: rawValues,
            sqlLiterals: sqlLiterals
        )
        guard !descriptors.isEmpty else { return }

        var insertionIndex = menu.indexOfItem(withTag: SPEditMenuCopyAsSQLNoAutoInc)
        if insertionIndex == -1 { insertionIndex = menu.numberOfItems - 1 }
        insertionIndex += 1
        for descriptor in descriptors {
            let action = SACellValueCopyAction(descriptor: descriptor)
            let item = NSMenuItem(title: descriptor.title, action: #selector(SACellValueCopyAction.copy(_:)), keyEquivalent: "")
            item.target = action
            item.representedObject = action
            item.tag = descriptor.isSQL ? sqlMenuTag : rawMenuTag
            menu.insertItem(item, at: insertionIndex)
            insertionIndex += 1
        }
    }

    private static func sqlLiteral(
        value: Any,
        columnDefinition: NSDictionary,
        connection: SPMySQLConnection
    ) -> String? {
        let normalizedValue: Any
        if let geometry = value as? SPMySQLGeometryData {
            normalizedValue = geometry.data()
        } else {
            normalizedValue = value
        }

        return SACellValueCopyMenuBuilder.sqlLiteral(
            value: normalizedValue,
            typeGrouping: columnDefinition["typegrouping"] as? String,
            fieldType: columnDefinition["type"] as? String,
            quoteString: connection.escapeAndQuoteString,
            quoteData: connection.escapeAndQuoteData
        )
    }

    private static func removeItems(from menu: NSMenu) {
        if let firstItem = menu.item(withTag: rawMenuTag) {
            menu.removeItem(firstItem)
        }
        if let sqlItem = menu.item(withTag: sqlMenuTag) {
            menu.removeItem(sqlItem)
        }
    }
}
