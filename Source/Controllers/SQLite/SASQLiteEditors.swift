import SwiftUI

struct SASQLiteEditorRequest: Identifiable {
    enum Content {
        case schema(SASQLiteSchemaEditor.Request)
        case row(SASQLiteStructure, SASQLiteRow?)
    }

    let id = UUID()
    let content: Content
}

struct SASQLiteSchemaEditor: View {
    enum Request {
        case createTable
        case renameTable(SASQLiteObject)
        case addColumn(SASQLiteObject)
        case renameColumn(SASQLiteObject, SASQLiteColumn)

        var title: LocalizedStringKey {
            switch self {
            case .createTable: return "Create Table"
            case .renameTable: return "Rename Table"
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

    init(request: Request, cancel: @escaping () -> Void, save: @escaping (SASQLiteSchemaChange, String?) -> Void) {
        self.request = request
        self.cancel = cancel
        self.save = save
        switch request {
        case let .renameTable(object): _name = State(initialValue: object.name)
        case let .renameColumn(_, column): _name = State(initialValue: column.name)
        default: _name = State(initialValue: "")
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
        case .renameTable, .renameColumn:
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
    let cancel: () -> Void
    let save: ([Int64: SASQLiteValue]) -> Void
    @State private var fields: [Field]

    init(structure: SASQLiteStructure, row: SASQLiteRow?, cancel: @escaping () -> Void,
         save: @escaping ([Int64: SASQLiteValue]) -> Void) {
        self.row = row
        self.cancel = cancel
        self.save = save
        _fields = State(initialValue: structure.visibleColumns.enumerated().compactMap { index, column in
            guard column.hidden == 0 else { return nil }
            return Field(column: column, original: row.map { $0.values[index] })
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(row == nil ? "Add Row" : "Edit Row").font(.headline)
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
