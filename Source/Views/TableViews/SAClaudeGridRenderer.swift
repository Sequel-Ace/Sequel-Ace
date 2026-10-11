//
//  SAClaudeGridRenderer.swift
//  Sequel Ace
//
//  The Claude grid look for any NSTableView: background and zebra rows, row/column
//  lines limited to rows, hover under the lines, the theme selection, 30pt header,
//  vertically centred cells, live palette. App target only.
//

import AppKit

/// Draws a table in the Claude grid look; a table subclass owns one and forwards to it.
final class SAClaudeGridRenderer {

    unowned let table: NSTableView
    private(set) var palette = SAClaudeGridChrome.palette(from: .standard)
    private(set) var hoveredRow = -1
    /// Optional per-row error flag (console); error rows get a clay tint and a 2pt clay edge.
    var isErrorRow: ((Int) -> Bool)?
    /// How far the data cell draws its text below the top of its frame: SPTextAndLinkCell shifts it 2pt;
    /// a table of plain NSTextFieldCells (the console) sets 0.
    var cellTextTopOffset: CGFloat = 2

    /// Clay `#D97757`, the error accent.
    private static let clay = NSColor(srgbRed: 0xD9 / 255, green: 0x77 / 255, blue: 0x57 / 255, alpha: 1)
    private static let errorTintRatio: CGFloat = 0.06
    private static var lineHeights: [String: CGFloat] = [:]

    private var errorTint: NSColor
    private var observer: NSObjectProtocol?
    private var hoverArea: NSTrackingArea?

    init(table: NSTableView) {
        self.table = table
        errorTint = Self.errorTint(for: palette.background)
    }

    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

    private static func errorTint(for background: NSColor) -> NSColor {
        SAClaudeEditorChrome.derivedColour(text: clay, background: background, ratio: errorTintRatio)
    }

    /// Call from awakeFromNib: alternating rows off, 30pt header, corner view, palette, observers.
    func install() {
        // Idempotent: a second call would add a second defaults observer.
        guard observer == nil else { return }
        table.usesAlternatingRowBackgroundColors = false
        table.gridStyleMask.formUnion([.solidHorizontalGridLineMask, .solidVerticalGridLineMask])
        if var frame = table.headerView?.frame { frame.size.height = SAClaudeGridChrome.headerHeight; table.headerView?.frame = frame }
        table.cornerView = SAClaudeGridCornerView(frame: NSRect(x: 0, y: 0, width: 16, height: SAClaudeGridChrome.headerHeight))
        applyPalette(force: true)
        observer = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.applyPalette(force: false)
        }
    }

    /// Re-reads the theme; with `force` (appearance changes) also drops the cell styler's cached palette.
    func applyPalette(force: Bool) {
        if force { SAClaudeGridCellStyler.invalidatePalette() }
        let newPalette = SAClaudeGridChrome.palette(from: .standard)
        guard force || newPalette != palette else { return }
        palette = newPalette
        errorTint = Self.errorTint(for: palette.background)
        table.backgroundColor = palette.background
        let scrollView = table.enclosingScrollView
        scrollView?.backgroundColor = palette.background
        scrollView?.drawsBackground = true
        // Only when it changes: a new appearance re-enters viewDidChangeEffectiveAppearance.
        let scrollerAppearance = SAClaudeGridChrome.scrollerAppearance(for: palette.background)
        if scrollView?.appearance?.name != scrollerAppearance?.name {
            scrollView?.appearance = scrollerAppearance
        }
        (table.headerView as? SAClaudeTableHeaderView)?.palette = palette
        (table.cornerView as? SAClaudeGridCornerView)?.palette = palette
        table.needsDisplay = true
        table.headerView?.needsDisplay = true
    }

    /// NSTableView only calls drawGrid(inClipRect:) when the mask is non-empty; row and column
    /// lines are always drawn (the "vertical gridlines" preference no longer applies), so both
    /// bits are always on.
    func gridMask(_ proposed: NSTableView.GridLineStyle) -> NSTableView.GridLineStyle {
        proposed.union([.solidHorizontalGridLineMask, .solidVerticalGridLineMask])
    }

    /// Rows are at least 30pt. Pure, so a table may call it before its renderer has done anything.
    func clampedRowHeight(_ proposed: CGFloat) -> CGFloat {
        max(proposed, SAClaudeGridChrome.minimumRowHeight)
    }

    /// One line of the cell's text (cached per font).
    private static func lineHeight(for font: NSFont) -> CGFloat {
        let key = "\(font.fontName)|\(font.pointSize)"
        if let height = lineHeights[key] { return height }
        let height = NSLayoutManager().defaultLineHeight(for: font)
        lineHeights[key] = height
        return height
    }

    /// Cells lay their text out from the top; centre one line in the taller rows. This frame
    /// feeds drawing, the field editor and link-arrow hit testing alike; selection and hover
    /// use rect(ofRow:) and keep the full row.
    func frameOfCell(_ superFrame: NSRect, column: Int) -> NSRect {
        guard column >= 0, column < table.numberOfColumns, let cell = table.tableColumns[column].dataCell as? NSCell, let cellFont = cell.font else { return superFrame }
        let inset = max(0, floor((superFrame.height - (Self.lineHeight(for: cellFont) + cellTextTopOffset)) / 2))
        return superFrame.insetBy(dx: 0, dy: inset)
    }

    // MARK: Drawing

    func drawBackground(in clipRect: NSRect) {
        palette.background.setFill()
        let area = clipRect.intersection(table.bounds)
        area.fill()
        let visible = table.rows(in: area)
        guard visible.length > 0 else { return }
        palette.zebra.setFill()
        for row in visible.location..<NSMaxRange(visible) where SAClaudeGridChrome.isZebra(row: row) {
            table.rect(ofRow: row).intersection(area).fill()
        }
        guard let isErrorRow else { return }
        errorTint.setFill()
        for row in visible.location..<NSMaxRange(visible) where isErrorRow(row) {
            table.rect(ofRow: row).intersection(area).fill()
        }
    }

    func highlightSelection(in clipRect: NSRect) {
        let visible = table.rows(in: clipRect)
        guard visible.length > 0 else { return }
        // Hover is filled here, not in drawRow: this runs before drawGrid, so the row's lines stay on top.
        if hoveredRow >= visible.location, hoveredRow < NSMaxRange(visible), !table.isRowSelected(hoveredRow) {
            palette.hover.setFill()
            table.rect(ofRow: hoveredRow).intersection(clipRect).fill()
        }
        palette.selection.setFill()
        // Only the visible slice: after Select All on a huge result, walking every selected row janks.
        let selected = table.selectedRowIndexes
        for row in selected[selected.indexRange(in: visible.location..<NSMaxRange(visible))] {
            table.rect(ofRow: row).intersection(clipRect).fill()
        }
    }

    func drawGrid(in clipRect: NSRect) {
        palette.rowLine.setFill()
        let visible = table.rows(in: clipRect)
        for row in visible.location..<NSMaxRange(visible) {
            let r = table.rect(ofRow: row)
            NSRect(x: clipRect.minX, y: r.maxY - 1, width: clipRect.width, height: 1).intersection(clipRect).fill()
        }
        drawColumnLines(in: clipRect)
        // The clay edge goes last, over the selection and the lines.
        guard let isErrorRow else { return }
        Self.clay.setFill()
        let bounds = table.bounds
        for row in visible.location..<NSMaxRange(visible) where isErrorRow(row) {
            let r = table.rect(ofRow: row)
            NSRect(x: bounds.minX, y: r.minY, width: 2, height: r.height).intersection(clipRect).fill()
        }
    }

    /// Column lines run from the top to the bottom of the last row, not down the empty area.
    private func drawColumnLines(in clipRect: NSRect) {
        let rowCount = table.numberOfRows
        let lastRowMaxY = rowCount > 0 ? table.rect(ofRow: rowCount - 1).maxY : 0
        guard let bottom = SAClaudeGridChrome.columnLineExtent(rowCount: rowCount, lastRowMaxY: lastRowMaxY) else { return }
        let bounds = table.bounds
        for column in 0..<table.numberOfColumns {
            let r = table.rect(ofColumn: column)
            guard SAClaudeGridChrome.drawsColumnSeparator(columnMaxX: r.maxX, boundsMaxX: bounds.maxX) else { continue }
            NSRect(x: r.maxX - 1, y: bounds.minY, width: 1, height: bottom - bounds.minY).intersection(clipRect).fill()
        }
    }

    // MARK: Hover

    /// Call from updateTrackingAreas (after super). The table owns the area, so its mouse overrides
    /// receive the events and forward them here.
    func updateTrackingArea() {
        if let hoverArea { table.removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: table, userInfo: nil)
        table.addTrackingArea(area)
        hoverArea = area
    }

    func mouseMoved(_ event: NSEvent) {
        setHoveredRow(table.row(at: table.convert(event.locationInWindow, from: nil)))
    }

    func mouseExited() {
        setHoveredRow(-1)
    }

    /// Wheel and trackpad scrolling send no mouseMoved: re-read the row under the pointer.
    func scrolled() {
        // Like the tracking area (.activeInKeyWindow): no hover outside the key window.
        guard let window = table.window, window.isKeyWindow else { setHoveredRow(-1); return }
        let point = table.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        setHoveredRow(table.visibleRect.contains(point) ? table.row(at: point) : -1)
    }

    /// A re-run or reload leaves the old index meaningless.
    func rowsReloaded() {
        setHoveredRow(-1)
    }

    private func setHoveredRow(_ row: Int) {
        guard row != hoveredRow else { return }
        if hoveredRow >= 0, hoveredRow < table.numberOfRows { table.setNeedsDisplay(table.rect(ofRow: hoveredRow)) }
        hoveredRow = row
        if row >= 0 { table.setNeedsDisplay(table.rect(ofRow: row)) }
    }
}
