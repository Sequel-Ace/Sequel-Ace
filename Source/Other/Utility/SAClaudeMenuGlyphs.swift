//
//  SAClaudeMenuGlyphs.swift
//  Sequel Ace
//
//  The glyphs of the native right-click menus (and the main window's gear
//  pull-downs) in the Claude look: one map from a menu item's action selector
//  to an outline SF Symbol, and `apply`, which fills a menu's empty item
//  images from it. An image the code already set is never replaced; items
//  whose action isn't in the map (Bundles, cell filter operators, history
//  entries, anything new) get none. Titles, order, shortcuts and validation
//  are untouched. Pure (AppKit types only, no app state): built into the app
//  and the Unit Tests targets. The pass that runs it before each menu opens
//  is SAClaudeMenuGlyphPass.
//

import AppKit

enum SAClaudeMenuGlyphs {

    /// Action selector → outline SF Symbol, from the surveyed menus: table list (and the sidebar gear), Content and
    /// query-result grids, Structure fields / indexes, Relations, Triggers, the query editor, the connection screen's
    /// favourites (outline, gear, card grid), window tab chips, the filter bar and the query "Export Result" gear.
    private static let byAction: [String: String] = [
        // Copy
        "copy:": "doc.on.doc",                      // grids' Copy rows (tags 2001–2004), cell-value copies, text views
        "copyTableName:": "doc.on.doc",
        "copyCreateTableSyntax:": "doc.on.doc",
        "copyAsRTF": "doc.on.doc",
        "copyConnectionString:": "doc.on.doc",
        "copyPreviewClause:": "doc.on.doc",
        // Edit
        "cut:": "scissors",
        "paste:": "doc.on.clipboard",
        "pasteAsPlainText:": "doc.on.clipboard",
        // Rename / edit
        "renameTable:": "pencil",
        "renameNode:": "pencil",
        "editTrigger:": "pencil",
        // Add / duplicate
        "addRow:": "plus",
        "addEmptyFilterRow": "plus",
        "addEmptyFilterGroup": "plus.rectangle.on.rectangle",
        "copyTable:": "plus.square.on.square",      // Duplicate Table…
        "duplicateRow:": "plus.square.on.square",
        "duplicateField:": "plus.square.on.square",
        "duplicateFavorite:": "plus.square.on.square",
        // Truncate / delete
        "truncateTable:": "eraser",
        "removeTable:": "trash",
        "removeRow:": "trash",
        "removeField:": "trash",
        "removeIndex:": "trash",
        "removeRelation:": "trash",
        "removeTrigger:": "trash",
        "removeNode:": "trash",
        // Export / import
        "exportSelectedTablesAs:": "square.and.arrow.up",
        "exportCustomQueryResultAsFormat:": "square.and.arrow.up",
        "exportFavorites:": "square.and.arrow.up",
        "importFavorites:": "square.and.arrow.down",
        // Windows and tabs
        "openTableInNewTab:": "macwindow.badge.plus",
        "openTableInNewWindow:": "macwindow",
        "moveTabToNewWindow:": "macwindow",
        "mergeAllWindows:": "rectangle.stack",
        "closeTab:": "xmark",
        "closeOtherTabs:": "xmark.circle",
        // Table and query tools
        "togglePinTable:": "pin",
        "showCreateTableSyntax:": "chevron.left.forwardslash.chevron.right",
        "showOptimizedFieldType:": "wand.and.stars",
        "resetAutoIncrement:": "arrow.counterclockwise",
        "showMySQLHelpForCurrentWord:": "questionmark.circle",
        "selectCurrentQuery:": "selection.pin.in.out",
        "makeSelectedFavoriteDefault:": "star",
        // Refresh / reload
        "refresh:": "arrow.clockwise",
        "refreshTables:": "arrow.clockwise",
        "reloadTable:": "arrow.clockwise",
    ]

    /// Submenus whose rows are choices rather than commands (column toggles, sort keys, filter operators): the rows
    /// get no glyph, their parent row (View Columns, Sort By, Filter by Selected Value) gets this one.
    private static let parentOnly: [String: String] = [
        "toggleColumnView:": "eye",
        "sortFavorites:": "arrow.up.arrow.down",
        "reverseSortFavorites:": "arrow.up.arrow.down",
        "apply:": "line.3.horizontal.decrease",     // SACellFilterAction's operators
    ]

    /// Every symbol name the map can hand out (the tests check each exists).
    static var allSymbolNames: Set<String> { Set(byAction.values).union(parentOnly.values) }

    /// The glyph for an item with this action, or nil when it gets none. `title` is there for an action whose glyph
    /// would depend on the item; none in the surveyed menus does (every Copy row is `doc.on.doc`).
    static func symbol(forAction selector: String, title: String) -> String? {
        byAction[selector]
    }

    /// Gives each item of `menu` and its submenus whose image is empty and whose action maps the glyph `imageFor`
    /// returns for it (shown, on macOS 27, whatever the system's menu-icon setting: `preferredImageVisibility`);
    /// a submenu's parent row takes the glyph all its rows share. Never replaces an image: an item that already has
    /// one keeps it, except that AppKit's own image for a mapped standard action (Copy, Cut, Paste) is shown too.
    /// Does nothing to the main menu bar's menus (any menu whose top supermenu is `mainMenu`).
    static func apply(to menu: NSMenu, imageFor: (String) -> NSImage?, mainMenu: NSMenu? = NSApp?.mainMenu) {
        if let mainMenu, topMenu(of: menu) === mainMenu { return }
        fill(menu, imageFor: imageFor)
    }

    private static func fill(_ menu: NSMenu, imageFor: (String) -> NSImage?) {
        for item in menu.items where !item.isSeparatorItem {
            if let submenu = item.submenu {
                fill(submenu, imageFor: imageFor)
                if item.image == nil, let name = sharedSymbol(of: submenu) {
                    setImage(of: item, to: name, imageFor: imageFor)
                }
                continue
            }
            guard let action = item.action,
                  let name = symbol(forAction: NSStringFromSelector(action), title: item.title) else { continue }
            if item.image == nil {
                setImage(of: item, to: name, imageFor: imageFor)
            } else if isAppKitsOwnImage(of: item) {
                show(item)
            }
        }
    }

    /// The one glyph every command row of `submenu` maps to (directly or as a parent-only group), else nil.
    private static func sharedSymbol(of submenu: NSMenu) -> String? {
        let rows = submenu.items.filter { !$0.isSeparatorItem && $0.submenu == nil && $0.action != nil }
        guard !rows.isEmpty else { return nil }
        var shared: String?
        for row in rows {
            let selector = NSStringFromSelector(row.action!)
            guard let name = symbol(forAction: selector, title: row.title) ?? parentOnly[selector],
                  shared == nil || shared == name else { return nil }
            shared = name
        }
        return shared
    }

    private static func setImage(of item: NSMenuItem, to name: String, imageFor: (String) -> NSImage?) {
        guard let image = imageFor(name) else { return }
        item.image = image
        show(item)
    }

    /// macOS 27 hides menu item images unless the system's setting shows them (`.automatic`); a glyph of this map
    /// is shown regardless, as the Claude look asks.
    private static func show(_ item: NSMenuItem) {
        if #available(macOS 27.0, *) { item.preferredImageVisibility = .visible }
    }

    /// Whether the item's image is the one AppKit gives its action by itself (a fresh item with the same title and
    /// action has an image that looks the same), rather than one the code set.
    private static func isAppKitsOwnImage(of item: NSMenuItem) -> Bool {
        guard let image = item.image, let action = item.action,
              let own = NSMenuItem(title: item.title, action: action, keyEquivalent: "").image else { return false }
        return own.accessibilityDescription == image.accessibilityDescription && own.size == image.size
    }

    private static func topMenu(of menu: NSMenu) -> NSMenu {
        var top = menu
        while let supermenu = top.supermenu { top = supermenu }
        return top
    }
}
