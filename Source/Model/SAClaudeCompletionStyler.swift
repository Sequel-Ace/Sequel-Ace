//
//  SAClaudeCompletionStyler.swift
//  Sequel Ace
//
//  The editor autocomplete popup (SPNarrowDownCompletion) as a Claude card: an
//  opaque rounded surface with a hairline border and 5pt padding, 26pt rows with
//  the theme selection as a rounded pill, Claude glyphs tinted from the editor
//  theme, the name in the editor font and a plain muted type label. App-only.
//

import AppKit

/// The completion list: paints the popup surface and draws the selection as a
/// rounded pill in the theme's selection colour instead of the system highlight.
@objc(SAClaudeCompletionTableView)
final class SAClaudeCompletionTableView: NSTableView {

    static let pillRadius: CGFloat = 6

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    // Set before SPNarrowDownCompletion adds its columns, so the table's content
    // width (which it reads to size the window) already includes the spacing.
    private func configure() {
        // No inset style padding: the card's 5pt padding is the only inset, and rows fill it.
        style = .plain
        selectionHighlightStyle = .none
        gridStyleMask = []
        rowHeight = SAClaudeCompletionStyler.rowHeight
        intercellSpacing = NSSize(width: 6, height: 0)
    }

    override func drawBackground(inClipRect clipRect: NSRect) {
        let area = clipRect.intersection(bounds)
        guard !area.isEmpty else { return }
        let theme = SAClaudeCompletionStyler.currentTheme()
        SAClaudeStatusChrome.popupSurface(theme: theme).setFill()
        area.fill()

        let visibleRows = rows(in: area)
        guard visibleRows.length > 0, !selectedRowIndexes.isEmpty else { return }
        NSGraphicsContext.saveGraphicsState()
        // Clip rather than intersect, so a partial redraw keeps the pill's corners where they belong.
        NSBezierPath(rect: area).addClip()
        theme.selection.setFill()
        // Rows can be wider than the popup (one-column and dictionary lists); keep the pill's
        // ends inside the visible width so both stay rounded.
        let visible = visibleRect
        for row in selectedRowIndexes where row >= visibleRows.location && row < NSMaxRange(visibleRows) {
            var pill = rect(ofRow: row).insetBy(dx: 0, dy: 1)
            pill.origin.x = max(pill.minX, visible.minX)
            pill.size.width = min(pill.maxX, visible.maxX) - pill.minX
            guard pill.width > 0 else { continue }
            NSBezierPath(roundedRect: pill, xRadius: Self.pillRadius, yRadius: Self.pillRadius).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    private var clipBoundsObserver: NSObjectProtocol?

    deinit {
        if let clipBoundsObserver { NotificationCenter.default.removeObserver(clipBoundsObserver) }
    }

    // The pill follows the visible width, so repaint when the list scrolls sideways.
    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        if let clipBoundsObserver { NotificationCenter.default.removeObserver(clipBoundsObserver) }
        clipBoundsObserver = nil
        guard let clipView = superview as? NSClipView else { return }
        clipView.postsBoundsChangedNotifications = true
        var lastX = clipView.bounds.minX
        clipBoundsObserver = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: clipView, queue: .main) { [weak self, weak clipView] _ in
            guard let clipView, clipView.bounds.minX != lastX else { return }
            lastX = clipView.bounds.minX
            self?.needsDisplay = true
        }
    }

    override func selectRowIndexes(_ indexes: IndexSet, byExtendingSelection extend: Bool) {
        super.selectRowIndexes(indexes, byExtendingSelection: extend)
        // There is no system highlight to invalidate, so repaint for the pill to follow.
        needsDisplay = true
    }
}

/// A text cell that centres its single line vertically in the 26pt row.
private final class SAClaudeCompletionTextCell: NSTextFieldCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        let drawing = super.drawingRect(forBounds: rect)
        guard let font else { return drawing }
        let lineHeight = SAClaudeCompletionStyler.lineHeight(of: font)
        guard lineHeight < drawing.height else { return drawing }
        return NSRect(x: drawing.minX, y: drawing.minY + floor((drawing.height - lineHeight) / 2),
                      width: drawing.width, height: lineHeight)
    }
}

/// The popup's content view: the rounded card that holds the completion list's scroll view.
private final class SAClaudeCompletionCardView: NSView {
    private weak var scrollView: NSScrollView?
    private weak var tableView: NSTableView?
    private var appliedFont: NSFont?
    private var defaultsObserver: NSObjectProtocol?

    init(frame: NSRect, scrollView: NSScrollView, tableView: NSTableView) {
        self.scrollView = scrollView
        self.tableView = tableView
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        defaultsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.refresh(force: false)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    deinit {
        if let defaultsObserver { NotificationCenter.default.removeObserver(defaultsObserver) }
    }

    override var wantsUpdateLayer: Bool { true }

    // Runs with the view's appearance current, so dynamic fallback colours resolve correctly.
    override func updateLayer() {
        guard let layer else { return }
        let theme = SAClaudeCompletionStyler.currentTheme()
        layer.cornerRadius = SAClaudeCompletionStyler.cornerRadius
        layer.masksToBounds = true
        layer.borderWidth = 1
        layer.borderColor = SAClaudeStatusChrome.hairline(theme: theme).cgColor
        layer.backgroundColor = SAClaudeStatusChrome.popupSurface(theme: theme).cgColor
    }

    // Replaces autoresizing: the scroll view always sits inside the padding,
    // which SACompletionWindowLayout adds to the window size.
    override func resizeSubviews(withOldSize oldSize: NSSize) {
        layoutScrollView()
        window?.invalidateShadow()
    }

    func layoutScrollView() {
        let padding = SACompletionWindowLayout.cardPadding
        scrollView?.frame = NSRect(x: padding, y: padding,
                                   width: max(0, bounds.width - 2 * padding),
                                   height: max(0, bounds.height - 2 * padding))
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        // Dynamic fallback colours (no theme saved yet) resolve differently in light and dark.
        DispatchQueue.main.async { [weak self] in self?.refresh(force: true) }
    }

    /// Re-applies colours and fonts when the editor theme or font changed (or always, when `force`).
    func refresh(force: Bool) {
        let themeChanged = SAClaudeCompletionStyler.refreshTheme()
        let font = SAClaudeCompletionStyler.editorFont()
        guard force || themeChanged || font != appliedFont else { return }
        apply(font: font)
    }

    func apply(font: NSFont) {
        appliedFont = font
        let theme = SAClaudeCompletionStyler.currentTheme()
        if let scrollView {
            scrollView.drawsBackground = false
            scrollView.contentView.drawsBackground = false
            scrollView.borderType = .noBorder
            scrollView.appearance = SAClaudeGridChrome.scrollerAppearance(for: theme.background)
        }
        if let tableView {
            tableView.backgroundColor = SAClaudeStatusChrome.popupSurface(theme: theme)
            // Taller rows for a large editor font; the window takes the height on the next filter pass.
            tableView.rowHeight = SACompletionWindowLayout.rowHeight(forFontLineHeight: SAClaudeCompletionStyler.lineHeight(of: font))
            if let column = tableView.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("name")) {
                let cell = (column.dataCell as? SAClaudeCompletionTextCell) ?? SAClaudeCompletionTextCell(textCell: "")
                cell.isEditable = false
                cell.lineBreakMode = .byTruncatingTail
                cell.font = font
                cell.textColor = theme.text
                column.dataCell = cell
            }
            tableView.needsDisplay = true
        }
        needsDisplay = true
        window?.invalidateShadow()
    }
}

@objc(SAClaudeCompletionStyler)
final class SAClaudeCompletionStyler: NSObject {

    static let rowHeight = SACompletionWindowLayout.minimumRowHeight
    static let cornerRadius: CGFloat = 10

    /// The height of one line of text in `font`, as the list's cells lay it out.
    static func lineHeight(of font: NSFont) -> CGFloat {
        ceil(font.ascender - font.descender + font.leading)
    }

    /// How far right of the popup window's left edge the name column's text starts, so the popup
    /// can line that text up with the typed word (in multi-column and in one-column/dictionary lists).
    @objc(nameTextOffsetForTableView:)
    static func nameTextOffset(for tableView: NSTableView) -> CGFloat {
        let index = tableView.column(withIdentifier: NSUserInterfaceItemIdentifier("name"))
        guard index >= 0 else { return SACompletionWindowLayout.nameTextOffset(cellDrawingMinX: 0) }
        // frameOfCell(atColumn:row:) is empty until the first filter pass loads rows, so inset the
        // column's rect by half the intercell spacing, as the table does for its cells.
        var cellFrame = tableView.rect(ofColumn: index).insetBy(dx: tableView.intercellSpacing.width / 2, dy: 0)
        cellFrame.size.height = tableView.rowHeight
        let cell = tableView.tableColumns[index].dataCell as? NSCell
        let drawingMinX = cell?.drawingRect(forBounds: cellFrame).minX ?? cellFrame.minX
        return SACompletionWindowLayout.nameTextOffset(cellDrawingMinX: drawingMinX)
    }

    /// The gap between the caret's line and a popup that opens above it.
    private static let aboveCaretGap: CGFloat = 3

    /// For a popup that would run past the bottom of the editor's visible area (and has more room
    /// above the caret's line), the caret position `-[SPNarrowDownCompletion filter]` places it
    /// above the line from; `nil` keeps it below.
    ///
    /// - Parameters:
    ///   - caret: The popup's caret position in screen coordinates: the bottom of the caret's line.
    ///   - popupFontSize: The popup's font size; the popup puts its bottom 1.5 × this above the position.
    @objc(abovePositionForCaret:popupHeight:popupFontSize:editor:)
    static func abovePosition(caret: NSPoint, popupHeight: CGFloat, popupFontSize: CGFloat, editor: NSTextView?) -> NSValue? {
        guard let editor, let window = editor.window,
              let clipView = editor.enclosingScrollView?.contentView else { return nil }
        let visible = window.convertToScreen(clipView.convert(clipView.bounds, to: nil))
        let lineHeight = editor.layoutManager?.defaultLineHeight(for: editor.font ?? editorFont()) ?? popupFontSize * 1.2
        guard SACompletionWindowLayout.opensAbove(popupHeight: popupHeight, lineBottom: caret.y, lineHeight: lineHeight,
                                                  visibleMinY: visible.minY, visibleMaxY: visible.maxY) else { return nil }
        return NSValue(point: NSPoint(x: caret.x, y: caret.y + lineHeight + aboveCaretGap - popupFontSize * 1.5))
    }

    private static var theme: SAClaudeThemeColours?
    private static var images: [String: NSImage] = [:]

    /// The editor theme the popup draws with: cached, refreshed whenever the popup is styled.
    static func currentTheme() -> SAClaudeThemeColours {
        if let theme { return theme }
        refreshTheme()
        return theme ?? SAClaudeThemeColours.from(defaults: .standard)
    }

    /// Re-reads the editor theme. Returns whether it changed.
    @discardableResult
    static func refreshTheme() -> Bool {
        let fresh = SAClaudeThemeColours.from(defaults: .standard)
        guard fresh != theme else { return false }
        theme = fresh
        images.removeAll()
        return true
    }

    /// The query editor font. Keep the key in sync with SPCustomQueryEditorFont in SPConstants.m.
    static func editorFont() -> NSFont {
        SAArchiving.font(from: UserDefaults.standard.data(forKey: "CustomQueryEditorFont")) ?? .systemFont(ofSize: 12)
    }

    /// Turns the popup window into the card: call once its content view (the
    /// table's scroll view) is in place. Safe to call again; it only re-applies colours.
    @objc(styleWindow:tableView:)
    static func style(window: NSWindow, tableView: NSTableView) {
        refreshTheme()
        window.alphaValue = 1
        window.isOpaque = false
        window.backgroundColor = .clear

        let card: SAClaudeCompletionCardView
        if let existing = window.contentView as? SAClaudeCompletionCardView {
            card = existing
        } else {
            guard let scrollView = tableView.enclosingScrollView else { return }
            card = SAClaudeCompletionCardView(frame: scrollView.frame, scrollView: scrollView, tableView: tableView)
            window.contentView = card
            card.addSubview(scrollView)
            card.layoutScrollView()
        }
        card.apply(font: editorFont())
    }

    /// The icon for a completion item's image name: a tinted Claude glyph for the
    /// known kinds, otherwise the named image as before.
    @objc(imageForName:)
    static func image(forName name: String?) -> NSImage? {
        guard let name else { return nil }
        guard let kind = SAClaudeCompletionKind(imageName: name) else { return NSImage(named: name) }
        let theme = currentTheme()
        if let cached = images[name] { return cached }
        let image = SAClaudeGlyphs.image(kind.glyph, tint: SAClaudeStatusChrome.completionTint(kind, theme: theme))
        images[name] = image
        return image
    }

    /// The type column's cell: plain right-aligned muted text instead of a token pill.
    @objc(typeCell)
    static func typeCell() -> NSCell {
        let cell = SAClaudeCompletionTextCell(textCell: "")
        cell.isEditable = false
        cell.alignment = .right
        cell.font = .systemFont(ofSize: 11)
        cell.textColor = SAClaudeStatusChrome.typeText(theme: currentTheme())
        cell.lineBreakMode = .byTruncatingTail
        return cell
    }
}
