//
//  SAClaudeQueryConsoleStyler.swift
//  Sequel Ace
//
//  The Query Console window in the Claude look: the console table drawn as the
//  Claude grid (with error rows tinted and edged in clay), a 40pt toolbar at the
//  top holding the filter field, the options menu, Clear and Save…, and the cell
//  text helper the controller calls. Colours follow the editor theme live.
//  App target only.
//

import AppKit

/// The console's table: the shared Claude grid drawing, plus error rows from `isErrorRow`.
@objc(SAClaudeConsoleTableView) final class SAClaudeConsoleTableView: NSTableView {

    /// The drawing, hover and palette live in the renderer; these overrides only forward to it.
    private lazy var renderer: SAClaudeGridRenderer = {
        let renderer = SAClaudeGridRenderer(table: self)
        // Plain NSTextFieldCells draw their text at the top of the frame (no SPTextAndLinkCell 2pt shift).
        renderer.cellTextTopOffset = 0
        return renderer
    }()

    var isErrorRow: ((Int) -> Bool)? {
        get { renderer.isErrorRow }
        set { renderer.isErrorRow = newValue; needsDisplay = true }
    }

    override func awakeFromNib() {
        super.awakeFromNib()
        // Cell-based tables mark the selected row's cells highlighted, which draws a system selection box
        // over the theme selection; the grids clear that in willDisplayCell, but the console's delegate has
        // no such hook. With no highlight style the cells stay plain and the selection is drawn below.
        selectionHighlightStyle = .none
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

    /// No highlight style means AppKit skips highlightSelection(inClipRect:); hover and selection are
    /// filled here instead, at the same point (after the background, before the lines and cells).
    override func drawBackground(inClipRect clipRect: NSRect) {
        renderer.drawBackground(in: clipRect)
        renderer.highlightSelection(in: clipRect)
    }

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
}

/// Restyles the Query Console window once and keeps it in step with the editor theme.
@objc(SAClaudeQueryConsoleStyler) final class SAClaudeQueryConsoleStyler: NSObject {

    private static var associationKey: UInt8 = 0

    // MARK: Cell text

    private static var cachedStyle: SAClaudeConsoleTextStyle?
    private static var styleObserver: NSObjectProtocol?

    /// The text style for console cells (cached; dropped on any defaults change).
    private static var textStyle: SAClaudeConsoleTextStyle {
        if styleObserver == nil {
            styleObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { _ in
                cachedStyle = nil
            }
        }
        if let cachedStyle { return cachedStyle }
        let style = SAClaudeConsoleTextStyle.from(defaults: .standard, font: UserDefaults.getFont())
        cachedStyle = style
        return style
    }

    /// The console cell's text: General font with tabular digits, muted meta columns, SQL colouring
    /// for queries, soft clay for errors.
    @objc(attributedValue:columnIdentifier:isError:)
    static func attributedValue(_ value: String, columnIdentifier: String, isError: Bool) -> NSAttributedString {
        SAClaudeConsoleText.attributed(value, column: SAClaudeConsoleColumn(identifier: columnIdentifier), isError: isError, style: textStyle)
    }

    // MARK: Window

    private weak var window: NSWindow?
    private weak var contentView: NSView?
    private weak var tableView: NSTableView?
    private weak var scrollView: NSScrollView?
    private weak var searchField: NSSearchField?
    private weak var gearButton: NSPopUpButton?
    private weak var clearButton: NSButton?
    private weak var saveButton: NSButton?
    private weak var loggingLabel: NSTextField?
    private let toolbar = SAClaudeConsoleToolbarView()
    private let fieldBackground = SAClaudeConsoleFieldView()
    private let bottomLine = SAClaudeDividerLine(frame: .zero)
    private var placeholder = ""
    private var defaultsObserver: NSObjectProtocol?
    private var appearanceObservation: NSKeyValueObservation?
    private var saveTitleObservation: NSKeyValueObservation?
    private var appliedPalettes: (grid: SAClaudeGridChrome.Palette, editor: SAClaudeEditorChrome.Palette)?
    private var appliedTextStyle: SAClaudeConsoleTextStyle?
    private var appliedFontKey: String?

    private static let buttonFont = NSFont.systemFont(ofSize: 13)
    private static let fieldFont = NSFont.systemFont(ofSize: 13)
    private static let labelFont = NSFont.systemFont(ofSize: 11)
    private static let fieldInset: CGFloat = 6

    /// Builds the toolbar and restyles the window (once per window).
    @objc(attachToWindow:tableView:searchField:clearButton:saveButton:loggingLabel:isErrorRow:)
    static func attach(window: NSWindow?, tableView: NSTableView?, searchField: NSSearchField?, clearButton: NSButton?,
                       saveButton: NSButton?, loggingLabel: NSTextField?, isErrorRow: ((Int) -> Bool)?) {
        guard let window, let contentView = window.contentView, let tableView, let scrollView = tableView.enclosingScrollView,
              objc_getAssociatedObject(window, &associationKey) == nil else { return }
        let styler = SAClaudeQueryConsoleStyler()
        objc_setAssociatedObject(window, &associationKey, styler, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        styler.window = window
        styler.contentView = contentView
        styler.tableView = tableView
        styler.scrollView = scrollView
        styler.searchField = searchField
        styler.clearButton = clearButton
        styler.saveButton = saveButton
        styler.loggingLabel = loggingLabel
        styler.gearButton = findPopUp(in: contentView, excluding: scrollView)
        (tableView as? SAClaudeConsoleTableView)?.isErrorRow = isErrorRow
        styler.build()
    }

    deinit {
        if let defaultsObserver { NotificationCenter.default.removeObserver(defaultsObserver) }
    }

    /// The options (gear) pull-down: the XIB gives it no outlet.
    private static func findPopUp(in view: NSView, excluding excluded: NSView) -> NSPopUpButton? {
        for subview in view.subviews where subview !== excluded {
            if let popUp = subview as? NSPopUpButton { return popUp }
            if let found = findPopUp(in: subview, excluding: excluded) { return found }
        }
        return nil
    }

    private func build() {
        guard let contentView, let scrollView else { return }
        let height = SAClaudeConsoleToolbarLayout.height
        let bounds = contentView.bounds

        // The toolbar across the top; the table fills the rest.
        toolbar.frame = NSRect(x: bounds.minX, y: contentView.isFlipped ? bounds.minY : bounds.maxY - height, width: bounds.width, height: height)
        toolbar.autoresizingMask = [.width, contentView.isFlipped ? .maxYMargin : .minYMargin]
        contentView.addSubview(toolbar)
        bottomLine.frame = NSRect(x: 0, y: toolbar.isFlipped ? height - 1 : 0, width: bounds.width, height: 1)
        bottomLine.autoresizingMask = [.width, toolbar.isFlipped ? .minYMargin : .maxYMargin]
        toolbar.addSubview(bottomLine)

        scrollView.frame = NSRect(x: bounds.minX, y: contentView.isFlipped ? bounds.minY + height : bounds.minY,
                                  width: bounds.width, height: max(0, bounds.height - height))
        scrollView.autoresizingMask = [.width, .height]
        // The toolbar's line separates them; the XIB bezel would add a second edge.
        scrollView.borderType = .noBorder

        if let searchField {
            fieldBackground.onClick = { [weak searchField] in
                guard let searchField else { return }
                searchField.window?.makeFirstResponder(searchField)
            }
            toolbar.addSubview(fieldBackground)
            fieldBackground.addSubview(searchField)
            searchField.autoresizingMask = []
            searchField.isBezeled = false
            searchField.isBordered = false
            searchField.drawsBackground = false
            searchField.focusRingType = .none
            searchField.controlSize = .regular
            searchField.font = Self.fieldFont
            placeholder = searchField.placeholderString ?? ""
        }
        if let loggingLabel {
            toolbar.addSubview(loggingLabel)
            loggingLabel.autoresizingMask = []
            loggingLabel.isBordered = false
            loggingLabel.isBezeled = false
            loggingLabel.drawsBackground = false
            loggingLabel.font = Self.labelFont
            loggingLabel.lineBreakMode = .byTruncatingTail
            loggingLabel.cell?.isScrollable = false
            loggingLabel.cell?.truncatesLastVisibleLine = true
        }
        if let gearButton {
            toolbar.addSubview(gearButton)
            gearButton.autoresizingMask = []
            gearButton.isBordered = false
            (gearButton.cell as? NSPopUpButtonCell)?.arrowPosition = .noArrow
            gearButton.imagePosition = .imageOnly
            gearButton.setAccessibilityLabel(NSLocalizedString("Console options", comment: "Query Console: accessibility name of the options menu button in the toolbar"))
            SAClaudeHoverHighlighter.attach(to: gearButton)
        }
        // The controller titles Save "Save As..." or "Save View As..." (filtered); that full title becomes the tooltip.
        saveButton?.toolTip = saveButton?.title
        let labelled: [(NSButton?, String)] = [
            (clearButton, NSLocalizedString("Clear", comment: "clear button")),
            (saveButton, NSLocalizedString("Save…", comment: "Run All console: button that saves all output to a text file")),
        ]
        for (button, title) in labelled {
            guard let button else { continue }
            toolbar.addSubview(button)
            button.autoresizingMask = []
            button.isBordered = false
            button.title = title
            button.font = Self.buttonFont
            button.imagePosition = .imageLeading
            button.imageScaling = .scaleNone
            // Borderless buttons put the image at the very left edge otherwise; this centres icon + label together.
            button.alignment = .center
            button.imageHugsTitle = true
            SAClaudeHoverHighlighter.attach(to: button)
        }
        // The controller retitles Save as the filter changes; keep the short label, move its title to the tooltip.
        if let saveButton {
            let label = saveButton.title
            saveTitleObservation = saveButton.observe(\.title) { button, _ in
                guard button.title != label else { return }
                button.toolTip = button.title
                button.title = label
            }
        }

        toolbar.onResize = { [weak self] in self?.layoutToolbar() }
        applyPalette(force: true)
        defaultsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.applyPalette(force: false)
        }
        // Dynamic fallback colours (no theme saved yet) resolve differently in light and dark; applyPalette(force:)
        // also drops the cached cell text style, which bakes them in.
        appearanceObservation = contentView.observe(\.effectiveAppearance) { [weak self] _, _ in
            DispatchQueue.main.async { self?.applyPalette(force: true) }
        }
    }

    /// The controller's font observer calls -[NSTableView setFont:], which leaves the cells' fonts alone; the
    /// renderer centres text by the cell font, so the cells take the General font here (and the table redraws).
    private func applyFont(_ font: NSFont) {
        let key = "\(font.fontName)|\(font.pointSize)"
        guard key != appliedFontKey else { return }
        appliedFontKey = key
        guard let tableView else { return }
        for column in tableView.tableColumns { (column.dataCell as? NSCell)?.font = font }
        tableView.needsDisplay = true
    }

    /// Drops the cached cell text style and redraws when it changed (a font or syntax-colour-only theme change
    /// leaves the grid and editor palettes equal), or always with `force` (appearance changes).
    private func applyTextStyle(font: NSFont, force: Bool) {
        let style = SAClaudeConsoleTextStyle.from(defaults: .standard, font: font)
        guard force || style != appliedTextStyle else { return }
        appliedTextStyle = style
        Self.cachedStyle = nil
        tableView?.needsDisplay = true
    }

    /// Applies the colours derived from the editor theme; skips work when nothing changed.
    private func applyPalette(force: Bool) {
        let grid = SAClaudeGridChrome.palette(from: .standard)
        let editor = SAClaudeEditorChrome.palette(from: .standard)
        let font = UserDefaults.getFont()
        applyFont(font)
        applyTextStyle(font: font, force: force)
        if !force, let appliedPalettes, appliedPalettes.grid == grid, appliedPalettes.editor == editor { return }
        appliedPalettes = (grid, editor)

        let background = grid.background
        window?.backgroundColor = background
        contentView?.layer?.backgroundColor = background.cgColor
        toolbar.fillColour = background
        bottomLine.colourOverride = grid.rowLine
        fieldBackground.fillColour = grid.hover

        // Controls on the toolbar (field caret and cancel button, menus) follow the theme's brightness.
        let appearance = SAClaudeGridChrome.scrollerAppearance(for: background)
        // The title under the transparent title bar too. Only on a change: it re-enters the appearance observation.
        if let window, window.appearance?.name != appearance?.name { window.appearance = appearance }
        if toolbar.appearance?.name != appearance?.name { toolbar.appearance = appearance }
        if let scrollView {
            scrollView.drawsBackground = true
            scrollView.backgroundColor = background
            if scrollView.appearance?.name != appearance?.name { scrollView.appearance = appearance }
        }

        if let searchField {
            searchField.textColor = grid.text
            (searchField.cell as? NSSearchFieldCell)?.placeholderAttributedString =
                NSAttributedString(string: placeholder, attributes: [.foregroundColor: grid.headerLabel, .font: Self.fieldFont])
        }
        loggingLabel?.textColor = grid.headerLabel

        if let gearButton {
            gearButton.item(at: 0)?.image = SAClaudeGlyphs.image(.more, tint: editor.icon)
            gearButton.contentTintColor = editor.buttonText
            SAClaudeHoverHighlighter.setFillColour(grid.hover, for: gearButton)
        }
        let labelled: [(NSButton?, SAClaudeGlyph)] = [(clearButton, .clear), (saveButton, .save)]
        for (button, glyph) in labelled {
            guard let button else { continue }
            let image = SAClaudeGlyphs.image(glyph, tint: editor.icon)
            button.image = image
            button.alternateImage = image
            button.contentTintColor = editor.buttonText
            SAClaudeHoverHighlighter.setFillColour(grid.hover, for: button)
        }

        tableView?.needsDisplay = true
        tableView?.headerView?.needsDisplay = true
        layoutToolbar()
    }

    /// Icon + label width, like the editor bar: 28 for the icon and its padding, the label, 10 after.
    private func labelledWidth(of button: NSButton) -> CGFloat {
        let titleWidth = ceil((button.title as NSString).size(withAttributes: [.font: button.font ?? Self.buttonFont]).width)
        return 28 + titleWidth + 10
    }

    private func layoutToolbar() {
        let bounds = toolbar.bounds
        let buttonHeight = SAClaudeEditorChrome.buttonHeight
        let buttonY = SAClaudeEditorChrome.centredY(height: buttonHeight, in: bounds.height)
        var buttons: [NSView] = []
        var widths: [CGFloat] = []
        if let gearButton { buttons.append(gearButton); widths.append(buttonHeight) }
        for case let button? in [clearButton, saveButton] {
            buttons.append(button)
            widths.append(max(labelledWidth(of: button), buttonHeight))
        }
        let layout = SAClaudeConsoleToolbarLayout.layout(totalWidth: bounds.width, buttonWidths: widths)
        for (index, button) in buttons.enumerated() {
            let frame = NSRect(x: bounds.minX + layout.buttons[index].x, y: buttonY, width: layout.buttons[index].width, height: buttonHeight)
            if button.frame != frame { button.frame = frame }
        }

        let fieldHeight = SAClaudeConsoleToolbarLayout.searchHeight
        let fieldFrame = NSRect(x: bounds.minX + layout.search.x, y: SAClaudeEditorChrome.centredY(height: fieldHeight, in: bounds.height),
                                width: layout.search.width, height: fieldHeight)
        if fieldBackground.frame != fieldFrame { fieldBackground.frame = fieldFrame }
        if let searchField {
            let height = ceil(searchField.cell?.cellSize.height ?? 16)
            let frame = NSRect(x: Self.fieldInset, y: SAClaudeEditorChrome.centredY(height: height, in: fieldHeight),
                               width: max(0, fieldFrame.width - Self.fieldInset * 2), height: height)
            if searchField.frame != frame { searchField.frame = frame }
        }

        if let loggingLabel {
            let padding = SAClaudeConsoleToolbarLayout.sidePadding
            let x = fieldFrame.maxX + padding
            let right = (buttons.first.map { $0.frame.minX } ?? bounds.maxX) - padding
            let height = ceil(loggingLabel.cell?.cellSize.height ?? 14)
            let frame = NSRect(x: x, y: SAClaudeEditorChrome.centredY(height: height, in: bounds.height), width: max(0, right - x), height: height)
            if loggingLabel.frame != frame { loggingLabel.frame = frame }
        }
    }
}

/// The toolbar's background; reports size changes so the styler can re-lay out its controls.
final class SAClaudeConsoleToolbarView: NSView {
    var fillColour: NSColor = .clear { didSet { needsDisplay = true } }
    var onResize: (() -> Void)?

    override func draw(_ dirtyRect: NSRect) {
        fillColour.setFill()
        bounds.intersection(dirtyRect).fill()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        onResize?()
    }
}

/// The rounded field behind the borderless search field; a click on its padding focuses the field.
final class SAClaudeConsoleFieldView: NSView {
    var fillColour: NSColor = .clear { didSet { needsDisplay = true } }
    var onClick: (() -> Void)?

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath.clip(bounds.intersection(dirtyRect))
        fillColour.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: SAClaudeStyle.barButtonRadius, yRadius: SAClaudeStyle.barButtonRadius).fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
}
