//
//  SAClaudeTableView.swift
//  Sequel Ace
//
//  The Claude grid look for an SPTableView (the Structure tab's fields and
//  indexes): the same renderer as SAClaudeCopyTable, plus theme text for
//  cells the delegate doesn't colour. App target only.
//

import AppKit

@objc(SAClaudeTableView) final class SAClaudeTableView: SPTableView {

    private lazy var renderer = SAClaudeGridRenderer(table: self)

    override func awakeFromNib() {
        super.awakeFromNib()
        renderer.install()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        renderer.applyPalette(force: true)
    }

    override var gridStyleMask: NSTableView.GridLineStyle {
        get { super.gridStyleMask }
        set { super.gridStyleMask = renderer.gridMask(newValue) }
    }

    override var rowHeight: CGFloat {
        get { super.rowHeight }
        set { super.rowHeight = renderer.clampedRowHeight(newValue) }
    }

    override func frameOfCell(atColumn column: Int, row: Int) -> NSRect {
        renderer.frameOfCell(super.frameOfCell(atColumn: column, row: row), column: column)
    }

    override func drawBackground(inClipRect clipRect: NSRect) { renderer.drawBackground(in: clipRect) }
    override func highlightSelection(inClipRect clipRect: NSRect) { renderer.highlightSelection(in: clipRect) }
    override func drawGrid(inClipRect clipRect: NSRect) { renderer.drawGrid(in: clipRect) }

    // Cell-based tables only; overriding the deprecated hook is deliberate.
    @available(macOS, deprecated: 10.10)
    override func preparedCell(atColumn column: Int, row: Int) -> NSCell? {
        let cell = super.preparedCell(atColumn: column, row: row)
        if let cell { SAClaudeGridCellStyler.styleDefaultText(cell) }
        return cell
    }

    // MARK: Inline editing

    override func editColumn(_ column: Int, row: Int, with event: NSEvent?, select: Bool) {
        super.editColumn(column, row: row, with: event, select: select)
        guard let editor = currentEditor() as? NSTextView else { return }
        editor.drawsBackground = true
        editor.backgroundColor = renderer.palette.background
        editor.textColor = renderer.palette.text
        editor.insertionPointColor = renderer.palette.caret
    }

    /// The field editor is the window's shared one: give its caret back before other fields use it.
    /// Reset before super, which may start editing the next cell (Tab/Return) and re-tint it.
    override func textDidEndEditing(_ notification: Notification) {
        (notification.object as? NSTextView)?.insertionPointColor = .textColor
        super.textDidEndEditing(notification)
    }

    override func updateTrackingAreas() { super.updateTrackingAreas(); renderer.updateTrackingArea() }
    override func mouseMoved(with event: NSEvent) { super.mouseMoved(with: event); renderer.mouseMoved(event) }
    override func mouseExited(with event: NSEvent) { super.mouseExited(with: event); renderer.mouseExited() }
    override func scrollWheel(with event: NSEvent) { super.scrollWheel(with: event); renderer.scrolled() }
    override func reloadData() {
        renderer.rowsReloaded()
        super.reloadData()
        fitColumnsToContent()
    }

    // MARK: Column widths

    /// Padding added to a column's widest content (cell insets and breathing room).
    private static let columnPadding: CGFloat = 16
    /// Wide values (comments, defaults) stop here; the rest truncate as before.
    private static let maximumFittedWidth: CGFloat = 360
    /// Rows measured per column; Structure and index lists are short, this only bounds the work.
    private static let measuredRows = 500

    /// Widens or narrows each visible column to its widest header or cell (the XIB widths were made
    /// for 11pt text; the theme font is larger), so values and pop-up menus aren't cut off.
    private func fitColumnsToContent() {
        let rows = min(numberOfRows, Self.measuredRows)
        for column in tableColumns where !column.isHidden {
            var width = ceil(column.headerCell.cellSize.width)
            for row in 0..<rows {
                // A copy of the column's cell, filled the way the table fills it for drawing.
                guard let cell = (column.dataCell(forRow: row) as? NSCell)?.copy() as? NSCell else { continue }
                cell.objectValue = dataSource?.tableView?(self, objectValueFor: column, row: row)
                delegate?.tableView?(self, willDisplayCell: cell, for: column, row: row)
                width = max(width, ceil(cell.cellSize.width))
            }
            let fitted = min(max(width + Self.columnPadding, column.minWidth), min(column.maxWidth, Self.maximumFittedWidth))
            if abs(column.width - fitted) > 0.5 { column.width = fitted }
        }
    }
    override func noteNumberOfRowsChanged() { renderer.rowsReloaded(); super.noteNumberOfRowsChanged() }
}
