//
//  SAClaudeToolbarLayout.swift
//  Sequel Ace
//
//  The main window toolbar's items as the Claude look arranges them: the
//  identifiers (unchanged, so saved layouts load), the default order, which
//  views are selectable, the glyph per item, the View ▸ Toolbar submenu's
//  wording, and where a re-added item goes. Shared with the unit tests.
//

import AppKit

enum SAClaudeToolbarLayout {
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

    /// Database on the left, the views centred, the rest on the right.
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
        case database: return NSLocalizedString("ClaudeToolbarMenuDatabase", value: "Database", comment: "View ▸ Toolbar submenu: show/hide the database picker")
        case structure: return NSLocalizedString("ClaudeToolbarMenuStructure", value: "Structure", comment: "View ▸ Toolbar submenu: show/hide the Structure view button")
        case content: return NSLocalizedString("ClaudeToolbarMenuContent", value: "Content", comment: "View ▸ Toolbar submenu: show/hide the Content view button")
        case relations: return NSLocalizedString("ClaudeToolbarMenuRelations", value: "Relations", comment: "View ▸ Toolbar submenu: show/hide the Relations view button")
        case triggers: return NSLocalizedString("ClaudeToolbarMenuTriggers", value: "Triggers", comment: "View ▸ Toolbar submenu: show/hide the Triggers view button")
        case tableInfo: return NSLocalizedString("ClaudeToolbarMenuTableInfo", value: "Table info", comment: "View ▸ Toolbar submenu: show/hide the Table Info view button")
        case query: return NSLocalizedString("ClaudeToolbarMenuQuery", value: "Query", comment: "View ▸ Toolbar submenu: show/hide the Query view button")
        case history: return NSLocalizedString("ClaudeToolbarMenuHistory", value: "History", comment: "View ▸ Toolbar submenu: show/hide the back/forward history buttons")
        case recordView: return NSLocalizedString("ClaudeToolbarMenuRecordView", value: "Record view", comment: "View ▸ Toolbar submenu: show/hide the Record View button")
        case users: return NSLocalizedString("ClaudeToolbarMenuUsers", value: "Users", comment: "View ▸ Toolbar submenu: show/hide the Users button")
        case showConsole: return NSLocalizedString("ClaudeToolbarMenuConsole", value: "Console", comment: "View ▸ Toolbar submenu: show/hide the Console button")
        case clearConsole: return NSLocalizedString("ClaudeToolbarMenuClearConsole", value: "Clear console", comment: "View ▸ Toolbar submenu: show/hide the Clear Console button")
        default: return identifier
        }
    }

    /// The Claude glyph an item draws, or nil for items with their own control (database, history) and spaces.
    static func glyph(for identifier: String) -> SAClaudeGlyph? {
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

    /// The database pill: glyph, gaps, name and chevron, between 120 and 220pt.
    static func databasePillWidth(textWidth: CGFloat) -> CGFloat {
        min(220, max(120, ceil(textWidth) + 56))
    }
}
