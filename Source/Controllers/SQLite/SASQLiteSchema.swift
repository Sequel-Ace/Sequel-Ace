import Foundation

struct SASQLiteObject: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable {
        case table, view, virtual
    }

    let name: String
    let kind: Kind
    let withoutRowID: Bool

    var id: Data { Data(name.utf8) }
    var reference: String { "main." + SASQLiteConnection.identifier(name) }
}

struct SASQLiteColumn: Identifiable, Sendable {
    let id: Int64
    let name: String
    let type: String
    let notNull: Bool
    let defaultSQL: String?
    let primaryKeyPosition: Int64
    let hidden: Int64

    var identifier: String { SASQLiteConnection.identifier(name) }
    var generated: Bool { hidden == 2 || hidden == 3 }
}

struct SASQLiteStructure: Sendable {
    let object: SASQLiteObject
    let columns: [SASQLiteColumn]
    let indexes: SASQLiteResult
    let foreignKeys: SASQLiteResult
    let triggers: SASQLiteResult
    let definition: String?
    let schemaVersion: Int64

    var accessibleRowID: String? {
        guard object.kind == .table, !object.withoutRowID else { return nil }
        let names = Set(columns.map { $0.name.lowercased() })
        return ["rowid", "_rowid_", "oid"].first { !names.contains($0) }
    }

    var primaryKey: [SASQLiteColumn] {
        columns.filter { $0.primaryKeyPosition > 0 }.sorted { $0.primaryKeyPosition < $1.primaryKeyPosition }
    }

    var visibleColumns: [SASQLiteColumn] { columns.filter { $0.hidden != 1 } }
    var writableColumns: [SASQLiteColumn] { columns.filter { $0.hidden == 0 } }
}

struct SASQLiteRow: Sendable {
    let values: [SASQLiteValue]
    let rowID: Int64?
}

struct SASQLitePage: Sendable {
    let structure: SASQLiteStructure
    let rows: [SASQLiteRow]
    let hasMore: Bool
}

enum SASQLiteColumnType: String, CaseIterable, Sendable {
    case integer = "INTEGER"
    case real = "REAL"
    case text = "TEXT"
    case blob = "BLOB"
    case numeric = "NUMERIC"
}

struct SASQLiteColumnDefinition: Sendable {
    let name: String
    let type: SASQLiteColumnType
    let notNull: Bool
    let primaryKey: Bool

    func sql() throws -> String {
        try SASQLiteConnection.validatedIdentifier(name) + " " + type.rawValue + (notNull ? " NOT NULL" : "")
    }
}

enum SASQLiteSchemaChange: Sendable {
    case createTable(String, [SASQLiteColumnDefinition])
    case renameTable(SASQLiteObject, String)
    case dropObject(SASQLiteObject)
    case addColumn(SASQLiteObject, SASQLiteColumnDefinition)
    case renameColumn(SASQLiteObject, SASQLiteColumn, String)
    case dropColumn(SASQLiteObject, SASQLiteColumn)
}

extension SASQLiteConnection {
    func objects() throws -> [SASQLiteObject] {
        try query("""
            SELECT name, type, wr FROM pragma_table_list
            WHERE schema = 'main' AND type IN ('table', 'view', 'virtual') AND name NOT LIKE 'sqlite\\_%' ESCAPE '\\'
            ORDER BY name COLLATE NOCASE, name
            """).rows.compactMap { row in
            guard let name = row[0].string, let type = row[1].string, let kind = SASQLiteObject.Kind(rawValue: type) else {
                return nil
            }
            return SASQLiteObject(name: name, kind: kind, withoutRowID: row[2].integer == 1)
        }
    }

    func structure(_ object: SASQLiteObject) throws -> SASQLiteStructure {
        let bindings = [SASQLiteValue(object.name)]
        let columns = try query("""
            SELECT cid, name, type, "notnull", dflt_value, pk, hidden
            FROM pragma_table_xinfo(?, 'main') ORDER BY cid
            """, bindings: bindings).rows.compactMap { row -> SASQLiteColumn? in
                guard let id = row[0].integer, let name = row[1].string else { return nil }
                return SASQLiteColumn(id: id, name: name, type: row[2].string ?? "", notNull: row[3].integer == 1,
                                      defaultSQL: row[4].string, primaryKeyPosition: row[5].integer ?? 0, hidden: row[6].integer ?? 0)
            }
        let indexes = try query("""
            SELECT list.name AS Name, list."unique" AS "Unique", list.origin AS Origin,
                   list.partial AS Partial, schema.sql AS SQL
            FROM pragma_index_list(?, 'main') AS list
            LEFT JOIN main.sqlite_schema AS schema ON schema.name = list.name AND schema.type = 'index'
            ORDER BY list.name
            """, bindings: bindings)
        let foreignKeys = try query("""
            SELECT id, seq, "table", "from", "to", on_update, on_delete, match
            FROM pragma_foreign_key_list(?, 'main') ORDER BY id, seq
            """, bindings: bindings)
        let triggers = try query("""
            SELECT name, sql FROM main.sqlite_schema WHERE type = 'trigger' AND tbl_name = ? ORDER BY name
            """, bindings: bindings)
        let definition = try query("""
            SELECT sql FROM main.sqlite_schema WHERE name = ? AND type IN ('table', 'view')
            """, bindings: bindings).rows.first?.first?.string
        return SASQLiteStructure(object: object, columns: columns, indexes: indexes, foreignKeys: foreignKeys,
                                 triggers: triggers, definition: definition, schemaVersion: try schemaVersion())
    }

    func page(_ object: SASQLiteObject, offset: Int, size: Int) throws -> SASQLitePage {
        try readSnapshot {
            let structure = try structure(object)
            let rowID = structure.accessibleRowID.map(Self.identifier)
            let projection = (rowID.map { [$0] } ?? []) + structure.visibleColumns.map(\.identifier)
            guard !projection.isEmpty else { throw SASQLiteError.invalidInput }
            let order = rowID.map { [$0] } ?? structure.primaryKey.map(\.identifier)
            let orderBy = order.isEmpty ? "" : " ORDER BY " + order.joined(separator: ", ")
            let rows = try query("""
                SELECT \(projection.joined(separator: ", ")) FROM \(object.reference)\(orderBy) LIMIT ? OFFSET ?
                """, bindings: [.integer(Int64(size + 1)), .integer(Int64(offset))]).rows
            return SASQLitePage(structure: structure, rows: rows.prefix(size).map { values in
                SASQLiteRow(values: rowID == nil ? values : Array(values.dropFirst()),
                            rowID: rowID == nil ? nil : values.first?.integer)
            }, hasMore: rows.count > size)
        }
    }

    func apply(_ change: SASQLiteSchemaChange) throws {
        try requireIdleWriter()
        switch change {
        case let .createTable(name, columns):
            try createTable(name, columns: columns)
        case let .renameTable(object, name):
            try query("ALTER TABLE \(object.reference) RENAME TO \(Self.validatedIdentifier(name))")
        case let .dropObject(object):
            let kind = object.kind == .view ? "VIEW" : "TABLE"
            try query("DROP \(kind) \(object.reference)")
        case let .addColumn(object, column):
            try query("ALTER TABLE \(object.reference) ADD COLUMN \(column.sql())")
        case let .renameColumn(object, column, name):
            try query("ALTER TABLE \(object.reference) RENAME COLUMN \(column.identifier) TO \(Self.validatedIdentifier(name))")
        case let .dropColumn(object, column):
            try query("ALTER TABLE \(object.reference) DROP COLUMN \(column.identifier)")
        }
    }

    func createTable(_ name: String, columns: [SASQLiteColumnDefinition]) throws {
        guard !columns.isEmpty else { throw SASQLiteError.invalidInput }
        var definitions = try columns.map { try $0.sql() }
        let keys = columns.filter(\.primaryKey)
        if !keys.isEmpty {
            let identifiers = try keys.map { try Self.validatedIdentifier($0.name) }.joined(separator: ", ")
            definitions.append("PRIMARY KEY (\(identifiers))")
        }
        try query("CREATE TABLE main.\(Self.validatedIdentifier(name)) (\(definitions.joined(separator: ", ")))")
    }

    func insert(_ values: [Int64: SASQLiteValue], into structure: SASQLiteStructure) throws {
        try writeTransaction {
            try validate(structure)
            let columns = structure.writableColumns.filter { values[$0.id] != nil }
            guard columns.count == values.count else { throw SASQLiteError.invalidInput }
            if columns.isEmpty {
                try query("INSERT INTO \(structure.object.reference) DEFAULT VALUES")
                return
            }
            let names = columns.map(\.identifier).joined(separator: ", ")
            let placeholders = Array(repeating: "?", count: columns.count).joined(separator: ", ")
            try query("INSERT INTO \(structure.object.reference) (\(names)) VALUES (\(placeholders))",
                      bindings: columns.compactMap { values[$0.id] })
        }
    }

    func update(_ values: [Int64: SASQLiteValue], row: SASQLiteRow, in structure: SASQLiteStructure) throws {
        try writeTransaction {
            let selector = try check(row, in: structure)
            let columns = structure.writableColumns.filter { values[$0.id] != nil }
            guard columns.count == values.count, !columns.isEmpty else { throw SASQLiteError.invalidInput }
            let assignments = columns.map { $0.identifier + " = ?" }.joined(separator: ", ")
            try query("UPDATE \(structure.object.reference) SET \(assignments) WHERE \(selector.predicate)",
                      bindings: columns.compactMap { values[$0.id] } + selector.bindings)
        }
    }

    func delete(_ row: SASQLiteRow, in structure: SASQLiteStructure) throws {
        try writeTransaction {
            let selector = try check(row, in: structure)
            try query("DELETE FROM \(structure.object.reference) WHERE \(selector.predicate)", bindings: selector.bindings)
        }
    }

    private func schemaVersion() throws -> Int64 {
        try query("PRAGMA main.schema_version").rows.first?.first?.integer ?? 0
    }

    private func validate(_ structure: SASQLiteStructure) throws {
        guard structure.object.kind == .table else { throw SASQLiteError.noActiveRow }
        guard try schemaVersion() == structure.schemaVersion else { throw SASQLiteError.rowChanged }
    }

    private func check(_ row: SASQLiteRow, in structure: SASQLiteStructure) throws -> (predicate: String, bindings: [SASQLiteValue]) {
        try validate(structure)
        let selector = try structure.selector(for: row)
        let columns = structure.visibleColumns.map(\.identifier).joined(separator: ", ")
        let current = try query("SELECT \(columns) FROM \(structure.object.reference) WHERE \(selector.predicate) LIMIT 2",
                                bindings: selector.bindings).rows
        guard current == [row.values] else { throw SASQLiteError.rowChanged }
        return selector
    }
}

extension SASQLiteStructure {
    func selector(for row: SASQLiteRow) throws -> (predicate: String, bindings: [SASQLiteValue]) {
        if let alias = accessibleRowID, let rowID = row.rowID {
            return (SASQLiteConnection.identifier(alias) + " = ?", [.integer(rowID)])
        }
        let keys = primaryKey
        let columns = visibleColumns
        let values = keys.compactMap { key in columns.firstIndex { $0.id == key.id }.map { row.values[$0] } }
        guard object.kind == .table, !keys.isEmpty, values.count == keys.count, !values.contains(.null) else {
            throw SASQLiteError.noActiveRow
        }
        return (keys.map { $0.identifier + " COLLATE BINARY IS ?" }.joined(separator: " AND "), values)
    }
}
