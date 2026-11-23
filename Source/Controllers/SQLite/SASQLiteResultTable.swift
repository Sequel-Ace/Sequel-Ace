import AppKit
import SwiftUI

/// Native cell-based table used by SQLite Content and Query. Uses the same
/// header, cells, preference font, and table geometry as the server views.
struct SASQLiteResultTable: NSViewRepresentable {
    let columns: [String]
    let types: [String?]
    let rows: [[SASQLiteValue]]
    var selection: Binding<Int?>?
    var isQueryResult = false
    var sortColumn: Int?
    var descending = false
    var sort: ((Int) -> Void)?
    var editRow: ((Int) -> Void)?

    @AppStorage(SPDisplayTableViewVerticalGridlines) private var verticalGridlines = false
    @AppStorage(SPDisplayTableViewColumnTypes) private var showsTypes = true
    @AppStorage(SPDisplayBinaryDataAsHex) private var hexBlobs = false
    @AppStorage(SPNullValue) private var nullText = "NULL"
    @AppStorage(SPGlobalFontSettings) private var fontPreferences: Data?

    func makeNSView(context: Context) -> NSScrollView {
        let table = TableView(frame: .zero)
        table.style = .plain
        let headerHeight: CGFloat
        if #available(macOS 26, *) { headerHeight = 28 } else { headerHeight = 17 }
        let headerFrame = NSRect(x: 0, y: 0, width: 0, height: headerHeight)
        table.headerView = SATableHeaderView(frame: headerFrame)
        table.focusRingType = .none
        table.backgroundColor = .controlBackgroundColor
        table.gridColor = .gridColor
        table.intercellSpacing = NSSize(width: 3, height: 2)
        table.usesAlternatingRowBackgroundColors = true
        table.allowsExpansionToolTips = true
        table.allowsMultipleSelection = selection == nil
        table.columnAutoresizingStyle = isQueryResult ? .lastColumnOnlyAutoresizingStyle : .noColumnAutoresizing
        table.verticalMotionCanBeginDrag = false
        table.dataSource = context.coordinator
        table.delegate = context.coordinator
        table.target = context.coordinator
        table.doubleAction = #selector(Coordinator.openRow(_:))
        table.copyRows = { [weak coordinator = context.coordinator] table in coordinator?.copyRows(in: table) }

        let scroll = NSScrollView()
        scroll.focusRingType = .none
        scroll.hasHorizontalScroller = true
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.usesPredominantAxisScrolling = false
        scroll.horizontalLineScroll = 18
        scroll.horizontalPageScroll = 10
        scroll.verticalLineScroll = 18
        scroll.verticalPageScroll = 10
        scroll.documentView = table
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let table = scroll.documentView as? TableView else { return }
        context.coordinator.update(table, with: self)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class TableView: SPTableView {
        var copyRows: ((TableView) -> Void)?

        @objc func copy(_ sender: Any?) {
            copyRows?(self)
        }

        override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
            if item.action == #selector(copy(_:)) { return numberOfSelectedRows > 0 }
            return super.validateUserInterfaceItem(item)
        }
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        private var parent: SASQLiteResultTable
        private var appliedColumns: [String] = []
        private var appliedTypes: [String?] = []
        private var appliedShowsTypes: Bool?
        private var appliedFont: NSFont?
        private var updating = false

        init(_ parent: SASQLiteResultTable) { self.parent = parent }

        func update(_ table: TableView, with next: SASQLiteResultTable) {
            let displayChanged = parent.rows != next.rows || parent.nullText != next.nullText || parent.hexBlobs != next.hexBlobs
            parent = next
            updating = true
            defer { updating = false }

            table.gridStyleMask = next.verticalGridlines ? .solidVerticalGridLineMask : []
            let font = SAArchiving.font(from: next.fontPreferences) ?? UserDefaults.getFont()
            let rebuild = appliedColumns != next.columns || appliedTypes != next.types ||
                appliedShowsTypes != next.showsTypes || appliedFont != font
            if rebuild {
                configureColumns(of: table, font: font)
            }
            if rebuild || displayChanged {
                table.reloadData()
            }

            for (index, column) in table.tableColumns.enumerated() {
                let imageName = next.descending ? "NSDescendingSortIndicator" : "NSAscendingSortIndicator"
                table.setIndicatorImage(index == next.sortColumn ? NSImage(named: imageName) : nil, in: column)
            }
            table.highlightedTableColumn = next.sortColumn.flatMap { table.tableColumns.indices.contains($0) ? table.tableColumns[$0] : nil }

            if let selection = next.selection {
                if let row = selection.wrappedValue, next.rows.indices.contains(row) {
                    if table.selectedRow != row { table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
                } else if table.numberOfSelectedRows > 0 {
                    table.deselectAll(nil)
                }
            }
        }

        private func configureColumns(of table: TableView, font: NSFont) {
            let preserveWidths = appliedColumns == parent.columns
            let widths = preserveWidths ? Dictionary(uniqueKeysWithValues: table.tableColumns.map { ($0.identifier, $0.width) }) : [:]
            for column in table.tableColumns { table.removeTableColumn(column) }
            table.rowHeight = 4 + ("{ǞṶḹÜ∑zgyf" as NSString).size(withAttributes: [.font: font]).height
            appliedColumns = parent.columns
            appliedTypes = parent.types
            appliedShowsTypes = parent.showsTypes
            appliedFont = font

            for (index, name) in parent.columns.enumerated() {
                let type = parent.types.indices.contains(index) ? parent.types[index] : nil
                let identifier = NSUserInterfaceItemIdentifier(String(index))
                let column = NSTableColumn(identifier: identifier)
                column.resizingMask = .userResizingMask
                column.minWidth = 40
                column.maxWidth = 1_000
                column.isEditable = false

                let cell = SPTextAndLinkCell(textCell: "")
                cell.font = font
                cell.lineBreakMode = .byTruncatingTail
                cell.isEditable = false
                column.dataCell = cell

                let definition: NSDictionary = ["name": name, "type": type ?? ""]
                column.headerCell.attributedStringValue = definition.tableContentColumnHeaderAttributedString(columnTypesVisible: parent.showsTypes)
                column.headerToolTip = type.map { name + " – " + $0 } ?? name
                let headerWidth = column.headerCell.attributedStringValue.size().width
                let sampleWidth = parent.rows.prefix(100).reduce(headerWidth) { width, row in
                    guard row.indices.contains(index) else { return width }
                    let value = (display(row[index]) as NSString).size(withAttributes: [.font: font]).width
                    return max(width, value)
                }
                column.width = widths[identifier] ?? min(420, max(45, sampleWidth + 16))
                table.addTableColumn(column)
            }
        }

        func numberOfRows(in tableView: NSTableView) -> Int { parent.rows.count }

        func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
            value(in: tableColumn, row: row).map(display)
        }

        func tableView(_ tableView: NSTableView, willDisplayCell cell: Any, for tableColumn: NSTableColumn?, row: Int) {
            guard let cell = cell as? NSTextFieldCell, let value = value(in: tableColumn, row: row) else { return }
            switch value {
            case .integer, .real: cell.alignment = .right
            default: cell.alignment = .left
            }
            cell.textColor = value == .null && tableView.selectedRow != row ? .lightGray : .controlTextColor
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !updating, let table = notification.object as? NSTableView else { return }
            let row = table.selectedRow
            parent.selection?.wrappedValue = row >= 0 ? row : nil
        }

        func tableView(_ tableView: NSTableView, didClick tableColumn: NSTableColumn) {
            if let index = Int(tableColumn.identifier.rawValue) { parent.sort?(index) }
        }

        @objc func openRow(_ table: NSTableView) {
            if parent.rows.indices.contains(table.clickedRow) { parent.editRow?(table.clickedRow) }
        }

        func copyRows(in table: NSTableView) {
            let indexes = table.tableColumns.compactMap { Int($0.identifier.rawValue) }
            let lines = table.selectedRowIndexes.compactMap { row in
                guard parent.rows.indices.contains(row) else { return nil as String? }
                return indexes.compactMap { index in
                    guard parent.rows[row].indices.contains(index) else { return nil }
                    let value = parent.rows[row][index]
                    return value == .null ? parent.nullText : value.display
                }.joined(separator: "\t")
            }
            guard !lines.isEmpty else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
        }

        private func value(in column: NSTableColumn?, row: Int) -> SASQLiteValue? {
            guard let column, let index = Int(column.identifier.rawValue),
                  parent.rows.indices.contains(row), parent.rows[row].indices.contains(index) else { return nil }
            return parent.rows[row][index]
        }

        private func display(_ value: SASQLiteValue) -> String {
            switch value {
            case .null:
                return parent.nullText
            case let .blob(data) where !parent.hexBlobs:
                return String(data: data.prefix(256), encoding: .utf8) ?? value.preview
            default:
                return value.preview
            }
        }
    }
}

struct SASQLiteSidebarList: NSViewRepresentable {
    let objects: [SASQLiteObject]
    let pinned: Set<Data>
    @Binding var selection: Data?
    let canSelect: Bool

    func makeNSView(context: Context) -> NSScrollView {
        let table = SATablesListView(frame: .zero)
        table.style = .sourceList
        table.useSequelAceSourceListSelection()
        table.focusRingType = .none
        table.headerView = nil
        table.allowsColumnReordering = false
        table.allowsExpansionToolTips = true
        table.allowsTypeSelect = false
        table.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        table.intercellSpacing = NSSize(width: 3, height: 2)
        table.backgroundColor = NSColor(named: NSColor.Name("_sourceListBackgroundColor")) ?? .clear
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("tables"))
        column.minWidth = 50
        column.maxWidth = 3_000
        column.width = 214
        column.dataCell = SPTableTextFieldCell(textCell: "")
        table.addTableColumn(column)
        table.dataSource = context.coordinator
        table.delegate = context.coordinator
        table.objectTypeAtRow = { [weak coordinator = context.coordinator] row in
            coordinator?.object(at: row).map { SPTableType(rawValue: $0.kind == .view ? 1 : 0) } ?? SPTableType(rawValue: -1)
        }

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsets(top: 0, left: 9, bottom: 0, right: 9)
        scroll.contentView.drawsBackground = false
        scroll.autohidesScrollers = true
        scroll.hasVerticalScroller = true
        scroll.documentView = table
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let table = scroll.documentView as? SATablesListView else { return }
        context.coordinator.update(table, with: self)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        private enum Row: Equatable {
            case heading(String)
            case object(SASQLiteObject)
        }

        private var parent: SASQLiteSidebarList
        private var rows: [Row] = []
        private var updating = false

        init(_ parent: SASQLiteSidebarList) { self.parent = parent }

        func update(_ table: SATablesListView, with parent: SASQLiteSidebarList) {
            self.parent = parent
            updating = true
            defer { updating = false }
            let pinned = parent.objects.filter { parent.pinned.contains($0.id) }
            let title = parent.objects.contains { $0.kind == .view }
                ? NSLocalizedString("TABLES & VIEWS", comment: "Tables and views sidebar heading")
                : NSLocalizedString("TABLES", comment: "Tables sidebar heading")
            var next: [Row] = []
            if !pinned.isEmpty {
                next.append(.heading(NSLocalizedString("PINNED TABLES", comment: "Pinned tables sidebar heading")))
                next.append(contentsOf: pinned.map(Row.object))
            }
            next.append(.heading(title))
            next.append(contentsOf: parent.objects.filter { !parent.pinned.contains($0.id) }.map(Row.object))
            if next != rows {
                rows = next
                table.reloadData()
            }
            if let selected = rows.indices.first(where: { object(at: $0)?.id == parent.selection && object(at: $0) != nil }) {
                if table.selectedRow != selected {
                    table.selectRowIndexes(IndexSet(integer: selected), byExtendingSelection: false)
                }
            } else if table.selectedRow != -1 {
                table.deselectAll(nil)
            }
        }

        func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

        func object(at row: Int) -> SASQLiteObject? {
            guard rows.indices.contains(row), case let .object(object) = rows[row] else { return nil }
            return object
        }

        func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
            guard rows.indices.contains(row) else { return nil }
            switch rows[row] {
            case let .heading(title): return title
            case let .object(object): return object.name
            }
        }

        func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool { object(at: row) == nil }

        func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
            parent.canSelect && object(at: row) != nil
        }

        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            object(at: row) == nil ? 25 : 4 + ("{ǞṶḹÜ∑zgyf" as NSString).size(withAttributes: [.font: UserDefaults.getFont()]).height
        }

        func tableView(_ tableView: NSTableView, willDisplayCell cell: Any, for tableColumn: NSTableColumn?, row: Int) {
            guard let cell = cell as? SPTableTextFieldCell else { return }
            let object = object(at: row)
            cell.font = UserDefaults.getFont()
            cell.image = object.flatMap { NSImage(named: $0.kind == .view ? "table-view-small" : "table-small") }
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !updating, let table = notification.object as? NSTableView,
                  let object = object(at: table.selectedRow) else { return }
            parent.selection = object.id
        }
    }
}

struct SASQLiteSearchField: NSViewRepresentable {
    @Binding var text: String
    let title: String

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = title
        field.controlSize = .small
        field.sendsSearchStringImmediately = true
        field.delegate = context.coordinator
        field.setAccessibilityLabel(title)
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: SASQLiteSearchField
        init(_ parent: SASQLiteSearchField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            if let field = notification.object as? NSSearchField { parent.text = field.stringValue }
        }
    }
}
