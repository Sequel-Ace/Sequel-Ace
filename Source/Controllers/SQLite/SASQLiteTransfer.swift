import Foundation
import SQLite3

struct SASQLiteSQLExportOptions: Sendable {
    var objects: Set<Data>?
    var structure = true
    var content = true
    var drop = false
}

enum SASQLiteCSVTarget: Sendable {
    case existing(SASQLiteStructure, mapping: [Int64?])
    case newTable(String, columns: [String])
}

enum SASQLiteCSV {
    /// Comma-separated UTF-8, with optional BOM and CRLF, CR or LF records.
    /// An unquoted \N denotes NULL. A quoted "\N" and empty fields are text.
    static func read(_ url: URL, cancellation: SASQLiteCancellation, limit: Int? = nil,
                     record: ([String?], Int) throws -> Void) throws {
        enum State { case start, bare, quoted, closingQuote }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }

        var state = State.start
        var field: [UInt8] = []
        var fields: [String?] = []
        var number = 0
        var skipLF = false

        func finishField() throws {
            guard let text = String(bytes: field, encoding: .utf8) else { throw SASQLiteError.invalidCSV(number + 1) }
            fields.append(state != .closingQuote && text == #"\N"# ? nil : text)
            field.removeAll(keepingCapacity: true)
            state = .start
        }

        func finishRecord() throws {
            try finishField()
            number += 1
            try record(fields, number)
            fields.removeAll(keepingCapacity: true)
        }

        var firstChunk = true
        while let data = try file.read(upToCount: 64 * 1024), !data.isEmpty {
            try cancellation.check()
            let bytes = firstChunk && data.starts(with: [0xef, 0xbb, 0xbf]) ? data.dropFirst(3) : data[...]
            firstChunk = false
            for byte in bytes {
                if skipLF {
                    skipLF = false
                    if byte == 10 { continue }
                }
                if state == .quoted {
                    if byte == 34 { state = .closingQuote } else { field.append(byte) }
                    continue
                }
                switch byte {
                case 34 where state == .start:
                    state = .quoted
                case 34 where state == .closingQuote:
                    field.append(byte)
                    state = .quoted
                case 44:
                    try finishField()
                case 10, 13:
                    try finishRecord()
                    if number == limit { return }
                    skipLF = byte == 13
                default:
                    guard byte != 34, state != .closingQuote else { throw SASQLiteError.invalidCSV(number + 1) }
                    field.append(byte)
                    state = .bare
                }
            }
        }
        guard state != .quoted else { throw SASQLiteError.invalidCSV(number + 1) }
        if state != .start || !fields.isEmpty { try finishRecord() }
    }

    static func preview(_ url: URL, cancellation: SASQLiteCancellation) throws -> [String?] {
        var fields: [String?] = []
        try read(url, cancellation: cancellation, limit: 1) { fields = $0; _ = $1 }
        guard !fields.isEmpty else { throw SASQLiteError.invalidCSV(1) }
        return fields
    }

    static func line(_ values: [SASQLiteValue]) -> String {
        values.map { value in
            if value == .null { return #"\N"# }
            let text = value.display
            if text.isEmpty || text == #"\N"# || text.utf8.contains(where: { [34, 44, 10, 13].contains($0) }) {
                return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            }
            return text
        }.joined(separator: ",") + "\r\n"
    }
}

enum SASQLiteOutput {
    /// Stage on the destination volume so a failed write never replaces the output.
    static func stage(at destination: URL, replace: Bool, _ write: (URL) throws -> Void) throws {
        let files = FileManager.default
        if !replace, files.fileExists(atPath: destination.path) { throw SASQLiteError.existingDestination }
        let directory = destination.deletingLastPathComponent().appendingPathComponent(".sequel-ace-\(UUID().uuidString)", isDirectory: true)
        try files.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? files.removeItem(at: directory) }
        let staged = directory.appendingPathComponent(destination.lastPathComponent)
        try write(staged)
        if replace, files.fileExists(atPath: destination.path) {
            _ = try files.replaceItemAt(destination, withItemAt: staged)
        } else {
            try files.moveItem(at: staged, to: destination)
        }
    }

    static func text(at destination: URL, write: ((String) throws -> Void) throws -> Void) throws {
        if let existing = try? FileHandle(forReadingFrom: destination) {
            defer { try? existing.close() }
            let magic = Data("SQLite format 3\0".utf8)
            if try existing.read(upToCount: magic.count) == magic { throw SASQLiteError.existingDestination }
        }
        try stage(at: destination, replace: true) { staged in
            try Data().write(to: staged, options: .withoutOverwriting)
            let file = try FileHandle(forWritingTo: staged)
            do {
                try write { try file.write(contentsOf: Data($0.utf8)) }
                try file.close()
            } catch {
                try? file.close()
                throw error
            }
        }
    }
}

extension SASQLiteConnection {
    func importCSV(_ url: URL, into target: SASQLiteCSVTarget, hasHeader: Bool,
                   cancellation: SASQLiteCancellation) throws {
        try writeTransaction {
            let reference: String
            let mapping: [String?]
            switch target {
            case let .existing(structure, columnIDs):
                guard structure.object.kind == .table,
                      try query("PRAGMA main.schema_version").rows.first?.first?.integer == structure.schemaVersion else {
                    throw SASQLiteError.rowChanged
                }
                reference = structure.object.reference
                let writable = structure.writableColumns
                mapping = try columnIDs.map { id in
                    guard let id else { return nil }
                    guard let column = writable.first(where: { $0.id == id }) else { throw SASQLiteError.invalidInput }
                    return column.identifier
                }
            case let .newTable(name, names):
                try createTable(name, columns: names.map { .init(name: $0, type: .text, notNull: false, primaryKey: false) })
                reference = "main." + (try Self.validatedIdentifier(name))
                mapping = try names.map { try Self.validatedIdentifier($0) }
            }
            let columns = mapping.compactMap { $0 }
            guard !columns.isEmpty, Set(columns).count == columns.count else { throw SASQLiteError.invalidInput }
            let placeholders = Array(repeating: "?", count: columns.count).joined(separator: ", ")
            let insert = "INSERT INTO \(reference) (\(columns.joined(separator: ", "))) VALUES (\(placeholders))"
            var sawRecord = false
            try SASQLiteCSV.read(url, cancellation: cancellation) { fields, number in
                sawRecord = true
                guard fields.count == mapping.count else { throw SASQLiteError.invalidCSV(number) }
                if hasHeader && number == 1 { return }
                let values: [SASQLiteValue] = zip(mapping, fields).compactMap { column, field in
                    guard column != nil else { return nil }
                    return field.map(SASQLiteValue.init) ?? .null
                }
                try query(insert, bindings: values)
            }
            guard sawRecord else { throw SASQLiteError.invalidCSV(1) }
            try cancellation.check()
        }
    }

    func exportCSV(_ object: SASQLiteObject, to destination: URL, cancellation: SASQLiteCancellation) throws {
        try readSnapshot {
            let columns = try structure(object).visibleColumns
            guard !columns.isEmpty else { throw SASQLiteError.invalidInput }
            try SASQLiteOutput.text(at: destination) { write in
                try write(SASQLiteCSV.line(columns.map { SASQLiteValue($0.name) }))
                try stream("SELECT \(columns.map(\.identifier).joined(separator: ", ")) FROM \(object.reference)") { row in
                    try cancellation.check()
                    try write(SASQLiteCSV.line(row))
                }
                try cancellation.check()
            }
        }
    }

    func exportSQL(to destination: URL, cancellation: SASQLiteCancellation, options: SASQLiteSQLExportOptions = .init()) throws {
        try readSnapshot {
            let objects = try objects().filter { options.objects?.contains($0.id) ?? true }
            let tables = objects.filter { $0.kind != .view }
            guard !tables.contains(where: { $0.kind == .virtual }) else { throw SASQLiteError.virtualTableDump }
            try SASQLiteOutput.text(at: destination) { write in
                try write("PRAGMA foreign_keys=OFF;\nBEGIN TRANSACTION;\n")
                let structures = try tables.map { try structure($0) }
                if options.drop {
                    for object in objects.filter({ $0.kind == .view }) + tables {
                        let kind = object.kind == .view ? "VIEW" : "TABLE"
                        try write("DROP \(kind) IF EXISTS \(Self.identifier(object.name));\n")
                    }
                }
                if options.structure {
                    for table in structures {
                        try cancellation.check()
                        if let sql = table.definition { try write(sql + ";\n") }
                    }
                }
                if options.content {
                    for table in structures {
                        let rowID = table.accessibleRowID.map { [Self.identifier($0)] } ?? []
                        let columns = (rowID + table.writableColumns.map(\.identifier)).joined(separator: ", ")
                        let prefix = "INSERT INTO \(Self.identifier(table.object.name)) (\(columns)) VALUES ("
                        try stream("SELECT \(columns) FROM \(table.object.reference)") { row in
                            try cancellation.check()
                            try write(prefix + row.map(\.sqlLiteral).joined(separator: ", ") + ");\n")
                        }
                    }
                    if try query("SELECT 1 FROM main.sqlite_schema WHERE name = 'sqlite_sequence'").rows.first != nil {
                        let exported = Set(tables.map(\.id))
                        try stream("SELECT name, seq FROM main.sqlite_sequence") { row in
                            guard let table = row[0].string, exported.contains(Data(table.utf8)) else { return }
                            let name = row[0].sqlLiteral
                            try write("DELETE FROM sqlite_sequence WHERE name = \(name);\n")
                            try write("INSERT INTO sqlite_sequence VALUES(\(name),\(row[1].sqlLiteral));\n")
                        }
                    }
                }
                if options.structure {
                    let exported = Set(objects.map(\.id))
                    try stream("""
                        SELECT tbl_name, sql FROM main.sqlite_schema
                        WHERE type IN ('index', 'view', 'trigger') AND sql IS NOT NULL
                        ORDER BY CASE type WHEN 'index' THEN 0 WHEN 'view' THEN 1 ELSE 2 END, rowid
                        """) { row in
                            if let table = row[0].string, exported.contains(Data(table.utf8)), let sql = row[1].string {
                                try write(sql + ";\n")
                            }
                        }
                }
                try cancellation.check()
                try write("COMMIT;\n")
            }
        }
    }

    func importSQL(_ url: URL, cancellation: SASQLiteCancellation) throws {
        try requireIdleWriter()
        let enforceForeignKeys = try query("PRAGMA foreign_keys").rows.first?.first?.integer == 1
        if enforceForeignKeys { try query("PRAGMA foreign_keys=OFF") }
        defer { if enforceForeignKeys { _ = try? query("PRAGMA foreign_keys=ON") } }

        try writeTransaction {
            var began = false
            var committed = false
            var executed = false
            try Self.readSQL(url, cancellation: cancellation) { sql in
                let body = Self.withoutLeadingSQLComments(sql)
                guard !body.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ";"))).isEmpty else { return }
                guard !committed else { throw SASQLiteError.unsafeImport }
                if !began, !executed, Self.isSQLWrapper(body, #"PRAGMA\s+foreign_keys\s*=\s*(?:OFF|0)"#) {
                    return
                }
                if !began, !executed, Self.isSQLWrapper(body, #"BEGIN(?:\s+(?:DEFERRED|IMMEDIATE|EXCLUSIVE))?(?:\s+TRANSACTION)?"#) {
                    began = true
                    return
                }
                if began, Self.isSQLWrapper(body, #"(?:COMMIT|END)(?:\s+TRANSACTION)?"#) {
                    committed = true
                    return
                }

                setAuthorization(.importStatement)
                defer { setAuthorization(.workspace) }
                do {
                    try query(body, limit: 0)
                } catch SASQLiteError.engine(let code, _) where code & 0xff == SQLITE_AUTH {
                    throw SASQLiteError.unsafeImport
                }
                guard inTransaction else { throw SASQLiteError.unsafeImport }
                executed = true
            }
            guard !began || committed else { throw SASQLiteError.unsafeImport }
            guard try query("PRAGMA main.foreign_key_check", limit: 1).rows.isEmpty else {
                throw SASQLiteError.foreignKeyViolation
            }
            try cancellation.check()
        }
    }

    func backup(to destination: URL, cancellation: SASQLiteCancellation) throws {
        guard !inTransaction else { throw SASQLiteError.openTransaction }
        try SASQLiteOutput.stage(at: destination, replace: false) { staged in
            try copyPages(to: staged, cancellation: cancellation)
            // A WAL-mode source can leave WAL flags in the copied header.
            // Publish a standalone file that also opens from a read-only folder.
            let standalone = try SASQLiteConnection(url: staged, readOnly: false)
            try standalone.query("PRAGMA journal_mode=DELETE")
            try cancellation.check()
        }
    }

    private func copyPages(to staged: URL, cancellation: SASQLiteCancellation) throws {
        let target = try SASQLiteConnection(url: staged, readOnly: false, create: true)
        guard let backup = sqlite3_backup_init(target.handle, "main", handle, "main") else {
            throw Self.error(target.handle, sqlite3_errcode(target.handle))
        }
        var code = SQLITE_OK
        var retries = 0
        do {
            repeat {
                try cancellation.check()
                code = sqlite3_backup_step(backup, 128)
                switch code & 0xff {
                case SQLITE_OK:
                    retries = 0
                case SQLITE_DONE:
                    break
                case SQLITE_BUSY where retries < 15, SQLITE_LOCKED where retries < 15:
                    retries += 1
                    Thread.sleep(forTimeInterval: 0.1)
                default:
                    throw Self.error(target.handle, code)
                }
            } while code != SQLITE_DONE
        } catch {
            sqlite3_backup_finish(backup)
            throw error
        }
        code = sqlite3_backup_finish(backup)
        guard code == SQLITE_OK else { throw Self.error(target.handle, code) }
        try cancellation.check()
    }

    private static func readSQL(_ url: URL, cancellation: SASQLiteCancellation, statement: (String) throws -> Void) throws {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var buffer: [UInt8] = []
        var firstChunk = true

        func decoded() throws -> String {
            guard let sql = String(bytes: buffer, encoding: .utf8) else { throw SASQLiteError.invalidInput }
            return sql
        }

        while let data = try file.read(upToCount: 64 * 1024), !data.isEmpty {
            try cancellation.check()
            let bytes = firstChunk && data.starts(with: [0xef, 0xbb, 0xbf]) ? data.dropFirst(3) : data[...]
            firstChunk = false
            for byte in bytes {
                guard byte != 0 else { throw SASQLiteError.invalidInput }
                buffer.append(byte)
                if byte == 59 {
                    let sql = try decoded()
                    if sqlite3_complete(sql) == 1 {
                        try cancellation.check()
                        try statement(sql)
                        buffer.removeAll(keepingCapacity: true)
                    }
                }
            }
        }
        if !buffer.isEmpty { try statement(decoded()) }
    }

    private static func withoutLeadingSQLComments(_ sql: String) -> String {
        var sql = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        while true {
            if sql.hasPrefix("--") {
                guard let newline = sql.firstIndex(where: \.isNewline) else { return "" }
                sql = String(sql[newline...]).trimmingCharacters(in: .whitespacesAndNewlines)
            } else if sql.hasPrefix("/*"), let end = sql.range(of: "*/", range: sql.index(sql.startIndex, offsetBy: 2)..<sql.endIndex) {
                sql = String(sql[end.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                return sql
            }
        }
    }

    private static func isSQLWrapper(_ sql: String, _ pattern: String) -> Bool {
        sql.range(of: #"^\s*"# + pattern + #"\s*;?\s*$"#, options: [.regularExpression, .caseInsensitive]) != nil
    }
}

private extension SASQLiteValue {
    var sqlLiteral: String {
        switch self {
        case .null:
            return "NULL"
        case let .integer(value):
            return String(value)
        case let .real(value):
            if value.isInfinite { return value < 0 ? "-9e999" : "9e999" }
            return String(value)
        case let .text(bytes):
            if !bytes.contains(0), let text = String(data: bytes, encoding: .utf8) {
                return "'" + text.replacingOccurrences(of: "'", with: "''") + "'"
            }
            return "CAST(X'\(Self.hex(bytes))' AS TEXT)"
        case let .blob(bytes):
            return "X'\(Self.hex(bytes))'"
        }
    }
}
