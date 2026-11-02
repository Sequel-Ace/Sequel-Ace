//
//  SAClaudeNavigatorStyler.swift
//  Sequel Ace
//
//  The Navigator panel in the Claude look (spec 2026-10-18-claude-utility-windows-design.md, section D):
//
//  - The schema tree as a Claude sidebar: sidebar fill, selection pills, 22pt rows of 12pt text, the type column muted,
//    the main sidebar's glyphs (database, table, view, procedure, function, column; a server for a connection) in place
//    of the old bitmap icons.
//  - The information list under it in the same sidebar look, each "Label: value" row as the main window's Table
//    information rows (label muted, value right-aligned); the divider between them a hairline.
//  - The top bar: the search field (a Claude field), the sync toggle as a ghost toggle (accent tint and a soft fill while
//    on), Reload as a ghost icon.
//
//  The panel is a shared NSPanel owned by `SPNavigatorController`; it is claimed by identity (the controller's window and
//  outlets) whenever the generic skin considers it (each time it becomes key). The tree's row heights come from the
//  controller's delegate, which asks `SAClaudeUtilitySidebarMetrics`. App target only.
//

import AppKit

@MainActor
@objc(SAClaudeNavigatorStyler) final class SAClaudeNavigatorStyler: NSObject {

    enum Strings {
        static var reload: String { NSLocalizedString("ClaudeNavigatorReload", value: "Reload all structures", comment: "navigator : tooltip and accessibility name of the reload button in the top bar") }
    }

    struct Outlets {
        let outline: NSOutlineView
        let info: NSTableView
        let split: NSSplitView
        let search: NSSearchField
        let sync: NSButton
        let reload: NSButton
    }

    static let rowHeight: CGFloat = 22
    static let font = NSFont.systemFont(ofSize: 12)
    static let barHeight: CGFloat = 40
    static let barInset: CGFloat = 10
    static let controlHeight: CGFloat = 24

    private static var associationKey: UInt8 = 0
    private weak var window: NSWindow?
    private let o: Outlets
    private var appearanceObservation: NSKeyValueObservation?

    private init(window: NSWindow, outlets: Outlets) {
        self.window = window
        self.o = outlets
        super.init()
    }

    // MARK: Claiming

    static func claim(_ window: NSWindow?) {
        guard let window else { return }
        if let styler = objc_getAssociatedObject(window, &associationKey) as? SAClaudeNavigatorStyler {
            styler.apply()
            return
        }
        guard let controller = window.windowController, controller.window === window,
              SAClaudeFormOwners.className(of: controller) == "SPNavigatorController",
              let outlets = findOutlets(controller, window: window) else { return }
        let styler = SAClaudeNavigatorStyler(window: window, outlets: outlets)
        objc_setAssociatedObject(window, &associationKey, styler, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        styler.build()
        styler.apply()
    }

    private static func findOutlets(_ controller: NSObject, window: NSWindow) -> Outlets? {
        guard let outline: NSOutlineView = SAClaudeFormRecipes.outlet(controller, "outlineSchema2"),
              let info: NSTableView = SAClaudeFormRecipes.outlet(controller, "infoTable"),
              let split: NSSplitView = SAClaudeFormRecipes.outlet(controller, "schemaStatusSplitView"),
              let search: NSSearchField = SAClaudeFormRecipes.outlet(controller, "searchField"),
              let sync: NSButton = SAClaudeFormRecipes.outlet(controller, "syncButton"),
              let contentView = window.contentView, split.superview === contentView, search.superview === contentView,
              sync.superview === contentView,
              let reload = contentView.subviews.compactMap({ $0 as? NSButton }).first(where: { $0.action == NSSelectorFromString("reloadAllStructures:") }),
              outline.window === window, info.window === window else { return nil }
        return Outlets(outline: outline, info: info, split: split, search: search, sync: sync, reload: reload)
    }

    // MARK: Building

    private func build() {
        SAClaudeUtilitySidebar.adopt(o.outline) { state in
            state.rowHeight = Self.rowHeight
            state.font = Self.font
            state.detailColumns = ["type"]
            state.glyph = { table, _, image in Self.glyph(replacing: image, in: table) }
        }
        SAClaudeUtilitySidebar.adopt(o.info) { state in
            state.rowHeight = Self.rowHeight
            state.font = Self.font
            state.glyph = { _, _, _ in nil }
            state.attributedText = { table, row, cell in Self.infoRow(table: table, row: row, cell: cell) }
        }
        SAClaudeUtilityChrome.styleSplitDivider(o.split)
        SAClaudeUtilityChrome.styleGhostIcon(o.reload, symbol: "arrow.clockwise", label: Strings.reload)
        SAClaudeGhostToggleCell.install(on: o.sync, symbol: "arrow.triangle.2.circlepath")

        SAClaudeThemeWatcher.observe(self) { styler in
            MainActor.assumeIsolated { styler.recolour() }
        }
        SAClaudeAccent.observe(self) { styler in
            MainActor.assumeIsolated { styler.o.sync.needsDisplay = true }
        }
        appearanceObservation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.recolour() } }
        }
    }

    // MARK: Glyphs

    private static let glyphCanvas = NSSize(width: SAClaudeStyle.iconSize + 6, height: SAClaudeStyle.iconSize)
    private static var glyphs: [String: NSImage] = [:]

    /// The Claude glyph for the bitmap icon the controller gave a row's cell (by the image's name); an image this doesn't
    /// know is kept.
    private static func glyph(replacing image: NSImage?, in table: NSTableView) -> NSImage? {
        guard let name = image?.name() else { return image }
        if let cached = glyphs[name] { return cached }
        let glyph: SAClaudeGlyph?
        switch name {
        case "database-small": glyph = .database
        case "table-small-square": glyph = .table
        case "table-view-small-square": glyph = .view
        case "proc-small": glyph = .procedure
        case "func-small": glyph = .function
        case "field-small-square": glyph = .field
        case "network-small":
            // Tinted for the list's appearance (a symbol image is drawn as it is).
            let tint = SAClaudeUtilityChrome.resolved(SAClaudeStyle.textMuted, for: table)
            return SAClaudeUtilityChrome.tintedSymbol("server.rack", tint: tint, canvas: glyphCanvas, glyphX: 0)
        case "dummy-small": return image
        default: return image
        }
        guard let glyph else { return image }
        // Drawn in its dynamic tint at every use, so it follows the appearance.
        let drawn = SAClaudeGlyphs.image(glyph, tint: SAClaudeGlyphs.tint(for: glyph), canvas: glyphCanvas, glyphX: 0)
        glyphs[name] = drawn
        return drawn
    }

    /// An information row ("Type: InnoDB") as the main window's Table information rows: the label muted, the value
    /// secondary and right-aligned; no indent of the cell's own (the row is indented by its paragraph).
    private static func infoRow(table: NSTableView, row: Int, cell: NSTextFieldCell) -> NSAttributedString? {
        let text = cell.stringValue
        guard !text.isEmpty, let column = table.tableColumns.first else { return nil }
        (cell as? ImageAndTextCell)?.setIndentationLevel(0)
        return SAClaudeInfoRow.attributedRow(text: text, width: column.width)
    }

    // MARK: Applying

    private func apply() {
        layout()
        recolour()
    }

    /// The top bar: the search field filling the left, then the sync toggle and Reload on the right; the split below.
    private func layout() {
        guard let contentView = window?.contentView else { return }
        let bounds = contentView.bounds
        let barMidY = bounds.maxY - Self.barHeight / 2
        let iconSize = SAClaudeSidebarBarLayout.buttonSize
        let reload = NSRect(x: bounds.maxX - Self.barInset - iconSize, y: (barMidY - iconSize / 2).rounded(), width: iconSize, height: iconSize)
        let syncWidth = SAClaudeGhostToggleCell.width(of: o.sync)
        let sync = NSRect(x: reload.minX - 6 - syncWidth, y: (barMidY - Self.controlHeight / 2).rounded(), width: syncWidth, height: Self.controlHeight)
        let search = NSRect(x: bounds.minX + Self.barInset, y: (barMidY - Self.controlHeight / 2).rounded(),
                            width: max(60, sync.minX - 8 - bounds.minX - Self.barInset), height: Self.controlHeight)
        SAClaudeUtilityChrome.pin(o.reload, reload, [.minXMargin, .minYMargin])
        SAClaudeUtilityChrome.pin(o.sync, sync, [.minXMargin, .minYMargin])
        SAClaudeUtilityChrome.pin(o.search, search, [.width, .minYMargin])
        SAClaudeUtilityChrome.pin(o.split, NSRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: max(0, bounds.height - Self.barHeight)),
                                  [.width, .height])
    }

    private func recolour() {
        let colours = SAClaudeSheetColours.current()
        SAClaudeUtilityChrome.recolourGhostIcons([o.reload], colours)
        SAClaudeHoverHighlighter.setFillColour(colours.palette.hover, for: o.sync)
        for list in [o.outline, o.info] as [NSTableView] {
            list.needsDisplay = true
            list.headerView?.needsDisplay = true
        }
        o.sync.needsDisplay = true
        o.split.needsDisplay = true
    }
}

// MARK: - Ghost toggle

/// A toggle push button (the Navigator's recessed "sync") as a ghost toggle: borderless, a leading symbol and its title in
/// the theme text while off; the accent and a soft accent fill while on; the hover fill (`SAClaudeHoverHighlighter`).
/// Installed over the button's exact NSButtonCell in place (no stored properties), so its state, key equivalent, target
/// and action stay as they were.
@objc(SAClaudeGhostToggleCell) final class SAClaudeGhostToggleCell: NSButtonCell {

    static let font = NSFont.systemFont(ofSize: 12)
    static let padding: CGFloat = 8
    static let imageGap: CGFloat = 5
    static let radius: CGFloat = SAClaudeStyle.barButtonRadius
    /// The on state's fill: the accent at this alpha.
    static let fillAlpha: CGFloat = 0.16

    /// Swaps `button`'s exact NSButtonCell for this one (and the button for one drawn by its cell, as the other Claude
    /// cells are, `SAClaudeFilterCells.install`) and gives it `symbol`; false when it can't (another class, or observed by KVO).
    @discardableResult
    static func install(on button: NSButton, symbol: String) -> Bool {
        guard SAClaudeFilterCells.install(SAClaudeGhostToggleCell.self, on: button) else { return false }
        button.image = SAClaudeUtilityChrome.symbol(symbol, pointSize: 12)
        button.imagePosition = .imageLeading
        SAClaudeHoverHighlighter.attach(to: button)
        button.needsDisplay = true
        return true
    }

    /// The width the toggle needs for its symbol and title.
    static func width(of button: NSButton) -> CGFloat {
        let title = ceil((button.title as NSString).size(withAttributes: [.font: font]).width)
        let image = button.image.map { $0.size.width + imageGap } ?? 0
        return title + image + 2 * padding
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        let isOn = state == .on
        let path = NSBezierPath(roundedRect: cellFrame.insetBy(dx: 0.5, dy: 0.5), xRadius: Self.radius, yRadius: Self.radius)
        if isOn {
            SAClaudeAccent.accent.withAlphaComponent(Self.fillAlpha).setFill()
            path.fill()
        }
        let tint: NSColor = !isEnabled ? SAClaudeFilterBarStyler.currentPalette.icon
            : isOn ? SAClaudeAccent.accent : SAClaudeFilterBarStyler.currentThemeText
        let title = NSAttributedString(string: self.title, attributes: [.font: Self.font, .foregroundColor: tint])
        let titleSize = title.size()
        let imageSize = image?.size ?? .zero
        let contentWidth = ceil(titleSize.width) + (image == nil ? 0 : imageSize.width + Self.imageGap)
        var x = (cellFrame.midX - contentWidth / 2).rounded()
        if let image {
            let rect = NSRect(x: x, y: (cellFrame.midY - imageSize.height / 2).rounded(), width: imageSize.width, height: imageSize.height)
            NSImage(size: imageSize, flipped: false) { r in
                image.draw(in: r)
                tint.set()
                r.fill(using: .sourceAtop)
                return true
            }.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            x += imageSize.width + Self.imageGap
        }
        title.draw(at: NSPoint(x: x, y: (cellFrame.midY - titleSize.height / 2).rounded()))
    }
}
