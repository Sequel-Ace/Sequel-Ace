//
//  SAClaudeConnectionsFileMenu.swift
//  Sequel Ace
//
//  Import Connections… and Export Connections… outside a favourite card's right-click menu, for the connection
//  screen's ⋯ menu and the File menu (added at launch; MainMenu.xib is untouched).
//
//  `SAClaudeConnectionsCommands` routes both to a connection controller's own actions and validation:
//  `importFavorites:`; and `exportFavorites:` with a favourite or folder selected ("Export Connections…", "Export
//  Selected…" for several) or, with nothing or only Quick Connect selected, `exportAllFavorites:` ("Export All
//  Connections…": every favourite and folder, same writer, panel and file format). The card menu keeps its own Export….
//
//  `SAClaudeConnectionsFileMenu` installs the File menu items on a router that acts on the main window's connection
//  screen: disabled while that window is connected, connecting or showing a sheet. App target only; the menu shapes
//  and the export decision are SAClaudeConnectionsMenuModel.
//

import AppKit

/// Import / Export Connections… for the connection controller `resolve` returns (nil: disabled).
final class SAClaudeConnectionsCommands: NSObject, NSMenuItemValidation {

    private let resolve: () -> SPConnectionController?

    init(resolve: @escaping () -> SPConnectionController?) {
        self.resolve = resolve
        super.init()
    }

    static let importSelector = #selector(importConnections(_:))
    static let exportSelector = #selector(exportConnections(_:))

    @objc func importConnections(_ sender: Any?) {
        guard let controller = resolve(), Self.controller(controller, validates: SAClaudeConnectionsMenuModel.importAction) else { return }
        controller.importFavorites(sender)
    }

    @objc func exportConnections(_ sender: Any?) {
        guard let controller = resolve() else { return }
        let command = Self.exportCommand(for: controller)
        guard Self.controller(controller, validates: command.action) else { return }
        _ = NSApp.sendAction(command.action, to: controller, from: sender)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let controller = resolve() else { return false }
        switch menuItem.action {
        case Self.importSelector:
            return Self.controller(controller, validates: SAClaudeConnectionsMenuModel.importAction)
        case Self.exportSelector:
            let command = Self.exportCommand(for: controller)
            if menuItem.title != command.title { menuItem.title = command.title }
            return Self.controller(controller, validates: command.action)
        default:
            return false
        }
    }

    /// The selection's export, or everything's when no favourite or folder is selected (Quick Connect isn't one).
    private static func exportCommand(for controller: SPConnectionController) -> (title: String, action: Selector) {
        let quickConnect = controller.favoritesListDataSource?.quickConnectItem
        let selected = (controller.selectedFavoriteNodes() ?? []).filter { ($0 as AnyObject) !== quickConnect }
        return SAClaudeConnectionsMenuModel.exportCommand(selectedFavoriteCount: selected.count)
    }

    /// The connection controller's own `validateMenuItem:` for `action`, asked with a stand-in item so ours keeps its
    /// title (the controller retitles a multi-selection Export to "Export Selected...").
    private static func controller(_ controller: SPConnectionController, validates action: Selector) -> Bool {
        let probe = NSMenuItem(title: "", action: action, keyEquivalent: "")
        probe.target = controller
        return (controller as AnyObject).validateMenuItem?(probe) ?? true
    }
}

@objc(SAClaudeConnectionsFileMenu) final class SAClaudeConnectionsFileMenu: NSObject {

    /// The File menu items' target (a menu item holds its target weakly).
    private static let commands = SAClaudeConnectionsCommands { frontConnectionController() }

    /// Adds the two items after File ▸ Export… (once; call at launch).
    @objc static func install() {
        guard let mainMenu = NSApp.mainMenu, let fileMenu = (mainMenu.item(withTag: 1) ?? mainMenu.item(withTitle: "File"))?.submenu else { return }
        SAClaudeConnectionsMenuModel.installFileMenuItems(in: fileMenu, target: commands,
                                                          importAction: SAClaudeConnectionsCommands.importSelector,
                                                          exportAction: SAClaudeConnectionsCommands.exportSelector)
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
}
