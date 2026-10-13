//
//  SAClaudeFavoriteCardGridView.swift
//  Sequel Ace
//
//  The connection screen's favourite cards: a flipped view (the document view of its own scroll view) that draws
//  the cards and folder headers laid out by `SAClaudeFavoriteCardLayout`, and turns clicks, keys, right-clicks and
//  drags into requests to its owner (`SAClaudeFavoriteCardGridController`), which drives the hidden favourites
//  outline. The view holds no favourites state of its own beyond what it draws.
//  App target only.
//

import AppKit

final class SAClaudeFavoriteCardGridView: NSView, NSDraggingSource {

    struct Colours {
        var text: NSColor = .labelColor
        var muted: NSColor = .secondaryLabelColor
        var hairline: NSColor = .separatorColor
        var hoverStroke: NSColor = .tertiaryLabelColor
        var cardFill: NSColor = .controlBackgroundColor
        /// Quick connect's dashed outline.
        var dashedStroke: NSColor = .tertiaryLabelColor
        var dropFill: NSColor = .selectedContentBackgroundColor
    }

    /// The private drag type: the dragged card's ID, within this app only.
    static let dragType = NSPasteboard.PasteboardType("com.sequel-ace.claude.favorite-card")

    typealias Layout = SAClaudeFavoriteCardLayout

    // MARK: Owner hooks

    /// A card or folder header was clicked (or chosen with the arrow keys).
    var onSelect: ((String) -> Void)?
    /// A favourite card was double-clicked, or Return / Enter was pressed with one selected.
    var onActivate: ((String) -> Void)?
    /// The menu for a right-click on a card or folder header (`nil` ID: empty space).
    var menuProvider: ((String?) -> NSMenu?)?
    /// Whether this card may be dragged now.
    var canDrag: ((String) -> Bool)?
    /// Whether dropping this card at this target would move it.
    var canDrop: ((String, Layout.DropTarget) -> Bool)?
    /// Performs the drop; `true` when the favourite moved.
    var onDrop: ((String, Layout.DropTarget) -> Bool)?
    /// `false` while connecting (the outline is disabled then): clicks, keys and drags are ignored.
    var isInteractive: () -> Bool = { true }
    /// The colour for a favourite colour index, resolved at draw time under the view's appearance.
    var favouriteColour: (Int) -> NSColor? = { _ in nil }

    // MARK: State

    var colours = Colours() { didSet { needsDisplay = true } }
    /// The selected card or folder (the hidden outline's first selected row).
    var selectedID: String? {
        didSet {
            guard selectedID != oldValue else { return }
            needsDisplay = true
            noteFocusRingMaskChanged()
            if let selectedID, let frame = frame(of: selectedID) { scrollToVisible(frame.insetBy(dx: 0, dy: -Layout.gap)) }
            NSAccessibility.post(element: self, notification: .selectedChildrenChanged)
        }
    }
    /// The unsaved-edits dot on the selected card.
    var showsUnsavedDot = false { didSet { if showsUnsavedDot != oldValue { needsDisplay = true } } }
    /// A search is active: an empty result shows "No favourites match".
    var isFiltering = false

    private(set) var model = SAClaudeFavoriteGridModel(topLevel: [], folders: [])
    private(set) var items: [Layout.Item] = []
    private(set) var contentHeight: CGFloat = 0
    private var cardsByID: [String: SAClaudeFavoriteCard] = [:]
    private var foldersByID: [String: SAClaudeFavoriteFolder] = [:]

    private var hoverID: String? { didSet { if hoverID != oldValue { needsDisplay = true } } }
    private var dropTarget: Layout.DropTarget? { didSet { if dropTarget != oldValue { needsDisplay = true } } }
    private var mouseDownID: String?
    private var mouseDownPoint: NSPoint?
    private var draggedID: String?
    private var trackingArea: NSTrackingArea?
    private var accessibilityCards: [SAClaudeFavoriteCardAccessibilityElement] = []

    private static let nameFont = NSFont.systemFont(ofSize: 13, weight: .medium)
    private static let summaryFont = NSFont.systemFont(ofSize: 11)
    private static let badgeFont = NSFont.systemFont(ofSize: 10, weight: .medium)
    private static let headerFont = NSFont.systemFont(ofSize: 11)
    private static let messageFont = NSFont.systemFont(ofSize: 12)
    private static let padding: CGFloat = 12
    private static let dotSize: CGFloat = 6
    private static let dragThreshold: CGFloat = 4
    private static let autoscrollMargin: CGFloat = 20
    private static let gradientStart: CGFloat = 0.33
    private static let gradientEnd: CGFloat = 0.07

    private static let noMatches = NSLocalizedString("ClaudeFavoriteCardsNoMatches", value: "No favourites match",
                                                     comment: "connection screen : shown in the favourite cards when the search matches nothing")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([Self.dragType])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { true }

    // MARK: - Model and layout

    /// Shows `model` laid out at `width`; the view is at least `minimumHeight` tall so the space below the cards
    /// still takes drops (the end of the top level or the last folder).
    func update(model: SAClaudeFavoriteGridModel, width: CGFloat, minimumHeight: CGFloat) {
        self.model = model
        let layout = Layout.items(for: model, width: max(width, 1))
        items = layout.items
        contentHeight = layout.contentHeight
        cardsByID = Dictionary(model.allCards.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        foldersByID = Dictionary(model.folders.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        if let hoverID, frame(of: hoverID) == nil { self.hoverID = nil }
        setFrameSize(NSSize(width: max(width, 1), height: max(contentHeight, minimumHeight)))
        rebuildAccessibilityElements()
        needsDisplay = true
        noteFocusRingMaskChanged()
    }

    func frame(of id: String) -> NSRect? {
        items.first { $0.kind == .card(id) || $0.kind == .folderHeader(id) }?.frame
    }

    private func item(at point: NSPoint) -> Layout.Item? {
        items.first { $0.frame.contains(point) }
    }

    private func id(of item: Layout.Item) -> String {
        switch item.kind {
        case .card(let id), .folderHeader(let id): return id
        }
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        for item in items where item.frame.intersects(dirtyRect) {
            switch item.kind {
            case .card(let id):
                guard let card = cardsByID[id] else { continue }
                if card.isQuickConnect { drawQuickConnect(card, in: item.frame) } else { drawCard(card, in: item.frame) }
            case .folderHeader(let id):
                guard let folder = foldersByID[id] else { continue }
                drawHeader(folder, in: item.frame)
            }
        }
        if isFiltering, model.allCards.allSatisfy(\.isQuickConnect) { drawNoMatches() }
        drawDropIndicator()
    }

    private func cardPath(_ frame: NSRect, inset: CGFloat) -> NSBezierPath {
        let radius = Layout.radius - inset
        return NSBezierPath(roundedRect: frame.insetBy(dx: inset, dy: inset), xRadius: radius, yRadius: radius)
    }

    private func drawCard(_ card: SAClaudeFavoriteCard, in frame: NSRect) {
        let fill = cardPath(frame, inset: 0)
        colours.cardFill.setFill()
        fill.fill()
        if let index = card.colorIndex, let colour = favouriteColour(index) {
            // A diagonal wash of the favourite colour over the card fill, strongest at the top left.
            let start = SAClaudeEditorChrome.derivedColour(text: colour, background: colours.cardFill, ratio: Self.gradientStart)
            let end = SAClaudeEditorChrome.derivedColour(text: colour, background: colours.cardFill, ratio: Self.gradientEnd)
            NSGradient(starting: start, ending: end)?.draw(in: fill, angle: 45)
        }
        drawOutline(card, in: frame)

        // Badge (top right), then the name beside it and the summary below.
        var nameMaxX = frame.maxX - Self.padding
        if !card.badge.isEmpty {
            let badge = NSAttributedString(string: card.badge, attributes: [.font: Self.badgeFont, .foregroundColor: colours.muted])
            let size = badge.size()
            let pill = NSRect(x: frame.maxX - 10 - ceil(size.width) - 12, y: frame.minY + 11, width: ceil(size.width) + 12, height: 16)
            colours.text.withAlphaComponent(0.07).setFill()
            NSBezierPath(roundedRect: pill, xRadius: 8, yRadius: 8).fill()
            badge.draw(at: NSPoint(x: pill.minX + 6, y: pill.midY - size.height / 2))
            nameMaxX = pill.minX - 8
        }
        let x = frame.minX + Self.padding
        drawText(card.name, font: Self.nameFont, colour: colours.text,
                 in: NSRect(x: x, y: frame.minY + 11, width: max(0, nameMaxX - x), height: 18))
        drawText(card.summary, font: Self.summaryFont, colour: colours.muted,
                 in: NSRect(x: x, y: frame.minY + 35, width: max(0, frame.maxX - Self.padding - x), height: 16))

        if showsUnsavedDot, card.id == selectedID {
            SAClaudeStatusChrome.clay.setFill()
            NSBezierPath(ovalIn: NSRect(x: frame.minX + 5, y: frame.minY + 5, width: Self.dotSize, height: Self.dotSize)).fill()
        }
    }

    private func drawQuickConnect(_ card: SAClaudeFavoriteCard, in frame: NSRect) {
        let path = cardPath(frame, inset: 0.5)
        path.lineWidth = 1
        path.setLineDash([4, 3], count: 2, phase: 0)
        (card.id == hoverID ? colours.hoverStroke : colours.dashedStroke).setStroke()
        path.stroke()
        if card.id == selectedID { drawSelection(in: frame) }

        let glyphSize: CGFloat = 16
        let glyph = NSRect(x: frame.minX + Self.padding + 2, y: frame.midY - glyphSize / 2, width: glyphSize, height: glyphSize)
        drawSymbol("bolt", pointSize: 14, colour: colours.muted, in: glyph)
        let x = glyph.maxX + 10
        let width = max(0, frame.maxX - Self.padding - x)
        drawText(card.name, font: Self.nameFont, colour: colours.text, in: NSRect(x: x, y: frame.minY + 11, width: width, height: 18))
        drawText(card.summary, font: Self.summaryFont, colour: colours.muted, in: NSRect(x: x, y: frame.minY + 35, width: width, height: 16))
    }

    private func drawOutline(_ card: SAClaudeFavoriteCard, in frame: NSRect) {
        if card.id == selectedID {
            drawSelection(in: frame)
            return
        }
        let path = cardPath(frame, inset: 0.5)
        path.lineWidth = 1
        (card.id == hoverID ? colours.hoverStroke : colours.hairline).setStroke()
        path.stroke()
    }

    private func drawSelection(in frame: NSRect) {
        let path = cardPath(frame, inset: 1)
        path.lineWidth = 2
        SAClaudeStatusChrome.clay.setStroke()
        path.stroke()
    }

    private func drawHeader(_ folder: SAClaudeFavoriteFolder, in frame: NSRect) {
        if dropTarget == .into(folderID: folder.id) || (dropTarget == .endOf(folderID: folder.id) && folder.cards.isEmpty) {
            let highlight = NSBezierPath(roundedRect: frame.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
            colours.dropFill.setFill()
            highlight.fill()
            highlight.lineWidth = 1
            SAClaudeStatusChrome.clay.setStroke()
            highlight.stroke()
        }
        let selected = folder.id == selectedID
        let colour = selected ? SAClaudeStatusChrome.clay : colours.muted
        let glyph = NSRect(x: frame.minX + 4, y: frame.midY - 7, width: 14, height: 14)
        drawSymbol("folder", pointSize: 11, colour: colour, in: glyph)
        drawText(folder.title, font: Self.headerFont, colour: selected ? SAClaudeStatusChrome.clay : colours.muted,
                 in: NSRect(x: glyph.maxX + 6, y: frame.midY - 7, width: max(0, frame.maxX - glyph.maxX - 10), height: 15))
    }

    private func drawNoMatches() {
        guard let quickConnect = items.first(where: { $0.kind == .card(SAClaudeFavoriteGridModel.quickConnectID) })?.frame else { return }
        let besideQuickConnect = quickConnect.maxX + Layout.gap + 160 <= bounds.maxX
        let rect = besideQuickConnect
            ? NSRect(x: quickConnect.maxX + Layout.gap + 6, y: quickConnect.midY - 8, width: bounds.maxX - quickConnect.maxX - Layout.gap - 6, height: 17)
            : NSRect(x: quickConnect.minX + 6, y: quickConnect.maxY + 8, width: bounds.width - 6, height: 17)
        drawText(Self.noMatches, font: Self.messageFont, colour: colours.muted, in: rect)
    }

    private func drawDropIndicator() {
        guard let dropTarget, let bar = insertionBar(for: dropTarget) else { return }
        SAClaudeStatusChrome.clay.setFill()
        NSBezierPath(roundedRect: bar, xRadius: 1, yRadius: 1).fill()
    }

    /// The clay bar for a reorder target; `nil` when the folder header shows the target instead.
    private func insertionBar(for target: Layout.DropTarget) -> NSRect? {
        let width: CGFloat = 2
        switch target {
        case .before(let cardID, _):
            guard let card = frame(of: cardID) else { return nil }
            return NSRect(x: max(0, card.minX - Layout.gap / 2 - width / 2), y: card.minY, width: width, height: card.height)
        case .endOf(let folderID):
            let cards = folderID.map { foldersByID[$0]?.cards ?? [] } ?? model.topLevel
            guard let last = cards.last, let card = frame(of: last.id) else { return nil }
            return NSRect(x: min(bounds.maxX - width, card.maxX + Layout.gap / 2 - width / 2), y: card.minY, width: width, height: card.height)
        case .into:
            return nil
        }
    }

    private func drawText(_ string: String, font: NSFont, colour: NSColor, in rect: NSRect) {
        guard rect.width > 0, !string.isEmpty else { return }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: colour, .paragraphStyle: paragraph])
            .draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }

    private func drawSymbol(_ name: String, pointSize: CGFloat, colour: NSColor, in rect: NSRect) {
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
                .applying(NSImage.SymbolConfiguration(paletteColors: [colour]))) else { return }
        let size = symbol.size
        let target = NSRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height)
        symbol.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    // MARK: - Focus ring

    override var focusRingMaskBounds: NSRect {
        selectedID.flatMap { frame(of: $0) } ?? .zero
    }

    override func drawFocusRingMask() {
        guard let selectedID, let frame = frame(of: selectedID) else { return }
        if cardsByID[selectedID] != nil {
            cardPath(frame, inset: 0).fill()
        } else {
            NSBezierPath(roundedRect: frame, xRadius: 6, yRadius: 6).fill()
        }
    }

    // MARK: - Mouse

    override func updateTrackingAreas() {
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
        super.updateTrackingAreas()
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let item = item(at: point), case .card(let id) = item.kind { hoverID = id } else { hoverID = nil }
    }

    override func mouseExited(with event: NSEvent) {
        hoverID = nil
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownID = nil
        mouseDownPoint = nil
        guard isInteractive() else { return }
        // Becoming first responder first ends any edit in the panel, as clicking the outline did.
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        guard let item = item(at: point) else { return }
        let id = id(of: item)
        onSelect?(id)
        if case .card = item.kind {
            if event.clickCount == 2 {
                onActivate?(id)
            } else {
                mouseDownID = id
                mouseDownPoint = point
            }
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let id = mouseDownID, let start = mouseDownPoint, isInteractive() else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard hypot(point.x - start.x, point.y - start.y) >= Self.dragThreshold else { return }
        mouseDownID = nil
        guard let card = cardsByID[id], !card.isQuickConnect, canDrag?(id) ?? false, let frame = frame(of: id) else { return }

        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(id, forType: Self.dragType)
        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
        draggingItem.setDraggingFrame(frame, contents: snapshot(of: frame))
        draggedID = id
        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        mouseDownID = nil
        mouseDownPoint = nil
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard isInteractive() else { return nil }
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        return menuProvider?(item(at: point).map(id(of:)))
    }

    private func snapshot(of rect: NSRect) -> NSImage {
        let image = NSImage(size: rect.size)
        if let rep = bitmapImageRepForCachingDisplay(in: rect) {
            cacheDisplay(in: rect, to: rep)
            image.addRepresentation(rep)
        }
        return image
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        guard isInteractive() else {
            super.keyDown(with: event)
            return
        }
        let direction: Layout.MoveDirection?
        switch event.keyCode {
        case 123: direction = .left
        case 124: direction = .right
        case 125: direction = .down
        case 126: direction = .up
        case 36, 76:
            // Return / Enter connects, as on the outline.
            if let selectedID, cardsByID[selectedID] != nil { onActivate?(selectedID) }
            return
        default: direction = nil
        }
        guard let direction else {
            super.keyDown(with: event)
            return
        }
        let current = selectedID.flatMap { cardsByID[$0] != nil ? $0 : nil }
        if let next = Layout.neighbour(of: current, direction, items: items) {
            onSelect?(next)
        } else {
            NSSound.beep()
        }
    }

    // MARK: - Dragging source

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? .move : []
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        draggedID = nil
        dropTarget = nil
    }

    // MARK: - Dragging destination

    private func target(for sender: NSDraggingInfo) -> (id: String, target: Layout.DropTarget)? {
        guard (sender.draggingSource as? SAClaudeFavoriteCardGridView) === self, let id = draggedID, isInteractive() else { return nil }
        let point = convert(sender.draggingLocation, from: nil)
        guard let target = Layout.dropTarget(at: point, items: items, model: model), canDrop?(id, target) ?? false else { return nil }
        return (id, target)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        draggingUpdated(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        autoscroll(to: convert(sender.draggingLocation, from: nil))
        let resolved = target(for: sender)
        dropTarget = resolved?.target
        return resolved == nil ? [] : .move
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        dropTarget = nil
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer { dropTarget = nil }
        guard let (id, target) = target(for: sender) else { return false }
        return onDrop?(id, target) ?? false
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        dropTarget = nil
    }

    /// Scrolls the capped grid while a drag hovers near its top or bottom edge.
    private func autoscroll(to point: NSPoint) {
        let visible = visibleRect
        guard visible.height < bounds.height else { return }
        let step: CGFloat = 12
        if point.y < visible.minY + Self.autoscrollMargin {
            scroll(NSPoint(x: visible.minX, y: max(0, visible.minY - step)))
        } else if point.y > visible.maxY - Self.autoscrollMargin {
            scroll(NSPoint(x: visible.minX, y: min(bounds.height - visible.height, visible.minY + step)))
        }
    }

    // MARK: - Accessibility

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .list }
    override func accessibilityLabel() -> String? {
        NSLocalizedString("ClaudeFavoriteCardsAccessibility", value: "Favourites", comment: "connection screen : accessibility name of the favourite cards")
    }
    override func accessibilityChildren() -> [Any]? { accessibilityCards }
    override func accessibilitySelectedChildren() -> [Any]? { accessibilityCards.filter { $0.cardID == selectedID } }

    private func rebuildAccessibilityElements() {
        accessibilityCards = model.allCards.compactMap { card in
            guard let frame = frame(of: card.id) else { return nil }
            let element = SAClaudeFavoriteCardAccessibilityElement()
            element.cardID = card.id
            element.owner = self
            element.setAccessibilityRole(.button)
            element.setAccessibilityLabel([card.name, card.summary, card.badge].filter { !$0.isEmpty }.joined(separator: ", "))
            element.setAccessibilityFrameInParentSpace(frame)
            element.setAccessibilityParent(self)
            return element
        }
    }

    fileprivate func pressAccessibilityCard(_ id: String) {
        guard isInteractive() else { return }
        onSelect?(id)
    }
}

/// One card for VoiceOver; pressing it selects the card.
private final class SAClaudeFavoriteCardAccessibilityElement: NSAccessibilityElement {
    var cardID = ""
    weak var owner: SAClaudeFavoriteCardGridView?

    override func accessibilityPerformPress() -> Bool {
        owner?.pressAccessibilityCard(cardID)
        return owner != nil
    }
}
