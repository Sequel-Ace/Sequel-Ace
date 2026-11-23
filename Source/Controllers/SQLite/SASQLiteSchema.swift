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
    let encoding: String

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
    let totalRows: Int64
    let matchingRows: Int64
}

struct SASQLiteBrowseOptions: Sendable {
    struct Filter: Sendable {
        enum Operator: String, CaseIterable, Sendable {
            case contains, equals, notEqual, beginsWith, endsWith, greaterThan, lessThan, isNull, isNotNull
        }

        let columnID: Int64
        let operation: Operator
        let value: String

        func predicate(for column: SASQLiteColumn) -> (String, [SASQLiteValue]) {
            let identifier = column.identifier
            switch operation {
            case .isNull: return (identifier + " IS NULL", [])
            case .isNotNull: return (identifier + " IS NOT NULL", [])
            case .equals: return (identifier + " = ?", [.init(value)])
            case .notEqual: return (identifier + " <> ?", [.init(value)])
            case .greaterThan: return (identifier + " > ?", [.init(value)])
            case .lessThan: return (identifier + " < ?", [.init(value)])
            case .contains, .beginsWith, .endsWith:
                let escaped = value.replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_")
                let prefix = operation == .beginsWith ? "" : "%"
                let suffix = operation == .endsWith ? "" : "%"
                return ("CAST(" + identifier + " AS TEXT) LIKE ? ESCAPE '\\'", [.init(prefix + escaped + suffix)])
            }
        }
    }

    var filter: Filter?
    var sortColumn: Int64?
    var descending = false
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
    case duplicateTable(SASQLiteObject, String, includeRows: Bool)
    case truncateTable(SASQLiteObject)
    case dropObject(SASQLiteObject)
    case addColumn(SASQLiteObject, SASQLiteColumnDefinition)
    case renameColumn(SASQLiteObject, SASQLiteColumn, String)
    case dropColumn(SASQLiteObject, SASQLiteColumn)
    case redefineColumn(SASQLiteObject, SASQLiteColumn, String)
    case addIndex(SASQLiteObject, name: String, columns: [SASQLiteColumn], unique: Bool)
    case dropIndex(String)
    case addRelation(SASQLiteObject, SASQLiteForeignKey)
    case dropRelation(SASQLiteObject, Int64)
    case saveTrigger(String, replacing: String?)
    case dropTrigger(String)
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
                   list.partial AS Partial,
                   (SELECT group_concat(name, ', ') FROM pragma_index_info(list.name, 'main')) AS Columns,
                   schema.sql AS SQL
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
                                 triggers: triggers, definition: definition, schemaVersion: try schemaVersion(),
                                 encoding: try query("PRAGMA main.encoding").rows.first?.first?.string ?? "")
    }

    func page(_ object: SASQLiteObject, offset: Int, size: Int, options: SASQLiteBrowseOptions = .init()) throws -> SASQLitePage {
        try readSnapshot {
            let structure = try structure(object)
            let rowID = structure.accessibleRowID.map(Self.identifier)
            let projection = (rowID.map { [$0] } ?? []) + structure.visibleColumns.map(\.identifier)
            guard !projection.isEmpty else { throw SASQLiteError.invalidInput }
            var order = rowID.map { [$0] } ?? structure.primaryKey.map(\.identifier)
            if let sortColumn = options.sortColumn, let column = structure.visibleColumns.first(where: { $0.id == sortColumn }) {
                order.insert(column.identifier + (options.descending ? " DESC" : " ASC"), at: 0)
            }
            let orderBy = order.isEmpty ? "" : " ORDER BY " + order.joined(separator: ", ")
            let filter = options.filter.flatMap { filter in
                structure.visibleColumns.first { $0.id == filter.columnID }.map { filter.predicate(for: $0) }
            }
            let whereSQL = filter.map { " WHERE " + $0.0 } ?? ""
            let parameters = filter?.1 ?? []
            let total = try query("SELECT count(*) FROM \(object.reference)").rows.first?.first?.integer ?? 0
            let matching = filter == nil ? total : try query("SELECT count(*) FROM \(object.reference)\(whereSQL)", bindings: parameters).rows.first?.first?.integer ?? 0
            let rows = try query("""
                SELECT \(projection.joined(separator: ", ")) FROM \(object.reference)\(whereSQL)\(orderBy) LIMIT ? OFFSET ?
                """, bindings: parameters + [.integer(Int64(size + 1)), .integer(Int64(offset))]).rows
            return SASQLitePage(structure: structure, rows: rows.prefix(size).map { values in
                SASQLiteRow(values: rowID == nil ? values : Array(values.dropFirst()),
                            rowID: rowID == nil ? nil : values.first?.integer)
            }, hasMore: rows.count > size, totalRows: total, matchingRows: matching)
        }
    }

    func apply(_ change: SASQLiteSchemaChange) throws {
        try requireIdleWriter()
        switch change {
        case let .createTable(name, columns):
            try createTable(name, columns: columns)
        case let .renameTable(object, name):
            try query("ALTER TABLE \(object.reference) RENAME TO \(Self.validatedIdentifier(name))")
        case let .duplicateTable(object, name, includeRows):
            try duplicateTable(object, as: name, includeRows: includeRows)
        case let .truncateTable(object):
            try query("DELETE FROM \(object.reference)")
        case let .dropObject(object):
            let kind = object.kind == .view ? "VIEW" : "TABLE"
            try query("DROP \(kind) \(object.reference)")
        case let .addColumn(object, column):
            try query("ALTER TABLE \(object.reference) ADD COLUMN \(column.sql())")
        case let .renameColumn(object, column, name):
            try query("ALTER TABLE \(object.reference) RENAME COLUMN \(column.identifier) TO \(Self.validatedIdentifier(name))")
        case let .dropColumn(object, column):
            try query("ALTER TABLE \(object.reference) DROP COLUMN \(column.identifier)")
        case let .redefineColumn(object, column, declaration):
            try rebuild(object) { definition, _ in
                try definition.redefineColumn(column.name, declaration: declaration)
            }
        case let .addIndex(object, name, columns, unique):
            guard !columns.isEmpty else { throw SASQLiteError.invalidInput }
            let index = try Self.validatedIdentifier(name)
            let table = Self.identifier(object.name)
            let names = columns.map(\.identifier).joined(separator: ", ")
            try query("CREATE \(unique ? "UNIQUE " : "")INDEX main.\(index) ON \(table) (\(names))")
        case let .dropIndex(name):
            try query("DROP INDEX main.\(Self.validatedIdentifier(name))")
        case let .addRelation(object, relation):
            try rebuild(object) { definition, _ in definition.terms.append(try relation.sql()) }
        case let .dropRelation(object, id):
            try rebuild(object) { definition, structure in
                try definition.removeForeignKey(id, metadata: structure.foreignKeys.rows)
            }
        case let .saveTrigger(sql, replacing):
            let tokens = SASQLiteTableDefinition.tokens(sql)
            guard tokens.first?.text.uppercased() == "CREATE",
                  tokens.dropFirst().first?.text.uppercased() == "TRIGGER",
                  let range = SASQLiteSQLStyle.currentStatement(in: sql, at: 0),
                  !tokens.contains(where: { $0.range.location >= NSMaxRange(range) }) else {
                throw SASQLiteError.invalidInput
            }
            try writeTransaction {
                if let replacing { try query("DROP TRIGGER main.\(Self.validatedIdentifier(replacing))") }
                try query(sql)
            }
        case let .dropTrigger(name):
            try query("DROP TRIGGER main.\(Self.validatedIdentifier(name))")
        }
    }

    private func duplicateTable(_ object: SASQLiteObject, as name: String, includeRows: Bool) throws {
        guard object.kind == .table else { throw SASQLiteError.invalidInput }
        let nameSQL = try Self.validatedIdentifier(name)
        try writeTransaction {
            let structure = try structure(object)
            guard let original = structure.definition else { throw SASQLiteError.invalidInput }
            let tokens = SASQLiteTableDefinition.tokens(original)
            guard let tableIndex = tokens.firstIndex(where: { $0.kind == .keyword && $0.text.uppercased() == "TABLE" }) else {
                throw SASQLiteError.invalidInput
            }
            var nameIndex = tableIndex + 1
            if tokens.dropFirst(nameIndex).prefix(3).map({ $0.text.uppercased() }) == ["IF", "NOT", "EXISTS"] {
                nameIndex += 3
            }
            guard tokens.indices.contains(nameIndex) else { throw SASQLiteError.invalidInput }
            let definition = (original as NSString).replacingCharacters(in: tokens[nameIndex].range, with: "main." + nameSQL)
            try query(definition)
            try duplicateIndexes(structure.indexes, into: name)
            if includeRows {
                let columns = structure.writableColumns.map(\.identifier).joined(separator: ", ")
                try query("INSERT INTO main.\(nameSQL) (\(columns)) SELECT \(columns) FROM \(object.reference)")
            }
        }
    }

    private func duplicateIndexes(_ indexes: SASQLiteResult, into tableName: String) throws {
        for row in indexes.rows {
            // Inline PRIMARY KEY and UNIQUE constraints recreate their own autoindexes.
            guard let sql = row.last?.string else { continue }
            guard let originalName = row.first?.string else { throw SASQLiteError.invalidInput }
            let tokens = SASQLiteTableDefinition.tokens(sql)
            guard let index = tokens.firstIndex(where: { $0.kind == .keyword && $0.text.uppercased() == "INDEX" }),
                  let on = tokens.indices.dropFirst(index + 1).first(where: { tokens[$0].kind == .keyword && tokens[$0].text.uppercased() == "ON" }),
                  tokens.indices.contains(on + 1) else { throw SASQLiteError.invalidInput }

            let baseName = tableName + "_" + originalName
            var name = baseName
            var suffix = 2
            while try !query("SELECT 1 FROM main.sqlite_schema WHERE name = ? COLLATE NOCASE", bindings: [.init(name)]).rows.isEmpty {
                name = baseName + "_" + String(suffix)
                suffix += 1
            }

            // Rewrite only the index and table names. Keep UNIQUE, expressions,
            // collations, sort directions, and any partial predicate intact.
            let original = sql as NSString
            let prefix = original.substring(to: NSMaxRange(tokens[index].range))
            let definition = original.substring(from: NSMaxRange(tokens[on + 1].range))
            try query("\(prefix) main.\(Self.identifier(name)) ON \(Self.identifier(tableName))\(definition)")
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

struct SASQLiteForeignKey: Sendable {
    enum Action: String, CaseIterable, Sendable {
        case noAction = "NO ACTION"
        case restrict = "RESTRICT"
        case cascade = "CASCADE"
        case setNull = "SET NULL"
        case setDefault = "SET DEFAULT"
    }

    let name: String
    let from: String
    let referencedTable: String
    let referencedColumn: String
    let onUpdate: Action
    let onDelete: Action

    func sql() throws -> String {
        let nameSQL = name.isEmpty ? "" : "CONSTRAINT " + (try SASQLiteConnection.validatedIdentifier(name)) + " "
        let source = try SASQLiteConnection.validatedIdentifier(from)
        let table = try SASQLiteConnection.validatedIdentifier(referencedTable)
        let target = try SASQLiteConnection.validatedIdentifier(referencedColumn)
        return "\(nameSQL)FOREIGN KEY (\(source)) REFERENCES \(table) (\(target)) ON UPDATE \(onUpdate.rawValue) ON DELETE \(onDelete.rawValue)"
    }
}

/// Preserve constraints and table options SQLite does not expose as form fields.
struct SASQLiteTableDefinition {
    var terms: [String]
    let suffix: String

    init(_ sql: String) throws {
        let tokens = Self.tokens(sql)
        guard let opening = tokens.firstIndex(where: { $0.kind == .symbol && $0.text == "(" }) else {
            throw SASQLiteError.invalidInput
        }
        let source = sql as NSString
        var terms: [String] = []
        var start = NSMaxRange(tokens[opening].range)
        var depth = 1
        for token in tokens.dropFirst(opening + 1) where token.kind == .symbol {
            if token.text == "(" { depth += 1 }
            if token.text == ")" { depth -= 1 }
            if depth == 0 || depth == 1 && token.text == "," {
                let text = source.substring(with: NSRange(location: start, length: token.range.location - start))
                terms.append(text.trimmingCharacters(in: .whitespacesAndNewlines))
                if depth == 0 {
                    self.terms = terms
                    suffix = source.substring(from: NSMaxRange(token.range))
                    return
                }
                start = NSMaxRange(token.range)
            }
        }
        throw SASQLiteError.invalidInput
    }

    func column(_ name: String) -> String? {
        terms.first { term in
            Self.tokens(term).first.map { Self.unquote($0).utf8.elementsEqual(name.utf8) } == true
        }
    }

    mutating func redefineColumn(_ name: String, declaration: String) throws {
        guard let original = column(name), let index = terms.firstIndex(of: original) else { throw SASQLiteError.invalidInput }
        let validation = try Self("CREATE TABLE validation (\(declaration))")
        guard validation.terms.count == 1, validation.suffix.isEmpty, validation.column(name) != nil else {
            throw SASQLiteError.invalidInput
        }
        terms[index] = declaration
    }

    mutating func removeForeignKey(_ id: Int64, metadata: [[SASQLiteValue]]) throws {
        // SQLite lists foreign keys in reverse declaration order. Verify the
        // candidate's source and target against the engine metadata before editing.
        let candidates = terms.indices.reversed().compactMap { index -> (Int, [SASQLiteSQLStyle.Token], Int)? in
            let tokens = Self.topLevelTokens(terms[index])
            guard let reference = tokens.firstIndex(where: { $0.kind == .keyword && $0.text.uppercased() == "REFERENCES" }) else { return nil }
            return (index, tokens, reference)
        }
        let keys = Set(metadata.compactMap { $0.first?.integer })
        guard candidates.count == keys.count, let index = Int(exactly: id), candidates.indices.contains(index),
              let metadata = metadata.first(where: { $0.first?.integer == id }) else { throw SASQLiteError.invalidInput }
        let (term, tokens, reference) = candidates[index]
        guard tokens.indices.contains(reference + 1),
              Self.unquote(tokens[reference + 1]).caseInsensitiveCompare(metadata[2].string ?? "") == .orderedSame else {
            throw SASQLiteError.invalidInput
        }
        if ["FOREIGN", "CONSTRAINT"].contains(tokens.first?.text.uppercased()) {
            terms.remove(at: term)
            return
        }
        guard let column = tokens.first,
              Self.unquote(column).caseInsensitiveCompare(metadata[3].string ?? "") == .orderedSame else {
            throw SASQLiteError.invalidInput
        }
        let followingConstraint = tokens.indices.dropFirst(reference + 2).first { i in
            guard tokens[i].kind == .keyword else { return false }
            let keyword = tokens[i].text.uppercased()
            if ["CONSTRAINT", "PRIMARY", "UNIQUE", "CHECK", "COLLATE", "GENERATED"].contains(keyword) { return true }
            if ["DEFAULT", "NULL"].contains(keyword) { return tokens[i - 1].text.uppercased() != "SET" }
            return keyword == "NOT" && tokens.indices.contains(i + 1) && tokens[i + 1].text.uppercased() == "NULL"
        }
        let start = reference >= 2 && tokens[reference - 2].text.uppercased() == "CONSTRAINT" ? reference - 2 : reference
        let source = terms[term] as NSString
        let from = tokens[start].range.location
        let to = followingConstraint.map { tokens[$0].range.location } ?? source.length
        terms[term] = source.replacingCharacters(in: NSRange(location: from, length: to - from), with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func tokens(_ sql: String) -> [SASQLiteSQLStyle.Token] {
        SASQLiteSQLStyle.tokens(in: sql).filter { ![.whitespace, .blockComment, .lineComment].contains($0.kind) }
    }

    private static func topLevelTokens(_ sql: String) -> [SASQLiteSQLStyle.Token] {
        var depth = 0
        return tokens(sql).filter { token in
            if token.kind == .symbol && token.text == "(" { depth += 1; return false }
            if token.kind == .symbol && token.text == ")" { depth -= 1; return false }
            return depth == 0
        }
    }

    private static func unquote(_ token: SASQLiteSQLStyle.Token) -> String {
        let text = token.text
        guard let first = text.utf8.first, [34, 39, 91, 96].contains(first), text.count >= 2 else { return text }
        let quote = String(decoding: [first], as: UTF8.self)
        return String(text.dropFirst().dropLast()).replacingOccurrences(of: quote + quote, with: quote)
    }
}

private extension SASQLiteConnection {
    func rebuild(_ object: SASQLiteObject, change: (inout SASQLiteTableDefinition, SASQLiteStructure) throws -> Void) throws {
        guard object.kind == .table else { throw SASQLiteError.invalidInput }
        let foreignKeys = try query("PRAGMA foreign_keys").rows.first?.first?.integer ?? 0
        let legacyRename = try query("PRAGMA legacy_alter_table").rows.first?.first?.integer ?? 0
        try query("PRAGMA foreign_keys=OFF")
        defer {
            _ = try? query("PRAGMA foreign_keys=\(foreignKeys)")
            _ = try? query("PRAGMA legacy_alter_table=\(legacyRename)")
        }
        try query("PRAGMA legacy_alter_table=ON")
        try writeTransaction {
            let original = try structure(object)
            guard let sql = original.definition else { throw SASQLiteError.invalidInput }
            var definition = try SASQLiteTableDefinition(sql)
            try change(&definition, original)

            let temporaryName = "sequel_ace_rebuild_" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
            let temporary = SASQLiteObject(name: temporaryName, kind: .table, withoutRowID: object.withoutRowID)
            let create = "CREATE TABLE \(temporary.reference) (\(definition.terms.joined(separator: ",\n")))\(definition.suffix)"
            try query(create)
            let destination = try structure(temporary)
            let originalNames = Set(original.visibleColumns.map { Data($0.name.utf8) })
            let common = destination.writableColumns.filter { originalNames.contains(Data($0.name.utf8)) }.map(\.identifier)
            let sourceID = original.accessibleRowID.map(Self.identifier)
            let targetID = destination.accessibleRowID.map(Self.identifier)
            var source = common
            var target = common
            if let sourceID, let targetID {
                source.insert(sourceID, at: 0)
                target.insert(targetID, at: 0)
            }
            guard !source.isEmpty else { throw SASQLiteError.invalidInput }
            try query("INSERT INTO \(temporary.reference) (\(target.joined(separator: ", "))) SELECT \(source.joined(separator: ", ")) FROM \(object.reference)")

            let hasSequence = try query("SELECT 1 FROM main.sqlite_schema WHERE name='sqlite_sequence'").rows.first != nil
            let sequence = hasSequence
                ? try query("SELECT seq FROM main.sqlite_sequence WHERE name = ?", bindings: [SASQLiteValue(object.name)]).rows.first?.first
                : nil
            try query("DROP TABLE \(object.reference)")
            try query("ALTER TABLE \(temporary.reference) RENAME TO \(Self.identifier(object.name))")
            if let sequence, SASQLiteTableDefinition.tokens(create).contains(where: { $0.kind == .keyword && $0.text.uppercased() == "AUTOINCREMENT" }) {
                try query("DELETE FROM main.sqlite_sequence WHERE name = ?", bindings: [SASQLiteValue(object.name)])
                try query("INSERT INTO main.sqlite_sequence(name, seq) VALUES (?, ?)", bindings: [SASQLiteValue(object.name), sequence])
            }
            for sql in original.indexes.rows.compactMap({ $0.last?.string }) + original.triggers.rows.compactMap({ $0.last?.string }) {
                try query(sql)
            }
            guard try query("PRAGMA main.foreign_key_check", limit: 1).rows.isEmpty else { throw SASQLiteError.foreignKeyViolation }
        }
    }
}
