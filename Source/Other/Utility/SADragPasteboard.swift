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

    /// Marker carrying the row index of one row of a *drag-out* selection —
    /// result rows, content rows, navigator items. Nothing reads it for its
    /// value; it exists so each dragged row can be its own pasteboard item
    /// (which is what gives the drag its per-row image) without any of them
    /// contributing to the payload the receiver reads. See `attach(…)`.
    @objc static let dragRowType = "com.sequel-ace.pasteboard.drag-row"

    /// Keyed-archived array of schema paths dragged out of the navigator.
    /// Read by SPTextView. Renamed from the legacy non-UTI
    /// "SPNavigatorPasteboardDragType" — see the UTI note above.
    @objc static let navigatorSchemaPathsType = "com.sequel-ace.pasteboard.navigator-schema-paths"

    /// `CREATE TABLE …` statement for a single navigator table.
    /// Read by SPTablesList. Renamed from the legacy non-UTI
    /// "SPNavigatorTableDataPasteboardDragType".
    @objc static let navigatorTableDataType = "com.sequel-ace.pasteboard.navigator-table-data"

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

    // MARK: - Whole-drag payloads

    // The drag-*out* views (query results, table content, navigator) wrote one
    // combined blob for the whole selection under the deprecated whole-drag
    // writer, and that blob leaves the app: it lands in TextEdit, the rule
    // filter, the tables list, the query editor. Its shape therefore cannot
    // change, only where it is written from.
    //
    // The per-row/per-item writer cannot express it, so the drag is built in two
    // steps: `dragRowItem(row:)` gives every dragged row a marker-only item (so
    // the drag still gets its per-row image), then `attach…` puts the whole-drag
    // payload on the *first* of those items once AppKit hands us the session.
    //
    // ⚠️ The marker-only part is load-bearing, and the reason is not obvious.
    // `NSPasteboard` does not read these types alike:
    //
    //   - `.string` is **concatenated across every item, joined with "\n"**.
    //   - `.tabularText`, custom types, and property lists come from the **first
    //     item only**.
    //
    // So if the per-row items each carried their own `.string`, a receiver would
    // get the first item's whole-drag blob followed by every row's fragment
    // appended after it. Leaving them marker-only keeps `-stringForType:`
    // byte-identical to what the deprecated writer produced.

    /// A marker-only pasteboard item standing in for one row of a drag-out
    /// selection. Carries no payload — see the note above.
    @objc(dragRowItemForRow:)
    static func dragRowItem(row: Int) -> NSPasteboardItem {
        item(row: row, forType: dragRowType)
    }

    /// The item a whole-drag payload belongs on: the first one, which is the one
    /// every non-`.string` read resolves to.
    private static func payloadItem(on pasteboard: NSPasteboard) -> NSPasteboardItem? {
        pasteboard.pasteboardItems?.first
    }

    /// Attaches the selection's combined text to `pasteboard` under both the
    /// plain-string and tabular-text types, matching the pair the deprecated
    /// writers declared.
    ///
    /// Returns false when the drag carries no items — an empty selection, or a
    /// writer that refused every row.
    @discardableResult
    @objc(attachDragString:toPasteboard:)
    static func attach(dragString string: String, to pasteboard: NSPasteboard) -> Bool {
        guard let item = payloadItem(on: pasteboard) else { return false }
        let asString = item.setString(string, forType: .string)
        let asTabular = item.setString(string, forType: .tabularText)
        return asString && asTabular
    }

    /// Attaches `string` under a single `type`.
    @discardableResult
    @objc(attachString:forType:toPasteboard:)
    static func attach(string: String, forType type: String, to pasteboard: NSPasteboard) -> Bool {
        guard let item = payloadItem(on: pasteboard) else { return false }
        let stored = item.setString(string, forType: NSPasteboard.PasteboardType(type))
        assert(stored, "'\(type)' was rejected by NSPasteboardItem; pasteboard types must be valid UTIs")
        return stored
    }

    /// Attaches a property list under `type` — the rule-filter cell payload.
    @discardableResult
    @objc(attachPropertyList:forType:toPasteboard:)
    static func attach(propertyList: Any, forType type: String, to pasteboard: NSPasteboard) -> Bool {
        guard let item = payloadItem(on: pasteboard) else { return false }
        let stored = item.setPropertyList(propertyList, forType: NSPasteboard.PasteboardType(type))
        assert(stored, "'\(type)' was rejected by NSPasteboardItem; pasteboard types must be valid UTIs")
        return stored
    }

    /// Attaches raw data under `type` — the navigator's keyed-archived paths.
    @discardableResult
    @objc(attachData:forType:toPasteboard:)
    static func attach(data: Data, forType type: String, to pasteboard: NSPasteboard) -> Bool {
        guard let item = payloadItem(on: pasteboard) else { return false }
        let stored = item.setData(data, forType: NSPasteboard.PasteboardType(type))
        assert(stored, "'\(type)' was rejected by NSPasteboardItem; pasteboard types must be valid UTIs")
        return stored
    }

    // MARK: - Payload field resolution

    // The two pure lookups the drag-out sites needed, lifted out of the
    // delegate methods so they can be tested without an outline view or a
    // live result set.

    /// A navigator schema path with its leading connection ID stripped — the
    /// part before and including the first delimiter.
    ///
    /// Replaces `stringByReplacingOccurrencesOfRegex:@"^.*?<delim>"`. Splitting
    /// on the first occurrence rather than running the regex also drops the
    /// pattern's newline caveat: `.` does not match newlines in ICU, so a key
    /// containing one before its delimiter used to come back unstripped.
    /// Returns the key unchanged when it holds no delimiter, as the regex did.
    @objc(schemaPathFromKey:delimiter:)
    static func schemaPath(fromKey key: String, delimiter: String) -> String {
        guard !delimiter.isEmpty, let range = key.range(of: delimiter) else { return key }
        return String(key[range.upperBound...])
    }

    /// Whether a navigator schema path contributes anything to the drag's text.
    ///
    /// The whole-drag writer joined paths with
    /// `-componentsJoinedByPeriodAndBacktickQuotedAndIgnoreFirst`, which drops
    /// the first component — so a single-component path (a connection, or a
    /// database once its connection ID is stripped) produced an empty string,
    /// and a drag containing only those was refused outright by the trailing
    /// `if(![dragString length]) return NO;`.
    ///
    /// The per-item writer has to reconstruct that refusal, or dragging a
    /// connection or database on its own starts a drag that drops the internal
    /// connection key into the query editor.
    @objc(carriesDragTextForSchemaPath:delimiter:)
    static func carriesDragText(schemaPath: String, delimiter: String) -> Bool {
        guard !delimiter.isEmpty else { return false }
        return schemaPath.components(separatedBy: delimiter).count >= 2
    }

    /// The schema column name behind a clicked table column, or nil when the
    /// click cannot be resolved to one.
    ///
    /// Visible columns carry their storage index as the column identifier (the
    /// mapping SPCopyTable uses), so this is a two-step lookup with a bounds
    /// check at each step. `identifiers` are the view's column identifiers in
    /// display order; `columnNames` are the storage-ordered column names.
    ///
    /// Both arrive as untyped ObjC arrays because the call sites build them
    /// with `-valueForKey:`, which substitutes `NSNull` for anything missing —
    /// a `[String]` parameter would trap on that during bridging rather than
    /// resolve to "no column", which is the honest answer. Non-string entries
    /// are therefore treated as absent.
    @objc(columnNameForClickedColumn:identifiers:columnNames:)
    static func columnName(forClickedColumn column: Int,
                           identifiers: [Any],
                           columnNames: [Any]) -> String? {
        guard column >= 0, column < identifiers.count,
              let identifier = identifiers[column] as? String else { return nil }

        // NSString's -integerValue, not Int(_:), to keep the ObjC leniency the
        // identifiers were read with: it parses a leading integer and yields 0
        // rather than failing on anything unexpected.
        let storageIndex = (identifier as NSString).integerValue
        guard storageIndex >= 0, storageIndex < columnNames.count else { return nil }

        return columnNames[storageIndex] as? String
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
