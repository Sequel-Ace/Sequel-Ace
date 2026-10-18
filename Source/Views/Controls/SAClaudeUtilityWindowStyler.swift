//
//  SAClaudeUtilityWindowStyler.swift
//  Sequel Ace
//
//  The pieces of the Claude look the utility windows share (spec 2026-10-18-claude-utility-windows-design.md, C and D),
//  for their bespoke stylers (the User Manager's, SAClaudeUserManagerStyler.swift; the other windows'):
//
//  - `SAClaudeUtilityChrome`: ghost icon buttons (square image buttons, help "?"), sidebar bar buttons and the gear,
//    ghost pills, titled cards, hairline split dividers, hairline-framed lists, SF Symbol images.
//  - `SAClaudeUtilitySidebar`: a source list in the Claude sidebar look (sidebar fill, rounded selection pills, row text,
//    glyphs, a quiet header). The list's class is swapped in place to a subclass that adds no stored properties.
//  - `SAClaudeUtilityGridTableView`: a plain list in the Claude grid look (as the Query Console and Server Variables).
//  - `SAClaudeTabViewTabs`: Claude segmented tabs (`SAClaudeConnectionTypeTabs`) in place of an NSTabView's own strip,
//    driving the tab view's selection (so its delegate runs as before) and following every change of it.
//
//  Every class swap follows `SAClaudeClassSwap` (exact class, nothing observing it by KVO); a view that can't be swapped
//  keeps the generic sheet skin. Frames, bindings, targets and actions stay as the XIB and the code made them; the
//  geometry is in SAClaudeUtilityWindowLayout.swift. App target only.
//

import AppKit

// MARK: - Chrome

enum SAClaudeUtilityChrome {

    /// An SF Symbol as a template image, for a ghost button (tinted by its `contentTintColor`).
    static func symbol(_ name: String, pointSize: CGFloat = 13, accessibilityDescription: String? = nil) -> NSImage? {
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: accessibilityDescription)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)) else { return nil }
        image.isTemplate = true
        return image
    }

    private static var tintedSymbols: [String: NSImage] = [:]

    /// An SF Symbol drawn in a resolved `tint` on a `canvas` (the glyph centred in a 16pt square at `glyphX`), not a
    /// template: for cells that draw their image as it is (`ImageAndTextCell`). Cached per symbol, tint and canvas.
    static func tintedSymbol(_ name: String, tint: NSColor, pointSize: CGFloat = 12, canvas: NSSize, glyphX: CGFloat) -> NSImage? {
        let rgb = tint.usingColorSpace(.sRGB) ?? tint
        let key = "\(name)|\(pointSize)|\(canvas.width)x\(canvas.height)|\(glyphX)|\(rgb.redComponent),\(rgb.greenComponent),\(rgb.blueComponent),\(rgb.alphaComponent)"
        if let cached = tintedSymbols[key] { return cached }
        guard let glyph = symbol(name, pointSize: pointSize) else { return nil }
        let image = NSImage(size: canvas, flipped: false) { _ in
            let size = glyph.size
            let rect = NSRect(x: glyphX + ((SAClaudeStyle.iconSize - size.width) / 2).rounded(),
                              y: ((canvas.height - size.height) / 2).rounded(), width: size.width, height: size.height)
            glyph.draw(in: rect)
            rgb.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        tintedSymbols[key] = image
        return image
    }

    /// `colour` resolved for `view`'s appearance (a dynamic colour baked for a cached image).
    static func resolved(_ colour: NSColor, for view: NSView) -> NSColor {
        var result = colour
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            result = NSColor(cgColor: colour.cgColor) ?? colour
        }
        return result
    }

    // MARK: Buttons

    /// A square image button (+/−, ◀/▶, …) as a 28pt ghost icon: borderless, the symbol only, hover fill; `label` is its
    /// tooltip and what VoiceOver reads.
    static func styleGhostIcon(_ button: NSButton, symbol name: String, label: String) {
        SAClaudeFormChrome.makeGhostIcon(button, image: symbol(name, accessibilityDescription: label), toolTip: label)
        button.setAccessibilityLabel(label)
    }

    /// A help (?) button as a ghost "?" icon.
    static func styleHelpButton(_ button: NSButton, label: String) {
        styleGhostIcon(button, symbol: "questionmark.circle", label: label)
    }

    /// A sidebar bottom-bar button (add, remove, a gear pull-down) as the main window's sidebar has them: the Claude glyph
    /// in the muted tint, borderless, the rounded hover fill.
    static func styleBarButton(_ button: NSButton, glyph: SAClaudeGlyph, label: String) {
        SAClaudeFormChrome.makePlain(button)
        SAClaudeSidebarChrome.styleBarButton(button, glyph: glyph)
        button.toolTip = label
        button.setAccessibilityLabel(label)
    }

    /// A gear pull-down as a Claude glyph button (its menu gets glyphs from `SAClaudeMenuGlyphPass` as it opens).
    static func styleGearButton(_ popUp: NSPopUpButton, label: String) {
        styleBarButton(popUp, glyph: .actions, label: label)
    }

    /// The tint of the ghost icons: the sheets' muted colour and hover fill.
    static func recolourGhostIcons(_ buttons: [NSButton], _ colours: SAClaudeSheetColours) {
        for button in buttons {
            if button.contentTintColor != colours.muted { button.contentTintColor = colours.muted }
            SAClaudeHoverHighlighter.setFillColour(colours.palette.hover, for: button)
        }
    }

    static let pillFont = NSFont.systemFont(ofSize: 12)
    private static let pillPadding: CGFloat = 10
    private static let pillImageGap: CGFloat = 5

    /// A titled push button as a ghost pill: borderless, an optional leading symbol, the title in 12pt, the rounded hover
    /// fill. Recolour with `recolourGhostPill`.
    static func styleGhostPill(_ button: NSButton, symbol name: String?) {
        SAClaudeFormChrome.makePlain(button)
        if let name, let image = symbol(name, pointSize: 12) {
            button.image = image
            button.alternateImage = nil
            button.imagePosition = .imageLeading
            button.imageHugsTitle = true
        } else {
            button.imagePosition = .noImage
        }
        SAClaudeHoverHighlighter.attach(to: button)
    }

    static func recolourGhostPill(_ button: NSButton, _ colours: SAClaudeSheetColours) {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let title = NSAttributedString(string: button.title, attributes: [.font: pillFont, .foregroundColor: colours.theme.text, .paragraphStyle: style])
        if button.attributedTitle != title { button.attributedTitle = title }
        if button.contentTintColor != colours.theme.text { button.contentTintColor = colours.theme.text }
        SAClaudeHoverHighlighter.setFillColour(colours.palette.hover, for: button)
    }

    /// The width a ghost pill needs for its title and symbol.
    static func ghostPillWidth(_ button: NSButton) -> CGFloat {
        let title = ceil((button.title as NSString).size(withAttributes: [.font: pillFont]).width)
        let image = button.imagePosition == .noImage ? 0 : (button.image?.size.width ?? 0) + pillImageGap
        return title + image + 2 * pillPadding
    }

    // MARK: Cards, dividers, lists

    /// Makes a titled box a Claude titled card (`SAClaudeSheetTitledBox`, as the sheet skin does) with no content margins of
    /// its own, so a styler places its content exactly; false when it isn't a titled box whose class may change.
    @discardableResult
    static func makeTitledCard(_ box: NSBox) -> Bool {
        if !(box is SAClaudeSheetTitledBox) {
            guard type(of: box) == NSBox.self, box.boxType == .primary, box.titlePosition != .noTitle, !box.title.isEmpty,
                  SAClaudeClassSwap.mayChangeClass(of: box) else { return false }
            object_setClass(box, SAClaudeSheetTitledBox.self)
        }
        if box.contentViewMargins != .zero { box.contentViewMargins = .zero }
        SAClaudeSheetBoxDrawing.hideNativeDrawing(of: box)
        box.needsDisplay = true
        return true
    }

    /// Places `box` so its content view fills `content` (in the box's superview) and returns what the box adds around it.
    @discardableResult
    static func placeCard(_ box: NSBox, content: NSRect) -> SAClaudeCardLayout.Chrome {
        if !box.autoresizingMask.isEmpty { box.autoresizingMask = [] }
        box.setFrameFromContentFrame(content)
        return chrome(of: box, content: content)
    }

    /// What `box` adds around its content frame (title above, line around), measured as AppKit lays it out.
    static func cardChrome(of box: NSBox) -> SAClaudeCardLayout.Chrome {
        let probe = NSRect(x: box.frame.minX, y: box.frame.minY, width: max(40, box.contentView?.frame.width ?? 40), height: 40)
        let saved = box.frame
        box.setFrameFromContentFrame(probe)
        let chrome = chrome(of: box, content: probe)
        box.frame = saved
        return chrome
    }

    private static func chrome(of box: NSBox, content: NSRect) -> SAClaudeCardLayout.Chrome {
        let frame = box.frame
        return SAClaudeCardLayout.Chrome(top: frame.maxY - content.maxY, bottom: content.minY - frame.minY,
                                         left: content.minX - frame.minX, right: frame.maxX - content.maxX)
    }

    /// A split view's divider as a 1pt hairline (`SPSplitView`'s custom colour; a plain split view keeps its own colour).
    static func styleSplitDivider(_ split: NSSplitView, colour: NSColor = SAClaudeStyle.divider) {
        if split.dividerStyle != .thin { split.dividerStyle = .thin }
        if let split = split as? SPSplitView, split.customDividerColor != colour { split.customDividerColor = colour }
        split.needsDisplay = true
    }

    static let listRadius: CGFloat = 8

    /// A list's scroll view framed by a rounded hairline: its own border off, its corners clipped by its layer, the line
    /// drawn by an `SAClaudeListFrameView` just above it (NSScrollView resets its layer's border to its border type).
    /// Call again whenever the list moves.
    static func frameList(_ scrollView: NSScrollView, hairline: NSColor) {
        if scrollView.borderType != .noBorder { scrollView.borderType = .noBorder }
        scrollView.wantsLayer = true
        if let layer = scrollView.layer {
            if layer.cornerRadius != listRadius { layer.cornerRadius = listRadius }
            if !layer.masksToBounds { layer.masksToBounds = true }
        }
        guard let superview = scrollView.superview else { return }
        let frame = superview.subviews.lazy.compactMap { $0 as? SAClaudeListFrameView }.first { $0.list === scrollView } ?? {
            let frame = SAClaudeListFrameView(frame: scrollView.frame)
            frame.list = scrollView
            superview.addSubview(frame, positioned: .above, relativeTo: scrollView)
            return frame
        }()
        if frame.frame != scrollView.frame { frame.frame = scrollView.frame }
        if frame.autoresizingMask != scrollView.autoresizingMask { frame.autoresizingMask = scrollView.autoresizingMask }
        if frame.isHidden != scrollView.isHidden { frame.isHidden = scrollView.isHidden }
        if frame.colour != hairline { frame.colour = hairline }
    }

    /// Sets `view`'s frame (only when it changes) and drops its autoresizing, as a styler lays it out itself.
    static func place(_ view: NSView?, _ frame: NSRect) {
        guard let view else { return }
        if view.frame != frame { view.frame = frame }
        if !view.autoresizingMask.isEmpty { view.autoresizingMask = [] }
    }
}

/// The rounded hairline around a list (`SAClaudeUtilityChrome.frameList`): drawn over the list's edge, never taking clicks.
@objc(SAClaudeListFrameView) final class SAClaudeListFrameView: NSView {
    weak var list: NSScrollView?
    var colour: NSColor = .separatorColor { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        let radius = SAClaudeUtilityChrome.listRadius
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: radius - 0.5, yRadius: radius - 0.5)
        path.lineWidth = 1
        colour.setStroke()
        path.stroke()
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

// MARK: - Sidebar source list

/// A list in the Claude sidebar look. Adopted lists are of one of the subclasses below (marked by this protocol), which
/// forward to `SAClaudeUtilitySidebar`. Another list class gets its own three-override subclass in `sidebarClass(for:)`.
protocol SAClaudeUtilitySidebarList: NSTableView {}

enum SAClaudeUtilitySidebar {

    static let rowHeight: CGFloat = 28
    static let font = NSFont.systemFont(ofSize: 13)
    /// The selection pill's inset from the list's sides.
    static let pillInset: CGFloat = 6

    /// What an adopted list can't store itself: the glyph for a row (nil: the cell keeps its own image).
    final class State {
        var glyph: ((NSTableView, Int) -> NSImage?)?
    }

    private static var stateKey: UInt8 = 0

    static func state(of table: NSTableView) -> State? {
        objc_getAssociatedObject(table, &stateKey) as? State
    }

    /// Whether `table` has been adopted (the generic sheet skin leaves such a list alone).
    static func isAdopted(_ table: NSTableView) -> Bool { table is SAClaudeUtilitySidebarList }

    /// Gives `table` the sidebar look: its class swapped in place, the plain style with the Claude selection pills, sidebar
    /// fill, 28pt rows, 13pt row text in the sidebar colours, `glyph`'s image for each row, a quiet header. False (nothing
    /// changed) when its class is not one this knows or something observes it by KVO. Idempotent.
    @discardableResult
    static func adopt(_ table: NSTableView, glyph: ((NSTableView, Int) -> NSImage?)? = nil) -> Bool {
        if !isAdopted(table) {
            guard let sidebarClass = sidebarClass(for: table), SAClaudeClassSwap.mayChangeClass(of: table) else { return false }
            object_setClass(table, sidebarClass)
        }
        let state = state(of: table) ?? {
            let state = State()
            objc_setAssociatedObject(table, &stateKey, state, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            return state
        }()
        state.glyph = glyph
        style(table)
        return true
    }

    private static func sidebarClass(for table: NSTableView) -> AnyClass? {
        let cls: AnyClass = type(of: table)
        if cls == SPOutlineView.self { return SAClaudeSidebarSPOutlineView.self }
        return nil
    }

    private static func style(_ table: NSTableView) {
        if table.style != .plain { table.style = .plain }
        // A regular style (not the source list's) so AppKit draws no selection or vibrancy of its own: the pills are drawn
        // in `highlightSelection(inClipRect:)`.
        if table.selectionHighlightStyle != .regular { table.selectionHighlightStyle = .regular }
        table.usesAlternatingRowBackgroundColors = false
        table.gridStyleMask = []
        table.focusRingType = .none
        table.backgroundColor = SAClaudeStyle.sidebarBackground
        if table.rowHeight != rowHeight { table.rowHeight = rowHeight }
        if let scrollView = table.enclosingScrollView {
            scrollView.drawsBackground = true
            scrollView.backgroundColor = SAClaudeStyle.sidebarBackground
        }
        if let header = table.headerView, !(header is SAClaudeSidebarHeaderView) {
            let sidebarHeader = SAClaudeSidebarHeaderView(frame: header.frame)
            sidebarHeader.menu = header.menu
            table.headerView = sidebarHeader
        }
        table.needsDisplay = true
        table.headerView?.needsDisplay = true
    }

    // MARK: Drawing (called by the adopted classes)

    /// The selection as rounded pills, the same colour focused or not (as the main window's tables list).
    static func drawSelection(_ table: NSTableView, in clipRect: NSRect) {
        let rects = SAClaudeSelectionLayout.pillRects(selectedRows: Array(table.selectedRowIndexes), rowRect: { table.rect(ofRow: $0) },
                                                      inset: pillInset)
        SAClaudeStyle.selection.setFill()
        for rect in rects where rect.intersects(clipRect) {
            NSBezierPath(roundedRect: rect, xRadius: SAClaudeStyle.pillRadius, yRadius: SAClaudeStyle.pillRadius).fill()
        }
    }

    /// The row's cell after the table (and its delegate) prepared it: never highlighted (the pill shows the selection), the
    /// row font, primary text when selected, secondary otherwise, muted while the list is disabled; the row's glyph.
    static func prepare(_ cell: NSCell?, table: NSTableView, row: Int) {
        guard let cell = cell as? NSTextFieldCell else { return }
        cell.backgroundStyle = .normal
        cell.isHighlighted = false
        if cell.font != font { cell.font = font }
        cell.drawsBackground = false
        cell.textColor = !table.isEnabled ? SAClaudeStyle.textMuted
            : table.isRowSelected(row) ? SAClaudeStyle.textPrimary : SAClaudeStyle.textSecondary
        if let glyph = state(of: table)?.glyph, let imageCell = cell as? ImageAndTextCell {
            imageCell.setImage(glyph(table, row))
        }
    }

    private static let textHeight = ceil(NSLayoutManager().defaultLineHeight(for: font)) + SAClaudeStyle.cellTextInset

    /// The cell centred on one line of text (cells draw from the top of their frame); editing uses the same frame.
    static func cellFrame(_ frame: NSRect) -> NSRect {
        let height = min(frame.height, textHeight)
        return NSRect(x: frame.minX, y: frame.minY + floor((frame.height - height) / 2), width: max(0, frame.width - pillInset), height: height)
    }
}

/// `SPOutlineView` (the User Manager's accounts, the Bundle Editor's commands) in the sidebar look; installed with
/// `object_setClass`, no stored properties.
@objc(SAClaudeSidebarSPOutlineView) final class SAClaudeSidebarSPOutlineView: SPOutlineView, SAClaudeUtilitySidebarList {
    override func highlightSelection(inClipRect clipRect: NSRect) {
        SAClaudeUtilitySidebar.drawSelection(self, in: clipRect)
    }

    // Cell-based lists only; overriding the deprecated hook is deliberate.
    @available(macOS, deprecated: 10.10)
    override func preparedCell(atColumn column: Int, row: Int) -> NSCell? {
        let cell = super.preparedCell(atColumn: column, row: row)
        SAClaudeUtilitySidebar.prepare(cell, table: self, row: row)
        return cell
    }

    override func frameOfCell(atColumn column: Int, row: Int) -> NSRect {
        SAClaudeUtilitySidebar.cellFrame(super.frameOfCell(atColumn: column, row: row))
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
        headerView?.needsDisplay = true
    }
}

/// A sidebar list's header: the sidebar fill, the column titles muted in the sidebar header style, the sort indicator
/// (when the list shows one) tinted to match. Clicks sort as the native header's do.
@objc(SAClaudeSidebarHeaderView) final class SAClaudeSidebarHeaderView: NSTableHeaderView {
    override func draw(_ dirtyRect: NSRect) {
        let area = bounds.intersection(dirtyRect)
        SAClaudeStyle.sidebarBackground.setFill()
        area.fill()
        guard let table = tableView else { return }
        for (index, column) in table.tableColumns.enumerated() where !column.isHidden {
            var rect = headerRect(ofColumn: index)
            guard rect.intersects(area) else { continue }
            if let indicator = table.indicatorImage(in: column) {
                let size = indicator.size
                let indicatorRect = NSRect(x: rect.maxX - SAClaudeStyle.sidebarTrailingPadding - size.width, y: (rect.midY - size.height / 2).rounded(),
                                           width: size.width, height: size.height)
                let tint = SAClaudeStyle.textMuted
                NSImage(size: size, flipped: false) { r in
                    indicator.draw(in: r)
                    tint.set()
                    r.fill(using: .sourceAtop)
                    return true
                }.draw(in: indicatorRect)
                rect.size.width = max(0, indicatorRect.minX - rect.minX)
            }
            // Level with the rows' text: the row pill's inset plus its padding.
            let title = NSAttributedString(string: column.title, attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: SAClaudeStyle.textMuted,
            ])
            let height = ceil(title.size().height)
            let x = rect.minX + SAClaudeUtilitySidebar.pillInset + 8
            title.draw(with: NSRect(x: x, y: (rect.midY - height / 2).rounded(), width: max(0, rect.maxX - x), height: height),
                       options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

// MARK: - Grid list

/// A plain NSTableView in the Claude grid look (theme background and zebra, hover, the theme selection, a 30pt Claude
/// header, row and column lines, cells centred, live palette), its class swapped in place (no stored properties; the
/// renderer and hooks live in `State`). As `SAClaudeServerVariablesTableView`, without the search.
@objc(SAClaudeUtilityGridTableView) final class SAClaudeUtilityGridTableView: NSTableView {

    private static var stateKey: UInt8 = 0

    final class State {
        let renderer: SAClaudeGridRenderer
        /// Called with each cell after the table and its delegate prepared it (column, row).
        var prepareCell: ((NSCell, Int, Int) -> Void)?
        /// A tint over a row's background (under the selection and the lines).
        var rowTint: ((Int) -> NSColor?)?
        init(renderer: SAClaudeGridRenderer) { self.renderer = renderer }
    }

    var state: State? { objc_getAssociatedObject(self, &Self.stateKey) as? State }

    /// Turns an exact NSTableView into this class and installs the grid; nil when it can't (another class, or observed by KVO).
    static func adopt(_ table: NSTableView) -> SAClaudeUtilityGridTableView? {
        if let adopted = table as? SAClaudeUtilityGridTableView { return adopted }
        guard Swift.type(of: table) == NSTableView.self, SAClaudeClassSwap.mayChangeClass(of: table) else { return nil }
        object_setClass(table, SAClaudeUtilityGridTableView.self)
        guard let adopted = table as? SAClaudeUtilityGridTableView else { return nil }
        let renderer = SAClaudeGridRenderer(table: adopted)
        // Plain NSTextFieldCells draw their text at the top of the frame.
        renderer.cellTextTopOffset = 0
        objc_setAssociatedObject(adopted, &stateKey, State(renderer: renderer), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        adopted.installGrid()
        return adopted
    }

    private func installGrid() {
        guard let renderer = state?.renderer else { return }
        if let header = headerView, Swift.type(of: header) == NSTableHeaderView.self {
            let claudeHeader = SAClaudeTableHeaderView(frame: header.frame)
            claudeHeader.menu = header.menu
            headerView = claudeHeader
        }
        // The plain style: no inset style's padding around the rows (the grid runs to the list's edges).
        if style != .plain { style = .plain }
        // No highlight style: the cells stay plain and the theme selection is drawn under them.
        selectionHighlightStyle = .none
        renderer.install()
        gridStyleMask = super.gridStyleMask
        rowHeight = super.rowHeight
        updateTrackingAreas()
        needsDisplay = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        state?.renderer.applyPalette(force: true)
    }

    override var gridStyleMask: NSTableView.GridLineStyle {
        get { super.gridStyleMask }
        set { super.gridStyleMask = state?.renderer.gridMask(newValue) ?? newValue }
    }

    override var rowHeight: CGFloat {
        get { super.rowHeight }
        set { super.rowHeight = state?.renderer.clampedRowHeight(newValue) ?? newValue }
    }

    /// The cells' text clear of the column lines, level with the Claude header's titles (the plain style has no padding).
    static let cellPadding: CGFloat = 8

    override func frameOfCell(atColumn column: Int, row: Int) -> NSRect {
        let frame = super.frameOfCell(atColumn: column, row: row)
        guard let renderer = state?.renderer else { return frame }
        let centred = renderer.frameOfCell(frame, column: column)
        return NSRect(x: centred.minX + Self.cellPadding, y: centred.minY, width: max(0, centred.width - 2 * Self.cellPadding), height: centred.height)
    }

    override func drawBackground(inClipRect clipRect: NSRect) {
        guard let state else { return super.drawBackground(inClipRect: clipRect) }
        state.renderer.drawBackground(in: clipRect)
        if let rowTint = state.rowTint {
            let visible = rows(in: clipRect)
            if visible.length > 0 {
                for row in visible.location..<NSMaxRange(visible) {
                    guard let tint = rowTint(row) else { continue }
                    tint.setFill()
                    rect(ofRow: row).intersection(clipRect).fill(using: .sourceOver)
                }
            }
        }
        state.renderer.highlightSelection(in: clipRect)
    }

    override func drawGrid(inClipRect clipRect: NSRect) {
        guard let renderer = state?.renderer else { return super.drawGrid(inClipRect: clipRect) }
        renderer.drawGrid(in: clipRect)
    }

    @available(macOS, deprecated: 10.10)
    override func preparedCell(atColumn column: Int, row: Int) -> NSCell? {
        let cell = super.preparedCell(atColumn: column, row: row)
        if let cell, let prepare = state?.prepareCell {
            prepare(cell, column, row)
            cell.isHighlighted = false
        }
        return cell
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        state?.renderer.updateTrackingArea()
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        state?.renderer.mouseMoved(event)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        state?.renderer.mouseExited()
    }

    override func scrollWheel(with event: NSEvent) {
        super.scrollWheel(with: event)
        state?.renderer.scrolled()
    }

    override func reloadData() {
        state?.renderer.rowsReloaded()
        super.reloadData()
    }

    override func noteNumberOfRowsChanged() {
        state?.renderer.rowsReloaded()
        super.noteNumberOfRowsChanged()
    }
}

// MARK: - Tabs

/// An NSTabView whose selection changes are reported to its `SAClaudeTabViewTabs` (every path: the Claude tabs, the
/// controller's own `selectTabViewItemWithIdentifier:`, a refusal by the delegate). Installed with `object_setClass`.
@objc(SAClaudeDrivenTabView) final class SAClaudeDrivenTabView: NSTabView {
    override func selectTabViewItem(_ tabViewItem: NSTabViewItem?) {
        super.selectTabViewItem(tabViewItem)
        SAClaudeTabViewTabs.tabs(for: self)?.selectionChanged()
    }

    override func selectTabViewItem(at index: Int) {
        super.selectTabViewItem(at: index)
        SAClaudeTabViewTabs.tabs(for: self)?.selectionChanged()
    }

    override func selectTabViewItem(withIdentifier identifier: Any) {
        super.selectTabViewItem(withIdentifier: identifier)
        SAClaudeTabViewTabs.tabs(for: self)?.selectionChanged()
    }
}

/// Claude segmented tabs in place of a tab view's own strip: picking a segment selects that tab view item (the tab view's
/// delegate may refuse, as it could a native tab click; the segments then show the tab that stayed), and the segments
/// follow every selection the code makes. Retained by the tab view.
final class SAClaudeTabViewTabs: NSObject {

    private static var associationKey: UInt8 = 0

    let control = SAClaudeConnectionTypeTabs()
    private weak var tabView: NSTabView?
    /// Called after the tab view's selection changed (or a pick was refused).
    var onChange: ((NSTabViewItem?) -> Void)?

    static func tabs(for tabView: NSTabView) -> SAClaudeTabViewTabs? {
        objc_getAssociatedObject(tabView, &associationKey) as? SAClaudeTabViewTabs
    }

    /// Hides `tabView`'s strip and border and gives it Claude tabs (the control is the caller's to add and place); nil when
    /// it is not an exact NSTabView whose class may change. Idempotent.
    static func attach(to tabView: NSTabView, accessibilityLabel: String) -> SAClaudeTabViewTabs? {
        if let existing = tabs(for: tabView) { return existing }
        guard type(of: tabView) == NSTabView.self, SAClaudeClassSwap.mayChangeClass(of: tabView) else { return nil }
        object_setClass(tabView, SAClaudeDrivenTabView.self)
        let tabs = SAClaudeTabViewTabs()
        tabs.tabView = tabView
        objc_setAssociatedObject(tabView, &associationKey, tabs, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        tabView.tabViewType = .noTabsNoBorder
        tabView.drawsBackground = false
        tabs.control.titles = tabView.tabViewItems.map(\.label)
        tabs.control.accessibilityGroupLabel = accessibilityLabel
        // The driven tab view reports the outcome (a refused pick too), which puts the segments back where the tab view is.
        tabs.control.onSelect = { [weak tabs] index in
            guard let tabs, let tabView = tabs.tabView, index < tabView.numberOfTabViewItems else { return }
            tabView.selectTabViewItem(at: index)
        }
        tabs.sync()
        return tabs
    }

    /// The segments show the tab view's selected item.
    func sync() {
        guard let tabView else { return }
        let titles = tabView.tabViewItems.map(\.label)
        if control.titles != titles { control.titles = titles }
        guard let selected = tabView.selectedTabViewItem else { return }
        let index = tabView.indexOfTabViewItem(selected)
        if index != NSNotFound, control.selectedIndex != index { control.selectedIndex = index }
    }

    fileprivate func selectionChanged() {
        sync()
        onChange?(tabView?.selectedTabViewItem)
    }

    func recolour(_ colours: SAClaudeSheetColours) {
        control.colours = SAClaudeConnectionTypeTabs.Colours(selectedFill: colours.fieldFill, selectedStroke: colours.palette.hairline,
                                                             hoverFill: colours.palette.hover, text: colours.theme.text, mutedText: colours.muted)
    }
}
