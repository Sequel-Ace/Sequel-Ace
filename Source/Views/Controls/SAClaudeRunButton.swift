//
//  SAClaudeRunButton.swift
//  Sequel Ace
//
//  The query editor's Run button drawn as Claude's clay split button.
//  SPComboPopupButton already splits clicks (left of its divider runs, right
//  of it opens the run menu); this subclass only changes the drawing and
//  sizes itself to its title. App target only.
//

import AppKit

@objc(SAClaudeRunButton) final class SAClaudeRunButton: SPComboPopupButton {

    private var titleAttributes: [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: NSColor.white]
    }

    private var shortcutAttributes: [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.white.withAlphaComponent(0.75)]
    }

    /// The shortcut of the run-menu item whose action is this button's action.
    private var shortcut: String {
        guard let action, let item = menu?.items.first(where: { $0.action == action && !$0.keyEquivalent.isEmpty }) else { return "" }
        return SAClaudeEditorChrome.shortcutString(keyEquivalent: item.keyEquivalent, modifiers: item.keyEquivalentModifierMask)
    }

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
    }

    private func fitKeepingRightEdge() {
        let width = intrinsicContentSize.width
        guard abs(frame.width - width) > 0.5 else { needsDisplay = true; return }
        setFrameOrigin(NSPoint(x: frame.maxX - width, y: frame.minY))
        setFrameSize(NSSize(width: width, height: frame.height))
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let pressed = cell?.isHighlighted ?? false
        let fill = pressed ? SAClaudeEditorChrome.runFillPressed : SAClaudeEditorChrome.runFill
        (isEnabled ? fill : fill.withAlphaComponent(0.45)).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7).fill()

        let title = displayTitle as NSString
        let shortcutText = shortcut as NSString
        let layout = SAClaudeEditorChrome.runLayout(bounds: bounds, lineOffset: CGFloat(lineOffset),
                                                    titleSize: title.size(withAttributes: titleAttributes),
                                                    shortcutSize: shortcutText.size(withAttributes: shortcutAttributes))
        NSColor.white.withAlphaComponent(0.28).setFill()
        NSRect(x: layout.dividerX - 0.5, y: bounds.minY + 6, width: 1, height: bounds.height - 12).fill()

        let play = NSBezierPath()
        play.move(to: NSPoint(x: layout.playRect.minX, y: layout.playRect.minY))
        play.line(to: NSPoint(x: layout.playRect.minX, y: layout.playRect.maxY))
        play.line(to: NSPoint(x: layout.playRect.maxX, y: layout.playRect.midY))
        play.close()
        NSColor.white.setFill()
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
        NSColor.white.setStroke()
        chevron.stroke()
    }
}
