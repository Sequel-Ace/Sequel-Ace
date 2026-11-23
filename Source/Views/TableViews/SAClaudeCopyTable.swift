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
            observer = SAClaudeAppearanceChange.addObserver { _ in
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

    /// Every theme text colour `style(_:role: .text)` has applied. Grids reuse one data cell per column,
    /// so a cell still carrying an earlier theme's colour must count as "nobody chose it" after a theme change.
    private static var appliedTextColours: [NSColor] = []

    private static func noteAppliedTextColour(_ colour: NSColor) {
        if !appliedTextColours.contains(where: { $0 == colour }) { appliedTextColours.append(colour) }
    }

    /// Sets the cell's text colour and font for its role; called from the grids' willDisplayCell.
    @objc(styleCell:role:)
    static func style(_ cell: Any, role: SAClaudeGridCellRole) {
        guard let cell = cell as? NSTextFieldCell else { return }
        switch role {
        case .text: applyText(Self.palette.text, to: cell)
        case .null: cell.textColor = Self.palette.null
        case .displayOverride: cell.textColor = Self.palette.displayOverride
        }
        finishStyling(cell, null: role == .null)
    }

    /// Sets a theme text colour and remembers it, so a cell still carrying it counts as "nobody chose it".
    private static func applyText(_ colour: NSColor, to cell: NSTextFieldCell) {
        noteAppliedTextColour(colour)
        cell.textColor = colour
    }

    private static func finishStyling(_ cell: NSTextFieldCell, null: Bool) {
        if let base = cell.font { cell.font = font(base, null: null) }
        // Cell-based tables mark the selected row's cells highlighted, which draws a system
        // selection box and white text; the table draws the theme selection itself.
        cell.isHighlighted = false
    }

    /// How far a disabled (read-only) cell's text sits from the background towards the text colour.
    private static let disabledTextRatio: CGFloat = 0.45

    /// The system colours a cell has when nobody chose one for it.
    static func isDefaultTextColour(_ colour: NSColor?) -> Bool {
        guard let colour else { return true }
        return colour == .controlTextColor || colour == .labelColor || colour == .textColor || colour == .secondaryLabelColor
            || appliedTextColours.contains(where: { $0 == colour })
    }

    /// Themes a text cell whose colour is still the system default (grids whose delegates don't style
    /// their cells); a colour a delegate set on purpose is kept.
    static func styleDefaultText(_ cell: NSCell) {
        guard let textCell = cell as? NSTextFieldCell, isDefaultTextColour(textCell.textColor) else {
            (cell as? NSTextFieldCell)?.isHighlighted = false
            return
        }
        if textCell.isEnabled {
            style(textCell, role: .text)
        } else {
            // AppKit only dims the stock control colour, so a themed colour would make a read-only cell
            // (a view's structure, Length/Default of TEXT/BLOB/JSON columns) look editable.
            let palette = Self.palette
            applyText(SAClaudeEditorChrome.derivedColour(text: palette.text, background: palette.background,
                                                          ratio: disabledTextRatio), to: textCell)
            finishStyling(textCell, null: false)
        }
    }
}

extension Notification.Name {
    /// Posted by `SAClaudeCopyTable` after it reloads its rows or changes their number.
    static let SAClaudeCopyTableDidReload = Notification.Name("SAClaudeCopyTableDidReload")
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

    /// Theme each prepared cell's default-coloured text (Relations, Triggers); Content and Query style their own.
    @objc var stylesCells = false

    // Cell-based tables only; overriding the deprecated hook is deliberate.
    @available(macOS, deprecated: 10.10)
    override func preparedCell(atColumn column: Int, row: Int) -> NSCell? {
        let cell = super.preparedCell(atColumn: column, row: row)
        if stylesCells, let cell { SAClaudeGridCellStyler.styleDefaultText(cell) }
        return cell
    }

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
        if fitsColumnsToContent { fitColumnsToContent() }
        NotificationCenter.default.post(name: .SAClaudeCopyTableDidReload, object: self)
    }

    override func noteNumberOfRowsChanged() {
        renderer.rowsReloaded()
        super.noteNumberOfRowsChanged()
        if fitsColumnsToContent { fitColumnsToContent() }
        NotificationCenter.default.post(name: .SAClaudeCopyTableDidReload, object: self)
    }

    // MARK: Fitted columns

    /// Whether the columns are sized to their content on every reload, the last one filling the grid's width and
    /// following it as the window resizes (Relations and Triggers: their XIB widths left most of the grid empty
    /// and truncated names and values). Content and Query keep their own column widths.
    @objc var fitsColumnsToContent = false {
        didSet {
            guard fitsColumnsToContent, !oldValue else { return }
            columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
            fitColumnsToContent()
        }
    }

    /// The most rows measured for a column's width; Relations and Triggers have a handful.
    private static let fittedRowLimit = 500
    /// Room beside a cell's own text width so the widest value isn't flush with the column's edge.
    private static let fittedCellPadding: CGFloat = 8

    /// Sizes each column to its header or widest value (see `SAClaudeGridChrome.fittedColumnWidths`).
    @objc func fitColumnsToContent() {
        guard numberOfColumns > 0 else { return }
        let rows = min(numberOfRows, Self.fittedRowLimit)
        let natural = tableColumns.enumerated().map { index, column -> CGFloat in
            var width = SAClaudeTableHeaderView.titleWidth(of: column)
            for row in 0..<rows {
                guard let cell = preparedCell(atColumn: index, row: row) else { continue }
                width = max(width, ceil(cell.cellSize.width) + Self.fittedCellPadding)
            }
            return width
        }
        let visibleWidth = enclosingScrollView?.contentSize.width ?? bounds.width
        let available = visibleWidth - intercellSpacing.width * CGFloat(numberOfColumns)
        let widths = SAClaudeGridChrome.fittedColumnWidths(natural: natural, available: available)
        // The last column follows the grid's width; as the window narrows it stops at its content's width (the grid
        // then scrolls) instead of AppKit's 10pt minimum. Only the current last column keeps such a minimum.
        for (index, column) in tableColumns.enumerated() {
            let original = xibMinimumWidths[column.identifier] ?? column.minWidth
            xibMinimumWidths[column.identifier] = original
            column.minWidth = index == tableColumns.count - 1
                ? min(max(original, ceil(natural[index]), SAClaudeGridChrome.fittedColumnMinimum), SAClaudeGridChrome.fittedColumnCap)
                : original
        }
        for (column, width) in zip(tableColumns, widths) where column.width != width {
            column.width = min(max(width, column.minWidth), column.maxWidth)
        }
    }

    /// Each column's minimum width before `fitColumnsToContent` raised the last one's.
    private var xibMinimumWidths: [NSUserInterfaceItemIdentifier: CGFloat] = [:]

    // MARK: Copy

    /// The Query results grid; the Content tab's grid doesn't change the Copy button's default.
    private static let queryResultsIdentifier = "CustomQueryResultsTableView"

    /// Copying from the Query results (its menu or the Edit menu) makes that action the Copy button's default.
    override func copy(_ sender: Any?) {
        super.copy(sender)
        guard identifier?.rawValue == Self.queryResultsIdentifier,
              let tag = (sender as? NSMenuItem)?.tag ?? (sender as? NSControl)?.tag,
              let action = SAClaudeQueryCopyAction(rawValue: tag) else { return }
        SAClaudeQueryCopyAction.store(action, in: .standard)
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
    /// The space `drawColumn` leaves each side of the title.
    private static let titleInset: CGFloat = 8

    /// The width a column needs for its whole title as the header draws it (name and type tag, both insets).
    static func titleWidth(of column: NSTableColumn) -> CGFloat {
        let parts = SAClaudeGridChrome.headerParts(column.headerCell.attributedStringValue)
        var width = NSAttributedString(string: parts.name, attributes: [.font: nameFont]).size().width
        if let type = parts.type {
            width += NSAttributedString(string: "  ", attributes: [.font: tagFont]).size().width
            width += NSAttributedString(string: type.uppercased(), attributes: [.font: tagFont, .kern: 0.4]).size().width
        }
        return ceil(width) + titleInset * 2
    }

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
        var textRect = rect.insetBy(dx: Self.titleInset, dy: 0)
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
        // A centred header cell (the Export sheet's checkbox columns) keeps its title centred; others stay leading.
        if column.headerCell.alignment == .center { style.alignment = .center }
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
