//
//  SAClaudeConnectionTypeTabs.swift
//  Sequel Ace
//
//  The connection panel's type tabs (TCP/IP, Socket, SSH, AWS IAM, Vault): ghost segments in one row, the
//  selected one drawn on the card surface with a hairline. It replaces the tab view's own tab strip; selecting a
//  segment only reports the index (the panel styler selects the tab view item, so the controller's tab delegate and
//  `type` binding run as before). Arrow keys move the selection while it has focus. App target only.
//

import AppKit

final class SAClaudeConnectionTypeTabs: NSControl {

    struct Colours {
        var selectedFill: NSColor
        var selectedStroke: NSColor
        var hoverFill: NSColor
        var text: NSColor
        var mutedText: NSColor
    }

    static let height: CGFloat = 26
    private static let segmentPadding: CGFloat = 10
    private static let radius: CGFloat = 7
    private static let font = NSFont.systemFont(ofSize: 12)
    private static let selectedFont = NSFont.systemFont(ofSize: 12, weight: .medium)

    var titles: [String] = [] {
        didSet {
            rebuildAccessibilityChildren()
            needsDisplay = true
        }
    }

    /// Set from the controller's `type`; does not report a selection.
    var selectedIndex: Int = 0 {
        didSet {
            guard oldValue != selectedIndex else { return }
            needsDisplay = true
            NSAccessibility.post(element: self, notification: .valueChanged)
        }
    }

    var colours = Colours(selectedFill: .controlBackgroundColor, selectedStroke: .separatorColor, hoverFill: .quaternaryLabelColor,
                          text: .labelColor, mutedText: .secondaryLabelColor) {
        didSet { needsDisplay = true }
    }

    /// Called with the segment the user picked (mouse or keyboard), after `selectedIndex` changed.
    var onSelect: ((Int) -> Void)?

    private var hoverIndex: Int? {
        didSet { if oldValue != hoverIndex { needsDisplay = true } }
    }
    private var hoverTrackingArea: NSTrackingArea?
    private var segmentElements: [SegmentElement] = []

    /// The width that fits every title at the selected weight.
    var preferredWidth: CGFloat {
        segmentWidths().reduce(0, +)
    }

    private func segmentWidths() -> [CGFloat] {
        titles.map { title in
            ceil(NSAttributedString(string: title, attributes: [.font: Self.selectedFont]).size().width) + 2 * Self.segmentPadding
        }
    }

    /// The segments' rects, shrunk proportionally when the control is narrower than its preferred width.
    private func segmentRects() -> [NSRect] {
        let widths = segmentWidths()
        let total = widths.reduce(0, +)
        guard total > 0 else { return [] }
        let scale = min(1, bounds.width / total)
        let height = min(Self.height, bounds.height)
        let y = (bounds.midY - height / 2).rounded(.down)
        var x = bounds.maxX - total * scale
        return widths.map { width in
            defer { x += width * scale }
            return NSRect(x: x, y: y, width: width * scale, height: height)
        }
    }

    private func index(at point: NSPoint) -> Int? {
        segmentRects().firstIndex { $0.contains(point) }
    }

    // MARK: - Drawing

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let rects = segmentRects()
        for (index, rect) in rects.enumerated() {
            let selected = index == selectedIndex
            let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: Self.radius, yRadius: Self.radius)
            if selected {
                colours.selectedFill.setFill()
                path.fill()
                colours.selectedStroke.setStroke()
                path.lineWidth = 1
                path.stroke()
            } else if index == hoverIndex {
                colours.hoverFill.setFill()
                path.fill()
            }
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            style.lineBreakMode = .byTruncatingTail
            let title = NSAttributedString(string: titles[index], attributes: [
                .font: selected ? Self.selectedFont : Self.font,
                .foregroundColor: selected ? colours.text : colours.mutedText,
                .paragraphStyle: style,
            ])
            let textHeight = ceil(title.size().height)
            let textRect = NSRect(x: rect.minX + 2, y: (rect.midY - textHeight / 2).rounded(), width: max(0, rect.width - 4), height: textHeight)
            title.draw(with: textRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        }
    }

    override var focusRingMaskBounds: NSRect {
        let rects = segmentRects()
        return rects.indices.contains(selectedIndex) ? rects[selectedIndex] : bounds
    }

    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: focusRingMaskBounds, xRadius: Self.radius, yRadius: Self.radius).fill()
    }

    // MARK: - Selecting

    private func select(_ index: Int) {
        guard titles.indices.contains(index), isEnabled else { return }
        selectedIndex = index
        noteFocusRingMaskChanged()
        onSelect?(index)
    }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if let index = index(at: convert(event.locationInWindow, from: nil)) { select(index) }
    }

    override func keyDown(with event: NSEvent) {
        switch event.specialKey {
        case .leftArrow?: select(selectedIndex - 1)
        case .rightArrow?: select(selectedIndex + 1)
        default: super.keyDown(with: event)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea { removeTrackingArea(hoverTrackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeInActiveApp, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { hoverIndex = index(at: convert(event.locationInWindow, from: nil)) }
    override func mouseMoved(with event: NSEvent) { hoverIndex = index(at: convert(event.locationInWindow, from: nil)) }
    override func mouseExited(with event: NSEvent) { hoverIndex = nil }

    // MARK: - Accessibility

    /// One radio button per segment, so VoiceOver can read and pick the connection type.
    private final class SegmentElement: NSAccessibilityElement {
        weak var tabs: SAClaudeConnectionTypeTabs?
        var index = 0

        override func accessibilityFrame() -> NSRect {
            guard let tabs, let window = tabs.window else { return .zero }
            let rects = tabs.segmentRects()
            guard rects.indices.contains(index) else { return .zero }
            return window.convertToScreen(tabs.convert(rects[index], to: nil))
        }

        override func accessibilityParent() -> Any? { tabs }
        override func accessibilityValue() -> Any? { NSNumber(value: tabs?.selectedIndex == index) }
        override func accessibilityPerformPress() -> Bool {
            tabs?.select(index)
            return true
        }
    }

    private func rebuildAccessibilityChildren() {
        segmentElements = titles.enumerated().map { index, title in
            let element = SegmentElement()
            element.tabs = self
            element.index = index
            element.setAccessibilityRole(.radioButton)
            element.setAccessibilityLabel(title)
            return element
        }
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .radioGroup }
    override func accessibilityLabel() -> String? {
        NSLocalizedString("ClaudeConnectionTypeTabs", value: "Connection type", comment: "accessibility name of the connection type tabs in the connection panel")
    }
    override func accessibilityChildren() -> [Any]? { segmentElements }
    override func accessibilityValue() -> Any? { titles.indices.contains(selectedIndex) ? titles[selectedIndex] : nil }
}
