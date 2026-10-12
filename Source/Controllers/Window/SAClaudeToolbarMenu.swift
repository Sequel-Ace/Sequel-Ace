//
//  SAClaudeToolbarMenu.swift
//  Sequel Ace
//
//  View ▸ Toolbar: show or hide each main window toolbar item, switch between
//  icon and text and icon only, or reset to the default layout. Works on the
//  key window's document toolbar; AppKit keeps every window and tab sharing
//  the toolbar identifier in step and autosaves the result. App target only.
//

import AppKit

@objc(SAClaudeToolbarMenu) final class SAClaudeToolbarMenu: NSObject, NSMenuItemValidation {

    private static let shared = SAClaudeToolbarMenu()
    private static let toolbarIdentifier = "TableWindowToolbar"

    /// Adds the submenu after View ▸ Customize Toolbar… (once).
    @objc static func install() {
        let customize = #selector(NSWindow.runToolbarCustomizationPalette(_:))
        guard let mainMenu = NSApp.mainMenu else { return }
        for top in mainMenu.items {
            guard let menu = top.submenu, let index = menu.items.firstIndex(where: { $0.action == customize }) else { continue }
            guard !menu.items.contains(where: { $0.submenu?.identifier?.rawValue == "SAClaudeToolbarMenu" }) else { return }
            let item = NSMenuItem(title: NSLocalizedString("ClaudeToolbarMenuTitle", value: "Toolbar", comment: "View menu: submenu for showing or hiding toolbar items"),
                                  action: nil, keyEquivalent: "")
            item.submenu = shared.makeMenu()
            menu.insertItem(item, at: index + 1)
            return
        }
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.identifier = NSUserInterfaceItemIdentifier("SAClaudeToolbarMenu")
        for identifier in SAClaudeToolbarLayout.menuItems {
            let item = NSMenuItem(title: SAClaudeToolbarLayout.menuTitle(for: identifier), action: #selector(toggleItem(_:)), keyEquivalent: "")
            item.representedObject = identifier
            item.target = self
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let iconAndText = NSMenuItem(title: NSLocalizedString("ClaudeToolbarMenuIconAndText", value: "Icon and text", comment: "View ▸ Toolbar: show toolbar items with icons and labels"),
                                     action: #selector(setIconAndText(_:)), keyEquivalent: "")
        iconAndText.target = self
        menu.addItem(iconAndText)
        let iconOnly = NSMenuItem(title: NSLocalizedString("ClaudeToolbarMenuIconOnly", value: "Icon only", comment: "View ▸ Toolbar: show toolbar items as icons without labels"),
                                  action: #selector(setIconOnly(_:)), keyEquivalent: "")
        iconOnly.target = self
        menu.addItem(iconOnly)
        menu.addItem(.separator())
        let reset = NSMenuItem(title: NSLocalizedString("ClaudeToolbarMenuReset", value: "Reset to default", comment: "View ▸ Toolbar: restore the default toolbar items and order"),
                               action: #selector(resetToDefault(_:)), keyEquivalent: "")
        reset.target = self
        menu.addItem(reset)
        return menu
    }

    /// The key (or main) window's document toolbar.
    private var toolbar: NSToolbar? {
        for window in [NSApp.keyWindow, NSApp.mainWindow].compactMap({ $0 }) {
            if let toolbar = window.toolbar, toolbar.identifier == Self.toolbarIdentifier { return toolbar }
        }
        return nil
    }

    private func identifiers(of toolbar: NSToolbar) -> [String] { toolbar.items.map(\.itemIdentifier.rawValue) }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let toolbar else { menuItem.state = .off; return false }
        switch menuItem.action {
        case #selector(toggleItem(_:)):
            let identifier = menuItem.representedObject as? String ?? ""
            menuItem.state = identifiers(of: toolbar).contains(identifier) ? .on : .off
        case #selector(setIconAndText(_:)):
            menuItem.state = toolbar.displayMode == .iconAndLabel || toolbar.displayMode == .default ? .on : .off
        case #selector(setIconOnly(_:)):
            menuItem.state = toolbar.displayMode == .iconOnly ? .on : .off
        default:
            break
        }
        return true
    }

    @objc private func toggleItem(_ sender: NSMenuItem) {
        guard let toolbar, let identifier = sender.representedObject as? String else { return }
        let current = identifiers(of: toolbar)
        if let index = current.firstIndex(of: identifier) {
            toolbar.removeItem(at: index)
        } else {
            toolbar.insertItem(withItemIdentifier: NSToolbarItem.Identifier(identifier),
                               at: SAClaudeToolbarLayout.insertionIndex(of: identifier, into: current))
        }
    }

    @objc private func setIconAndText(_ sender: Any?) { toolbar?.displayMode = .iconAndLabel }
    @objc private func setIconOnly(_ sender: Any?) { toolbar?.displayMode = .iconOnly }

    @objc private func resetToDefault(_ sender: Any?) {
        guard let toolbar else { return }
        while !toolbar.items.isEmpty { toolbar.removeItem(at: toolbar.items.count - 1) }
        for (index, identifier) in SAClaudeToolbarLayout.defaultItems.enumerated() {
            toolbar.insertItem(withItemIdentifier: NSToolbarItem.Identifier(identifier), at: index)
        }
        toolbar.displayMode = .iconAndLabel
    }
}
