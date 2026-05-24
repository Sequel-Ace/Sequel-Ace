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
