//
//  SPFilterRuleEditor.swift
//  Sequel Ace
//
//  Created by Sequel-Ace contributors on 2026.04.19.
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import Cocoa

/// Protocol the rule editor and the drop box use to ask their controller
/// to mutate the current filter set from a dropped cell payload.
/// `SPRuleFilterController` adopts this via its existing Objective-C
/// methods – there's no bespoke Swift surface.
@objc public protocol SPFilterRuleEditorDropHandler: AnyObject {
    /// Append a fully-populated rule to the current filter set without
    /// running the filter. The user presses Apply Filters (or Return in
    /// any argument field) to actually query.
    ///
    /// - Returns: `true` if a rule was appended.
    @objc(appendFilterForColumn:value:isNull:)
    func appendFilter(forColumn columnName: String, value: String?, isNull: Bool) -> Bool

    /// Replace the rule at `row` (0-indexed top-level row in the rule
    /// editor) with a fully-populated rule derived from the drop.
    ///
    /// - Returns: `true` if the rule was replaced.
    @objc(replaceFilterAtRow:forColumn:value:isNull:)
    func replaceFilter(at row: Int, forColumn columnName: String, value: String?, isNull: Bool) -> Bool

    /// Insert an empty filter row (same as clicking the "+" button).
    /// Used when the user clicks the drop box instead of dropping onto it.
    @objc(addEmptyFilterRow)
    func addEmptyFilterRow()
}

/// `NSRuleEditor` subclass that extends the content-tab filter with
/// drag-and-drop support for the
/// `SPCellValuePasteboard.pasteboardRowTypeRaw` payload. Dropping a
/// result-grid cell onto an existing rule replaces that entire rule
/// with a new one derived from the dropped cell (column + default
/// operator + value). Appending fresh rules is handled separately by
/// `SPRuleFilterDropBox`, so the user can choose between "replace this
/// rule" and "add a new rule" purely by target.
@objc public class SPFilterRuleEditor: NSRuleEditor {
    private static let rowDropType = NSPasteboard.PasteboardType(SPCellValuePasteboard.pasteboardRowTypeRaw)

    /// Thin accent-coloured rectangle drawn around the row the drag is
    /// hovering over. Added the first time a drag enters, moved on
    /// every `draggingUpdated`, and torn down on exit / drop so we pay
    /// no drawing cost outside an active drag.
    private var highlightOverlay: SPFilterRuleEditorHighlight?

    override public init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([Self.rowDropType])
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([Self.rowDropType])
    }

    override public func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        return dragOperation(for: sender)
    }

    override public func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        return dragOperation(for: sender)
    }

    override public func draggingExited(_ sender: NSDraggingInfo?) {
        clearHighlight()
    }

    override public func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        return row(for: sender) != nil
    }

    override public func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer { clearHighlight() }
        guard
            let row = row(for: sender),
            let plist = sender.draggingPasteboard.propertyList(forType: Self.rowDropType) as? [String: Any],
            let columnName = plist[SPCellValuePasteboard.rowColumnNameKey] as? String,
            !columnName.isEmpty,
            let handler = self.delegate as? SPFilterRuleEditorDropHandler
        else {
            return false
        }
        let value = plist[SPCellValuePasteboard.rowValueKey] as? String
        let isNull = (plist[SPCellValuePasteboard.rowValueKindKey] as? String) == SPCellValuePasteboard.rowValueKindNull
        return handler.replaceFilter(at: row, forColumn: columnName, value: value, isNull: isNull)
    }

    override public func concludeDragOperation(_ sender: NSDraggingInfo?) {
        clearHighlight()
    }

    /// Returns a copy drag operation only when the drop lies over an
    /// existing top-level rule – that's the only valid target for the
    /// rule editor itself (the drop box handles the append case).
    /// Side-effect: updates the highlight overlay so the user sees which
    /// rule is about to be replaced.
    private func dragOperation(for sender: NSDraggingInfo) -> NSDragOperation {
        guard let row = row(for: sender) else {
            clearHighlight()
            return []
        }
        showHighlight(forRow: row)
        return .copy
    }

    /// Resolve the dragging point to a top-level row index, or `nil`
    /// when the cursor is outside the editor, no rows are dropped on,
    /// or the pasteboard doesn't carry our custom type. Row frames are
    /// computed from `rowHeight` rather than by hit-testing display
    /// views – NSRuleEditor can reuse the same display view across
    /// rows that share a criterion node, so a view-frame union is
    /// unreliable.
    private func row(for sender: NSDraggingInfo) -> Int? {
        guard sender.draggingPasteboard.availableType(from: [Self.rowDropType]) != nil else { return nil }
        guard self.delegate is SPFilterRuleEditorDropHandler else { return nil }
        let point = convert(sender.draggingLocation, from: nil)
        let rowH = self.rowHeight
        guard rowH > 0 else { return nil }

        // NSRuleEditor lays row 0 out at the top. When the view is
        // flipped, y grows downward so row index = floor(y / rowHeight);
        // otherwise row 0 starts at bounds.maxY and we invert.
        let y = isFlipped ? point.y : (bounds.maxY - point.y)
        let index = Int(floor(y / rowH))
        guard index >= 0, index < numberOfRows else { return nil }
        // Drop target must be a top-level simple rule: a compound
        // (AND / OR) row can't be "replaced" with a single expression,
        // and a nested subrow would require tree-walking the serialized
        // filter to map the visible index to a child index. Both cases
        // are rejected; the user can use the drop box to append a new
        // rule instead.
        guard parentRow(forRow: index) == -1 else { return nil }
        guard rowType(forRow: index) == .simple else { return nil }
        return index
    }

    private func showHighlight(forRow row: Int) {
        let rowH = self.rowHeight
        guard rowH > 0 else { return }
        let y: CGFloat = isFlipped
            ? CGFloat(row) * rowH
            : bounds.maxY - CGFloat(row + 1) * rowH
        // A 2pt inset keeps the border inside the row's own cell, so
        // it never bleeds into neighbouring rows.
        let frame = NSRect(x: 0, y: y, width: bounds.width, height: rowH).insetBy(dx: 2, dy: 2)

        if let overlay = highlightOverlay {
            overlay.frame = frame
        } else {
            let overlay = SPFilterRuleEditorHighlight(frame: frame)
            // Frontmost subview so the border is drawn on top of the
            // row's popup / checkbox / text field; the overlay is only
            // a stroke, so the cells remain fully visible – and it
            // ignores hit-testing, so they stay interactive too.
            addSubview(overlay, positioned: .above, relativeTo: subviews.last)
            highlightOverlay = overlay
        }
    }

    private func clearHighlight() {
        highlightOverlay?.removeFromSuperview()
        highlightOverlay = nil
    }
}

/// Thin rounded border drawn around the rule row a drag is hovering
/// over. Kept as a border only – never a filled tile – so it can't be
/// mistaken for, or obscured by, any tinting NSRuleEditor applies to
/// rows on drag-over. Hit-testing is disabled so the row's popups,
/// checkbox, and text field remain interactive through the overlay.
private final class SPFilterRuleEditorHighlight: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil // transparent to mouse events
    }
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 4, yRadius: 4)
        path.lineWidth = 2
        NSColor.controlAccentColor.setStroke()
        path.stroke()
    }
}
