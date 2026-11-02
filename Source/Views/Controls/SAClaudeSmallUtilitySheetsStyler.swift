//
//  SAClaudeSmallUtilitySheetsStyler.swift
//  Sequel Ace
//
//  The smaller utility windows in the Claude look (spec 2026-10-18-claude-utility-windows-design.md, section D), each
//  claimed by identity (its controller's outlet is the window) on top of the generic sheet skin:
//
//  - The Advanced Filter panel (`SPFilterTableController`): the filter table in the Claude grid look, the divider a
//    hairline, the WHERE clause framed, Filter the accent primary; its Default Operator sheet's help a ghost "?".
//  - The Process List's Custom Interval sheet: OK and Cancel regular size on the right margin.
//  - Settings ▸ Appearance's Edit Theme List sheet: the themes list in the Claude grid look and framed, Duplicate and
//    Remove as ghost icons, Close the primary on the right margin; the Enter Name sheet's Save and Cancel likewise.
//
//  App target only.
//

import AppKit

@MainActor
@objc(SAClaudeSmallUtilitySheetsStyler) final class SAClaudeSmallUtilitySheetsStyler: NSObject {

    enum Strings {
        static var duplicateTheme: String { NSLocalizedString("ClaudeThemeListDuplicate", value: "Duplicate theme", comment: "settings : edit theme list sheet : tooltip and accessibility name of the duplicate button under the themes list") }
        static var removeTheme: String { NSLocalizedString("ClaudeThemeListRemove", value: "Remove theme", comment: "settings : edit theme list sheet : tooltip and accessibility name of the remove button under the themes list") }
    }

    private static var claimedKey: UInt8 = 0

    /// Styles `window` if it is one of the windows above (again on every call: each step is idempotent). Also called by
    /// `SPFilterTableController` as its panel loads: a list's class can only be swapped before AppKit first lays its window
    /// out (a portal view then observes the list's layer by KVO, `SAClaudeClassSwap`).
    @objc(claimWindow:) static func claim(_ window: NSWindow?) {
        guard let window else { return }
        if styleFilterPanel(window) || styleDefaultOperatorSheet(window) || styleCustomInterval(window)
            || styleThemeListSheet(window) || styleEnterNameSheet(window) {
            objc_setAssociatedObject(window, &claimedKey, true, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }

    /// Whether `window` was styled here (the harness and tests).
    static func isClaimed(_ window: NSWindow) -> Bool {
        objc_getAssociatedObject(window, &claimedKey) as? Bool ?? false
    }

    private static func outlet<T>(_ object: NSObject?, _ key: String) -> T? {
        SAClaudeFormRecipes.outlet(object, key)
    }

    /// The controller of `window`'s sheet parent when it is of class `name`.
    private static func parentController(of window: NSWindow, named name: String) -> NSWindowController? {
        guard let controller = window.sheetParent?.windowController, SAClaudeFormOwners.className(of: controller) == name else { return nil }
        return controller
    }

    // MARK: Advanced Filter

    private static func styleFilterPanel(_ window: NSWindow) -> Bool {
        guard let controller = window.windowController, controller.window === window,
              SAClaudeFormOwners.className(of: controller) == "SPFilterTableController",
              let table: NSTableView = outlet(controller, "filterTableView"), table.window === window,
              let split: NSSplitView = outlet(controller, "filterTableSplitView"),
              let filter: NSButton = outlet(controller, "filterTableFilterButton"),
              let whereClause: NSTextView = outlet(controller, "filterTableWhereClause") else { return false }
        let colours = SAClaudeSheetColours.current()
        if let grid = SAClaudeUtilityGridCopyTable.adopt(table) {
            // The swapped (vertical) layout greys the field names' column: the grid's muted text, no grey box.
            grid.state?.prepareCell = { [weak grid] cell, _, _ in
                guard let grid, let textCell = cell as? NSTextFieldCell, let palette = grid.state?.renderer.palette else { return }
                if textCell.drawsBackground, textCell.backgroundColor == NSColor.lightGray {
                    textCell.drawsBackground = false
                    textCell.textColor = palette.null
                }
            }
            if let scrollView = grid.enclosingScrollView { SAClaudeUtilityChrome.frameListOnceShown(scrollView) }
        }
        SAClaudeUtilityChrome.styleSplitDivider(split)
        SAClaudeFormChrome.force(filter, primary: true)
        if let scrollView = whereClause.enclosingScrollView { SAClaudeUtilityChrome.frameList(scrollView, hairline: colours.palette.hairline) }
        return true
    }

    private static func styleDefaultOperatorSheet(_ window: NSWindow) -> Bool {
        guard let controller = parentController(of: window, named: "SPFilterTableController"),
              let sheet: NSWindow = outlet(controller, "filterTableSetDefaultOperatorSheet"), sheet === window,
              let contentView = window.contentView else { return false }
        if let help = SAClaudeFormFind.button(in: contentView, action: "showDefaultOperaterHelp:") {
            SAClaudeUtilityChrome.styleHelpButton(help, label: SAClaudeManagerSheetStyler.Strings.help)
            SAClaudeUtilityChrome.recolourGhostIcons([help], .current())
        }
        return true
    }

    // MARK: Process List

    private static func styleCustomInterval(_ window: NSWindow) -> Bool {
        guard let controller = parentController(of: window, named: "SPProcessListController"),
              let sheet: NSWindow = outlet(controller, "customIntervalWindow"), sheet === window,
              let contentView = window.contentView,
              let ok: NSButton = outlet(controller, "customIntervalButton") else { return false }
        let cancel = SAClaudeFormFind.buttons(in: contentView, action: "closeSheet:").first { $0 !== ok }
        SAClaudeUtilityChrome.layoutFooter([ok] + [cancel].compactMap { $0 }, in: contentView)
        return true
    }

    // MARK: Settings ▸ Appearance

    private static func editorPane(of window: NSWindow) -> NSObject? {
        guard let controller = parentController(of: window, named: "SPPreferenceController") else { return nil }
        return outlet(controller, "editorPreferencePane")
    }

    /// The Edit Theme List sheet's list in the grid look, before AppKit first lays the sheet out (see `claim`): called by
    /// `SPEditorPreferencePane` as it wakes from its nib.
    @objc(prepareThemeList:) static func prepareThemeList(_ table: NSTableView?) {
        if let table { styleThemeList(table) }
    }

    private static func styleThemeList(_ table: NSTableView) {
        guard let grid = SAClaudeUtilityGridTableView.adopt(table) else { return }
        if grid.style != .plain { grid.style = .plain }
        grid.state?.cellPadding = 8
    }

    private static func styleThemeListSheet(_ window: NSWindow) -> Bool {
        guard let pane = editorPane(of: window), let sheet: NSWindow = outlet(pane, "editThemeListWindow"), sheet === window,
              let contentView = window.contentView else { return false }
        if let table: NSTableView = outlet(pane, "editThemeListTable") {
            styleThemeList(table)
            // The list's one column fills it (the XIB's is narrower than the list).
            table.sizeLastColumnToFit()
            if let scrollView = table.enclosingScrollView { SAClaudeUtilityChrome.frameListOnceShown(scrollView) }
        }
        let colours = SAClaudeSheetColours.current()
        var icons: [NSButton] = []
        if let duplicate: NSButton = outlet(pane, "duplicateThemeButton") {
            SAClaudeUtilityChrome.styleGhostIcon(duplicate, symbol: "plus.square.on.square", label: Strings.duplicateTheme)
            icons.append(duplicate)
        }
        if let remove: NSButton = outlet(pane, "removeThemeButton") {
            SAClaudeUtilityChrome.styleGhostIcon(remove, symbol: "minus", label: Strings.removeTheme)
            icons.append(remove)
        }
        SAClaudeUtilityChrome.recolourGhostIcons(icons, colours)
        // Close is the sheet's only button (it answers Escape): the primary.
        if let close = SAClaudeFormFind.button(in: contentView, action: "closePanelSheet:") {
            SAClaudeFormChrome.force(close, primary: true)
            SAClaudeUtilityChrome.layoutFooter([close], in: contentView)
        }
        return true
    }

    private static func styleEnterNameSheet(_ window: NSWindow) -> Bool {
        guard let pane = editorPane(of: window), let sheet: NSWindow = outlet(pane, "enterNameWindow"), sheet === window,
              let contentView = window.contentView, let save: NSButton = outlet(pane, "themeNameSaveButton") else { return false }
        let cancel = SAClaudeFormFind.buttons(in: contentView, action: "closePanelSheet:").first { $0 !== save }
        SAClaudeUtilityChrome.layoutFooter([save] + [cancel].compactMap { $0 }, in: contentView)
        return true
    }
}
