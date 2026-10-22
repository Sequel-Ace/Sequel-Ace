//
//  SAClaudeConnectionsFileMenu.swift
//  Sequel Ace
//
//  The File menu's Import Connections… and Export Connections… (added at launch; MainMenu.xib is untouched). Both act
//  on the main window's connection screen and send its connection controller the favourites gear menu's own
//  `importFavorites:` / `exportFavorites:`, with that controller's validation: Import whenever a connection screen is
//  frontmost, Export when it also has a favourite or folder selected (as the card menu's Export…). Disabled while the
//  main window is connected, connecting or showing a sheet. App target only; the menu shape is
//  SAClaudeConnectionsMenuModel.
//

import AppKit

@objc(SAClaudeConnectionsFileMenu) final class SAClaudeConnectionsFileMenu: NSObject, NSMenuItemValidation {

    /// The items' target (a menu item holds its target weakly).
    private static let shared = SAClaudeConnectionsFileMenu()

    /// Adds the two items after File ▸ Export… (once; call at launch).
    @objc static func install() {
        guard let mainMenu = NSApp.mainMenu, let fileMenu = (mainMenu.item(withTag: 1) ?? mainMenu.item(withTitle: "File"))?.submenu else { return }
        SAClaudeConnectionsMenuModel.installFileMenuItems(in: fileMenu, target: shared,
                                                          importAction: #selector(importConnections(_:)),
                                                          exportAction: #selector(exportConnections(_:)))
    }

    /// The connection controller of the main window's connection screen, when the commands can use it.
    static func frontConnectionController(in window: NSWindow? = NSApp.mainWindow) -> SPConnectionController? {
        guard let window, let windowController = window.windowController as? SPWindowController else { return nil }
        let controller = windowController.databaseDocument.connectionController()
        // The connection view (with the favourites outline) is in the window until the document connects.
        let showsPage = controller.favoritesOutlineView()?.window === window
        guard SAClaudeConnectionsMenuModel.commandsAvailable(showsConnectionPage: showsPage, isConnecting: controller.isConnecting,
                                                             hasAttachedSheet: window.attachedSheet != nil) else { return nil }
        return controller
    }

    @objc func importConnections(_ sender: Any?) {
        Self.frontConnectionController()?.importFavorites(sender)
    }

    @objc func exportConnections(_ sender: Any?) {
        guard let controller = Self.frontConnectionController(), Self.controller(controller, validates: SAClaudeConnectionsMenuModel.exportAction) else { return }
        controller.exportFavorites(sender)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let controller = Self.frontConnectionController() else { return false }
        switch menuItem.action {
        case #selector(importConnections(_:)):
            return Self.controller(controller, validates: SAClaudeConnectionsMenuModel.importAction)
        case #selector(exportConnections(_:)):
            return Self.controller(controller, validates: SAClaudeConnectionsMenuModel.exportAction)
        default:
            return false
        }
    }

    /// The connection controller's own `validateMenuItem:` for `action`, asked with a stand-in item so the File menu
    /// item keeps its title (the controller retitles a multi-selection Export to "Export Selected...").
    private static func controller(_ controller: SPConnectionController, validates action: Selector) -> Bool {
        let probe = NSMenuItem(title: "", action: action, keyEquivalent: "")
        probe.target = controller
        return (controller as AnyObject).validateMenuItem?(probe) ?? true
    }
}
