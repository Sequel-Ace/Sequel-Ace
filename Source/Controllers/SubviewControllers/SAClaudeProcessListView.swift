//
//  SAClaudeProcessListView.swift
//  Sequel Ace
//
//  The Process List window as a triage view, in the window `SPProcessListController` loads (its XIB views stay,
//  hidden, for the controller's code paths): one header row (SwiftUI — chips with counts, threshold pill, search,
//  Refresh, Auto refresh, gear), a muted notes line when needed, then a split — the list on the left (an AppKit
//  view-based table: a coloured stripe, a meta line, the query's first two lines) and the detail panel on the right
//  (SwiftUI). Rows, counts, selection and the panel's snapshot come from `SAClaudeProcessListModel`; refreshes come
//  from the session (`SAClaudeProcessListSession.onRefresh`); kills, Save As… and Open in editor go back to the
//  controller. App target only.
//

import AppKit
import Combine
import SwiftUI

@MainActor
@objc(SAClaudeProcessListContent) final class SAClaudeProcessListContent: NSObject {

    // MARK: Actions (set by `install`; a harness may replace them)

    struct Actions {
        var refresh: () -> Void = {}
        var killQuery: (_ id: Int64, _ shownQuery: String?) -> Void = { _, _ in }
        var killConnection: (_ id: Int64) -> Void = { _ in }
        var setAutoRefresh: (Bool) -> Void = { _ in }
        var openInEditor: (String) -> Void = { _ in }
    }

    var actions = Actions()

    // MARK: Views

    let rootView: SAClaudeProcessListRootView
    let tableView: SAClaudeProcessListTableView
    let splitView: SAClaudeProcessListSplitView
    private let scrollView = NSScrollView()
    private let headerHost: NSHostingView<AnyView>
    private let notesHost: NSHostingView<AnyView>
    private let detailHost: NSHostingView<AnyView>
    private let emptyLabel = NSTextField(labelWithString: "")
    let gearMenu = NSMenu()

    // MARK: Models

    let palette: SAClaudeSwiftUIPalette
    let header = SAClaudeProcessListHeaderModel()
    let detail = SAClaudeProcessDetailModel()
    private var colours = SAClaudeProcessListColours.current()
    private var paletteObservation: AnyCancellable?

    // MARK: State

    private weak var session: SAClaudeProcessListSession?
    private(set) var processes: [SAClaudeProcess] = []
    private var rawRows: [Int64: [String: Any]] = [:]
    private(set) var contents = SAClaudeProcessListContents(rows: [], counts: SAClaudeProcessListCounts())
    private(set) var selection = SAClaudeProcessListSelection()
    private(set) var user = ""
    private(set) var ownConnectionId: Int64 = 0
    private var hasLoaded = false
    private var isReloading = false
    private var spinnerWork: DispatchWorkItem?
    /// How long the last `apply()` took (refresh + render of the list, header and panel models), for the harness.
    private(set) var lastApplyDuration: TimeInterval = 0

    static let splitAutosaveName = "ClaudeProcessListDetailSplit"
    static let minimumContentSize = NSSize(width: 760, height: 400)
    static let defaultContentSize = NSSize(width: 1040, height: 620)

    // MARK: Install

    /// Builds the triage view over `window`'s content (hiding the XIB's views and their key equivalents, which the
    /// view answers itself), turns the gear menu into Auto Refresh Interval ▸ and Save As… (the retired Show Process
    /// ID and Show FULL items removed), and wires its actions to `controller`. `contextMenu` is the XIB's right-click
    /// menu (Copy, Kill Query, Kill Connection), kept on the new list.
    @objc(installInWindow:controller:autoRefreshIntervalItem:contextMenu:)
    static func install(in window: NSWindow, controller: SPProcessListController?, autoRefreshIntervalItem: NSMenuItem?,
                        contextMenu: NSMenu?) -> SAClaudeProcessListContent {
        let content = SAClaudeProcessListContent(window: window, contextMenu: contextMenu)
        content.buildGearMenu(autoRefreshIntervalItem: autoRefreshIntervalItem, controller: controller)
        if let controller {
            content.actions = Actions(
                refresh: { [weak controller] in controller?.refreshProcessList(nil) },
                killQuery: { [weak controller] id, query in controller?.killQuery(onConnectionId: id, shownQuery: query) },
                killConnection: { [weak controller] id in controller?.killConnection(withConnectionId: id) },
                setAutoRefresh: { [weak controller] on in controller?.setAutoRefreshEnabled(on) },
                openInEditor: { [weak controller] query in
                    Self.open(query, inEditorOf: controller?.connection?.delegate() as? SPDatabaseDocument)
                })
        }
        return content
    }

    private init(window: NSWindow, contextMenu: NSMenu?) {
        palette = SAClaudeSwiftUIPalette(source: .app)
        rootView = SAClaudeProcessListRootView(frame: window.contentView?.bounds ?? .zero)
        tableView = SAClaudeProcessListTableView(frame: .zero)
        splitView = SAClaudeProcessListSplitView(frame: .zero)
        headerHost = NSHostingView(rootView: AnyView(EmptyView()))
        notesHost = NSHostingView(rootView: AnyView(EmptyView()))
        detailHost = NSHostingView(rootView: AnyView(EmptyView()))
        super.init()

        headerHost.rootView = AnyView(SAClaudeProcessListHeader(model: header).environmentObject(palette))
        notesHost.rootView = AnyView(SAClaudeProcessListNotes(model: header).environmentObject(palette))
        detailHost.rootView = AnyView(SAClaudeProcessDetailPanel(model: detail).environmentObject(palette))
        for host in [headerHost, notesHost, detailHost] as [NSView] {
            (host as? NSHostingView<AnyView>)?.sizingOptions = []
        }

        if let contentView = window.contentView {
            for view in contentView.subviews {
                view.isHidden = true
                if let button = view as? NSButton { button.keyEquivalent = "" }
            }
            rootView.frame = contentView.bounds
            rootView.autoresizingMask = [.width, .height]
            contentView.addSubview(rootView)
        }
        rootView.content = self

        buildList(contextMenu: contextMenu)
        splitView.addSubview(scrollView)
        splitView.addSubview(detailHost)
        splitView.delegate = self
        rootView.addSubview(headerHost)
        rootView.addSubview(notesHost)
        rootView.addSubview(splitView)

        header.onChange = { [weak self] in self?.apply() }
        header.onRefresh = { [weak self] in self?.actions.refresh() }
        header.onAutoRefresh = { [weak self] on in self?.actions.setAutoRefresh(on) }
        header.onGear = { [weak self] anchor in self?.showGearMenu(under: anchor) }
        header.onThreshold = { [weak self] seconds in
            UserDefaults.standard.set(seconds, forKey: SAClaudeProcessClassifier.thresholdKey)
            self?.apply()
        }
        header.setThresholdIndex(Self.thresholdIndex(UserDefaults.standard.integer(forKey: SAClaudeProcessClassifier.thresholdKey)))
        header.setAutoRefreshFromWindow(UserDefaults.standard.bool(forKey: SPProcessListEnableAutoRefresh))
        detail.onCopy = { [weak self] in self?.copyShownQuery() }
        detail.onOpenInEditor = { [weak self] in self?.openShownQueryInEditor() }
        detail.onKillQuery = { [weak self] in self?.killShown(.query) }
        detail.onKillConnection = { [weak self] in self?.killShown(.connection) }
        detail.onShowCurrent = { [weak self] in
            self?.selection.showCurrent()
            self?.detail.detail = self?.selection.detail
        }

        // Theme, accent and appearance changes: the SwiftUI parts follow the palette; the list recolours with it.
        paletteObservation = palette.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.recolour() }
        }

        sizeWindow(window)
        splitView.autosaveName = Self.splitAutosaveName
        rootView.needsLayout = true
        apply()
    }

    private func buildList(contextMenu: NSMenu?) {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("process"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = SAClaudeProcessRowCell.rowHeight
        tableView.intercellSpacing = .zero
        tableView.allowsMultipleSelection = true
        tableView.allowsEmptySelection = true
        tableView.allowsTypeSelect = false
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableView.gridStyleMask = []
        tableView.focusRingType = .none
        tableView.style = .plain
        tableView.menu = contextMenu
        if let contextMenu {
            // No "Ask Siri" field on top (macOS 27 adds it to context menus that allow plug-ins).
            contextMenu.allowsContextMenuPlugIns = false
            // Copy, Kill Query and Kill Connection in one glyph size and weight (AppKit's own Copy image, a symbol the menu
            // redraws at its size, would show taller than the circles). The glyph pass leaves images set here alone.
            for item in contextMenu.items where !item.isSeparatorItem {
                guard let action = item.action, let name = SAClaudeMenuGlyphs.symbol(forAction: NSStringFromSelector(action), title: item.title),
                      let image = SAClaudeMenuGlyphPass.uniformImage(named: name) else { continue }
                item.image = image
                if #available(macOS 27.0, *) { item.preferredImageVisibility = .visible }
            }
        }
        tableView.dataSource = self
        tableView.delegate = self
        tableView.willShowContextMenu = { [weak self] in self?.captureContextTarget() }
        tableView.setAccessibilityLabel(NSLocalizedString("Connections", value: "Connections", comment: "process list : accessibility label of the list"))

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true

        emptyLabel.font = .systemFont(ofSize: 12)
        emptyLabel.alignment = .center
        emptyLabel.isHidden = true
        scrollView.addSubview(emptyLabel)
        recolour()
    }

    private func buildGearMenu(autoRefreshIntervalItem: NSMenuItem?, controller: SPProcessListController?) {
        if let item = autoRefreshIntervalItem, let old = item.menu {
            // The retired options go (the id is always in the row; the list is always FULL).
            let retired: Set<String> = ["toggleShowProcessID:", "toggeleShowFullProcessList:"]
            for oldItem in old.items where oldItem.action.map({ retired.contains(NSStringFromSelector($0)) }) ?? false {
                oldItem.unbind(.value)
                old.removeItem(oldItem)
            }
            old.removeItem(item)
            gearMenu.addItem(item)
            gearMenu.addItem(.separator())
        }
        let save = NSMenuItem(title: NSLocalizedString("Save As…", value: "Save As…", comment: "process list : gear menu item saving the list shown to a file"),
                              action: #selector(SPProcessListController.saveServerProcesses(_:)), keyEquivalent: "")
        save.target = controller
        gearMenu.addItem(save)
    }

    private func sizeWindow(_ window: NSWindow) {
        window.contentMinSize = Self.minimumContentSize
        guard let contentView = window.contentView else { return }
        let size = contentView.bounds.size
        if size.width < Self.minimumContentSize.width || size.height < Self.minimumContentSize.height {
            // The old list's frame (640×203 by default) is too small for the triage view.
            window.setContentSize(NSSize(width: max(size.width, Self.defaultContentSize.width),
                                         height: max(size.height, Self.defaultContentSize.height)))
        }
    }

    static func thresholdIndex(_ seconds: Int) -> Int {
        let value = seconds > 0 ? seconds : SAClaudeProcessClassifier.defaultThreshold
        return SAClaudeProcessClassifier.thresholds.firstIndex(of: value)
            ?? SAClaudeProcessClassifier.thresholds.firstIndex(of: SAClaudeProcessClassifier.defaultThreshold) ?? 1
    }

    var threshold: Int { SAClaudeProcessClassifier.thresholds[header.thresholdIndex] }

    // MARK: Session

    /// Follows `session` (the window's connection for this opening): every refresh result updates the list.
    @objc(attachSession:user:)
    func attach(_ session: SAClaudeProcessListSession?, user: String?) {
        self.session = session
        self.user = user ?? ""
        processes = session?.processes ?? []
        hasLoaded = !processes.isEmpty
        session?.onRefresh = { [weak self, weak session] result in
            guard let self, let session, self.session === session else { return }
            self.sessionDidRefresh(result, session: session)
        }
        header.setAutoRefreshFromWindow(UserDefaults.standard.bool(forKey: SPProcessListEnableAutoRefresh))
        updateNotes()
        apply()
    }

    /// The window closed: stop following its session; the next opening starts from an empty list.
    @objc func detachSession() {
        session?.onRefresh = nil
        session = nil
        processes = []
        rawRows = [:]
        hasLoaded = false
        selection.clear()
        refreshFinished()
        apply()
    }

    func sessionDidRefresh(_ result: SAClaudeProcessListRefresh, session: SAClaudeProcessListSession) {
        switch result {
        case let .fetched(processes, rows):
            self.processes = processes
            rawRows = Self.rowsById(rows)
            hasLoaded = true
        case .failed, .skipped:
            break
        }
        updateNotes()
        if case .skipped = result { return }
        apply()
    }

    /// The refresh's rows (today's dictionaries, for Copy and Save As…) by connection id.
    static func rowsById(_ rows: [[String: Any]]) -> [Int64: [String: Any]] {
        var byId: [Int64: [String: Any]] = [:]
        byId.reserveCapacity(rows.count)
        for row in rows {
            if let process = SAClaudeProcess(row: row) { byId[process.id] = row }
        }
        return byId
    }

    private func updateNotes() {
        var notes: [String] = []
        if let note = session?.sharedConnectionNote { notes.append(note) }
        if let error = session?.lastRefreshError {
            let message = error.trimmingCharacters(in: .whitespacesAndNewlines)
            notes.append(String(format: NSLocalizedString("Couldn't refresh: %@ — showing the last list.", value: "Couldn't refresh: %@ — showing the last list.",
                                                          comment: "process list : muted note when a refresh failed (the server's message)"),
                                message.isEmpty ? NSLocalizedString("Not connected", value: "Not connected", comment: "process list : its connection is not connected") : message))
        }
        if header.notes != notes {
            header.notes = notes
            rootView.needsLayout = true
        }
    }

    /// The controller started a refresh: the spinner shows if it takes a moment.
    @objc func refreshStarted() {
        spinnerWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.header.showsSpinner = true }
        spinnerWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    @objc func refreshFinished() {
        spinnerWork?.cancel()
        spinnerWork = nil
        if header.showsSpinner { header.showsSpinner = false }
    }

    /// The auto refresh preference changed (the switch, ⇧⌘R or the controller).
    @objc func autoRefreshChanged(_ on: Bool) {
        header.setAutoRefreshFromWindow(on)
    }

    // MARK: Building the list

    /// Recomputes the rows and counts for the chip, search and threshold; reloads the list keeping the selection by
    /// connection id; updates the header and the panel.
    func apply() {
        let start = CACurrentMediaTime()
        if let session { ownConnectionId = session.ownConnectionId }
        let threshold = self.threshold
        contents = SAClaudeProcessListModel.contents(.init(processes: processes, threshold: threshold, filter: header.filter,
                                                           search: header.search, user: user, ownConnectionId: ownConnectionId))
        selection.refresh(with: processes)

        isReloading = true
        tableView.reloadData()
        let indexes = selection.indexes(in: contents.rows)
        if tableView.selectedRowIndexes != indexes { tableView.selectRowIndexes(indexes, byExtendingSelection: false) }
        isReloading = false

        if header.counts != contents.counts { header.counts = contents.counts }
        if detail.threshold != threshold { detail.threshold = threshold }
        if detail.detail != selection.detail { detail.detail = selection.detail }
        updateEmptyLabel()
        lastApplyDuration = CACurrentMediaTime() - start
    }

    private func updateEmptyLabel() {
        let text: String
        if !hasLoaded {
            text = NSLocalizedString("Loading…", value: "Loading…", comment: "process list : before the first refresh")
        } else if contents.rows.isEmpty {
            text = NSLocalizedString("No connections match.", value: "No connections match.", comment: "process list : the chip and search show nothing")
        } else {
            text = ""
        }
        emptyLabel.stringValue = text
        emptyLabel.isHidden = text.isEmpty
        layoutEmptyLabel()
    }

    private func layoutEmptyLabel() {
        let bounds = scrollView.contentView.frame
        emptyLabel.frame = NSRect(x: bounds.minX + 16, y: bounds.midY - 10, width: max(0, bounds.width - 32), height: 20)
    }

    private func recolour() {
        colours = SAClaudeProcessListColours.current()
        tableView.backgroundColor = colours.listBackground
        scrollView.backgroundColor = colours.listBackground
        scrollView.scrollerKnobStyle = colours.isDark ? .light : .dark
        emptyLabel.textColor = colours.muted
        splitView.dividerColour = colours.hairline
        splitView.needsDisplay = true
        rootView.hairline = colours.hairline
        rootView.needsDisplay = true
        isReloading = true
        tableView.reloadData()
        tableView.selectRowIndexes(selection.indexes(in: contents.rows), byExtendingSelection: false)
        isReloading = false
    }

    // MARK: Layout

    func layout(in bounds: NSRect) {
        let headerHeight = SAClaudeProcessListHeader.height
        let notesHeight = header.notes.isEmpty ? 0 : SAClaudeProcessListNotes.height
        // The root view is flipped: y grows downwards.
        headerHost.frame = NSRect(x: 0, y: 0, width: bounds.width, height: headerHeight)
        notesHost.frame = NSRect(x: 0, y: headerHeight, width: bounds.width, height: notesHeight)
        notesHost.isHidden = notesHeight == 0
        let top = headerHeight + notesHeight + 1
        let newFrame = NSRect(x: 0, y: top, width: bounds.width, height: max(0, bounds.height - top))
        if splitView.frame != newFrame { splitView.frame = newFrame }
        if !splitView.didPlaceDivider, newFrame.width > 0 { placeInitialDivider() }
        layoutEmptyLabel()
    }

    /// The list takes ≈58% the first time; after that the split's autosave remembers the user's position.
    private func placeInitialDivider() {
        splitView.didPlaceDivider = true
        let key = "NSSplitView Subview Frames \(Self.splitAutosaveName)"
        guard UserDefaults.standard.object(forKey: key) == nil else { return }
        splitView.setPosition((splitView.bounds.width * 0.58).rounded(), ofDividerAt: 0)
    }

    // MARK: Selection

    fileprivate func userChangedSelection() {
        guard !isReloading else { return }
        let rows = contents.rows
        let ids = tableView.selectedRowIndexes.compactMap { rows.indices.contains($0) ? rows[$0].id : nil }
        let lead = rows.indices.contains(tableView.selectedRow) ? rows[tableView.selectedRow].id : nil
        selection.userSelected(ids: ids, lead: lead, in: rows)
        if detail.detail != selection.detail { detail.detail = selection.detail }
    }

    /// What the open right-click menu acts on, captured as it opened (`tableView.willShowContextMenu`): a refresh that
    /// lands while the menu is open reorders the rows under `clickedRow`, never these ids.
    private(set) var contextTarget: SAClaudeProcessListContextTarget?

    /// Captures the right-click menu's target: the clicked row's connection (or the selection it is part of).
    func captureContextTarget() {
        let rows = contents.rows
        let clicked = rows.indices.contains(tableView.clickedRow) ? rows[tableView.clickedRow].id : nil
        contextTarget = SAClaudeProcessListContextTarget(clickedId: clicked, selectedIds: selectedIds(), rows: rows)
    }

    private func selectedIds() -> [Int64] {
        let rows = contents.rows
        return tableView.selectedRowIndexes.compactMap { rows.indices.contains($0) ? rows[$0].id : nil }
    }

    /// The target of a command: the captured right-click target, or (the Edit menu's Copy) the selection.
    private func commandTarget(fromContextMenu: Bool) -> SAClaudeProcessListContextTarget {
        if fromContextMenu, let contextTarget { return contextTarget }
        return SAClaudeProcessListContextTarget(clickedId: nil, selectedIds: selectedIds(), rows: contents.rows)
    }

    // MARK: Commands for the controller

    /// The rows Copy puts on the pasteboard (today's dictionaries), in list order.
    @objc(rowsToCopyFromContextMenu:)
    func rowsToCopy(fromContextMenu: Bool) -> [[String: Any]] {
        commandTarget(fromContextMenu: fromContextMenu).ids.compactMap { rawRows[$0] }
    }

    /// The rows the list shows now (chip and search applied), in list order, for Save As….
    @objc func shownRows() -> [[String: Any]] {
        contents.rows.compactMap { rawRows[$0.id] }
    }

    /// Whether Kill Query / Kill Connection can act from the right-click menu: exactly one connection, still listed.
    @objc(canKillFromContextMenu:)
    func canKill(fromContextMenu: Bool) -> Bool {
        commandTarget(fromContextMenu: fromContextMenu).killTarget(in: processes) != nil
    }

    /// Kill Query on the captured connection, with the query its row showed when the menu opened (the session
    /// re-reads it and asks if it changed since).
    @objc(killQueryFromContextMenu:)
    func killQuery(fromContextMenu: Bool) {
        guard let target = commandTarget(fromContextMenu: fromContextMenu).killTarget(in: processes) else { return }
        actions.killQuery(target.id, target.shownQuery)
    }

    @objc(killConnectionFromContextMenu:)
    func killConnection(fromContextMenu: Bool) {
        guard let target = commandTarget(fromContextMenu: fromContextMenu).killTarget(in: processes) else { return }
        actions.killConnection(target.id)
    }

    /// Whether the list (not the panel's text) is where the Edit menu's Copy applies.
    @objc func listIsFirstResponder() -> Bool {
        tableView.window?.firstResponder === tableView
    }

    // MARK: Detail panel actions

    private func copyShownQuery() {
        guard let query = selection.detail?.shownQuery else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(query, forType: .string)
    }

    private func openShownQueryInEditor() {
        guard let query = selection.detail?.shownQuery else { return }
        actions.openInEditor(query)
    }

    /// Kill query / Kill connection act on the connection the panel shows — its id and the query it shows — never on
    /// a row index; an ended connection does nothing (its buttons are disabled).
    private func killShown(_ kind: SAClaudeProcessKillKind) {
        guard let detail = selection.detail, let id = detail.killTarget,
              SAClaudeProcessKillDecision.canKill(shownId: id, in: processes) else { return }
        switch kind {
        case .query: actions.killQuery(id, detail.shownQuery)
        case .connection: actions.killConnection(id)
        }
    }

    // MARK: Keys and the gear

    fileprivate func performKeyEquivalent(_ event: NSEvent) -> Bool {
        // Caps Lock (and the keypad / fn flags) don't change a shortcut.
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function])
        guard let key = event.charactersIgnoringModifiers?.lowercased() else { return false }
        if key == "r", flags == [.command] {
            if !header.autoRefresh { actions.refresh() }
            return true
        }
        if key == "r", flags == [.command, .shift] {
            actions.setAutoRefresh(!header.autoRefresh)
            return true
        }
        if key == "f", flags == [.command] {
            header.focusSearch()
            return true
        }
        return false
    }

    /// Open in editor: the window that owns the Process List comes forward on its Query tab and the query goes into its
    /// editor as History's insert does (on its own line). If the tab can't switch (an edit there can't be saved), the
    /// window still comes forward and nothing is inserted.
    static func open(_ query: String, inEditorOf document: SPDatabaseDocument?) {
        guard let document, !query.isEmpty else {
            NSSound.beep()
            return
        }
        document.parentWindowControllerWindow()?.makeKeyAndOrderFront(nil)
        document.viewQuery()
        guard document.currentlySelectedView() == .customQuery else { return }
        // One undo removes just this insert, as with a History pick.
        document.customQueryInstance.textView.breakUndoCoalescing()
        document.customQueryInstance.insertPickedQuery(query)
    }

    private func showGearMenu(under anchor: NSView) {
        let y: CGFloat = anchor.isFlipped ? anchor.bounds.maxY + 4 : -4
        gearMenu.popUp(positioning: nil, at: NSPoint(x: 0, y: y), in: anchor)
    }
}

// MARK: - Table data source and delegate

extension SAClaudeProcessListContent: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int { contents.rows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard contents.rows.indices.contains(row) else { return nil }
        let cell = (tableView.makeView(withIdentifier: SAClaudeProcessRowCell.identifier, owner: nil) as? SAClaudeProcessRowCell)
            ?? SAClaudeProcessRowCell()
        cell.configure(contents.rows[row], colours: colours)
        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let rowView = (tableView.makeView(withIdentifier: SAClaudeProcessRowView.identifier, owner: nil) as? SAClaudeProcessRowView)
            ?? SAClaudeProcessRowView()
        if contents.rows.indices.contains(row) {
            let item = contents.rows[row]
            rowView.stripe = SAClaudeProcessListTones.colour(for: item.group, dark: colours.isDark)
                .withAlphaComponent(item.isBackground ? 0.45 : 1)
        }
        rowView.colours = colours
        return rowView
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        userChangedSelection()
    }
}

// MARK: - Split view delegate

extension SAClaudeProcessListContent: NSSplitViewDelegate {
    static let minimumListWidth: CGFloat = 340
    static let minimumDetailWidth: CGFloat = 300

    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        max(proposedMinimumPosition, Self.minimumListWidth)
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        min(proposedMaximumPosition, splitView.bounds.width - Self.minimumDetailWidth)
    }

    func splitView(_ splitView: NSSplitView, canCollapseSubview subview: NSView) -> Bool { false }

    func splitViewDidResizeSubviews(_ notification: Notification) {
        layoutEmptyLabel()
    }
}

// MARK: - Colours

/// The list's colours: the theme background and selection (as the Claude grids), the status tones, hairline, muted.
struct SAClaudeProcessListColours {
    let listBackground: NSColor
    let text: NSColor
    let muted: NSColor
    let hairline: NSColor
    let rowLine: NSColor
    let hover: NSColor
    let selection: NSColor
    let isDark: Bool

    /// The needs-attention text of a row (its state and time), in the group's colour like its stripe, readable on the
    /// selection too.
    var attention: NSColor { SAClaudeProcessListTones.attentionText(dark: isDark, selection: selection) }

    static func current() -> SAClaudeProcessListColours {
        let sheet = SAClaudeSheetColours.current()
        let grid = sheet.gridPalette
        return SAClaudeProcessListColours(listBackground: grid.background, text: grid.text, muted: sheet.muted,
                                          hairline: sheet.palette.hairline, rowLine: grid.rowLine, hover: grid.hover,
                                          selection: grid.selection, isDark: sheet.isDark)
    }
}

// MARK: - Views

/// The window's new content: lays out the header, the notes line and the split; answers ⌘R, ⇧⌘R and ⌘F.
final class SAClaudeProcessListRootView: NSView {
    weak var content: SAClaudeProcessListContent?
    var hairline: NSColor = .separatorColor

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        content?.layout(in: bounds)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if content?.performKeyEquivalent(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }

    /// The hairline under the header (and the notes line).
    override func draw(_ dirtyRect: NSRect) {
        guard let content else { return }
        let y = content.splitView.frame.minY - 1
        let line = NSRect(x: 0, y: y, width: bounds.width, height: 1).intersection(dirtyRect)
        guard !line.isEmpty else { return }
        hairline.setFill()
        line.fill()
    }
}

/// A split with a 1pt hairline divider.
final class SAClaudeProcessListSplitView: NSSplitView {
    var dividerColour: NSColor = .separatorColor
    var didPlaceDivider = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isVertical = true
        dividerStyle = .thin
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var dividerThickness: CGFloat { 1 }
    override var dividerColor: NSColor { dividerColour }
}

/// The list. A right-click selects nothing (AppKit outlines the clicked row); its commands act on that row unless it is
/// part of the selection (`SAClaudeProcessListModel.commandTargets`).
final class SAClaudeProcessListTableView: NSTableView {
    /// Called as the right-click menu opens, once `clickedRow` is set: the content captures what it acts on.
    var willShowContextMenu: (() -> Void)?

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event)
        if menu != nil { willShowContextMenu?() }
        return menu
    }
}

/// A row's background: the hover and selection fills, the status stripe and the row line.
final class SAClaudeProcessRowView: NSTableRowView {
    static let identifier = NSUserInterfaceItemIdentifier("SAClaudeProcessRowView")
    static let stripeWidth: CGFloat = 3

    var stripe: NSColor = .clear { didSet { needsDisplay = true } }
    var colours: SAClaudeProcessListColours? { didSet { needsDisplay = true } }
    private var isHovered = false { didSet { if isHovered != oldValue { needsDisplay = true } } }
    private var tracking: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = Self.identifier
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Text keeps its own colours on the selection fill.
    override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    override func prepareForReuse() {
        super.prepareForReuse()
        isHovered = false
    }

    override func drawBackground(in dirtyRect: NSRect) {
        guard let colours else { return }
        let area = bounds.intersection(dirtyRect)
        (isHovered && !isSelected ? colours.hover : colours.listBackground).setFill()
        area.fill()
        drawStripeAndLine(dirtyRect)
    }

    override func drawSelection(in dirtyRect: NSRect) {
        guard let colours else { return }
        colours.selection.setFill()
        bounds.intersection(dirtyRect).fill()
        drawStripeAndLine(dirtyRect)
    }

    private func drawStripeAndLine(_ dirtyRect: NSRect) {
        let stripeRect = NSRect(x: 6, y: bounds.minY + 9, width: Self.stripeWidth, height: max(0, bounds.height - 18))
        if stripeRect.intersects(dirtyRect) {
            stripe.setFill()
            NSBezierPath(roundedRect: stripeRect, xRadius: Self.stripeWidth / 2, yRadius: Self.stripeWidth / 2).fill()
        }
        let line = NSRect(x: 16, y: isFlipped ? bounds.maxY - 1 : bounds.minY, width: max(0, bounds.width - 16), height: 1)
            .intersection(dirtyRect)
        if !line.isEmpty, let colours {
            colours.rowLine.setFill()
            line.fill()
        }
    }
}

/// A row's content: the meta line (id · user@host · database · state, 11pt muted, the state red when it needs
/// attention; the time right-aligned) and the query's first two lines (mono 12pt, wrapped, ellipsised) or a muted
/// "idle connection".
final class SAClaudeProcessRowCell: NSView {
    static let identifier = NSUserInterfaceItemIdentifier("SAClaudeProcessRowCell")
    static let metaFont = NSFont.systemFont(ofSize: 11)
    static let timeFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
    static let queryFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    static let idleFont = NSFont.systemFont(ofSize: 12)
    static let leading: CGFloat = 18
    static let trailing: CGFloat = 12
    static let top: CGFloat = 8
    static let metaHeight: CGFloat = 15
    static let gap: CGFloat = 3
    static let queryHeight: CGFloat = SAClaudeLineHeight.ceiledHeight(for: queryFont) * 2
    static let rowHeight: CGFloat = top + metaHeight + gap + queryHeight + top

    private let meta = SAClaudeProcessRowCell.label(lines: 1)
    private let time = SAClaudeProcessRowCell.label(lines: 1)
    private let query = SAClaudeProcessRowCell.label(lines: 2)

    override var isFlipped: Bool { true }

    init() {
        super.init(frame: .zero)
        identifier = Self.identifier
        time.alignment = .right
        time.font = Self.timeFont
        [meta, time, query].forEach(addSubview)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private static func label(lines: Int) -> NSTextField {
        let field = NSTextField(labelWithString: "")
        field.isSelectable = false
        field.drawsBackground = false
        field.maximumNumberOfLines = lines
        field.lineBreakMode = lines == 1 ? .byTruncatingTail : .byWordWrapping
        field.cell?.wraps = lines > 1
        field.cell?.truncatesLastVisibleLine = true
        field.usesSingleLineMode = lines == 1
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func configure(_ row: SAClaudeProcessListRow, colours: SAClaudeProcessListColours) {
        let attention = row.group == .needsAttention
        let process = row.process
        let separator = "  ·  "
        let text = NSMutableAttributedString(string: "#\(process.id)", attributes: [.font: Self.metaFont, .foregroundColor: colours.text])
        let host = process.host.isEmpty ? process.user : "\(process.user)@\(process.host)"
        let plain: [NSAttributedString.Key: Any] = [.font: Self.metaFont, .foregroundColor: colours.muted]
        text.append(NSAttributedString(string: separator + host, attributes: plain))
        if let db = process.db, !db.isEmpty { text.append(NSAttributedString(string: separator + db, attributes: plain)) }
        if !row.stateText.isEmpty {
            text.append(NSAttributedString(string: separator, attributes: plain))
            text.append(NSAttributedString(string: row.stateText, attributes: [.font: Self.metaFont, .foregroundColor: attention ? colours.attention : colours.muted]))
        }
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        text.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: text.length))
        meta.attributedStringValue = text

        time.stringValue = row.timeText
        time.textColor = attention ? colours.attention : colours.muted

        if let preview = row.preview {
            query.font = Self.queryFont
            query.textColor = colours.text
            query.stringValue = preview
        } else {
            query.font = Self.idleFont
            query.textColor = colours.muted
            query.stringValue = row.emptyQueryText
        }
        setAccessibilityLabel("#\(process.id), \(host), \(row.stateText), \(row.timeText)")
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let width = bounds.width
        let timeWidth: CGFloat = 64
        time.frame = NSRect(x: width - Self.trailing - timeWidth, y: Self.top, width: timeWidth, height: Self.metaHeight)
        meta.frame = NSRect(x: Self.leading, y: Self.top, width: max(0, width - Self.leading - Self.trailing - timeWidth - 8), height: Self.metaHeight)
        query.frame = NSRect(x: Self.leading, y: Self.top + Self.metaHeight + Self.gap,
                             width: max(0, width - Self.leading - Self.trailing), height: Self.queryHeight)
    }
}
