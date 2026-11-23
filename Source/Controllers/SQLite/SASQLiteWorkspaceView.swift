import AppKit
import SwiftUI

struct SASQLiteWorkspaceView: View {
    @ObservedObject var model: SASQLiteWorkspaceModel
    @State private var editor: SASQLiteEditorRequest?
    @State private var deletion: (() -> Void)?
    @State private var confirmsDeletion = false
    @State private var resultOffset = 0
    @State private var tableSearch = ""
    @State private var columnSearch = ""
    @State private var showsFavoriteName = false
    @State private var showsClearHistory = false
    @State private var favoriteName = ""
    @State private var querySortColumn: Int?
    @State private var querySortDescending = false
    @State private var filterColumn: Int64?
    @State private var filterOperator = SASQLiteBrowseOptions.Filter.Operator.contains
    @State private var filterText = ""
    @State private var selectedIndex: Int?
    @State private var selectedRelation: Int?
    @State private var selectedTrigger: Int?
    @State private var exportAction: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            if model.busy || model.session.readOnly {
                statusBar
                Divider()
            }
            HSplitView {
                sidebar.frame(minWidth: 160, idealWidth: 214, maxWidth: 214)
                VStack(spacing: 0) {
                    switch model.section {
                    case .data: dataView
                    case .structure: structureView
                    case .relations: relationsView
                    case .triggers: triggersView
                    case .status: tableInfoView
                    case .query: queryView
                    }
                }
                .frame(minWidth: 510, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { model.start() }
        .task(id: model.selection) {
            selectedIndex = nil
            selectedRelation = nil
            selectedTrigger = nil
            filterColumn = nil
            filterText = ""
            columnSearch = ""
        }
        .task(id: model.queryRunID) {
            resultOffset = 0
            querySortColumn = nil
        }
        .alert("Save Query to Favorites", isPresented: $showsFavoriteName) {
            TextField("Name", text: $favoriteName)
            Button("Cancel", role: .cancel) {}
            Button("Save") { model.saveQueryFavorite(favoriteName) }
        }
        .alert("Clear History", isPresented: $showsClearHistory) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) { model.clearQueryHistory() }
        }
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
        .task(id: model.showsImport) {
            guard model.showsImport else { return }
            model.showsImport = false
            model.selectImport()
        }
        .sheet(isPresented: $model.showsExport, onDismiss: runExportAction) {
            SASQLiteExportPanel(model: model, cancel: { model.showsExport = false }, export: selectExport)
        }
    }

    private func selectExport(_ action: @escaping () -> Void) {
        exportAction = action
        model.showsExport = false
    }

    private func runExportAction() {
        let action = exportAction
        exportAction = nil
        action?()
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
            SASQLiteSearchField(text: $tableSearch, title: NSLocalizedString("Filter", comment: "Table sidebar filter"))
                .frame(height: 24)
                .padding(.horizontal, 3)
                .padding(.vertical, 3)
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    let matches = model.objects.filter { tableSearch.isEmpty || $0.name.localizedCaseInsensitiveContains(tableSearch) }
                    SASQLiteSidebarList(objects: matches, pinned: model.pinnedObjects,
                                        selection: $model.selection, canSelect: !model.busy)
                    if model.showsTableInformation {
                        Divider()
                        VStack(alignment: .leading, spacing: 8) {
                            Text(model.busy || model.currentObject == nil ? "ACTIVITIES" : "TABLE INFORMATION")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                            if model.busy {
                                HStack {
                                    ProgressView().controlSize(.small)
                                    Button("Cancel") { model.operation?.cancel() }
                                }
                            } else if let page = model.page {
                                Text(page.structure.object.name)
                                Text(page.totalRows == 1 ? "1 row in table" : "\(page.totalRows) rows in table").foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .frame(height: min(155, geometry.size.height * 0.25))
                    }
                }
                .background(.regularMaterial)
            }
            Divider()
            HStack(spacing: 0) {
                tableAction(NSImage.addTemplateName, name: "Add new table", enabled: model.canWrite) {
                    editor = .init(content: .schema(.createTable))
                }
                Menu {
                    sidebarActions
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.visible)
                .fixedSize()
                tableAction(NSImage.refreshTemplateName, name: "Refresh", enabled: !model.busy) {
                    model.reloadObjects()
                }
                tableAction(symbol: "eye", name: "Toggle the visibility of the Information panel", enabled: true) {
                    model.showsTableInformation.toggle()
                }
                Spacer()
            }
            .frame(height: 25)
            .background(.bar)
        }
    }

    @ViewBuilder private var sidebarActions: some View {
        if let object = model.currentObject {
            Button("Copy Table Name") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(object.name, forType: .string)
            }
            if object.kind == .table {
                Button("Rename Table…") { editor = .init(content: .schema(.renameTable(object))) }
                    .disabled(!model.canWrite)
                Button("Duplicate Table…") { editor = .init(content: .schema(.duplicateTable(object))) }
                    .disabled(!model.canWrite)
                Divider()
                Button("Truncate Table…", role: .destructive) {
                    confirm { model.apply(.truncateTable(object)) }
                }
                .disabled(!model.canWrite)
            }
            Button("Remove Table…", role: .destructive) {
                confirm { model.apply(.dropObject(object)) }
            }
            .disabled(!model.canWrite)
            Divider()
            Button("Toggle Pin Table") { model.togglePin(object) }
            Button("Open Table in New Tab") { SASQLiteOpening.openObject(object, from: model, inNewWindow: false) }
            Button("Open Table in New Window") { SASQLiteOpening.openObject(object, from: model, inNewWindow: true) }
            Divider()
            Button("Copy CREATE Syntax") {
                if let definition = model.page?.structure.definition {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(definition, forType: .string)
                }
            }
            .disabled(model.page?.structure.definition == nil)
            Button("Export…") { model.showsExport = true }
                .disabled(model.busy)
        } else {
            Button("Create Table…") { editor = .init(content: .schema(.createTable)) }
                .disabled(!model.canWrite)
        }
    }

    @ViewBuilder private var dataView: some View {
        if let page = model.page {
            let columns = page.structure.visibleColumns
            let terms = columnSearch.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            let displayed = columns.indices.filter { index in
                terms.isEmpty || terms.contains { columns[index].name.localizedCaseInsensitiveContains($0) }
            }
            if model.showsFilters { dataFilters(columns) }
            HSplitView {
                SASQLiteResultTable(columns: displayed.map { columns[$0].name },
                                    types: displayed.map { columns[$0].type },
                                    rows: page.rows.map { row in displayed.map { row.values[$0] } },
                                    selection: $model.selectedRow,
                                    sortColumn: displayed.firstIndex { columns[$0].id == model.browse.sortColumn },
                                    descending: model.browse.descending,
                                    sort: { index in
                    if displayed.indices.contains(index) { model.sort(by: columns[displayed[index]]) }
                }) { row in
                    guard model.canEditRow, let selected = model.currentRow, model.selectedRow == row else { return }
                    editor = .init(content: .row(page.structure, selected))
                }
                if model.showsRecord {
                    SARecordView(model: model.recordModel).frame(minWidth: 240, idealWidth: 320, maxWidth: 410)
                }
            }
            .task(id: model.selectedRow) {
                let row = model.currentRow
                model.showRecord(columns: columns.map(\.name), row: row?.values, edit: model.canEditRow ? { index, input in
                    guard let row, columns.indices.contains(index), !columns[index].generated else { return false }
                    let value: SASQLiteValue
                    switch row.values[index] {
                    case .integer:
                        guard let integer = Int64(input) else { return false }
                        value = .integer(integer)
                    case .real:
                        guard let real = Double(input), !real.isNaN else { return false }
                        value = .real(real)
                    case .text, .null:
                        value = SASQLiteValue(input)
                    case .blob:
                        return false
                    }
                    model.save([columns[index].id: value], row: row, in: page.structure)
                    return true
                } : nil)
            }
            Divider()
            HStack(spacing: 0) {
                tableAction(NSImage.addTemplateName, name: "Add Row…",
                            enabled: model.canWrite && page.structure.object.kind == .table) {
                    editor = .init(content: .row(page.structure, nil))
                }
                tableAction(NSImage.removeTemplateName, name: "Delete Row…", enabled: model.canEditRow) {
                    if let row = model.currentRow { confirm { model.delete(row, in: page.structure) } }
                }
                tableAction(symbol: "plus.square.on.square", name: "Duplicate Row", enabled: model.canWrite && page.structure.object.kind == .table && model.currentRow != nil) {
                    if let row = model.currentRow { editor = .init(content: .duplicateRow(page.structure, row)) }
                }
                tableAction(symbol: "pencil", name: "Edit Row…", enabled: model.canEditRow) {
                    if let row = model.currentRow { editor = .init(content: .row(page.structure, row)) }
                }
                tableAction(NSImage.refreshTemplateName, name: "Refresh", enabled: !model.busy) {
                    model.loadPage(at: model.offset)
                }
                tableAction(symbol: "sidebar.right", name: "Toggle Record View", enabled: true) {
                    model.toggleRecordView(nil)
                }
                tableAction(symbol: "line.3.horizontal.decrease", name: "Filter", enabled: !model.busy) {
                    model.showsFilters.toggle()
                }
                SASQLiteSearchField(text: $columnSearch, title: NSLocalizedString("Filter Columns", comment: "Content column filter"))
                    .frame(width: 135, height: 21)
                Text(page.matchingRows == 1 ? "1 row in table" : "\(page.matchingRows) rows in table").font(.caption).padding(.leading, 8)
                Spacer()
                pager(offset: model.offset, count: page.rows.count, hasMore: page.hasMore) {
                    model.loadPage(at: $0)
                }
            }
            .padding(.horizontal, 3)
            .frame(height: 25)
            .background(.bar)
        } else {
            emptySelection
        }
    }

    private func dataFilters(_ columns: [SASQLiteColumn]) -> some View {
        HStack {
            Picker("Column", selection: $filterColumn) {
                Text("Choose Column").tag(nil as Int64?)
                ForEach(columns) { column in Text(column.name).tag(Optional(column.id)) }
            }
            .fixedSize()
            Picker("Operator", selection: $filterOperator) {
                ForEach(SASQLiteBrowseOptions.Filter.Operator.allCases, id: \.self) { operation in
                    Text(filterTitle(operation)).tag(operation)
                }
            }
            .fixedSize()
            TextField("Value", text: $filterText)
                .disabled(filterOperator == .isNull || filterOperator == .isNotNull)
            Button("Filter") {
                if let filterColumn {
                    model.filter(using: .init(columnID: filterColumn, operation: filterOperator, value: filterText))
                }
            }
            .disabled(filterColumn == nil || model.busy)
            Button("Clear") {
                filterText = ""
                model.filter(using: nil)
            }
            .disabled(model.browse.filter == nil || model.busy)
        }
        .controlSize(.small)
        .padding(6)
        .background(.bar)
    }

    private func filterTitle(_ operation: SASQLiteBrowseOptions.Filter.Operator) -> LocalizedStringKey {
        switch operation {
        case .contains: return "Contains"
        case .equals: return "Equals"
        case .notEqual: return "Does Not Equal"
        case .beginsWith: return "Begins With"
        case .endsWith: return "Ends With"
        case .greaterThan: return "Greater Than"
        case .lessThan: return "Less Than"
        case .isNull: return "Is NULL"
        case .isNotNull: return "Is Not NULL"
        }
    }

    @ViewBuilder private var structureView: some View {
        if let structure = model.page?.structure {
            VSplitView {
                VStack(spacing: 0) {
                    let columns = structure.visibleColumns
                    let rows = columns.map { column in
                        [SASQLiteValue(column.name), SASQLiteValue(column.type),
                         SASQLiteValue(column.notNull || column.primaryKeyPosition > 0 ? "" : "✓"),
                         column.defaultSQL.map(SASQLiteValue.init) ?? .null,
                         SASQLiteValue(column.generated ? NSLocalizedString("Generated", comment: "Generated column") : "")]
                    }
                    SASQLiteResultTable(columns: [
                        NSLocalizedString("Field", comment: "Structure field name"),
                        NSLocalizedString("Type", comment: "Structure field type"),
                        NSLocalizedString("Allow Null", comment: "Structure field nullability"),
                        NSLocalizedString("Default", comment: "Structure field default"),
                        NSLocalizedString("Extra", comment: "Structure field attributes")
                    ], types: [], rows: rows, selection: $model.selectedColumn) { index in
                        if columns.indices.contains(index) { editColumn(columns[index], in: structure) }
                    }
                    let editable = model.canWrite && structure.object.kind == .table
                    schemaFooter {
                        tableAction(NSImage.addTemplateName, name: "Add Column…", enabled: editable) {
                            editor = .init(content: .schema(.addColumn(structure.object)))
                        }
                        tableAction(NSImage.removeTemplateName, name: "Delete Column…", enabled: editable && selectedColumn(in: structure) != nil) {
                            if let column = selectedColumn(in: structure) { confirm { model.apply(.dropColumn(structure.object, column)) } }
                        }
                        tableAction(symbol: "pencil", name: "Edit Column…", enabled: editable && selectedColumn(in: structure) != nil) {
                            if let column = selectedColumn(in: structure) { editColumn(column, in: structure) }
                        }
                        tableAction(symbol: "character.cursor.ibeam", name: "Rename Column…", enabled: editable && selectedColumn(in: structure) != nil) {
                            if let column = selectedColumn(in: structure) { editor = .init(content: .schema(.renameColumn(structure.object, column))) }
                        }
                        tableAction(NSImage.refreshTemplateName, name: "Refresh", enabled: !model.busy) { model.reloadObjects() }
                    }
                }
                .frame(minHeight: 140)
                indexView(structure).frame(minHeight: 105)
            }
            .id(structure.object.id)
        } else {
            emptySelection
        }
    }

    private func editColumn(_ column: SASQLiteColumn, in structure: SASQLiteStructure) {
        guard model.canWrite, structure.object.kind == .table,
              let definition = structure.definition,
              let declaration = try? SASQLiteTableDefinition(definition).column(column.name) else { return }
        editor = .init(content: .column(structure, column, declaration))
    }

    private func indexView(_ structure: SASQLiteStructure) -> some View {
        let rows = structure.indexes.rows
        let selected = selectedIndex.flatMap { rows.indices.contains($0) ? rows[$0] : nil }
        return VStack(alignment: .leading, spacing: 0) {
            Text("Indexes").font(.headline).padding(6)
            SASQLiteResultTable(columns: [NSLocalizedString("Key Name", comment: "Index name"),
                                          NSLocalizedString("Unique", comment: "Index uniqueness"),
                                          NSLocalizedString("Columns", comment: "Index columns")],
                                types: [], rows: rows.map { [$0[0], $0[1], $0[4]] }, selection: $selectedIndex)
            schemaFooter {
                tableAction(NSImage.addTemplateName, name: "Add Index", enabled: model.canWrite && structure.object.kind == .table) {
                    editor = .init(content: .index(structure))
                }
                tableAction(NSImage.removeTemplateName, name: "Remove Index", enabled: model.canWrite && selected?.last?.string != nil) {
                    if let name = selected?.first?.string { confirm { model.apply(.dropIndex(name)) } }
                }
            }
        }
    }

    @ViewBuilder private var relationsView: some View {
        if let structure = model.page?.structure {
            let groups = Dictionary(grouping: structure.foreignKeys.rows, by: { $0[0].integer ?? -1 })
            let ids = groups.keys.sorted()
            let rows = ids.compactMap { id -> [SASQLiteValue]? in
                guard let group = groups[id], let first = group.first else { return nil }
                return [.integer(id), SASQLiteValue(group.compactMap { $0[3].string }.joined(separator: ", ")),
                        first[2], SASQLiteValue(group.compactMap { $0[4].string }.joined(separator: ", ")), first[5], first[6]]
            }
            let titles = [NSLocalizedString("Name", comment: "Foreign key identifier"),
                          NSLocalizedString("Columns", comment: "Foreign key columns"),
                          NSLocalizedString("Reference Table", comment: "Foreign key target table"),
                          NSLocalizedString("Reference Columns", comment: "Foreign key target columns"),
                          NSLocalizedString("On Update", comment: "Foreign key update action"),
                          NSLocalizedString("On Delete", comment: "Foreign key delete action")]
            VStack(spacing: 0) {
                SASQLiteResultTable(columns: titles, types: [], rows: rows, selection: $selectedRelation)
                schemaFooter {
                    let editable = model.canWrite && structure.object.kind == .table
                    tableAction(NSImage.addTemplateName, name: "Add Relation", enabled: editable) {
                        editor = .init(content: .relation(structure))
                    }
                    tableAction(NSImage.removeTemplateName, name: "Remove Relation", enabled: editable && selectedRelation.map(ids.indices.contains) == true) {
                        if let selectedRelation, ids.indices.contains(selectedRelation) {
                            confirm { model.apply(.dropRelation(structure.object, ids[selectedRelation])) }
                        }
                    }
                    tableAction(NSImage.refreshTemplateName, name: "Refresh", enabled: !model.busy) { model.reloadObjects() }
                }
            }
        } else {
            emptySelection
        }
    }

    @ViewBuilder private var triggersView: some View {
        if let structure = model.page?.structure {
            let triggers = structure.triggers.rows
            let rows = triggers.map { row in
                let header = SASQLiteTableDefinition.tokens(row[1].string ?? "").dropFirst(3).prefix { $0.text.uppercased() != "ON" }
                let event = header.first { ["INSERT", "UPDATE", "DELETE"].contains($0.text.uppercased()) }?.text.uppercased() ?? ""
                let timing = header.prefix { $0.text.uppercased() != event }.map { $0.text.uppercased() }.joined(separator: " ")
                return [row[0], SASQLiteValue(event), SASQLiteValue(timing), row[1]]
            }
            let titles = [NSLocalizedString("Trigger", comment: "Trigger name"), NSLocalizedString("Event", comment: "Trigger event"),
                          NSLocalizedString("Timing", comment: "Trigger timing"), NSLocalizedString("Statement", comment: "Trigger SQL")]
            VStack(spacing: 0) {
                SASQLiteResultTable(columns: titles, types: [], rows: rows, selection: $selectedTrigger) { index in
                    if model.canWrite, triggers.indices.contains(index) {
                        editor = .init(content: .trigger(structure.object, name: triggers[index][0].string, sql: triggers[index][1].string))
                    }
                }
                schemaFooter {
                    tableAction(NSImage.addTemplateName, name: "Add Trigger", enabled: model.canWrite && structure.object.kind != .virtual) {
                        editor = .init(content: .trigger(structure.object, name: nil, sql: nil))
                    }
                    tableAction(NSImage.removeTemplateName, name: "Remove Trigger", enabled: model.canWrite && selectedTrigger.map(triggers.indices.contains) == true) {
                        if let selectedTrigger, triggers.indices.contains(selectedTrigger), let name = triggers[selectedTrigger][0].string {
                            confirm { model.apply(.dropTrigger(name)) }
                        }
                    }
                    tableAction(NSImage.refreshTemplateName, name: "Refresh", enabled: !model.busy) { model.reloadObjects() }
                }
            }
        } else {
            emptySelection
        }
    }

    @ViewBuilder private var tableInfoView: some View {
        if let page = model.page {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    GroupBox("Table Information") {
                        Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 8) {
                            GridRow { Text("Name"); Text(page.structure.object.name) }
                            GridRow { Text("Type"); Text(page.structure.object.kind == .view ? "View" : "Table") }
                            GridRow { Text("Encoding"); Text(page.structure.encoding) }
                            GridRow { Text("Rows"); Text(page.totalRows.formatted()) }
                            GridRow { Text("Indexes"); Text(page.structure.indexes.rows.count.formatted()) }
                        }
                        .padding(10)
                    }
                    GroupBox("Create Syntax") {
                        Text(page.structure.definition ?? "")
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                    }
                    HStack {
                        Button("Copy CREATE Syntax") {
                            if let definition = page.structure.definition {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(definition, forType: .string)
                            }
                        }
                        Button("Refresh") { model.reloadObjects() }.disabled(model.busy)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
        } else {
            emptySelection
        }
    }

    private func schemaFooter<Buttons: View>(@ViewBuilder _ buttons: () -> Buttons) -> some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 0) { buttons(); Spacer() }
                .frame(height: 25)
                .background(.bar)
        }
    }

    private var queryView: some View {
        VSplitView {
            VStack(spacing: 0) {
                SASQLiteQueryEditor(model: model)
                    .frame(minHeight: 115)
                Divider()
                HStack {
                    Button("Format SQL") { model.queryEditor?.formatSQLiteSQL(nil) }
                        .keyboardShortcut("t", modifiers: [.control, .option, .command])
                        .disabled(model.busy || model.sql.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Spacer()
                    queryMenus
                    SASQLiteRunControl(model: model) { resultOffset = 0 }
                        .frame(width: 200, height: 22)
                }
                .padding(.horizontal, 6)
                .frame(height: 28)
                .background(.bar)
            }
            queryResults.frame(minHeight: 145)
        }
    }

    private var queryMenus: some View {
        HStack(spacing: 5) {
            Menu {
                Button("Save Query to Favorites") {
                    favoriteName = ""
                    showsFavoriteName = true
                }
                .disabled(model.sql.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if !model.queryFavorites.isEmpty { Divider() }
                ForEach(model.queryFavorites.indices, id: \.self) { index in
                    let favorite = model.queryFavorites[index]
                    Button(favorite["name"] ?? "") { model.sql = favorite["query"] ?? "" }
                }
            } label: {
                Image(systemName: "star")
            }
            .accessibilityLabel("Query Favorites")
            .help("Query Favorites")

            Menu {
                Button("Clear History") { showsClearHistory = true }.disabled(model.queryHistory.isEmpty)
                if !model.queryHistory.isEmpty { Divider() }
                ForEach(model.queryHistory.indices, id: \.self) { index in
                    let query = model.queryHistory[index]
                    Button(String(query.prefix(80))) { model.sql = query }
                }
            } label: {
                Image(systemName: "clock.arrow.circlepath")
            }
            .accessibilityLabel("Query History")
            .help("Query History")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func sortedQueryRows(_ rows: [[SASQLiteValue]]) -> [[SASQLiteValue]] {
        guard let column = querySortColumn else { return rows }
        return rows.enumerated().sorted { left, right in
            guard left.element.indices.contains(column), right.element.indices.contains(column) else { return left.offset < right.offset }
            let comparison = left.element[column].compare(to: right.element[column])
            if comparison == .orderedSame { return left.offset < right.offset }
            return comparison == (querySortDescending ? .orderedDescending : .orderedAscending)
        }.map(\.element)
    }

    @ViewBuilder private var queryResults: some View {
        if let statement = model.queryResult {
            let result = statement.result
            let rows = Array(sortedQueryRows(result?.rows ?? []).dropFirst(resultOffset).prefix(model.pageSize))
            VStack(alignment: .leading, spacing: 0) {
                if let error = statement.error {
                    ScrollView {
                        Text(error)
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                    }
                } else if let result, !result.columns.isEmpty {
                    HSplitView {
                        SASQLiteResultTable(columns: result.columns, types: result.columnTypes, rows: rows,
                                            selection: $model.selectedQueryRow, isQueryResult: true,
                                            sortColumn: querySortColumn, descending: querySortDescending, sort: { column in
                            querySortDescending = querySortColumn == column ? !querySortDescending : false
                            querySortColumn = column
                            resultOffset = 0
                            model.selectedQueryRow = nil
                        })
                        if model.showsRecord {
                            SARecordView(model: model.recordModel).frame(minWidth: 240, idealWidth: 320, maxWidth: 410)
                        }
                    }
                    .id(model.selectedResult)
                    .task(id: model.selectedQueryRow) {
                        let row = model.selectedQueryRow.flatMap { rows.indices.contains($0) ? rows[$0] : nil }
                        model.showRecord(columns: result.columns, row: row)
                    }
                } else {
                    Spacer()
                }

                Divider()
                HStack(spacing: 8) {
                    if model.scriptResults.count > 1 {
                        Picker("Statement", selection: $model.selectedResult) {
                            ForEach(model.scriptResults.indices, id: \.self) { index in
                                Text("Statement \(index + 1)").tag(index)
                            }
                        }
                        .fixedSize()
                        .task(id: model.selectedResult) {
                            resultOffset = 0
                            model.selectedQueryRow = nil
                            querySortColumn = nil
                        }
                    }
                    if let result, result.changedRows > 0 {
                        Text("Rows changed: \(result.changedRows)").foregroundStyle(.secondary)
                    }
                    if result?.truncated == true {
                        Text("Results are limited to 1,000 rows per run.").foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let result, !result.columns.isEmpty {
                        pager(offset: resultOffset, count: rows.count, hasMore: resultOffset + rows.count < result.rows.count) {
                            resultOffset = $0
                            model.selectedQueryRow = nil
                        }
                    }
                }
                .controlSize(.small)
                .padding(.horizontal, 5)
                .frame(height: 25)
                .background(.bar)
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

    private func pager(offset: Int, count: Int, hasMore: Bool, select: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 0) {
            tableAction(symbol: "chevron.left", name: "Previous", enabled: !model.busy && offset > 0) {
                select(max(0, offset - model.pageSize))
            }
            Text("Page \(offset / model.pageSize + 1) · \(count) rows")
                .font(.caption)
                .monospacedDigit()
            tableAction(symbol: "chevron.right", name: "Next", enabled: !model.busy && hasMore) {
                select(offset + model.pageSize)
            }
        }
    }

    private func tableAction(_ template: NSImage.Name? = nil, symbol: String = "", name: LocalizedStringKey,
                             enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if let template, let image = NSImage(named: template) {
                    Image(nsImage: image)
                } else {
                    Image(systemName: symbol)
                }
            }
            .frame(width: 25, height: 23)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(name)
        .help(name)
        .disabled(!enabled)
    }

    private func selectedColumn(in structure: SASQLiteStructure) -> SASQLiteColumn? {
        guard let index = model.selectedColumn, structure.visibleColumns.indices.contains(index) else { return nil }
        return structure.visibleColumns[index]
    }

    private func confirm(_ action: @escaping () -> Void) {
        guard model.canWrite else { return }
        deletion = action
        confirmsDeletion = true
    }

    private func submitSchema(_ change: SASQLiteSchemaChange) {
        editor = nil
        model.apply(change)
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
        case let .duplicateRow(structure, row):
            SASQLiteRowEditor(structure: structure, row: row, duplicating: true, cancel: { editor = nil }, save: { values in
                editor = nil
                model.save(values, row: nil, in: structure)
            })
        case let .column(structure, column, declaration):
            SASQLiteDeclarationEditor(title: "Edit Column", field: "Column Definition", cancel: { editor = nil }, save: { sql in
                submitSchema(.redefineColumn(structure.object, column, sql))
            }, declaration: declaration)
        case let .index(structure):
            SASQLiteIndexEditor(structure: structure, cancel: { editor = nil }, save: submitSchema)
        case let .relation(structure):
            SASQLiteRelationEditor(structure: structure, objects: model.objects, loadStructure: model.loadImportStructure,
                                   cancel: { editor = nil }, save: submitSchema)
        case let .trigger(object, name, sql):
            let table = SASQLiteConnection.identifier(object.name)
            let defaultSQL = "CREATE TRIGGER new_trigger \(object.kind == .view ? "INSTEAD OF" : "AFTER") INSERT ON \(table)\nBEGIN\n    SELECT 1;\nEND;"
            SASQLiteDeclarationEditor(title: name == nil ? "Add Trigger" : "Edit Trigger", field: "Trigger Definition",
                                       cancel: { editor = nil }, save: { submitSchema(.saveTrigger($0, replacing: name)) },
                                       declaration: sql ?? defaultSQL)
        }
    }
}
