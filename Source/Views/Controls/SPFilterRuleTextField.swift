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
