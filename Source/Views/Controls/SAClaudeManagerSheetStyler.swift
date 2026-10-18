//
//  SAClaudeManagerSheetStyler.swift
//  Sequel Ace
//
//  The Query Favorites and Content Filter managers in the Claude look (spec 2026-10-18-claude-utility-windows-design.md,
//  section D). Both sheets have the same shape: a source list of favourites / filters under "Global" and file headers,
//  with add, remove and gear buttons under it; a form on the right (name, the query or clause in a syntax-coloured text
//  view, Insert Placeholder); Save and Cancel.
//
//  - The list is a Claude sidebar (sidebar fill, selection pills, 28pt rows, the Global / file rows as muted section
//    headers, the tab trigger column muted); its bar buttons are glyph buttons over a hairline; the divider a hairline.
//  - The query / clause editor is framed by a rounded hairline; the help button (Query Favorites) a ghost "?".
//  - Save (Return) the accent primary, Cancel secondary, both regular size on the right margin.
//  The form keeps the XIB's frames and autoresizing; Insert Placeholder is a pill (the generic skin) and, in the Query
//  Favorites manager, sits next to the help button in the footer as the XIB has it.
//
//  Claimed by owner identity (the manager is the window's controller; its outlets are in the XIB's places), from the
//  generic sheet skin's `consider`. Anything missing leaves the sheet in the generic skin. App target only.
//

import AppKit

@MainActor
@objc(SAClaudeManagerSheetStyler) final class SAClaudeManagerSheetStyler: NSObject {

    enum Strings {
        static var addFavorite: String { NSLocalizedString("ClaudeQueryFavoritesAdd", value: "Add query favorite", comment: "query favorites manager : tooltip and accessibility name of the add button under the favorites list") }
        static var removeFavorite: String { NSLocalizedString("ClaudeQueryFavoritesRemove", value: "Remove query favorite", comment: "query favorites manager : tooltip and accessibility name of the remove button under the favorites list") }
        static var favoriteActions: String { NSLocalizedString("ClaudeQueryFavoritesActions", value: "Favorite actions", comment: "query favorites manager : tooltip and accessibility name of the gear menu under the favorites list (Duplicate, Import, Export…)") }
        static var addFilter: String { NSLocalizedString("ClaudeContentFiltersAdd", value: "Add content filter", comment: "content filter manager : tooltip and accessibility name of the add button under the filters list") }
        static var removeFilter: String { NSLocalizedString("ClaudeContentFiltersRemove", value: "Remove content filter", comment: "content filter manager : tooltip and accessibility name of the remove button under the filters list") }
        static var filterActions: String { NSLocalizedString("ClaudeContentFiltersActions", value: "Filter actions", comment: "content filter manager : tooltip and accessibility name of the gear menu under the filters list (Duplicate, Import, Export)") }
        static var help: String { NSLocalizedString("ClaudeUtilityHelp", value: "Help", comment: "utility windows : tooltip and accessibility name of a help (?) button") }
    }

    /// The two managers, by their controllers' names, outlets and actions (keep in sync with SPQueryFavoriteManager.m /
    /// SPContentFilterManager.m and their XIBs).
    struct Kind {
        let controllerClass: String
        let splitKey: String
        let listKey: String
        let textKey: String
        let addAction: Selector
        let closeAction: Selector
        let placeholderKey: String?
        let detailColumns: Set<String>
        let addLabel: String
        let removeLabel: String
        let actionsLabel: String

        static var all: [Kind] {
            [Kind(controllerClass: "SPQueryFavoriteManager", splitKey: "favoritesSplitView", listKey: "favoritesTableView",
                  textKey: "favoriteQueryTextView", addAction: NSSelectorFromString("addQueryFavorite:"),
                  closeAction: NSSelectorFromString("closeQueryManagerSheet:"), placeholderKey: nil, detailColumns: ["tabtrigger"],
                  addLabel: Strings.addFavorite, removeLabel: Strings.removeFavorite, actionsLabel: Strings.favoriteActions),
             Kind(controllerClass: "SPContentFilterManager", splitKey: "contentFilterSplitView", listKey: "contentFilterTableView",
                  textKey: "contentFilterTextView", addAction: NSSelectorFromString("addContentFilter:"),
                  closeAction: NSSelectorFromString("closeContentFilterManagerSheet:"), placeholderKey: "insertPlaceholderButton",
                  detailColumns: [], addLabel: Strings.addFilter, removeLabel: Strings.removeFilter, actionsLabel: Strings.filterActions)]
        }
    }

    struct Outlets {
        let split: NSSplitView
        let sidebarPane: NSView
        let rightPane: NSView
        let list: NSTableView
        let listScroll: NSScrollView
        let add: NSButton
        let remove: NSButton
        let gear: NSPopUpButton
        let save: NSButton
        let cancel: NSButton
        let help: NSButton?
        let placeholder: NSPopUpButton
        let textScroll: NSScrollView
    }

    private static var associationKey: UInt8 = 0
    private static let showHelp = NSSelectorFromString("showHelp:")
    private static let insertPlaceholder = NSSelectorFromString("insertPlaceholder:")

    private weak var window: NSWindow?
    private let o: Outlets
    private let kind: Kind
    private var appearanceObservation: NSKeyValueObservation?

    private init(window: NSWindow, outlets: Outlets, kind: Kind) {
        self.window = window
        self.o = outlets
        self.kind = kind
        super.init()
    }

    // MARK: Claiming

    /// Claims `window` when it is a Query Favorites or Content Filter manager's sheet and styles it; a claimed window is
    /// styled again (idempotent).
    static func claim(_ window: NSWindow?) {
        guard let window else { return }
        if let styler = objc_getAssociatedObject(window, &associationKey) as? SAClaudeManagerSheetStyler {
            styler.apply()
            return
        }
        guard let controller = window.windowController, controller.window === window else { return }
        let name = SAClaudeFormOwners.className(of: controller)
        guard let kind = Kind.all.first(where: { $0.controllerClass == name }),
              let outlets = findOutlets(controller, kind: kind, window: window) else { return }
        let styler = SAClaudeManagerSheetStyler(window: window, outlets: outlets, kind: kind)
        objc_setAssociatedObject(window, &associationKey, styler, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        styler.build()
        styler.apply()
    }

    private static func outlet<T>(_ controller: NSObject, _ key: String) -> T? {
        SAClaudeFormRecipes.outlet(controller, key)
    }

    private static func findOutlets(_ controller: NSObject, kind: Kind, window: NSWindow) -> Outlets? {
        guard let split: NSSplitView = outlet(controller, kind.splitKey), split.window === window, split.subviews.count == 2,
              let list: NSTableView = outlet(controller, kind.listKey),
              let remove: NSButton = outlet(controller, "removeButton"),
              let text: NSTextView = outlet(controller, kind.textKey) else { return nil }
        let sidebarPane = split.subviews[0]
        let rightPane = split.subviews[1]
        let placeholder: NSPopUpButton? = kind.placeholderKey.flatMap { outlet(controller, $0) }
            ?? rightPane.subviews.compactMap({ $0 as? NSPopUpButton }).first { $0.action == insertPlaceholder }
        let closers = rightPane.subviews.compactMap { $0 as? NSButton }.filter { !($0 is NSPopUpButton) && $0.action == kind.closeAction }
        guard let listScroll = list.enclosingScrollView, listScroll.superview === sidebarPane, remove.superview === sidebarPane,
              let add = sidebarPane.subviews.compactMap({ $0 as? NSButton }).first(where: { !($0 is NSPopUpButton) && $0.action == kind.addAction }),
              let gear = sidebarPane.subviews.compactMap({ $0 as? NSPopUpButton }).first(where: { $0.pullsDown }),
              let save = closers.first(where: { $0.tag == 1 }), let cancel = closers.first(where: { $0.tag == 0 }),
              let placeholder, placeholder.superview === rightPane,
              let textScroll = text.enclosingScrollView, textScroll.superview === rightPane else { return nil }
        let help = rightPane.subviews.compactMap { $0 as? NSButton }.first { !($0 is NSPopUpButton) && $0.action == showHelp }
        return Outlets(split: split, sidebarPane: sidebarPane, rightPane: rightPane, list: list, listScroll: listScroll, add: add,
                       remove: remove, gear: gear, save: save, cancel: cancel, help: help, placeholder: placeholder, textScroll: textScroll)
    }

    // MARK: Building

    private func build() {
        let detailColumns = kind.detailColumns
        SAClaudeUtilitySidebar.adopt(o.list) { state in
            state.groupRowsAsHeaders = true
            state.detailColumns = detailColumns
        }
        SAClaudeUtilityChrome.styleSidebarPane(o.sidebarPane, list: o.listScroll,
                                               bar: [(o.add, .add, kind.addLabel), (o.remove, .remove, kind.removeLabel),
                                                     (o.gear, .actions, kind.actionsLabel)],
                                               split: o.split)
        SAClaudeFormChrome.force(o.save, primary: true)
        SAClaudeFormChrome.force(o.cancel, primary: false)
        if let help = o.help { SAClaudeUtilityChrome.styleHelpButton(help, label: Strings.help) }

        SAClaudeThemeWatcher.observe(self) { styler in
            MainActor.assumeIsolated { styler.recolour() }
        }
        appearanceObservation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.recolour() } }
        }
    }

    // MARK: Applying

    private func apply() {
        layout()
        recolour()
    }

    /// The footer: Save and Cancel on the right margin; the help button on the left margin with Insert Placeholder beside
    /// it (Query Favorites; the Content Filter manager keeps its Insert Placeholder under the clause, as the XIB has it).
    private func layout() {
        let frames = SAClaudeUtilityChrome.layoutFooter([o.save, o.cancel], in: o.rightPane)
        guard let help = o.help, let footer = frames.first else { return }
        let size = SAClaudeSidebarBarLayout.buttonSize
        let helpFrame = NSRect(x: o.rightPane.bounds.minX + SAClaudeFooterLayout.margin - 4, y: (footer.midY - size / 2).rounded(), width: size, height: size)
        SAClaudeUtilityChrome.pin(help, helpFrame, [.maxXMargin, .maxYMargin])
        let pill = o.placeholder.frame
        SAClaudeUtilityChrome.pin(o.placeholder, NSRect(x: helpFrame.maxX + 8, y: (footer.midY - pill.height / 2).rounded(), width: pill.width, height: pill.height),
                                  [.maxXMargin, .maxYMargin])
    }

    private func recolour() {
        let colours = SAClaudeSheetColours.current()
        if let help = o.help { SAClaudeUtilityChrome.recolourGhostIcons([help], colours) }
        // The text view's layer exists once it is on screen: framed at every apply.
        SAClaudeUtilityChrome.frameList(o.textScroll, hairline: colours.palette.hairline)
        o.list.needsDisplay = true
        o.list.headerView?.needsDisplay = true
        o.split.needsDisplay = true
    }
}
