//
//  SAClaudeImportMapperStyler.swift
//  Sequel Ace
//
//  The Claude CSV field mapping sheet: a header ("Import CSV", the source file in a pill frame, "Into" and the
//  table-target pill with the "+ New table" ghost, or the new-table name row), a "Field mapping" card (the preview
//  row navigator and the mapping table: pill-drawn source values, glyph operators, 24pt rows), an "Options" card (its
//  rows are `SAClaudeImportOptionsStyler`'s) and a footer (the "Go back" ghost, Cancel, Import). The XIB's own controls are restyled and placed from
//  `SAClaudeImportMapperLayout`; the controller keeps every action, shortcut, menu and the visibility of the
//  new-table controls. The generic sheet skin keeps styling the controls; this styler owns the layout, the cards and
//  the bespoke pieces. Attached once per `SPFieldMapperController` from its `awakeFromNib`, updated from its method,
//  table-target, new-table and header-row actions; any missing outlet leaves the generic look. App target only.
//

import AppKit

@objc(SAClaudeImportMapperStyler) final class SAClaudeImportMapperStyler: NSObject {

    private typealias Layout = SAClaudeImportMapperLayout

    private static var associationKey: UInt8 = 0

    private static let titleFont = NSFont.systemFont(ofSize: 15, weight: .medium)
    private static let sectionFont = NSFont.systemFont(ofSize: 11)
    private static let labelFont = NSFont.systemFont(ofSize: 12)
    private static let navigatorFont = NSFont.systemFont(ofSize: 11)
    private static let pillRadius: CGFloat = 7
    private static let cardRadius: CGFloat = 12
    /// The path control's inset in its pill frame.
    private static let pathInset = NSSize(width: 8, height: 2)
    private static let ghostButtonPadding: CGFloat = 8
    private static let tableRowHeight: CGFloat = 24

    // The mapping table's columns (SPFieldMapperController.m's identifiers).
    private static let importValueColumn = NSUserInterfaceItemIdentifier("import_value")
    private static let operatorColumn = NSUserInterfaceItemIdentifier("operator")
    private static let targetFieldColumn = NSUserInterfaceItemIdentifier("target_field")
    private static let typeColumn = NSUserInterfaceItemIdentifier("type")

    /// The controller's views this styler moves or restyles, read once by KVC.
    private struct Outlets {
        let window: NSWindow
        let contentView: NSView
        /// The XIB's header box: it holds the off-screen key-equivalent buttons, so it stays (drawn no more).
        let headerBox: NSBox
        let headerTitle: NSTextField
        let pathControl: NSPathControl
        let tableTargetPopUp: NSPopUpButton
        let newTableNameLabel: NSTextField
        let newTableNameField: NSTextField
        let newTableInfoButton: NSButton
        let newTableButton: NSButton
        let tableScrollView: NSScrollView
        let tableView: NSTableView
        let previousRowButton: NSButton
        let nextRowButton: NSButton
        let recordCountLabel: NSTextField
        let advancedButton: NSButton
        /// An NSButton in the XIB, typed NSTextField in the header.
        let advancedLabel: NSView
        let advancedBox: NSBox
        let goBackButton: NSButton
        let cancelButton: NSButton
        let importButton: NSButton

        init?(_ c: NSObject) {
            func outlet<T>(_ key: String) -> T? { SAClaudeExportStyler.outlet(c, key) }
            guard let window = (c as? NSWindowController)?.window, let contentView = window.contentView, !contentView.isFlipped,
                  let pathControl: NSPathControl = outlet("fileSourcePath"),
                  let tableTargetPopUp: NSPopUpButton = outlet("tableTargetPopup"),
                  let newTableNameLabel: NSTextField = outlet("newTableNameLabel"),
                  let newTableNameField: NSTextField = outlet("newTableNameTextField"),
                  let newTableInfoButton: NSButton = outlet("newTableNameInfoButton"),
                  let newTableButton: NSButton = outlet("newTableButton"),
                  let tableScrollView: NSScrollView = outlet("fieldMapperTableScrollView"),
                  let tableView: NSTableView = outlet("fieldMapperTableView"), tableView.enclosingScrollView === tableScrollView,
                  let previousRowButton: NSButton = outlet("rowDownButton"),
                  let nextRowButton: NSButton = outlet("rowUpButton"),
                  let recordCountLabel: NSTextField = outlet("recordCountLabel"),
                  let advancedButton: NSButton = outlet("advancedButton"),
                  let advancedLabel: NSView = outlet("advancedLabel"),
                  let advancedBox: NSBox = outlet("advancedBox"),
                  let goBackButton: NSButton = outlet("gobackButton"),
                  let importButton: NSButton = outlet("importButton")
            else { return nil }

            // The placed views are the content view's own (the layout's frames are in its coordinates).
            let placed: [NSView] = [pathControl, tableTargetPopUp, newTableNameLabel, newTableNameField, newTableInfoButton, newTableButton,
                                    tableScrollView, previousRowButton, nextRowButton, recordCountLabel, goBackButton, importButton]
            guard placed.allSatisfy({ $0.superview === contentView }) else { return nil }

            // The XIB views without outlets: the header box (with its title) and Cancel.
            guard let headerBox = contentView.subviews.compactMap({ $0 as? NSBox }).first(where: { box in
                      box !== advancedBox && (box.contentView?.subviews.contains { $0 is NSTextField } ?? false)
                  }),
                  let headerTitle = headerBox.contentView?.subviews.compactMap({ $0 as? NSTextField }).first,
                  let cancelButton = contentView.subviews.first(where: {
                      guard let button = $0 as? NSButton, !(button is NSPopUpButton) else { return false }
                      return button.tag == 0 && button.keyEquivalent == "\u{1b}"
                  }) as? NSButton else { return nil }

            self.window = window
            self.contentView = contentView
            self.headerBox = headerBox
            self.headerTitle = headerTitle
            self.pathControl = pathControl
            self.tableTargetPopUp = tableTargetPopUp
            self.newTableNameLabel = newTableNameLabel
            self.newTableNameField = newTableNameField
            self.newTableInfoButton = newTableInfoButton
            self.newTableButton = newTableButton
            self.tableScrollView = tableScrollView
            self.tableView = tableView
            self.previousRowButton = previousRowButton
            self.nextRowButton = nextRowButton
            self.recordCountLabel = recordCountLabel
            self.advancedButton = advancedButton
            self.advancedLabel = advancedLabel
            self.advancedBox = advancedBox
            self.goBackButton = goBackButton
            self.cancelButton = cancelButton
            self.importButton = importButton
        }
    }

    private let outlets: Outlets
    /// The Options card (and the Global values sheet's polish).
    private let options: SAClaudeImportOptionsStyler

    // Added views.
    private let titleLabel = NSTextField(labelWithString: NSLocalizedString("ClaudeImportMapperTitle", value: "Import CSV", comment: "import field mapping sheet: title in the header"))
    private let pathCard = SAClaudeTableInfoCardView()
    private let intoLabel = NSTextField(labelWithString: NSLocalizedString("ClaudeImportInto", value: "Into", comment: "import field mapping sheet: label before the target table pop-up"))
    private let leftCard = SAClaudeTableInfoCardView()
    private let rightCard = SAClaudeTableInfoCardView()
    private let leftTitle = NSTextField(labelWithString: NSLocalizedString("ClaudeImportFieldMapping", value: "Field mapping", comment: "import field mapping sheet: title of the card with the mapping table"))
    private let rightTitle = NSTextField(labelWithString: NSLocalizedString("ClaudeImportOptions", value: "Options", comment: "import field mapping sheet: title of the card with the import options"))

    private let newTableTitle = NSLocalizedString("ClaudeImportNewTable", value: "+ New table", comment: "import field mapping sheet: button that imports into a new table")
    private let goBackTitle = NSLocalizedString("ClaudeImportGoBack", value: "‹ Go back", comment: "import field mapping sheet: button that goes back to the file chooser")

    private var palette: SAClaudeEditorChrome.Palette?
    private var themeText: NSColor?
    private var cardFill: NSColor?
    private var isLayingOut = false

    private var frameObservers: [NSObjectProtocol] = []
    private var appearanceObservation: NSKeyValueObservation?

    // MARK: - Hooks

    /// Restyles and lays out the field mapping sheet of `controller` (an `SPFieldMapperController`), once. Does
    /// nothing when an expected outlet or XIB view is missing.
    @objc(attachToController:) static func attach(to controller: NSObject) {
        guard styler(for: controller) == nil, let outlets = Outlets(controller),
              let options = SAClaudeImportOptionsStyler(controller: controller, container: outlets.contentView,
                                                        newTableNameField: outlets.newTableNameField) else { return }
        let styler = SAClaudeImportMapperStyler(outlets: outlets, options: options)
        objc_setAssociatedObject(controller, &associationKey, styler, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        styler.build()
    }

    /// While attached the styler owns the sheet's size and the method options: the controller's window-height and
    /// advanced-panel code returns early.
    @objc(isAttachedToController:) static func isAttached(to controller: NSObject) -> Bool {
        styler(for: controller) != nil
    }

    /// After the controller changed the import method, the target table, new-table mode or the header-row switch.
    @objc(controllerDidUpdate:) static func controllerDidUpdate(_ controller: NSObject) {
        onMain { styler(for: controller)?.update() }
    }

    private static func styler(for controller: NSObject) -> SAClaudeImportMapperStyler? {
        objc_getAssociatedObject(controller, &associationKey) as? SAClaudeImportMapperStyler
    }

    private static func onMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
    }

    // MARK: - Building

    private init(outlets: Outlets, options: SAClaudeImportOptionsStyler) {
        self.outlets = outlets
        self.options = options
        super.init()
    }

    deinit {
        for observer in frameObservers { NotificationCenter.default.removeObserver(observer) }
        appearanceObservation?.invalidate()
    }

    private func build() {
        let o = outlets
        // The sheet is not on screen yet: it opens at least the minimum size (the frame autosave may restore a
        // smaller one).
        let minimum = Layout.minimumContentSize
        o.window.minSize = minimum
        o.window.contentMinSize = minimum
        let size = o.contentView.bounds.size
        if size.width < minimum.width || size.height < minimum.height {
            o.window.setContentSize(NSSize(width: max(size.width, minimum.width), height: max(size.height, minimum.height)))
        }

        hideClassicChrome()
        addViews()
        restyle()
        refresh(force: true)
        update()
        // The columns share the table's width from now on (the operator column keeps its fixed 28pt).
        o.tableView.sizeToFit()
        observe()
    }

    /// The header box's drawing and title (the box stays: its off-screen buttons carry ⌘=, ⌥⌘A and ⌘⌫), and the
    /// advanced disclosure, its label and separator (the Options card shows the method's options).
    private func hideClassicChrome() {
        let o = outlets
        o.headerBox.isTransparent = true
        o.headerTitle.isHidden = true
        for view: NSView in [o.advancedButton, o.advancedLabel, o.advancedBox] where !view.isHidden {
            view.isHidden = true
        }
    }

    private func addViews() {
        let o = outlets
        titleLabel.font = Self.titleFont
        intoLabel.font = Self.labelFont
        for title in [leftTitle, rightTitle] {
            title.font = Self.sectionFont
            title.lineBreakMode = .byTruncatingTail
        }
        // Above the theme surface the window skin adds (when it already has), below every control.
        let surface = o.contentView.subviews.first { $0.identifier?.rawValue == "SAClaudeSheetSurface" }
        pathCard.radius = Self.pillRadius
        for card in [leftCard, rightCard] { card.radius = Self.cardRadius }
        for card in [pathCard, leftCard, rightCard] {
            o.contentView.addSubview(card, positioned: surface == nil ? .below : .above, relativeTo: surface)
        }
        for view in [titleLabel, intoLabel, leftTitle, rightTitle] as [NSView] { o.contentView.addSubview(view) }
        // VoiceOver reads "Into" as the target pop-up's title.
        o.tableTargetPopUp.setAccessibilityTitleUIElement(intoLabel)
    }

    /// One-off restyles of the XIB's controls (colours follow in `refresh`).
    private func restyle() {
        let o = outlets
        // Header.
        o.pathControl.controlSize = .small
        o.pathControl.cell?.lineBreakMode = .byTruncatingMiddle
        SAClaudeFilterCells.installPill(on: o.tableTargetPopUp)
        o.newTableNameLabel.stringValue = NSLocalizedString("ClaudeImportNewTableName", value: "Name", comment: "import field mapping sheet: label before the new table's name field")
        o.newTableNameLabel.font = Self.labelFont
        o.newTableNameLabel.lineBreakMode = .byTruncatingTail
        for button in [o.newTableButton, o.goBackButton] {
            button.isBordered = false
            button.image = nil
            button.imagePosition = .noImage
            // A tint would override the muted attributed title once the button is borderless.
            button.contentTintColor = nil
            SAClaudeHoverHighlighter.attach(to: button)
        }
        for button in [o.newTableInfoButton, o.previousRowButton, o.nextRowButton] {
            button.isBordered = false
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleNone
            SAClaudeHoverHighlighter.attach(to: button)
        }

        // Mapping card: the navigator and the table.
        o.recordCountLabel.font = Self.navigatorFont
        o.recordCountLabel.alignment = .right
        o.recordCountLabel.lineBreakMode = .byTruncatingTail
        o.tableScrollView.borderType = .noBorder
        let table = o.tableView
        table.rowHeight = Self.tableRowHeight
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        let headers: [(NSUserInterfaceItemIdentifier, String)] = [
            (Self.importValueColumn, NSLocalizedString("ClaudeImportColumnSource", value: "CSV field", comment: "import field mapping sheet: header of the column choosing the CSV value for each target column")),
            (Self.targetFieldColumn, NSLocalizedString("ClaudeImportColumnTarget", value: "Target column", comment: "import field mapping sheet: header of the target table's column names")),
            (Self.typeColumn, NSLocalizedString("ClaudeImportColumnType", value: "Type", comment: "import field mapping sheet: header of the target columns' types")),
        ]
        for (identifier, title) in headers {
            table.tableColumn(withIdentifier: identifier)?.headerCell.stringValue = title
        }
        // The data cells draw Claude pills and operator glyphs; their menus, targets and actions stay the controller's.
        Self.swapPopUpCell(of: table.tableColumn(withIdentifier: Self.importValueColumn), to: SAClaudeTablePillPopUpCell.self)
        Self.swapPopUpCell(of: table.tableColumn(withIdentifier: Self.operatorColumn), to: SAClaudeImportOperatorCell.self)
    }

    /// Swaps `column`'s data cell, an exact NSPopUpButtonCell nothing observes, to `cellClass` in place.
    private static func swapPopUpCell(of column: NSTableColumn?, to cellClass: AnyClass) {
        guard let cell = column?.dataCell as? NSPopUpButtonCell, type(of: cell) == NSPopUpButtonCell.self,
              SAClaudeClassSwap.mayChangeClass(of: cell) else { return }
        object_setClass(cell, cellClass)
    }

    private func observe() {
        let o = outlets
        o.contentView.postsFrameChangedNotifications = true
        frameObservers.append(NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: o.contentView, queue: nil) { [weak self] _ in
            Self.onMain { self?.layOut() }
        })
        SAClaudeThemeWatcher.observe(self) { $0.refresh(force: false) }
        appearanceObservation = o.window.observe(\.effectiveAppearance) { [weak self] _, _ in
            Self.onMain { self?.refresh(force: true) }
        }
        SAClaudeAccent.observe(self) { $0.refresh(force: true) }
    }

    // MARK: - Updating

    /// Follows the controller: the ghost titles' enabled state, the header set it shows (existing table or new
    /// table), the layout and the key view loop.
    private func update() {
        let o = outlets
        // The controller never shows them again while attached (`openAdvancedSheet:` returns early); belt and braces.
        for view: NSView in [o.advancedButton, o.advancedLabel, o.advancedBox] where !view.isHidden { view.isHidden = true }
        styleGhostTitles()
        options.update()
        layOut()
        chainKeyViews()
    }

    // MARK: - Colours

    /// Re-derives the colours when the editor theme changed (always, when `force`) and recolours the added views.
    private func refresh(force: Bool) {
        let o = outlets
        var resolved: (SAClaudeEditorChrome.Palette, NSColor, NSColor, NSColor)?
        o.window.effectiveAppearance.performAsCurrentDrawingAppearance {
            let palette = SAClaudeEditorChrome.palette(from: .standard)
            let theme = SAClaudeThemeColours.from(defaults: .standard)
            let surface = SAClaudeStatusChrome.popupSurface(theme: theme)
            resolved = (palette, theme.text, SAClaudeFilterChrome.cardFill(text: theme.text, background: surface),
                        SAClaudeFilterChrome.fieldFill(text: theme.text, background: surface))
        }
        guard let (palette, text, fill, fieldFill) = resolved else { return }
        guard force || palette != self.palette || text != themeText || fill != cardFill else { return }
        self.palette = palette
        themeText = text
        cardFill = fill
        let muted = palette.icon

        for card in [pathCard, leftCard, rightCard] {
            card.fill = fill
            card.stroke = palette.hairline
        }
        titleLabel.textColor = text
        for label in [intoLabel, leftTitle, rightTitle, o.newTableNameLabel, o.recordCountLabel] { label.textColor = muted }
        let glyphs: [(NSButton, SAClaudeGlyph)] = [(o.newTableInfoButton, .info), (o.previousRowButton, .chevronLeft), (o.nextRowButton, .chevronRight)]
        for (button, glyph) in glyphs {
            let image = SAClaudeGlyphs.image(glyph, tint: muted)
            button.image = image
            button.alternateImage = image
        }
        for button in [o.newTableInfoButton, o.previousRowButton, o.nextRowButton, o.newTableButton, o.goBackButton] {
            SAClaudeHoverHighlighter.setFillColour(palette.hover, for: button)
        }
        (o.tableView.tableColumn(withIdentifier: Self.targetFieldColumn)?.dataCell as? NSTextFieldCell)?.textColor = text
        options.recolour(palette: palette, text: text, cardFill: fill, fieldFill: fieldFill)
        // The pill and operator cells read the palette at draw time.
        o.tableView.needsDisplay = true
        styleGhostTitles()
    }

    /// "+ New table" and "‹ Go back" in SF Pro 12 muted, half strength while disabled (an attributed title doesn't dim).
    private func styleGhostTitles() {
        guard let muted = palette?.icon else { return }
        let o = outlets
        for (button, title) in [(o.newTableButton, newTableTitle), (o.goBackButton, goBackTitle)] {
            let colour = button.isEnabled ? muted : muted.withAlphaComponent(0.5)
            let attributed = NSAttributedString(string: title, attributes: [.font: Self.labelFont, .foregroundColor: colour])
            if button.attributedTitle != attributed { button.attributedTitle = attributed }
        }
    }

    // MARK: - Layout

    private func layOut() {
        let o = outlets
        guard !isLayingOut, o.contentView.bounds.width > 0, o.contentView.bounds.height > 0 else { return }
        isLayingOut = true
        defer { isLayingOut = false }

        let inputs = Layout.Inputs(pathWidth: pathWidth(), intoLabelWidth: Self.cellWidth(intoLabel),
                                   newButtonWidth: Self.ghostWidth(o.newTableButton), nameLabelWidth: Self.cellWidth(o.newTableNameLabel),
                                   goBackWidth: Self.ghostWidth(o.goBackButton))
        let f = Layout.frames(in: o.contentView.bounds, inputs)

        // Header: both sets are placed; the controller shows one (the target pop-up and New, or the name row).
        Self.placeLabel(titleLabel, f.title)
        Self.place(pathCard, f.path)
        Self.place(o.pathControl, f.path.insetBy(dx: Self.pathInset.width, dy: Self.pathInset.height))
        let pathShown = f.path.width > 2 * Self.pathInset.width
        if pathCard.isHidden == pathShown { pathCard.isHidden = !pathShown }
        let intoHidden = o.tableTargetPopUp.isHidden
        if intoLabel.isHidden != intoHidden { intoLabel.isHidden = intoHidden }
        Self.placeLabel(intoLabel, f.intoLabel)
        Self.place(o.tableTargetPopUp, f.target)
        Self.place(o.newTableButton, f.newButton)
        Self.placeLabel(o.newTableNameLabel, f.nameLabel)
        Self.place(o.newTableNameField, f.nameField)
        Self.place(o.newTableInfoButton, f.info)

        // Mapping card.
        Self.place(leftCard, f.leftCard)
        Self.placeLabel(leftTitle, f.leftTitle)
        Self.placeLabel(o.recordCountLabel, f.navigatorLabel)
        Self.place(o.previousRowButton, f.previousRow)
        Self.place(o.nextRowButton, f.nextRow)
        Self.place(o.tableScrollView, f.table)

        // Options card.
        Self.place(rightCard, f.rightCard)
        Self.placeLabel(rightTitle, f.rightTitle)
        options.layOut(in: f.options)

        // Footer.
        Self.place(o.goBackButton, f.goBack)
        Self.place(o.cancelButton, f.cancel)
        Self.place(o.importButton, f.importButton)
    }

    /// The path control's own width in its pill frame (the layout clamps it to the room left).
    private func pathWidth() -> CGFloat {
        let control = outlets.pathControl
        let intrinsic = control.intrinsicContentSize.width
        let width = intrinsic > 0 ? intrinsic : (control.cell?.cellSize.width ?? 0)
        return ceil(width) + 2 * Self.pathInset.width
    }

    private static func ghostWidth(_ button: NSButton) -> CGFloat {
        ceil((button.cell?.cellSize.width ?? 0) + ghostButtonPadding)
    }

    private static func cellWidth(_ view: NSControl) -> CGFloat {
        ceil(view.cell?.cellSize.width ?? 0)
    }

    private static func place(_ view: NSView, _ frame: NSRect) {
        let aligned = NSRect(x: frame.minX.rounded(), y: frame.minY.rounded(), width: frame.width.rounded(), height: frame.height.rounded())
        if view.frame != aligned { view.frame = aligned }
        if !view.autoresizingMask.isEmpty { view.autoresizingMask = [] }
    }

    /// A one-line label at its text height, centred on `frame`'s row.
    private static func placeLabel(_ label: NSTextField, _ frame: NSRect) {
        let height = ceil(label.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)).height ?? frame.height)
        place(label, NSRect(x: frame.minX, y: (frame.midY - height / 2).rounded(.down), width: frame.width, height: height))
    }

    // MARK: - Key view loop

    /// Table target (or the new table's name) → table → options → Go back → Cancel → Import, and back.
    private func chainKeyViews() {
        let o = outlets
        let first: NSView = o.tableTargetPopUp.isHidden ? o.newTableNameField : o.tableTargetPopUp
        let chain: [NSView] = [first, o.tableView] + options.keyViews + [o.goBackButton, o.cancelButton, o.importButton]
        var pairs = Array(zip(chain, chain.dropFirst()))
        if let head = chain.first, let last = chain.last { pairs.append((last, head)) }
        for (view, next) in pairs where view.nextKeyView !== next || next.previousKeyView !== view {
            // Re-setting the same next view may not touch its previous view: clear first.
            if view.nextKeyView === next { view.nextKeyView = nil }
            view.nextKeyView = next
        }
    }
}

// MARK: - Mapping table cells

/// The mapping table's source-value cell: the Claude pill (an outline, the selected title in the cell's font — the
/// user's table font, set by the controller — and the selector), 2pt inside the row. Draw-only: installed in place of
/// the column's NSPopUpButtonCell by `object_setClass`, so its menu, menu delegate and the table's handling stay.
@objc(SAClaudeTablePillPopUpCell) final class SAClaudeTablePillPopUpCell: NSPopUpButtonCell {

    private static let inset: CGFloat = 2

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        SAClaudePillPopUpButtonCell.drawPill(title: SAClaudePillPopUpButtonCell.displayTitle(of: self), in: cellFrame.insetBy(dx: Self.inset, dy: Self.inset),
                                             flipped: controlView.isFlipped, font: font ?? FilterCellDrawing.font,
                                             enabled: isEnabled, highlighted: isHighlighted, outlined: true)
    }
}

/// The mapping table's operator cell: the selected operator as a muted glyph, centred — "→" import (item 0),
/// "·" skip (1), "=" match (2, UPDATE only) — instead of the native titles. Draw-only, like the pill cell: the menu
/// and its items are the controller's.
@objc(SAClaudeImportOperatorCell) final class SAClaudeImportOperatorCell: NSPopUpButtonCell {

    private static let glyphs = ["→", "·", "="]

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        let index = indexOfSelectedItem
        guard Self.glyphs.indices.contains(index) else { return }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        if !isEnabled { NSGraphicsContext.current?.cgContext.setAlpha(FilterCellDrawing.disabledAlpha) }
        FilterCellDrawing.drawTitle(Self.glyphs[index], in: cellFrame, colour: SAClaudeFilterBarStyler.currentPalette.icon,
                                    font: font ?? FilterCellDrawing.font, alignment: .center)
    }
}
