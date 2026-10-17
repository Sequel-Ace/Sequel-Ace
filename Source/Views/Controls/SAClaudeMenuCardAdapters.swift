//
//  SAClaudeMenuCardAdapters.swift
//  Sequel Ace
//
//  What each main-window dropdown tells the Claude menu card (`SAClaudeMenuCardPresenter`): which of its
//  NSMenu's items become rows, headers and footer actions, their glyphs, search, and palette. The menus
//  stay the source of truth; adapters only read them. App target only.
//

import AppKit

/// The toolbar database pop-up: search, "Your databases" then "System", the current database ticked,
/// Add Database… and Refresh Databases as the footer. Follows Sequel Ace's appearance like the toolbar pills.
final class SAClaudeDatabaseMenuAdapter: SAClaudeMenuCardAdapter {
    private weak var popup: NSPopUpButton?

    init(popup: NSPopUpButton) {
        self.popup = popup
    }

    var hasSearch: Bool { true }

    var searchPlaceholder: String {
        NSLocalizedString("ClaudeMenuFindDatabase", value: "Find a database", comment: "Claude menu card: placeholder of the database card's search field")
    }

    func entries(for menu: NSMenu) -> [SAClaudeMenuEntry]? {
        SAClaudeMenuCardModel.databaseEntries(
            from: menu,
            selectedIndex: popup?.indexOfSelectedItem ?? -1,
            userHeader: NSLocalizedString("ClaudeMenuYourDatabases", value: "Your databases",
                                          comment: "Claude menu card: database card section header above the user's databases"),
            systemHeader: NSLocalizedString("ClaudeMenuSystemDatabases", value: "System",
                                            comment: "Claude menu card: database card section header above the system databases (mysql, sys, …)"))
    }

    func palette(for control: NSView) -> SAClaudeMenuCardPalette { .app(for: control) }
}

/// A back/forward segment's history menu: its entries as they are (newest first, "(Filtered)" kept), no search,
/// no footer, no glyphs. Follows Sequel Ace's appearance like the toolbar pills.
final class SAClaudeHistoryEntriesMenuAdapter: SAClaudeMenuCardAdapter {
    static let shared = SAClaudeHistoryEntriesMenuAdapter()

    var hasSearch: Bool { false }
    var searchPlaceholder: String { "" }

    func entries(for menu: NSMenu) -> [SAClaudeMenuEntry]? {
        SAClaudeMenuCardModel.entries(from: menu)
    }

    func palette(for control: NSView) -> SAClaudeMenuCardPalette { .app(for: control) }
}

// MARK: - Query editor bar (editor theme's palette, like the ⋯ card)

/// The Query History pull-down: search, one row per query (the query in mono, up to two lines), Copy History
/// (⌥ Save History…) and Clear History as the footer. The native search field item is not shown: it is cleared,
/// with the items its filter hid, so the card lists every query.
final class SAClaudeQueryHistoryMenuAdapter: SAClaudeMenuCardAdapter {
    static let shared = SAClaudeQueryHistoryMenuAdapter()

    var hasSearch: Bool { true }

    var searchPlaceholder: String {
        NSLocalizedString("ClaudeMenuSearchHistory", value: "Search history", comment: "Claude menu card: placeholder of the query history card's search field")
    }

    func entries(for menu: NSMenu) -> [SAClaudeMenuEntry]? {
        SAClaudeMenuCardModel.resetNativeSearch(in: menu)
        return SAClaudeMenuCardModel.queryHistoryEntries(from: menu)
    }

    func palette(for control: NSView) -> SAClaudeMenuCardPalette { .editor() }
}

/// The Query Favorites pull-down: search, the per-file then "Global" sections, two-line favourite rows (name and
/// trigger chip, then the query), the save/edit actions as the footer. The native search field is cleared as above.
final class SAClaudeQueryFavoritesMenuAdapter: SAClaudeMenuCardAdapter {
    static let shared = SAClaudeQueryFavoritesMenuAdapter()

    var hasSearch: Bool { true }

    var searchPlaceholder: String {
        NSLocalizedString("ClaudeMenuSearchFavorites", value: "Search favorites", comment: "Claude menu card: placeholder of the query favorites card's search field")
    }

    func entries(for menu: NSMenu) -> [SAClaudeMenuEntry]? {
        SAClaudeMenuCardModel.resetNativeSearch(in: menu)
        return SAClaudeMenuCardModel.queryFavoritesEntries(from: menu)
    }

    func palette(for control: NSView) -> SAClaudeMenuCardPalette { .editor() }
}

/// The Run split button's chevron: the run menu's items in order, with glyphs and shortcuts. No search.
final class SAClaudeRunMenuAdapter: SAClaudeMenuCardAdapter {
    static let shared = SAClaudeRunMenuAdapter()

    var hasSearch: Bool { false }
    var searchPlaceholder: String { "" }

    func entries(for menu: NSMenu) -> [SAClaudeMenuEntry]? { SAClaudeMenuCardModel.runEntries(from: menu) }

    func palette(for control: NSView) -> SAClaudeMenuCardPalette { .editor() }
}

/// The Copy split button's chevron: the four copy actions, the last used ticked, the row-count note as the footer.
final class SAClaudeCopyMenuAdapter: SAClaudeMenuCardAdapter {
    static let shared = SAClaudeCopyMenuAdapter()

    var hasSearch: Bool { false }
    var searchPlaceholder: String { "" }

    func entries(for menu: NSMenu) -> [SAClaudeMenuEntry]? { SAClaudeMenuCardModel.copyEntries(from: menu) }

    func palette(for control: NSView) -> SAClaudeMenuCardPalette { .editor() }
}

// MARK: - Split buttons

extension SPComboPopupButton {
    /// Whether `event` is on the chevron part: the same test SPComboPopupButtonCell's -trackMouse:… uses.
    func isOnChevron(_ event: NSEvent) -> Bool {
        convert(event.locationInWindow, from: nil).x + CGFloat(lineOffset) >= frame.width
    }

    /// ↓ with no ⌘/⌃/⌥: the key that opens a split button's card (Space/Return keep the main action).
    static func opensCard(_ event: NSEvent) -> Bool {
        event.keyCode == 125 && event.modifierFlags.intersection([.command, .control, .option]).isEmpty
    }

    /// Opens the card for the button's menu; `isOpen` is set while it is shown (the chevron's open drawing).
    func showSplitCard(adapter: SAClaudeMenuCardAdapter, isOpen: @escaping (Bool) -> Void) -> Bool {
        guard isEnabled, let menu else { return false }
        let presenter = SAClaudeMenuCardPresenter.shared
        guard presenter.show(menu: menu, from: self, adapter: adapter, onClose: { isOpen(false) }) else { return false }
        if presenter.shownControl === self { isOpen(true) }
        return true
    }
}
