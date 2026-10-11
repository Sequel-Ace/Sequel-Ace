//
//  SAClaudeCopyTable.swift
//  Sequel Ace
//
//  The Query and Content tab grids as a quiet sheet: theme background, every
//  other row shaded, lines between rows and columns, hover tint, the theme's selection colour, a 30pt header
//  with the column type as a small tag. Only drawing changes; copying, editing,
//  sorting and menus are SPCopyTable's. App target only.
//

import AppKit

@objc enum SAClaudeGridCellRole: Int {
    case text, null, displayOverride
}

/// Colours and fonts for grid cells, from the editor theme (cached; refreshed on settings changes).
@objc(SAClaudeGridCellStyler) final class SAClaudeGridCellStyler: NSObject {

    private static var cachedPalette: SAClaudeGridChrome.Palette?
    private static var observer: NSObjectProtocol?
    private static var fonts: [String: NSFont] = [:]

    static var palette: SAClaudeGridChrome.Palette {
        if observer == nil {
            observer = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { _ in
                cachedPalette = nil
            }
        }
        if let cachedPalette { return cachedPalette }
        let palette = SAClaudeGridChrome.palette(from: .standard)
        cachedPalette = palette
        return palette
    }

    /// Drops the cached palette (e.g. when the effective appearance changes the fallback dynamic colours).
    static func invalidatePalette() {
        cachedPalette = nil
    }

    private static func font(_ base: NSFont, null: Bool) -> NSFont {
        let key = "\(base.fontName)|\(base.pointSize)|\(null)"
        if let font = fonts[key] { return font }
        let font = null ? SAClaudeGridChrome.nullFont(base) : SAClaudeGridChrome.valueFont(base)
        fonts[key] = font
        return font
    }

    /// Sets the cell's text colour and font for its role; called from the grids' willDisplayCell.
    @objc(styleCell:role:)
    static func style(_ cell: Any, role: SAClaudeGridCellRole) {
        guard let cell = cell as? NSTextFieldCell else { return }
        switch role {
        case .text: cell.textColor = Self.palette.text
        case .null: cell.textColor = Self.palette.null
        case .displayOverride: cell.textColor = Self.palette.displayOverride
        }
        if let base = cell.font { cell.font = font(base, null: role == .null) }
        // Cell-based tables mark the selected row's cells highlighted, which draws a system
        // selection box and white text; the table draws the theme selection itself.
        cell.isHighlighted = false
    }
}

@objc(SAClaudeCopyTable) final class SAClaudeCopyTable: SPCopyTable {

    private var palette = SAClaudeGridChrome.palette(from: .standard)
    private var observer: NSObjectProtocol?
    private var hoveredRow = -1
    private var hoverArea: NSTrackingArea?

    override func awakeFromNib() {
        super.awakeFromNib()
        usesAlternatingRowBackgroundColors = false
        gridStyleMask.formUnion([.solidHorizontalGridLineMask, .solidVerticalGridLineMask])
        if var frame = headerView?.frame { frame.size.height = SAClaudeGridChrome.headerHeight; headerView?.frame = frame }
        cornerView = SAClaudeGridCornerView(frame: NSRect(x: 0, y: 0, width: 16, height: SAClaudeGridChrome.headerHeight))
        applyPalette(force: true)
        observer = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.applyPalette(force: false)
        }
    }

    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        SAClaudeGridCellStyler.invalidatePalette()
        applyPalette(force: true)
    }

    private func applyPalette(force: Bool) {
        let newPalette = SAClaudeGridChrome.palette(from: .standard)
        guard force || newPalette != palette else { return }
        palette = newPalette
        backgroundColor = palette.background
        enclosingScrollView?.backgroundColor = palette.background
        enclosingScrollView?.drawsBackground = true
        // Only when it changes: a new appearance re-enters viewDidChangeEffectiveAppearance.
        let scrollerAppearance = SAClaudeGridChrome.scrollerAppearance(for: palette.background)
        if enclosingScrollView?.appearance?.name != scrollerAppearance?.name {
            enclosingScrollView?.appearance = scrollerAppearance
        }
        (headerView as? SAClaudeTableHeaderView)?.palette = palette
        (cornerView as? SAClaudeGridCornerView)?.palette = palette
        needsDisplay = true
        headerView?.needsDisplay = true
    }

    /// NSTableView only calls drawGrid(inClipRect:) when the mask is non-empty; row and column
    /// lines are always drawn (the "vertical gridlines" preference no longer applies), so both
    /// bits are always on.
    override var gridStyleMask: NSTableView.GridLineStyle {
        get { super.gridStyleMask }
        set { super.gridStyleMask = newValue.union([.solidHorizontalGridLineMask, .solidVerticalGridLineMask]) }
    }

    override var rowHeight: CGFloat {
        get { super.rowHeight }
        set { super.rowHeight = max(newValue, SAClaudeGridChrome.minimumRowHeight) }
    }

    private static var lineHeights: [String: CGFloat] = [:]

    /// One line of the cell's text plus SPTextAndLinkCell's 2pt top offset (cached per font).
    private static func lineHeight(for font: NSFont) -> CGFloat {
        let key = "\(font.fontName)|\(font.pointSize)"
        if let height = lineHeights[key] { return height }
        let height = NSLayoutManager().defaultLineHeight(for: font) + 2
        lineHeights[key] = height
        return height
    }

    /// Cells lay their text out from the top; centre one line in the taller rows. This frame
    /// feeds drawing, the field editor and link-arrow hit testing alike; selection and hover
    /// use rect(ofRow:) and keep the full row.
    override func frameOfCell(atColumn column: Int, row: Int) -> NSRect {
        let frame = super.frameOfCell(atColumn: column, row: row)
        guard column >= 0, column < numberOfColumns, let cell = tableColumns[column].dataCell as? NSCell, let cellFont = cell.font else { return frame }
        let inset = max(0, floor((frame.height - Self.lineHeight(for: cellFont)) / 2))
        return frame.insetBy(dx: 0, dy: inset)
    }

    override func drawBackground(inClipRect clipRect: NSRect) {
        palette.background.setFill()
        let area = clipRect.intersection(bounds)
        area.fill()
        let visible = rows(in: area)
        guard visible.length > 0 else { return }
        palette.zebra.setFill()
        for row in visible.location..<NSMaxRange(visible) where SAClaudeGridChrome.isZebra(row: row) {
            rect(ofRow: row).intersection(area).fill()
        }
    }

    override func highlightSelection(inClipRect clipRect: NSRect) {
        let visible = rows(in: clipRect)
        guard visible.length > 0 else { return }
        // Hover is filled here, not in drawRow: this runs before drawGrid, so the row's lines stay on top.
        if hoveredRow >= visible.location, hoveredRow < NSMaxRange(visible), !isRowSelected(hoveredRow) {
            palette.hover.setFill()
            rect(ofRow: hoveredRow).intersection(clipRect).fill()
        }
        palette.selection.setFill()
        // Only the visible slice: after Select All on a huge result, walking every selected row janks.
        let selected = selectedRowIndexes
        for row in selected[selected.indexRange(in: visible.location..<NSMaxRange(visible))] {
            rect(ofRow: row).intersection(clipRect).fill()
        }
    }

    override func drawGrid(inClipRect clipRect: NSRect) {
        palette.rowLine.setFill()
        let visible = rows(in: clipRect)
        for row in visible.location..<NSMaxRange(visible) {
            let r = rect(ofRow: row)
            NSRect(x: clipRect.minX, y: r.maxY - 1, width: clipRect.width, height: 1).intersection(clipRect).fill()
        }
        // Column lines run from the top to the bottom of the last row, not down the empty area.
        let lastRowMaxY = numberOfRows > 0 ? rect(ofRow: numberOfRows - 1).maxY : 0
        guard let bottom = SAClaudeGridChrome.columnLineExtent(rowCount: numberOfRows, lastRowMaxY: lastRowMaxY) else { return }
        for column in 0..<numberOfColumns {
            let r = rect(ofColumn: column)
            guard SAClaudeGridChrome.drawsColumnSeparator(columnMaxX: r.maxX, boundsMaxX: bounds.maxX) else { continue }
            NSRect(x: r.maxX - 1, y: bounds.minY, width: 1, height: bottom - bounds.minY).intersection(clipRect).fill()
        }
    }

    // MARK: Hover

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        setHoveredRow(row(at: convert(event.locationInWindow, from: nil)))
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        setHoveredRow(-1)
    }

    /// Wheel and trackpad scrolling send no mouseMoved: re-read the row under the pointer.
    override func scrollWheel(with event: NSEvent) {
        super.scrollWheel(with: event)
        updateHoveredRowFromPointer()
    }

    /// A re-run or reload leaves the old index meaningless.
    override func reloadData() {
        hoveredRow = -1
        super.reloadData()
    }

    override func noteNumberOfRowsChanged() {
        setHoveredRow(-1)
        super.noteNumberOfRowsChanged()
    }

    private func updateHoveredRowFromPointer() {
        // Like the tracking area (.activeInKeyWindow): no hover outside the key window.
        guard let window, window.isKeyWindow else { setHoveredRow(-1); return }
        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        setHoveredRow(visibleRect.contains(point) ? row(at: point) : -1)
    }

    private func setHoveredRow(_ row: Int) {
        guard row != hoveredRow else { return }
        if hoveredRow >= 0, hoveredRow < numberOfRows { setNeedsDisplay(rect(ofRow: hoveredRow)) }
        hoveredRow = row
        if row >= 0 { setNeedsDisplay(rect(ofRow: row)) }
    }

    // MARK: Inline editing (Content tab)

    override func editColumn(_ column: Int, row: Int, with event: NSEvent?, select: Bool) {
        super.editColumn(column, row: row, with: event, select: select)
        guard let editor = currentEditor() as? NSTextView else { return }
        editor.drawsBackground = true
        editor.backgroundColor = palette.background
        editor.textColor = palette.text
        editor.insertionPointColor = palette.caret
    }

    /// The field editor is the window's shared one: give its caret back before other fields use it.
    /// (Cells set its text and background colours each time they start editing; not the caret.)
    /// Reset before super, which may start editing the next cell (Tab/Return) and re-tint it.
    override func textDidEndEditing(_ notification: Notification) {
        (notification.object as? NSTextView)?.insertionPointColor = .textColor
        super.textDidEndEditing(notification)
    }
}

/// The header: raised fill, column separators, name in the muted label colour, the type as a small tag,
/// the sort indicator, and a 1pt line underneath. Keeps SATableHeaderView's column menus.
@objc(SAClaudeTableHeaderView) final class SAClaudeTableHeaderView: SATableHeaderView {

    var palette = SAClaudeGridChrome.palette(from: .standard) { didSet { needsDisplay = true } }

    private static let nameFont = NSFont.systemFont(ofSize: 11.5, weight: .medium)
    private static let tagFont = NSFont.systemFont(ofSize: 9.5, weight: .medium)

    override func draw(_ dirtyRect: NSRect) {
        let area = bounds.intersection(dirtyRect)
        palette.headerBackground.setFill()
        area.fill()
        guard let table = tableView else { return }
        for column in 0..<table.numberOfColumns {
            let rect = headerRect(ofColumn: column)
            guard rect.intersects(area) else { continue }
            drawColumn(table.tableColumns[column], in: rect, table: table)
            if table.numberOfRows > 0, SAClaudeGridChrome.drawsColumnSeparator(columnMaxX: rect.maxX, boundsMaxX: table.bounds.maxX) {
                palette.rowLine.setFill()
                NSRect(x: rect.maxX - 1, y: rect.minY, width: 1, height: rect.height).intersection(area).fill()
            }
        }
        palette.headerLine.setFill()
        NSRect(x: area.minX, y: bounds.maxY - 1, width: area.width, height: 1).intersection(area).fill()
    }

    private func drawColumn(_ column: NSTableColumn, in rect: NSRect, table: NSTableView) {
        let parts = SAClaudeGridChrome.headerParts(column.headerCell.attributedStringValue)
        var textRect = rect.insetBy(dx: 8, dy: 0)
        if let indicator = table.indicatorImage(in: column) {
            let size = indicator.size
            let indicatorRect = NSRect(x: rect.maxX - 8 - size.width, y: rect.midY - size.height / 2, width: size.width, height: size.height)
            if indicator.isTemplate {
                // Template images draw black; tint them like the header label.
                let palette = self.palette
                let tinted = NSImage(size: size, flipped: false) { r in
                    indicator.draw(in: r)
                    palette.headerLabel.set()
                    r.fill(using: .sourceAtop)
                    return true
                }
                tinted.draw(in: indicatorRect)
            } else {
                indicator.draw(in: indicatorRect)
            }
            textRect.size.width -= size.width + 4
        }
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        let name = NSMutableAttributedString(string: parts.name, attributes: [.font: Self.nameFont, .foregroundColor: palette.headerLabel, .paragraphStyle: style])
        if let type = parts.type {
            name.append(NSAttributedString(string: "  ", attributes: [.font: Self.tagFont]))
            name.append(NSAttributedString(string: type.uppercased(), attributes: [.font: Self.tagFont, .foregroundColor: palette.typeTag, .kern: 0.4, .paragraphStyle: style]))
        }
        let height = name.size().height
        name.draw(with: NSRect(x: textRect.minX, y: rect.midY - height / 2, width: textRect.width, height: height),
                  options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }
}

/// Fills the corner above the vertical scroller like the header.
final class SAClaudeGridCornerView: NSView {
    var palette = SAClaudeGridChrome.palette(from: .standard) { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        let area = bounds.intersection(dirtyRect)
        palette.headerBackground.setFill()
        area.fill()
        palette.headerLine.setFill()
        NSRect(x: area.minX, y: bounds.maxY - 1, width: area.width, height: 1).intersection(area).fill()
    }
}
