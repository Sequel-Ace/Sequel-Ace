//
//  SAClaudeExportTokenChips.swift
//  Sequel Ace
//
//  The Customise popover's filename tokens as Claude outline chips, in place of the native token pool field: a
//  wrapping row of chips, each a small hairline-outlined button with a muted "+" and the token's name. A click adds
//  the token to the filename field (the popover does the adding); a drag carries the same pasteboard content the
//  controller writes for its own token fields, so a drop goes through the controller's `readFromPasteboard`.
//  App target only.
//

import AppKit

/// One token chip: click to add, drag into the field.
final class SAClaudeExportTokenChip: NSView, NSDraggingSource {

    struct Colours: Equatable {
        var stroke: NSColor
        var hoverStroke: NSColor
        var text: NSColor
        var muted: NSColor
    }

    static let height: CGFloat = 22
    private static let radius: CGFloat = 6
    private static let padding: CGFloat = 8
    private static let glyphSize: CGFloat = 9
    private static let glyphGap: CGFloat = 4
    private static let dragThreshold: CGFloat = 3
    private static let font = NSFont.systemFont(ofSize: 12)

    let tokenId: String
    let title: String
    var colours: Colours { didSet { if oldValue != colours { needsDisplay = true } } }
    /// Called on a click (not a drag) and on an accessibility press.
    var onClick: (() -> Void)?

    private var isHovered = false { didSet { if oldValue != isHovered { needsDisplay = true } } }
    private var mouseDownEvent: NSEvent?
    private var isDragging = false

    init(tokenId: String, title: String, colours: Colours) {
        self.tokenId = tokenId
        self.title = title
        self.colours = colours
        super.init(frame: .zero)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self, userInfo: nil))
    }

    required init?(coder: NSCoder) { nil }

    /// The chip's width: padding, "+", gap, title, padding.
    var preferredWidth: CGFloat {
        ceil(2 * Self.padding + Self.glyphSize + Self.glyphGap + NSAttributedString(string: title, attributes: [.font: Self.font]).size().width)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        let outline = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: Self.radius, yRadius: Self.radius)
        outline.lineWidth = 1
        (isHovered ? colours.hoverStroke : colours.stroke).setStroke()
        outline.stroke()

        let configuration = NSImage.SymbolConfiguration(pointSize: Self.glyphSize, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [colours.muted]))
        if let plus = NSImage(systemSymbolName: "plus", accessibilityDescription: nil)?.withSymbolConfiguration(configuration) {
            let size = plus.size
            plus.draw(in: NSRect(x: Self.padding + (Self.glyphSize - size.width) / 2, y: (bounds.midY - size.height / 2).rounded(),
                                 width: size.width, height: size.height))
        }

        let text = NSAttributedString(string: title, attributes: [.font: Self.font, .foregroundColor: colours.text])
        let textHeight = ceil(text.size().height)
        let x = Self.padding + Self.glyphSize + Self.glyphGap
        text.draw(with: NSRect(x: x, y: (bounds.midY - textHeight / 2).rounded(), width: max(0, bounds.width - x - Self.padding), height: textHeight),
                  options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }

    // MARK: Mouse

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !isDragging, let start = mouseDownEvent else { return }
        let dx = event.locationInWindow.x - start.locationInWindow.x, dy = event.locationInWindow.y - start.locationInWindow.y
        guard hypot(dx, dy) >= Self.dragThreshold else { return }
        isDragging = true
        beginDrag(with: start)
    }

    override func mouseUp(with event: NSEvent) {
        defer { mouseDownEvent = nil }
        guard !isDragging, mouseDownEvent != nil, bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onClick?()
    }

    // MARK: Dragging

    /// The controller's own token pasteboard content (`tokenField:writeRepresentedObjects:toPasteboard:`): the
    /// property list `[{tokenId}]` under its private type, and `{tokenId}` as plain text.
    private func pasteboardItem() -> NSPasteboardItem {
        let item = NSPasteboardItem()
        item.setString("{\(tokenId)}", forType: .string)
        item.setPropertyList([["tokenId": tokenId]], forType: NSPasteboard.PasteboardType(SPExportCustomFileNameTokenPlistType))
        return item
    }

    private func beginDrag(with event: NSEvent) {
        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem())
        draggingItem.setDraggingFrame(bounds, contents: snapshot())
        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    private func snapshot() -> NSImage? {
        guard let rep = bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        cacheDisplay(in: bounds, to: rep)
        let image = NSImage(size: bounds.size)
        image.addRepresentation(rep)
        return image
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    // MARK: Accessibility

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityLabel() -> String? {
        String(format: NSLocalizedString("ClaudeExportAddToken", value: "Add %@ token", comment: "export dialog: accessibility name of a filename token chip, e.g. \"Add Database token\""), title)
    }
    override func accessibilityPerformPress() -> Bool {
        onClick?()
        return true
    }
}

/// The chips, wrapped onto as many rows as the width needs (flipped: rows flow from the top).
final class SAClaudeExportTokenChipsView: NSView {

    private static let gap: CGFloat = 6

    private(set) var chips: [SAClaudeExportTokenChip] = []

    override var isFlipped: Bool { true }

    /// Replaces the chips (once per change of the available tokens).
    func setChips(_ newChips: [SAClaudeExportTokenChip]) {
        chips.forEach { $0.removeFromSuperview() }
        chips = newChips
        newChips.forEach { addSubview($0) }
        layOutChips()
    }

    /// The chips' frames in `width`, left to right, wrapping.
    private func frames(forWidth width: CGFloat) -> [NSRect] {
        var x: CGFloat = 0, y: CGFloat = 0
        return chips.map { chip in
            let chipWidth = min(chip.preferredWidth, width)
            if x > 0, x + chipWidth > width {
                x = 0
                y += SAClaudeExportTokenChip.height + Self.gap
            }
            defer { x += chipWidth + Self.gap }
            return NSRect(x: x, y: y, width: chipWidth, height: SAClaudeExportTokenChip.height)
        }
    }

    /// The height the chips need at `width` (0 without chips).
    func height(forWidth width: CGFloat) -> CGFloat {
        frames(forWidth: width).last.map { $0.maxY } ?? 0
    }

    func layOutChips() {
        for (chip, frame) in zip(chips, frames(forWidth: bounds.width)) where chip.frame != frame { chip.frame = frame }
    }
}
