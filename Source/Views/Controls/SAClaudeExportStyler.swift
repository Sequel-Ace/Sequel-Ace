//
//  SAClaudeExportStyler.swift
//  Sequel Ace
//
//  The Claude Export sheet: a header with the format switcher, a "What to export" card (source switcher, table
//  list, All / None), the format options card, a "Save to" card (path, filename, compression, low memory) and a
//  footer (Presets, info line, Cancel, Export). The XIB's own controls are re-parented, restyled and placed from
//  `SAClaudeExportLayout`; the format tab view and the source pop-up stay the models the switchers drive. The
//  generic sheet skin keeps styling the controls; this styler owns the layout, the cards and the bespoke pieces.
//  Attached once per `SPExportController` from its `awakeFromNib`; any missing outlet leaves the generic look.
//  App target only.
//

import AppKit

@objc(SAClaudeExportStyler) final class SAClaudeExportStyler: NSObject {

    private typealias Layout = SAClaudeExportLayout

    private static var associationKey: UInt8 = 0

    private static let titleFont = NSFont.systemFont(ofSize: 15, weight: .medium)
    private static let sectionFont = NSFont.systemFont(ofSize: 11)
    private static let labelFont = NSFont.systemFont(ofSize: 12)
    private static let infoFont = NSFont.systemFont(ofSize: 11)
    private static let compressionWidth: CGFloat = 160
    private static let ghostButtonPadding: CGFloat = 8
    private static let checkboxColumns = ["structure", "content", "drop"]

    /// The controller's views this styler moves or restyles, read once by KVC.
    private struct Outlets {
        let window: NSWindow
        let contentView: NSView
        let exporterView: NSView
        let exportButton: NSButton
        let cancelButton: NSButton
        let pathField: NSTextField
        let pathLabel: NSTextField
        let changeButton: NSButton
        let presetsPopUp: NSPopUpButton
        let tableList: NSTableView
        let typeTabView: NSTabView
        let optionsTabView: NSTabView
        let inputPopUp: NSPopUpButton
        let filePerTableCheck: NSButton
        let selectAllButton: NSButton
        let deselectAllButton: NSButton
        let refreshButton: NSButton
        let tableListScrollView: NSScrollView
        let filenameDividerBox: NSBox
        let advancedOptionsButton: NSButton
        let advancedOptionsView: NSView
        let advancedOptionsLabelButton: NSButton
        let lowMemoryButton: NSButton
        let compressionPopUp: NSPopUpButton
        let tableListButtonBar: NSBox
        let formatInfoText: NSTextField
        let customFilenameButton: NSButton
        let customFilenameLabelButton: NSButton
        let customFilenameView: NSView
        let customFilenameTokenField: NSTokenField
        let customFilenameTokenPool: NSTokenField
    }

    private let outlets: Outlets

    // Added views.
    private let titleLabel = NSTextField(labelWithString: NSLocalizedString("ClaudeExportTitle", value: "Export", comment: "export dialog: title in the header"))
    private let formatSwitcher = SAClaudeConnectionTypeTabs()
    private let sourceSwitcher = SAClaudeConnectionTypeTabs()
    private let leftCard = SAClaudeTableInfoCardView()
    private let rightCard = SAClaudeTableInfoCardView()
    private let saveCard = SAClaudeTableInfoCardView()
    private let leftTitle = NSTextField(labelWithString: NSLocalizedString("ClaudeExportWhatTitle", value: "What to export", comment: "export dialog: title of the card with the source and the table list"))
    private let optionsTitle = NSTextField(labelWithString: "")
    private let saveTitle = NSTextField(labelWithString: NSLocalizedString("ClaudeExportSaveToTitle", value: "Save to", comment: "export dialog: title of the card with the destination folder and filename"))
    private let folderGlyph = NSImageView()
    private let fileGlyph = NSImageView()
    private let filenameLabel = NSTextField(labelWithString: "")
    private let compressionLabel = NSTextField(labelWithString: NSLocalizedString("ClaudeExportCompression", value: "Compression", comment: "export dialog: label of the output compression pop-up"))
    private lazy var customiseButton = NSButton(title: NSLocalizedString("ClaudeExportCustomise", value: "Customise", comment: "export dialog: button that opens the custom filename editor"),
                                                target: self, action: #selector(customise(_:)))

    /// Task 3: the options card's rows; nil when an options outlet is missing (that card keeps the XIB layout).
    private var optionsStyler: SAClaudeExportOptionsStyler?
    /// Task 4: the custom filename editor, in a child panel under Customise.
    private let filenameEditor: SAClaudeExportFilenameEditor
    /// Task 5: the progress and errors sheets; nil when their outlets are missing (those sheets keep the generic look).
    private var progressStyler: SAClaudeProgressSheetStyler?

    private var palette: SAClaudeEditorChrome.Palette?
    private var themeText: NSColor?
    private var cardFill: NSColor?
    private var isLayingOut = false

    private var frameObservers: [NSObjectProtocol] = []
    private var appearanceObservation: NSKeyValueObservation?
    private var columnObservations: [NSKeyValueObservation] = []

    // MARK: - Hooks

    /// Restyles and lays out the export sheet of `controller` (an `SPExportController`), once. Does nothing when an
    /// expected outlet or XIB view is missing.
    @objc(attachToController:) static func attach(to controller: NSObject) {
        guard styler(for: controller) == nil, let outlets = findOutlets(in: controller) else { return }
        let styler = SAClaudeExportStyler(outlets: outlets)
        objc_setAssociatedObject(controller, &associationKey, styler, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        styler.optionsStyler = SAClaudeExportOptionsStyler(controller: controller, tabView: outlets.optionsTabView)   // Task 3
        styler.progressStyler = SAClaudeProgressSheetStyler(   // Task 5
            progress: SAClaudeProgressSheetStyler.Outlets(controller, title: "exportProgressTitle", status: "exportProgressText",
                                                          indicator: "exportProgressIndicator"),
            errors: SAClaudeProgressSheetStyler.ErrorOutlets(controller, window: "errorsWindow", textView: "errorsTextView"),
            card: outlet(controller, "exportProgressWindow"))
        // A chip changes the filename field programmatically, which posts no text notification: the controller
        // updates its preview as after its own programmatic changes.
        styler.filenameEditor.onFieldChanged = { [weak controller] in
            let selector = NSSelectorFromString("updateDisplayedExportFilename")
            guard let controller, controller.responds(to: selector) else { return }
            controller.perform(selector)
        }
        styler.build()
    }

    @objc(isAttachedToController:) static func isAttached(to controller: NSObject) -> Bool {
        styler(for: controller) != nil
    }

    /// After the controller switched format (`_switchTab`) or source (`setExportInput:`).
    @objc(controllerDidUpdate:) static func controllerDidUpdate(_ controller: NSObject) {
        onMain { styler(for: controller)?.update() }
    }

    /// The generated (or custom) filename the controller would write, shown in the Save to card.
    @objc(controller:didUpdateFilename:) static func controller(_ controller: NSObject, didUpdateFilename filename: String) {
        onMain {
            guard let styler = styler(for: controller) else { return }
            styler.filenameLabel.stringValue = filename
            styler.filenameLabel.toolTip = filename
            // The controller refreshes the available tokens just before (e.g. "Table" removed): the chips follow.
            styler.filenameEditor.refreshTokens()
        }
    }

    /// True when the styler handled the custom-filename toggle itself (the filename editor panel, Task 4).
    @objc(handleCustomFilenameToggleForController:) static func handleCustomFilenameToggle(for controller: NSObject) -> Bool {
        styler(for: controller)?.toggleFilenameEditor() ?? false
    }

    private static func styler(for controller: NSObject) -> SAClaudeExportStyler? {
        objc_getAssociatedObject(controller, &associationKey) as? SAClaudeExportStyler
    }

    private static func onMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
    }

    // MARK: - Finding the outlets

    /// The controller's outlet `key` (an ivar or a property), or nil when it has none or it is nil / of another type.
    static func outlet<T>(_ controller: NSObject, _ key: String) -> T? {
        // `value(forKey:)` raises for an unknown key: look first.
        guard class_getInstanceVariable(type(of: controller), key) != nil || controller.responds(to: NSSelectorFromString(key)) else { return nil }
        return controller.value(forKey: key) as? T
    }

    private static func findOutlets(in c: NSObject) -> Outlets? {
        guard let window: NSWindow = outlet(c, "window"), let contentView = window.contentView,
              let exporterView: NSView = outlet(c, "exporterView"),
              let exportButton: NSButton = outlet(c, "exportButton"),
              let pathField: NSTextField = outlet(c, "exportPathField"),
              let tableList: NSTableView = outlet(c, "exportTableList"),
              let typeTabView: NSTabView = outlet(c, "exportTypeTabBar"),
              let optionsTabView: NSTabView = outlet(c, "exportOptionsTabBar"),
              let inputPopUp: NSPopUpButton = outlet(c, "exportInputPopUpButton"),
              let filePerTableCheck: NSButton = outlet(c, "exportFilePerTableCheck"),
              let selectAllButton: NSButton = outlet(c, "exportSelectAllTablesButton"),
              let deselectAllButton: NSButton = outlet(c, "exportDeselectAllTablesButton"),
              let refreshButton: NSButton = outlet(c, "exportRefreshTablesButton"),
              let tableListScrollView: NSScrollView = outlet(c, "exportTablelistScrollView"),
              let filenameDividerBox: NSBox = outlet(c, "exportFilenameDividerBox"),
              let advancedOptionsButton: NSButton = outlet(c, "exportAdvancedOptionsViewButton"),
              let advancedOptionsView: NSView = outlet(c, "exportAdvancedOptionsView"),
              let advancedOptionsLabelButton: NSButton = outlet(c, "exportAdvancedOptionsViewLabelButton"),
              let lowMemoryButton: NSButton = outlet(c, "exportProcessLowMemoryButton"),
              let compressionPopUp: NSPopUpButton = outlet(c, "exportOutputCompressionFormatPopupButton"),
              let tableListButtonBar: NSBox = outlet(c, "exportTableListButtonBar"),
              let formatInfoText: NSTextField = outlet(c, "exportFormatInfoText"),
              let customFilenameButton: NSButton = outlet(c, "exportCustomFilenameViewButton"),
              let customFilenameLabelButton: NSButton = outlet(c, "exportCustomFilenameViewLabelButton"),
              let customFilenameView: NSView = outlet(c, "exportCustomFilenameView"),
              let customFilenameTokenField: NSTokenField = outlet(c, "exportCustomFilenameTokenField"),
              let customFilenameTokenPool: NSTokenField = outlet(c, "exportCustomFilenameTokenPool"),
              !contentView.isFlipped, !exporterView.isFlipped else { return nil }

        // The XIB views without outlets.
        let changeAction = NSSelectorFromString("changeExportOutputPath:")
        let pathRow = pathField.frame
        guard let changeButton = exporterView.subviews.first(where: { ($0 as? NSButton)?.action == changeAction }) as? NSButton,
              let presetsPopUp = exporterView.subviews.first(where: { ($0 as? NSPopUpButton)?.pullsDown == true }) as? NSPopUpButton,
              let pathLabel = exporterView.subviews.compactMap({ $0 as? NSTextField })
                .filter({ $0 !== pathField && !$0.isEditable && $0.frame.maxX <= pathRow.minX + 1 && abs($0.frame.midY - pathRow.midY) < pathRow.height })
                .max(by: { $0.frame.maxX < $1.frame.maxX }),
              let cancelButton = contentView.subviews.first(where: {
                  guard let button = $0 as? NSButton, !(button is NSPopUpButton) else { return false }
                  return button.tag == 0 && button.keyEquivalent == "\u{1b}"
              }) as? NSButton else { return nil }

        return Outlets(window: window, contentView: contentView, exporterView: exporterView, exportButton: exportButton,
                       cancelButton: cancelButton, pathField: pathField, pathLabel: pathLabel, changeButton: changeButton,
                       presetsPopUp: presetsPopUp, tableList: tableList, typeTabView: typeTabView, optionsTabView: optionsTabView,
                       inputPopUp: inputPopUp, filePerTableCheck: filePerTableCheck, selectAllButton: selectAllButton,
                       deselectAllButton: deselectAllButton, refreshButton: refreshButton, tableListScrollView: tableListScrollView,
                       filenameDividerBox: filenameDividerBox, advancedOptionsButton: advancedOptionsButton,
                       advancedOptionsView: advancedOptionsView, advancedOptionsLabelButton: advancedOptionsLabelButton,
                       lowMemoryButton: lowMemoryButton, compressionPopUp: compressionPopUp, tableListButtonBar: tableListButtonBar,
                       formatInfoText: formatInfoText, customFilenameButton: customFilenameButton,
                       customFilenameLabelButton: customFilenameLabelButton, customFilenameView: customFilenameView,
                       customFilenameTokenField: customFilenameTokenField, customFilenameTokenPool: customFilenameTokenPool)
    }

    // MARK: - Building

    private init(outlets: Outlets) {
        self.outlets = outlets
        filenameEditor = SAClaudeExportFilenameEditor(customView: outlets.customFilenameView, tokenField: outlets.customFilenameTokenField,
                                                        tokenPool: outlets.customFilenameTokenPool)
        super.init()
    }

    deinit {
        for observer in frameObservers { NotificationCenter.default.removeObserver(observer) }
        appearanceObservation?.invalidate()
        columnObservations.forEach { $0.invalidate() }
    }

    private func build() {
        let o = outlets
        // The sheet is not on screen yet: it opens at least the minimum size.
        let minimum = Layout.minimumContentSize
        o.window.minSize = minimum
        o.window.contentMinSize = minimum
        let size = o.contentView.bounds.size
        if size.width < minimum.width || size.height < minimum.height {
            o.window.setContentSize(NSSize(width: max(size.width, minimum.width), height: max(size.height, minimum.height)))
        }

        hideClassicChrome()
        reparent()
        addViews()
        restyle()
        refresh(force: true)
        update()
        SAClaudeWindowSkin.skin(for: o.window)?.refresh(force: true)
        o.window.initialFirstResponder = o.tableList
        observe()
    }

    /// The format tab strip, the source pop-up, the disclosure rows, the separator and the boxes' drawing.
    private func hideClassicChrome() {
        let o = outlets
        o.typeTabView.tabViewType = .noTabsNoBorder
        o.typeTabView.drawsBackground = false
        o.optionsTabView.tabViewType = .noTabsNoBorder
        o.optionsTabView.drawsBackground = false
        for view: NSView in [o.inputPopUp, o.pathLabel, o.filenameDividerBox, o.customFilenameButton, o.customFilenameLabelButton,
                             o.advancedOptionsButton, o.advancedOptionsLabelButton] {
            view.isHidden = true
        }
        o.tableListButtonBar.isTransparent = true
    }

    /// The advanced strip's two controls and the table bar's buttons into the exporter view; Presets and the info
    /// line into the footer. The objects stay the controller's.
    private func reparent() {
        let o = outlets
        func move(_ view: NSView, to parent: NSView) {
            guard view.superview !== parent else { return }
            view.removeFromSuperview()
            parent.addSubview(view)
        }
        move(o.lowMemoryButton, to: o.exporterView)
        move(o.compressionPopUp, to: o.exporterView)
        o.advancedOptionsView.isHidden = true
        for button in [o.refreshButton, o.deselectAllButton, o.selectAllButton] { move(button, to: o.exporterView) }
        move(o.presetsPopUp, to: o.contentView)
        move(o.formatInfoText, to: o.contentView)
    }

    private func addViews() {
        let o = outlets
        titleLabel.font = Self.titleFont
        formatSwitcher.titles = o.typeTabView.tabViewItems.map(\.label)
        formatSwitcher.accessibilityGroupLabel = NSLocalizedString("ClaudeExportFormatSwitcher", value: "Export format", comment: "export dialog: accessibility name of the format switcher")
        formatSwitcher.onSelect = { [weak tabView = o.typeTabView] index in
            tabView?.selectTabViewItem(at: index)
        }
        for view in [titleLabel, formatSwitcher] as [NSView] { o.contentView.addSubview(view) }

        // Above the theme surface the window skin adds, below every control.
        for card in [saveCard, rightCard, leftCard] {
            card.radius = Layout.cardRadius
            o.exporterView.addSubview(card, positioned: .below, relativeTo: nil)
        }
        for title in [leftTitle, optionsTitle, saveTitle] {
            title.font = Self.sectionFont
            title.lineBreakMode = .byTruncatingTail
        }
        sourceSwitcher.titles = [
            NSLocalizedString("ClaudeExportSourceTables", value: "Tables", comment: "export dialog: source switcher segment, export the marked tables"),
            NSLocalizedString("ClaudeExportSourceFiltered", value: "Filtered results", comment: "export dialog: source switcher segment, export the Content tab's filtered rows"),
            NSLocalizedString("ClaudeExportSourceQuery", value: "Query results", comment: "export dialog: source switcher segment, export the Query tab's result"),
        ]
        sourceSwitcher.accessibilityGroupLabel = NSLocalizedString("ClaudeExportSourceSwitcher", value: "Export source", comment: "export dialog: accessibility name of the source switcher")
        sourceSwitcher.onSelect = { [weak popUp = o.inputPopUp] segment in
            guard let popUp, Layout.popUpIndexForSegment.indices.contains(segment), let action = popUp.action else { return }
            popUp.selectItem(at: Layout.popUpIndexForSegment[segment])
            NSApp.sendAction(action, to: popUp.target, from: popUp)
        }
        for (glyph, symbol) in [(folderGlyph, "folder"), (fileGlyph, "doc")] {
            let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            image?.isTemplate = true
            glyph.image = image
            glyph.imageScaling = .scaleProportionallyDown
            glyph.setAccessibilityElement(false)
        }
        filenameLabel.font = Self.labelFont
        filenameLabel.lineBreakMode = .byTruncatingMiddle
        filenameLabel.usesSingleLineMode = true
        compressionLabel.font = Self.labelFont
        compressionLabel.lineBreakMode = .byTruncatingTail
        customiseButton.isBordered = false
        customiseButton.font = Self.labelFont
        SAClaudeHoverHighlighter.attach(to: customiseButton)

        let added: [NSView] = [leftTitle, optionsTitle, saveTitle, sourceSwitcher, folderGlyph, fileGlyph, filenameLabel,
                               customiseButton, compressionLabel]
        for view in added { o.exporterView.addSubview(view) }
    }

    /// One-off restyles of the XIB's controls (colours follow in `refresh`).
    private func restyle() {
        let o = outlets
        // Presets: wide enough for its title before the window skin first walks it, so it becomes a pill.
        o.presetsPopUp.item(at: 0)?.title = NSLocalizedString("ClaudeExportPresets", value: "Presets", comment: "export dialog: title of the saved settings pull-down")
        o.presetsPopUp.synchronizeTitleAndSelectedItem()
        o.presetsPopUp.frame.size.width = Layout.presetsWidth

        o.formatInfoText.font = Self.infoFont
        o.formatInfoText.lineBreakMode = .byTruncatingTail
        o.formatInfoText.usesSingleLineMode = true
        o.formatInfoText.cell?.wraps = false
        o.formatInfoText.cell?.truncatesLastVisibleLine = true

        if o.lowMemoryButton.toolTip == nil { o.lowMemoryButton.toolTip = o.lowMemoryButton.title }
        o.lowMemoryButton.title = NSLocalizedString("ClaudeExportLowMemory", value: "Low memory", comment: "export dialog: low memory export checkbox (the full explanation is its tooltip)")
        // The Claude checkbox cell now, not at the sheet skin's first walk (after the first layout): the layout
        // measures the cell that draws (its 14pt box and 12pt title), so the title never truncates.
        for checkbox in [o.lowMemoryButton, o.filePerTableCheck] { SAClaudeFilterCells.install(SAClaudeCheckboxCell.self, on: checkbox) }

        o.refreshButton.isBordered = false
        o.refreshButton.imagePosition = .imageOnly
        SAClaudeHoverHighlighter.attach(to: o.refreshButton)
        for button in [o.selectAllButton, o.deselectAllButton] {
            button.image = nil
            button.alternateImage = nil
            button.imagePosition = .noImage
            button.isBordered = false
            // The XIB's labelColor tint would override the muted attributed title once the button is borderless.
            button.contentTintColor = nil
            SAClaudeHoverHighlighter.attach(to: button)
        }

        let table = o.tableList
        table.rowHeight = 22
        for identifier in Self.checkboxColumns {
            guard let column = table.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier(identifier)) else { continue }
            column.maxWidth = Layout.checkboxColumnWidth
            column.minWidth = Layout.checkboxColumnWidth
            column.width = Layout.checkboxColumnWidth
            // The title above the centred box is centred too (`SAClaudeTableHeaderView` honours the header cell's alignment).
            column.headerCell.alignment = .center
            // Two XIB data cells carry IB's placeholder title "Check", clipped by the old 15pt columns; at 72pt it would
            // show beside every box. Title-less, the Claude checkbox is centred in its column.
            (column.dataCell as? NSButtonCell)?.title = ""
        }
    }

    private func observe() {
        let o = outlets
        for view in [o.exporterView, o.contentView] {
            view.postsFrameChangedNotifications = true
            frameObservers.append(NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: view, queue: nil) { [weak self] _ in
                Self.onMain { self?.layOut() }
            })
        }
        SAClaudeThemeWatcher.observe(self) { $0.refresh(force: false) }
        appearanceObservation = o.window.observe(\.effectiveAppearance) { [weak self] _, _ in
            Self.onMain { self?.refresh(force: true) }
        }
        SAClaudeAccent.observe(self) { $0.refresh(force: true) }
        // The controller hides checkbox columns as the SQL options change; the Table column takes their room.
        for identifier in Self.checkboxColumns {
            guard let column = o.tableList.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier(identifier)) else { continue }
            columnObservations.append(column.observe(\.isHidden) { [weak self] _, _ in
                Self.onMain { self?.outlets.tableList.sizeToFit() }
            })
        }
    }

    // MARK: - Updating

    /// Mirrors the controller's format and source into the switchers, the titles and the table headers, and lays out.
    private func update() {
        let o = outlets
        guard let item = o.typeTabView.selectedTabViewItem,
              let format = Layout.Format(rawValue: o.typeTabView.indexOfTabViewItem(item)) else { return }
        formatSwitcher.selectedIndex = format.rawValue
        let popUpEnabled = (0..<3).map { o.inputPopUp.item(at: $0)?.isEnabled ?? false }
        let segments = Layout.sourceSegments(format: format, popUpEnabled: popUpEnabled, popUpSelected: o.inputPopUp.indexOfSelectedItem)
        sourceSwitcher.enabledSegments = segments.enabled
        sourceSwitcher.selectedIndex = segments.selected
        optionsTitle.stringValue = String(format: NSLocalizedString("ClaudeExportOptionsTitle", value: "%@ options", comment: "export dialog: title of the options card, e.g. \"SQL options\""), item.label)

        // `_switchTab` blanks the content header for every format but SQL.
        let titles = Layout.columnTitles(for: format)
        for (identifier, title) in [("structure", titles.structure), ("content", titles.content), ("drop", titles.drop)] {
            o.tableList.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier(identifier))?.headerCell.stringValue = title
        }
        o.tableList.headerView?.needsDisplay = true

        closeFilenameEditor()
        styleGhostTitles()
        optionsStyler?.updateLabelStates()   // Task 3
        layOut()
        o.tableList.sizeToFit()
        chainKeyViews()
    }

    /// Task 4: toggles the custom filename editor panel; true when handled.
    private func toggleFilenameEditor() -> Bool {
        filenameEditor.toggle(relativeTo: customiseButton)
        return true
    }

    /// Task 4: closes the custom filename editor panel (format or source changed).
    private func closeFilenameEditor() { filenameEditor.close() }

    @objc private func customise(_ sender: Any?) {
        _ = toggleFilenameEditor()
    }

    // MARK: - Colours

    /// Re-derives the colours when the editor theme changed (always, when `force`) and recolours the added views.
    private func refresh(force: Bool) {
        let o = outlets
        var resolved: (SAClaudeEditorChrome.Palette, NSColor, NSColor)?
        o.window.effectiveAppearance.performAsCurrentDrawingAppearance {
            let palette = SAClaudeEditorChrome.palette(from: .standard)
            let theme = SAClaudeThemeColours.from(defaults: .standard)
            resolved = (palette, theme.text, SAClaudeFilterChrome.cardFill(text: theme.text, background: SAClaudeStatusChrome.popupSurface(theme: theme)))
        }
        guard let (palette, text, fill) = resolved else { return }
        guard force || palette != self.palette || text != themeText || fill != cardFill else { return }
        self.palette = palette
        themeText = text
        cardFill = fill
        let muted = palette.icon

        for card in [leftCard, rightCard, saveCard] {
            card.fill = fill
            card.stroke = palette.hairline
        }
        titleLabel.textColor = text
        filenameLabel.textColor = text
        for label in [leftTitle, optionsTitle, saveTitle, compressionLabel, o.formatInfoText] { label.textColor = muted }
        for glyph in [folderGlyph, fileGlyph] { glyph.contentTintColor = muted }
        optionsStyler?.recolour(muted: muted, text: text)   // Task 3
        filenameEditor.recolour(in: o.window.effectiveAppearance)   // Task 4
        progressStyler?.recolour(palette: palette)   // Task 5
        let switcherColours = SAClaudeConnectionTypeTabs.Colours(selectedFill: fill, selectedStroke: palette.hairline, hoverFill: palette.hover,
                                                                 text: text, mutedText: muted)
        formatSwitcher.colours = switcherColours
        sourceSwitcher.colours = switcherColours
        let refreshImage = SAClaudeGlyphs.image(.refresh, tint: muted)
        o.refreshButton.image = refreshImage
        o.refreshButton.alternateImage = refreshImage
        for button in [o.refreshButton, o.selectAllButton, o.deselectAllButton, customiseButton] {
            SAClaudeHoverHighlighter.setFillColour(palette.hover, for: button)
        }
        styleGhostTitles()
    }

    /// "All", "None" and "Customise" in SF Pro 12 muted, half strength while disabled (an attributed title doesn't dim).
    private func styleGhostTitles() {
        guard let muted = palette?.icon else { return }
        let o = outlets
        let titles: [(NSButton, String)] = [
            (o.selectAllButton, NSLocalizedString("ClaudeExportMarkAll", value: "All", comment: "export dialog: button that marks every table in the list")),
            (o.deselectAllButton, NSLocalizedString("ClaudeExportMarkNone", value: "None", comment: "export dialog: button that unmarks every table in the list")),
            (customiseButton, customiseButton.title),
        ]
        for (button, title) in titles {
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

        let w = Layout.window(in: o.contentView.bounds, switcherWidth: formatSwitcher.preferredWidth)
        Self.placeLabel(titleLabel, w.title)
        Self.place(formatSwitcher, w.formatSwitcher)
        if o.typeTabView.frame != w.body { o.typeTabView.frame = w.body }
        if o.typeTabView.autoresizingMask != [.width, .height] { o.typeTabView.autoresizingMask = [.width, .height] }
        // The selected item's view (the exporter view) fills the tab view.
        let content = o.typeTabView.contentRect
        if o.exporterView.superview === o.typeTabView, o.exporterView.frame != content { o.exporterView.frame = content }
        Self.place(o.presetsPopUp, w.presets)
        Self.placeLabel(o.formatInfoText, w.info)
        Self.place(o.cancelButton, w.cancel)
        Self.place(o.exportButton, w.export)

        let inputs = Layout.BodyInputs(
            sourceSwitcherWidth: sourceSwitcher.preferredWidth, showsFilePerTable: !o.filePerTableCheck.isHidden,
            allWidth: Self.ghostWidth(o.selectAllButton), noneWidth: Self.ghostWidth(o.deselectAllButton),
            customiseWidth: Self.ghostWidth(customiseButton), compressionLabelWidth: Self.cellWidth(compressionLabel),
            compressionWidth: Self.compressionWidth, lowMemoryWidth: Self.cellWidth(o.lowMemoryButton))
        let b = Layout.body(in: o.exporterView.bounds, inputs)
        Self.place(leftCard, b.leftCard)
        Self.place(rightCard, b.rightCard)
        Self.place(saveCard, b.saveCard)
        Self.placeLabel(leftTitle, b.leftTitle)
        Self.placeLabel(optionsTitle, b.rightTitle)
        Self.placeLabel(saveTitle, b.saveTitle)
        Self.place(sourceSwitcher, b.sourceSwitcher)
        if b.filePerTable.height > 0 { Self.place(o.filePerTableCheck, b.filePerTable) }
        Self.place(o.tableListScrollView, b.tableList)
        Self.place(o.tableListButtonBar, b.bar)
        Self.place(o.refreshButton, b.refresh)
        Self.place(o.deselectAllButton, b.none)
        Self.place(o.selectAllButton, b.all)
        Self.place(o.optionsTabView, b.options)
        Self.place(o.pathField, b.path)
        Self.place(o.changeButton, b.change)
        Self.place(folderGlyph, b.folderGlyph)
        Self.place(fileGlyph, b.fileGlyph)
        Self.placeLabel(filenameLabel, b.filename)
        Self.place(customiseButton, b.customise)
        Self.placeLabel(compressionLabel, b.compressionLabel)
        Self.place(o.compressionPopUp, b.compression)
        Self.place(o.lowMemoryButton, b.lowMemory)
        layOutOptions()
    }

    /// Task 3: places the selected options item's controls in the options card.
    private func layOutOptions() { optionsStyler?.layOut() }

    /// Task 3: the options card's controls, top to bottom, for the key view loop.
    private var optionsKeyViews: [NSView] { optionsStyler?.keyViews ?? [] }

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

    /// Format → source → table → options → path → Change… → Customise → compression → Low memory → Presets →
    /// Cancel → Export, and back to the format switcher.
    private func chainKeyViews() {
        let o = outlets
        let chain: [NSView] = [formatSwitcher, sourceSwitcher, o.tableList] + optionsKeyViews
            + [o.pathField, o.changeButton, customiseButton, o.compressionPopUp, o.lowMemoryButton, o.presetsPopUp, o.cancelButton, o.exportButton]
        var pairs = Array(zip(chain, chain.dropFirst()))
        if let first = chain.first, let last = chain.last { pairs.append((last, first)) }
        for (view, next) in pairs where view.nextKeyView !== next || next.previousKeyView !== view {
            // Re-setting the same next view may not touch its previous view: clear first.
            if view.nextKeyView === next { view.nextKeyView = nil }
            view.nextKeyView = next
        }
    }
}
