import SwiftUI

struct SASQLiteEditorRequest: Identifiable {
    enum Content {
        case schema(SASQLiteSchemaEditor.Request)
        case row(SASQLiteStructure, SASQLiteRow?)
        case duplicateRow(SASQLiteStructure, SASQLiteRow)
        case column(SASQLiteStructure, SASQLiteColumn, String)
        case index(SASQLiteStructure)
        case relation(SASQLiteStructure)
        case trigger(SASQLiteObject, name: String?, sql: String?)
    }

    let id = UUID()
    let content: Content
}

struct SASQLiteSchemaEditor: View {
    enum Request {
        case createTable
        case renameTable(SASQLiteObject)
        case duplicateTable(SASQLiteObject)
        case addColumn(SASQLiteObject)
        case renameColumn(SASQLiteObject, SASQLiteColumn)

        var title: LocalizedStringKey {
            switch self {
            case .createTable: return "Create Table"
            case .renameTable: return "Rename Table"
            case .duplicateTable: return "Duplicate Table"
            case .addColumn: return "Add Column"
            case .renameColumn: return "Rename Column"
            }
        }
    }

    private struct Column: Identifiable {
        let id = UUID()
        var name = ""
        var type = SASQLiteColumnType.text
        var notNull = false
        var primaryKey = false

        var definition: SASQLiteColumnDefinition {
            .init(name: name, type: type, notNull: notNull, primaryKey: primaryKey)
        }
    }

    let request: Request
    let cancel: () -> Void
    let save: (SASQLiteSchemaChange, String?) -> Void
    @State private var name: String
    @State private var columns = [Column()]
    @State private var includeRows = true

    init(request: Request, cancel: @escaping () -> Void, save: @escaping (SASQLiteSchemaChange, String?) -> Void) {
        self.request = request
        self.cancel = cancel
        self.save = save
        switch request {
        case let .renameTable(object): _name = State(initialValue: object.name)
        case let .duplicateTable(object): _name = State(initialValue: object.name + "_copy")
        case let .renameColumn(_, column): _name = State(initialValue: column.name)
        default: _name = State(initialValue: "")
        }
        if case .createTable = request {
            _columns = State(initialValue: [Column(name: "id", type: .integer, notNull: true, primaryKey: true)])
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(request.title).font(.headline)
            switch request {
            case .createTable:
                TextField("Table Name", text: $name)
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach($columns) { $column in
                            HStack {
                                columnFields($column, primaryKey: true)
                                Button {
                                    columns.removeAll { $0.id == column.id }
                                } label: {
                                    Image(systemName: "minus.circle")
                                }
                                .accessibilityLabel("Remove Column")
                                .disabled(columns.count == 1)
                            }
                        }
                    }
                }
                .frame(maxHeight: 220)
                Button("Add Column") { columns.append(Column()) }
            case .addColumn:
                columnFields($columns[0], primaryKey: false)
            case .renameTable:
                TextField("Table Name", text: $name)
            case .duplicateTable:
                TextField("Table Name", text: $name)
                Toggle("Copy Table Content", isOn: $includeRows)
            case .renameColumn:
                TextField("Column Name", text: $name)
            }
            HStack {
                Spacer()
                Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
                Button("Save", action: submit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid)
            }
        }
        .padding(20)
        .frame(width: 540)
    }

    private func columnFields(_ column: Binding<Column>, primaryKey: Bool) -> some View {
        HStack {
            TextField("Column Name", text: column.name)
            Picker("Type", selection: column.type) {
                ForEach(SASQLiteColumnType.allCases, id: \.self) { type in Text(type.rawValue).tag(type) }
            }
            .fixedSize()
            if primaryKey {
                Toggle("NOT NULL", isOn: column.notNull)
                Toggle("Primary Key", isOn: column.primaryKey)
            }
        }
    }

    private var isValid: Bool {
        switch request {
        case .createTable:
            return validName(name) && columns.allSatisfy { validName($0.name) }
        case .addColumn:
            return validName(columns[0].name)
        case .renameTable, .duplicateTable, .renameColumn:
            return validName(name)
        }
    }

    private func validName(_ name: String) -> Bool {
        (try? SASQLiteConnection.validatedIdentifier(name)) != nil
    }

    private func submit() {
        switch request {
        case .createTable: save(.createTable(name, columns.map(\.definition)), name)
        case let .renameTable(object): save(.renameTable(object, name), name)
        case let .duplicateTable(object): save(.duplicateTable(object, name, includeRows: includeRows), name)
        case let .addColumn(object): save(.addColumn(object, columns[0].definition), nil)
        case let .renameColumn(object, column): save(.renameColumn(object, column, name), nil)
        }
    }
}

struct SASQLiteRowEditor: View {
    private enum Kind: CaseIterable {
        case databaseDefault, null, text, integer, real, blob

        var label: LocalizedStringKey {
            switch self {
            case .databaseDefault: return "Database Default"
            case .null: return "NULL"
            case .text: return "Text"
            case .integer: return "Integer"
            case .real: return "Real"
            case .blob: return "BLOB (Hex)"
            }
        }

        var takesInput: Bool { self != .null && self != .databaseDefault }
    }

    private struct Field: Identifiable {
        let column: SASQLiteColumn
        let original: SASQLiteValue?
        let initialKind: Kind
        let initialInput: String
        var kind: Kind
        var input: String

        var id: Int64 { column.id }

        init(column: SASQLiteColumn, original: SASQLiteValue?) {
            self.column = column
            self.original = original
            switch original {
            case nil: kind = .databaseDefault; input = ""
            case .null?: kind = .null; input = ""
            case let .blob(bytes)?: kind = .blob; input = SASQLiteValue.hex(bytes)
            case .text?: kind = .text; input = original?.display ?? ""
            case .integer?: kind = .integer; input = original?.display ?? ""
            case .real?: kind = .real; input = original?.display ?? ""
            }
            initialKind = kind
            initialInput = input
        }

        var changed: Bool { kind != initialKind || !input.utf8.elementsEqual(initialInput.utf8) }

        var value: SASQLiteValue? {
            switch kind {
            case .databaseDefault: return nil
            case .null: return .null
            case .text: return SASQLiteValue(input)
            case .integer: return Int64(input.trimmingCharacters(in: .whitespaces)).map(SASQLiteValue.integer)
            case .real:
                guard let number = Double(input.trimmingCharacters(in: .whitespaces)), !number.isNaN else { return nil }
                return .real(number)
            case .blob:
                let hex = Array(input.utf8)
                guard hex.count.isMultiple(of: 2) else { return nil }
                var bytes = Data()
                for index in stride(from: 0, to: hex.count, by: 2) {
                    guard let high = Self.hexDigit(hex[index]), let low = Self.hexDigit(hex[index + 1]) else { return nil }
                    bytes.append(high * 16 + low)
                }
                return .blob(bytes)
            }
        }

        private static func hexDigit(_ byte: UInt8) -> UInt8? {
            switch byte {
            case 48...57: return byte - 48
            case 65...70: return byte - 55
            case 97...102: return byte - 87
            default: return nil
            }
        }
    }

    let row: SASQLiteRow?
    let duplicating: Bool
    let cancel: () -> Void
    let save: ([Int64: SASQLiteValue]) -> Void
    @State private var fields: [Field]

    init(structure: SASQLiteStructure, row: SASQLiteRow?, duplicating: Bool = false, cancel: @escaping () -> Void,
         save: @escaping ([Int64: SASQLiteValue]) -> Void) {
        self.row = duplicating ? nil : row
        self.duplicating = duplicating
        self.cancel = cancel
        self.save = save
        _fields = State(initialValue: structure.visibleColumns.enumerated().compactMap { index, column in
            guard column.hidden == 0 else { return nil }
            let value = duplicating && column.primaryKeyPosition > 0 ? nil : row.map { $0.values[index] }
            return Field(column: column, original: value)
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(duplicating ? "Duplicate Row" : row == nil ? "Add Row" : "Edit Row").font(.headline)
            ScrollView {
                VStack(spacing: 10) {
                    ForEach($fields) { $field in
                        HStack {
                            Text(field.column.name).frame(width: 135, alignment: .leading)
                            Picker("Value Type", selection: $field.kind) {
                                ForEach(Kind.allCases.filter { row == nil || $0 != .databaseDefault }, id: \.self) { kind in
                                    Text(kind.label).tag(kind)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 130)
                            TextField("Value", text: $field.input)
                                .disabled(!field.kind.takesInput)
                        }
                    }
                }
            }
            .frame(minHeight: 100, maxHeight: 310)
            HStack {
                Spacer()
                Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
                Button("Save") { save(values) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(fields.contains { $0.changed && $0.kind.takesInput && $0.value == nil } || row != nil && values.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 570)
    }

    private var values: [Int64: SASQLiteValue] {
        Dictionary(uniqueKeysWithValues: fields.compactMap { field in
            guard row == nil || field.changed, let value = field.value else { return nil }
            return (field.id, value)
        })
    }
}

struct SASQLiteCSVImportView: View {
    let request: SASQLiteCSVImport
    let objects: [SASQLiteObject]
    let cancel: () -> Void
    let save: (SASQLiteCSVTarget, Bool) -> Void
    let loadStructure: (SASQLiteObject) async throws -> SASQLiteStructure
    @State private var target: Data?
    @State private var structure: SASQLiteStructure?
    @State private var mapping: [Int64?]
    @State private var names: [String]
    @State private var tableName = ""
    @State private var header = true
    @State private var schemaError: String?

    init(request: SASQLiteCSVImport, objects: [SASQLiteObject], current: SASQLiteStructure?, cancel: @escaping () -> Void,
         save: @escaping (SASQLiteCSVTarget, Bool) -> Void,
         loadStructure: @escaping (SASQLiteObject) async throws -> SASQLiteStructure) {
        self.request = request
        self.objects = objects.filter { $0.kind == .table }
        self.cancel = cancel
        self.save = save
        self.loadStructure = loadStructure
        let current = current?.object.kind == .table ? current : nil
        _target = State(initialValue: current?.object.id)
        _structure = State(initialValue: current)
        _mapping = State(initialValue: Self.defaultMapping(request.fields, columns: current?.writableColumns ?? [], header: true))
        _names = State(initialValue: Self.defaultNames(request.fields, header: true))
        _tableName = State(initialValue: request.url.deletingPathExtension().lastPathComponent)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Import CSV into SQLite").font(.headline)
            Text(request.url.lastPathComponent).foregroundStyle(.secondary)
            Toggle("First Record Contains Column Names", isOn: $header)
            Picker("Destination", selection: $target) {
                Text("New Table").tag(nil as Data?)
                ForEach(objects) { object in Text(object.name).tag(Optional(object.id)) }
            }
            if target == nil { TextField("Table Name", text: $tableName) }
            if let schemaError { Text(schemaError).foregroundStyle(.red) }
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(request.fields.indices, id: \.self) { index in
                        HStack {
                            if header, let name = request.fields[index], !name.isEmpty {
                                Text(name).frame(width: 150, alignment: .leading)
                            } else {
                                Text("CSV Field \(index + 1)").frame(width: 150, alignment: .leading)
                            }
                            if target == nil {
                                TextField("Column Name", text: $names[index])
                            } else {
                                Picker("Column", selection: $mapping[index]) {
                                    Text("Skip").tag(nil as Int64?)
                                    ForEach(structure?.writableColumns ?? []) { column in Text(column.name).tag(Optional(column.id)) }
                                }
                                .labelsHidden()
                            }
                        }
                    }
                }
            }
            .frame(minHeight: 110, maxHeight: 250)
            HStack {
                Spacer()
                Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
                Button("Import") {
                    if let transfer { save(transfer, header) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(transfer == nil)
            }
        }
        .padding(20)
        .frame(width: 480)
        .task(id: target) {
            guard structure?.object.id != target else { return }
            structure = nil
            schemaError = nil
            updateMapping()
            guard let target, let object = objects.first(where: { $0.id == target }) else { return }
            do {
                let loaded = try await loadStructure(object)
                guard !Task.isCancelled, self.target == loaded.object.id else { return }
                structure = loaded
                updateMapping()
            } catch {
                if !Task.isCancelled { schemaError = error.localizedDescription }
            }
        }
        .task(id: header) { updateMapping() }
    }

    private var transfer: SASQLiteCSVTarget? {
        if target == nil {
            guard (try? SASQLiteConnection.validatedIdentifier(tableName)) != nil,
                  names.allSatisfy({ (try? SASQLiteConnection.validatedIdentifier($0)) != nil }) else { return nil }
            return .newTable(tableName, columns: names)
        }
        let mapped = mapping.compactMap { $0 }
        guard let structure, !mapped.isEmpty, Set(mapped).count == mapped.count else { return nil }
        return .existing(structure, mapping: mapping)
    }

    private func updateMapping() {
        mapping = Self.defaultMapping(request.fields, columns: structure?.writableColumns ?? [], header: header)
        names = Self.defaultNames(request.fields, header: header)
    }

    private static func defaultMapping(_ fields: [String?], columns: [SASQLiteColumn], header: Bool) -> [Int64?] {
        if !header { return fields.indices.map { columns.indices.contains($0) ? columns[$0].id : nil } }
        return fields.map { field in
            columns.first { $0.name.caseInsensitiveCompare(field ?? "") == .orderedSame }?.id
        }
    }

    private static func defaultNames(_ fields: [String?], header: Bool) -> [String] {
        fields.enumerated().map { index, field in
            if header, let field, !field.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return field }
            return "column_\(index + 1)"
        }
    }
}

struct SASQLiteDeclarationEditor: View {
    let title: LocalizedStringKey
    let field: LocalizedStringKey
    let cancel: () -> Void
    let save: (String) -> Void
    @State var declaration: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            Text(field).foregroundStyle(.secondary)
            TextEditor(text: $declaration)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 95, maxHeight: 160)
                .border(.separator)
            HStack {
                Spacer()
                Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
                Button("Save") { save(declaration) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(declaration.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 540)
    }
}

struct SASQLiteIndexEditor: View {
    let structure: SASQLiteStructure
    let cancel: () -> Void
    let save: (SASQLiteSchemaChange) -> Void
    @State private var name = ""
    @State private var unique = false
    @State private var columns: Set<Int64> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Index").font(.headline)
            TextField("Index Name", text: $name)
            Picker("Type", selection: $unique) {
                Text("INDEX").tag(false)
                Text("UNIQUE").tag(true)
            }
            Text("Columns")
            List(structure.visibleColumns, selection: $columns) { column in
                Text(column.name).tag(column.id)
            }
            .frame(height: 135)
            HStack {
                Spacer()
                Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
                Button("Add") {
                    save(.addIndex(structure.object, name: name, columns: structure.visibleColumns.filter { columns.contains($0.id) }, unique: unique))
                }
                .keyboardShortcut(.defaultAction)
                .disabled(columns.isEmpty || (try? SASQLiteConnection.validatedIdentifier(name)) == nil)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}

struct SASQLiteRelationEditor: View {
    let structure: SASQLiteStructure
    let objects: [SASQLiteObject]
    let loadStructure: (SASQLiteObject) async throws -> SASQLiteStructure
    let cancel: () -> Void
    let save: (SASQLiteSchemaChange) -> Void

    @State private var name = ""
    @State private var source: String?
    @State private var destination: Data?
    @State private var destinationColumn: String?
    @State private var targetColumns: [SASQLiteColumn] = []
    @State private var schemaError: String?
    @State private var onUpdate = SASQLiteForeignKey.Action.noAction
    @State private var onDelete = SASQLiteForeignKey.Action.noAction

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Relation").font(.headline)
            TextField("Name", text: $name)
            columnPicker("Column", selection: $source, columns: structure.visibleColumns)
            Picker("Reference Table", selection: $destination) {
                Text("Choose Table").tag(nil as Data?)
                ForEach(objects.filter { $0.kind == .table }) { object in Text(object.name).tag(Optional(object.id)) }
            }
            columnPicker("Reference Column", selection: $destinationColumn, columns: targetColumns)
            actionPicker("On Update", selection: $onUpdate)
            actionPicker("On Delete", selection: $onDelete)
            if let schemaError { Text(schemaError).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
                Button("Add", action: submit).keyboardShortcut(.defaultAction)
                    .disabled(source == nil || destination == nil || destinationColumn == nil)
            }
        }
        .padding(20)
        .frame(width: 420)
        .task(id: destination) {
            targetColumns = []
            destinationColumn = nil
            schemaError = nil
            guard let destination, let object = objects.first(where: { $0.id == destination }) else { return }
            do {
                let target = try await loadStructure(object)
                guard !Task.isCancelled, self.destination == destination else { return }
                targetColumns = target.visibleColumns
                destinationColumn = target.primaryKey.first?.name ?? target.visibleColumns.first?.name
            } catch {
                if !Task.isCancelled { schemaError = error.localizedDescription }
            }
        }
    }

    private func columnPicker(_ title: LocalizedStringKey, selection: Binding<String?>, columns: [SASQLiteColumn]) -> some View {
        Picker(title, selection: selection) {
            Text("Choose Column").tag(nil as String?)
            ForEach(columns) { column in Text(column.name).tag(Optional(column.name)) }
        }
    }

    private func actionPicker(_ title: LocalizedStringKey, selection: Binding<SASQLiteForeignKey.Action>) -> some View {
        Picker(title, selection: selection) {
            ForEach(SASQLiteForeignKey.Action.allCases, id: \.self) { action in Text(action.rawValue).tag(action) }
        }
    }

    private func submit() {
        guard let source, let destination, let target = objects.first(where: { $0.id == destination }),
              let destinationColumn else { return }
        save(.addRelation(structure.object, SASQLiteForeignKey(name: name, from: source, referencedTable: target.name,
                                                              referencedColumn: destinationColumn, onUpdate: onUpdate, onDelete: onDelete)))
    }
}

struct SASQLiteExportPanel: View {
    private enum Format { case sql, csv, backup }
    private enum Source { case tables, query }

    @ObservedObject var model: SASQLiteWorkspaceModel
    let cancel: () -> Void
    let export: (@escaping () -> Void) -> Void
    @State private var format = Format.sql
    @State private var source = Source.tables
    private struct TableChoice: Identifiable {
        let object: SASQLiteObject
        var enabled: Bool
        var id: Data { object.id }
    }

    @State private var tables: [TableChoice] = []
    @State private var csvTable: Data?
    @State private var includesStructure = true
    @State private var includesContent = true
    @State private var includesDrop = false
    @State private var restore = false

    var body: some View {
        VStack(spacing: 10) {
            TabView(selection: $format) {
                sqlOptions.tabItem { Text("SQL") }.tag(Format.sql)
                csvOptions.tabItem { Text("CSV") }.tag(Format.csv)
                backupOptions.tabItem { Text("SQLite Backup") }.tag(Format.backup)
            }
            .frame(minHeight: 235)
            HStack {
                Spacer()
                Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
                Button("Export", action: submit).keyboardShortcut(.defaultAction).disabled(!canExport)
            }
        }
        .padding(16)
        .frame(width: 535)
        .onAppear {
            tables = model.objects.map { TableChoice(object: $0, enabled: $0.kind != .virtual) }
            csvTable = model.currentObject?.id ?? model.objects.first?.id
        }
    }

    private var sqlOptions: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Include")
                Toggle("Structure", isOn: $includesStructure)
                Toggle("Content", isOn: $includesContent)
                Toggle("DROP TABLE syntax", isOn: $includesDrop)
            }
            Divider()
            HStack {
                Text("Tables").font(.headline)
                Spacer()
                Button("Mark all tables") { setTables(true) }
                Button("Unmark all tables") { setTables(false) }
            }
            List($tables) { $table in
                Toggle(table.object.name, isOn: $table.enabled)
                    .disabled(table.object.kind == .virtual)
            }
        }
        .padding(10)
    }

    private var csvOptions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Source", selection: $source) {
                Text("Tables").tag(Source.tables)
                Text("Query Results").tag(Source.query)
                    .disabled(model.queryResult?.result?.columns.isEmpty != false)
            }
            if source == .tables {
                List(model.objects, selection: $csvTable) { object in
                    Label(object.name, image: object.kind == .view ? "table-view-small" : "table-small").tag(object.id)
                }
            } else {
                Text("Loaded Query Results as CSV…").foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(10)
    }

    private var backupOptions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("SQLite Backup", selection: $restore) {
                Text("Create SQLite Backup…").tag(false)
                Text("Restore as New SQLite Database…").tag(true)
            }
            .pickerStyle(.radioGroup)
            Spacer()
        }
        .padding(10)
    }

    private var selected: Set<Data> { Set(tables.filter(\.enabled).map(\.id)) }

    private func setTables(_ enabled: Bool) {
        for index in tables.indices where tables[index].object.kind != .virtual {
            tables[index].enabled = enabled
        }
    }

    private var canExport: Bool {
        switch format {
        case .sql: return !selected.isEmpty && (includesStructure || includesContent)
        case .csv: return source == .tables ? csvTable != nil : model.queryResult?.result?.columns.isEmpty == false
        case .backup: return true
        }
    }

    private func submit() {
        switch format {
        case .sql:
            let options = SASQLiteSQLExportOptions(objects: selected, structure: includesStructure,
                                                   content: includesContent, drop: includesStructure && includesDrop)
            export { model.exportSQL(options: options) }
        case .csv where source == .tables:
            if let object = model.objects.first(where: { $0.id == csvTable }) {
                export { model.exportTable(object) }
            }
        case .csv:
            export { model.exportResult() }
        case .backup:
            export { model.backup(restore: restore) }
        }
    }
}
