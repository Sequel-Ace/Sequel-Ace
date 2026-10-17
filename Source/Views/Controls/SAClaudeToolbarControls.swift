//
//  SAClaudeToolbarControls.swift
//  Sequel Ace
//
//  The toolbar's two control items drawn as Claude pills: the database
//  picker (glyph, name, chevron) and the history back/forward pair. Menus,
//  actions and enablement are the XIB's and the document's. App target only.
//

import AppKit

@objc(SAClaudeDatabasePopUpButton) final class SAClaudeDatabasePopUpButton: NSPopUpButton {

    private static var titleFont: NSFont { .systemFont(ofSize: 13) }
    private var trackingArea: NSTrackingArea?
    private var isHovered = false { didSet { if isHovered != oldValue { needsDisplay = true } } }

    override func awakeFromNib() {
        super.awakeFromNib()
        isBordered = false
        (cell as? NSPopUpButtonCell)?.arrowPosition = .noArrow
        // The XIB's fixed frame would otherwise win: the toolbar must size the pill from intrinsicContentSize.
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.defaultHigh, for: .horizontal)
        setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        // The pill's database glyph is drawn in the accent: redraw (re-rendering the tinted image) when it changes.
        SAClaudeAccent.observe(self) { $0.needsDisplay = true }
    }

    private var displayTitle: String { titleOfSelectedItem ?? title }

    override var intrinsicContentSize: NSSize {
        let width = (displayTitle as NSString).size(withAttributes: [.font: Self.titleFont]).width
        return NSSize(width: SAClaudeToolbarLayout.databasePillWidth(textWidth: width), height: 32)
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

    // MARK: Claude card

    private lazy var cardAdapter = SAClaudeDatabaseMenuAdapter(popup: self)

    /// Opens the database card instead of the native menu (which stays attached); false when it can't (disabled,
    /// no window, or the card refused the menu), and the caller opens the native menu.
    private func showCard() -> Bool {
        guard isEnabled, let menu else { return false }
        return SAClaudeMenuCardPresenter.shared.show(menu: menu, from: self, adapter: cardAdapter)
    }

    override func mouseDown(with event: NSEvent) {
        if !showCard() { super.mouseDown(with: event) }
    }

    // The pop-up's only job is to open: Space, Return and ↓ (and VoiceOver's press) open the card too.
    override func keyDown(with event: NSEvent) {
        let opensCard = event.modifierFlags.intersection([.command, .control, .option]).isEmpty
            && [49, 36, 76, 125].contains(event.keyCode)  // Space, Return, keypad Enter, ↓
        if !(opensCard && showCard()) { super.keyDown(with: event) }
    }

    override func accessibilityPerformPress() -> Bool {
        showCard() || super.accessibilityPerformPress()
    }

    override func accessibilityPerformShowMenu() -> Bool {
        showCard() || super.accessibilityPerformShowMenu()
    }

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        bounds.intersection(dirtyRect).clip()
        let pill = NSRect(x: bounds.minX, y: bounds.midY - 16, width: bounds.width, height: 32)
        ((isHovered && isEnabled) ? SAClaudeStyle.selection : SAClaudeStyle.hoverFill).setFill()
        NSBezierPath(roundedRect: pill, xRadius: 8, yRadius: 8).fill()

        let alpha: CGFloat = isEnabled ? 1 : 0.35
        let glyphRect = NSRect(x: pill.minX + 10, y: pill.midY - 9, width: 18, height: 18)
        SAClaudeGlyphs.image(.database, tint: SAClaudeStyle.tintDatabase)
            .draw(in: glyphRect, from: .zero, operation: .sourceOver, fraction: alpha, respectFlipped: true, hints: nil)

        let chevronRect = NSRect(x: pill.maxX - 22, y: pill.midY - 8, width: 16, height: 16)
        let titleRect = NSRect(x: glyphRect.maxX + 6, y: pill.minY, width: max(0, chevronRect.minX - glyphRect.maxX - 8), height: pill.height)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [.font: Self.titleFont, .foregroundColor: SAClaudeStyle.textPrimary.withAlphaComponent(alpha), .paragraphStyle: paragraph]
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
        SAClaudeStyle.textMuted.withAlphaComponent(alpha).setStroke()
        chevron.stroke()
    }
}

@objc(SAClaudeHistorySegmentedControl) final class SAClaudeHistorySegmentedControl: NSSegmentedControl {

    private static let segmentWidth: CGFloat = 34
    private var trackingArea: NSTrackingArea?
    private var hoveredSegment: Int? { didSet { if hoveredSegment != oldValue { needsDisplay = true } } }

    override func awakeFromNib() {
        super.awakeFromNib()
        // Adjacent segments without gaps/insets so hit areas match the drawn 30pt halves.
        segmentStyle = .smallSquare
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.defaultHigh, for: .horizontal)
        setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        for segment in 0..<segmentCount { setWidth(Self.segmentWidth, forSegment: segment) }
    }

    override var intrinsicContentSize: NSSize { NSSize(width: Self.segmentWidth * CGFloat(max(segmentCount, 1)), height: 32) }
    override func sizeToFit() { setFrameSize(intrinsicContentSize) }

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

    // MARK: Claude card (press and hold)

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
        NSRect(x: bounds.minX + CGFloat(segment) * Self.segmentWidth, y: bounds.midY - 16, width: Self.segmentWidth, height: 32)
    }

    private func showCard(forSegment segment: Int) -> Bool {
        guard let menu = historyMenu(forSegment: segment) else { return false }
        return SAClaudeMenuCardPresenter.shared.show(menu: menu, from: self, adapter: SAClaudeHistoryEntriesMenuAdapter.shared,
                                                     anchorRect: segmentRect(segment))
    }

    /// A click navigates once; a press held for `holdDelay` (or dragged) opens the segment's history card instead.
    /// While a card is open for this control, a click on either segment only closes it (no navigation).
    override func mouseDown(with event: NSEvent) {
        if SAClaudeMenuCardPresenter.shared.consumesClick(on: self) { return }
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

    // Space/Return keep navigating (super); ↓ opens the card.
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 125, event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
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
        let pill = NSRect(x: bounds.minX, y: bounds.midY - 16, width: bounds.width, height: 32)
        let shape = NSBezierPath(roundedRect: pill, xRadius: 8, yRadius: 8)
        SAClaudeStyle.hoverFill.setFill()
        shape.fill()
        if let hoveredSegment, isEnabled, isEnabled(forSegment: hoveredSegment) {
            NSGraphicsContext.saveGraphicsState()
            shape.addClip()
            SAClaudeStyle.selection.setFill()
            NSRect(x: pill.minX + CGFloat(hoveredSegment) * Self.segmentWidth, y: pill.minY, width: Self.segmentWidth, height: pill.height).fill()
            NSGraphicsContext.restoreGraphicsState()
        }
        SAClaudeStyle.divider.setFill()
        for segment in 1..<max(segmentCount, 1) {
            NSRect(x: pill.minX + CGFloat(segment) * Self.segmentWidth - 0.5, y: pill.minY + 8, width: 1, height: pill.height - 16).fill()
        }
        for segment in 0..<segmentCount {
            let glyph: SAClaudeGlyph = segment == 0 ? .chevronLeft : .chevronRight
            let rect = NSRect(x: pill.minX + CGFloat(segment) * Self.segmentWidth + (Self.segmentWidth - 18) / 2, y: pill.midY - 9, width: 18, height: 18)
            SAClaudeGlyphs.image(glyph, tint: SAClaudeStyle.textMuted)
                .draw(in: rect, from: .zero, operation: .sourceOver, fraction: isEnabled(forSegment: segment) && isEnabled ? 1 : 0.35,
                      respectFlipped: true, hints: nil)
        }
    }
}
