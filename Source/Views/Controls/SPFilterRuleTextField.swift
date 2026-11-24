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
/// The subclass currently has no per-field behaviour – drag-and-drop is
/// handled at the rule-editor level by `SPFilterRuleEditor` so dropping
/// a cell replaces the whole rule rather than just the argument value.
/// The type is kept as a seam for future per-field customisation
/// without having to re-plumb `SPRuleFilterController`'s text-field
/// instantiation.
@objc public class SPFilterRuleTextField: NSTextField {
    override public init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
}

/// A single display value lets NSRuleEditor give the input the rest of the row.
@objcMembers public final class SAFilterListInput: NSView {
    public let field: NSTextField
    private let checkbox: NSButton
    public var checked: Bool { checkbox.state == .on }

    @objc(initWithField:checked:target:action:)
    public init(field: NSTextField, checked: Bool, target: AnyObject, action: Selector) {
        self.field = field
        let title = NSLocalizedString("Quote each value", comment: "Content filter checkbox for a comma-separated list of text values")
        checkbox = NSButton(checkboxWithTitle: title, target: target, action: action)
        super.init(frame: field.frame)
        setAccessibilityRole(.group)
        setAccessibilityChildren([field, checkbox])
        checkbox.controlSize = .small
        checkbox.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        checkbox.state = checked ? .on : .off
        for view in [field, checkbox] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
            view.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true
        }
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: leadingAnchor),
            checkbox.leadingAnchor.constraint(equalTo: field.trailingAnchor, constant: 6),
            // Leave space before the rule editor’s remove/add buttons.
            checkbox.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            checkbox.widthAnchor.constraint(equalToConstant: ceil(checkbox.fittingSize.width) + 2),
        ])
    }

    public required init?(coder: NSCoder) { nil }

    public static func field(forDisplayValue value: Any?) -> NSTextField? {
        (value as? SAFilterListInput)?.field ?? value as? NSTextField
    }

    public static func displayValue(forControl control: NSControl) -> NSView {
        control.superview as? SAFilterListInput ?? control
    }
}
