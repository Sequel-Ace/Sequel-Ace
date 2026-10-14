//
//  SAClaudeImportOptionsStyler.swift
//  Sequel Ace
//
//  The CSV field mapping sheet's Options card: "First line contains field names", the import method switcher
//  (INSERT · REPLACE · UPDATE, driving the hidden method pop-up), "Align by" with its pill, then a "<Method> options"
//  group holding the current method's advanced options, always visible. The advanced views' checkboxes (and
//  INSERT's ON DUPLICATE KEY UPDATE text view) are re-parented once into the sheet and the current method's shown;
//  the advanced views stay hidden. The controller keeps resetting the options and their mutual exclusion. Also the
//  Global values child sheet's light polish (glyph +/-, the Insert pill, the table's quiet grid look). Owned by
//  `SAClaudeImportMapperStyler`, which calls it from its update, layout, refresh and key-view steps. App target only.
//

import AppKit

final class SAClaudeImportOptionsStyler {

    private typealias Rows = SAClaudeExportLayout

    private static let titleFont = NSFont.systemFont(ofSize: 11)
    private static let labelFont = NSFont.systemFont(ofSize: 12)
    private static let labelWidth: CGFloat = 74
    private static let alignPopUpWidth: CGFloat = 200
    private static let inlineGap: CGFloat = 6
    private static let checkboxHeight: CGFloat = 18
    private static let pillHeight: CGFloat = 24
    /// Three lines of the ON DUPLICATE KEY UPDATE text view.
    private static let textHeight: CGFloat = 54
    private static let textRadius: CGFloat = 7
    private static let textInset = NSSize(width: 4, height: 4)
    /// The method pop-up's item tags: INSERT, REPLACE, UPDATE (the switcher's segments, in order).
    private static let methodTags = [0, 1, 2]

    /// One row of the card.
    private enum Item {
        case checkbox(NSButton)
        case method
        case align
        case methodTitle
        /// INSERT's ON DUPLICATE KEY UPDATE text view, under its checkbox.
        case onUpdateText

        var spec: Rows.OptionRow { if case .methodTitle = self { return .title } else { return .control(indented: false) } }
    }

    /// The controller's views this styler moves or restyles, read once by KVC.
    private struct Outlets {
        let headerSwitch: NSButton
        let methodLabel: NSTextField
        let methodPopUp: NSPopUpButton
        let alignLabel: NSTextField
        let alignPopUp: NSPopUpButton
        let advancedViews: [NSView]
        let onUpdateTextView: NSTextView
        let onUpdateScrollView: NSScrollView
        /// Each method's rows, by its pop-up tag.
        let methodItems: [[Item]]

        init?(_ c: NSObject, container: NSView) {
            func outlet<T>(_ key: String) -> T? { SAClaudeExportStyler.outlet(c, key) }
            func checkboxes(_ keys: [String], in view: NSView) -> [NSButton]? {
                let buttons = keys.compactMap { outlet($0) as NSButton? }
                return buttons.count == keys.count && buttons.allSatisfy({ $0.superview === view }) ? buttons : nil
            }
            guard let headerSwitch: NSButton = outlet("importFieldNamesHeaderSwitch"),
                  let methodLabel: NSTextField = outlet("importMethodLabel"),
                  let methodPopUp: NSPopUpButton = outlet("importMethodPopup"),
                  let alignLabel: NSTextField = outlet("alignByPopupLabel"),
                  let alignPopUp: NSPopUpButton = outlet("alignByPopup"),
                  [headerSwitch, methodLabel, methodPopUp, alignLabel, alignPopUp].allSatisfy({ $0.superview === container }),
                  Self.hasMethodItems(methodPopUp),
                  let insertView: NSView = outlet("advancedInsertView"),
                  let replaceView: NSView = outlet("advancedReplaceView"),
                  let updateView: NSView = outlet("advancedUpdateView"),
                  let insert = checkboxes(["lowPriorityCheckBox", "delayedCheckBox", "highPriorityCheckBox", "ignoreCheckBox",
                                           "onupdateCheckBox", "skipexistingRowsCheckBox"], in: insertView),
                  let replace = checkboxes(["lowPriorityReplaceCheckBox", "delayedReplaceCheckBox"], in: replaceView),
                  let update = checkboxes(["lowPriorityUpdateCheckBox", "ignoreUpdateCheckBox", "addRemainingDataSwitch"], in: updateView),
                  let onUpdateTextView: NSTextView = outlet("onupdateTextView"),
                  let onUpdateScrollView = onUpdateTextView.enclosingScrollView, onUpdateScrollView.superview === insertView
            else { return nil }
            self.headerSwitch = headerSwitch
            self.methodLabel = methodLabel
            self.methodPopUp = methodPopUp
            self.alignLabel = alignLabel
            self.alignPopUp = alignPopUp
            advancedViews = [insertView, replaceView, updateView]
            self.onUpdateTextView = onUpdateTextView
            self.onUpdateScrollView = onUpdateScrollView
            // INSERT: LOW_PRIORITY, DELAYED, HIGH_PRIORITY, IGNORE, ON DUPLICATE KEY UPDATE + its text, Skip existing rows.
            methodItems = [
                insert.prefix(5).map { Item.checkbox($0) } + [.onUpdateText, .checkbox(insert[5])],
                replace.map { Item.checkbox($0) },
                update.map { Item.checkbox($0) },
            ]
        }

        /// The pop-up carries the INSERT, REPLACE and UPDATE tags.
        private static func hasMethodItems(_ popUp: NSPopUpButton) -> Bool {
            SAClaudeImportOptionsStyler.methodTags.allSatisfy { popUp.menu?.item(withTag: $0) != nil }
        }

        /// Every view a method row shows (checkboxes, and the text view's scroll view).
        func views(of items: [Item]) -> [NSView] {
            items.compactMap { item in
                switch item {
                case .checkbox(let button): return button
                case .onUpdateText: return onUpdateScrollView
                default: return nil
                }
            }
        }
    }

    /// The Global values sheet's controls this styler polishes (nil: the sheet keeps the generic skin).
    private struct GlobalValues {
        let addButton: NSButton
        let removeButton: NSButton
        let insertPullDown: NSPopUpButton
        /// Optional: without it the table keeps the XIB's source-list look.
        let table: NSTableView?

        init?(_ c: NSObject) {
            guard let addButton: NSButton = SAClaudeExportStyler.outlet(c, "addGlobalValueButton"),
                  let removeButton: NSButton = SAClaudeExportStyler.outlet(c, "removeGlobalValueButton"),
                  let insertPullDown: NSPopUpButton = SAClaudeExportStyler.outlet(c, "insertPullDownButton") else { return nil }
            self.addButton = addButton
            self.removeButton = removeButton
            self.insertPullDown = insertPullDown
            table = SAClaudeExportStyler.outlet(c, "globalValuesTableView")
        }
    }

    private let outlets: Outlets
    private let globalValues: GlobalValues?
    private let container: NSView
    /// In new-table mode (the controller shows the name field) only INSERT is possible.
    private let newTableNameField: NSTextField

    // Added views.
    private let switcher = SAClaudeConnectionTypeTabs()
    private let methodRowLabel = NSTextField(labelWithString: NSLocalizedString("ClaudeImportMethod", value: "Method", comment: "import field mapping sheet: label before the import method switcher (INSERT · REPLACE · UPDATE)"))
    private let alignRowLabel = NSTextField(labelWithString: NSLocalizedString("ClaudeImportAlignBy", value: "Align by", comment: "import field mapping sheet: label before the pop-up choosing how CSV fields are aligned to the table's columns"))
    private let methodTitle = NSTextField(labelWithString: "")
    /// The ON DUPLICATE KEY UPDATE text view's hairline frame; its fill is the view's background.
    private let textFrame = SAClaudeTableInfoCardView()

    private var fills: (field: NSColor, card: NSColor)?
    private var editableObservation: NSKeyValueObservation?

    // MARK: - Building

    /// The options card of `controller`'s sheet (`container` is its content view), or nil when an expected outlet is
    /// missing or a control is not where the XIB has it.
    init?(controller: NSObject, container: NSView, newTableNameField: NSTextField) {
        guard let outlets = Outlets(controller, container: container) else { return nil }
        self.outlets = outlets
        self.container = container
        self.newTableNameField = newTableNameField
        globalValues = GlobalValues(controller)
        install()
    }

    deinit {
        editableObservation?.invalidate()
    }

    private func install() {
        let o = outlets
        // The switcher and the new labels replace the method pop-up and the XIB's labels.
        for view: NSView in [o.methodLabel, o.alignLabel, o.methodPopUp] { view.isHidden = true }

        switcher.titles = Self.methodTags.map { o.methodPopUp.menu?.item(withTag: $0)?.title ?? "" }
        switcher.accessibilityGroupLabel = NSLocalizedString("ClaudeImportMethodSwitcher", value: "Import method", comment: "import field mapping sheet: accessibility name of the INSERT / REPLACE / UPDATE switcher")
        switcher.onSelect = { [weak popUp = o.methodPopUp] index in
            guard let popUp, Self.methodTags.indices.contains(index), popUp.selectItem(withTag: Self.methodTags[index]),
                  let action = popUp.action else { return }
            // The controller resets the options and calls back (`controllerDidUpdate:`), which shows the method's rows.
            NSApp.sendAction(action, to: popUp.target, from: popUp)
        }
        for label in [methodRowLabel, alignRowLabel] {
            label.font = Self.labelFont
            label.lineBreakMode = .byTruncatingTail
        }
        methodTitle.font = Self.titleFont
        methodTitle.lineBreakMode = .byTruncatingTail
        for view in [switcher, methodRowLabel, alignRowLabel, methodTitle] as [NSView] { container.addSubview(view) }
        o.alignPopUp.setAccessibilityTitleUIElement(alignRowLabel)
        SAClaudeFilterCells.installPill(on: o.alignPopUp)

        // The methods' options move into the sheet, once; the advanced views stay hidden (and empty).
        textFrame.radius = Self.textRadius
        container.addSubview(textFrame)
        for view in o.methodItems.flatMap(o.views(of:)) {
            view.removeFromSuperview()
            container.addSubview(view)
        }
        for view in o.advancedViews where !view.isHidden { view.isHidden = true }
        // The Claude checkbox cell now, not at the sheet skin's first walk: the rows measure the cell that draws.
        let checkboxes = [o.headerSwitch] + o.methodItems.flatMap { $0 }.compactMap { item -> NSButton? in
            if case .checkbox(let button) = item { return button } else { return nil }
        }
        for checkbox in checkboxes { SAClaudeFilterCells.install(SAClaudeCheckboxCell.self, on: checkbox) }

        // The text view draws no background: its frame's fill shows (the controller's lightGray / white writes and the
        // skin's theme background are not drawn), and follows its editable state.
        let scrollView = o.onUpdateScrollView
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        o.onUpdateTextView.drawsBackground = false
        o.onUpdateTextView.textContainerInset = Self.textInset
        editableObservation = o.onUpdateTextView.observe(\.isEditable) { [weak self] _, _ in
            Self.onMain { self?.applyTextFill() }
        }

        if let g = globalValues {
            for button in [g.addButton, g.removeButton] {
                button.isBordered = false
                button.imagePosition = .imageOnly
                button.imageScaling = .scaleNone
                SAClaudeHoverHighlighter.attach(to: button)
            }
            SAClaudeFilterCells.installPill(on: g.insertPullDown)
            if let table = g.table {
                // The generic skin leaves source lists (and their private background colour) alone. As a regular
                // table on a system background it gives this one the quiet grid look when the sheet begins: the theme
                // background (kept in step with the theme), no alternating rows, hairline grid colour, the Claude
                // header; the selection is the regular highlight, its text inverting as AppKit's does.
                table.selectionHighlightStyle = .regular
                table.usesAlternatingRowBackgroundColors = false
                table.backgroundColor = .controlBackgroundColor
            }
        }
    }

    private static func onMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
    }

    // MARK: - Updating

    /// The pop-up's tag of the current method (INSERT when none is selected).
    private var currentTag: Int {
        let tag = outlets.methodPopUp.selectedTag()
        return Self.methodTags.contains(tag) ? tag : 0
    }

    /// Follows the controller: the switcher's segments and selection, the group title, the current method's rows
    /// (the others hidden) and the text view's fill. Call before laying out.
    func update() {
        let o = outlets
        let segments = SAClaudeImportMapperLayout.methodSegments(
            itemEnabled: Self.methodTags.map { o.methodPopUp.menu?.item(withTag: $0)?.isEnabled ?? false },
            selectedTag: o.methodPopUp.selectedTag(), newTableMode: !newTableNameField.isHidden)
        switcher.enabledSegments = segments.enabled
        switcher.selectedIndex = segments.selected

        let method = o.methodPopUp.menu?.item(withTag: currentTag)?.title ?? ""
        let title = String(format: NSLocalizedString("ClaudeImportMethodOptions", value: "%@ options", comment: "import field mapping sheet: title of the group with the import method's options, e.g. \"INSERT options\""), method)
        if methodTitle.stringValue != title { methodTitle.stringValue = title }

        for (index, items) in o.methodItems.enumerated() {
            let hidden = Self.methodTags[index] != currentTag
            for view in o.views(of: items) where view.isHidden != hidden { view.isHidden = hidden }
        }
        if textFrame.isHidden != o.onUpdateScrollView.isHidden { textFrame.isHidden = o.onUpdateScrollView.isHidden }
        for view in o.advancedViews where !view.isHidden { view.isHidden = true }
        applyTextFill()
    }

    /// The field fill while the text view is editable, the card's when it is not.
    private func applyTextFill() {
        guard let fills else { return }
        let fill = outlets.onUpdateTextView.isEditable ? fills.field : fills.card
        if textFrame.fill != fill { textFrame.fill = fill }
    }

    // MARK: - Colours

    func recolour(palette: SAClaudeEditorChrome.Palette, text: NSColor, cardFill: NSColor, fieldFill: NSColor) {
        let muted = palette.icon
        for label in [methodRowLabel, alignRowLabel, methodTitle] where label.textColor != muted { label.textColor = muted }
        switcher.colours = SAClaudeConnectionTypeTabs.Colours(selectedFill: cardFill, selectedStroke: palette.hairline, hoverFill: palette.hover,
                                                              text: text, mutedText: muted)
        textFrame.stroke = palette.hairline
        fills = (fieldFill, cardFill)
        applyTextFill()
        let font = SAClaudeCompletionStyler.editorFont()
        if outlets.onUpdateTextView.font != font { outlets.onUpdateTextView.font = font }

        if let g = globalValues {
            for (button, glyph) in [(g.addButton, SAClaudeGlyph.add), (g.removeButton, .remove)] {
                let image = SAClaudeGlyphs.image(glyph, tint: muted)
                button.image = image
                button.alternateImage = image
                SAClaudeHoverHighlighter.setFillColour(palette.hover, for: button)
            }
        }
    }

    // MARK: - Layout

    /// Places the card's rows top-down in `rect` (the Options card below its title).
    func layOut(in rect: NSRect) {
        let items: [Item] = [.checkbox(outlets.headerSwitch), .method, .align, .methodTitle] + outlets.methodItems[currentTag]
        var top = rect.maxY
        var segment: [Item] = []
        // The rows run in segments around the taller text view (`optionRows` stacks rows of one height).
        func placeSegment() {
            guard !segment.isEmpty else { return }
            let area = NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: max(0, top - rect.minY))
            let frames = Rows.optionRows(segment.map(\.spec), in: area)
            for (item, frame) in zip(segment, frames) { place(item, frame) }
            top = (frames.last?.minY ?? top) - Rows.rowGap
            segment = []
        }
        for item in items {
            guard case .onUpdateText = item else { segment.append(item); continue }
            placeSegment()
            let x = rect.minX + Rows.indent
            let frame = NSRect(x: x, y: top - Self.textHeight, width: max(0, rect.maxX - x), height: Self.textHeight)
            Self.place(textFrame, frame)
            Self.place(outlets.onUpdateScrollView, frame.insetBy(dx: 1, dy: 1))
            top = frame.minY - Rows.rowGap
        }
        placeSegment()
    }

    private func place(_ item: Item, _ frame: NSRect) {
        let o = outlets
        switch item {
        case .checkbox(let button):
            let width = min(ceil(button.cell?.cellSize.width ?? frame.width), frame.width)
            Self.place(button, NSRect(x: frame.minX, y: frame.midY - Self.checkboxHeight / 2, width: width, height: Self.checkboxHeight))
        case .method:
            let x = Self.placeRowLabel(methodRowLabel, frame)
            let height = SAClaudeConnectionTypeTabs.height
            Self.place(switcher, NSRect(x: x, y: frame.midY - height / 2, width: min(ceil(switcher.preferredWidth), max(0, frame.maxX - x)), height: height))
        case .align:
            let x = Self.placeRowLabel(alignRowLabel, frame)
            Self.place(o.alignPopUp, NSRect(x: x, y: frame.midY - Self.pillHeight / 2, width: min(Self.alignPopUpWidth, max(0, frame.maxX - x)),
                                            height: Self.pillHeight))
        case .methodTitle:
            Self.placeLabel(methodTitle, frame)
        case .onUpdateText:
            break
        }
    }

    /// Places a row's label in its 74pt column; returns where the row's control starts.
    private static func placeRowLabel(_ label: NSTextField, _ frame: NSRect) -> CGFloat {
        let width = min(labelWidth, frame.width)
        placeLabel(label, NSRect(x: frame.minX, y: frame.minY, width: width, height: frame.height))
        return frame.minX + width + inlineGap
    }

    /// First line → Method → Align by → the current method's options, for the key view loop.
    var keyViews: [NSView] {
        let o = outlets
        let options: [NSView] = o.methodItems[currentTag].compactMap { item in
            switch item {
            case .checkbox(let button): return button
            case .onUpdateText: return o.onUpdateTextView
            default: return nil
            }
        }
        return [o.headerSwitch, switcher, o.alignPopUp] + options
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
}
