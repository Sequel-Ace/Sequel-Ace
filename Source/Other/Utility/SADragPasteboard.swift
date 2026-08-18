//
//  SADragPasteboard.swift
//  Sequel Ace
//
//  Created as part of the deprecated drag-API migration.
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import AppKit

/// Pasteboard plumbing and refusal rules for the table views migrated off the
/// deprecated `-tableView:writeRowsWithIndexes:toPasteboard:`.
///
/// Its replacement, `-tableView:pasteboardWriterForRow:`, is asked about one row
/// at a time and cannot see the whole drag, so the "refuse this entire drag"
/// decisions the old API expressed by returning NO have to be reconstructed from
/// the row plus the selection. That reconstruction is the part worth testing, so
/// it lives here rather than in the delegate methods.
@objc final class SADragPasteboard: NSObject {

    // MARK: - Types

    // ⚠️ These must stay UTI-conformant (reverse-DNS). `NSPasteboardItem` and
    // `NSPasteboardWriting` both refuse a type that isn't a valid UTI — AppKit
    // logs "'X' is not a valid UTI string. Cannot set data for an invalid UTI."
    // and the item ends up carrying nothing, while `writeObjects:` still returns
    // YES. The deprecated `-declareTypes:`/`-setString:forType:` path accepted
    // the app's legacy names ("SequelProPasteboard", "SSLCipherPboardType"),
    // which is why these drags needed new type names when they were migrated.

    /// Row index of a table row being reordered within its own table.
    @objc static let tableRowType = "com.sequel-ace.pasteboard.table-row"

    /// Name of an SSL cipher being reordered in the network preference pane.
    @objc static let sslCipherType = "com.sequel-ace.pasteboard.ssl-cipher"

    // MARK: - Writing

    /// A pasteboard item carrying `string` under `type`.
    @objc(itemWithString:forType:)
    static func item(string: String, forType type: String) -> NSPasteboardItem {
        let item = NSPasteboardItem()
        let stored = item.setString(string, forType: NSPasteboard.PasteboardType(type))

        // Rather than let a non-UTI type produce an empty item and a drag that
        // silently carries nothing.
        assert(stored, "'\(type)' was rejected by NSPasteboardItem; pasteboard types must be valid UTIs")

        return item
    }

    /// A pasteboard item carrying `row` as its decimal string under `type`.
    @objc(itemWithRow:forType:)
    static func item(row: Int, forType type: String) -> NSPasteboardItem {
        item(string: String(row), forType: type)
    }

    // MARK: - Reading

    /// The strings stored under `type` by each item on `pasteboard`, in item
    /// order — which is row order, since the writer is asked per row.
    ///
    /// Replaces reading one archived collection written for the whole drag.
    @objc(stringsFromPasteboard:forType:)
    static func strings(from pasteboard: NSPasteboard, forType type: String) -> [String] {
        let pasteboardType = NSPasteboard.PasteboardType(type)
        return (pasteboard.pasteboardItems ?? []).compactMap { $0.string(forType: pasteboardType) }
    }

    // MARK: - Refusal rules

    /// True when a drag beginning at `row` must be refused because it would carry
    /// more than one row.
    ///
    /// For drop handlers that reorder exactly one row: the old delegate method
    /// refused such a drag outright, and allowing it would silently move only the
    /// first row. A row that isn't selected is dragged on its own, so it is fine.
    @objc(refusesMultiRowDragForRow:selectedRows:)
    static func refusesMultiRowDrag(row: Int, selectedRows: IndexSet) -> Bool {
        selectedRows.contains(row) && selectedRows.count > 1
    }

    /// True when a drag beginning at `row` must be refused because it would carry
    /// `excludedRow` — a row that cannot be reordered, such as the SSL cipher
    /// list's "use system defaults" marker.
    ///
    /// Refuses both the excluded row itself and every row of a selection holding
    /// it, matching the old whole-drag refusal. `NSNotFound` means "no such row".
    @objc(refusesDragForRow:selectedRows:excludedRow:)
    static func refusesDrag(row: Int, selectedRows: IndexSet, excludedRow: Int) -> Bool {
        guard excludedRow != NSNotFound else { return false }
        if row == excludedRow { return true }
        return selectedRows.contains(row) && selectedRows.contains(excludedRow)
    }
}
