//
//  SADesignToolbarMenu.swift
//  Sequel Ace
//
//  View ▸ Toolbar: show or hide each main window toolbar item, switch between
//  Icon and Text, Icon Only and Text Only, or reset to the default layout. Works on the
//  key window's document toolbar; AppKit keeps every window and tab sharing
//  the toolbar identifier in step and autosaves the result. App target only.
//

import AppKit

@objc(SADesignToolbarMenu) final class SADesignToolbarMenu: NSObject, NSMenuItemValidation {

    private static let shared = SADesignToolbarMenu()
    private static let toolbarIdentifier = "TableWindowToolbar"

    /// Adds the submenu after View ▸ Customize Toolbar… (once).
    @objc static func install() {
        let customize = #selector(NSWindow.runToolbarCustomizationPalette(_:))
        guard let mainMenu = NSApp.mainMenu else { return }
        for top in mainMenu.items {
            guard let menu = top.submenu, let index = menu.items.firstIndex(where: { $0.action == customize }) else { continue }
            guard !menu.items.contains(where: { $0.submenu?.identifier?.rawValue == "SADesignToolbarMenu" }) else { return }
            let item = NSMenuItem(title: NSLocalizedString("Toolbar", comment: "View menu: submenu for showing or hiding toolbar items"),
                                  action: nil, keyEquivalent: "")
            item.submenu = shared.makeMenu()
            menu.insertItem(item, at: index + 1)
            return
        }
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.identifier = NSUserInterfaceItemIdentifier("SADesignToolbarMenu")
        for identifier in SADesignToolbarLayout.menuItems {
            let item = NSMenuItem(title: SADesignToolbarLayout.menuTitle(for: identifier), action: #selector(toggleItem(_:)), keyEquivalent: "")
            item.representedObject = identifier
            item.target = self
            menu.addItem(item)
        }
        menu.addItem(.separator())
        // The display modes, worded as in the Customize Toolbar sheet.
        let modes: [(String, NSToolbar.DisplayMode)] = [
            (NSLocalizedString("Icon and Text", comment: "View ▸ Toolbar: show toolbar items with icons and labels"), .iconAndLabel),
            (NSLocalizedString("Icon Only", comment: "View ▸ Toolbar: show toolbar items as icons without labels"), .iconOnly),
            (NSLocalizedString("Text Only", comment: "View ▸ Toolbar: show toolbar items as labels without icons"), .labelOnly),
        ]
        for (title, mode) in modes {
            let item = NSMenuItem(title: title, action: #selector(setDisplayMode(_:)), keyEquivalent: "")
            item.tag = Int(mode.rawValue)
            item.target = self
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let reset = NSMenuItem(title: NSLocalizedString("Reset to Default", comment: "View ▸ Toolbar: restore the default toolbar items and order"),
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

    /// Runs a toolbar edit, then re-asserts each document toolbar's selected view. AppKit propagates
    /// edits to every toolbar sharing the identifier (all tabs) and may clear the selection, which
    /// SPTableContent, SPCustomQuery, SPTableStructure etc. read to know their view is in front.
    private func preservingSelection(_ edit: () -> Void) {
        let saved: [(NSToolbar, NSToolbarItem.Identifier?)] = NSApp.windows.compactMap { window in
            guard let toolbar = window.toolbar, toolbar.identifier == Self.toolbarIdentifier else { return nil }
            return (toolbar, toolbar.selectedItemIdentifier)
        }
        edit()
        for (toolbar, selected) in saved {
            if let selected { toolbar.selectedItemIdentifier = selected }
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let toolbar else { menuItem.state = .off; return false }
        switch menuItem.action {
        case #selector(toggleItem(_:)):
            let identifier = menuItem.representedObject as? String ?? ""
            menuItem.state = identifiers(of: toolbar).contains(identifier) ? .on : .off
        case #selector(setDisplayMode(_:)):
            // The default mode shows icons and labels.
            let current: NSToolbar.DisplayMode = toolbar.displayMode == .default ? .iconAndLabel : toolbar.displayMode
            menuItem.state = menuItem.tag == Int(current.rawValue) ? .on : .off
        default:
            break
        }
        return true
    }

    @objc private func toggleItem(_ sender: NSMenuItem) {
        guard let toolbar, let identifier = sender.representedObject as? String else { return }
        let current = identifiers(of: toolbar)
        preservingSelection {
            if let index = current.firstIndex(of: identifier) {
                toolbar.removeItem(at: index)
            } else {
                toolbar.insertItem(withItemIdentifier: NSToolbarItem.Identifier(identifier),
                                   at: SADesignToolbarLayout.insertionIndex(of: identifier, into: current))
            }
        }
    }

    @objc private func setDisplayMode(_ sender: NSMenuItem) {
        guard let mode = NSToolbar.DisplayMode(rawValue: UInt(sender.tag)) else { return }
        toolbar?.displayMode = mode
    }

    @objc private func resetToDefault(_ sender: Any?) {
        guard let toolbar else { return }
        preservingSelection {
            while !toolbar.items.isEmpty { toolbar.removeItem(at: toolbar.items.count - 1) }
            for (index, identifier) in SADesignToolbarLayout.defaultItems.enumerated() {
                toolbar.insertItem(withItemIdentifier: NSToolbarItem.Identifier(identifier), at: index)
            }
            toolbar.displayMode = .iconAndLabel
        }
    }
}
