//
//  SAClaudeSidebarChrome.swift
//  Sequel Ace
//
//  Drawing and formatting helpers for the Claude-style left navigation:
//  section headers, info-panel rows, bottom-bar buttons. Pure AppKit, shared
//  with the Unit Tests target.
//

import AppKit

@objc final class SAClaudeSidebarChrome: NSObject {

    /// Draws a section header ("Tables and views") in a row, in the header
    /// style, aligned with the icons below it. Call inside a flipped view.
    @objc(drawHeader:inRowRect:)
    static func drawHeader(_ title: String, inRowRect rowRect: NSRect) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: SAClaudeStyle.headerFont,
            .foregroundColor: SAClaudeStyle.textMuted,
            .paragraphStyle: paragraph,
        ]
        let text = NSAttributedString(string: title, attributes: attributes)
        let frame = SAClaudeSidebarGeometry.headerTextFrame(in: rowRect, textHeight: ceil(text.size().height))
        guard frame.width > 0 else { return }
        text.draw(with: frame, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }
}

/// Formats a Table information row ("rows: ~18,402") as a muted label and a
/// right-aligned value. Pure so it can be unit-tested.
@objc final class SAClaudeInfoRow: NSObject {

    /// Splits at the first ": " and capitalises the label's first letter.
    ///
    /// - Returns: The label and value, or `nil` when there is no ": " or either side is empty.
    static func split(_ text: String) -> (label: String, value: String)? {
        guard let range = text.range(of: ": ") else { return nil }
        let label = String(text[..<range.lowerBound])
        let value = String(text[range.upperBound...])
        guard !label.isEmpty, !value.isEmpty else { return nil }
        return (label.prefix(1).uppercased() + label.dropFirst(), value)
    }

    /// The row as drawn: label muted on the left, value secondary on a right
    /// tab stop `infoRowTrailingPadding` in from `width`; text without ": " plain.
    @objc(attributedRowForText:width:)
    static func attributedRow(text: String, width: CGFloat) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        paragraph.tabStops = [NSTextTab(textAlignment: .right, location: max(0, width - SAClaudeStyle.infoRowTrailingPadding))]
        let font = SAClaudeStyle.infoFont
        guard let parts = split(text) else {
            return NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: SAClaudeStyle.textSecondary, .paragraphStyle: paragraph])
        }
        let row = NSMutableAttributedString(string: parts.label, attributes: [.font: font, .foregroundColor: SAClaudeStyle.textMuted, .paragraphStyle: paragraph])
        row.append(NSAttributedString(string: "\t" + parts.value, attributes: [.font: font, .foregroundColor: SAClaudeStyle.textSecondary, .paragraphStyle: paragraph]))
        return row
    }
}

extension SAClaudeSidebarChrome {

    /// Gives one of the sidebar's plain tables (Table information, Activities)
    /// the Claude background, no system selection and no source-list styling.
    @objc(styleSidebarTable:)
    static func styleSidebarTable(_ table: NSTableView) {
        table.style = .plain
        table.selectionHighlightStyle = .none
        table.usesAlternatingRowBackgroundColors = false
        table.gridStyleMask = []
        table.backgroundColor = SAClaudeStyle.sidebarBackground
        if let scrollView = table.enclosingScrollView {
            scrollView.drawsBackground = true
            scrollView.backgroundColor = SAClaudeStyle.sidebarBackground
        }
    }
}

/// Gives a view Claude's rounded hover fill while the mouse is over it.
/// Retained by the view it highlights.
@objc final class SAClaudeHoverHighlighter: NSObject {
    private static var associationKey: UInt8 = 0
    private weak var view: NSView?

    /// Attaches a highlighter to `view` (once) and rounds its layer.
    @objc static func attach(to view: NSView) {
        guard highlighter(for: view) == nil else { return }
        let highlighter = SAClaudeHoverHighlighter()
        highlighter.view = view
        view.wantsLayer = true
        view.layer?.cornerRadius = SAClaudeStyle.barButtonRadius
        view.addTrackingArea(NSTrackingArea(rect: .zero,
                                            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                            owner: highlighter, userInfo: nil))
        objc_setAssociatedObject(view, &associationKey, highlighter, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    /// The highlighter attached to `view`, if any.
    static func highlighter(for view: NSView) -> SAClaudeHoverHighlighter? {
        objc_getAssociatedObject(view, &associationKey) as? SAClaudeHoverHighlighter
    }

    @objc func mouseEntered(with event: NSEvent) { setHovered(true) }
    @objc func mouseExited(with event: NSEvent) { setHovered(false) }

    /// Shows or clears the hover fill, resolved for the view's appearance.
    func setHovered(_ hovered: Bool) {
        guard let view else { return }
        var fill: CGColor?
        if hovered {
            view.effectiveAppearance.performAsCurrentDrawingAppearance {
                fill = SAClaudeStyle.hoverFill.cgColor
            }
        }
        view.layer?.backgroundColor = fill
    }
}

extension SAClaudeSidebarChrome {

    /// Turns a bottom-bar button into a quiet Claude-style icon button: its
    /// glyph in the muted tint, no border, the rounded hover fill. A pull-down
    /// menu button shows the glyph through its first (title) item.
    @objc(styleBarButton:glyph:)
    static func styleBarButton(_ button: NSButton, glyph: SAClaudeGlyph) {
        let image = SAClaudeGlyphs.image(glyph, tint: SAClaudeGlyphs.tint(for: glyph))
        if let popup = button as? NSPopUpButton {
            popup.item(at: 0)?.image = image
        } else {
            button.image = image
            button.alternateImage = image
        }
        button.isBordered = false
        button.imagePosition = .imageOnly
        SAClaudeHoverHighlighter.attach(to: button)
    }

    /// Adds Claude's 1pt divider along the top edge of `bar` (once). The bar's
    /// coordinates are not flipped, so the top edge is `maxY`.
    @objc(addTopDivider:)
    static func addTopDivider(to bar: NSView) {
        guard !bar.subviews.contains(where: { $0 is SAClaudeDividerLine }) else { return }
        let line = SAClaudeDividerLine(frame: NSRect(x: 0, y: bar.bounds.maxY - 1, width: bar.bounds.width, height: 1))
        line.autoresizingMask = [.width, .minYMargin]
        bar.addSubview(line)
    }
}

/// A 1pt line in the Claude divider colour, redrawn for light/dark.
@objc final class SAClaudeDividerLine: NSView {
    override func draw(_ dirtyRect: NSRect) {
        SAClaudeStyle.divider.setFill()
        bounds.fill()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}
