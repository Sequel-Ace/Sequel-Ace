//
//  SAClaudeFavoriteCardGridController.swift
//  Sequel Ace
//
//  Owns the connection screen's favourite cards: builds `SAClaudeFavoriteGridModel` from the favourites tree, keeps
//  the card IDs ⇄ tree nodes map, and drives the hidden favourites outline, which keeps owning selection, editing
//  state, menus and persistence:
//  - a card click selects the card's outline row, so the controller's selection handler fills the form;
//  - the selected card mirrors the outline's (first) selected row, and shows the unsaved-edits dot while the
//    controller is editing a favourite (what the outline's blue editing dot showed);
//  - double-click / Return go through the controller's `nodeDoubleClicked:` with the outline's double-action item;
//  - right-click selects the card and shows the favourites gear menu (the outline's context menu as a fallback);
//  - a drop is translated into a tree position (`SAClaudeFavoriteCardLayout.treeDestination`) and moved with the
//    shared `SAFavoritesMover`, then the outline reloads and reselects exactly as after an outline drop.
//
//  Card IDs are per-node ("node:<address>"; Quick connect has its own), rebuilt on every reload while the map
//  holds the nodes, so an ID never outlives its node.
//
//  The page (Task 6) places `view`, calls `reload()` when the favourites view data reloads, forwards the search
//  text to `setFilter(_:)` and sizes the view with `preferredHeight(forWidth:)`.
//  App target only.
//

import AppKit

@objc final class SAClaudeFavoriteCardGridController: NSObject {

    /// The scroll view hosting the grid; the owner sets its frame (the grid follows its width).
    @objc let view = NSScrollView()
    /// The cards themselves: the key-view loop's stop for the grid.
    var cardsView: NSView { gridView }
    /// Called after the cards change (reload, filter): their preferred height may have changed.
    var onModelChange: (() -> Void)?

    private let gridView = SAClaudeFavoriteCardGridView()
    private weak var connectionController: SPConnectionController?
    private weak var outline: SPFavoritesOutlineView?
    private weak var dataSource: SAFavoritesListDataSource?

    private var entries: [SAClaudeFavoriteTreeEntry] = []
    private var nodesByID: [String: SPTreeNode] = [:]
    private var model = SAClaudeFavoriteGridModel(topLevel: [], folders: [])
    private var filter = ""
    private var layoutWidth: CGFloat = 0
    private var theme: (palette: SAClaudeEditorChrome.Palette, text: NSColor)?

    private var notificationObservers: [NSObjectProtocol] = []
    private var observations: [NSKeyValueObservation] = []

    private static let quickConnectName = NSLocalizedString("ClaudeFavoriteCardsQuickConnect", value: "Quick connect",
                                                            comment: "connection screen : title of the Quick connect card")
    private static let quickConnectSummary = NSLocalizedString("ClaudeFavoriteCardsQuickConnectSummary", value: "Fill in the panel below",
                                                               comment: "connection screen : subtitle of the Quick connect card")

    /// `nil` when the favourites tree or the outline can't be read (the classic sidebar should stay then).
    @objc init?(connectionController: SPConnectionController) {
        guard let dataSource = connectionController.favoritesListDataSource,
              let outline = connectionController.favoritesOutlineView(),
              dataSource.favoritesRoot.children?.first != nil else { return nil }
        self.connectionController = connectionController
        self.outline = outline
        self.dataSource = dataSource
        super.init()

        view.documentView = gridView
        view.drawsBackground = false
        view.contentView.drawsBackground = false
        view.borderType = .noBorder
        view.hasVerticalScroller = true
        view.hasHorizontalScroller = false
        view.autohidesScrollers = true
        view.verticalScrollElasticity = .none

        connectHandlers()
        refreshColours(force: true)
        observe()
        reload()
    }

    deinit {
        notificationObservers.forEach { NotificationCenter.default.removeObserver($0) }
        observations.forEach { $0.invalidate() }
    }

    // MARK: - API

    /// Re-reads the favourites tree and re-mirrors the outline's selection. Call whenever the favourites view data
    /// reloads (the controller's `-_reloadFavoritesViewData`).
    @objc func reload() {
        guard let dataSource, let topLevel = dataSource.favoritesRoot.children?.first else { return }
        var nodes: [String: SPTreeNode] = [SAClaudeFavoriteGridModel.quickConnectID: dataSource.quickConnectItem]
        entries = (topLevel.children ?? []).map { Self.entry(for: $0, into: &nodes) }
        nodesByID = nodes
        rebuildModel()
        syncSelection()
    }

    /// Filters the cards with the favourites search (every token in the name or host). The owner also sends the
    /// text to the controller's `searchFavorites:` so the hidden outline shows the same favourites.
    @objc func setFilter(_ text: String) {
        guard text != filter else { return }
        filter = text
        rebuildModel()
        syncSelection()
    }

    /// The grid's visible height at `width`: its content height, capped at three card rows.
    @objc func preferredHeight(forWidth width: CGFloat) -> CGFloat {
        SAClaudeFavoriteCardLayout.visibleHeight(contentHeight: SAClaudeFavoriteCardLayout.items(for: model, width: width).contentHeight)
    }

    /// Lays the cards out for a content width (the scroll view's frame changes also lay out on their own).
    @objc func layOut(width: CGFloat) {
        layoutWidth = width
        gridView.update(model: model, width: width, minimumHeight: view.contentSize.height)
    }

    // MARK: - Tree ⇄ cards

    /// The node's object address (not its hash, which is seeded and may collide); unique while the map retains it.
    private static func id(for node: SPTreeNode) -> String {
        "node:" + String(UInt(bitPattern: ObjectIdentifier(node)), radix: 16)
    }

    private static func entry(for node: SPTreeNode, into nodes: inout [String: SPTreeNode]) -> SAClaudeFavoriteTreeEntry {
        let id = id(for: node)
        nodes[id] = node
        if node.isGroup {
            let name = (node.representedObject as? SPGroupNode)?.nodeName ?? ""
            return .folder(id: id, name: name, children: (node.children ?? []).map { entry(for: $0, into: &nodes) })
        }
        let favourite = (node.representedObject as? SPFavoriteNode)?.nodeFavorite as? [AnyHashable: Any] ?? [:]
        func string(_ key: String) -> String {
            switch favourite[key] {
            case let string as String: return string
            case let number as NSNumber: return number.stringValue
            default: return ""
            }
        }
        return .favorite(id: id, name: string(SPFavoriteNameKey), type: (favourite[SPFavoriteTypeKey] as? NSNumber)?.intValue ?? 0,
                         user: string(SPFavoriteUserKey), host: string(SPFavoriteHostKey), port: string(SPFavoritePortKey),
                         socket: string(SPFavoriteSocketKey), sshHost: string(SPFavoriteSSHHostKey),
                         colorIndex: (favourite[SPFavoriteColorIndexKey] as? NSNumber)?.intValue)
    }

    private func rebuildModel() {
        model = SAClaudeFavoriteGridModel.make(from: entries, quickConnectName: Self.quickConnectName,
                                               quickConnectSummary: Self.quickConnectSummary, query: filter)
        gridView.isFiltering = SAFavoriteSearchMatcher(query: filter).isActive
        layOut(width: layoutWidth > 0 ? layoutWidth : view.contentSize.width)
        onModelChange?()
    }

    private func id(forOutlineNode node: SPTreeNode) -> String? {
        if node === dataSource?.quickConnectItem { return SAClaudeFavoriteGridModel.quickConnectID }
        let id = Self.id(for: node)
        return nodesByID[id] === node ? id : nil
    }

    // MARK: - Driving the outline

    private func connectHandlers() {
        gridView.onSelect = { [weak self] id in self?.select(id) }
        gridView.onActivate = { [weak self] id in self?.activate(id) }
        gridView.onRenameFolder = { [weak self] id, name in self?.renameFolder(id, to: name) }
        gridView.menuProvider = { [weak self] id in self?.menu(selecting: id) }
        // As the outline: a drag may start unless the delegate says no (it saves an in-progress rename then).
        gridView.canDrag = { [weak self] _ in
            guard let self else { return false }
            return self.dataSource?.delegate?.favoritesListShouldBeginDrag?() != false
        }
        gridView.canDrop = { [weak self] id, target in
            guard let self else { return false }
            return SAClaudeFavoriteCardLayout.treeDestination(for: target, moving: id, in: self.entries) != nil
        }
        gridView.onDrop = { [weak self] id, target in self?.drop(id, at: target) ?? false }
        gridView.isInteractive = { [weak self] in self?.outline?.isEnabled ?? false }
        gridView.favouriteColour = { SPFavoriteColorSupport.sharedInstance().color(for: $0) }
    }

    /// Selects the node's outline row (expanding collapsed folders above it first, since a row only exists for a
    /// visible node), so the outline's delegate path fills the form exactly as a sidebar click did.
    private func select(_ id: String) {
        guard let outline, let node = nodesByID[id] else { return }
        var ancestors: [SPTreeNode] = []
        var parent = node.parent as? SPTreeNode
        while let ancestor = parent, ancestor.parent != nil {
            ancestors.insert(ancestor, at: 0)
            parent = ancestor.parent as? SPTreeNode
        }
        ancestors.forEach { outline.expandItem($0) }
        let row = outline.row(forItem: node)
        guard row >= 0, outline.selectedRowIndexes != IndexSet(integer: row) else { return }
        outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
    }

    /// The controller's double-action, with the node set as the outline's double-action item (as the outline's own
    /// double-click and Return do): a favourite connects, a folder starts its rename, Quick connect does nothing.
    private func activate(_ id: String) {
        guard let outline, let connectionController, let node = nodesByID[id] else { return }
        select(id)
        // Only act on the node the outline really has selected (selection fails when it has no row, e.g. hidden by
        // the outline's search filter), as the controller acts on the selected row.
        guard outline.selectedRow >= 0, outline.item(atRow: outline.selectedRow) as? SPTreeNode === node else { return }
        // `itemForDoubleAction` is publicly read-only; its private setter is reached through KVC.
        outline.setValue(node, forKey: "itemForDoubleAction")
        connectionController.nodeDoubleClicked(outline)
        outline.setValue(nil, forKey: "itemForDoubleAction")
    }

    /// Shows the inline name field on `node`'s folder header (the page calls this in place of the hidden outline's
    /// cell editing). `false` when the folder has no header in the grid (e.g. hidden by the search).
    @discardableResult
    func beginRenaming(folder node: SPTreeNode) -> Bool {
        guard node.isGroup, let id = id(forOutlineNode: node), id != SAClaudeFavoriteGridModel.quickConnectID,
              gridView.frame(of: id) != nil else { return false }
        gridView.beginRenamingFolder(id, name: (node.representedObject as? SPGroupNode)?.nodeName ?? "")
        return true
    }

    /// Commits a folder name through the outline data source's cell-edit path (trimmed, ignored when empty; the
    /// controller renames, saves and reloads), as the outline's own inline edit did.
    private func renameFolder(_ id: String, to name: String) {
        guard let outline, let dataSource, let node = nodesByID[id], node.isGroup,
              name != (node.representedObject as? SPGroupNode)?.nodeName else { return }
        dataSource.outlineView(outline, setObjectValue: name, for: outline.tableColumns.first, byItem: node)
    }

    /// Selects the right-clicked card or folder, then returns the favourites gear menu; on empty space the menu
    /// acts on the current selection, as the outline's did.
    private func menu(selecting id: String?) -> NSMenu? {
        if let id { select(id) }
        return gearMenu() ?? outline?.menu
    }

    /// The sidebar's gear pull-down menu (Rename … Sort By), found by its Import action next to the outline.
    private func gearMenu() -> NSMenu? {
        guard let sidebar = outline?.enclosingScrollView?.superview else { return nil }
        let importAction = #selector(SPConnectionController.importFavorites(_:))
        func find(in view: NSView) -> NSMenu? {
            if let popUp = view as? NSPopUpButton, let menu = popUp.menu, menu.items.contains(where: { $0.action == importAction }) {
                return menu
            }
            for subview in view.subviews {
                if let menu = find(in: subview) { return menu }
            }
            return nil
        }
        return find(in: sidebar)
    }

    /// Moves the dragged favourite with the shared mover, then reloads and reselects the outline as its own drop
    /// does (`SAFavoritesListDataSource.outlineView(_:acceptDrop:item:childIndex:)`).
    private func drop(_ id: String, at target: SAClaudeFavoriteCardLayout.DropTarget) -> Bool {
        guard let outline, let dataSource, let node = nodesByID[id],
              let destination = SAClaudeFavoriteCardLayout.treeDestination(for: target, moving: id, in: entries) else { return false }
        let parent: SPTreeNode?
        if let folderID = destination.folderID {
            parent = nodesByID[folderID]
        } else {
            parent = dataSource.favoritesRoot.children?.first
        }
        guard let parent else { return false }
        if case .into = target { outline.expandItem(parent) }

        let preDropSelection = outline.selectedRowIndexes.compactMap { outline.item(atRow: $0) as? SPTreeNode }
        guard SAFavoritesMover.move([node], into: parent, at: destination.index,
                                    controller: dataSource.favoritesController, delegate: dataSource.delegate) else { return false }
        dataSource.reloadData(in: outline)
        var restored = IndexSet()
        for selected in preDropSelection {
            let row = outline.row(forItem: selected)
            if row >= 0 { restored.insert(row) }
        }
        outline.selectRowIndexes(restored, byExtendingSelection: false)
        reload()
        return true
    }

    // MARK: - Mirroring the outline

    private func syncSelection() {
        guard let outline else { return }
        let node = outline.selectedRowIndexes.first.flatMap { outline.item(atRow: $0) as? SPTreeNode }
        gridView.selectedID = node.flatMap { id(forOutlineNode: $0) }
        updateUnsavedDot()
    }

    /// Mirrors the outline's editing dot: shown while the controller is editing and a favourite is selected.
    private func updateUnsavedDot() {
        guard let connectionController else { return }
        gridView.showsUnsavedDot = connectionController.isEditingConnection && connectionController.selectedFavorite() != nil
    }

    private func observe() {
        guard let outline, let connectionController else { return }
        // No `queue: .main`: a defaults write on a background thread posts synchronously there, and an observer
        // queue makes the writer wait for the main queue (a deadlock while main waits on that writer).
        notificationObservers.append(NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: nil) { [weak self] _ in
            self?.onMain { $0.refreshColours(force: false) }
        })
        notificationObservers.append(NotificationCenter.default.addObserver(forName: NSOutlineView.selectionDidChangeNotification, object: outline, queue: nil) { [weak self] _ in
            self?.onMain { $0.syncSelection() }
        })
        // Saves, drops and other windows' changes; the page also reloads from `-_reloadFavoritesViewData`.
        notificationObservers.append(NotificationCenter.default.addObserver(forName: .SPConnectionFavoritesChanged, object: nil, queue: nil) { [weak self] _ in
            self?.onMain { $0.reload() }
        })
        view.postsFrameChangedNotifications = true
        notificationObservers.append(NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: view, queue: nil) { [weak self] _ in
            self?.onMain { controller in
                let width = controller.view.contentSize.width
                controller.layOut(width: width)
            }
        })
        observations.append(view.observe(\.effectiveAppearance) { [weak self] _, _ in
            self?.onMain { $0.refreshColours(force: true) }
        })
        observations.append(connectionController.observe(\.isEditingConnection) { [weak self] _, _ in
            self?.onMain { $0.updateUnsavedDot() }
        })
    }

    private func onMain(_ work: @escaping (SAClaudeFavoriteCardGridController) -> Void) {
        if Thread.isMainThread {
            work(self)
        } else {
            DispatchQueue.main.async { [weak self] in
                if let self { work(self) }
            }
        }
    }

    // MARK: - Colours

    /// Re-derives the colours when the editor theme changed (or always, when `force`); the favourite colours are
    /// read at draw time, so a redraw picks up a changed colour list.
    private func refreshColours(force: Bool) {
        var resolved: (SAClaudeEditorChrome.Palette, NSColor)?
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            resolved = (SAClaudeEditorChrome.palette(from: .standard), SAClaudeThemeColours.from(defaults: .standard).text)
        }
        guard let (palette, text) = resolved else { return }
        guard force || palette != theme?.palette || text != theme?.text else {
            gridView.needsDisplay = true
            return
        }
        theme = (palette, text)
        let cardFill = SAClaudeFilterChrome.cardFill(text: text, background: palette.background)
        gridView.colours = SAClaudeFavoriteCardGridView.Colours(
            text: text,
            muted: palette.icon,
            hairline: palette.hairline,
            hoverStroke: SAClaudeEditorChrome.derivedColour(text: text, background: palette.background, ratio: 0.18),
            cardFill: cardFill,
            dashedStroke: SAClaudeFilterChrome.dropStroke(text: text, background: palette.background),
            dropFill: SAClaudeFilterChrome.dropHoverFill(background: palette.background))
    }
}
