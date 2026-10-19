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
//  is SAClaudeMenuGlyphPass; which menus it runs on (the main document
//  windows' and the utility windows' named in `utilityOwnerClasses`, with
//  their sheets) is `shouldApply`.
//

import AppKit

enum SAClaudeMenuGlyphs {

    /// Action selector → outline SF Symbol, from the surveyed menus: table list (and the sidebar gear), Content and
    /// query-result grids, Structure fields / indexes, Relations, Triggers, the query editor, the connection screen's
    /// favourites (outline, gear, card grid), window tab chips, the filter bar and the query "Export Result" gear; and the
    /// utility windows' gear and right-click menus (User Manager, Process List, Server Variables, Query Favorites and
    /// Content Filter managers, Bundle Editor).
    private static let byAction: [String: String] = [
        // Copy
        "copy:": "doc.on.doc",                      // grids' Copy rows (tags 2001–2004), cell-value copies, text views
        "copyTableName:": "doc.on.doc",
        "copyCreateTableSyntax:": "doc.on.doc",
        "copyAsRTF": "doc.on.doc",
        "copyConnectionString:": "doc.on.doc",
        "copyPreviewClause:": "doc.on.doc",
        "copyServerVariableName:": "doc.on.doc",    // Server Variables
        "copyServerVariableValue:": "doc.on.doc",
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
        "duplicateQueryFavorite:": "plus.square.on.square", // Query Favorites manager
        "duplicateContentFilter:": "plus.square.on.square", // Content Filter manager
        "duplicateCommandBundle:": "plus.square.on.square", // Bundle Editor
        "addHost:": "plus",                                 // User Manager
        // Truncate / delete
        "truncateTable:": "eraser",
        "removeTable:": "trash",
        "removeRow:": "trash",
        "removeField:": "trash",
        "removeIndex:": "trash",
        "removeRelation:": "trash",
        "removeTrigger:": "trash",
        "removeNode:": "trash",
        "removeUser:": "trash",                     // User Manager
        "removeHost:": "trash",
        "removeQueryFavorite:": "trash",            // Query Favorites manager
        "removeAllQueryFavorites:": "trash",
        "removeContentFilter:": "trash",            // Content Filter manager
        "removeCommandBundle:": "trash",            // Bundle Editor
        // Export / import
        "exportSelectedTablesAs:": "square.and.arrow.up",
        "exportCustomQueryResultAsFormat:": "square.and.arrow.up",
        "exportFavorites:": "square.and.arrow.up",      // connection gear and the Query Favorites manager's
        "exportContentFilter:": "square.and.arrow.up",
        "saveBundle:": "square.and.arrow.up",           // Bundle Editor's Export Bundle…
        "importFavorites:": "square.and.arrow.down",
        "importFavoritesByAdding:": "square.and.arrow.down",
        "importFavoritesByReplacing:": "square.and.arrow.down",
        "importContentFilterByAdding:": "square.and.arrow.down",
        // Save to a file
        "saveFavoriteToFile:": "arrow.down.doc",        // Query Favorites manager
        "saveServerProcesses:": "arrow.down.doc",       // Process List's Save As…
        "saveServerVariables:": "arrow.down.doc",       // Server Variables' Save As…
        // Refresh / reload
        "refresh:": "arrow.clockwise",                  // User Manager gear
        "refreshProcessList:": "arrow.clockwise",
        "reloadBundles:": "arrow.clockwise",
        // Process List
        "killProcessQuery:": "stop.circle",
        "killProcessConnection:": "xmark.octagon",
        // Bundle Editor
        "revealCommandBundleInFinder:": "folder",
        "undeleteDefaultBundles:": "arrow.uturn.backward",
        "displayBundleMetaInfo:": "info.circle",
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
    ]

    /// Submenus whose rows are choices rather than commands (column toggles, sort keys, filter operators): the rows
    /// get no glyph, their parent row (View Columns, Sort By, Filter by Selected Value) gets this one.
    private static let parentOnly: [String: String] = [
        "toggleColumnView:": "eye",
        "sortFavorites:": "arrow.up.arrow.down",
        "reverseSortFavorites:": "arrow.up.arrow.down",
        "apply:": "line.3.horizontal.decrease",     // SACellFilterAction's operators
        "setAutoRefreshInterval:": "timer",         // Process List's Auto Refresh Interval (and its Custom… row)
        "setCustomAutoRefreshInterval:": "timer",
    ]

    /// The weight of a uniform menu glyph (`SAClaudeMenuGlyphPass.uniformImage`) drawn at `scale` × the point size a circle
    /// glyph gets: a symbol drawn smaller (a tall one, doc.on.doc) gets thinner strokes, so it is drawn heavier to match.
    static func uniformWeight(scale: CGFloat) -> NSFont.Weight {
        if scale >= 0.92 { return .regular }
        if scale >= 0.84 { return .medium }
        return .semibold
    }

    /// Every symbol name the map can hand out (the tests check each exists).
    static var allSymbolNames: Set<String> { Set(byAction.values).union(parentOnly.values) }

    /// The glyph for an item with this action, or nil when it gets none. `title` is there for an action whose glyph
    /// would depend on the item; none in the surveyed menus does (every Copy row is `doc.on.doc`).
    static func symbol(forAction selector: String, title: String) -> String? {
        byAction[selector]
    }

    /// The owners (window controller or delegate) of the utility windows whose menus get glyphs too, in the window and
    /// in its sheets: the User Manager, Process List, Server Variables, the Query Favorites and Content Filter managers,
    /// the Navigator, the Bundle Editor and the Advanced Filter panel. Not every window the sheet styler skins: Settings,
    /// Export, Import, the field editor and the table / database sheets keep their menus as they are.
    static let utilityOwnerClasses: Set<String> = [
        "SPUserManager", "SPProcessListController", "SPServerVariablesController", "SPQueryFavoriteManager",
        "SPContentFilterManager", "SPNavigatorController", "SPBundleEditorController", "SPFilterTableController",
    ]

    /// Whether the pass glyphs a menu that is opening: never the main menu bar's menus, nor a window with a sheet attached
    /// (the sheet takes the menus); then a main document window (the database window, whose connection screen is the same
    /// window), or a window or sheet owned by one of `utilityOwnerClasses`. `ownerClasses` are the class names
    /// (`NSStringFromClass`, module-qualified or not) of the window's controller and delegate and those of the windows it
    /// is a sheet of. Menus opened in other sheets, panels, Settings and the Console stay as they are.
    static func shouldApply(isMainMenu: Bool, isMainDocumentWindow: Bool, hasAttachedSheet: Bool, ownerClasses: [String] = []) -> Bool {
        guard !isMainMenu, !hasAttachedSheet else { return false }
        if isMainDocumentWindow { return true }
        return ownerClasses.contains { utilityOwnerClasses.contains(SAClaudeSheetTargeting.unqualified($0)) }
    }

    /// Whether `menu` is the main menu bar's or one of its submenus (its top supermenu is `mainMenu`).
    static func isInMainMenu(_ menu: NSMenu, mainMenu: NSMenu?) -> Bool {
        guard let mainMenu else { return false }
        return topMenu(of: menu) === mainMenu
    }

    /// Gives each item of `menu` and its submenus whose image is empty and whose action maps the glyph `imageFor`
    /// returns for it (shown, on macOS 27, whatever the system's menu-icon setting: `preferredImageVisibility`);
    /// a submenu's parent row takes the glyph all its rows share. Never replaces an image: an item that already has
    /// one keeps it, except that AppKit's own image for a mapped standard action (Copy, Cut, Paste) is shown too.
    /// Does nothing to the main menu bar's menus (any menu whose top supermenu is `mainMenu`).
    static func apply(to menu: NSMenu, imageFor: (String) -> NSImage?, mainMenu: NSMenu? = NSApp?.mainMenu) {
        if isInMainMenu(menu, mainMenu: mainMenu) { return }
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
        let rows = submenu.items.filter { !$0.isSeparatorItem && $0.submenu == nil }
            .compactMap { row in row.action.map { (NSStringFromSelector($0), row.title) } }
        guard !rows.isEmpty else { return nil }
        var shared: String?
        for (selector, title) in rows {
            guard let name = symbol(forAction: selector, title: title) ?? parentOnly[selector],
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
