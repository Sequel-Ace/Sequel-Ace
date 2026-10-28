//
//  SASidebarBottomBar.swift
//  Sequel Ace
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import AppKit

/// Gives the main window sidebar's bottom bar the look of the bottom bars in
/// Finder, Mail and Xcode: borderless buttons that show only an SF Symbol in
/// its default size.
///
/// Only the look changes. Targets, actions, menus and the enabled state stay
/// as the nib defines them, and each button keeps its tooltip, which also
/// becomes its accessibility description.
@objc(SASidebarBottomBar) final class SASidebarBottomBar: NSObject {

    /// Styles the bar's controls. Any of them may be nil.
    ///
    /// - Parameters:
    ///   - addButton: Adds a table (`plus`).
    ///   - actionsButton: The pull-down menu of table actions (`ellipsis.circle`, no arrow).
    ///   - reloadButton: Refreshes the tables list (`arrow.clockwise`).
    ///   - infoToggle: Shows or hides the Table information pane. SPSplitView sets
    ///     its state to on while the pane is collapsed, so it shows `info.circle.fill`
    ///     while the pane is visible and `info.circle` while it is collapsed.
    ///   - dragHandle: The view that extends the divider's drag area. It loses the
    ///     legacy grip image but stays in place.
    @objc static func style(addButton: NSButton?,
                            actionsButton: NSPopUpButton?,
                            reloadButton: NSButton?,
                            infoToggle: NSButton?,
                            dragHandle: NSView?) {
        if let addButton {
            makeBorderless(addButton, symbol: "plus")
        }

        if let reloadButton {
            makeBorderless(reloadButton, symbol: "arrow.clockwise")
        }

        if let infoToggle {
            // The type comes first; the look and images below build on it.
            infoToggle.setButtonType(.toggle)
            makeBorderless(infoToggle, symbol: "info.circle.fill")
            infoToggle.alternateImage = symbol("info.circle", description: infoToggle.toolTip)
        }

        if let actionsButton {
            styleActions(actionsButton)
        }

        // The extra drag area stays; only the grip drawing goes.
        (dragHandle as? NSImageView)?.image = nil
    }

    private static func styleActions(_ button: NSPopUpButton) {
        let title = NSLocalizedString("Actions", comment: "main window : sidebar bottom bar : tooltip and accessibility description of the pull-down button that lists actions for the selected tables")

        button.isBordered = false
        button.imagePosition = .imageOnly
        button.toolTip = title
        button.setAccessibilityLabel(title)
        if let cell = button.cell as? NSPopUpButtonCell {
            cell.arrowPosition = .noArrow
            cell.alternateImage = nil
        }

        // A pull-down shows its first, hidden item in the button.
        button.itemArray.first?.image = symbol("ellipsis.circle", description: title)
    }

    private static func makeBorderless(_ button: NSButton, symbol name: String) {
        let description = button.toolTip

        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.contentTintColor = nil
        button.image = symbol(name, description: description)
        button.alternateImage = nil
        if let description {
            button.setAccessibilityLabel(description)
        }
    }

    private static func symbol(_ name: String, description: String?) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: description)
    }
}
