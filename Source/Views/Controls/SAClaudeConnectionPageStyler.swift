//
//  SAClaudeConnectionPageStyler.swift
//  Sequel Ace
//
//  Turns the connection screen (ConnectionView.xib) into one Claude page: the favourites sidebar collapses (its
//  outline stays in the hierarchy, hidden, and keeps owning selection, editing state, menus and persistence), the
//  right pane paints the theme background, and the details scroll view's document view becomes the page — one
//  centred column of `min(pane − 48, 960)` with, from the top: a top bar (the favourites search field, moved and
//  restyled; "Folder" / "Favourite" ghost buttons for `addGroup:` / `addFavorite:`, and a "⋯" ghost button whose menu
//  imports, exports (the selection, or all with none selected) and sorts connections — `SAClaudeConnectionsMenuModel`,
//  `SAClaudeConnectionsCommands`), the favourite cards
//  (`SAClaudeFavoriteCardGridController`), the connection panel (`SAClaudeConnectionPanelStyler`, given the
//  column width) and the instruction line (moved and restyled).
//
//  The controller's `-scrollViewFrameChanged:` still runs (it centres the form and, in a short window, scrolls to
//  the top); a hook at its end re-applies the page layout and restores the scroll position the user left, so a
//  relayout never jumps the page.
//
//  Inline editing on the hidden outline is redirected: the outline's class becomes a subclass whose
//  `editColumn(_:row:with:select:)` hands the node to the page instead of starting an invisible cell edit — a
//  favourite's rename focuses the panel's Name field (all selected); a folder's opens a name field on its card-grid
//  header, which commits through the outline data source's own cell-edit path.
//
//  When the favourites tree can't be read (no card grid) or the panel didn't attach, nothing here happens and the
//  classic sidebar stays. App target only.
//

import AppKit

// MARK: - Page pieces

/// A plain fill (the right pane's theme background); never takes clicks.
private final class SAClaudePageFillView: SAClaudeFlatFillView {}

/// The search field's rounded field look (fill, hairline; clay while editing); a click on its padding focuses it.
private final class SAClaudePageSearchFieldView: SAClaudeOutlinedFillView {
    var onClick: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        radius = 7
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
}

/// Weakly points an outline at its page (an associated object of the outline).
private final class SAClaudePageReference {
    weak var page: SAClaudeConnectionPageStyler?
    init(_ page: SAClaudeConnectionPageStyler) { self.page = page }
}

/// The hidden favourites outline's class while the page is shown: the controller's inline edits (Rename, Add
/// favourite, Add folder, double-click on a folder) go to the page instead of an invisible cell editor. No stored
/// properties: the class is swapped onto the XIB's outline.
private final class SAClaudePageFavoritesOutlineView: SPFavoritesOutlineView {
    override func editColumn(_ column: Int, row: Int, with event: NSEvent?, select: Bool) {
        guard let page = SAClaudeConnectionPageStyler.page(for: self) else {
            super.editColumn(column, row: row, with: event, select: select)
            return
        }
        // Always redirected while the page is shown, so the outline never opens its own (invisible) cell editor.
        // No row (-1) or no tree node behind it: nothing to edit.
        guard row >= 0, let node = item(atRow: row) as? SPTreeNode else { return }
        page.redirectEdit(of: node)
    }
}

// MARK: - Styler

@objc(SAClaudeConnectionPageStyler) final class SAClaudeConnectionPageStyler: NSObject {

    private static var associationKey: UInt8 = 0
    private static var outlineKey: UInt8 = 0

    private static let maximumColumnWidth: CGFloat = 960
    private static let sideMargin: CGFloat = 48
    private static let topMargin: CGFloat = 24
    private static let bottomMargin: CGFloat = 24
    private static let topBarHeight: CGFloat = 28
    /// Between the top bar, the cards and the panel.
    private static let sectionGap: CGFloat = 16
    /// Between the panel and the instruction line.
    private static let instructionGap: CGFloat = 12
    private static let searchMaximumWidth: CGFloat = 280
    private static let searchInset: CGFloat = 8
    private static let ghostPadding: CGFloat = 10
    private static let ghostGlyphWidth: CGFloat = 16
    private static let ghostGlyphGap: CGFloat = 4
    private static let buttonGap: CGFloat = 8
    /// The most layout passes one request runs (a pass can show / hide a legacy scroller and change the width).
    private static let maximumPasses = 3

    private static let searchFont = NSFont.systemFont(ofSize: 12)
    private static let ghostFont = NSFont.systemFont(ofSize: 12)
    private static let instructionFont = NSFont.systemFont(ofSize: 12)

    private weak var controller: SPConnectionController?
    private weak var scrollView: NSScrollView?
    private weak var container: NSView?
    private weak var instructionsField: NSTextField?
    private weak var searchField: NSSearchField?
    private weak var rightPane: NSView?
    private weak var panel: SAClaudeConnectionPanelStyler?
    private let grid: SAClaudeFavoriteCardGridController

    private let background = SAClaudePageFillView()
    private let topBar = NSView()
    private let searchFieldView = SAClaudePageSearchFieldView()
    private let folderButton = NSButton(title: "", target: nil, action: nil)
    private let favouriteButton = NSButton(title: "", target: nil, action: nil)
    private let moreButton = NSButton(title: "", target: nil, action: nil)
    /// The ⋯ menu's Import / Export target (menu items hold their targets weakly).
    private lazy var connectionsCommands = SAClaudeConnectionsCommands { [weak self] in self?.controller }
    private var placeholder = ""

    /// How far the visible top is below the page's top: kept across relayouts (the controller's short-window
    /// branch scrolls to the top before the page lays out again).
    private var topDistance: CGFloat = 0
    /// Where the page last put the panel: a scroll while it's elsewhere is the controller's, not the user's.
    private var laidOutContainerFrame: NSRect?
    /// Set once the page is built: the controller's hooks lay out nothing before.
    private var isAttached = false
    private var isLayingOut = false
    private var needsAnotherPass = false
    private var filterPending = false

    private var theme: (palette: SAClaudeEditorChrome.Palette, text: NSColor, fieldFill: NSColor)?
    private var notificationObservers: [NSObjectProtocol] = []
    private var observations: [NSKeyValueObservation] = []
    private var firstResponderObservation: NSKeyValueObservation?
    private weak var observedWindow: NSWindow?

    private init(grid: SAClaudeFavoriteCardGridController) {
        self.grid = grid
        super.init()
    }

    deinit {
        notificationObservers.forEach { NotificationCenter.default.removeObserver($0) }
        observations.forEach { $0.invalidate() }
        firstResponderObservation?.invalidate()
    }

    // MARK: - Hooks

    /// Builds the page once per scroll view (the scroll view retains the styler). Call after the connection panel
    /// attached; does nothing (the classic sidebar stays) when the favourites tree, the panel or the expected view
    /// structure is missing.
    @objc(attachToController:splitView:scrollView:container:instructionsField:searchField:)
    static func attach(controller: SPConnectionController, splitView: SPSplitView?, scrollView: NSScrollView?, container: NSView?,
                       instructionsField: NSTextField?, searchField: NSSearchField?) {
        guard let splitView, let scrollView, let container, let instructionsField, let searchField,
              objc_getAssociatedObject(scrollView, &associationKey) == nil,
              let document = scrollView.documentView, container.superview === document,
              let panel = SAClaudeConnectionPanelStyler.styler(for: container),
              let outline = controller.favoritesOutlineView(),
              splitView.subviews.count == 2, let sidebar = splitView.subviews.first, outline.isDescendant(of: sidebar),
              let rightPane = scrollView.superview, rightPane === splitView.subviews.last,
              instructionsField.superview === rightPane
        else {
            debugLog("the connection view doesn't have the expected structure; the classic sidebar stays")
            return
        }
        guard let grid = SAClaudeFavoriteCardGridController(connectionController: controller) else {
            debugLog("the favourites tree can't be read; the classic sidebar stays")
            return
        }
        let page = SAClaudeConnectionPageStyler(grid: grid)
        objc_setAssociatedObject(scrollView, &associationKey, page, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        page.controller = controller
        page.scrollView = scrollView
        page.container = container
        page.instructionsField = instructionsField
        page.searchField = searchField
        page.rightPane = rightPane
        page.panel = panel

        page.collapseSidebar(sidebar, in: splitView)
        page.redirectEditing(of: outline)
        page.buildViews(document: document)
        page.connectPanel(panel)
        page.refresh(force: true)
        page.observe()
        page.isAttached = true
        page.layOut()
        panel.chainKeyViews()
    }

    /// The end of the controller's `-scrollViewFrameChanged:`: the page takes the frames back.
    @objc(pageNeedsLayoutIn:)
    static func pageNeedsLayout(in scrollView: NSScrollView) {
        page(for: scrollView)?.layOut()
    }

    /// The end of the controller's `-_reloadFavoritesViewData`: the cards re-read the favourites tree.
    @objc(favoritesDidReloadIn:)
    static func favoritesDidReload(in scrollView: NSScrollView) {
        page(for: scrollView)?.grid.reload()
    }

    /// Whether the favourites show as the page's cards (no tree): the controller's `-addGroup:` adds top-level folders.
    @objc(showsCardsIn:)
    static func showsCards(in scrollView: NSScrollView) -> Bool {
        page(for: scrollView)?.isAttached ?? false
    }

    private static func page(for scrollView: NSScrollView) -> SAClaudeConnectionPageStyler? {
        objc_getAssociatedObject(scrollView, &associationKey) as? SAClaudeConnectionPageStyler
    }

    fileprivate static func page(for outline: NSOutlineView) -> SAClaudeConnectionPageStyler? {
        (objc_getAssociatedObject(outline, &outlineKey) as? SAClaudePageReference)?.page
    }

    private static func debugLog(_ message: @autoclosure () -> String) {
        #if DEBUG
        NSLog("Claude connection page: %@", message())
        #endif
    }

    // MARK: - Building

    /// The sidebar collapses to zero width with its divider hidden (`SPSplitView`'s own collapse, which also stops
    /// the divider dragging); the sidebar stays in the hierarchy, hidden. The split view no longer autosaves, so the
    /// width saved for the classic sidebar is kept.
    private func collapseSidebar(_ sidebar: NSView, in splitView: SPSplitView) {
        splitView.autosaveName = nil
        // `SPSplitView` raises when the handle's window differs from its own, and nil has no window: only clear it
        // while the split view isn't in a window yet (the attach runs before it is).
        if splitView.window == nil { splitView.setAdditionalDragHandle(nil) }
        splitView.setCollapsibleSubviewIndex(0)
        splitView.setCollapsibleSubviewCollapsed(true, animate: false)
        sidebar.isHidden = true
    }

    private func redirectEditing(of outline: SPFavoritesOutlineView) {
        guard object_getClass(outline) == SPFavoritesOutlineView.self else {
            Self.debugLog("the favourites outline isn't a plain SPFavoritesOutlineView; inline edits stay on the outline")
            return
        }
        object_setClass(outline, SAClaudePageFavoritesOutlineView.self)
        objc_setAssociatedObject(outline, &Self.outlineKey, SAClaudePageReference(self), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    private func buildViews(document: NSView) {
        guard let scrollView, let rightPane, let instructionsField, let searchField, let controller else { return }

        // The right pane: the theme background behind a scroll view that fills it.
        background.frame = rightPane.bounds
        background.autoresizingMask = [.width, .height]
        rightPane.addSubview(background, positioned: .below, relativeTo: nil)
        scrollView.frame = rightPane.bounds
        scrollView.autoresizingMask = [.width, .height]
        scrollView.drawsBackground = false
        scrollView.contentView.drawsBackground = false

        // Top bar: the favourites search field (same object, action and delegate) in a Claude field.
        topBar.autoresizingMask = []
        document.addSubview(topBar)
        searchFieldView.onClick = { [weak self] in
            guard let field = self?.searchField else { return }
            field.window?.makeFirstResponder(field)
        }
        topBar.addSubview(searchFieldView)
        placeholder = searchField.placeholderString ?? ""
        searchField.removeFromSuperview()
        searchField.autoresizingMask = []
        searchFieldView.addSubview(searchField)
        SAClaudeSearchFieldCell.install(on: searchField)
        searchField.isBezeled = false
        searchField.isBordered = false
        searchField.drawsBackground = false
        searchField.focusRingType = .none
        searchField.controlSize = .regular
        searchField.font = Self.searchFont

        let buttons: [(NSButton, String, String, Selector)] = [
            (folderButton,
             NSLocalizedString("ClaudeConnectionPageFolder", value: "Folder", comment: "connection screen : top bar button adding a favourites folder"),
             NSLocalizedString("ClaudeConnectionPageNewFolder", value: "New folder", comment: "connection screen : tooltip of the top bar button adding a favourites folder"),
             #selector(SPConnectionController.addGroup(_:))),
            (favouriteButton,
             NSLocalizedString("ClaudeConnectionPageFavourite", value: "Favourite", comment: "connection screen : top bar button adding a favourite"),
             NSLocalizedString("ClaudeConnectionNewFavourite", value: "New favourite", comment: "connection panel : placeholder of the connection name in the header"),
             #selector(SPConnectionController.addFavorite(_:))),
        ]
        for (button, title, help, action) in buttons {
            button.title = title
            button.toolTip = help
            button.setAccessibilityLabel(help)
            button.target = controller
            button.action = action
            button.bezelStyle = .regularSquare
            button.imagePosition = .imageLeading
            button.autoresizingMask = []
            SAClaudeFilterCells.installCellDrawing(on: button)
            button.isBordered = false
            topBar.addSubview(button)
            SAClaudeHoverHighlighter.attach(to: button)
        }

        // "⋯": Import Connections…, Export Connections…, Sort By (the card menu's actions), an icon-only ghost button.
        let moreHelp = NSLocalizedString("ClaudeConnectionPageMore", value: "Import, export and sort connections",
                                         comment: "connection screen : tooltip and accessibility name of the top bar ⋯ button (its menu imports, exports and sorts connection favourites)")
        moreButton.toolTip = moreHelp
        moreButton.setAccessibilityLabel(moreHelp)
        moreButton.target = self
        moreButton.action = #selector(showMoreMenu(_:))
        moreButton.bezelStyle = .regularSquare
        moreButton.imagePosition = .imageOnly
        moreButton.autoresizingMask = []
        SAClaudeFilterCells.installCellDrawing(on: moreButton)
        moreButton.isBordered = false
        topBar.addSubview(moreButton)
        SAClaudeHoverHighlighter.attach(to: moreButton)

        document.addSubview(grid.view)

        // The instruction line moves under the panel, muted.
        instructionsField.removeFromSuperview()
        instructionsField.autoresizingMask = []
        instructionsField.isBezeled = false
        instructionsField.isBordered = false
        instructionsField.drawsBackground = false
        instructionsField.alignment = .center
        instructionsField.lineBreakMode = .byTruncatingTail
        instructionsField.font = Self.instructionFont
        document.addSubview(instructionsField)
    }

    /// The panel takes the column width from the page, lets the page place it after each of its layouts, and
    /// starts its key-view loop at the search field and the cards.
    private func connectPanel(_ panel: SAClaudeConnectionPanelStyler) {
        panel.onLayout = { [weak self] in self?.layOut() }
        panel.leadingKeyViews = { [weak self] in
            guard let self else { return [] }
            return [self.searchField, self.grid.cardsView].compactMap { $0 }
        }
        grid.onModelChange = { [weak self] in self?.layOut() }
    }

    // MARK: - Observing

    private func observe() {
        guard let scrollView, let container, let rightPane else { return }
        notificationObservers.append(SAClaudeAppearanceChange.addObserver { [weak self] _ in
            self?.onMain { $0.refresh(force: false) }
        })
        observations.append(rightPane.observe(\.effectiveAppearance) { [weak self] _, _ in
            self?.onMain { $0.refresh(force: true) }
        })
        // The search field's focus outline is the accent.
        SAClaudeAccent.observe(self) { $0.updateFocus() }
        // The user's scrolling (the page restores it after relayouts).
        scrollView.contentView.postsBoundsChangedNotifications = true
        notificationObservers.append(NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: scrollView.contentView, queue: nil) { [weak self] _ in
            self?.onMain { $0.recordScrollPosition() }
        })
        // Multiple favourites selected: the controller hides the panel; the instruction moves up to its place.
        observations.append(container.observe(\.isHidden) { [weak self] _, _ in
            self?.onMain { $0.layOut() }
        })
        // The search field filters the outline (`searchFavorites:` sets the data source's query); the cards follow
        // the same query, after the outline has reloaded, so every card has an outline row.
        if let dataSource = controller?.favoritesListDataSource {
            observations.append(dataSource.observe(\.searchQuery, options: [.initial]) { [weak self] _, _ in
                self?.onMain { $0.scheduleFilterSync() }
            })
        }
        observations.append(container.observe(\.window) { [weak self] _, _ in
            self?.onMain { $0.observeFirstResponder() }
        })
        observeFirstResponder()
    }

    private func onMain(_ work: @escaping (SAClaudeConnectionPageStyler) -> Void) {
        if Thread.isMainThread {
            work(self)
        } else {
            DispatchQueue.main.async { [weak self] in
                if let self { work(self) }
            }
        }
    }

    private func scheduleFilterSync() {
        guard !filterPending else { return }
        filterPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.filterPending = false
            self.grid.setFilter(self.controller?.favoritesListDataSource?.searchQuery ?? "")
        }
    }

    /// Follows the first responder of the page's window: the search field's clay outline, and the hidden outline
    /// handing focus to the cards (the search field's Down arrow and the controller's key views lead to it).
    private func observeFirstResponder() {
        guard let container, container.window !== observedWindow else { return }
        firstResponderObservation = nil
        observedWindow = container.window
        updateFocus()
        guard let window = container.window else { return }
        firstResponderObservation = window.observe(\.firstResponder) { [weak self] _, _ in
            self?.onMain { $0.firstResponderChanged() }
        }
    }

    private func firstResponderChanged() {
        updateFocus()
        guard let window = observedWindow, let outline = controller?.favoritesOutlineView(), window.firstResponder === outline else { return }
        // Not inside the window's own first-responder change.
        DispatchQueue.main.async { [weak self] in
            guard let self, window.firstResponder === outline else { return }
            window.makeFirstResponder(self.grid.cardsView)
        }
    }

    private func updateFocus() {
        guard let theme else { return }
        let editing = searchField?.currentEditor() != nil
        let stroke = editing ? SAClaudeStatusChrome.clay : theme.palette.hairline
        if searchFieldView.stroke != stroke { searchFieldView.stroke = stroke }
    }

    // MARK: - Redirected editing

    /// Called instead of the hidden outline's inline cell edit: a favourite's name is edited in the panel header,
    /// a folder's on its card-grid header.
    fileprivate func redirectEdit(of node: SPTreeNode) {
        // After the controller's action (and any menu) has finished.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if node.isGroup {
                if self.grid.beginRenaming(folder: node) { self.grid.view.scrollToVisible(self.grid.view.bounds) }
            } else {
                self.panel?.beginEditingName()
            }
        }
    }

    // MARK: - Colours

    private func refresh(force: Bool) {
        guard let rightPane else { return }
        var resolved: (SAClaudeEditorChrome.Palette, NSColor, NSColor)?
        rightPane.effectiveAppearance.performAsCurrentDrawingAppearance {
            let palette = SAClaudeEditorChrome.palette(from: .standard)
            let text = SAClaudeThemeColours.from(defaults: .standard).text
            resolved = (palette, text, SAClaudeFilterChrome.fieldFill(text: text, background: palette.background))
        }
        guard let (palette, text, fieldFill) = resolved else { return }
        guard force || palette != theme?.palette || text != theme?.text else { return }
        theme = (palette, text, fieldFill)

        background.fillColour = palette.background
        searchFieldView.fill = fieldFill
        if let searchField {
            searchField.textColor = text
            (searchField.cell as? NSSearchFieldCell)?.placeholderAttributedString =
                NSAttributedString(string: placeholder, attributes: [.foregroundColor: palette.icon, .font: Self.searchFont])
            searchField.needsDisplay = true
        }
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        for button in [folderButton, favouriteButton] {
            button.attributedTitle = NSAttributedString(string: button.title, attributes: [
                .font: Self.ghostFont, .foregroundColor: palette.buttonText, .paragraphStyle: style,
            ])
            button.image = SAClaudeGlyphs.image(.add, tint: palette.buttonText)
            SAClaudeHoverHighlighter.setFillColour(palette.hover, for: button)
            button.needsDisplay = true
        }
        let moreImage = SAClaudeGlyphs.image(.more, tint: palette.buttonText)
        moreImage.accessibilityDescription = moreButton.accessibilityLabel()
        moreButton.image = moreImage
        SAClaudeHoverHighlighter.setFillColour(palette.hover, for: moreButton)
        moreButton.needsDisplay = true
        instructionsField?.textColor = palette.icon
        updateFocus()
        rightPane.needsDisplay = true
    }

    // MARK: - Layout

    private func columnWidth() -> CGFloat {
        guard let scrollView else { return 0 }
        return max(1, min(scrollView.contentSize.width - Self.sideMargin, Self.maximumColumnWidth)).rounded(.down)
    }

    private static func ghostWidth(_ button: NSButton) -> CGFloat {
        ceil(NSAttributedString(string: button.title, attributes: [.font: ghostFont]).size().width)
            + ghostGlyphWidth + ghostGlyphGap + 2 * ghostPadding
    }

    /// Sets `frame` (on whole points) only when it changed.
    private static func place(_ view: NSView, _ frame: NSRect) {
        let aligned = NSRect(x: frame.minX.rounded(), y: frame.minY.rounded(), width: frame.width.rounded(), height: frame.height.rounded())
        if view.frame != aligned { view.frame = aligned }
    }

    /// Lays the page out: top bar, cards, panel, instruction line, top to bottom in the centred column; then the
    /// document's height and the scroll position the user left. Re-entrant calls (the panel relaying out for a new
    /// width, a scroller appearing) run as another pass.
    private func layOut() {
        guard isAttached else { return }
        guard !isLayingOut else {
            needsAnotherPass = true
            return
        }
        isLayingOut = true
        defer { isLayingOut = false }
        var passes = 0
        repeat {
            needsAnotherPass = false
            layOutPass()
            passes += 1
        } while needsAnotherPass && passes < Self.maximumPasses
    }

    private func layOutPass() {
        guard let scrollView, let document = scrollView.documentView, let container, let instructionsField else { return }
        let clip = scrollView.contentView
        let paneWidth = scrollView.contentSize.width
        let column = columnWidth()
        let x = ((paneWidth - column) / 2).rounded(.down)

        // The panel lays out at the column width first (its own frames and height).
        if let panel, panel.columnWidth != column {
            panel.columnWidth = column
            panel.layOut()
        }

        let panelShown = !container.isHidden
        // The panel's own size: while the controller resizes the form it briefly sets the container to its XIB
        // height, and a page laid out with that would clamp the scroll position for nothing.
        let panelSize = panel?.laidOutSize ?? container.frame.size
        // The instruction line only stands in for the panel (several favourites selected).
        if instructionsField.isHidden != panelShown { instructionsField.isHidden = panelShown }
        let instructionHeight = panelShown ? 0 : ceil(instructionsField.cell?.cellSize.height ?? 16)

        // Offsets from the page's top.
        let topBarTop = Self.topMargin
        let gridTop = topBarTop + Self.topBarHeight + Self.sectionGap
        // The cards take the height the window leaves under the top bar and over the panel (at its own height):
        // all of them on a tall window, the panel right under them; otherwise they scroll, ending on a row.
        let below = Self.sectionGap + (panelShown ? panelSize.height : instructionHeight) + Self.bottomMargin
        let gridHeight = grid.preferredHeight(forWidth: column, available: clip.bounds.height - gridTop - below)
        let panelTop = gridTop + gridHeight + Self.sectionGap
        let total = panelShown ? panelTop + panelSize.height + Self.bottomMargin : panelTop + instructionHeight + Self.bottomMargin
        let instructionTop = panelTop
        let height = max(total, clip.bounds.height).rounded(.up)

        let documentFrame = NSRect(x: 0, y: 0, width: paneWidth, height: height)
        if document.frame != documentFrame { document.frame = documentFrame }
        // The document isn't flipped: y from its top.
        func y(_ top: CGFloat, _ itemHeight: CGFloat) -> CGFloat { height - top - itemHeight }

        Self.place(topBar, NSRect(x: x, y: y(topBarTop, Self.topBarHeight), width: column, height: Self.topBarHeight))
        layOutTopBar(width: column)
        Self.place(grid.view, NSRect(x: x, y: y(gridTop, gridHeight), width: column, height: gridHeight))

        var containerFrame = NSRect(x: ((paneWidth - panelSize.width) / 2).rounded(.down), y: y(panelTop, panelSize.height),
                                    width: panelSize.width, height: panelSize.height)
        containerFrame = containerFrame.integral
        if container.frame != containerFrame {
            // The controller may have started an animated resize of the container; a zero-duration animation of the
            // same property replaces it, so it ends here.
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                context.allowsImplicitAnimation = false
                container.animator().frame = containerFrame
            }
            if container.frame != containerFrame { container.frame = containerFrame }
        }
        laidOutContainerFrame = container.frame
        Self.place(instructionsField, NSRect(x: x, y: y(instructionTop, instructionHeight), width: column, height: instructionHeight))

        // Back to where the user was (the controller's short-window branch scrolled to the top).
        let visibleHeight = clip.bounds.height
        let maximumOrigin = max(0, height - visibleHeight)
        let origin = NSPoint(x: 0, y: min(maximumOrigin, max(0, height - visibleHeight - topDistance)).rounded())
        if clip.bounds.origin != origin {
            clip.scroll(to: origin)
            scrollView.reflectScrolledClipView(clip)
        }
        // A clamped position becomes the user's: the page really is shorter (the panel uses its own size, so no
        // intermediate pass is), and reopening Advanced mustn't jump back to the old, deeper position.
        let distance = max(0, height - visibleHeight - clip.bounds.origin.y)
        if distance < topDistance { topDistance = distance }
    }

    private func layOutTopBar(width: CGFloat) {
        let height = Self.topBarHeight
        // Right to left: ⋯ (square), Favourite, Folder.
        let moreWidth = height
        let favouriteWidth = Self.ghostWidth(favouriteButton)
        let folderWidth = Self.ghostWidth(folderButton)
        let favouriteX = width - moreWidth - Self.buttonGap - favouriteWidth
        Self.place(moreButton, NSRect(x: width - moreWidth, y: 0, width: moreWidth, height: height))
        Self.place(favouriteButton, NSRect(x: favouriteX, y: 0, width: favouriteWidth, height: height))
        Self.place(folderButton, NSRect(x: favouriteX - Self.buttonGap - folderWidth, y: 0, width: folderWidth, height: height))
        let buttonsWidth = moreWidth + favouriteWidth + folderWidth + 2 * Self.buttonGap
        let searchWidth = max(80, min(Self.searchMaximumWidth, width - buttonsWidth - Self.sectionGap))
        Self.place(searchFieldView, NSRect(x: 0, y: 0, width: searchWidth, height: height))
        if let searchField {
            let fieldHeight = ceil(searchField.cell?.cellSize.height ?? 16)
            Self.place(searchField, NSRect(x: Self.searchInset, y: ((height - fieldHeight) / 2).rounded(.down),
                                           width: max(0, searchWidth - 2 * Self.searchInset), height: fieldHeight))
        }
    }

    // MARK: - ⋯ menu

    /// Opens the ⋯ menu under the button, its right edge on the button's: Import, Export (the selection, or every
    /// favourite with none selected) and the gear menu's Sort By.
    @objc private func showMoreMenu(_ sender: NSButton) {
        let menu = SAClaudeConnectionsMenuModel.moreMenu(gearMenu: grid.gearMenu(), target: connectionsCommands,
                                                         importAction: SAClaudeConnectionsCommands.importSelector,
                                                         exportAction: SAClaudeConnectionsCommands.exportSelector)
        // The same "no Ask Siri field" as the card menu.
        SAClaudeMenuGlyphPass.suppressAssistant(in: menu)
        // Glyphs (which widen the menu by their column) and the validated titles go in before it is measured, so its
        // right edge lands on the button's; the pass, as it opens, then finds nothing left to fill.
        SAClaudeMenuGlyphPass.applyGlyphs(to: menu)
        menu.update()
        let origin = SAClaudeConnectionsMenuModel.popUpOrigin(buttonBounds: sender.bounds, isFlipped: sender.isFlipped, menuWidth: menu.size.width)
        menu.popUp(positioning: nil, at: origin, in: sender)
    }

    /// Remembers how far down the user scrolled, unless the controller has just moved the panel (its own centring
    /// and scroll to the top run before the page lays out again).
    private func recordScrollPosition() {
        guard isAttached, !isLayingOut, let scrollView, let document = scrollView.documentView, let container,
              let laidOut = laidOutContainerFrame, container.frame == laidOut else { return }
        topDistance = max(0, document.frame.height - scrollView.contentView.bounds.maxY)
    }
}
