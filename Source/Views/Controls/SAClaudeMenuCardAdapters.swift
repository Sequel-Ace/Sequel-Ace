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
