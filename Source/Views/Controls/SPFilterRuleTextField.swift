//
//  SPFilterRuleTextField.swift
//  Sequel Ace
//
//  Created by Sequel-Ace contributors on 2026.04.17.
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import Cocoa

/// Holder for the pasteboard-type identifiers used to transfer a
/// result-grid cell onto the Content-tab filter. Exposed as an `@objc`
/// class so the string constants can be referenced from both the
/// Objective-C drag source (`SPTableContent`) and the Swift drop
/// targets (`SPFilterRuleEditor`, `SPRuleFilterDropBox`) without
/// duplicating them.
@objc public class SPCellValuePasteboard: NSObject {
    /// Reverse-DNS identifier of the cell-as-row pasteboard type. The
    /// payload is a property-list dictionary carrying enough context
    /// for a drop target to synthesize a full filter rule – column,
    /// value, and value-kind marker (see the `row*` keys below).
    @objc public static let pasteboardRowTypeRaw: String = "com.sequel-ace.cell-row"

    /// Key for the column name inside the `pasteboardRowTypeRaw` plist.
    @objc public static let rowColumnNameKey: String = "columnName"

    /// Key for the display value inside the `pasteboardRowTypeRaw` plist.
    @objc public static let rowValueKey: String = "value"

    /// Key for the kind-of-value marker inside the `pasteboardRowTypeRaw`
    /// plist. Used so a drop target can map a NULL cell to an `IS NULL`
    /// operator instead of inserting the literal string "NULL".
    @objc public static let rowValueKindKey: String = "valueKind"

    /// Marker value written under `rowValueKindKey` for SQL NULL cells.
    @objc public static let rowValueKindNull: String = "NULL"

    /// Marker value written under `rowValueKindKey` for ordinary string cells.
    @objc public static let rowValueKindString: String = "string"

    /// The plist a drag should publish under `pasteboardRowTypeRaw` for the
    /// cell the drag started on, or `nil` when the drag must not advertise a
    /// cell payload at all.
    ///
    /// Only a positively-resolved cell qualifies: a known column name, and
    /// either a non-nil display value or a cell identified as SQL NULL. A nil
    /// display value on a non-NULL cell means the lookup failed — a stale row
    /// after a reload, an out-of-range storage index — and publishing it anyway
    /// would synthesize a spurious `col = ''` filter on drop.
    ///
    /// `BIT` cells display as `0`/`1` digit strings, but the `bit` filter
    /// definitions compare `CAST('<value>' AS DECIMAL(65,30))`, so their value is published in
    /// decimal form (`00000101` becomes `5`); a `BIT` display value that is not
    /// a bit string does not count as a resolved cell.
    ///
    /// - Parameters:
    ///   - columnName: Schema column name of the dragged cell.
    ///   - value: Display value of the cell.
    ///   - isNull: Whether the cell is SQL NULL.
    ///   - typeGrouping: Sequel Ace type grouping of the column, if known.
    /// - Returns: The payload, or `nil` when the drag must not advertise one.
    @objc(rowPayloadForColumnName:value:isNull:typeGrouping:)
    public static func rowPayload(columnName: String?, value: String?, isNull: Bool, typeGrouping: String? = nil) -> [String: String]? {
        guard let columnName, !columnName.isEmpty else { return nil }
        guard isNull || value != nil else { return nil }

        var payloadValue = value ?? ""
        if !isNull, SPFieldTypeClassifier.isBitField(fieldTypeGroup: typeGrouping, fieldType: nil) {
            guard let decimal = SPFieldTypeClassifier.decimalString(forBitString: payloadValue) else { return nil }
            payloadValue = decimal
        }

        return [
            rowColumnNameKey: columnName,
            rowValueKey: payloadValue,
            rowValueKindKey: isNull ? rowValueKindNull : rowValueKindString,
        ]
    }
}

/// `NSTextField` subclass used for the argument input of a rule row.
///
/// The subclass has no per-field drag-and-drop behaviour – drop handling
/// is done at the rule-editor level by `SPFilterRuleEditor` so dropping
/// a cell replaces the whole rule rather than just the argument value.
///
/// It does keep its height at `SAClaudeFilterChrome.controlHeight`: AppKit's
/// rule editor remembers the size a row view had when the delegate returned it
/// and restores that size on every layout (so a later resize cannot stick),
/// and the Claude look needs these fields taller than a text field's own
/// height. The row centres the field vertically itself.
@objc public class SPFilterRuleTextField: NSTextField {
    override public class var cellClass: AnyClass? {
        get { SPFilterRuleTextFieldCell.self }
        set { super.cellClass = newValue }
    }

    override public init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override public var frame: NSRect {
        get { super.frame }
        set {
            var frame = newValue
            frame.size.height = SAClaudeFilterChrome.controlHeight
            super.frame = frame
        }
    }

    override public func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(NSSize(width: newSize.width, height: SAClaudeFilterChrome.controlHeight))
    }
}

/// The cell of a rule row's argument field. While the field is drawn without a bezel (the Claude look
/// draws its own rounded outline) its text sits inset from the edge and centred vertically; with a
/// bezel it is AppKit's own placement.
final class SPFilterRuleTextFieldCell: NSTextFieldCell {
    /// Space between the field's edge and its text.
    private static let textInset: CGFloat = 7

    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        var drawingRect = super.drawingRect(forBounds: rect)
        guard !isBezeled else { return drawingRect }
        drawingRect = drawingRect.insetBy(dx: Self.textInset, dy: 0)
        let lineHeight = ceil(NSLayoutManager().defaultLineHeight(for: font ?? .systemFont(ofSize: NSFont.smallSystemFontSize)))
        let spare = drawingRect.height - lineHeight
        if spare > 0 {
            drawingRect.origin.y += (spare / 2).rounded(.down)
            drawingRect.size.height = lineHeight
        }
        return drawingRect
    }

    // AppKit places the field editor exactly where it is told to, not by -drawingRectForBounds:.
    override func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, event: NSEvent?) {
        super.edit(withFrame: drawingRect(forBounds: rect), in: controlView, editor: textObj, delegate: delegate, event: event)
    }

    override func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, start selStart: Int, length selLength: Int) {
        super.select(withFrame: drawingRect(forBounds: rect), in: controlView, editor: textObj, delegate: delegate, start: selStart, length: selLength)
    }
}
