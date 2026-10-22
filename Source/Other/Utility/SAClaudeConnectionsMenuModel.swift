//
//  SAClaudeConnectionsMenuModel.swift
//  Sequel Ace
//
//  Connection import, export and sorting outside a favourite card's right-click menu: the connection screen's "⋯"
//  menu (Import Connections…, Export Connections…, Sort By ▸) and the File menu's Import / Export Connections… items.
//  Import and Export go through the connections router (SAClaudeConnectionsCommands), which sends the favourites gear
//  menu's own `importFavorites:` / `exportFavorites:` — or, with no favourite selected, `exportAllFavorites:` (every
//  favourite and folder, same writer and file format) — so panels, alerts and file formats are the card menu's.
//  Sort By is the gear menu's own (`sortFavorites:`, `reverseSortFavorites:`). Pure (AppKit types only, no app
//  state): built into the app and the Unit Tests targets. The ⋯ button is SAClaudeConnectionPageStyler's.
//

import AppKit

enum SAClaudeConnectionsMenuModel {

    static let importAction = NSSelectorFromString("importFavorites:")
    static let exportAction = NSSelectorFromString("exportFavorites:")
    static let exportAllAction = NSSelectorFromString("exportAllFavorites:")
    private static let sortAction = NSSelectorFromString("sortFavorites:")
    private static let fileExportAction = NSSelectorFromString("export:")

    static let importItemIdentifier = NSUserInterfaceItemIdentifier("SAClaudeImportConnections")
    static let exportItemIdentifier = NSUserInterfaceItemIdentifier("SAClaudeExportConnections")
    private static let separatorIdentifier = NSUserInterfaceItemIdentifier("SAClaudeConnectionsSeparator")

    static var importTitle: String {
        NSLocalizedString("ClaudeConnectionsImport", value: "Import Connections…",
                          comment: "connection screen ⋯ menu and File menu : imports connection favourites from a file (or a copied connection string)")
    }

    static var exportTitle: String {
        NSLocalizedString("ClaudeConnectionsExport", value: "Export Connections…",
                          comment: "connection screen ⋯ menu and File menu : exports the selected connection favourites to a file")
    }

    static var exportAllTitle: String {
        NSLocalizedString("ClaudeConnectionsExportAll", value: "Export All Connections…",
                          comment: "connection screen ⋯ menu and File menu : exports every connection favourite (with its folders) to a file; shown when no favourite is selected")
    }

    static var exportSelectedTitle: String {
        NSLocalizedString("ClaudeConnectionsExportSelected", value: "Export Selected…",
                          comment: "connection screen ⋯ menu and File menu : exports the several selected connection favourites to a file")
    }

    // MARK: - Export: the selection, or everything

    /// What Export Connections… does for `selectedFavoriteCount` selected favourites and folders (Quick Connect not
    /// counted): the selection with the controller's `exportFavorites:`, or with none every favourite with
    /// `exportAllFavorites:`; and the item's title for it. Nil (no connection page to act on, the item is disabled):
    /// the plain "Export Connections…", so a disabled item never keeps a stale title.
    static func exportCommand(selectedFavoriteCount: Int?) -> (title: String, action: Selector) {
        guard let selectedFavoriteCount else { return (exportTitle, exportAction) }
        switch selectedFavoriteCount {
        case ..<1: return (exportAllTitle, exportAllAction)
        case 1: return (exportTitle, exportAction)
        default: return (exportSelectedTitle, exportAction)
        }
    }

    // MARK: - ⋯ menu

    /// The gear menu's Sort By item: the one whose submenu sends `sortFavorites:`.
    static func sortByItem(in gearMenu: NSMenu) -> NSMenuItem? {
        gearMenu.items.first { $0.submenu?.items.contains { $0.action == sortAction } ?? false }
    }

    /// The connection screen's ⋯ menu: Import Connections… and Export Connections… sending `importAction` /
    /// `exportAction` to `target` (the connections router), then a copy of the gear menu's Sort By. The copy keeps its
    /// items' titles, actions, targets, states and order (`sortFavorites:` reads the sort from the item's index); the
    /// gear menu keeps its own. Items are auto-enabled: the router (Import, Export and its title) and the connection
    /// controller (Sort By and its ticks, as in the card menu) validate them.
    static func moreMenu(gearMenu: NSMenu?, target: AnyObject?, importAction: Selector, exportAction: Selector) -> NSMenu {
        let menu = NSMenu(title: "")
        menu.autoenablesItems = true
        for (title, action) in [(importTitle, importAction), (exportTitle, exportAction)] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = target
            menu.addItem(item)
        }
        if let gearMenu, let sortBy = sortByItem(in: gearMenu) {
            menu.addItem(.separator())
            menu.addItem(copy(of: sortBy))
        }
        return menu
    }

    /// Where the ⋯ menu's top-left goes in its button's coordinates: under the button (4pt below), its right edge on
    /// the button's. `menuWidth` is the menu's width as it will be shown — measured after its glyphs are in.
    static func popUpOrigin(buttonBounds: NSRect, isFlipped: Bool, menuWidth: CGFloat) -> NSPoint {
        let gap: CGFloat = 4
        return NSPoint(x: buttonBounds.maxX - menuWidth, y: isFlipped ? buttonBounds.maxY + gap : buttonBounds.minY - gap)
    }

    /// A menu item with its own copy of its submenu (a menu can be the submenu of one item only).
    private static func copy(of item: NSMenuItem) -> NSMenuItem {
        let copy = NSMenuItem(title: item.title, action: item.action, keyEquivalent: item.keyEquivalent)
        copy.keyEquivalentModifierMask = item.keyEquivalentModifierMask
        copy.target = item.target
        copy.tag = item.tag
        copy.state = item.state
        copy.image = item.image
        copy.representedObject = item.representedObject
        if let submenu = item.submenu {
            let menu = NSMenu(title: submenu.title)
            menu.autoenablesItems = submenu.autoenablesItems
            for child in submenu.items { menu.addItem(child.isSeparatorItem ? .separator() : self.copy(of: child)) }
            copy.submenu = menu
        }
        return copy
    }

    // MARK: - File menu

    /// Adds a separator, Import Connections… and Export Connections… (sending `importAction` / `exportAction` to
    /// `target`) right after the File menu's Export… item, or at the end without one. Once: a second call does nothing.
    static func installFileMenuItems(in fileMenu: NSMenu, target: AnyObject, importAction: Selector, exportAction: Selector) {
        guard !fileMenu.items.contains(where: { $0.identifier == importItemIdentifier }) else { return }
        let separator = NSMenuItem.separator()
        separator.identifier = separatorIdentifier
        let importItem = NSMenuItem(title: importTitle, action: importAction, keyEquivalent: "")
        importItem.identifier = importItemIdentifier
        let exportItem = NSMenuItem(title: exportTitle, action: exportAction, keyEquivalent: "")
        exportItem.identifier = exportItemIdentifier
        importItem.target = target
        exportItem.target = target

        var index = fileMenu.items.firstIndex { $0.action == fileExportAction }.map { $0 + 1 } ?? fileMenu.numberOfItems
        for item in [separator, importItem, exportItem] {
            fileMenu.insertItem(item, at: index)
            index += 1
        }
    }

    /// The File menu's connection items act on the main window's connection screen: only while it shows one, isn't
    /// connecting and has no sheet open (the import and export panels are sheets on it).
    static func commandsAvailable(showsConnectionPage: Bool, isConnecting: Bool, hasAttachedSheet: Bool) -> Bool {
        showsConnectionPage && !isConnecting && !hasAttachedSheet
    }
}
