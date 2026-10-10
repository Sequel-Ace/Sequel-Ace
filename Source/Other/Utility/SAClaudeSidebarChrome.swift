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
    private var isHovered = false
    private var appearanceObservation: NSKeyValueObservation?

    /// Attaches a highlighter to `view` (once) and rounds its layer.
    @objc static func attach(to view: NSView) {
        guard highlighter(for: view) == nil else { return }
        let highlighter = SAClaudeHoverHighlighter()
        highlighter.view = view
        view.wantsLayer = true
        view.layer?.cornerRadius = SAClaudeStyle.barButtonRadius
        // Active in the active app, not only the key window, so a sheet
        // taking key status mid-hover still delivers mouseExited.
        view.addTrackingArea(NSTrackingArea(rect: .zero,
                                            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                                            owner: highlighter, userInfo: nil))
        // The fill is a resolved CGColor, so re-resolve it on a light/dark switch.
        highlighter.appearanceObservation = view.observe(\.effectiveAppearance) { [weak highlighter] _, _ in
            guard let highlighter, highlighter.isHovered else { return }
            highlighter.setHovered(true)
        }
        objc_setAssociatedObject(view, &associationKey, highlighter, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    /// The highlighter attached to `view`, if any.
    static func highlighter(for view: NSView) -> SAClaudeHoverHighlighter? {
        objc_getAssociatedObject(view, &associationKey) as? SAClaudeHoverHighlighter
    }

    // The tracking area sends its owner `mouseEntered:` / `mouseExited:`. This
    // is a plain NSObject, not an NSResponder override, so the selectors must be
    // spelled out: `mouseEntered(with:)` alone exports as `mouseEnteredWith:`.
    @objc(mouseEntered:) func mouseEntered(with event: NSEvent) { setHovered(true) }
    @objc(mouseExited:) func mouseExited(with event: NSEvent) { setHovered(false) }

    /// Shows or clears the hover fill, resolved for the view's appearance.
    /// A disabled control gets no fill.
    func setHovered(_ hovered: Bool) {
        isHovered = hovered
        guard let view else { return }
        var fill: CGColor?
        if hovered, (view as? NSControl)?.isEnabled ?? true {
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

    /// Adds Claude's 1pt divider across `pane` just above the bottom bar
    /// (once), pinned to the bar so it stays put as the pane resizes.
    ///
    /// - Parameters:
    ///   - pane: The sidebar pane that holds the bar's buttons.
    ///   - barView: One of the bar's buttons; the line sits on its top edge.
    @objc(addBarDivider:aboveView:)
    static func addBarDivider(to pane: NSView, above barView: NSView) {
        guard !pane.subviews.contains(where: { $0 is SAClaudeDividerLine }) else { return }
        let barFrame = pane.convert(barView.bounds, from: barView)
        let y = pane.isFlipped ? barFrame.minY - 1 : barFrame.maxY
        let line = SAClaudeDividerLine(frame: NSRect(x: 0, y: y, width: pane.bounds.width, height: 1))
        // The flexible margin is the one away from the bar: the top margin,
        // which is maxY when the pane is not flipped and minY when it is.
        line.autoresizingMask = [.width, pane.isFlipped ? .minYMargin : .maxYMargin]
        pane.addSubview(line)
    }

    /// Paints the tables-list name cell for its row: the row font, primary
    /// text when selected, secondary otherwise, muted while the list is
    /// disabled; always on a normal background so a selected row never
    /// switches to the white-on-accent text of an emphasized selection.
    /// Never highlighted: NSTableView highlights the selected row's cell
    /// before willDisplayCell, and a highlighted text cell fills a lighter box
    /// behind its text. The pill is drawn by the list, not the cell.
    @objc(styleTablesListCell:selected:enabled:)
    static func styleTablesListCell(_ cell: NSTextFieldCell, selected: Bool, enabled: Bool) {
        cell.font = SAClaudeStyle.rowFont
        cell.textColor = !enabled ? SAClaudeStyle.textMuted : selected ? SAClaudeStyle.textPrimary : SAClaudeStyle.textSecondary
        cell.backgroundStyle = .normal
        cell.isHighlighted = false
    }

    /// Gives the sidebar's list/info split view a 1pt divider, so its
    /// divider colour draws as a hairline rather than a 9pt band.
    @objc(styleSidebarSplitView:)
    static func styleSidebarSplitView(_ split: NSSplitView) {
        split.dividerStyle = .thin
    }

    /// Paints the whole sidebar pane (filter strip, bottom bar, drag-handle
    /// area) in the sidebar colour by adding a background view beneath all
    /// its other subviews (once).
    @objc(addSidebarBackground:)
    static func addSidebarBackground(to pane: NSView) {
        guard !pane.subviews.contains(where: { $0 is SAClaudeSidebarBackgroundView }) else { return }
        let background = SAClaudeSidebarBackgroundView(frame: pane.bounds)
        background.autoresizingMask = [.width, .height]
        pane.addSubview(background, positioned: .below, relativeTo: nil)
    }
}

/// Fills its bounds with the Claude sidebar colour, redrawn for light/dark.
/// Never takes clicks, so the views above it behave as before.
@objc final class SAClaudeSidebarBackgroundView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        SAClaudeStyle.sidebarBackground.setFill()
        dirtyRect.fill()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
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

    /// Never takes clicks from the views under it.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
