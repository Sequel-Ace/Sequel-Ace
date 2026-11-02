//
//  SAClaudeInlineNameCommand.swift
//  Sequel Ace
//
//  The keys an inline name field on the Claude connection page takes for itself (a folder's name field on the card
//  grid, the favourite's name in the panel title): Return / Enter save the name, Escape cancels. Handled in the
//  field's `control(_:textView:doCommandBy:)`, so Return never reaches the window's default button (Connect).
//  Pure Foundation: compiles into the Unit Tests target.
//

import Foundation

/// What the connection panel did with a key in its title's name field (the controller's `doCommandBy` hook).
@objc enum SAClaudeNameCommandResult: Int {
    /// Not the title's name field, or not Return / Escape: the controller handles it as before.
    case notHandled
    /// Saved (Return) or cancelled (Escape) the name.
    case handled
    /// Escape undid the only edit of a connection that wasn't being edited: the controller ends its editing state.
    case cancelledToClean
}

enum SAClaudeInlineNameCommand: Equatable {
    case commit
    case cancel

    /// The field editor's command for a key; `nil` for any other command (the field handles it as usual).
    init?(_ selector: Selector) {
        switch NSStringFromSelector(selector) {
        case "insertNewline:", "insertNewlineIgnoringFieldEditor:", "insertLineBreak:":
            self = .commit
        case "cancelOperation:":
            self = .cancel
        default:
            return nil
        }
    }
}
