//
//  SAClaudeExportOptionsStyler.swift
//  Sequel Ace
//
//  The Export sheet's format options card: the selected format's controls re-flowed into rows (group titles,
//  checkboxes, labelled inputs) from `SAClaudeExportLayout.optionRows`. The XIB's static labels are hidden and
//  replaced by this styler's own, one set per options item view. Owned by `SAClaudeExportStyler`, which calls it
//  from its layout, refresh, update and key-view seams. Any missing outlet: no options styler, and the card keeps
//  the XIB layout (styled by the sheet skin). App target only.
//

import AppKit

final class SAClaudeExportOptionsStyler: NSObject {

    private typealias Layout = SAClaudeExportLayout

    private static let titleFont = NSFont.systemFont(ofSize: 11)
    private static let labelFont = NSFont.systemFont(ofSize: 12)
    private static let inlineGap: CGFloat = 6
    private static let checkboxHeight: CGFloat = 18
    private static let fieldHeight: CGFloat = 22
    private static let pillHeight: CGFloat = 24
    private static let disabledAlpha: CGFloat = 0.5

    /// A control beside a row label, at a fixed size.
    private struct Input {
        let control: NSControl
        let width: CGFloat
        let height: CGFloat
    }

    private enum Row {
        case title(NSTextField)
        case checkbox(NSButton, indented: Bool)
        /// An optional label (`labelWidth` wide, or its fitting width when nil), then the inputs left to right.
        case inputs(label: NSTextField?, labelWidth: CGFloat?, [Input])

        var spec: Layout.OptionRow {
            switch self {
            case .title: return .title
            case .checkbox(_, let indented): return .control(indented: indented)
            case .inputs: return .control(indented: false)
            }
        }

        var controls: [NSView] {
            switch self {
            case .title: return []
            case .checkbox(let button, _): return [button]
            case .inputs(_, _, let inputs): return inputs.map(\.control)
            }
        }
    }

    /// One options tab item: its view and its rows, top to bottom.
    private struct Page {
        let view: NSView
        let rows: [Row]
    }

    private let tabView: NSTabView
    /// Keyed by the options tab item identifier ("sql", "csv", "xml", "dot").
    private let pages: [String: Page]
    private var titles: [NSTextField] = []
    /// Each row label and the input it names (its row's first).
    private var pairs: [(label: NSTextField, control: NSControl)] = []
    private var mutedColour: NSColor?
    private var textColour: NSColor?
    private var enabledObservations: [NSKeyValueObservation] = []

    // MARK: - Building

    /// The options styler for `controller`'s options tab view, or nil when an expected outlet or item view is missing
    /// or a control is not in its format's item view.
    init?(controller c: NSObject, tabView: NSTabView) {
        func itemView(_ identifier: String) -> NSView? {
            tabView.tabViewItems.first(where: { ($0.identifier as? String) == identifier })?.view
        }
        guard let sqlStructure: NSButton = Self.outlet(c, "exportSQLIncludeStructureCheck"),
              let sqlAutoIncrement: NSButton = Self.outlet(c, "exportSQLIncludeAutoIncrementValueButton"),
              let sqlDrop: NSButton = Self.outlet(c, "exportSQLIncludeDropSyntaxCheck"),
              let sqlContent: NSButton = Self.outlet(c, "exportSQLIncludeContentCheck"),
              let sqlErrors: NSButton = Self.outlet(c, "exportSQLIncludeErrorsCheck"),
              let sqlBLOBAsHex: NSButton = Self.outlet(c, "exportSQLBLOBFieldsAsHexCheck"),
              let sqlGenerated: NSButton = Self.outlet(c, "exportSQLIncludeGeneratedColumnsCheck"),
              let sqlUTF8BOM: NSButton = Self.outlet(c, "exportUseUTF8BOMButton"),
              let sqlInsertN: NSTextField = Self.outlet(c, "exportSQLInsertNValueTextField"),
              let sqlInsertDivider: NSPopUpButton = Self.outlet(c, "exportSQLInsertDividerPopUpButton"),
              let csvFieldNames: NSButton = Self.outlet(c, "exportCSVIncludeFieldNamesCheck"),
              let csvTerminated: NSComboBox = Self.outlet(c, "exportCSVFieldsTerminatedField"),
              let csvWrapped: NSComboBox = Self.outlet(c, "exportCSVFieldsWrappedField"),
              let csvEscaped: NSComboBox = Self.outlet(c, "exportCSVFieldsEscapedField"),
              let csvLines: NSComboBox = Self.outlet(c, "exportCSVLinesTerminatedField"),
              let csvNULL: NSTextField = Self.outlet(c, "exportCSVNULLValuesAsTextField"),
              let xmlFormat: NSPopUpButton = Self.outlet(c, "exportXMLFormatPopUpButton"),
              let xmlStructure: NSButton = Self.outlet(c, "exportXMLIncludeStructure"),
              let xmlContent: NSButton = Self.outlet(c, "exportXMLIncludeContent"),
              let xmlNULL: NSTextField = Self.outlet(c, "exportXMLNULLValuesAsTextField"),
              let dotLowerCase: NSButton = Self.outlet(c, "exportDotForceLowerTableNamesCheck"),
              let sqlView = itemView("sql"), let csvView = itemView("csv"), let xmlView = itemView("xml"), let dotView = itemView("dot"),
              ![sqlView, csvView, xmlView, dotView].contains(where: \.isFlipped) else { return nil }

        let include = NSLocalizedString("ClaudeExportOptInclude", value: "Include", comment: "export dialog options: group title, what the export includes (SQL, XML)")
        let nullValues = NSLocalizedString("ClaudeExportOptNullValues", value: "NULL values", comment: "export dialog options: group title, the text written for NULL values (CSV, XML)")
        let terminate = NSLocalizedString("ClaudeExportOptTerminate", value: "Terminate", comment: "export dialog options: CSV row label, the character that terminates fields or lines")
        let title = Self.makeTitle, label = Self.makeLabel
        func field(_ control: NSControl, _ width: CGFloat) -> Input { Input(control: control, width: width, height: Self.fieldHeight) }
        func pill(_ control: NSControl, _ width: CGFloat) -> Input { Input(control: control, width: width, height: Self.pillHeight) }

        let sql = Page(view: sqlView, rows: [
            .title(title(include)),
            .checkbox(sqlStructure, indented: false),
            .checkbox(sqlAutoIncrement, indented: true),
            .checkbox(sqlDrop, indented: true),
            .checkbox(sqlContent, indented: false),
            .checkbox(sqlErrors, indented: false),
            .title(title(NSLocalizedString("ClaudeExportOptOutput", value: "Output", comment: "export dialog options: SQL group title, how the output is written"))),
            .checkbox(sqlBLOBAsHex, indented: false),
            .checkbox(sqlGenerated, indented: false),
            .checkbox(sqlUTF8BOM, indented: false),
            .title(title(NSLocalizedString("ClaudeExportOptInsert", value: "INSERT", comment: "export dialog options: SQL group title, how INSERT statements are split"))),
            .inputs(label: label(NSLocalizedString("ClaudeExportOptInsertEvery", value: "New statement every", comment: "export dialog options: SQL row label before the number and unit (KiB of data / rows) after which a new INSERT statement starts")),
                    labelWidth: nil, [field(sqlInsertN, 60), pill(sqlInsertDivider, 100)]),
        ])
        let csv = Page(view: csvView, rows: [
            .checkbox(csvFieldNames, indented: false),
            .title(title(NSLocalizedString("ClaudeExportOptFields", value: "Fields", comment: "export dialog options: CSV group title, the field separator, enclosing and escape characters"))),
            .inputs(label: label(terminate), labelWidth: 80, [field(csvTerminated, 64)]),
            .inputs(label: label(NSLocalizedString("ClaudeExportOptWrap", value: "Wrap", comment: "export dialog options: CSV row label, the character that encloses fields")),
                    labelWidth: 80, [field(csvWrapped, 64)]),
            .inputs(label: label(NSLocalizedString("ClaudeExportOptEscape", value: "Escape", comment: "export dialog options: CSV row label, the character that escapes special characters")),
                    labelWidth: 80, [field(csvEscaped, 64)]),
            .title(title(NSLocalizedString("ClaudeExportOptLines", value: "Lines", comment: "export dialog options: CSV group title, the line terminator"))),
            .inputs(label: label(terminate), labelWidth: 80, [field(csvLines, 64)]),
            .title(title(nullValues)),
            .inputs(label: nil, labelWidth: nil, [field(csvNULL, 120)]),
        ])
        let xml = Page(view: xmlView, rows: [
            .inputs(label: label(NSLocalizedString("ClaudeExportOptFormat", value: "Format", comment: "export dialog options: XML row label before the schema pop-up (MySQL / Plain schema)")),
                    labelWidth: 80, [pill(xmlFormat, 150)]),
            .title(title(include)),
            .checkbox(xmlStructure, indented: false),
            .checkbox(xmlContent, indented: false),
            .title(title(nullValues)),
            .inputs(label: nil, labelWidth: nil, [field(xmlNULL, 120)]),
        ])
        let dot = Page(view: dotView, rows: [.checkbox(dotLowerCase, indented: false)])

        let pages = ["sql": sql, "csv": csv, "xml": xml, "dot": dot]
        // Every control must be its page's view's own subview: its frame is placed in that view's coordinates.
        guard pages.values.allSatisfy({ page in page.rows.allSatisfy { $0.controls.allSatisfy { $0.superview === page.view } } }) else { return nil }
        self.tabView = tabView
        self.pages = pages
        super.init()
        for page in pages.values { install(page) }
        observeEnabled()
    }

    deinit {
        enabledObservations.forEach { $0.invalidate() }
    }

    /// Hides the page's XIB static labels and adds this styler's.
    private func install(_ page: Page) {
        let controls = Set(page.rows.flatMap(\.controls).map(ObjectIdentifier.init))
        for case let field as NSTextField in page.view.subviews where !field.isEditable && !controls.contains(ObjectIdentifier(field)) {
            field.isHidden = true
        }
        for row in page.rows {
            switch row {
            case .title(let title):
                titles.append(title)
                page.view.addSubview(title)
            case .inputs(let label?, _, let inputs):
                if let first = inputs.first { pairs.append((label, first.control)) }
                page.view.addSubview(label)
            case .checkbox(let button, _):
                // The Claude checkbox cell before the first layout (the sheet skin's walk comes later): the row
                // measures the cell that draws (its 14pt box and 12pt title), so the title never truncates.
                SAClaudeFilterCells.install(SAClaudeCheckboxCell.self, on: button)
            default:
                break
            }
        }
    }

    /// A row label follows its input's enabled state as the controller toggles it (the SQL / XML options).
    private func observeEnabled() {
        // Not a pop-up: KVO subclasses the observed object, and the sheet skin never swaps the class of an observed
        // object (`SAClaudeClassSwap`), so the pop-up would lose its pill. The controller never disables the one
        // labelled pop-up (XML Format); `updateLabelStates()` still follows it on every controller update.
        for pair in pairs where !(pair.control is NSPopUpButton) {
            enabledObservations.append(pair.control.observe(\.isEnabled, options: [.initial, .new]) { [weak self, weak label = pair.label] control, _ in
                Self.onMain { [weak control] in
                    guard let self, let label, let control else { return }
                    self.colour(label, enabled: control.isEnabled)
                }
            })
        }
    }

    private static func makeTitle(_ string: String) -> NSTextField {
        let title = NSTextField(labelWithString: string)
        title.font = titleFont
        title.lineBreakMode = .byTruncatingTail
        return title
    }

    private static func makeLabel(_ string: String) -> NSTextField {
        let label = NSTextField(labelWithString: string)
        label.font = labelFont
        label.lineBreakMode = .byTruncatingTail
        return label
    }

    // MARK: - Colours

    /// Group titles muted; row labels in the theme text, muted at half strength beside a disabled input.
    func recolour(muted: NSColor, text: NSColor) {
        mutedColour = muted
        textColour = text
        for title in titles where title.textColor != muted { title.textColor = muted }
        updateLabelStates()
    }

    /// Re-reads every labelled input's enabled state (after the controller switched format or applied settings).
    func updateLabelStates() {
        for pair in pairs { colour(pair.label, enabled: pair.control.isEnabled) }
    }

    private func colour(_ label: NSTextField, enabled: Bool) {
        guard let textColour, let mutedColour else { return }
        let colour = enabled ? textColour : mutedColour.withAlphaComponent(Self.disabledAlpha)
        if label.textColor != colour { label.textColor = colour }
    }

    // MARK: - Layout

    /// Places the selected options item's rows, top-aligned in its view.
    func layOut() {
        guard let page = selectedPage else { return }
        let view = page.view
        // The item fills the tab view (`.noTabsNoBorder`).
        if view.superview === tabView, view.frame != tabView.contentRect { view.frame = tabView.contentRect }
        let frames = Layout.optionRows(page.rows.map(\.spec), in: view.bounds)
        for (row, frame) in zip(page.rows, frames) {
            switch row {
            case .title(let title):
                Self.placeLabel(title, frame)
            case .checkbox(let button, _):
                let width = min(ceil(button.cell?.cellSize.width ?? frame.width), frame.width)
                Self.place(button, NSRect(x: frame.minX, y: frame.midY - Self.checkboxHeight / 2, width: width, height: Self.checkboxHeight))
            case .inputs(let label, let labelWidth, let inputs):
                var x = frame.minX
                if let label {
                    // The inputs keep their widths; a label too long for the rest truncates (its tooltip shows it whole).
                    let inputsWidth = inputs.reduce(0) { $0 + Self.inlineGap + $1.width }
                    let wanted = labelWidth ?? ceil(label.cell?.cellSize.width ?? 0)
                    let width = max(0, min(wanted, frame.maxX - x - inputsWidth))
                    let toolTip = width < ceil(label.cell?.cellSize.width ?? 0) ? label.stringValue : nil
                    if label.toolTip != toolTip { label.toolTip = toolTip }
                    Self.placeLabel(label, NSRect(x: x, y: frame.minY, width: width, height: frame.height))
                    x += width + Self.inlineGap
                }
                for input in inputs {
                    Self.place(input.control, NSRect(x: x, y: frame.midY - input.height / 2, width: input.width, height: input.height))
                    x += input.width + Self.inlineGap
                }
            }
        }
    }

    /// The selected options item's controls, top to bottom, for the key view loop.
    var keyViews: [NSView] {
        selectedPage?.rows.flatMap(\.controls) ?? []
    }

    private var selectedPage: Page? {
        guard let item = tabView.selectedTabViewItem, let identifier = item.identifier as? String,
              let page = pages[identifier], item.view === page.view else { return nil }
        return page
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

    // MARK: - Helpers

    /// The controller's outlet `key` (an ivar or a property), or nil when it has none or it is nil / of another type.
    private static func outlet<T>(_ controller: NSObject, _ key: String) -> T? {
        // `value(forKey:)` raises for an unknown key: look first.
        guard class_getInstanceVariable(type(of: controller), key) != nil || controller.responds(to: NSSelectorFromString(key)) else { return nil }
        return controller.value(forKey: key) as? T
    }

    private static func onMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
    }
}
