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

    /// The frame width a bar pull-down needs to draw its whole glyph and its chevron: its own measure once styled (35pt
    /// for the 16pt gear, as the main window's sidebar gear in DBView.xib), never under the bar's 28pt square. In a 28pt
    /// square the pull-down's arrow area clips the glyph to its left half.
    static func pullDownWidth(_ popUp: NSPopUpButton) -> CGFloat {
        let measured = popUp.intrinsicContentSize.width
        return max(SAClaudeSidebarBarLayout.buttonSize, ceil(measured > 0 ? measured : popUp.cell?.cellSize.width ?? 0))
    }

    /// A bar button's frame width: a pull-down's own (`pullDownWidth`), else the 28pt square.
    static func barWidth(_ button: NSButton) -> CGFloat {
        if let popUp = button as? NSPopUpButton, popUp.pullsDown { return pullDownWidth(popUp) }
        return SAClaudeSidebarBarLayout.buttonSize
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

    /// `frameList` now and again once the list is on screen (its layer exists only then): for a sheet styled as it begins.
    static func frameListOnceShown(_ scrollView: NSScrollView) {
        frameList(scrollView, hairline: SAClaudeSheetColours.current().palette.hairline)
        DispatchQueue.main.async { [weak scrollView] in
            if let scrollView { frameList(scrollView, hairline: SAClaudeSheetColours.current().palette.hairline) }
        }
    }

    /// Sets `view`'s frame (only when it changes) and drops its autoresizing, as a styler lays it out itself.
    static func place(_ view: NSView?, _ frame: NSRect) {
        guard let view else { return }
        if view.frame != frame { view.frame = frame }
        if !view.autoresizingMask.isEmpty { view.autoresizingMask = [] }
    }

    /// Sets `view`'s frame (only when it changes) and its autoresizing, for a view placed once that then follows its
    /// superview as the XIB's views do.
    static func pin(_ view: NSView?, _ frame: NSRect, _ mask: NSView.AutoresizingMask) {
        guard let view else { return }
        if view.frame != frame { view.frame = frame }
        if view.autoresizingMask != mask { view.autoresizingMask = mask }
    }

    // MARK: Baselines

    private static let baselineLayout = NSLayoutManager()

    /// How far below `view`'s top its text's baseline sits: a text field's (a label's, a Claude sheet field's) line drawn
    /// from the top of its cell's drawing rect; a Claude pill pop-up's title centred on its pill; anything else a line of
    /// `fallbackFont` centred on it.
    static func baselineFromTop(of view: NSView, fallbackFont: NSFont) -> CGFloat {
        let bounds = view.bounds
        func fromTop(_ rect: NSRect) -> CGFloat { view.isFlipped ? rect.minY - bounds.minY : bounds.maxY - rect.maxY }
        if let field = view as? NSTextField, let cell = field.cell, let font = field.font {
            return fromTop(cell.drawingRect(forBounds: bounds)) + baselineLayout.defaultBaselineOffset(for: font)
        }
        let font = view is NSPopUpButton && (view as? NSPopUpButton)?.cell is SAClaudePillPopUpButtonCell ? FilterCellDrawing.font : fallbackFont
        let pill = view is NSPopUpButton ? SAClaudeFilterChrome.controlFrame(in: bounds) : bounds
        let height = ceil(NSAttributedString(string: "Xg", attributes: [.font: font]).size().height)
        let line = NSRect(x: pill.minX, y: (pill.midY - height / 2).rounded(), width: pill.width, height: height)
        return fromTop(line) + baselineLayout.defaultBaselineOffset(for: font)
    }

    /// Moves `label` up or down (only) so its text sits on `control`'s text baseline. Both in one superview.
    static func alignBaseline(of label: NSTextField, to control: NSView) {
        guard let container = control.superview, label.superview === container, let labelFont = label.font else { return }
        let controlBaseline = baselineFromTop(of: control, fallbackFont: labelFont)
        let labelBaseline = baselineFromTop(of: label, fallbackFont: labelFont)
        var frame = label.frame
        if container.isFlipped {
            frame.origin.y = ((control.frame.minY + controlBaseline - labelBaseline) * 2).rounded() / 2
        } else {
            frame.origin.y = SAClaudeFormBaseline.labelY(baselineY: control.frame.maxY - controlBaseline, labelHeight: frame.height,
                                                         labelBaselineFromTop: labelBaseline)
        }
        if label.frame != frame { label.frame = frame }
    }

    // MARK: Footer buttons

    static let buttonFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)

    /// A sheet's push button at the regular size (13pt), as the User Manager's Apply and Cancel.
    static func makeRegular(_ button: NSButton) {
        if button.controlSize != .regular { button.controlSize = .regular }
        if button.font != buttonFont { button.font = buttonFont }
    }

    /// The frame width a push button needs: its widest title (`titles` and its own) at the Claude cells' medium weight, the
    /// pill's padding and the classic margins either side; at least 84pt.
    static func pushButtonWidth(_ button: NSButton, titles: [String] = []) -> CGFloat {
        let medium = NSFont.systemFont(ofSize: (button.font ?? buttonFont).pointSize, weight: .medium)
        let title = (titles + [button.title]).map { ceil(($0 as NSString).size(withAttributes: [.font: medium]).width) }.max() ?? 0
        let inset = SAClaudeSheetButtonGeometry.metrics(for: button.controlSize).classicSideMargin
        return max(84, title + 2 * SAClaudeFilterChrome.pillPadding + 2 * inset + 8)
    }

    /// Lays `buttons` (the rightmost first: Save, then Cancel) along the bottom of `container`, regular size, right-aligned
    /// on the margin, pinned to the bottom right. Returns their frames.
    @discardableResult
    static func layoutFooter(_ buttons: [NSButton], in container: NSView) -> [NSRect] {
        buttons.forEach(makeRegular)
        let inset = SAClaudeSheetButtonGeometry.metrics(for: .regular).classicSideMargin
        let bounds = container.bounds
        let frames = SAClaudeFooterLayout.trailing(widths: buttons.map { pushButtonWidth($0) }, maxX: bounds.maxX,
                                                   y: bounds.minY + SAClaudeFooterLayout.bottom, buttonInset: inset)
        for (button, frame) in zip(buttons, frames) { pin(button, frame, [.minXMargin, .maxYMargin]) }
        return frames
    }

    // MARK: Sidebar panes

    /// A source list's pane in the main sidebar's recipe: the sidebar fill under everything, a 32pt bottom bar with a
    /// hairline above it, its buttons (`bar`: add, remove, the gear…) as bar glyph buttons from the pill inset, the drag
    /// handle muted, the split divider a hairline. Bar buttons keep to the bottom left as the pane resizes.
    static func styleSidebarPane(_ pane: NSView, list: NSScrollView, bar: [(button: NSButton, glyph: SAClaudeGlyph, label: String)], split: NSSplitView) {
        guard let first = bar.first?.button else { return }
        SAClaudeSidebarChrome.addSidebarBackground(to: pane)
        SAClaudeSidebarChrome.addBarDivider(to: pane, above: first)
        SAClaudeSidebarChrome.setBarHeight(in: pane, below: list)
        for item in bar {
            if let popUp = item.button as? NSPopUpButton, item.glyph == .actions {
                styleGearButton(popUp, label: item.label)
            } else {
                styleBarButton(item.button, glyph: item.glyph, label: item.label)
            }
        }
        let frames = SAClaudeSidebarBarLayout.buttons(widths: bar.map { barWidth($0.button) }, x: SAClaudeUtilitySidebar.pillInset,
                                                      midY: pane.bounds.minY + SAClaudeSidebarChrome.barHeight / 2)
        for (item, frame) in zip(bar, frames) { pin(item.button, frame, [.maxXMargin, .maxYMargin]) }
        // SPSplitView's drag handle (an outlet ivar, read by KVC).
        if let handle: NSImageView = SAClaudeFormRecipes.outlet(split, "additionalDragHandleView"), handle.superview === pane {
            handle.contentTintColor = SAClaudeStyle.textMuted
        }
        styleSplitDivider(split)
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
/// forward to `SAClaudeUtilitySidebar`. Another list class gets its own five-override subclass in `sidebarClass(for:)`.
protocol SAClaudeUtilitySidebarList: NSTableView {}

enum SAClaudeUtilitySidebar {

    static let rowHeight: CGFloat = 28
    static let font = NSFont.systemFont(ofSize: 13)
    /// A detail column's text.
    static let detailFont = NSFont.systemFont(ofSize: 11)
    /// The selection pill's inset from the list's sides.
    static let pillInset: CGFloat = 6
    /// Rows the code makes shorter than this are spacers (the Navigator's), kept as the code made them.
    static let spacerHeight: CGFloat = 10
    /// A caption header row: its height, its text (the list header's caption style), the text's distance from the row's
    /// bottom (as the main sidebar's section headers sit on their row's bottom, scaled to the caption).
    static let captionRowHeight: CGFloat = 26
    static let captionFont = NSFont.systemFont(ofSize: 11, weight: .medium)
    static let captionBottomPadding: CGFloat = 5

    /// How one adopted list looks, and what it can't store itself.
    final class State {
        var rowHeight = SAClaudeUtilitySidebar.rowHeight
        var font = SAClaudeUtilitySidebar.font
        /// The glyph for a row, given the image its cell has now; unset, the cell keeps its own image.
        var glyph: ((NSTableView, Int, NSImage?) -> NSImage?)?
        /// Top-level group rows (the delegate's `isGroupRow` / `isGroupItem`) drawn as the main sidebar's section headers
        /// ("Tables and views": muted, aligned with the rows' glyphs, on the row's bottom) instead of AppKit's group style.
        var groupRowsAsHeaders = false
        /// Columns (by identifier) of secondary detail (a tab trigger, a column type): muted, 11pt.
        var detailColumns: Set<String> = []
        /// The text a row shows instead of its cell's (nil: the cell's own, in the row colours).
        var attributedText: ((NSTableView, Int, NSTextFieldCell) -> NSAttributedString?)?
        /// The title a section header row shows, given its data source title (nil: that title).
        var headerTitle: ((NSTableView, Int, String) -> String)?
        /// How far an outline list's rows (chevrons and cells) sit right of where AppKit puts them, so its first chevrons
        /// start inside the selection pill (`SAClaudeSidebarListLayout.chevronShift`); set as the list is styled.
        var chevronShift: CGFloat = 0
        /// Section header rows drawn as captions (the managers' "Global" and file rows, which can't be selected): 11pt
        /// medium muted text on a shorter row (`captionRowHeight`), so they don't read as rows to click.
        var headerRowsAsCaptions = false
        /// `contentLeading` as last measured, for that many rows; dropped on a reload (`invalidateContentLeading`).
        var contentLeadingCache: (rows: Int, value: CGFloat?)?
    }

    private static var stateKey: UInt8 = 0

    static func state(of table: NSTableView) -> State? {
        objc_getAssociatedObject(table, &stateKey) as? State
    }

    /// Whether `table` has been adopted (the generic sheet skin leaves such a list alone).
    static func isAdopted(_ table: NSTableView) -> Bool { table is SAClaudeUtilitySidebarList }

    /// Gives `table` the sidebar look: its class swapped in place, the plain style with the Claude selection pills, sidebar
    /// fill, the state's rows (28pt, 13pt text in the sidebar colours by default; `configure` changes them), a quiet
    /// header. False (nothing changed) when its class is not one this knows or something observes it by KVO. Idempotent.
    @discardableResult
    static func adopt(_ table: NSTableView, configure: (State) -> Void = { _ in }) -> Bool {
        if !isAdopted(table) {
            guard let sidebarClass = sidebarClass(for: table), SAClaudeClassSwap.mayChangeClass(of: table) else { return false }
            object_setClass(table, sidebarClass)
        }
        let state = state(of: table) ?? {
            let state = State()
            objc_setAssociatedObject(table, &stateKey, state, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            return state
        }()
        configure(state)
        style(table, state)
        return true
    }

    private static func sidebarClass(for table: NSTableView) -> AnyClass? {
        let cls: AnyClass = type(of: table)
        if cls == SPOutlineView.self { return SAClaudeSidebarSPOutlineView.self }
        if cls == SPNavigatorOutlineView.self { return SAClaudeSidebarNavigatorOutlineView.self }
        if cls == SPTableView.self { return SAClaudeSidebarSPTableView.self }
        if cls == NSTableView.self { return SAClaudeSidebarTableView.self }
        return nil
    }

    private static func style(_ table: NSTableView, _ state: State) {
        if table.style != .plain { table.style = .plain }
        // A regular style (not the source list's) so AppKit draws no selection or vibrancy of its own: the pills are drawn
        // in `highlightSelection(inClipRect:)`.
        if table.selectionHighlightStyle != .regular { table.selectionHighlightStyle = .regular }
        table.usesAlternatingRowBackgroundColors = false
        table.gridStyleMask = []
        table.focusRingType = .none
        table.backgroundColor = SAClaudeStyle.sidebarBackground
        // Group rows stay in the list (AppKit would float them over the rows as they scroll).
        if table.floatsGroupRows { table.floatsGroupRows = false }
        if table.rowHeight != state.rowHeight { table.rowHeight = state.rowHeight }
        // Rows meet (the pills carry the spacing), so a row is exactly the state's height.
        if table.intercellSpacing.height != 0 { table.intercellSpacing.height = 0 }
        // The first chevrons inside the selection pill: a top-level row's, or (under section header rows) the next level's.
        if let outline = table as? NSOutlineView {
            state.chevronShift = SAClaudeSidebarListLayout.chevronShift(chevronLevel: state.groupRowsAsHeaders ? 1 : 0,
                                                                        indentation: outline.indentationPerLevel, pillInset: pillInset)
        }
        state.contentLeadingCache = nil
        // Heights a delegate gives (`SAClaudeUtilitySidebarMetrics`) are asked for again.
        if table.numberOfRows > 0 { table.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0..<table.numberOfRows)) }
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

    /// Whether `row` is a group row by the list's delegate (`tableView:isGroupRow:`, `outlineView:isGroupItem:`).
    static func isGroupRow(_ table: NSTableView, _ row: Int) -> Bool {
        if let outline = table as? NSOutlineView {
            guard let delegate = outline.delegate, delegate.responds(to: #selector(NSOutlineViewDelegate.outlineView(_:isGroupItem:))),
                  let item = outline.item(atRow: row) else { return false }
            return delegate.outlineView?(outline, isGroupItem: item) ?? false
        }
        guard let delegate = table.delegate, delegate.responds(to: #selector(NSTableViewDelegate.tableView(_:isGroupRow:))) else { return false }
        return delegate.tableView?(table, isGroupRow: row) ?? false
    }

    /// A row drawn as a section header: a top-level group row of a list whose state asks for headers.
    static func isHeaderRow(_ table: NSTableView, _ row: Int) -> Bool {
        guard state(of: table)?.groupRowsAsHeaders == true else { return false }
        if let outline = table as? NSOutlineView, outline.level(forRow: row) > 0 { return false }
        return isGroupRow(table, row)
    }

    // MARK: Drawing (called by the adopted classes)

    /// Draws `row` as a section header when it is one (its first column's value, from the data source, in the main
    /// sidebar's header style); false for any other row, which the list draws itself.
    static func drawHeaderRow(_ table: NSTableView, _ row: Int) -> Bool {
        guard isHeaderRow(table, row), let column = table.tableColumns.first else { return false }
        let value: Any?
        if let outline = table as? NSOutlineView {
            value = outline.dataSource?.outlineView?(outline, objectValueFor: column, byItem: outline.item(atRow: row))
        } else {
            value = table.dataSource?.tableView?(table, objectValueFor: column, row: row)
        }
        var title = (value as? String) ?? (value as? NSAttributedString)?.string ?? ""
        if let headerTitle = state(of: table)?.headerTitle { title = headerTitle(table, row, title) }
        let rowRect = table.rect(ofRow: row)
        // Level with the rows' content (their chevrons, glyphs or text), as the list's own header.
        let x = contentLeading(table) ?? rowRect.minX + pillInset + SAClaudeStyle.rowContentPadding
        if state(of: table)?.headerRowsAsCaptions == true {
            SAClaudeSidebarChrome.drawHeader(title, inRowRect: rowRect, x: x, font: captionFont, bottomPadding: captionBottomPadding)
        } else {
            SAClaudeSidebarChrome.drawHeader(title, inRowRect: rowRect, x: x)
        }
        return true
    }

    /// The row content's leading edge (list coordinates): where the first row that is not a header or a spacer starts its
    /// content — the chevrons' glyph when that row's level shows disclosure chevrons, else its cell's image (a glyph) or
    /// text, after any indentation the controller gives the cell. The list's header and its section header rows start
    /// their text here. Nil for an empty list.
    static func contentLeading(_ table: NSTableView) -> CGFloat? {
        let state = state(of: table)
        if let cached = state?.contentLeadingCache, cached.rows == table.numberOfRows { return cached.value }
        let value = measureContentLeading(table)
        state?.contentLeadingCache = (table.numberOfRows, value)
        return value
    }

    /// Forgets the measured content edge (the rows were reloaded) and redraws the header that starts there.
    static func invalidateContentLeading(_ table: NSTableView) {
        guard let state = state(of: table), state.contentLeadingCache != nil else { return }
        state.contentLeadingCache = nil
        table.headerView?.needsDisplay = true
    }

    private static func measureContentLeading(_ table: NSTableView) -> CGFloat? {
        guard let column = table.tableColumns.first else { return nil }
        let limit = min(table.numberOfRows, 200)
        guard let row = (0..<limit).first(where: { !isHeaderRow(table, $0) && table.rect(ofRow: $0).height >= spacerHeight }) else { return nil }
        if let outline = table as? NSOutlineView, outline.outlineTableColumn === column {
            let level = outline.level(forRow: row)
            if let expandable = (0..<limit).first(where: { outline.level(forRow: $0) == level && outline.isExpandable(outline.item(atRow: $0)) }) {
                let chevron = outline.frameOfOutlineCell(atRow: expandable)
                if !chevron.isEmpty { return chevron.minX + SAClaudeSidebarListLayout.chevronInkInset }
            }
        }
        // The column's cell as the delegate prepares it for that row (its indentation, its image).
        let cell = column.dataCell(forRow: row) as? NSCell
        if let cell {
            if let outline = table as? NSOutlineView {
                outline.delegate?.outlineView?(outline, willDisplayCell: cell, for: column, item: outline.item(atRow: row) as Any)
            } else {
                table.delegate?.tableView?(table, willDisplayCell: cell, for: column, row: row)
            }
        }
        let imageCell = cell as? ImageAndTextCell
        var hasImage = imageCell?.image() != nil
        if let glyph = state(of: table)?.glyph, let imageCell { hasImage = glyph(table, row, imageCell.image()) != nil }
        return SAClaudeSidebarListLayout.cellContentLeading(frame: table.frameOfCell(atColumn: 0, row: row),
                                                            indentationLevel: imageCell?.indentationLevel() ?? 0,
                                                            indentationStep: imageAndTextIndent, hasImage: hasImage,
                                                            imageInset: SAClaudeStyle.cellImageInset, textInset: SAClaudeStyle.cellTextInset)
    }

    /// `ImageAndTextCell`'s indentation per level (INDENT_AMOUNT, keep in sync with ImageAndTextCell.h).
    private static let imageAndTextIndent: CGFloat = 17

    /// The selection as rounded pills, the same colour focused or not (as the main window's tables list).
    static func drawSelection(_ table: NSTableView, in clipRect: NSRect) {
        // Rows of a list wider than its scroll view (a column wider than the list) end out of sight: the pill keeps its
        // inset from the visible edge.
        let visible = table.visibleRect
        let rects = SAClaudeSelectionLayout.pillRects(selectedRows: Array(table.selectedRowIndexes), rowRect: { row in
            var rect = table.rect(ofRow: row)
            let minX = max(rect.minX, visible.minX), maxX = min(rect.maxX, visible.maxX)
            if maxX > minX { rect.origin.x = minX; rect.size.width = maxX - minX }
            return rect
        }, inset: pillInset)
        SAClaudeStyle.selection.setFill()
        for rect in rects where rect.intersects(clipRect) {
            NSBezierPath(roundedRect: rect, xRadius: SAClaudeStyle.pillRadius, yRadius: SAClaudeStyle.pillRadius).fill()
        }
    }

    /// The row's cell after the table (and its delegate) prepared it: never highlighted (the pill shows the selection), the
    /// row font, primary text when selected, secondary otherwise, muted while the list is disabled (and for headers and
    /// detail columns); the row's glyph.
    static func prepare(_ cell: NSCell?, table: NSTableView, column: Int, row: Int) {
        guard let cell = cell as? NSTextFieldCell else { return }
        let state = state(of: table)
        cell.backgroundStyle = .normal
        cell.isHighlighted = false
        cell.drawsBackground = false
        let identifier = column >= 0 && column < table.numberOfColumns ? table.tableColumns[column].identifier.rawValue : ""
        let isHeader = isHeaderRow(table, row)
        let isDetail = state?.detailColumns.contains(identifier) == true
        let font = isHeader ? SAClaudeStyle.headerFont : isDetail ? detailFont : (state?.font ?? font)
        if cell.font != font { cell.font = font }
        cell.textColor = !table.isEnabled || isHeader || isDetail ? SAClaudeStyle.textMuted
            : table.isRowSelected(row) ? SAClaudeStyle.textPrimary : SAClaudeStyle.textSecondary
        if let attributed = state?.attributedText?(table, row, cell) { cell.attributedStringValue = attributed }
        if let glyph = state?.glyph, let imageCell = cell as? ImageAndTextCell {
            imageCell.setImage(glyph(table, row, imageCell.image()))
        }
    }

    private static var textHeights: [CGFloat: CGFloat] = [:]

    /// The cell centred on one line of text in `table`'s font (cells draw from the top of their frame), the outline
    /// column's moved right with its chevrons (`State.chevronShift`); editing uses the same frame.
    static func cellFrame(_ frame: NSRect, table: NSTableView, column: Int) -> NSRect {
        let state = state(of: table)
        let size = state?.font.pointSize ?? font.pointSize
        let textHeight = textHeights[size] ?? {
            let height = ceil(NSLayoutManager().defaultLineHeight(for: .systemFont(ofSize: size))) + SAClaudeStyle.cellTextInset
            textHeights[size] = height
            return height
        }()
        let height = min(frame.height, textHeight)
        var shift: CGFloat = 0
        if let state, state.chevronShift > 0, let outline = table as? NSOutlineView, column >= 0, column < outline.numberOfColumns,
           outline.tableColumns[column] === outline.outlineTableColumn {
            shift = state.chevronShift
        }
        return NSRect(x: frame.minX + shift, y: frame.minY + floor((frame.height - height) / 2),
                      width: max(0, frame.width - pillInset - shift), height: height)
    }

    /// A disclosure chevron's frame, moved right with the rows (`State.chevronShift`).
    static func outlineCellFrame(_ frame: NSRect, table: NSTableView) -> NSRect {
        guard !frame.isEmpty, let shift = state(of: table)?.chevronShift, shift > 0 else { return frame }
        return frame.offsetBy(dx: shift, dy: 0)
    }
}

/// The row heights the sheets' delegates give their lists (thin hooks in the controllers' `heightOfRow` methods): an
/// adopted sidebar's own height for a row, else what the controller proposed.
@objc(SAClaudeUtilitySidebarMetrics) final class SAClaudeUtilitySidebarMetrics: NSObject {
    /// `proposed` for a list in its own look or a spacer row (shorter than `spacerHeight`); the sidebar's row height for
    /// an adopted list.
    @objc(rowHeightForTable:proposed:) static func rowHeight(for table: NSTableView?, proposed: CGFloat) -> CGFloat {
        guard let table, proposed >= SAClaudeUtilitySidebar.spacerHeight,
              let state = SAClaudeUtilitySidebar.state(of: table), SAClaudeUtilitySidebar.isAdopted(table) else { return proposed }
        return state.rowHeight
    }

    /// `rowHeight(for:proposed:)` for a given row: a section header row of a list that draws them as captions gets the
    /// caption's shorter height.
    @objc(rowHeightForTable:row:proposed:) static func rowHeight(for table: NSTableView?, row: Int, proposed: CGFloat) -> CGFloat {
        let height = rowHeight(for: table, proposed: proposed)
        guard let table, height != proposed, SAClaudeUtilitySidebar.state(of: table)?.headerRowsAsCaptions == true,
              row >= 0, row < table.numberOfRows, SAClaudeUtilitySidebar.isHeaderRow(table, row) else { return height }
        return SAClaudeUtilitySidebar.captionRowHeight
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
        SAClaudeUtilitySidebar.prepare(cell, table: self, column: column, row: row)
        return cell
    }

    override func drawRow(_ row: Int, clipRect: NSRect) {
        if !SAClaudeUtilitySidebar.drawHeaderRow(self, row) { super.drawRow(row, clipRect: clipRect) }
    }

    override func frameOfCell(atColumn column: Int, row: Int) -> NSRect {
        SAClaudeUtilitySidebar.cellFrame(super.frameOfCell(atColumn: column, row: row), table: self, column: column)
    }

    override func frameOfOutlineCell(atRow row: Int) -> NSRect {
        SAClaudeUtilitySidebar.outlineCellFrame(super.frameOfOutlineCell(atRow: row), table: self)
    }

    override func reloadData() {
        super.reloadData()
        SAClaudeUtilitySidebar.invalidateContentLeading(self)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
        headerView?.needsDisplay = true
    }
}

/// The Navigator's `SPNavigatorOutlineView` in the sidebar look (as `SAClaudeSidebarSPOutlineView`).
@objc(SAClaudeSidebarNavigatorOutlineView) final class SAClaudeSidebarNavigatorOutlineView: SPNavigatorOutlineView, SAClaudeUtilitySidebarList {
    override func highlightSelection(inClipRect clipRect: NSRect) {
        SAClaudeUtilitySidebar.drawSelection(self, in: clipRect)
    }

    @available(macOS, deprecated: 10.10)
    override func preparedCell(atColumn column: Int, row: Int) -> NSCell? {
        let cell = super.preparedCell(atColumn: column, row: row)
        SAClaudeUtilitySidebar.prepare(cell, table: self, column: column, row: row)
        return cell
    }

    override func drawRow(_ row: Int, clipRect: NSRect) {
        if !SAClaudeUtilitySidebar.drawHeaderRow(self, row) { super.drawRow(row, clipRect: clipRect) }
    }

    override func frameOfCell(atColumn column: Int, row: Int) -> NSRect {
        SAClaudeUtilitySidebar.cellFrame(super.frameOfCell(atColumn: column, row: row), table: self, column: column)
    }

    override func frameOfOutlineCell(atRow row: Int) -> NSRect {
        SAClaudeUtilitySidebar.outlineCellFrame(super.frameOfOutlineCell(atRow: row), table: self)
    }

    override func reloadData() {
        super.reloadData()
        SAClaudeUtilitySidebar.invalidateContentLeading(self)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
        headerView?.needsDisplay = true
    }
}

/// An `SPTableView` source list (the Query Favorites and Content Filter managers') in the sidebar look.
@objc(SAClaudeSidebarSPTableView) final class SAClaudeSidebarSPTableView: SPTableView, SAClaudeUtilitySidebarList {
    override func highlightSelection(inClipRect clipRect: NSRect) {
        SAClaudeUtilitySidebar.drawSelection(self, in: clipRect)
    }

    @available(macOS, deprecated: 10.10)
    override func preparedCell(atColumn column: Int, row: Int) -> NSCell? {
        let cell = super.preparedCell(atColumn: column, row: row)
        SAClaudeUtilitySidebar.prepare(cell, table: self, column: column, row: row)
        return cell
    }

    override func drawRow(_ row: Int, clipRect: NSRect) {
        if !SAClaudeUtilitySidebar.drawHeaderRow(self, row) { super.drawRow(row, clipRect: clipRect) }
    }

    override func frameOfCell(atColumn column: Int, row: Int) -> NSRect {
        SAClaudeUtilitySidebar.cellFrame(super.frameOfCell(atColumn: column, row: row), table: self, column: column)
    }

    override func reloadData() {
        super.reloadData()
        SAClaudeUtilitySidebar.invalidateContentLeading(self)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
        headerView?.needsDisplay = true
    }
}

/// A plain NSTableView list in the sidebar look (the Navigator's information list).
@objc(SAClaudeSidebarTableView) final class SAClaudeSidebarTableView: NSTableView, SAClaudeUtilitySidebarList {
    override func highlightSelection(inClipRect clipRect: NSRect) {
        SAClaudeUtilitySidebar.drawSelection(self, in: clipRect)
    }

    @available(macOS, deprecated: 10.10)
    override func preparedCell(atColumn column: Int, row: Int) -> NSCell? {
        let cell = super.preparedCell(atColumn: column, row: row)
        SAClaudeUtilitySidebar.prepare(cell, table: self, column: column, row: row)
        return cell
    }

    override func drawRow(_ row: Int, clipRect: NSRect) {
        if !SAClaudeUtilitySidebar.drawHeaderRow(self, row) { super.drawRow(row, clipRect: clipRect) }
    }

    override func frameOfCell(atColumn column: Int, row: Int) -> NSRect {
        SAClaudeUtilitySidebar.cellFrame(super.frameOfCell(atColumn: column, row: row), table: self, column: column)
    }

    override func reloadData() {
        super.reloadData()
        SAClaudeUtilitySidebar.invalidateContentLeading(self)
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
            guard !column.title.isEmpty else { continue }
            let title = NSAttributedString(string: column.title, attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: SAClaudeStyle.textMuted,
            ])
            let height = ceil(title.size().height)
            // The first column's title level with the rows' content (chevrons, glyphs or text); another column's with its
            // text (the row pill's inset plus its padding).
            let rowContent = index == 0 ? SAClaudeUtilitySidebar.contentLeading(table) : nil
            let x = rowContent ?? rect.minX + SAClaudeUtilitySidebar.pillInset + 8
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

/// A list in the Claude grid look (theme background and zebra, hover, the theme selection, a 30pt Claude header, row and
/// column lines, cells centred, live palette), its class swapped in place to one of the grid classes below (no stored
/// properties; the renderer and hooks live in `State`). Every grid class forwards to this one implementation: a plain
/// NSTableView becomes `SAClaudeUtilityGridTableView` (the Server Variables list is a subclass of it that adds nothing but
/// its type), an `SPCopyTable` (the Advanced Filter panel's) `SAClaudeUtilityGridCopyTable`. What a window needs beyond
/// the grid goes through the hooks (its cells' text, reload notices, a mark drawn over a row).
protocol SAClaudeUtilityGridList: NSTableView {}

enum SAClaudeUtilityGrid {

    private static var stateKey: UInt8 = 0

    final class State {
        let renderer: SAClaudeGridRenderer
        /// Called with each cell after the table and its delegate prepared it (column, row); the cell is then never
        /// drawn highlighted (the theme selection is drawn under it).
        var prepareCell: ((NSCell, Int, Int) -> Void)?
        /// Called after a row is drawn (cells included), with its rect, to draw a mark over it.
        var drawOverRow: ((Int, NSRect) -> Void)?
        var willReload: () -> Void = {}
        var didReload: () -> Void = {}
        /// Horizontal room between a cell's text and the column lines (0: the table's own).
        var cellPadding: CGFloat = 0
        init(renderer: SAClaudeGridRenderer) { self.renderer = renderer }
    }

    static func state(of table: NSTableView) -> State? {
        objc_getAssociatedObject(table, &stateKey) as? State
    }

    /// Turns `table` (exactly of class `from`) into `gridClass` and installs the grid; the table unchanged when it is
    /// already of `gridClass`. Nil when it can't (another class, or observed by KVO, `SAClaudeClassSwap`).
    /// `cellTextTopOffset`: where the columns' cells draw their text (0 for plain NSTextFieldCells, 2 for SPTextAndLinkCell).
    static func adopt<T: NSTableView>(_ table: NSTableView, from: NSTableView.Type, as gridClass: T.Type, cellTextTopOffset: CGFloat) -> T? {
        if let adopted = table as? SAClaudeUtilityGridList { return type(of: adopted) == gridClass ? adopted as? T : nil }
        guard type(of: table) == from, SAClaudeClassSwap.mayChangeClass(of: table) else { return nil }
        object_setClass(table, gridClass)
        guard let adopted = table as? T else { return nil }
        let renderer = SAClaudeGridRenderer(table: adopted)
        renderer.cellTextTopOffset = cellTextTopOffset
        objc_setAssociatedObject(adopted, &stateKey, State(renderer: renderer), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        install(on: adopted)
        return adopted
    }

    private static func install(on table: NSTableView) {
        guard let renderer = state(of: table)?.renderer else { return }
        // The Claude header (its palette is the renderer's) before the renderer sizes it to 30pt.
        if let header = table.headerView, type(of: header) == NSTableHeaderView.self {
            let claudeHeader = SAClaudeTableHeaderView(frame: header.frame)
            claudeHeader.menu = header.menu
            table.headerView = claudeHeader
        }
        // Cell-based tables mark the selected row's cells highlighted, which draws a system selection box over the
        // theme selection; with no highlight style the cells stay plain and the selection is drawn below (as the
        // Query Console does).
        table.selectionHighlightStyle = .none
        renderer.install()
        // The table's own values set before the swap: run them through the clamps now.
        table.gridStyleMask = table.gridStyleMask
        table.rowHeight = table.rowHeight
        table.updateTrackingAreas()
        table.needsDisplay = true
    }

    // MARK: Forwarding (called by the grid classes' overrides)

    static func gridMask(_ table: NSTableView, _ proposed: NSTableView.GridLineStyle) -> NSTableView.GridLineStyle {
        state(of: table)?.renderer.gridMask(proposed) ?? proposed
    }

    static func rowHeight(_ table: NSTableView, _ proposed: CGFloat) -> CGFloat {
        state(of: table)?.renderer.clampedRowHeight(proposed) ?? proposed
    }

    static func frameOfCell(_ table: NSTableView, _ frame: NSRect, column: Int) -> NSRect {
        guard let state = state(of: table) else { return frame }
        let centred = state.renderer.frameOfCell(frame, column: column)
        guard state.cellPadding > 0 else { return centred }
        return NSRect(x: centred.minX + state.cellPadding, y: centred.minY, width: max(0, centred.width - 2 * state.cellPadding), height: centred.height)
    }

    /// No highlight style means AppKit skips highlightSelection(inClipRect:); hover and selection are filled here
    /// instead, at the same point (after the background, before the lines and cells). False: not a grid yet.
    static func drawBackground(_ table: NSTableView, in clipRect: NSRect) -> Bool {
        guard let renderer = state(of: table)?.renderer else { return false }
        renderer.drawBackground(in: clipRect)
        renderer.highlightSelection(in: clipRect)
        return true
    }

    static func drawGrid(_ table: NSTableView, in clipRect: NSRect) -> Bool {
        guard let renderer = state(of: table)?.renderer else { return false }
        renderer.drawGrid(in: clipRect)
        return true
    }

    static func didDrawRow(_ table: NSTableView, _ row: Int, clipRect: NSRect) {
        state(of: table)?.drawOverRow?(row, table.rect(ofRow: row).intersection(clipRect))
    }

    static func prepared(_ cell: NSCell?, column: Int, row: Int, in table: NSTableView) {
        guard let cell, let prepare = state(of: table)?.prepareCell else { return }
        prepare(cell, column, row)
        cell.isHighlighted = false
    }

    static func appearanceChanged(_ table: NSTableView) { state(of: table)?.renderer.applyPalette(force: true) }
    static func updateTrackingArea(_ table: NSTableView) { state(of: table)?.renderer.updateTrackingArea() }
    static func mouseMoved(_ table: NSTableView, _ event: NSEvent) { state(of: table)?.renderer.mouseMoved(event) }
    static func mouseExited(_ table: NSTableView) { state(of: table)?.renderer.mouseExited() }
    static func scrolled(_ table: NSTableView) { state(of: table)?.renderer.scrolled() }

    /// Around a reload (`super.reloadData()` in between).
    static func reload(_ table: NSTableView, _ reload: () -> Void) {
        let state = state(of: table)
        state?.renderer.rowsReloaded()
        state?.willReload()
        reload()
        state?.didReload()
    }

    static func rowsChanged(_ table: NSTableView) { state(of: table)?.renderer.rowsReloaded() }
}

/// A plain NSTableView in the Claude grid look (`SAClaudeUtilityGrid`). Open for subclassing: the Server Variables list is
/// `SAClaudeServerVariablesTableView`.
@objc(SAClaudeUtilityGridTableView) class SAClaudeUtilityGridTableView: NSTableView, SAClaudeUtilityGridList {

    typealias State = SAClaudeUtilityGrid.State

    var state: State? { SAClaudeUtilityGrid.state(of: self) }

    /// Turns an exact NSTableView into `gridClass` (this class or a subclass of it) and installs the grid; the table
    /// unchanged when it was already adopted. Nil when it can't (another class, or observed by KVO, `SAClaudeClassSwap`).
    static func adopt(_ table: NSTableView, as gridClass: SAClaudeUtilityGridTableView.Type = SAClaudeUtilityGridTableView.self) -> SAClaudeUtilityGridTableView? {
        // Plain NSTextFieldCells draw their text at the top of the frame (no SPTextAndLinkCell 2pt shift).
        SAClaudeUtilityGrid.adopt(table, from: NSTableView.self, as: gridClass, cellTextTopOffset: 0)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        SAClaudeUtilityGrid.appearanceChanged(self)
    }

    override var gridStyleMask: NSTableView.GridLineStyle {
        get { super.gridStyleMask }
        set { super.gridStyleMask = SAClaudeUtilityGrid.gridMask(self, newValue) }
    }

    override var rowHeight: CGFloat {
        get { super.rowHeight }
        set { super.rowHeight = SAClaudeUtilityGrid.rowHeight(self, newValue) }
    }

    override func frameOfCell(atColumn column: Int, row: Int) -> NSRect {
        SAClaudeUtilityGrid.frameOfCell(self, super.frameOfCell(atColumn: column, row: row), column: column)
    }

    override func drawBackground(inClipRect clipRect: NSRect) {
        if !SAClaudeUtilityGrid.drawBackground(self, in: clipRect) { super.drawBackground(inClipRect: clipRect) }
    }

    override func drawGrid(inClipRect clipRect: NSRect) {
        if !SAClaudeUtilityGrid.drawGrid(self, in: clipRect) { super.drawGrid(inClipRect: clipRect) }
    }

    override func drawRow(_ row: Int, clipRect: NSRect) {
        super.drawRow(row, clipRect: clipRect)
        SAClaudeUtilityGrid.didDrawRow(self, row, clipRect: clipRect)
    }

    // Cell-based tables only; overriding the deprecated hook is deliberate.
    @available(macOS, deprecated: 10.10)
    override func preparedCell(atColumn column: Int, row: Int) -> NSCell? {
        let cell = super.preparedCell(atColumn: column, row: row)
        SAClaudeUtilityGrid.prepared(cell, column: column, row: row, in: self)
        return cell
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        SAClaudeUtilityGrid.updateTrackingArea(self)
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        SAClaudeUtilityGrid.mouseMoved(self, event)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        SAClaudeUtilityGrid.mouseExited(self)
    }

    override func scrollWheel(with event: NSEvent) {
        super.scrollWheel(with: event)
        SAClaudeUtilityGrid.scrolled(self)
    }

    override func reloadData() {
        SAClaudeUtilityGrid.reload(self) { super.reloadData() }
    }

    override func noteNumberOfRowsChanged() {
        SAClaudeUtilityGrid.rowsChanged(self)
        super.noteNumberOfRowsChanged()
    }
}

/// An `SPCopyTable` (the Advanced Filter panel's) in the Claude grid look (`SAClaudeUtilityGrid`); SPCopyTable's own
/// behaviour (copy, editing keys, menus) is untouched.
@objc(SAClaudeUtilityGridCopyTable) final class SAClaudeUtilityGridCopyTable: SPCopyTable, SAClaudeUtilityGridList {

    var state: SAClaudeUtilityGrid.State? { SAClaudeUtilityGrid.state(of: self) }

    /// Turns an exact SPCopyTable into this class and installs the grid (its cells are SPTextAndLinkCells).
    static func adopt(_ table: NSTableView) -> SAClaudeUtilityGridCopyTable? {
        SAClaudeUtilityGrid.adopt(table, from: SPCopyTable.self, as: SAClaudeUtilityGridCopyTable.self, cellTextTopOffset: 2)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        SAClaudeUtilityGrid.appearanceChanged(self)
    }

    override var gridStyleMask: NSTableView.GridLineStyle {
        get { super.gridStyleMask }
        set { super.gridStyleMask = SAClaudeUtilityGrid.gridMask(self, newValue) }
    }

    override var rowHeight: CGFloat {
        get { super.rowHeight }
        set { super.rowHeight = SAClaudeUtilityGrid.rowHeight(self, newValue) }
    }

    override func frameOfCell(atColumn column: Int, row: Int) -> NSRect {
        SAClaudeUtilityGrid.frameOfCell(self, super.frameOfCell(atColumn: column, row: row), column: column)
    }

    override func drawBackground(inClipRect clipRect: NSRect) {
        if !SAClaudeUtilityGrid.drawBackground(self, in: clipRect) { super.drawBackground(inClipRect: clipRect) }
    }

    override func drawGrid(inClipRect clipRect: NSRect) {
        if !SAClaudeUtilityGrid.drawGrid(self, in: clipRect) { super.drawGrid(inClipRect: clipRect) }
    }

    override func drawRow(_ row: Int, clipRect: NSRect) {
        super.drawRow(row, clipRect: clipRect)
        SAClaudeUtilityGrid.didDrawRow(self, row, clipRect: clipRect)
    }

    // Cell-based tables only; overriding the deprecated hook is deliberate.
    @available(macOS, deprecated: 10.10)
    override func preparedCell(atColumn column: Int, row: Int) -> NSCell? {
        let cell = super.preparedCell(atColumn: column, row: row)
        SAClaudeUtilityGrid.prepared(cell, column: column, row: row, in: self)
        return cell
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        SAClaudeUtilityGrid.updateTrackingArea(self)
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        SAClaudeUtilityGrid.mouseMoved(self, event)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        SAClaudeUtilityGrid.mouseExited(self)
    }

    override func scrollWheel(with event: NSEvent) {
        super.scrollWheel(with: event)
        SAClaudeUtilityGrid.scrolled(self)
    }

    override func reloadData() {
        SAClaudeUtilityGrid.reload(self) { super.reloadData() }
    }

    override func noteNumberOfRowsChanged() {
        SAClaudeUtilityGrid.rowsChanged(self)
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
