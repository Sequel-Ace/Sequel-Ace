//
//  SADesignToolbarControls.swift
//  Sequel Ace
//
//  The toolbar's two control items drawn as pills: the database
//  picker (glyph, name, chevron) and the history back/forward pair. Menus,
//  actions and enablement are the XIB's and the document's. App target only.
//

import AppKit

@objc(SADesignDatabasePopUpButton) final class SADesignDatabasePopUpButton: NSPopUpButton, SADesignToolbarPalettePreviewing {

    private static var titleFont: NSFont { .systemFont(ofSize: 13) }
    /// The pill's layout, which also sizes it (`SADesignToolbarLayout.databasePillWidth`).
    private typealias Pill = SADesignToolbarLayout.DatabasePill
    private var trackingArea: NSTrackingArea?
    private var isHovered = false { didSet { if isHovered != oldValue { needsDisplay = true } } }
    /// While the pill's card is open, the pill keeps its pressed look.
    private var isCardOpen = false { didSet { if isCardOpen != oldValue { needsDisplay = true } } }
    /// A palette preview's copy: draws as the pill, opens nothing.
    private var isPreview = false

    override func awakeFromNib() {
        super.awakeFromNib()
        configurePill()
    }

    private func configurePill() {
        isBordered = false
        (cell as? NSPopUpButtonCell)?.arrowPosition = .noArrow
        // The XIB's fixed frame would otherwise win: the toolbar must size the pill from intrinsicContentSize.
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.defaultHigh, for: .horizontal)
        setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        // The pill's database glyph is drawn in the accent (made readable on the pill): redraw when it changes.
        SADesignAccent.observe(self) { $0.needsDisplay = true }
    }

    private var displayTitle: String { titleOfSelectedItem ?? title }

    /// The pill as it looks now (its database name), enabled: its menu holds only that name, and it has no target or action.
    func palettePreview() -> NSView {
        let copy = SADesignDatabasePopUpButton(frame: NSRect(origin: .zero, size: intrinsicContentSize), pullsDown: false)
        copy.addItem(withTitle: displayTitle)
        copy.isPreview = true
        copy.configurePill()
        return copy
    }

    /// The drawn pill, 32pt high, centered in the bounds.
    private var pillRect: NSRect { NSRect(x: bounds.minX, y: bounds.midY - 16, width: bounds.width, height: 32) }

    override var intrinsicContentSize: NSSize {
        let width = (displayTitle as NSString).size(withAttributes: [.font: Self.titleFont]).width
        return NSSize(width: SADesignToolbarLayout.databasePillWidth(textWidth: width), height: 32)
    }

    // The document selects items as databases change; keep the pill fitted to the name.
    override func select(_ item: NSMenuItem?) { super.select(item); invalidateIntrinsicContentSize(); needsDisplay = true }
    override func selectItem(at index: Int) { super.selectItem(at: index); invalidateIntrinsicContentSize(); needsDisplay = true }
    override func selectItem(withTitle title: String) { super.selectItem(withTitle: title); invalidateIntrinsicContentSize(); needsDisplay = true }
    override func synchronizeTitleAndSelectedItem() { super.synchronizeTitleAndSelectedItem(); invalidateIntrinsicContentSize(); needsDisplay = true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self)
        addTrackingArea(area)
        trackingArea = area
    }
    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }

    /// The database glyph: the accent, made readable on the pill's fill and on its hover fill.
    static func glyphTint(dark: Bool) -> NSColor {
        SADesignAccent.readableGlyph(on: SADesignStyle.hoverFill, SADesignStyle.selection, dark: dark)
    }

    // MARK: Card

    private lazy var cardAdapter = SADesignDatabaseMenuAdapter(popup: self)

    /// Opens the database card instead of the native menu (which stays attached); false when it can't (disabled,
    /// no window, or the card refused the menu), and the caller opens the native menu.
    private func showCard() -> Bool {
        guard isEnabled, !isPreview, let menu else { return false }
        let presenter = SADesignMenuCardPresenter.shared
        guard presenter.show(menu: menu, from: self, adapter: cardAdapter, onClose: { [weak self] in self?.isCardOpen = false }) else {
            return false
        }
        // A click that closed the card (or toggled it shut) leaves nothing open for this pill.
        isCardOpen = presenter.shownControl === self
        return true
    }

    override func mouseDown(with event: NSEvent) {
        if isPreview { return }
        if !showCard() { super.mouseDown(with: event) }
    }

    // The pop-up's only job is to open: Space, Return, ↓ and ↑ (and VoiceOver's press) open the card too.
    override func keyDown(with event: NSEvent) {
        let opensCard = event.modifierFlags.intersection([.command, .control, .option]).isEmpty
            && [49, 36, 76, 125, 126].contains(event.keyCode)  // Space, Return, keypad Enter, ↓, ↑
        if !(opensCard && showCard()) { super.keyDown(with: event) }
    }

    /// What a key equivalent or a programmatic click opens: the card, as a click does.
    override func performClick(_ sender: Any?) {
        if !showCard() { super.performClick(sender) }
    }

    override func accessibilityPerformPress() -> Bool {
        showCard() || super.accessibilityPerformPress()
    }

    override func accessibilityPerformShowMenu() -> Bool {
        showCard() || super.accessibilityPerformShowMenu()
    }

    // The keyboard focus ring follows the pill's rounded fill.
    override var focusRingMaskBounds: NSRect { pillRect }
    override func drawFocusRingMask() { SADesignToolbarFocusRing.drawMask(pillRect) }

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        bounds.intersection(dirtyRect).clip()
        let pill = pillRect
        // Hovered, or pressed while its card is open: the selection fill.
        (((isHovered || isCardOpen) && isEnabled) ? SADesignStyle.selection : SADesignStyle.hoverFill).setFill()
        NSBezierPath(roundedRect: pill, xRadius: SADesignToolbarFocusRing.radius, yRadius: SADesignToolbarFocusRing.radius).fill()

        let alpha: CGFloat = isEnabled ? 1 : 0.35
        let glyphRect = NSRect(x: pill.minX + Pill.glyphInset, y: pill.midY - Pill.glyphSize / 2, width: Pill.glyphSize, height: Pill.glyphSize)
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        SADesignGlyphs.image(.database, tint: Self.glyphTint(dark: dark))
            .draw(in: glyphRect, from: .zero, operation: .sourceOver, fraction: alpha, respectFlipped: true, hints: nil)

        let chevronRect = NSRect(x: pill.maxX - Pill.chevronInset - Pill.chevronSize, y: pill.midY - Pill.chevronSize / 2,
                                 width: Pill.chevronSize, height: Pill.chevronSize)
        let titleX = glyphRect.maxX + Pill.titleGap
        let titleRect = NSRect(x: titleX, y: pill.minY, width: max(0, chevronRect.minX - Pill.titleChevronGap - titleX), height: pill.height)
        let paragraph = NSMutableParagraphStyle()
        // A long name keeps its start and its end, as the native pop-up did.
        paragraph.lineBreakMode = .byTruncatingMiddle
        let attributes: [NSAttributedString.Key: Any] = [.font: Self.titleFont, .foregroundColor: SADesignStyle.textPrimary.withAlphaComponent(alpha), .paragraphStyle: paragraph]
        let size = (displayTitle as NSString).size(withAttributes: attributes)
        (displayTitle as NSString).draw(in: NSRect(x: titleRect.minX, y: (titleRect.midY - size.height / 2).rounded(), width: titleRect.width, height: size.height),
                                        withAttributes: attributes)

        let chevron = NSBezierPath()
        let c = NSPoint(x: chevronRect.midX, y: chevronRect.midY)
        let up: CGFloat = isFlipped ? -1 : 1
        chevron.move(to: NSPoint(x: c.x - 3.5, y: c.y + 1.75 * up))
        chevron.line(to: NSPoint(x: c.x, y: c.y - 1.75 * up))
        chevron.line(to: NSPoint(x: c.x + 3.5, y: c.y + 1.75 * up))
        chevron.lineWidth = 1.5
        chevron.lineCapStyle = .round
        chevron.lineJoinStyle = .round
        SADesignStyle.textMuted.withAlphaComponent(alpha).setStroke()
        chevron.stroke()
    }
}

@objc(SADesignHistorySegmentedControl) final class SADesignHistorySegmentedControl: NSSegmentedControl, SADesignToolbarPalettePreviewing {

    private static let segmentWidth: CGFloat = 34
    private var trackingArea: NSTrackingArea?
    private var hoveredSegment: Int? { didSet { if hoveredSegment != oldValue { needsDisplay = true } } }
    /// The segment whose history card is open: it keeps its pressed look until the card closes.
    private var cardSegment: Int? { didSet { if cardSegment != oldValue { needsDisplay = true } } }

    override func awakeFromNib() {
        super.awakeFromNib()
        configurePill()
    }

    private func configurePill() {
        // Adjacent segments without gaps/insets so hit areas match the drawn 30pt halves.
        segmentStyle = .smallSquare
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.defaultHigh, for: .horizontal)
        setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        for segment in 0..<segmentCount { setWidth(Self.segmentWidth, forSegment: segment) }
    }

    override var intrinsicContentSize: NSSize { NSSize(width: Self.segmentWidth * CGFloat(max(segmentCount, 1)), height: 32) }
    override func sizeToFit() { setFrameSize(intrinsicContentSize) }

    /// The pill with both chevrons enabled, with no menus, target or action.
    func palettePreview() -> NSView {
        let copy = SADesignHistorySegmentedControl(frame: NSRect(origin: .zero, size: intrinsicContentSize))
        copy.trackingMode = .momentary
        copy.segmentCount = segmentCount
        copy.configurePill()
        return copy
    }

    /// The drawn pill, 32pt high, centered in the bounds.
    private var pillRect: NSRect { NSRect(x: bounds.minX, y: bounds.midY - 16, width: bounds.width, height: 32) }

    // The keyboard focus ring follows the pill's rounded fill (the whole pill, not one segment).
    override var focusRingMaskBounds: NSRect { pillRect }
    override func drawFocusRingMask() { SADesignToolbarFocusRing.drawMask(pillRect) }

    // MARK: Toolbar label

    override var isEnabled: Bool { didSet { syncToolbarItemEnabled() } }

    override func setEnabled(_ enabled: Bool, forSegment segment: Int) {
        super.setEnabled(enabled, forSegment: segment)
        syncToolbarItemEnabled()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        syncToolbarItemEnabled()
    }

    /// Dims the toolbar item (its "Table History" label) with the chevrons (see `SADesignToolbarLayout.historyLabelEnabled`).
    private func syncToolbarItemEnabled() {
        guard let items = window?.toolbar?.items else { return }
        let enabled = SADesignToolbarLayout.historyLabelEnabled(controlEnabled: isEnabled,
                                                                segmentsEnabled: (0..<segmentCount).map { isEnabled(forSegment: $0) })
        for item in items where item.view.map({ isDescendant(of: $0) }) == true && item.isEnabled != enabled {
            item.isEnabled = enabled
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self)
        addTrackingArea(area)
        trackingArea = area
    }
    private func segment(at event: NSEvent) -> Int? {
        guard segmentCount > 0 else { return nil }
        let x = convert(event.locationInWindow, from: nil).x
        return min(segmentCount - 1, max(0, Int(x / Self.segmentWidth)))
    }
    override func mouseMoved(with event: NSEvent) { hoveredSegment = segment(at: event) }
    override func mouseEntered(with event: NSEvent) { hoveredSegment = segment(at: event) }
    override func mouseExited(with event: NSEvent) { hoveredSegment = nil }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }

    // MARK: Card (press and hold)

    /// How long a press waits for its mouse-up before it opens the segment's history card.
    static let holdDelay: TimeInterval = 0.35
    /// How far a press may move and still count as a click.
    private static let dragSlop: CGFloat = 4

    /// The segment a click handled here is navigating with, while its action runs.
    private var clickedSegment: Int?

    override var selectedSegment: Int {
        get { clickedSegment ?? super.selectedSegment }
        set { super.selectedSegment = newValue }
    }

    /// The segment's history menu when it can open one (control and segment enabled, entries present).
    private func historyMenu(forSegment segment: Int) -> NSMenu? {
        guard isEnabled, segment >= 0, segment < segmentCount, isEnabled(forSegment: segment),
              let menu = menu(forSegment: segment), menu.numberOfItems > 0 else { return nil }
        return menu
    }

    /// The drawn half of the pill for `segment`, in the control's coordinates: the card's anchor.
    private func segmentRect(_ segment: Int) -> NSRect {
        NSRect(x: pillRect.minX + CGFloat(segment) * Self.segmentWidth, y: pillRect.minY, width: Self.segmentWidth, height: pillRect.height)
    }

    private func showCard(forSegment segment: Int) -> Bool {
        guard let menu = historyMenu(forSegment: segment) else { return false }
        let presenter = SADesignMenuCardPresenter.shared
        guard presenter.show(menu: menu, from: self, adapter: SADesignHistoryEntriesMenuAdapter.shared, anchorRect: segmentRect(segment),
                             onClose: { [weak self] in self?.cardSegment = nil }) else { return false }
        cardSegment = presenter.shownControl === self ? segment : nil
        return true
    }

    /// A click navigates once; a press held for `holdDelay` (or dragged) opens the segment's history card instead.
    /// While a card is open for this control, a click on either segment only closes it (no navigation).
    override func mouseDown(with event: NSEvent) {
        if SADesignMenuCardPresenter.shared.consumesClick(on: self) { return }
        guard let segment = segment(at: event), historyMenu(forSegment: segment) != nil, let window else {
            super.mouseDown(with: event)
            return
        }
        let deadline = Date(timeIntervalSinceNow: Self.holdDelay)
        let start = event.locationInWindow
        while let next = window.nextEvent(matching: [.leftMouseUp, .leftMouseDragged], until: deadline, inMode: .eventTracking, dequeue: true) {
            if next.type == .leftMouseUp {
                // Exactly one navigation. SPHistoryController -historyControlClicked: reads selectedSegment, which a
                // momentary control reports only while it tracks a click itself (setting it is ignored): report the
                // pressed segment for the action, -1 again after it, as a native click does.
                clickedSegment = segment
                defer { clickedSegment = nil }
                sendAction(action, to: target)
                return
            }
            // A real drag opens the card at once; a click's few points of jitter keep waiting for its mouse-up.
            if hypot(next.locationInWindow.x - start.x, next.locationInWindow.y - start.y) > Self.dragSlop { break }
        }
        if !showCard(forSegment: segment) { super.mouseDown(with: event) }
    }

    /// The segment ↓ / VoiceOver's "show menu" opens: the selected one if it has history, else the first that has
    /// (a momentary control has no selected segment outside a click, so in practice Back, else Forward).
    private var keyboardSegment: Int? {
        if historyMenu(forSegment: selectedSegment) != nil { return selectedSegment }
        return (0..<segmentCount).first { historyMenu(forSegment: $0) != nil }
    }

    // Space/Return keep navigating (super); ↓ and ↑ open the card.
    override func keyDown(with event: NSEvent) {
        if [125, 126].contains(event.keyCode), event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
           let segment = keyboardSegment, showCard(forSegment: segment) { return }
        super.keyDown(with: event)
    }

    override func accessibilityPerformShowMenu() -> Bool {
        if let segment = keyboardSegment, showCard(forSegment: segment) { return true }
        return super.accessibilityPerformShowMenu()
    }

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        bounds.intersection(dirtyRect).clip()
        let pill = pillRect
        let shape = NSBezierPath(roundedRect: pill, xRadius: SADesignToolbarFocusRing.radius, yRadius: SADesignToolbarFocusRing.radius)
        SADesignStyle.hoverFill.setFill()
        shape.fill()
        // The hovered segment, and the one whose card is open (pressed): the selection fill.
        for segment in Set([hoveredSegment, cardSegment].compactMap { $0 }) where isEnabled && segment < segmentCount && isEnabled(forSegment: segment) {
            NSGraphicsContext.saveGraphicsState()
            shape.addClip()
            SADesignStyle.selection.setFill()
            NSRect(x: pill.minX + CGFloat(segment) * Self.segmentWidth, y: pill.minY, width: Self.segmentWidth, height: pill.height).fill()
            NSGraphicsContext.restoreGraphicsState()
        }
        SADesignStyle.divider.setFill()
        for segment in 1..<max(segmentCount, 1) {
            NSRect(x: pill.minX + CGFloat(segment) * Self.segmentWidth - 0.5, y: pill.minY + SASpacing.xSmall, width: 1,
                   height: pill.height - 2 * SASpacing.xSmall).fill()
        }
        for segment in 0..<segmentCount {
            let glyph: SADesignGlyph = segment == 0 ? .chevronLeft : .chevronRight
            let rect = NSRect(x: pill.minX + CGFloat(segment) * Self.segmentWidth + (Self.segmentWidth - 18) / 2, y: pill.midY - 9, width: 18, height: 18)
            SADesignGlyphs.image(glyph, tint: SADesignStyle.textMuted)
                .draw(in: rect, from: .zero, operation: .sourceOver, fraction: isEnabled(forSegment: segment) && isEnabled ? 1 : 0.35,
                      respectFlipped: true, hints: nil)
        }
    }
}
