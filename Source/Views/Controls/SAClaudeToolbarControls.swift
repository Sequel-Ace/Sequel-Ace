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
    }

    private var displayTitle: String { titleOfSelectedItem ?? title }

    override var intrinsicContentSize: NSSize {
        let width = (displayTitle as NSString).size(withAttributes: [.font: Self.titleFont]).width
        return NSSize(width: SAClaudeToolbarLayout.databasePillWidth(textWidth: width), height: 28)
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

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        bounds.intersection(dirtyRect).clip()
        let pill = NSRect(x: bounds.minX, y: bounds.midY - 14, width: bounds.width, height: 28)
        ((isHovered && isEnabled) ? SAClaudeStyle.selection : SAClaudeStyle.hoverFill).setFill()
        NSBezierPath(roundedRect: pill, xRadius: 8, yRadius: 8).fill()

        let alpha: CGFloat = isEnabled ? 1 : 0.35
        let glyphRect = NSRect(x: pill.minX + 10, y: pill.midY - 8, width: 16, height: 16)
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

    private static let segmentWidth: CGFloat = 30
    private var trackingArea: NSTrackingArea?
    private var hoveredSegment: Int? { didSet { if hoveredSegment != oldValue { needsDisplay = true } } }

    override func awakeFromNib() {
        super.awakeFromNib()
        // Adjacent segments without gaps/insets so hit areas match the drawn 30pt halves.
        segmentStyle = .smallSquare
        translatesAutoresizingMaskIntoConstraints = false
        for segment in 0..<segmentCount { setWidth(Self.segmentWidth, forSegment: segment) }
    }

    override var intrinsicContentSize: NSSize { NSSize(width: Self.segmentWidth * CGFloat(max(segmentCount, 1)), height: 28) }
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

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        bounds.intersection(dirtyRect).clip()
        let pill = NSRect(x: bounds.minX, y: bounds.midY - 14, width: bounds.width, height: 28)
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
            NSRect(x: pill.minX + CGFloat(segment) * Self.segmentWidth - 0.5, y: pill.minY + 7, width: 1, height: pill.height - 14).fill()
        }
        for segment in 0..<segmentCount {
            let glyph: SAClaudeGlyph = segment == 0 ? .chevronLeft : .chevronRight
            let rect = NSRect(x: pill.minX + CGFloat(segment) * Self.segmentWidth + (Self.segmentWidth - 16) / 2, y: pill.midY - 8, width: 16, height: 16)
            SAClaudeGlyphs.image(glyph, tint: SAClaudeStyle.textMuted)
                .draw(in: rect, from: .zero, operation: .sourceOver, fraction: isEnabled(forSegment: segment) && isEnabled ? 1 : 0.35,
                      respectFlipped: true, hints: nil)
        }
    }
}
