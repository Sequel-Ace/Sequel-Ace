//
//  SAClaudeRunButton.swift
//  Sequel Ace
//
//  The query editor's Run button drawn as Claude's accent split button.
//  SPComboPopupButton already splits clicks (left of its divider runs, right
//  of it opens the run menu); this subclass changes the drawing, sizes itself
//  to its title, and opens the run menu as a Claude card. App target only.
//

import AppKit

@objc(SAClaudeRunButton) final class SAClaudeRunButton: SPComboPopupButton {

    private var titleAttributes: [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: SAClaudeAccent.onAccent]
    }

    private var shortcutAttributes: [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: SAClaudeAccent.onAccent.withAlphaComponent(0.75)]
    }

    /// The shortcut of the run-menu item whose action is this button's action.
    private var shortcut: String {
        guard let action, let item = menu?.items.first(where: { $0.action == action && !$0.keyEquivalent.isEmpty }) else { return "" }
        return SAClaudeEditorChrome.shortcutString(keyEquivalent: item.keyEquivalent, modifiers: item.keyEquivalentModifierMask)
    }

    /// The run card is shown: the chevron part draws pressed.
    private var isCardOpen = false { didSet { if isCardOpen != oldValue { needsDisplay = true } } }

    /// SPCustomQuery sets the label with setTitle:, which for a pull-down retitles item 0.
    private var displayTitle: String { title }

    override var intrinsicContentSize: NSSize {
        let titleWidth = ceil((displayTitle as NSString).size(withAttributes: titleAttributes).width)
        let shortcutWidth = ceil((shortcut as NSString).size(withAttributes: shortcutAttributes).width)
        return NSSize(width: SAClaudeEditorChrome.runWidth(titleWidth: titleWidth, shortcutWidth: shortcutWidth, lineOffset: CGFloat(lineOffset)),
                      height: SAClaudeEditorChrome.buttonHeight)
    }

    /// SPCustomQuery retitles the button ("Run current", "Run all", …); keep it fitted and right-aligned.
    override func setTitle(_ string: String) {
        super.setTitle(string)
        fitKeepingRightEdge()
    }

    override func awakeFromNib() {
        super.awakeFromNib()
        isBordered = false
        fitKeepingRightEdge()
        // The fill, glyphs and title are the accent and its contrasting colour, drawn: redraw on a change.
        SAClaudeAccent.observe(self) { $0.needsDisplay = true }
    }

    private func fitKeepingRightEdge() {
        let width = intrinsicContentSize.width
        guard abs(frame.width - width) > 0.5 else { needsDisplay = true; return }
        setFrameOrigin(NSPoint(x: frame.maxX - width, y: frame.minY))
        setFrameSize(NSSize(width: width, height: frame.height))
        needsDisplay = true
    }

    // MARK: Claude card

    private func showCard() -> Bool {
        showSplitCard(adapter: SAClaudeRunMenuAdapter.shared) { [weak self] in self?.isCardOpen = $0 }
    }

    /// The chevron part opens the run card; the main part runs (SPComboPopupButtonCell's tracking, unchanged).
    override func mouseDown(with event: NSEvent) {
        if isOnChevron(event), showCard() { return }
        super.mouseDown(with: event)
    }

    /// ↓ opens the run card; Space/Return keep running.
    override func keyDown(with event: NSEvent) {
        if Self.opensCard(event), showCard() { return }
        super.keyDown(with: event)
    }

    override func accessibilityPerformShowMenu() -> Bool {
        showCard() || super.accessibilityPerformShowMenu()
    }

    /// VoiceOver's press runs, as Space does (NSPopUpButton's own press would open the native menu).
    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        performClick(nil)
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        let pressed = !isCardOpen && (cell?.isHighlighted ?? false)
        let fill = pressed ? SAClaudeEditorChrome.runFillPressed : SAClaudeEditorChrome.runFill
        (isEnabled ? fill : fill.withAlphaComponent(0.45)).setFill()
        let shape = NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7)
        shape.fill()

        let title = displayTitle as NSString
        let shortcutText = shortcut as NSString
        let layout = SAClaudeEditorChrome.runLayout(bounds: bounds, lineOffset: CGFloat(lineOffset),
                                                    titleSize: title.size(withAttributes: titleAttributes),
                                                    shortcutSize: shortcutText.size(withAttributes: shortcutAttributes))
        if isCardOpen {
            NSGraphicsContext.saveGraphicsState()
            shape.addClip()
            SAClaudeEditorChrome.runFillPressed.setFill()
            layout.chevronRect.fill()
            NSGraphicsContext.restoreGraphicsState()
        }
        SAClaudeAccent.onAccent.withAlphaComponent(0.28).setFill()
        NSRect(x: layout.dividerX - 0.5, y: bounds.minY + 6, width: 1, height: bounds.height - 12).fill()

        let play = NSBezierPath()
        play.move(to: NSPoint(x: layout.playRect.minX, y: layout.playRect.minY))
        play.line(to: NSPoint(x: layout.playRect.minX, y: layout.playRect.maxY))
        play.line(to: NSPoint(x: layout.playRect.maxX, y: layout.playRect.midY))
        play.close()
        SAClaudeAccent.onAccent.setFill()
        play.fill()

        title.draw(at: layout.titleOrigin, withAttributes: titleAttributes)
        shortcutText.draw(at: layout.shortcutOrigin, withAttributes: shortcutAttributes)

        let chevron = NSBezierPath()
        let c = NSPoint(x: layout.chevronRect.midX, y: layout.chevronRect.midY)
        chevron.move(to: NSPoint(x: c.x - 3.5, y: c.y + (isFlipped ? -1.75 : 1.75)))
        chevron.line(to: NSPoint(x: c.x, y: c.y + (isFlipped ? 1.75 : -1.75)))
        chevron.line(to: NSPoint(x: c.x + 3.5, y: c.y + (isFlipped ? -1.75 : 1.75)))
        chevron.lineWidth = 1.5
        chevron.lineCapStyle = .round
        chevron.lineJoinStyle = .round
        SAClaudeAccent.onAccent.setStroke()
        chevron.stroke()
    }
}
