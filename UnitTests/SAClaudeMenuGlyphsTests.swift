import AppKit
import XCTest

final class SAClaudeMenuGlyphsTests: XCTestCase {

    /// Every action of the surveyed right-click menus and main-window gear pull-downs that gets a glyph.
    private let expected: [String: String] = [
        // Table list (DBView 6180) and the sidebar gear pull-down (same items).
        "copyTableName:": "doc.on.doc",
        "renameTable:": "pencil",
        "copyTable:": "plus.square.on.square",            // Duplicate Table…
        "truncateTable:": "eraser",
        "removeTable:": "trash",
        "togglePinTable:": "pin",
        "openTableInNewTab:": "macwindow.badge.plus",
        "openTableInNewWindow:": "macwindow",
        "exportSelectedTablesAs:": "square.and.arrow.up",
        "showCreateTableSyntax:": "chevron.left.forwardslash.chevron.right",
        "copyCreateTableSyntax:": "doc.on.doc",
        // Content grid (6225) and query results (7467); the cell-value copy items also send copy:.
        "copy:": "doc.on.doc",
        "addRow:": "plus",
        "duplicateRow:": "plus.square.on.square",
        "removeRow:": "trash",
        // Structure fields (6210), indexes (6219) and its AUTO_INCREMENT gear, relations (6232), triggers (6735).
        "removeField:": "trash",
        "duplicateField:": "plus.square.on.square",
        "showOptimizedFieldType:": "wand.and.stars",
        "removeIndex:": "trash",
        "resetAutoIncrement:": "arrow.counterclockwise",
        "removeRelation:": "trash",
        "editTrigger:": "pencil",
        "removeTrigger:": "trash",
        // Query editor (SPTextView -menuForEvent:): the text view's own edit items and the ones it adds.
        "cut:": "scissors",
        "paste:": "doc.on.clipboard",
        "pasteAsPlainText:": "doc.on.clipboard",
        "copyAsRTF": "doc.on.doc",
        "showMySQLHelpForCurrentWord:": "questionmark.circle",
        "selectCurrentQuery:": "selection.pin.in.out",
        // Query "Export Result" gear pull-down (DBView 7977).
        "exportCustomQueryResultAsFormat:": "square.and.arrow.up",
        // Connection screen: favourites context menu (5788) and gear pull-down (5826), also the card grid's menu.
        "renameNode:": "pencil",
        "removeNode:": "trash",
        "copyConnectionString:": "doc.on.doc",
        "duplicateFavorite:": "plus.square.on.square",
        "makeSelectedFavoriteDefault:": "star",
        "exportFavorites:": "square.and.arrow.up",
        "importFavorites:": "square.and.arrow.down",
        // Window tab chips.
        "closeTab:": "xmark",
        "closeOtherTabs:": "xmark.circle",
        "moveTabToNewWindow:": "macwindow",
        "mergeAllWindows:": "rectangle.stack",
        // Filter bar (rule editor and its drop box).
        "addEmptyFilterRow": "plus",
        "addEmptyFilterGroup": "plus.rectangle.on.rectangle",
        "copyPreviewClause:": "doc.on.doc",
        // Refresh / reload.
        "refresh:": "arrow.clockwise",
        "refreshTables:": "arrow.clockwise",
        "reloadTable:": "arrow.clockwise",
    ]

    private func symbol(_ selector: String, _ title: String = "Item") -> String? {
        SAClaudeMenuGlyphs.symbol(forAction: selector, title: title)
    }

    /// Stands in for the pass's symbol images: a distinct image per name, so the tests can tell which one landed.
    private var images: [String: NSImage] = [:]
    private func image(_ name: String) -> NSImage? {
        if let image = images[name] { return image }
        let image = NSImage(size: NSSize(width: 15, height: 15))
        images[name] = image
        return image
    }

    /// The symbol name an image from `image(_:)` stands for.
    private func nameOf(_ image: NSImage?) -> String? {
        guard let image else { return nil }
        return images.first { $0.value === image }?.key
    }

    private func item(_ title: String, _ selector: String?) -> NSMenuItem {
        NSMenuItem(title: title, action: selector.map(NSSelectorFromString), keyEquivalent: "")
    }

    private func isVisible(_ item: NSMenuItem) -> Bool {
        if #available(macOS 27.0, *) { return item.preferredImageVisibility == .visible }
        return true
    }

    private func isAutomatic(_ item: NSMenuItem) -> Bool {
        if #available(macOS 27.0, *) { return item.preferredImageVisibility == .automatic }
        return true
    }

    // MARK: Map

    func testKnownActionsMap() {
        for (selector, name) in expected {
            XCTAssertEqual(symbol(selector), name, selector)
        }
        // Each Copy row of the grids sends copy: (tags 2001–2004); the title doesn't change the glyph.
        for title in ["Copy", "Copy with Column Names", "Copy as SQL INSERT", "Copy as SQL INSERT (no auto_inc)"] {
            XCTAssertEqual(symbol("copy:", title), "doc.on.doc", title)
        }
    }

    func testEveryMappedSymbolExists() {
        let names = Set(expected.values).union(SAClaudeMenuGlyphs.allSymbolNames)
        for name in names {
            XCTAssertNotNil(NSImage(systemSymbolName: name, accessibilityDescription: nil), "\(name) is not an SF Symbol here")
        }
    }

    func testUnknownActionHasNoGlyph() {
        // Dynamic items (Bundles, cell filter operators, display formats, sort choices, column toggles) and unknowns.
        for selector in ["executeBundleItemForDataTable:", "executeBundleItemForInputField:", "apply:", "sortFavorites:",
                         "reverseSortFavorites:", "toggleColumnView:", "toggleDisplayOverrideFormatter:", "submenuAction:",
                         "_popUpItemAction:", "somethingNew:", ""] {
            XCTAssertNil(symbol(selector), selector)
        }
    }

    // MARK: apply

    func testFillsEmptyImagesAndMakesThemVisible() {
        let menu = NSMenu()
        let rename = item("Rename Table...", "renameTable:")
        let unknown = item("Something", "somethingNew:")
        let noAction = item("Header", nil)
        [rename, unknown, noAction].forEach(menu.addItem)
        menu.addItem(.separator())

        SAClaudeMenuGlyphs.apply(to: menu, imageFor: image, mainMenu: nil)

        XCTAssertEqual(nameOf(rename.image), "pencil")
        XCTAssertTrue(isVisible(rename))
        XCTAssertNil(unknown.image)
        XCTAssertTrue(isAutomatic(unknown))
        XCTAssertNil(noAction.image)
    }

    func testNeverReplacesExistingImage() {
        let menu = NSMenu()
        // An image the code set (database glyph, a gear pull-down's title item) on an item whose action maps.
        let codeImage = NSImage(size: NSSize(width: 16, height: 16))
        let codeSet = item("Rename Table...", "renameTable:")
        codeSet.image = codeImage
        // A gear pull-down's title item: image, no mapped action.
        let gearTitle = item("", "_popUpItemAction:")
        let gearImage = NSImage(size: NSSize(width: 14, height: 14))
        gearTitle.image = gearImage
        // A database row: image, no action.
        let database = item("mysql", nil)
        let databaseImage = NSImage(size: NSSize(width: 12, height: 12))
        database.image = databaseImage
        [gearTitle, codeSet, database].forEach(menu.addItem)

        SAClaudeMenuGlyphs.apply(to: menu, imageFor: image, mainMenu: nil)
        SAClaudeMenuGlyphs.apply(to: menu, imageFor: image, mainMenu: nil)

        XCTAssertTrue(codeSet.image === codeImage)
        XCTAssertTrue(gearTitle.image === gearImage)
        XCTAssertTrue(database.image === databaseImage)
        // Their visibility is the code's business too.
        XCTAssertTrue(isAutomatic(codeSet))
        XCTAssertTrue(isAutomatic(gearTitle))
        XCTAssertTrue(isAutomatic(database))
    }

    /// AppKit gives some standard actions an image of its own (Copy, Cut, Paste…), hidden by default on macOS 27:
    /// the item keeps that image, and a mapped one is shown like the glyphs the pass adds.
    func testKeepsAppKitsOwnImageAndShowsIt() {
        let menu = NSMenu()
        let copy = item("Copy with Column Names", "copy:")
        menu.addItem(copy)
        let appKitImage = copy.image

        SAClaudeMenuGlyphs.apply(to: menu, imageFor: image, mainMenu: nil)

        if let appKitImage {
            XCTAssertTrue(copy.image === appKitImage)
        } else {
            XCTAssertEqual(nameOf(copy.image), "doc.on.doc")
        }
        XCTAssertTrue(isVisible(copy))
    }

    func testRecursesIntoSubmenus() {
        let menu = NSMenu()
        let export = item("Export", nil)
        let submenu = NSMenu(title: "Export")
        let sql = item("As SQL dump...", "exportSelectedTablesAs:")
        let csv = item("As CSV file...", "exportSelectedTablesAs:")
        let deeper = item("More", nil)
        let deeperMenu = NSMenu(title: "More")
        let remove = item("Remove Table...", "removeTable:")
        deeperMenu.addItem(remove)
        [sql, csv, deeper].forEach(submenu.addItem)
        submenu.setSubmenu(deeperMenu, for: deeper)
        menu.addItem(export)
        menu.setSubmenu(submenu, for: export)

        SAClaudeMenuGlyphs.apply(to: menu, imageFor: image, mainMenu: nil)

        XCTAssertEqual(nameOf(sql.image), "square.and.arrow.up")
        XCTAssertEqual(nameOf(csv.image), "square.and.arrow.up")
        XCTAssertEqual(nameOf(remove.image), "trash")
    }

    /// A submenu's parent row (Export, Export Result, View Columns, Sort By, Filter by Selected Value) takes the glyph
    /// its items share; with mixed or unknown items it gets none.
    func testSubmenuParentTakesItsItemsSharedGlyph() {
        func parent(_ selectors: [String?]) -> NSMenuItem {
            let parent = item("Parent", nil)
            let submenu = NSMenu()
            for selector in selectors { submenu.addItem(item("Child", selector)) }
            submenu.addItem(.separator())
            parent.submenu = submenu
            let menu = NSMenu()
            menu.addItem(parent)
            SAClaudeMenuGlyphs.apply(to: menu, imageFor: image, mainMenu: nil)
            return parent
        }
        XCTAssertEqual(nameOf(parent(["exportSelectedTablesAs:", "exportSelectedTablesAs:"]).image), "square.and.arrow.up")
        XCTAssertEqual(nameOf(parent(["exportCustomQueryResultAsFormat:"]).image), "square.and.arrow.up")
        XCTAssertEqual(nameOf(parent(["toggleColumnView:", "toggleColumnView:"]).image), "eye")
        XCTAssertEqual(nameOf(parent(["sortFavorites:", "sortFavorites:", "reverseSortFavorites:"]).image), "arrow.up.arrow.down")
        XCTAssertEqual(nameOf(parent(["apply:", "apply:"]).image), "line.3.horizontal.decrease")
        XCTAssertNil(parent(["removeTable:", "renameTable:"]).image)                  // mixed
        XCTAssertNil(parent(["executeBundleItemForDataTable:"]).image)                 // Bundles
        XCTAssertNil(parent(["exportSelectedTablesAs:", "somethingNew:"]).image)        // one unknown
        XCTAssertNil(parent([]).image)                                                 // empty
        // The rows of a parent-only group get none of their own.
        let viewColumns = parent(["toggleColumnView:"])
        XCTAssertNil(viewColumns.submenu?.items.first?.image)
    }

    func testSkipsMainMenu() {
        let mainMenu = NSMenu(title: "Main")
        let editItem = item("Edit", nil)
        let edit = NSMenu(title: "Edit")
        let rename = item("Rename Table...", "renameTable:")
        let formatItem = item("Format", nil)
        let format = NSMenu(title: "Format")
        let remove = item("Remove Table...", "removeTable:")
        edit.addItem(rename)
        edit.addItem(formatItem)
        edit.setSubmenu(format, for: formatItem)
        format.addItem(remove)
        mainMenu.addItem(editItem)
        mainMenu.setSubmenu(edit, for: editItem)

        SAClaudeMenuGlyphs.apply(to: mainMenu, imageFor: image, mainMenu: mainMenu)
        SAClaudeMenuGlyphs.apply(to: edit, imageFor: image, mainMenu: mainMenu)
        SAClaudeMenuGlyphs.apply(to: format, imageFor: image, mainMenu: mainMenu)

        XCTAssertNil(rename.image)
        XCTAssertNil(remove.image)
        XCTAssertNil(formatItem.image)

        // The same menu outside the main menu is filled.
        let context = NSMenu()
        let contextRename = item("Rename Table...", "renameTable:")
        context.addItem(contextRename)
        SAClaudeMenuGlyphs.apply(to: context, imageFor: image, mainMenu: mainMenu)
        XCTAssertEqual(nameOf(contextRename.image), "pencil")
    }

    func testMissingImageLeavesItemAlone() {
        let menu = NSMenu()
        let rename = item("Rename Table...", "renameTable:")
        menu.addItem(rename)

        SAClaudeMenuGlyphs.apply(to: menu, imageFor: { _ in nil }, mainMenu: nil)

        XCTAssertNil(rename.image)
        XCTAssertTrue(isAutomatic(rename))
    }
}
