//
//  SAClaudeServerVariablesStyler.swift
//  Sequel Ace
//
//  The Server Variables sheet in the Claude look (spec 2026-10-18-claude-utility-windows-design.md, section B): the
//  list in the Claude grid (theme selection, hover, 30pt header) with the search hits highlighted in names and values,
//  a header row with the title, the controller's "N of M" and the search field, a strip under the list showing the
//  selected variable's full value (mono, wrapped, selectable) with Copy, and Save As… / Close as Claude buttons.
//  Claimed by owner identity (`SPServerVariablesController`, its window and outlets); the XIB is not edited — its
//  views are re-laid out and its table becomes `SAClaudeServerVariablesTableView` in place. Filtering, "N of M",
//  Save As…, Close and the Copy menu stay the controller's. App target only.
//

import AppKit
import SwiftUI

// MARK: - Table

/// The XIB's table, its class swapped in place: the shared Claude grid (`SAClaudeUtilityGridTableView`). The styler gives
/// it the search hits in each cell and the reload notices that keep the selection on the same variables, through the
/// grid's hooks; the subclass only names the table (the generic sheet skin and the harness tell it by its class).
@objc(SAClaudeServerVariablesTableView) final class SAClaudeServerVariablesTableView: SAClaudeUtilityGridTableView {

    /// Turns the plain XIB table into this class and installs the grid look; nil when it can't (another class, or the
    /// table is observed by KVO, `SAClaudeClassSwap`).
    static func adopt(_ table: NSTableView) -> SAClaudeServerVariablesTableView? {
        SAClaudeUtilityGridTableView.adopt(table, as: SAClaudeServerVariablesTableView.self) as? SAClaudeServerVariablesTableView
    }
}

/// A grid cell's attributed text.
enum SAClaudeServerVariablesCellText {

    private static var fonts: [String: NSFont] = [:]

    /// The accent at the Record View search's highlight strength (`SAClaudeSwiftUIPalette.highlightAlpha`, which is
    /// main-actor isolated; the cells are drawn on main but this enum is not).
    static let highlightAlpha: CGFloat = 0.28
    static var highlight: NSColor { SAClaudeAccent.accent.withAlphaComponent(highlightAlpha) }

    /// Room the cell's text inset and the truncation ellipsis take from its frame.
    private static let textInset: CGFloat = 16

    /// `width` is the cell's frame width: a first hit past it brings the excerpt from just before it.
    static func attributed(_ text: String, font: NSFont?, colour: NSColor, filter: String, width: CGFloat) -> NSAttributedString {
        var line = SAClaudeServerVariablesSearch.singleLine(text)
        let font = valueFont(font)
        var ranges = SAClaudeServerVariablesSearch.ranges(of: filter, in: line)
        if let first = ranges.first, first.location > SAClaudeServerVariablesSearch.excerptLead {
            let throughHit = (line as NSString).substring(to: NSMaxRange(first)) as NSString
            if throughHit.size(withAttributes: [.font: font]).width > width - textInset {
                (line, ranges) = SAClaudeServerVariablesSearch.excerpt(line, ranges: ranges)
            }
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let result = NSMutableAttributedString(string: line, attributes: [.font: font, .foregroundColor: colour, .paragraphStyle: paragraph])
        if !ranges.isEmpty {
            let highlight = Self.highlight
            for range in ranges { result.addAttribute(.backgroundColor, value: highlight, range: range) }
        }
        return result
    }

    /// The grid's value font (upright, tabular digits) for the table font the controller gives the cells.
    private static func valueFont(_ font: NSFont?) -> NSFont {
        let base = font ?? NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        let key = "\(base.fontName)|\(base.pointSize)"
        if let cached = fonts[key] { return cached }
        let value = SAClaudeGridChrome.valueFont(base)
        fonts[key] = value
        return value
    }
}

// MARK: - Styler

@MainActor
@objc(SAClaudeServerVariablesStyler) final class SAClaudeServerVariablesStyler: NSObject {

    private typealias Layout = SAClaudeServerVariablesLayout

    private static var associationKey: UInt8 = 0
    private static let titleFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
    private static let countFont = NSFont.systemFont(ofSize: 11)
    private static let fieldFont = NSFont.systemFont(ofSize: 13)
    private static let buttonFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)
    private static let nameColumnWidth: CGFloat = 260

    private weak var window: NSWindow?
    private weak var table: SAClaudeServerVariablesTableView?
    private weak var searchField: NSSearchField?
    private weak var countField: NSTextField?
    private weak var titleField: NSTextField?
    private weak var saveButton: NSButton?
    private weak var closeButton: NSButton?
    private let topLine = SAClaudeDividerLine(frame: .zero)
    private let bottomLine = SAClaudeDividerLine(frame: .zero)
    private let palette = SAClaudeSwiftUIPalette(source: .app)
    let detailModel = SAClaudeServerVariablesDetailModel()
    /// Where Copy writes (the general pasteboard; a harness gives its own).
    var pasteboard = NSPasteboard.general
    private let detailHost: NSHostingView<AnyView>
    private var observers: [NSObjectProtocol] = []

    /// The variables the user selected, kept by name: reloads re-select them where they are now, and one filtered out
    /// comes back selected when the filter shows it again.
    private var selectedNames: [String] = []
    /// Set while the table reloads or the styler re-selects: those selection changes are not the user's.
    private var isRestoring = false

    private init(window: NSWindow) {
        self.window = window
        detailHost = NSHostingView(rootView: AnyView(EmptyView()))
        super.init()
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    // MARK: Claiming

    /// Claims `window` when it is a `SPServerVariablesController`'s sheet (by identity: the controller's own window, its
    /// outlets inside it) and lays it out; a window already claimed is laid out again. Called by the controller before
    /// the sheet begins and by the generic sheet skin each time it considers a window. Anything missing leaves the
    /// window in the generic skin.
    @objc(claimWindow:) static func claim(_ window: NSWindow?) {
        guard let window else { return }
        if let styler = styler(for: window) {
            styler.apply()
            return
        }
        guard let controller = window.windowController,
              SAClaudeFormOwners.className(of: controller) == "SPServerVariablesController",
              controller.window === window, let contentView = window.contentView,
              let table: NSTableView = SAClaudeFormRecipes.outlet(controller, "variablesTableView"),
              let searchField: NSSearchField = SAClaudeFormRecipes.outlet(controller, "filterVariablesSearchField"),
              let countField: NSTextField = SAClaudeFormRecipes.outlet(controller, "variablesCountTextField"),
              let saveButton: NSButton = SAClaudeFormRecipes.outlet(controller, "saveVariablesButton"),
              [table, searchField, countField, saveButton].allSatisfy({ $0.window === window }),
              table.enclosingScrollView?.superview === contentView,
              let closeButton = button(in: contentView, action: #selector(SPServerVariablesActions.closeSheet(_:))),
              let adopted = SAClaudeServerVariablesTableView.adopt(table) else { return }

        let styler = SAClaudeServerVariablesStyler(window: window)
        objc_setAssociatedObject(window, &associationKey, styler, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        styler.table = adopted
        styler.searchField = searchField
        styler.countField = countField
        styler.saveButton = saveButton
        styler.closeButton = closeButton
        styler.titleField = contentView.subviews.compactMap { $0 as? NSTextField }.first {
            $0 !== countField && !($0 is NSSearchField) && !$0.isEditable && !$0.isBezeled
        }
        styler.build(contentView: contentView)
        styler.apply()
    }

    /// The styler that claimed `window`, if any.
    static func styler(for window: NSWindow) -> SAClaudeServerVariablesStyler? {
        objc_getAssociatedObject(window, &associationKey) as? SAClaudeServerVariablesStyler
    }

    private static func button(in view: NSView, action: Selector) -> NSButton? {
        view.subviews.compactMap { $0 as? NSButton }.first { $0.action == action }
    }

    // MARK: Building

    private func build(contentView: NSView) {
        guard let window, let table else { return }

        // The sheet opens bigger than the XIB's 433×341 when its size is below the new minimum.
        window.contentMinSize = Layout.minimumSize
        let size = contentView.bounds.size
        if size.width < Layout.minimumSize.width || size.height < Layout.minimumSize.height {
            window.setContentSize(NSSize(width: max(size.width, Layout.preferredSize.width), height: max(size.height, Layout.preferredSize.height)))
        }

        for line in [topLine, bottomLine] where line.superview == nil {
            contentView.addSubview(line)
        }
        detailHost.sizingOptions = []
        detailHost.rootView = AnyView(SAClaudeServerVariablesDetailPanel(model: detailModel).environmentObject(palette))
        detailHost.setAccessibilityElement(false)
        contentView.addSubview(detailHost)

        if let scrollView = table.enclosingScrollView {
            scrollView.borderType = .noBorder
            scrollView.hasHorizontalScroller = false
        }
        // The value column fills what the name column leaves.
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        if let nameColumn = table.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier(SAClaudeServerVariablesColumns.name)) {
            nameColumn.width = Self.nameColumnWidth
        }

        if let titleField {
            titleField.font = Self.titleFont
            titleField.lineBreakMode = .byTruncatingTail
            titleField.cell?.isScrollable = false
        }
        if let countField {
            countField.font = Self.countFont
            countField.alignment = .right
            countField.lineBreakMode = .byTruncatingHead
            countField.cell?.isScrollable = false
        }
        if let searchField {
            searchField.controlSize = .regular
            searchField.font = Self.fieldFont
        }
        for button in [saveButton, closeButton].compactMap({ $0 }) {
            button.controlSize = .regular
            button.font = Self.buttonFont
        }

        // Each cell's text in the theme text colour and the grid's value font, on one line, with the search hits washed
        // in the accent highlight (the Record View search's colour); a value whose first hit lies past the column's edge
        // shows from just before it.
        table.state?.prepareCell = { [weak self, weak table] cell, column, row in
            guard let table, let textCell = cell as? NSTextFieldCell, let palette = table.state?.renderer.palette else { return }
            textCell.attributedStringValue = SAClaudeServerVariablesCellText.attributed(
                textCell.stringValue, font: textCell.font, colour: palette.text, filter: self?.searchField?.stringValue ?? "",
                width: table.frameOfCell(atColumn: column, row: row).width)
        }
        table.state?.willReload = { [weak self] in self?.isRestoring = true }
        table.state?.didReload = { [weak self] in self?.tableReloaded() }
        detailModel.onCopy = { [weak self] in self?.copyDetail() }

        let centre = NotificationCenter.default
        observers.append(centre.addObserver(forName: NSTableView.selectionDidChangeNotification, object: table, queue: nil) { [weak self] _ in
            MainActor.assumeIsolated { self?.selectionChanged() }
        })
        observers.append(centre.addObserver(forName: NSView.frameDidChangeNotification, object: contentView, queue: nil) { [weak self] _ in
            MainActor.assumeIsolated { self?.layout() }
        })
        // AppKit may give the search field a new text label of its own when editing ends.
        observers.append(centre.addObserver(forName: NSControl.textDidEndEditingNotification, object: searchField, queue: nil) { [weak self] _ in
            MainActor.assumeIsolated { self?.hideNativeSearchText() }
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.hideNativeSearchText() } }
        })
        contentView.postsFrameChangedNotifications = true
        // The highlights are drawn in the accent; the hairlines follow the theme.
        SAClaudeAccent.observe(self) { styler in
            MainActor.assumeIsolated { styler.table?.needsDisplay = true }
        }
        SAClaudeThemeWatcher.observe(self) { styler in
            MainActor.assumeIsolated { styler.applyLineColour() }
        }
        updateDetail()
    }

    // MARK: Applying

    /// Lays the sheet out (idempotent; on every claim and resize).
    private func apply() {
        layout()
        table?.sizeLastColumnToFit()
        hideNativeSearchText()
        applyLineColour()
    }

    /// The hairlines above and below the list, in the sheets' hairline colour.
    private func applyLineColour() {
        let hairline = SAClaudeSheetColours.current().palette.hairline
        guard topLine.colourOverride != hairline else { return }
        topLine.colourOverride = hairline
        bottomLine.colourOverride = hairline
    }

    /// The private view macOS 26+ draws a text field's text with while it is not being edited. The Claude search cell
    /// draws the text (and placeholder) itself, so the label would draw it a second time, a few points off. AppKit
    /// hides and shows it as editing begins and ends, so it is made transparent rather than hidden; checked again
    /// whenever AppKit may have made a new one (each claim, editing end, filter reload).
    private static let nativeTextLabelClass = "NSTextFieldSimpleLabel"

    private func hideNativeSearchText() {
        guard let searchField else { return }
        for view in searchField.subviews where view.alphaValue != 0 && String(describing: type(of: view)) == Self.nativeTextLabelClass {
            view.alphaValue = 0
        }
    }

    private func layout() {
        guard let contentView = window?.contentView, let table, let scrollView = table.enclosingScrollView else { return }
        let inset = SAClaudeSheetButtonGeometry.metrics(for: .regular).classicSideMargin
        let frames = Layout.frames(in: contentView.bounds, saveWidth: buttonWidth(saveButton, titles: Self.saveTitles),
                                   closeWidth: buttonWidth(closeButton, titles: [closeButton?.title ?? ""]), buttonInset: inset)
        place(titleField, frames.title)
        place(countField, frames.count)
        place(searchField, frames.search)
        place(topLine, frames.topLine)
        place(scrollView, frames.table)
        place(bottomLine, frames.bottomLine)
        place(detailHost, frames.detail)
        place(saveButton, frames.save)
        place(closeButton, frames.close)
    }

    /// The controller titles Save "Save As..." or "Save View As..." as the filter changes: room for both.
    private static let saveTitles = ["Save As...", "Save View As..."]

    /// The title at the button font, the pill's padding and the classic margins either side; at least 84pt.
    private func buttonWidth(_ button: NSButton?, titles: [String]) -> CGFloat {
        guard let button else { return 0 }
        // The Claude button cells draw the title medium, at the button's font size.
        let medium = NSFont.systemFont(ofSize: (button.font ?? Self.buttonFont).pointSize, weight: .medium)
        let titleWidth = (titles + [button.title]).map { ceil(($0 as NSString).size(withAttributes: [.font: medium]).width) }.max() ?? 0
        let inset = SAClaudeSheetButtonGeometry.metrics(for: button.controlSize).classicSideMargin
        return max(84, titleWidth + 2 * SAClaudeFilterChrome.pillPadding + 2 * inset + 8)
    }

    private func place(_ view: NSView?, _ frame: NSRect) {
        guard let view else { return }
        if view.frame != frame { view.frame = frame }
        if !view.autoresizingMask.isEmpty { view.autoresizingMask = [] }
    }

    // MARK: Selection and detail

    private func selectionChanged() {
        guard !isRestoring, let table else { return }
        selectedNames = table.selectedRowIndexes.compactMap { variable(at: $0)?.name }
        updateDetail()
    }

    /// After every reload (filter keystroke, refresh on open): the remembered variables selected where they are now.
    private func tableReloaded() {
        defer {
            isRestoring = false
            updateDetail()
            hideNativeSearchText()
        }
        guard let table else { return }
        let visible = (0..<table.numberOfRows).map { variable(at: $0)?.name ?? "" }
        let rows = SAClaudeServerVariablesSelection.rows(selecting: selectedNames, in: visible)
        if rows != table.selectedRowIndexes { table.selectRowIndexes(rows, byExtendingSelection: false) }
    }

    private func updateDetail() {
        guard let table else { return }
        let selected = table.selectedRowIndexes.compactMap { variable(at: $0) }
        let detail = SAClaudeServerVariablesDetail.make(selected: selected, filter: searchField?.stringValue ?? "")
        if detailModel.detail != detail { detailModel.detail = detail }
    }

    /// The row's variable, read through the controller's data source (the same values the cells show).
    private func variable(at row: Int) -> SAClaudeServerVariable? {
        guard let table, row >= 0, row < table.numberOfRows, let source = table.dataSource,
              let nameColumn = table.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier(SAClaudeServerVariablesColumns.name)),
              let valueColumn = table.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier(SAClaudeServerVariablesColumns.value)),
              let name = source.tableView?(table, objectValueFor: nameColumn, row: row) as? String else { return nil }
        let value = source.tableView?(table, objectValueFor: valueColumn, row: row)
        return SAClaudeServerVariable(name: name, value: (value as? String) ?? (value is NSNull ? "NULL" : ""))
    }

    private func copyDetail() {
        guard let text = detailModel.detail?.copyText else { return }
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString(text, forType: .string)
    }
}

/// The XIB's column identifiers (the `SHOW VARIABLES` field names).
enum SAClaudeServerVariablesColumns {
    static let name = "Variable_name"
    static let value = "Value"
}

/// Selectors of the controller the styler looks for (the class has no Swift header).
@objc private protocol SPServerVariablesActions {
    func closeSheet(_ sender: Any?)
}

// MARK: - Detail strip

@MainActor
final class SAClaudeServerVariablesDetailModel: ObservableObject {
    @Published var detail: SAClaudeServerVariablesDetail?
    var onCopy: () -> Void = {}
}

/// The selected variable's name and full value (mono, wrapped, selectable, scrollable) with Copy; several selected show
/// one `name = value` line each.
struct SAClaudeServerVariablesDetailPanel: View {
    @EnvironmentObject var palette: SAClaudeSwiftUIPalette
    @ObservedObject var model: SAClaudeServerVariablesDetailModel

    var body: some View {
        Group {
            if let detail = model.detail {
                content(detail)
            } else {
                Text(NSLocalizedString("Select a variable to see its full value.", value: "Select a variable to see its full value.", comment: "server variables : strip under the list with nothing selected"))
                    .font(.system(size: 12))
                    .foregroundColor(palette.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        // No fill of its own: the sheet's surface (the skin's) shows through, so the strip and the footer match exactly.
    }

    private func content(_ detail: SAClaudeServerVariablesDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                title(detail)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(palette.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Spacer(minLength: 8)
                Button(detail.name != nil
                       ? NSLocalizedString("Copy value", value: "Copy value", comment: "server variables : copy the selected variable's full value")
                       : NSLocalizedString("Copy all", value: "Copy all", comment: "server variables : copy the selected variables as name = value lines")) { model.onCopy() }
                    .buttonStyle(SAClaudeSecondaryButtonStyle(size: .form))
            }
            SAClaudeServerVariablesValueBox(detail: detail)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func title(_ detail: SAClaudeServerVariablesDetail) -> Text {
        guard let name = detail.name else {
            return Text(String(format: NSLocalizedString("%lld variables selected", value: "%lld variables selected", comment: "server variables : strip title when several variables are selected"), Int64(detail.count)))
        }
        return Text(SAClaudeRecordHighlight.attributed(name, ranges: detail.nameRanges, highlight: palette.highlight))
    }
}

/// The value in a field-like box; an empty value says so.
struct SAClaudeServerVariablesValueBox: View {
    @EnvironmentObject var palette: SAClaudeSwiftUIPalette
    let detail: SAClaudeServerVariablesDetail

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: SAClaudeSheetColours.fieldRadius, style: .continuous)
        ZStack(alignment: .topLeading) {
            if detail.isEmptyValue {
                Text(NSLocalizedString("empty", value: "empty", comment: "server variables : the selected variable's value is the empty string"))
                    .font(.system(size: 12).italic())
                    .foregroundColor(palette.muted)
                    .padding(10)
            } else {
                SAClaudeServerVariablesValueText(text: detail.text, ranges: detail.textRanges, textColour: NSColor(palette.text),
                                                 highlight: NSColor(palette.highlight))
                    .padding(.vertical, 6)
                    .padding(.horizontal, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(shape.fill(palette.fieldFill))
        .overlay(shape.strokeBorder(palette.hairline, lineWidth: 1))
        .clipShape(shape)
    }
}

/// A read-only, selectable, wrapping NSTextView in a scroll view, mono 12pt, the search hits washed in the highlight.
/// The text is replaced only when something it shows changed, so the selection and scroll position survive redraws.
struct SAClaudeServerVariablesValueText: NSViewRepresentable {
    let text: String
    let ranges: [NSRange]
    let textColour: NSColor
    let highlight: NSColor

    static let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

    final class Coordinator {
        var shown: (text: String, ranges: [NSRange], colour: NSColor, highlight: NSColor)?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        if let textView = scrollView.documentView as? NSTextView {
            textView.isEditable = false
            textView.isSelectable = true
            textView.isRichText = false
            textView.drawsBackground = false
            textView.textContainerInset = NSSize(width: 4, height: 2)
            textView.textContainer?.widthTracksTextView = true
            textView.isAutomaticLinkDetectionEnabled = false
            textView.setAccessibilityLabel(NSLocalizedString("Variable value", value: "Variable value", comment: "server variables : accessibility name of the full value of the selected variable"))
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView, let storage = textView.textStorage else { return }
        let coordinator = context.coordinator
        if let shown = coordinator.shown, shown.text == text, shown.ranges == ranges, shown.colour == textColour, shown.highlight == highlight {
            return
        }
        let textChanged = coordinator.shown?.text != text
        let rangesChanged = coordinator.shown?.ranges != ranges
        coordinator.shown = (text, ranges, textColour, highlight)
        let attributed = NSMutableAttributedString(string: text, attributes: [.font: Self.font, .foregroundColor: textColour])
        let length = attributed.length
        for range in ranges where NSMaxRange(range) <= length {
            attributed.addAttribute(.backgroundColor, value: highlight, range: range)
        }
        let selection = textView.selectedRanges
        storage.setAttributedString(attributed)
        if textChanged {
            textView.scrollToBeginningOfDocument(nil)
        } else {
            textView.selectedRanges = selection
        }
        // The first hit in view (a long value's match may be far down), when the search or the value changed.
        if textChanged || rangesChanged, let first = ranges.first, NSMaxRange(first) <= length {
            textView.scrollRangeToVisible(first)
        }
    }
}
