//
//  SAFavoritesListKeys.swift
//  Sequel Ace
//
//  Key handling decisions for the connection screen's favorites list.
//  AppKit only (no project ObjC types) so the Unit Tests target can compile it.
//

import AppKit

/// What `-[SPFavoritesOutlineView keyDown:]` should do with a Return/Enter key event.
@objc enum SAFavoritesReturnKeyAction: Int {
    /// Not handled here; carry on with the normal key handling.
    case passThrough
    /// Connect to the selected favorite (same as a double-click).
    case connect
    /// Swallow the event.
    case ignore
}

@objc final class SAFavoritesListKeys: NSObject {

    /// Return/Enter in the list: connect on a single selection, ignore an auto-repeat of a press
    /// (it would follow a rename that the same press just committed), anything else passes through.
    @objc static func returnKeyAction(keyCode: UInt16, isARepeat: Bool, selectedRowCount: Int) -> SAFavoritesReturnKeyAction {
        // 36 = Return, 76 = keypad Enter
        guard keyCode == 36 || keyCode == 76, selectedRowCount == 1 else { return .passThrough }
        return isARepeat ? .ignore : .connect
    }

    /// Field-editor commands while a row's name is being edited: Escape (cancelOperation:) aborts the edit,
    /// keeps the old name and leaves focus on the list. Returns whether it handled the command.
    static func handleEditingCommand(_ selector: Selector, in control: NSControl) -> Bool {
        guard selector == #selector(NSResponder.cancelOperation(_:)) else { return false }
        control.abortEditing()
        control.window?.makeFirstResponder(control)
        return true
    }
}
