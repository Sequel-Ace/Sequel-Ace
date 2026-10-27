//
//  SADesignMenuCardAdapters.swift
//  Sequel Ace
//
//  What each main-window dropdown tells the menu card (`SADesignMenuCardPresenter`): which of its
//  NSMenu's items become rows, headers and footer actions, their glyphs, search, and palette. The menus
//  stay the source of truth; adapters only read them. Here: the toolbar's database pop-up and
//  back/forward history. App target only.
//

import AppKit

/// The toolbar database pop-up: search, "Your databases" then "System", the current database ticked,
/// Add Database… and Refresh Databases as the footer. Follows Sequel Ace's appearance like the toolbar pills.
final class SADesignDatabaseMenuAdapter: SADesignMenuCardAdapter {
    private weak var popup: NSPopUpButton?

    init(popup: NSPopUpButton) {
        self.popup = popup
    }

    var hasSearch: Bool { true }

    var searchPlaceholder: String {
        NSLocalizedString("Find a database", comment: "Menu card: placeholder of the database card's search field")
    }

    func entries(for menu: NSMenu) -> [SADesignMenuEntry]? {
        SADesignMenuCardModel.databaseEntries(
            from: menu,
            selectedIndex: popup?.indexOfSelectedItem ?? -1,
            userHeader: NSLocalizedString("Your databases",
                                          comment: "Menu card: database card section header above the user's databases"),
            systemHeader: NSLocalizedString("System",
                                            comment: "Menu card: database card section header above the system databases (mysql, sys, …)"))
    }

    func palette(for control: NSView) -> SADesignMenuCardPalette { .app(for: control) }
}

/// A back/forward segment's history menu: its entries as they are (newest first, "(Filtered)" kept), no search,
/// no footer, no glyphs. Follows Sequel Ace's appearance like the toolbar pills.
final class SADesignHistoryEntriesMenuAdapter: SADesignMenuCardAdapter {
    static let shared = SADesignHistoryEntriesMenuAdapter()

    var hasSearch: Bool { false }
    var searchPlaceholder: String { "" }

    func entries(for menu: NSMenu) -> [SADesignMenuEntry]? {
        SADesignMenuCardModel.entries(from: menu)
    }

    func palette(for control: NSView) -> SADesignMenuCardPalette { .app(for: control) }
}
