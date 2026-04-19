//
//  SPFilterRuleTextField.swift
//  Sequel Ace
//
//  Created by Sequel-Ace contributors on 2026.04.17.
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import Cocoa

/// Holder for the custom pasteboard-type identifier used to transfer a
/// single result-grid cell value onto a filter-rule input. Exists as an
/// `@objc` class so the raw identifier string can be referenced from
/// Objective-C (the drag source) and Swift (the drop target) without
/// duplicating the constant.
@objc public class SPCellValuePasteboard: NSObject {
    /// Reverse-DNS identifier of the custom pasteboard type.
    @objc public static let pasteboardTypeRaw: String = "com.sequel-ace.cell-value"
}

/// `NSTextField` subclass used for the argument input of a filter rule
/// row in the Content tab's rule-editor filter. Accepts drops of a
/// single cell value dragged out of the result table and populates its
/// own string.
///
/// Why: the result-grid drag source also writes the whole row as a SQL
/// `INSERT` statement / tab-separated values for drops onto Terminal, a
/// text editor, etc. We don't want those long strings to land in the
/// filter field. Registering for our custom type lets us accept only
/// the clicked cell's value.
@objc public class SPFilterRuleTextField: NSTextField {
    private static let cellValueType = NSPasteboard.PasteboardType(SPCellValuePasteboard.pasteboardTypeRaw)

    /// Programmatic initializer used by the rule-editor controller that
    /// allocates these fields at runtime. Registers for the custom
    /// pasteboard type so drops route through the view's drag handlers.
    override public init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([Self.cellValueType])
    }

    /// Nib-loading initializer. Retained for parity with
    /// `NSTextField`'s designated initializer surface – the rule editor
    /// currently instantiates this class programmatically.
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([Self.cellValueType])
    }

    /// Accept the drag only when the custom cell-value type is on the
    /// pasteboard; otherwise the user sees the default no-drop cursor
    /// and any unrelated string/URL payload falls through to AppKit.
    override public func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingPasteboard.availableType(from: [Self.cellValueType]) != nil else {
            return []
        }
        return .copy
    }

    /// Keep the drag feedback consistent while the pointer hovers; the
    /// decision is re-evaluated on every movement in case AppKit adjusts
    /// pasteboard contents during the session.
    override public func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingPasteboard.availableType(from: [Self.cellValueType]) != nil else {
            return []
        }
        return .copy
    }

    /// Gate the real drop on the custom type being present so
    /// `performDragOperation(_:)` doesn't run for accidental text drags.
    override public func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        return sender.draggingPasteboard.availableType(from: [Self.cellValueType]) != nil
    }

    /// Read the custom payload and assign it to `stringValue`. The filter
    /// is not auto-applied; the user hits Return (or clicks Apply
    /// Filters) to run the query, matching the flow of typing a value
    /// into the field directly.
    override public func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let value = sender.draggingPasteboard.string(forType: Self.cellValueType) else {
            return false
        }
        self.stringValue = value
        return true
    }
}
