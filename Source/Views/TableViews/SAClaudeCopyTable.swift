//
//  SAClaudeCopyTable.swift
//  Sequel Ace
//
//  The Query and Content tab grids as a quiet sheet: theme background, every
//  other row shaded, lines between rows and columns, hover tint, the theme's selection colour, a 30pt header
//  with the column type as a small tag (drawn by SAClaudeGridRenderer). Only drawing changes; copying,
//  editing, sorting and menus are SPCopyTable's. App target only.
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

    /// The drawing, hover and palette live in the renderer; these overrides only forward to it.
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

    // MARK: Hover

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        renderer.updateTrackingArea()
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        renderer.mouseMoved(event)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        renderer.mouseExited()
    }

    override func scrollWheel(with event: NSEvent) {
        super.scrollWheel(with: event)
        renderer.scrolled()
    }

    override func reloadData() {
        renderer.rowsReloaded()
        super.reloadData()
    }

    override func noteNumberOfRowsChanged() {
        renderer.rowsReloaded()
        super.noteNumberOfRowsChanged()
    }

    // MARK: Inline editing (Content tab)

    override func editColumn(_ column: Int, row: Int, with event: NSEvent?, select: Bool) {
        super.editColumn(column, row: row, with: event, select: select)
        guard let editor = currentEditor() as? NSTextView else { return }
        editor.drawsBackground = true
        editor.backgroundColor = renderer.palette.background
        editor.textColor = renderer.palette.text
        editor.insertionPointColor = renderer.palette.caret
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
