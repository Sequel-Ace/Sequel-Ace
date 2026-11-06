import AppKit
import SwiftUI

struct SASQLiteWorkspaceView: View {
    @ObservedObject var model: SASQLiteWorkspaceModel
    @State private var editor: SASQLiteEditorRequest?
    @State private var deletion: (() -> Void)?
    @State private var confirmsDeletion = false
    @State private var resultOffset = 0
    @State private var tableSearch = ""

    var body: some View {
        VStack(spacing: 0) {
            if model.busy || model.session.readOnly {
                statusBar
                Divider()
            }
            HSplitView {
                sidebar.frame(minWidth: 160, idealWidth: 195, maxWidth: 245)
                VStack(spacing: 0) {
                    switch model.section {
                    case .data: dataView
                    case .structure: structureView
                    case .relations: detailsGrid(\.foreignKeys)
                    case .triggers: detailsGrid(\.triggers)
                    case .status: definitionView
                    case .query: queryView
                    }
                }
                .frame(minWidth: 510, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { model.start() }
        .sheet(item: $editor) { editorSheet($0.content) }
        .sheet(item: $model.csvImport) { request in
            SASQLiteCSVImportView(request: request, objects: model.objects, current: model.page?.structure,
                                  cancel: { model.csvImport = nil }, save: { target, header in
                model.csvImport = nil
                model.importCSV(request, into: target, hasHeader: header)
            }, loadStructure: model.loadImportStructure)
        }
        .alert("SQLite", isPresented: $model.showsError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage)
        }
        .alert("Confirm Deletion", isPresented: $confirmsDeletion) {
            Button("Delete", role: .destructive) {
                deletion?()
                deletion = nil
            }
            Button("Cancel", role: .cancel) { deletion = nil }
        } message: {
            Text("This change will be saved to the SQLite database.")
        }
        .confirmationDialog("Import into SQLite", isPresented: $model.showsImport) {
            Button("CSV…") { model.selectImport(csv: true) }
            Button("SQLite SQL…") { model.selectImport(csv: false) }
        }
        .confirmationDialog("Export from SQLite", isPresented: $model.showsExport) {
            Button("Table or View as CSV…") { model.exportTable() }
                .disabled(model.currentObject == nil)
            Button("Loaded Query Results as CSV…") { model.exportResult() }
                .disabled(model.queryResult?.result?.columns.isEmpty != false)
            Button("Database as SQLite SQL…") { model.exportSQL() }
            Button("Create SQLite Backup…") { model.backup(restore: false) }
            Button("Restore as New SQLite Database…") { model.backup(restore: true) }
        }
    }

    private var statusBar: some View {
        HStack(spacing: 10) {
            Spacer()
            if model.session.readOnly {
                Label("Read-Only", systemImage: "lock")
                    .foregroundStyle(.secondary)
            }
            if model.busy {
                ProgressView().controlSize(.small)
                Button("Cancel") { model.operation?.cancel() }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Tables & Views").font(.headline)
                Spacer()
                Button { editor = .init(content: .schema(.createTable)) } label: {
                    Image(systemName: "plus")
                }
                .help("Create Table")
                .accessibilityLabel("Create Table")
                .disabled(!model.canWrite)
            }
            .padding(10)
            Divider()
            List(selection: $model.selection) {
                ForEach(model.objects.filter { tableSearch.isEmpty || $0.name.localizedCaseInsensitiveContains(tableSearch) }) { object in
                    Label(object.name, systemImage: object.kind == .view ? "eye" : "tablecells")
                        .tag(object.id)
                        .contextMenu {
                            if object.kind != .view {
                                Button("Rename Table…") { editor = .init(content: .schema(.renameTable(object))) }
                                    .disabled(!model.canWrite)
                            }
                            Button("Delete…", role: .destructive) {
                                confirm { model.apply(.dropObject(object)) }
                            }
                            .disabled(!model.canWrite)
                        }
                }
            }
            .listStyle(.sidebar)
            .disabled(model.busy)
            .contextMenu {
                Button("Create Table…") { editor = .init(content: .schema(.createTable)) }
                    .disabled(!model.canWrite)
            }
            Divider()
            TextField("Filter Tables", text: $tableSearch)
                .textFieldStyle(.roundedBorder)
                .padding(8)
        }
    }

    @ViewBuilder private var dataView: some View {
        if let page = model.page {
            SASQLiteGrid(columns: page.structure.visibleColumns.map(\.name), rows: page.rows.map(\.values),
                         selection: $model.selectedRow)
            Divider()
            HStack {
                Button("Add Row…") { editor = .init(content: .row(page.structure, nil)) }
                    .disabled(!model.canWrite || page.structure.object.kind != .table)
                Button("Edit Row…") {
                    if let row = model.currentRow { editor = .init(content: .row(page.structure, row)) }
                }
                .disabled(!model.canEditRow)
                Button("Delete Row…") {
                    if let row = model.currentRow { confirm { model.delete(row, in: page.structure) } }
                }
                .disabled(!model.canEditRow)

                Spacer()

                pager(offset: model.offset, count: page.rows.count, hasMore: page.hasMore) {
                    model.loadPage(at: $0)
                }
            }
            .padding(10)
        } else {
            emptySelection
        }
    }

    @ViewBuilder private var structureView: some View {
        if let structure = model.page?.structure {
            TabView {
                VStack(spacing: 0) {
                    SASQLiteColumnsView(structure: structure, selection: $model.selectedColumn)
                    Divider()
                    HStack {
                        Button("Add Column…") { editor = .init(content: .schema(.addColumn(structure.object))) }
                        Button("Rename Column…") {
                            if let column = selectedColumn(in: structure) {
                                editor = .init(content: .schema(.renameColumn(structure.object, column)))
                            }
                        }
                        .disabled(selectedColumn(in: structure) == nil)
                        Button("Delete Column…") {
                            if let column = selectedColumn(in: structure) {
                                confirm { model.apply(.dropColumn(structure.object, column)) }
                            }
                        }
                        .disabled(selectedColumn(in: structure) == nil)
                        Spacer()
                    }
                    .disabled(!model.canWrite || structure.object.kind != .table)
                    .padding(8)
                }
                .tabItem { Text("Columns") }

                resultGrid(structure.indexes).tabItem { Text("Indexes") }
            }
            .padding(10)
        } else {
            emptySelection
        }
    }

    @ViewBuilder private func detailsGrid(_ result: KeyPath<SASQLiteStructure, SASQLiteResult>) -> some View {
        if let structure = model.page?.structure {
            resultGrid(structure[keyPath: result])
        } else {
            emptySelection
        }
    }

    @ViewBuilder private var definitionView: some View {
        if let definition = model.page?.structure.definition {
            ScrollView {
                Text(definition)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
        } else {
            emptySelection
        }
    }

    private var queryView: some View {
        VSplitView {
            VStack(spacing: 0) {
                SASQLiteQueryEditor(sql: $model.sql, selection: $model.selectedSQL)
                    .frame(minHeight: 115)
                Divider()
                HStack {
                    Button("Run Script") {
                        resultOffset = 0
                        model.runSQL(selectionOnly: false)
                    }
                        .keyboardShortcut(.return, modifiers: [.command, .shift])
                        .disabled(model.busy || model.sql.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Run Selection") {
                        resultOffset = 0
                        model.runSQL(selectionOnly: true)
                    }
                        .keyboardShortcut(.return, modifiers: [.command])
                        .disabled(model.busy || model.selectedSQL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Spacer()
                }
                .padding(10)
            }
            queryResults.frame(minHeight: 145)
        }
    }

    @ViewBuilder private var queryResults: some View {
        if let statement = model.queryResult {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Picker("Statement", selection: $model.selectedResult) {
                        ForEach(model.scriptResults.indices, id: \.self) { index in
                            Text("Statement \(index + 1)").tag(index)
                        }
                    }
                    .fixedSize()
                    .task(id: model.selectedResult) { resultOffset = 0 }
                    Spacer()
                    if let result = statement.result {
                        Text("Rows changed: \(result.changedRows)").foregroundStyle(.secondary)
                    }
                }
                .padding(10)
                if let error = statement.error {
                    ScrollView {
                        Text(error)
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                    }
                } else if let result = statement.result, !result.columns.isEmpty {
                    let rows = Array(result.rows.dropFirst(resultOffset).prefix(model.pageSize))
                    SASQLiteGrid(columns: result.columns, rows: rows, selection: nil)
                        .id(model.selectedResult)
                    HStack {
                        if result.truncated {
                            Text("Results are limited to 1,000 rows per run.").foregroundStyle(.secondary)
                        }
                        Spacer()
                        pager(offset: resultOffset, count: rows.count, hasMore: resultOffset + rows.count < result.rows.count) {
                            resultOffset = $0
                        }
                    }
                    .padding(10)
                } else {
                    Spacer()
                }
            }
        } else {
            Text("Run SQLite SQL to see results.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var emptySelection: some View {
        Text(model.objects.isEmpty ? "This SQLite database has no tables or views." : "Select a table or view.")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func resultGrid(_ result: SASQLiteResult) -> some View {
        SASQLiteGrid(columns: result.columns, rows: result.rows, selection: nil)
    }

    private func pager(offset: Int, count: Int, hasMore: Bool, select: @escaping (Int) -> Void) -> some View {
        HStack {
            Button("Previous") { select(max(0, offset - model.pageSize)) }.disabled(model.busy || offset == 0)
            Text("Page \(offset / model.pageSize + 1) · \(count) rows").monospacedDigit()
            Button("Next") { select(offset + model.pageSize) }.disabled(model.busy || !hasMore)
        }
    }

    private func selectedColumn(in structure: SASQLiteStructure) -> SASQLiteColumn? {
        structure.visibleColumns.first { $0.id == model.selectedColumn }
    }

    private func confirm(_ action: @escaping () -> Void) {
        guard model.canWrite else { return }
        deletion = action
        confirmsDeletion = true
    }

    @ViewBuilder private func editorSheet(_ content: SASQLiteEditorRequest.Content) -> some View {
        switch content {
        case let .schema(request):
            SASQLiteSchemaEditor(request: request, cancel: { editor = nil }, save: { change, name in
                editor = nil
                model.apply(change, select: name)
            })
        case let .row(structure, row):
            SASQLiteRowEditor(structure: structure, row: row, cancel: { editor = nil }, save: { values in
                editor = nil
                model.save(values, row: row, in: structure)
            })
        }
    }
}

private struct SASQLiteGrid: View {
    let columns: [String]
    let rows: [[SASQLiteValue]]
    let selection: Binding<Int?>?
    let columnWidths: [CGFloat]

    init(columns: [String], rows: [[SASQLiteValue]], selection: Binding<Int?>?) {
        self.columns = columns
        self.rows = rows
        self.selection = selection
        columnWidths = columns.indices.map { index in
            let maxLength = rows.prefix(20).reduce(columns[index].count) { max($0, $1[index].preview.count) }
            return CGFloat(min(270, max(85, 24 + 7 * maxLength)))
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView([.vertical, .horizontal]) {
                rowsAndHeader.frame(minWidth: geometry.size.width, minHeight: geometry.size.height, alignment: .topLeading)
            }
        }
    }

    private var rowsAndHeader: some View {
        LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
            Section {
                ForEach(rows.indices, id: \.self) { index in
                    if let selection {
                        Button { selection.wrappedValue = index } label: {
                            row(index, selected: selection.wrappedValue == index)
                        }
                        .buttonStyle(.plain)
                    } else {
                        row(index, selected: false).textSelection(.enabled)
                    }
                }
            } header: {
                HStack(spacing: 0) {
                    ForEach(columns.indices, id: \.self) { index in
                        cell(columns[index], column: index).fontWeight(.semibold)
                    }
                }
                .background(.bar)
            }
        }
    }

    private func row(_ index: Int, selected: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(rows[index].indices, id: \.self) { column in
                let value = rows[index][column]
                cell(value.preview, column: column)
                    .foregroundStyle(value == .null ? .secondary : .primary)
            }
        }
        .background(selected ? Color.accentColor.opacity(0.24) : Color.secondary.opacity(index.isMultiple(of: 2) ? 0.05 : 0))
        .contentShape(Rectangle())
    }

    private func cell(_ string: String, column: Int) -> some View {
        Text(string)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .frame(width: columnWidths[column], height: 25, alignment: .leading)
            .overlay(alignment: .trailing) { Divider() }
            .help(string)
    }
}

private struct SASQLiteColumnsView: View {
    let structure: SASQLiteStructure
    @Binding var selection: Int64?

    var body: some View {
        List(structure.visibleColumns, selection: $selection) { column in
            HStack {
                Text(column.name).frame(width: 150, alignment: .leading)
                Text(column.type).frame(width: 100, alignment: .leading)
                if column.primaryKeyPosition > 0 { Text("Primary Key") }
                if column.notNull { Text("NOT NULL") }
                if column.generated { Text("Generated") }
                if let sql = column.defaultSQL { Text("Default: \(sql)") }
                Spacer()
            }
            .tag(column.id)
        }
    }
}

private struct SASQLiteQueryEditor: NSViewRepresentable {
    @Binding var sql: String
    @Binding var selection: String

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        if let editor = scroll.documentView as? NSTextView {
            editor.string = sql
            editor.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
            editor.isRichText = false
            editor.allowsUndo = true
            editor.isAutomaticQuoteSubstitutionEnabled = false
            editor.isAutomaticDashSubstitutionEnabled = false
            editor.isAutomaticTextReplacementEnabled = false
            editor.textContainerInset = NSSize(width: 8, height: 8)
            editor.setAccessibilityLabel(NSLocalizedString("SQLite Query Editor", comment: "Accessibility label for SQLite SQL editor"))
            editor.delegate = context.coordinator
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scroll.documentView as? NSTextView, !editor.string.utf8.elementsEqual(sql.utf8) else { return }
        editor.string = sql
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SASQLiteQueryEditor

        init(_ parent: SASQLiteQueryEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            parent.sql = editor.string
            updateSelection(editor)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            if let editor = notification.object as? NSTextView { updateSelection(editor) }
        }

        private func updateSelection(_ editor: NSTextView) {
            let text = editor.string as NSString
            let range = editor.selectedRange()
            parent.selection = range.length > 0 && NSMaxRange(range) <= text.length ? text.substring(with: range) : ""
        }
    }
}
