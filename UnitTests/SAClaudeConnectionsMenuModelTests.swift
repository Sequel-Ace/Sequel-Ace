//
//  SAClaudeConnectionsMenuModelTests.swift
//  Unit Tests
//
//  The connection screen's ⋯ menu and the File menu's connection items (SAClaudeConnectionsMenuModel).
//

import AppKit
import XCTest

final class SAClaudeConnectionsMenuModelTests: XCTestCase {

    private final class Target: NSObject {}

    private func item(_ title: String, _ action: String?, target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action.map(NSSelectorFromString), keyEquivalent: "")
        item.target = target
        return item
    }

    /// The favourites gear menu as ConnectionView.xib builds it (the card's right-click menu).
    private func gearMenu(target: AnyObject, withSortBy: Bool = true) -> NSMenu {
        let menu = NSMenu(title: "OtherViews")
        menu.addItem(item("", nil))
        menu.addItem(item("Rename", "renameNode:", target: target))
        menu.addItem(item("Remove", "removeNode:", target: target))
        menu.addItem(.separator())
        menu.addItem(item("Copy Connection String", "copyConnectionString:", target: target))
        menu.addItem(item("Duplicate", "duplicateFavorite:", target: target))
        menu.addItem(.separator())
        menu.addItem(item("Import...", "importFavorites:", target: target))
        menu.addItem(item("Export...", "exportFavorites:", target: target))
        menu.addItem(.separator())
        menu.addItem(item("Make Default", "makeSelectedFavoriteDefault:", target: target))
        if withSortBy {
            let sort = NSMenu(title: "Sort By")
            for title in ["Name", "Host", "Type", "Color"] { sort.addItem(item(title, "sortFavorites:", target: target)) }
            sort.addItem(.separator())
            sort.addItem(item("Reverse Sort Order", "reverseSortFavorites:", target: target))
            sort.item(at: 1)?.state = .on
            let sortBy = item("Sort By", nil)
            menu.addItem(sortBy)
            menu.setSubmenu(sort, for: sortBy)
        }
        return menu
    }

    // MARK: - ⋯ menu

    func testMoreMenuListsImportExportAndSortBy() {
        let controller = Target()
        let gear = gearMenu(target: controller)
        let menu = SAClaudeConnectionsMenuModel.moreMenu(gearMenu: gear, target: controller)

        XCTAssertEqual(menu.items.map { $0.isSeparatorItem ? "-" : $0.title },
                       [SAClaudeConnectionsMenuModel.importTitle, SAClaudeConnectionsMenuModel.exportTitle, "-", "Sort By"])
        XCTAssertEqual(SAClaudeConnectionsMenuModel.importTitle, "Import Connections…")
        XCTAssertEqual(SAClaudeConnectionsMenuModel.exportTitle, "Export Connections…")
        // The card menu's own actions, sent to the connection controller.
        XCTAssertEqual(menu.items[0].action, NSSelectorFromString("importFavorites:"))
        XCTAssertEqual(menu.items[1].action, NSSelectorFromString("exportFavorites:"))
        XCTAssertTrue(menu.items[0].target === controller)
        XCTAssertTrue(menu.items[1].target === controller)
    }

    func testSortByIsACopyOfTheGearMenusWithTheSameActionsOrderAndChecks() {
        let controller = Target()
        let gear = gearMenu(target: controller)
        let gearSort = gear.items.last!.submenu!
        let menu = SAClaudeConnectionsMenuModel.moreMenu(gearMenu: gear, target: controller)

        guard let sort = menu.items.last?.submenu else { return XCTFail("no Sort By submenu") }
        // `sortFavorites:` reads the sort from the item's index in its menu: the order must be the gear's.
        XCTAssertEqual(sort.items.map { $0.isSeparatorItem ? "-" : $0.title }, ["Name", "Host", "Type", "Color", "-", "Reverse Sort Order"])
        XCTAssertEqual(sort.items.prefix(4).map(\.action), Array(repeating: NSSelectorFromString("sortFavorites:"), count: 4))
        XCTAssertEqual(sort.items.last?.action, NSSelectorFromString("reverseSortFavorites:"))
        XCTAssertTrue(sort.items.filter { !$0.isSeparatorItem }.allSatisfy { $0.target === controller })
        XCTAssertEqual(sort.items[1].state, .on)
        // A copy: the gear menu keeps its own Sort By (a menu can be the submenu of one item only).
        XCTAssertFalse(sort === gearSort)
        XCTAssertTrue(gear.items.last?.submenu === gearSort)
        XCTAssertEqual(gearSort.items.count, 6)
        XCTAssertFalse(sort.items.contains { item in gearSort.items.contains { $0 === item } })
    }

    func testMoreMenuWithoutTheGearMenuHasImportAndExportOnly() {
        let controller = Target()
        for gear in [nil, gearMenu(target: controller, withSortBy: false)] {
            let menu = SAClaudeConnectionsMenuModel.moreMenu(gearMenu: gear, target: controller)
            XCTAssertEqual(menu.items.map(\.action), [NSSelectorFromString("importFavorites:"), NSSelectorFromString("exportFavorites:")])
        }
    }

    func testMoreMenuItemsUseTheMenusAutoEnabling() {
        // Validation (Export needs a selection, Sort By two favourites) stays the controller's `validateMenuItem:`.
        let menu = SAClaudeConnectionsMenuModel.moreMenu(gearMenu: gearMenu(target: Target()), target: Target())
        XCTAssertTrue(menu.autoenablesItems)
    }

    // MARK: - File menu

    private func fileMenu() -> NSMenu {
        let menu = NSMenu(title: "File")
        menu.addItem(item("New Connection Window", "newWindow:"))
        menu.addItem(.separator())
        menu.addItem(item("Import…", "import:"))
        let clipboard = item("Import from Clipboard…", "importFromClipboard:")
        clipboard.isAlternate = true
        menu.addItem(clipboard)
        menu.addItem(item("Export…", "export:"))
        menu.addItem(.separator())
        menu.addItem(item("Close", "performClose:"))
        return menu
    }

    private func titles(_ menu: NSMenu) -> [String] {
        menu.items.map { $0.isSeparatorItem ? "-" : $0.title }
    }

    func testFileMenuItemsGoRightAfterExport() {
        let menu = fileMenu()
        let router = Target()
        SAClaudeConnectionsMenuModel.installFileMenuItems(in: menu, target: router,
                                                          importAction: NSSelectorFromString("importConnections:"),
                                                          exportAction: NSSelectorFromString("exportConnections:"))
        XCTAssertEqual(titles(menu), ["New Connection Window", "-", "Import…", "Import from Clipboard…", "Export…",
                                      "-", "Import Connections…", "Export Connections…", "-", "Close"])
        let importItem = menu.items[6], exportItem = menu.items[7]
        XCTAssertEqual(importItem.action, NSSelectorFromString("importConnections:"))
        XCTAssertEqual(exportItem.action, NSSelectorFromString("exportConnections:"))
        XCTAssertTrue(importItem.target === router)
        XCTAssertTrue(exportItem.target === router)
        XCTAssertEqual(importItem.keyEquivalent, "")
        XCTAssertEqual(exportItem.keyEquivalent, "")
        // Import… keeps its ⌥ alternate.
        XCTAssertTrue(menu.items[3].isAlternate)
    }

    func testFileMenuItemsAreInstalledOnce() {
        let menu = fileMenu()
        let router = Target()
        for _ in 0..<2 {
            SAClaudeConnectionsMenuModel.installFileMenuItems(in: menu, target: router,
                                                              importAction: NSSelectorFromString("importConnections:"),
                                                              exportAction: NSSelectorFromString("exportConnections:"))
        }
        XCTAssertEqual(titles(menu).filter { $0 == "Import Connections…" }.count, 1)
        XCTAssertEqual(menu.items.count, 10)
    }

    func testFileMenuWithoutExportGetsTheItemsAtTheEnd() {
        let menu = NSMenu(title: "File")
        menu.addItem(item("Close", "performClose:"))
        SAClaudeConnectionsMenuModel.installFileMenuItems(in: menu, target: Target(),
                                                          importAction: NSSelectorFromString("importConnections:"),
                                                          exportAction: NSSelectorFromString("exportConnections:"))
        XCTAssertEqual(titles(menu), ["Close", "-", "Import Connections…", "Export Connections…"])
    }

    func testFileMenuCommandsNeedAConnectionPageThatIsFree() {
        XCTAssertTrue(SAClaudeConnectionsMenuModel.commandsAvailable(showsConnectionPage: true, isConnecting: false, hasAttachedSheet: false))
        XCTAssertFalse(SAClaudeConnectionsMenuModel.commandsAvailable(showsConnectionPage: false, isConnecting: false, hasAttachedSheet: false))
        XCTAssertFalse(SAClaudeConnectionsMenuModel.commandsAvailable(showsConnectionPage: true, isConnecting: true, hasAttachedSheet: false))
        XCTAssertFalse(SAClaudeConnectionsMenuModel.commandsAvailable(showsConnectionPage: true, isConnecting: false, hasAttachedSheet: true))
    }
}
