//
//  SAClaudeQueryCopyAction.swift
//  Sequel Ace
//
//  The four ways the Query tab's results can be copied — the results grid's
//  copy menu items — with the wording the Copy button and its menu use and the
//  remembered default. Shared with the unit tests.
//

import Foundation

enum SAClaudeQueryCopyAction: Int, CaseIterable {
    // Keep in sync with SPEditMenuCopy, …WithColumns, …AsSQL, …AsSQLNoAutoInc in SPCopyTable.m.
    case plain = 2001, withColumnNames = 2002, sqlInsert = 2003, sqlInsertNoAutoIncrement = 2004

    /// The last action used on the Query results, as its tag.
    static let defaultsKey = "ClaudeQueryCopyDefaultAction"

    var tag: Int { rawValue }

    /// SQL INSERT needs the result's column definitions.
    var needsColumnDefinitions: Bool { self == .sqlInsert || self == .sqlInsertNoAutoIncrement }

    /// The Copy button menu's wording.
    var menuTitle: String {
        switch self {
        case .plain: return NSLocalizedString("ClaudeCopyMenuPlain", value: "Copy", comment: "Query bar Copy button menu: copy the result rows as tab-separated text")
        case .withColumnNames: return NSLocalizedString("ClaudeCopyMenuWithColumnNames", value: "Copy with column names", comment: "Query bar Copy button menu: copy the result rows with a header row of column names")
        case .sqlInsert: return NSLocalizedString("ClaudeCopyMenuSQLInsert", value: "Copy as SQL INSERT", comment: "Query bar Copy button menu: copy the result rows as SQL INSERT statements")
        case .sqlInsertNoAutoIncrement: return NSLocalizedString("ClaudeCopyMenuSQLInsertNoAutoInc", value: "Copy as SQL INSERT (no auto_inc)", comment: "Query bar Copy button menu: copy the result rows as SQL INSERT statements without the auto-increment column")
        }
    }

    /// The button's label for the action.
    var shortLabel: String {
        switch self {
        case .plain: return NSLocalizedString("ClaudeCopyLabelPlain", value: "Copy", comment: "Query bar Copy button label: copies the result rows")
        case .withColumnNames: return NSLocalizedString("ClaudeCopyLabelWithColumnNames", value: "Copy with names", comment: "Query bar Copy button label: copies the result rows with column names (keep short)")
        case .sqlInsert: return NSLocalizedString("ClaudeCopyLabelSQLInsert", value: "Copy as INSERT", comment: "Query bar Copy button label: copies the result rows as SQL INSERT statements (keep short)")
        case .sqlInsertNoAutoIncrement: return NSLocalizedString("ClaudeCopyLabelSQLInsertNoAutoInc", value: "Copy INSERT (no auto_inc)", comment: "Query bar Copy button label: copies the result rows as SQL INSERT without the auto-increment column (keep short)")
        }
    }

    /// Shown on the button for a moment after a copy.
    static var copiedLabel: String {
        NSLocalizedString("ClaudeCopyLabelCopied", value: "Copied", comment: "Query bar Copy button label shown briefly after copying")
    }

    static func storedDefault(in defaults: UserDefaults) -> SAClaudeQueryCopyAction {
        (defaults.object(forKey: defaultsKey) as? Int).flatMap(SAClaudeQueryCopyAction.init(rawValue:)) ?? .plain
    }

    static func store(_ action: SAClaudeQueryCopyAction, in defaults: UserDefaults) {
        guard storedDefault(in: defaults) != action || defaults.object(forKey: defaultsKey) == nil else { return }
        defaults.set(action.tag, forKey: defaultsKey)
    }

    /// What the button copies, e.g. "Copy 5 rows with column names" or "Copy 2 selected rows as SQL INSERT".
    func scopeDescription(selectedRows: Int, totalRows: Int) -> String {
        let rows: String
        if selectedRows > 0 {
            rows = selectedRows == 1
                ? NSLocalizedString("ClaudeCopyScopeOneSelected", value: "Copy 1 selected row", comment: "Query bar Copy button tooltip: one selected result row will be copied")
                : String(format: NSLocalizedString("ClaudeCopyScopeSelected", value: "Copy %ld selected rows", comment: "Query bar Copy button tooltip: this many selected result rows will be copied"), selectedRows)
        } else {
            rows = totalRows == 1
                ? NSLocalizedString("ClaudeCopyScopeOneAll", value: "Copy 1 row", comment: "Query bar Copy button tooltip: the result's only row will be copied")
                : String(format: NSLocalizedString("ClaudeCopyScopeAll", value: "Copy %ld rows", comment: "Query bar Copy button tooltip: all of this many result rows will be copied"), totalRows)
        }
        switch self {
        case .plain: return rows
        case .withColumnNames: return rows + NSLocalizedString("ClaudeCopyScopeSuffixColumnNames", value: " with column names", comment: "Query bar Copy button tooltip suffix (leading space): rows are copied with column names")
        case .sqlInsert: return rows + NSLocalizedString("ClaudeCopyScopeSuffixSQLInsert", value: " as SQL INSERT", comment: "Query bar Copy button tooltip suffix (leading space): rows are copied as SQL INSERT")
        case .sqlInsertNoAutoIncrement: return rows + NSLocalizedString("ClaudeCopyScopeSuffixSQLInsertNoAutoInc", value: " as SQL INSERT (no auto_inc)", comment: "Query bar Copy button tooltip suffix (leading space): rows are copied as SQL INSERT without the auto-increment column")
        }
    }

    /// The Copy button menu's footer line.
    static func footer(selectedRows: Int, totalRows: Int) -> String {
        if selectedRows > 0 {
            return selectedRows == 1
                ? NSLocalizedString("ClaudeCopyFooterOneSelected", value: "Copies 1 selected row", comment: "Query bar Copy button menu footer: one selected row will be copied")
                : String(format: NSLocalizedString("ClaudeCopyFooterSelected", value: "Copies %ld selected rows", comment: "Query bar Copy button menu footer: this many selected rows will be copied"), selectedRows)
        }
        return totalRows == 1
            ? NSLocalizedString("ClaudeCopyFooterOneAll", value: "Copies 1 row · nothing selected", comment: "Query bar Copy button menu footer: no selection, so the result's only row will be copied")
            : String(format: NSLocalizedString("ClaudeCopyFooterAll", value: "Copies %ld rows · nothing selected", comment: "Query bar Copy button menu footer: no selection, so all of this many rows will be copied"), totalRows)
    }

    /// Why the action can't run now, or nil when it can.
    func unavailableReason(totalRows: Int, hasColumnDefinitions: Bool) -> String? {
        if totalRows <= 0 {
            return NSLocalizedString("ClaudeCopyUnavailableNoRows", value: "No rows to copy", comment: "Query bar Copy button tooltip when the result has no rows")
        }
        if needsColumnDefinitions && !hasColumnDefinitions {
            return NSLocalizedString("ClaudeCopyUnavailableNoColumns", value: "SQL INSERT needs a result with column details", comment: "Query bar Copy button tooltip when the result has no column definitions to build SQL INSERT statements from")
        }
        return nil
    }
}
