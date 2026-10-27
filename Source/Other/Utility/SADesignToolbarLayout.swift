//
//  SADesignToolbarLayout.swift
//  Sequel Ace
//
//  The main window toolbar's items as the design system arranges them: the
//  identifiers (unchanged, so saved layouts load), the default order, which
//  views are selectable, the glyph per item, the View ▸ Toolbar submenu's
//  wording, and where a re-added item goes. Shared with the unit tests.
//

import AppKit

enum SADesignToolbarLayout {
    // Keep in sync with "Main window toolbar" in SPConstants.m and SARecordViewToolbarSupport.
    static let database = "DatabaseSelectToolbarItemIdentifier"
    static let history = "HistoryNavigationToolbarItemIdentifier"
    static let showConsole = "ShowConsoleIdentifier"
    static let clearConsole = "ClearConsoleIdentifier"
    static let structure = "SwitchToTableStructureToolbarItemIdentifier"
    static let content = "SwitchToTableContentToolbarItemIdentifier"
    static let query = "SwitchToRunQueryToolbarItemIdentifier"
    static let tableInfo = "SwitchToTableInfoToolbarItemIdentifier"
    static let relations = "SwitchToTableRelationsToolbarItemIdentifier"
    static let triggers = "SwitchToTableTriggersToolbarItemIdentifier"
    static let users = "SwitchToUserManagerToolbarItemIdentifier"
    static let recordView = "RecordViewToolbarItemIdentifier"
    static let flexibleSpace = NSToolbarItem.Identifier.flexibleSpace.rawValue
    static let space = NSToolbarItem.Identifier.space.rawValue

    /// Database on the left, the views centered, the rest on the right.
    static let defaultItems = [database, flexibleSpace, structure, content, relations, triggers, tableInfo, query,
                               flexibleSpace, history, recordView, users, showConsole]

    /// Whether the Table History item's label draws enabled: as its chevrons do, so while the control and at least one
    /// of its segments are enabled. AppKit dims a custom-view item's label only by the item's own `isEnabled`, which
    /// nothing validated, so the label stayed bright on the connection page while both chevrons were dimmed.
    static func historyLabelEnabled(controlEnabled: Bool, segmentsEnabled: [Bool]) -> Bool {
        controlEnabled && segmentsEnabled.contains(true)
    }

    /// The views the toolbar marks as selected.
    static let selectableItems: Set<String> = [structure, content, query, tableInfo, relations, triggers, recordView]

    /// The View ▸ Toolbar submenu's items, in its order.
    static let menuItems = [database, structure, content, relations, triggers, tableInfo, query,
                            history, recordView, users, showConsole, clearConsole]

    static func menuTitle(for identifier: String) -> String {
        switch identifier {
        // The items' Customize Toolbar names (Console keeps its toolbar label: the palette's "Show Console" would read as
        // a command here).
        case database: return NSLocalizedString("Select Database", comment: "toolbar item for selecting a db")
        case structure: return NSLocalizedString("Structure", comment: "View ▸ Toolbar submenu: show/hide the Structure view button")
        case content: return NSLocalizedString("Content", comment: "View ▸ Toolbar submenu: show/hide the Content view button")
        case relations: return NSLocalizedString("Relations", comment: "View ▸ Toolbar submenu: show/hide the Relations view button")
        case triggers: return NSLocalizedString("Triggers", comment: "View ▸ Toolbar submenu: show/hide the Triggers view button")
        case tableInfo: return NSLocalizedString("Table Info", comment: "View ▸ Toolbar submenu: show/hide the Table Info view button")
        case query: return NSLocalizedString("Query", comment: "View ▸ Toolbar submenu: show/hide the Query view button")
        case history: return NSLocalizedString("Table History", comment: "toolbar item for navigation history")
        case recordView: return NSLocalizedString("Record View", comment: "View ▸ Toolbar submenu: show/hide the Record View button")
        case users: return NSLocalizedString("Users", comment: "View ▸ Toolbar submenu: show/hide the Users button")
        case showConsole: return NSLocalizedString("Console", comment: "View ▸ Toolbar submenu: show/hide the Console button")
        case clearConsole: return NSLocalizedString("Clear Console", comment: "View ▸ Toolbar submenu: show/hide the Clear Console button")
        default: return identifier
        }
    }

    /// The glyph an item draws, or nil for items with their own control (database, history) and spaces.
    static func glyph(for identifier: String) -> SADesignGlyph? {
        switch identifier {
        case structure: return .structure
        case content: return .table
        case relations: return .relations
        case triggers: return .triggers
        case tableInfo: return .info
        case query: return .query
        case recordView: return .recordView
        case users: return .users
        case showConsole: return .console
        case clearConsole: return .clearConsole
        default: return nil
        }
    }

    /// Where to insert `identifier` among the toolbar's `current` items: after the nearest item present that
    /// comes before it in the default order (and any spaces right after that item), else at the start.
    static func insertionIndex(of identifier: String, into current: [String]) -> Int {
        let order = defaultItems.filter { $0 != flexibleSpace && $0 != space } + [clearConsole]
        guard let rank = order.firstIndex(of: identifier) else { return current.count }
        for index in current.indices.reversed() {
            guard let other = order.firstIndex(of: current[index]), other < rank else { continue }
            var insertion = index + 1
            while insertion < current.count, current[insertion] == flexibleSpace || current[insertion] == space { insertion += 1 }
            return insertion
        }
        return 0
    }

    /// The database pill's layout, left to right: inset, glyph, gap, the name, gap, the chevron's box, inset.
    ///
    /// The insets are off the `SASpacing` scale, kept as drawn: the glyph sits 10pt in, as a toolbar button's 20pt
    /// glyph does in its 40pt button, and the name keeps 6pt from the glyph and 2pt from the chevron's box, which keeps
    /// 6pt from the end.
    enum DatabasePill {
        static let glyphInset: CGFloat = 10
        static let glyphSize: CGFloat = 18
        static let titleGap: CGFloat = 6
        static let titleChevronGap: CGFloat = 2
        static let chevronSize: CGFloat = 16
        static let chevronInset: CGFloat = 6
        static let minWidth: CGFloat = 120
        static let maxWidth: CGFloat = 220

        /// Everything in the pill but the name.
        static var chrome: CGFloat { glyphInset + glyphSize + titleGap + titleChevronGap + chevronSize + chevronInset }
    }

    /// The database pill's width for a name `textWidth` wide: the name in full plus the pill's chrome, between
    /// `DatabasePill.minWidth` and `.maxWidth` (only a name wider than the maximum allows is truncated).
    static func databasePillWidth(textWidth: CGFloat) -> CGFloat {
        min(DatabasePill.maxWidth, max(DatabasePill.minWidth, ceil(textWidth) + DatabasePill.chrome))
    }
}
