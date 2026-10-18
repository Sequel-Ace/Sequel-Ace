//
//  SAClaudeUserManagerStyler.swift
//  Sequel Ace
//
//  The User Manager sheet in the Claude look (spec 2026-10-18-claude-utility-windows-design.md, section C): the accounts
//  list as a Claude sidebar (sidebar fill, selection pills, person / network glyphs for users and hosts) with its add,
//  remove and gear buttons as glyph buttons over a hairline; Claude segmented tabs driving the tab view; Login
//  Information and Resource Limits as titled cards of label + field rows; Global Privileges as four titled cards in two
//  columns, each a grid of Claude checkboxes, with Check All / Uncheck All as ghost pills; Schema Privileges as three
//  Claude grid lists with ◀ / ▶ ghost icons; Apply the accent primary, Cancel secondary; the Errors sheet's OK primary.
//
//  Claimed by owner identity (`SPUserManager`, its window and outlets), as the Server Variables sheet is. The XIB is not
//  edited: its views are re-laid out and restyled in place, so every checkbox and field keeps its value, enabled and
//  hidden bindings, and the checkboxes keep their order and accessibility (only their frames move). Behaviour is the
//  controller's: the tab delegate still decides which tab may be shown. Shared pieces: SAClaudeUtilityWindowStyler.swift;
//  geometry: SAClaudeUtilityWindowLayout.swift. App target only.
//

import AppKit

@MainActor
@objc(SAClaudeUserManagerStyler) final class SAClaudeUserManagerStyler: NSObject {

    private typealias Layout = SAClaudeUserManagerLayout

    // MARK: Strings

    enum Strings {
        static var addUser: String { NSLocalizedString("ClaudeUserManagerAddUser", value: "Add user", comment: "user manager : tooltip and accessibility name of the add-user button under the accounts list") }
        static var removeUser: String { NSLocalizedString("ClaudeUserManagerRemoveUser", value: "Remove user", comment: "user manager : tooltip and accessibility name of the remove-user button under the accounts list") }
        static var actions: String { NSLocalizedString("ClaudeUserManagerAccountActions", value: "Account actions", comment: "user manager : tooltip and accessibility name of the gear menu under the accounts list (Add Host, Remove Host, Refresh)") }
        static var sections: String { NSLocalizedString("ClaudeUserManagerSections", value: "User manager sections", comment: "user manager : accessibility name of the General / Global Privileges / Schema Privileges / Resources tabs") }
        static var grant: String { NSLocalizedString("ClaudeUserManagerGrantSchemaPrivileges", value: "Grant the selected privileges", comment: "user manager : schema privileges tab, tooltip of the arrow that moves the selected available privileges to the granted list") }
        static var revoke: String { NSLocalizedString("ClaudeUserManagerRevokeSchemaPrivileges", value: "Revoke the selected privileges", comment: "user manager : schema privileges tab, tooltip of the arrow that moves the selected granted privileges back to the available list") }
    }

    // MARK: Views

    /// A titled box of label + field rows (Login Information, Resource Limits).
    struct FormCard {
        let box: NSBox
        let rows: [(label: NSTextField, field: NSTextField)]
    }

    /// A titled box of privilege checkboxes, in the XIB's reading order (each column top to bottom, left column first).
    struct PrivilegeCard {
        let box: NSBox
        let checkboxes: [NSButton]
    }

    /// The tab view items by the controller's identifiers (keep in sync with SPUserManager.m).
    private enum TabIdentifier {
        static let general = "General"
        static let privileges = "Global Privileges"
        static let schema = "Schema Privileges"
        static let resources = "Resources"
    }

    /// The first checkbox's bound key in each privilege card, which tells the cards apart (their titles are localized).
    private enum CardKey {
        static let databaseAndTables = "select_priv"
        static let viewsAndProcedures = "create_view_priv"
        static let administration = "reload_priv"
        static let replication = "replication_client_priv"
    }

    struct Outlets {
        let splitView: NSSplitView
        let sidebarPane: NSView
        let rightPane: NSView
        let outline: NSOutlineView
        let outlineScroll: NSScrollView
        let addUser: NSButton
        let removeUser: NSButton
        let gear: NSPopUpButton
        let tabView: NSTabView
        let apply: NSButton
        let cancel: NSButton
        let general: FormCard
        let resources: FormCard
        let privilegesContainer: NSView
        /// Database and Tables, Views and Procedures, Replication.
        let leftCards: [PrivilegeCard]
        /// Administration.
        let rightCards: [PrivilegeCard]
        let checkAll: NSButton
        let uncheckAll: NSButton
        /// Schemas, granted, available.
        let schemaTables: [NSTableView]
        let addSchemaPrivilege: NSButton
        let removeSchemaPrivilege: NSButton
    }

    private static var associationKey: UInt8 = 0
    private static let buttonFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)

    private weak var window: NSWindow?
    private let o: Outlets
    private let tabs: SAClaudeTabViewTabs
    private var chrome = SAClaudeCardLayout.Chrome.zero
    private var grids: [SAClaudeUtilityGridTableView] = []
    /// Rows of the schemas list the controller marks as holding privileges for the selected host (it gives their cells a
    /// background; the grid tints the row instead).
    private var markedSchemaRows = IndexSet()
    private var isLayingOut = false
    private var hasGrown = false
    private var paneMinimum: CGFloat = 0
    private var appearanceObservation: NSKeyValueObservation?
    private var frameObserver: NSObjectProtocol?

    private init(window: NSWindow, outlets: Outlets, tabs: SAClaudeTabViewTabs) {
        self.window = window
        self.o = outlets
        self.tabs = tabs
        super.init()
    }

    deinit {
        if let frameObserver { NotificationCenter.default.removeObserver(frameObserver) }
    }

    // MARK: Claiming

    /// Claims `window` when it is an `SPUserManager`'s sheet (by identity: the controller's own window, its outlets inside
    /// it) and lays it out, or styles its Errors sheet; a window already claimed is laid out again. Called by the
    /// controller before the sheet begins and by the generic sheet skin each time it considers a window. Anything missing
    /// leaves the window in the generic skin.
    @objc(claimWindow:) static func claim(_ window: NSWindow?) {
        guard let window else { return }
        if let styler = styler(for: window) {
            styler.apply()
            return
        }
        if styleErrorsSheet(window) { return }
        guard let controller = window.windowController, SAClaudeFormOwners.className(of: controller) == "SPUserManager",
              controller.window === window, let outlets = findOutlets(controller, window: window),
              let tabs = SAClaudeTabViewTabs.attach(to: outlets.tabView, accessibilityLabel: Strings.sections) else { return }
        let styler = SAClaudeUserManagerStyler(window: window, outlets: outlets, tabs: tabs)
        objc_setAssociatedObject(window, &associationKey, styler, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        styler.build()
        styler.apply()
    }

    static func styler(for window: NSWindow) -> SAClaudeUserManagerStyler? {
        objc_getAssociatedObject(window, &associationKey) as? SAClaudeUserManagerStyler
    }

    private static func outlet<T>(_ controller: NSObject, _ key: String) -> T? {
        SAClaudeFormRecipes.outlet(controller, key)
    }

    private static func findOutlets(_ controller: NSObject, window: NSWindow) -> Outlets? {
        guard let splitView: NSSplitView = outlet(controller, "splitView"), splitView.window === window, splitView.subviews.count == 2,
              let outline: NSOutlineView = outlet(controller, "outlineView"),
              let tabView: NSTabView = outlet(controller, "tabView"),
              type(of: tabView) == NSTabView.self, SAClaudeClassSwap.mayChangeClass(of: tabView),
              let userName: NSTextField = outlet(controller, "userNameTextField"),
              let maxUpdates: NSTextField = outlet(controller, "maxUpdatesTextField"),
              let schemas: NSTableView = outlet(controller, "schemasTableView"),
              let granted: NSTableView = outlet(controller, "grantedTableView"),
              let available: NSTableView = outlet(controller, "availableTableView"),
              let addSchema: NSButton = outlet(controller, "addSchemaPrivButton"),
              let removeSchema: NSButton = outlet(controller, "removeSchemaPrivButton") else { return nil }
        let sidebarPane = splitView.subviews[0]
        let rightPane = splitView.subviews[1]
        guard let outlineScroll = outline.enclosingScrollView, outlineScroll.superview === sidebarPane,
              let addUser = button(in: sidebarPane, action: #selector(SPUserManagerActions.addUser(_:))),
              let removeUser = button(in: sidebarPane, action: #selector(SPUserManagerActions.removeUser(_:))),
              let gear = sidebarPane.subviews.compactMap({ $0 as? NSPopUpButton }).first(where: { $0.pullsDown }),
              tabView.superview === rightPane,
              let apply = button(in: rightPane, action: #selector(SPUserManagerActions.doApply(_:))),
              let cancel = button(in: rightPane, action: #selector(SPUserManagerActions.doCancel(_:))),
              let generalView = item(tabView, TabIdentifier.general), let privilegesView = item(tabView, TabIdentifier.privileges),
              let schemaView = item(tabView, TabIdentifier.schema), let resourcesView = item(tabView, TabIdentifier.resources),
              let general = formCard(containing: userName, in: generalView),
              let resources = formCard(containing: maxUpdates, in: resourcesView),
              let checkAll = button(below: privilegesView, action: #selector(SPUserManagerActions.checkAllPrivileges(_:))),
              let uncheckAll = button(below: privilegesView, action: #selector(SPUserManagerActions.uncheckAllPrivileges(_:))),
              let container = checkAll.superview, uncheckAll.superview === container,
              let cards = privilegeCards(in: container),
              [schemas, granted, available].allSatisfy({ $0.enclosingScrollView?.superview === schemaView }),
              addSchema.superview === schemaView, removeSchema.superview === schemaView else { return nil }
        return Outlets(splitView: splitView, sidebarPane: sidebarPane, rightPane: rightPane, outline: outline, outlineScroll: outlineScroll,
                       addUser: addUser, removeUser: removeUser, gear: gear, tabView: tabView, apply: apply, cancel: cancel,
                       general: general, resources: resources, privilegesContainer: container,
                       leftCards: cards.left, rightCards: cards.right, checkAll: checkAll, uncheckAll: uncheckAll,
                       schemaTables: [schemas, granted, available], addSchemaPrivilege: addSchema, removeSchemaPrivilege: removeSchema)
    }

    private static func button(in view: NSView, action: Selector) -> NSButton? {
        view.subviews.compactMap { $0 as? NSButton }.first { !($0 is NSPopUpButton) && $0.action == action }
    }

    private static func button(below view: NSView, action: Selector) -> NSButton? {
        for subview in view.subviews {
            if let button = subview as? NSButton, button.action == action { return button }
            if !(subview is NSControl), let found = button(below: subview, action: action) { return found }
        }
        return nil
    }

    private static func item(_ tabView: NSTabView, _ identifier: String) -> NSView? {
        tabView.tabViewItems.first { ($0.identifier as? String) == identifier }?.view
    }

    /// The titled box around `field` (inside `view`) and its label + field rows, paired top to bottom.
    private static func formCard(containing field: NSTextField, in view: NSView) -> FormCard? {
        var ancestor = field.superview
        while let current = ancestor, !(current is NSBox) {
            if current === view { return nil }
            ancestor = current.superview
        }
        guard let box = ancestor as? NSBox, box.isDescendant(of: view), let content = box.contentView else { return nil }
        // Fields by their value binding: the binding makes them editable only while an account is selected.
        let texts = content.subviews.compactMap { $0 as? NSTextField }.sorted { $0.frame.midY > $1.frame.midY }
        let fields = texts.filter { $0.infoForBinding(.value) != nil }
        let labels = texts.filter { $0.infoForBinding(.value) == nil }
        guard !fields.isEmpty, fields.count == labels.count, fields.contains(where: { $0 === field }) else { return nil }
        return FormCard(box: box, rows: Array(zip(labels, fields)).map { (label: $0.0, field: $0.1) })
    }

    /// The four privilege cards, told apart by the keys their checkboxes are bound to.
    private static func privilegeCards(in container: NSView) -> (left: [PrivilegeCard], right: [PrivilegeCard])? {
        var byKey: [String: PrivilegeCard] = [:]
        for box in container.subviews.compactMap({ $0 as? NSBox }) {
            guard let content = box.contentView else { continue }
            let checkboxes = content.subviews.compactMap { $0 as? NSButton }.filter { boundPrivilege(of: $0) != nil }
                .sorted { ($0.frame.minX.rounded(), -$0.frame.midY) < ($1.frame.minX.rounded(), -$1.frame.midY) }
            guard let first = checkboxes.first, let key = boundPrivilege(of: first) else { continue }
            byKey[key] = PrivilegeCard(box: box, checkboxes: checkboxes)
        }
        guard byKey.count == 4, let databaseAndTables = byKey[CardKey.databaseAndTables], let viewsAndProcedures = byKey[CardKey.viewsAndProcedures],
              let administration = byKey[CardKey.administration], let replication = byKey[CardKey.replication] else { return nil }
        return ([databaseAndTables, viewsAndProcedures, replication], [administration])
    }

    /// The privilege key a checkbox's value is bound to ("selection.select_priv" → "select_priv").
    private static func boundPrivilege(of button: NSButton) -> String? {
        guard let keyPath = button.infoForBinding(.value)?[.observedKeyPath] as? String, keyPath.hasPrefix("selection."),
              keyPath.hasSuffix("_priv") else { return nil }
        return String(keyPath.dropFirst("selection.".count))
    }

    // MARK: Building

    private func build() {
        buildSidebar()

        o.rightPane.addSubview(tabs.control)
        tabs.onChange = { [weak self] _ in self?.layoutTabs() }
        for button in [o.apply, o.cancel] {
            button.controlSize = .regular
            button.font = Self.buttonFont
        }
        SAClaudeFormChrome.force(o.apply, primary: true)
        SAClaudeFormChrome.force(o.cancel, primary: false)

        for card in [o.general, o.resources] {
            SAClaudeUtilityChrome.makeTitledCard(card.box)
            for row in card.rows {
                row.label.alignment = .right
                row.label.lineBreakMode = .byTruncatingTail
            }
        }
        for card in o.leftCards + o.rightCards { SAClaudeUtilityChrome.makeTitledCard(card.box) }
        if let box = o.leftCards.first?.box { chrome = SAClaudeUtilityChrome.cardChrome(of: box) }
        SAClaudeUtilityChrome.styleGhostPill(o.checkAll, symbol: "checkmark.square")
        SAClaudeUtilityChrome.styleGhostPill(o.uncheckAll, symbol: "square")

        buildSchemaLists()
        SAClaudeUtilityChrome.styleGhostIcon(o.addSchemaPrivilege, symbol: "chevron.left", label: Strings.grant)
        SAClaudeUtilityChrome.styleGhostIcon(o.removeSchemaPrivilege, symbol: "chevron.right", label: Strings.revoke)

        observe()
    }

    private func buildSidebar() {
        SAClaudeUtilitySidebar.adopt(o.outline) { table, row in
            Self.accountGlyph(table: table, row: row)
        }
        let pane = o.sidebarPane
        SAClaudeSidebarChrome.addSidebarBackground(to: pane)
        SAClaudeSidebarChrome.addBarDivider(to: pane, above: o.addUser)
        SAClaudeSidebarChrome.setBarHeight(in: pane, below: o.outlineScroll)
        SAClaudeUtilityChrome.styleBarButton(o.addUser, glyph: .add, label: Strings.addUser)
        SAClaudeUtilityChrome.styleBarButton(o.removeUser, glyph: .remove, label: Strings.removeUser)
        SAClaudeUtilityChrome.styleGearButton(o.gear, label: Strings.actions)
        SAClaudeUtilityChrome.styleSplitDivider(o.splitView)
    }

    /// A user (a top-level row) or one of its hosts: SF Symbols "person" and "network" in the muted sidebar tint, on a canvas
    /// that leaves a gap before the name (`ImageAndTextCell` draws the name right after its image).
    private static let glyphCanvas = NSSize(width: SAClaudeStyle.iconSize + 6, height: SAClaudeStyle.iconSize)

    private static func accountGlyph(table: NSTableView, row: Int) -> NSImage? {
        let isHost = ((table as? NSOutlineView)?.level(forRow: row) ?? 0) > 0
        let tint = SAClaudeUtilityChrome.resolved(SAClaudeStyle.textMuted, for: table)
        return SAClaudeUtilityChrome.tintedSymbol(isHost ? "network" : "person", tint: tint, canvas: glyphCanvas, glyphX: 0)
    }

    private func buildSchemaLists() {
        for (index, table) in o.schemaTables.enumerated() {
            guard let grid = SAClaudeUtilityGridTableView.adopt(table) else { continue }
            grids.append(grid)
            grid.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
            grid.enclosingScrollView?.hasHorizontalScroller = false
            let isSchemas = index == 0
            grid.state?.prepareCell = { [weak self, weak grid] cell, _, row in
                guard let self, let grid else { return }
                self.prepareSchemaCell(cell, in: grid, row: row, isSchemas: isSchemas)
            }
            if isSchemas {
                grid.state?.rowTint = { [weak self] row in
                    guard let self, self.markedSchemaRows.contains(row) else { return nil }
                    return SAClaudeAccent.accent.withAlphaComponent(Self.markAlpha)
                }
            }
        }
    }

    /// The schemas list's "has privileges" tint: the accent, lighter than the selection.
    private static let markAlpha: CGFloat = 0.16

    /// A schema list cell in the grid's colours. The controller greys the "All Databases" rows and gives schemas holding
    /// privileges a pale background: the grey becomes the grid's muted colour and the background a row tint.
    private func prepareSchemaCell(_ cell: NSCell, in grid: SAClaudeUtilityGridTableView, row: Int, isSchemas: Bool) {
        guard let cell = cell as? NSTextFieldCell, let palette = grid.state?.renderer.palette else { return }
        let muted = !grid.isEnabled || cell.textColor == NSColor.lightGray
        cell.textColor = muted ? palette.null : palette.text
        guard isSchemas else { return }
        let marked = cell.drawsBackground
        cell.drawsBackground = false
        guard marked != markedSchemaRows.contains(row) else { return }
        if marked { markedSchemaRows.insert(row) } else { markedSchemaRows.remove(row) }
        // Cells are prepared while the rows draw, after the backgrounds: draw the row again with its tint.
        DispatchQueue.main.async { [weak grid] in
            guard let grid, row < grid.numberOfRows else { return }
            grid.setNeedsDisplay(grid.rect(ofRow: row))
        }
    }

    private func observe() {
        // The tabs, pills, icons and list frames take the theme's colours; the schema tint is the accent.
        SAClaudeThemeWatcher.observe(self) { styler in
            MainActor.assumeIsolated { styler.recolour() }
        }
        SAClaudeAccent.observe(self) { styler in
            MainActor.assumeIsolated { styler.grids.forEach { $0.needsDisplay = true } }
        }
        appearanceObservation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.recolour() } }
        }
        // Dragging the split divider resizes the right pane, whose views the styler places itself.
        o.rightPane.postsFrameChangedNotifications = true
        frameObserver = NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: o.rightPane, queue: nil) { [weak self] _ in
            MainActor.assumeIsolated { self?.layout() }
        }
    }

    // MARK: Applying

    /// Lays the sheet out and colours it (idempotent; on every claim, each time the sheet skin considers the window).
    private func apply() {
        layout()
        recolour()
        linkTabsIntoKeyLoop()
    }

    /// The tabs come right after the accounts list in the key loop. Checked at every apply: AppKit sets the window's loop
    /// up itself when the sheet is first shown (and may have put the tabs elsewhere in it, from where they are taken out).
    private func linkTabsIntoKeyLoop() {
        let control = tabs.control
        guard o.outline.nextKeyView !== control else { return }
        var view: NSView? = o.outline
        for _ in 0..<500 {
            guard let current = view, let next = current.nextKeyView else { break }
            if next === control {
                current.nextKeyView = control.nextKeyView === current ? nil : control.nextKeyView
                break
            }
            view = next
            if next === o.outline { break }
        }
        let next = o.outline.nextKeyView
        o.outline.nextKeyView = control
        control.nextKeyView = next
    }

    private func recolour() {
        let colours = SAClaudeSheetColours.current()
        tabs.recolour(colours)
        SAClaudeUtilityChrome.recolourGhostIcons([o.addSchemaPrivilege, o.removeSchemaPrivilege], colours)
        for pill in [o.checkAll, o.uncheckAll] { SAClaudeUtilityChrome.recolourGhostPill(pill, colours) }
        frameSchemaLists(colours)
        o.outline.needsDisplay = true
        o.outline.headerView?.needsDisplay = true
        o.splitView.needsDisplay = true
    }

    private func layout() {
        guard !isLayingOut else { return }
        isLayingOut = true
        defer { isLayingOut = false }
        let place = SAClaudeUtilityChrome.place
        let bounds = o.rightPane.bounds
        let inset = SAClaudeSheetButtonGeometry.metrics(for: .regular).classicSideMargin
        let frames = Layout.paneFrames(in: bounds, tabsWidth: ceil(tabs.control.preferredWidth), cancelWidth: buttonWidth(o.cancel),
                                       applyWidth: buttonWidth(o.apply), buttonInset: inset)
        place(tabs.control, frames.tabs)
        place(o.tabView, frames.content)
        place(o.cancel, frames.cancel)
        place(o.apply, frames.apply)

        let addRemoveGear: [NSView] = [o.addUser, o.removeUser, o.gear]
        let bar = Layout.barButtons(count: addRemoveGear.count, x: SAClaudeUtilitySidebar.pillInset,
                                    midY: o.sidebarPane.bounds.minY + SAClaudeSidebarChrome.barHeight / 2)
        for (view, frame) in zip(addRemoveGear, bar) { place(view, frame) }

        layoutTabs()
    }

    /// Every tab's content, laid out in its item view (the selected one and the others alike).
    private func layoutTabs() {
        let contentRect = o.tabView.contentRect
        for item in o.tabView.tabViewItems {
            guard let view = item.view else { continue }
            if view.frame != contentRect { view.frame = contentRect }
        }
        let area = Layout.tabContent(in: NSRect(origin: .zero, size: contentRect.size))
        layoutFormCard(o.general, in: area)
        layoutFormCard(o.resources, in: area)
        // False: the sheet grew and everything was laid out again.
        guard layoutPrivileges(in: area) else { return }
        layoutSchema(in: area)
        tabs.sync()
    }

    private func layoutFormCard(_ card: FormCard, in area: NSRect) {
        let labelWidth = min(180, max(60, card.rows.map { ceil($0.label.cell?.cellSize.width ?? $0.label.frame.width) }.max() ?? 60))
        let labelHeight = card.rows.first.map { max(16, ceil($0.label.cell?.cellSize.height ?? 17)) } ?? 17
        let content = Layout.formCard(in: area, rows: card.rows.count, chrome: chrome)
        SAClaudeUtilityChrome.placeCard(card.box, content: content)
        let rows = SAClaudeFormCardLayout.rows(count: card.rows.count, labelWidth: labelWidth, labelHeight: labelHeight, width: content.width)
        for (views, frames) in zip(card.rows, rows) {
            SAClaudeUtilityChrome.place(views.label, frames.label)
            SAClaudeUtilityChrome.place(views.field, frames.field)
        }
    }

    /// The privilege cards with only their visible checkboxes (a server without a privilege hides its checkbox), so the
    /// grid closes up. Laid out again whenever a tab is selected, so a change of what the server supports shows. False
    /// when they didn't fit, so the sheet grew and was laid out again instead.
    private func layoutPrivileges(in area: NSRect) -> Bool {
        SAClaudeUtilityChrome.place(o.privilegesContainer, NSRect(origin: .zero, size: o.tabView.contentRect.size))
        func spec(_ card: PrivilegeCard) -> Layout.PrivilegeCard {
            Layout.PrivilegeCard(itemWidths: card.checkboxes.filter { !$0.isHidden }.map {
                SAClaudeToggleTitleMetrics.cellSize(title: $0.title, drawsTitle: true, nativeHeight: SAClaudeCheckboxGrid.rowHeight).width
            })
        }
        let frames = Layout.privileges(in: area, left: o.leftCards.map(spec), right: o.rightCards.map(spec), chrome: chrome,
                                       checkAllWidth: SAClaudeUtilityChrome.ghostPillWidth(o.checkAll),
                                       uncheckAllWidth: SAClaudeUtilityChrome.ghostPillWidth(o.uncheckAll))
        if frames.bottom < area.minY, growSheet(by: area.minY - frames.bottom) { return false }
        keepPaneWideEnough(cards: o.leftCards.map(spec) + o.rightCards.map(spec), columns: frames.columns)
        for (card, (content, checkboxFrames)) in zip(o.leftCards + o.rightCards, zip(frames.cards, frames.checkboxes)) {
            SAClaudeUtilityChrome.placeCard(card.box, content: content)
            for (checkbox, frame) in zip(card.checkboxes.filter { !$0.isHidden }, checkboxFrames) {
                SAClaudeUtilityChrome.place(checkbox, frame)
            }
        }
        SAClaudeUtilityChrome.place(o.checkAll, frames.checkAll)
        SAClaudeUtilityChrome.place(o.uncheckAll, frames.uncheckAll)
        return true
    }

    /// The controller's own minimum for the right pane (SPUserManager's windowDidLoad).
    private static let controllerPaneMinimum: CGFloat = 550

    /// The divider can't be dragged so far that a privilege card loses a column (its checkboxes would then not fit the
    /// tab): the pane's minimum becomes what the cards need, never more than the pane has now nor less than the
    /// controller's own.
    private func keepPaneWideEnough(cards: [Layout.PrivilegeCard], columns: [Int]) {
        guard let split = o.splitView as? SPSplitView else { return }
        let needed = Layout.minimumPaneWidth(cards: cards, columns: columns, chrome: chrome)
        let minimum = max(Self.controllerPaneMinimum, min(needed, o.rightPane.frame.width))
        guard minimum != paneMinimum else { return }
        paneMinimum = minimum
        split.setMinSize(minimum, ofSubviewAt: 1)
    }

    /// Makes the sheet taller when the privileges don't fit (they do at the XIB's size with every privilege a server can
    /// show; a larger system font could need more), then lays it out again. Once per sheet; false when it can't grow.
    private func growSheet(by amount: CGFloat) -> Bool {
        guard !hasGrown, let window, let contentView = window.contentView, amount > 0 else { return false }
        hasGrown = true
        let size = contentView.bounds.size
        window.setContentSize(NSSize(width: size.width, height: ceil(size.height + amount)))
        isLayingOut = false
        layout()
        return true
    }

    /// A view's layer exists only once it is in the window: framed again whenever the schema tab is laid out.
    private func frameSchemaLists(_ colours: SAClaudeSheetColours = .current()) {
        for table in o.schemaTables {
            if let scrollView = table.enclosingScrollView { SAClaudeUtilityChrome.frameList(scrollView, hairline: colours.palette.hairline) }
        }
    }

    private func layoutSchema(in area: NSRect) {
        let frames = Layout.schema(in: area)
        for (table, frame) in zip(o.schemaTables, [frames.schemas, frames.granted, frames.available]) {
            guard let scrollView = table.enclosingScrollView else { continue }
            SAClaudeUtilityChrome.place(scrollView, frame)
            // Each list's one column fills it (the XIB's columns don't resize with their table).
            scrollView.tile()
            if table.tableColumns.count == 1, let column = table.tableColumns.first {
                let width = max(column.minWidth, scrollView.contentView.bounds.width - table.intercellSpacing.width)
                if column.width != width { column.width = width }
            } else {
                table.sizeLastColumnToFit()
            }
        }
        SAClaudeUtilityChrome.place(o.addSchemaPrivilege, frames.add)
        SAClaudeUtilityChrome.place(o.removeSchemaPrivilege, frames.remove)
        frameSchemaLists()
    }

    /// The title at the button font, the pill's padding and the classic margins either side; at least 84pt.
    private func buttonWidth(_ button: NSButton) -> CGFloat {
        let medium = NSFont.systemFont(ofSize: (button.font ?? Self.buttonFont).pointSize, weight: .medium)
        let title = ceil((button.title as NSString).size(withAttributes: [.font: medium]).width)
        let inset = SAClaudeSheetButtonGeometry.metrics(for: button.controlSize).classicSideMargin
        return max(84, title + 2 * SAClaudeFilterChrome.pillPadding + 2 * inset + 8)
    }

    // MARK: Errors sheet

    /// The controller's Errors sheet (shown on the User Manager when Apply fails): OK the primary, the error text inset and
    /// framed by a hairline. The generic skin does the rest. True when `window` is that sheet.
    private static func styleErrorsSheet(_ window: NSWindow) -> Bool {
        guard let parent = window.sheetParent, let controller = parent.windowController,
              SAClaudeFormOwners.className(of: controller) == "SPUserManager",
              let errorsSheet: NSWindow = outlet(controller, "errorsSheet"), errorsSheet === window,
              let contentView = window.contentView else { return false }
        if let ok = button(in: contentView, action: #selector(SPUserManagerActions.closeErrorsSheet(_:))) {
            SAClaudeFormChrome.force(ok, primary: true)
        }
        for case let scrollView as NSScrollView in contentView.subviews {
            (scrollView.documentView as? NSTextView)?.textContainerInset = NSSize(width: 6, height: 6)
        }
        let frame = { [weak contentView] in
            let hairline = SAClaudeSheetColours.current().palette.hairline
            for case let scrollView as NSScrollView in contentView?.subviews ?? [] {
                SAClaudeUtilityChrome.frameList(scrollView, hairline: hairline)
            }
        }
        frame()
        // The sheet is styled as it begins, before its views have layers: frame the text once it is on screen.
        DispatchQueue.main.async(execute: frame)
        return true
    }
}

/// Selectors of the controller the styler looks for (`SPUserManager.h` is not in the Swift bridging header).
@objc private protocol SPUserManagerActions {
    func addUser(_ sender: Any?)
    func removeUser(_ sender: Any?)
    func doApply(_ sender: Any?)
    func doCancel(_ sender: Any?)
    func checkAllPrivileges(_ sender: Any?)
    func uncheckAllPrivileges(_ sender: Any?)
    func closeErrorsSheet(_ sender: Any?)
}
