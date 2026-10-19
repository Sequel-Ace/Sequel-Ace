//
//  SAClaudeManagerSheetStyler.swift
//  Sequel Ace
//
//  The Query Favorites and Content Filter managers in the Claude look (spec 2026-10-18-claude-utility-windows-design.md,
//  section D). Both sheets have the same shape: a source list of favourites / filters under "Global" and file headers,
//  with add, remove and gear buttons under it; a form on the right (name, the query or clause in a syntax-coloured text
//  view, Insert Placeholder); Save and Cancel.
//
//  - The list is a Claude sidebar (sidebar fill, selection pills, 28pt rows, the Global / file rows as 11pt muted
//    captions on shorter rows, the tab trigger column muted; the Query Favorites list without its own "Favorites"
//    header); its bar buttons are glyph buttons over a hairline; the divider a hairline.
//  - The query / clause editor is framed by a rounded hairline; the help button (Query Favorites) a ghost "?".
//  - Save (Return) the accent primary, Cancel secondary, both regular size on the right margin.
//  - The form laid out in one rule (`SAClaudeManagerFormLayout`): one right-aligned label column (Name and Tab Trigger;
//    Name and the conjunction label), every field starting at the same x after it, the editor across the form from the
//    labels' left edge; the footer's help, Insert Placeholder (Query Favorites), Cancel and Save on one centre line. Laid
//    out again whenever the right pane changes size; the controller's hidden states stay its own.
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
        let nameKey: String
        let detailColumns: Set<String>
        let addLabel: String
        let removeLabel: String
        let actionsLabel: String

        static var all: [Kind] {
            [Kind(controllerClass: "SPQueryFavoriteManager", splitKey: "favoritesSplitView", listKey: "favoritesTableView",
                  textKey: "favoriteQueryTextView", addAction: NSSelectorFromString("addQueryFavorite:"),
                  closeAction: NSSelectorFromString("closeQueryManagerSheet:"), placeholderKey: nil,
                  nameKey: "favoriteNameTextField", detailColumns: ["tabtrigger"],
                  addLabel: Strings.addFavorite, removeLabel: Strings.removeFavorite, actionsLabel: Strings.favoriteActions),
             Kind(controllerClass: "SPContentFilterManager", splitKey: "contentFilterSplitView", listKey: "contentFilterTableView",
                  textKey: "contentFilterTextView", addAction: NSSelectorFromString("addContentFilter:"),
                  closeAction: NSSelectorFromString("closeContentFilterManagerSheet:"), placeholderKey: "insertPlaceholderButton",
                  nameKey: "contentFilterNameTextField", detailColumns: [], addLabel: Strings.addFilter, removeLabel: Strings.removeFilter, actionsLabel: Strings.filterActions)]
        }
    }

    /// The Content Filter manager's own form views (keep in sync with SPContentFilterManager.h).
    struct FilterViews {
        let clauseLabel: NSTextField
        let argumentCount: NSTextField
        let conjunctionLabel: NSTextField
        let conjunction: NSTextField
        let suppress: NSButton
        let resultLabel: NSTextField
        let result: NSTextField
    }

    enum Form {
        /// Tab Trigger's label and field.
        case favorites(triggerLabel: NSTextField, trigger: NSTextField)
        case filter(FilterViews)
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
        let nameLabel: NSTextField
        let name: NSTextField
        let form: Form
    }

    private static var associationKey: UInt8 = 0
    private static let showHelp = NSSelectorFromString("showHelp:")
    private static let insertPlaceholder = NSSelectorFromString("insertPlaceholder:")

    private weak var window: NSWindow?
    private let o: Outlets
    private let kind: Kind
    private var appearanceObservation: NSKeyValueObservation?
    private var frameObserver: NSObjectProtocol?
    private var isLayingOut = false
    /// The resulting clause's height as the XIB has it (room for a few wrapped lines).
    private lazy var resultHeight: CGFloat = {
        if case .filter(let f) = o.form { return f.result.frame.height }
        return 0
    }()

    private init(window: NSWindow, outlets: Outlets, kind: Kind) {
        self.window = window
        self.o = outlets
        self.kind = kind
        super.init()
    }

    deinit {
        if let frameObserver { NotificationCenter.default.removeObserver(frameObserver) }
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
        guard let nameField: NSTextField = outlet(controller, kind.nameKey), nameField.superview === rightPane,
              let nameLabel = label(beside: nameField),
              let form = findForm(controller, kind: kind, rightPane: rightPane, nameLabel: nameLabel, textScroll: textScroll) else { return nil }
        return Outlets(split: split, sidebarPane: sidebarPane, rightPane: rightPane, list: list, listScroll: listScroll, add: add,
                       remove: remove, gear: gear, save: save, cancel: cancel, help: help, placeholder: placeholder, textScroll: textScroll,
                       nameLabel: nameLabel, name: nameField, form: form)
    }

    /// The static label left of `field` (`SAClaudeFormFind`), or one that starts left of it on its line and runs into it
    /// (the Content Filter manager's "Name:" overlaps its field in the XIB).
    private static func label(beside field: NSTextField) -> NSTextField? {
        if let label = SAClaudeFormFind.label(beside: field) { return label }
        return field.superview?.subviews.compactMap { $0 as? NSTextField }.first { label in
            label !== field && !label.isEditable && label.frame.minX < field.frame.minX
                && label.frame.midY >= field.frame.minY && label.frame.midY <= field.frame.maxY
        }
    }

    /// Tab Trigger (by its outlet, its label beside it) or the Content Filter manager's own views (by their outlets; the
    /// "Clause:" label is the one static label between the name and the editor). Found before anything moves.
    private static func findForm(_ controller: NSObject, kind: Kind, rightPane: NSView, nameLabel: NSTextField, textScroll: NSScrollView) -> Form? {
        if kind.controllerClass == "SPQueryFavoriteManager" {
            guard let trigger: NSTextField = outlet(controller, "favoriteTabTriggerTextField"), trigger.superview === rightPane,
                  let triggerLabel = label(beside: trigger) else { return nil }
            return .favorites(triggerLabel: triggerLabel, trigger: trigger)
        }
        guard let argumentCount: NSTextField = outlet(controller, "numberOfArgsLabel"),
              let conjunctionLabel: NSTextField = outlet(controller, "contentFilterConjunctionLabel"),
              let conjunction: NSTextField = outlet(controller, "contentFilterConjunctionTextField"),
              let suppress: NSButton = outlet(controller, "suppressLeadingFieldPlaceholderCheckbox"),
              let resultLabel: NSTextField = outlet(controller, "resultingClauseLabel"),
              let result: NSTextField = outlet(controller, "resultingClauseContentLabel"),
              [argumentCount, conjunctionLabel, conjunction, suppress, resultLabel, result].allSatisfy({ $0.superview === rightPane }) else { return nil }
        let known: [NSView] = [nameLabel, argumentCount, conjunctionLabel, resultLabel, result]
        let clauseLabel = rightPane.subviews.compactMap { $0 as? NSTextField }.first { label in
            !label.isEditable && !known.contains { $0 === label } && label.frame.minY >= textScroll.frame.maxY - 2 && label.frame.maxY <= nameLabel.frame.minY + 2
        }
        guard let clauseLabel else { return nil }
        return .filter(FilterViews(clauseLabel: clauseLabel, argumentCount: argumentCount, conjunctionLabel: conjunctionLabel,
                                   conjunction: conjunction, suppress: suppress, resultLabel: resultLabel, result: result))
    }

    // MARK: Building

    private func build() {
        let detailColumns = kind.detailColumns
        SAClaudeUtilitySidebar.adopt(o.list) { state in
            state.groupRowsAsHeaders = true
            // "Global" and the file rows group the favourites / filters and can't be selected: captions, not rows.
            state.headerRowsAsCaptions = true
            state.detailColumns = detailColumns
        }
        // The Query Favorites list's own "Favorites" header would sit as a second caption over "Global": the captions
        // carry the list. (The Content Filter list's header names the field type its filters are for, and stays.)
        if kind.controllerClass == "SPQueryFavoriteManager", o.list.headerView != nil {
            o.list.headerView = nil
            o.listScroll.tile()
        }
        SAClaudeUtilityChrome.styleSidebarPane(o.sidebarPane, list: o.listScroll,
                                               bar: [(o.add, .add, kind.addLabel), (o.remove, .remove, kind.removeLabel),
                                                     (o.gear, .actions, kind.actionsLabel)],
                                               split: o.split)
        SAClaudeFormChrome.force(o.save, primary: true)
        SAClaudeFormChrome.force(o.cancel, primary: false)
        if let help = o.help { SAClaudeUtilityChrome.styleHelpButton(help, label: Strings.help) }
        [o.save, o.cancel].forEach(SAClaudeUtilityChrome.makeRegular)
        // Inline labels right-aligned in their column; the conjunction field in the form's field font.
        var inlineLabels = [o.nameLabel]
        if case .favorites(let triggerLabel, _) = o.form { inlineLabels.append(triggerLabel) }
        if case .filter(let f) = o.form {
            inlineLabels.append(f.conjunctionLabel)
            if let font = o.name.font, f.conjunction.font != font { f.conjunction.font = font }
        }
        for label in inlineLabels {
            label.alignment = .right
            label.lineBreakMode = .byTruncatingTail
        }

        o.rightPane.postsFrameChangedNotifications = true
        frameObserver = NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: o.rightPane, queue: nil) { [weak self] _ in
            MainActor.assumeIsolated { self?.layout() }
        }

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

    private typealias Layout = SAClaudeManagerFormLayout

    /// The form and footer in `SAClaudeManagerFormLayout`'s rule (every apply, every resize of the right pane).
    private func layout() {
        guard !isLayingOut else { return }
        isLayingOut = true
        defer { isLayingOut = false }
        fillSheet()
        let place = SAClaudeUtilityChrome.place
        let bounds = o.rightPane.bounds
        let inset = SAClaudeSheetButtonGeometry.metrics(for: .regular).classicSideMargin
        let saveWidth = SAClaudeUtilityChrome.pushButtonWidth(o.save), cancelWidth = SAClaudeUtilityChrome.pushButtonWidth(o.cancel)
        let footer: Layout.Footer
        switch o.form {
        case .favorites(let triggerLabel, let trigger):
            let frames = Layout.favorites(in: bounds, nameLabelWidth: Self.textWidth(o.nameLabel), triggerLabelWidth: Self.textWidth(triggerLabel),
                                          saveWidth: saveWidth, cancelWidth: cancelWidth, buttonInset: inset,
                                          placeholderSize: o.placeholder.frame.size, help: o.help != nil)
            place(o.nameLabel, frames.name.label)
            place(o.name, frames.name.field)
            place(o.textScroll, frames.editor)
            place(triggerLabel, frames.trigger.label)
            place(trigger, frames.trigger.field)
            SAClaudeUtilityChrome.alignBaseline(of: o.nameLabel, to: o.name)
            SAClaudeUtilityChrome.alignBaseline(of: triggerLabel, to: trigger)
            if let accessory = frames.footer.accessory { place(o.placeholder, accessory) }
            footer = frames.footer
        case .filter(let f):
            let frames = Layout.contentFilter(in: bounds, nameLabelWidth: Self.textWidth(o.nameLabel), conjunctionLabelWidth: Self.textWidth(f.conjunctionLabel),
                                              saveWidth: saveWidth, cancelWidth: cancelWidth, buttonInset: inset,
                                              placeholderSize: o.placeholder.frame.size, suppressWidth: f.suppress.cell?.cellSize.width ?? f.suppress.frame.width,
                                              argumentCountWidth: Self.textWidth(f.argumentCount), resultHeight: resultHeight)
            place(o.nameLabel, frames.name.label)
            place(o.name, frames.name.field)
            place(f.clauseLabel, frames.clauseLabel)
            place(f.argumentCount, frames.argumentCount)
            place(o.textScroll, frames.editor)
            place(f.suppress, frames.suppress)
            place(o.placeholder, frames.placeholder)
            place(f.conjunctionLabel, frames.conjunction.label)
            place(f.conjunction, frames.conjunction.field)
            SAClaudeUtilityChrome.alignBaseline(of: o.nameLabel, to: o.name)
            SAClaudeUtilityChrome.alignBaseline(of: f.conjunctionLabel, to: f.conjunction)
            place(f.resultLabel, frames.resultLabel)
            place(f.result, frames.result)
            footer = frames.footer
        }
        place(o.save, footer.save)
        place(o.cancel, footer.cancel)
        if let help = o.help, let frame = footer.help { place(help, frame) }
        SAClaudeUtilityChrome.frameList(o.textScroll, hairline: SAClaudeSheetColours.current().palette.hairline)
    }

    /// The sidebar and form reach the sheet's top edge: the XIB leaves a 10pt band above the split view with a separator
    /// line in it (left from the old toolbar-style sheets), which shows as a strip with a hairline across the sheet. The
    /// separator is hidden and the split view fills the content view (and follows it).
    private func fillSheet() {
        guard let content = window?.contentView, o.split.superview === content else { return }
        for case let box as NSBox in content.subviews where box.boxType == .separator && box.frame.minY >= o.split.frame.maxY - 6 && !box.isHidden {
            box.isHidden = true
        }
        SAClaudeUtilityChrome.pin(o.split, content.bounds, [.width, .height])
    }

    /// A label's text width at its font.
    private static func textWidth(_ label: NSTextField) -> CGFloat {
        ceil(label.attributedStringValue.size().width)
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
