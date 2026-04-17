//
//  SPFilterRuleTextField.swift
//  Sequel Ace
//
//  Created by Sequel-Ace contributors on 2026.04.17.
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import Cocoa

/// Custom pasteboard type carrying a single cell's display value.
/// Used so the filter rule text field can distinguish a drag coming from
/// our own result grid (and populate itself with just the clicked cell's
/// value) from a generic text drag.
@objc public class SPCellValuePasteboard: NSObject {
    @objc public static let pasteboardTypeRaw: String = "com.sequel-ace.cell-value"
}

/// NSTextField subclass used for the argument input of a filter rule row
/// in the Content tab's rule-editor filter. Accepts drops of a single cell
/// value dragged out of the result table and populates its own string.
///
/// Why: the result-grid drag source also writes the whole row as a SQL
/// INSERT statement / tab-separated values for drops onto Terminal, a
/// text editor, etc. We don't want those long strings to land in the
/// filter field. Registering for our custom type lets us accept only the
/// clicked cell's value.
@objc public class SPFilterRuleTextField: NSTextField {
    private static let cellValueType = NSPasteboard.PasteboardType(SPCellValuePasteboard.pasteboardTypeRaw)

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([Self.cellValueType])
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([Self.cellValueType])
    }

    public override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingPasteboard.availableType(from: [Self.cellValueType]) != nil else {
            return []
        }
        return .copy
    }

    public override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingPasteboard.availableType(from: [Self.cellValueType]) != nil else {
            return []
        }
        return .copy
    }

    public override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        return sender.draggingPasteboard.availableType(from: [Self.cellValueType]) != nil
    }

    public override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let value = sender.draggingPasteboard.string(forType: Self.cellValueType) else {
            return false
        }
        self.stringValue = value
        // Trigger the same action the user would get by pressing Return or
        // ending the edit, so the rule editor picks up the new value and
        // the filter re-runs.
        if let action = self.action {
            NSApp.sendAction(action, to: self.target, from: self)
        }
        return true
    }
}
