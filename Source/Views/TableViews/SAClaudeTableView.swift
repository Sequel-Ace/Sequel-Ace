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

    override func updateTrackingAreas() { super.updateTrackingAreas(); renderer.updateTrackingArea() }
    override func mouseMoved(with event: NSEvent) { super.mouseMoved(with: event); renderer.mouseMoved(event) }
    override func mouseExited(with event: NSEvent) { super.mouseExited(with: event); renderer.mouseExited() }
    override func scrollWheel(with event: NSEvent) { super.scrollWheel(with: event); renderer.scrolled() }
    override func reloadData() { renderer.rowsReloaded(); super.reloadData() }
    override func noteNumberOfRowsChanged() { renderer.rowsReloaded(); super.noteNumberOfRowsChanged() }
}
