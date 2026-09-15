//
//  SACellFilterColumnIdentifier.swift
//  Sequel Ace
//
//  Created by Sequel-Ace contributors on 2026.05.23.
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import AppKit

/// Normalizes `NSTableColumn.identifier` values into storage-column indexes.
///
/// Table-content columns use numeric identifiers that map visible columns back
/// to the backing `SPDataStorage` column. AppKit allows arbitrary identifier
/// objects, so the cell-filter context-menu path validates the shape before
/// treating an identifier as an array index.
@objcMembers public final class SACellFilterColumnIdentifier: NSObject {

    /// Parses a table-column identifier into a storage index.
    ///
    /// Accepts `NSUserInterfaceItemIdentifier`, `String`, and `NSNumber`
    /// values that contain only decimal digits. Non-integer identifiers are
    /// rejected instead of being coerced with Objective-C's permissive
    /// `integerValue`, which would turn values such as `"abc"` into `0`.
    ///
    /// - Parameter identifier: Identifier object read from an `NSTableColumn`.
    /// - Returns: The storage index, or `nil` when the identifier is not a pure integer.
    @objc(storageIndexFromIdentifier:)
    public static func storageIndex(from identifier: Any?) -> NSNumber? {
        guard let rawValue = rawValue(from: identifier),
              rawValue.isNotEmpty,
              rawValue.allSatisfy(\.isNumber),
              let index = Int(rawValue) else {
            return nil
        }

        return NSNumber(value: index)
    }

    /// Resolves the storage index of the column shown at a visible position.
    ///
    /// Result tables let the user reorder columns by dragging, and the column
    /// filter hides columns, so a visible position such as `editedColumn` is
    /// not a storage index. Using one as the other makes editing checks read
    /// the definition or the data of a different column.
    ///
    /// - Parameters:
    ///   - visibleColumn: The column position as reported by the table view.
    ///   - tableView: The table view the position belongs to.
    /// - Returns: The storage index, or `-1` when the position is out of range
    ///   or the column identifier is not a storage index.
    @objc(storageIndexForVisibleColumn:inTableView:)
    public static func storageIndex(forVisibleColumn visibleColumn: Int, in tableView: NSTableView) -> Int {
        let tableColumns = tableView.tableColumns
        guard visibleColumn >= 0,
              visibleColumn < tableColumns.count,
              let index = storageIndex(from: tableColumns[visibleColumn].identifier) else {
            return -1
        }
        return index.intValue
    }

    private static func rawValue(from identifier: Any?) -> String? {
        switch identifier {
        case let identifier as NSUserInterfaceItemIdentifier:
            return identifier.rawValue
        case let identifier as String:
            return identifier
        case let identifier as NSNumber:
            return identifier.stringValue
        default:
            return identifier.map { String(describing: $0) }
        }
    }
}
