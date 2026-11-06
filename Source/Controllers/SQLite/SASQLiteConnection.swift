import Foundation
import SQLite3

enum SASQLiteValue: Equatable, Sendable {
    case null
    case integer(Int64)
    case real(Double)
    case text(Data)
    case blob(Data)

    init(_ string: String) {
        self = .text(Data(string.utf8))
    }

    var string: String? {
        guard case let .text(bytes) = self else { return nil }
        return String(decoding: bytes, as: UTF8.self)
    }

    var integer: Int64? {
        guard case let .integer(value) = self else { return nil }
        return value
    }

    var display: String {
        switch self {
        case .null: return "NULL"
        case let .integer(value): return String(value)
        case let .real(value): return String(value)
        case let .text(bytes): return String(decoding: bytes, as: UTF8.self)
        case let .blob(bytes): return "0x" + Self.hex(bytes)
        }
    }

    var preview: String {
        switch self {
        case let .blob(bytes) where bytes.count > 48: return "0x" + Self.hex(bytes.prefix(48)) + "…"
        case let .text(bytes) where bytes.count > 256: return String(decoding: bytes.prefix(256), as: UTF8.self) + "…"
        default: return display
        }
    }

    func compare(to other: SASQLiteValue) -> ComparisonResult {
        switch (self, other) {
        case let (.integer(left), .integer(right)): return NSNumber(value: left).compare(NSNumber(value: right))
        case let (.integer(left), .real(right)): return NSNumber(value: left).compare(NSNumber(value: right))
        case let (.real(left), .integer(right)): return NSNumber(value: left).compare(NSNumber(value: right))
        case let (.real(left), .real(right)): return NSNumber(value: left).compare(NSNumber(value: right))
        case let (.text(left), .text(right)), let (.blob(left), .blob(right)):
            if left == right { return .orderedSame }
            return left.lexicographicallyPrecedes(right) ? .orderedAscending : .orderedDescending
        default:
            if sortRank == other.sortRank { return .orderedSame }
            return sortRank < other.sortRank ? .orderedAscending : .orderedDescending
        }
    }

    private var sortRank: Int {
        switch self {
        case .null: return 0
        case .integer, .real: return 1
        case .text: return 2
        case .blob: return 3
        }
    }

    static func hex(_ bytes: Data) -> String {
        let digits = Array("0123456789ABCDEF".utf8)
        return String(decoding: bytes.flatMap { [digits[Int($0 >> 4)], digits[Int($0 & 15)]] }, as: UTF8.self)
    }
}

enum SASQLiteError: LocalizedError {
    case engine(Int32, String)
    case invalidFile
    case readOnly
    case invalidInput
    case noActiveRow
    case rowChanged
    case openTransaction
    case cancelled
    case unsafeImport
    case invalidCSV(Int)
    case foreignKeyViolation
    case virtualTableDump
    case existingDestination

    var errorDescription: String? {
        switch self {
        case let .engine(_, message): return message
        case .invalidFile: return NSLocalizedString("Choose a regular SQLite database file.", comment: "SQLite file error")
        case .readOnly: return NSLocalizedString("The SQLite database could only be opened for reading.", comment: "SQLite file error")
        case .invalidInput: return NSLocalizedString("Enter a valid SQLite name or value.", comment: "SQLite input error")
        case .noActiveRow: return NSLocalizedString("This row cannot be uniquely identified for editing.", comment: "SQLite row edit error")
        case .rowChanged: return NSLocalizedString("The row changed since it was loaded. Refresh the table and try again.", comment: "SQLite row edit conflict")
        case .openTransaction: return NSLocalizedString("Commit or roll back the open SQL transaction first.", comment: "SQLite transaction error")
        case .cancelled: return NSLocalizedString("SQLite operation cancelled.", comment: "SQLite cancellation")
        case .unsafeImport: return NSLocalizedString("This SQL file contains a command that cannot be imported in a single transaction.", comment: "SQLite SQL import error")
        case let .invalidCSV(row):
            return String.localizedStringWithFormat(NSLocalizedString("Invalid CSV record %lld.", comment: "SQLite CSV error with record number"), Int64(row))
        case .foreignKeyViolation: return NSLocalizedString("The import would leave foreign key violations.", comment: "SQLite SQL import error")
        case .virtualTableDump: return NSLocalizedString("Use a SQLite backup to export a database containing virtual tables.", comment: "SQLite SQL export limitation")
        case .existingDestination: return NSLocalizedString("Choose a new file so that an existing database is not overwritten.", comment: "SQLite backup destination error")
        }
    }
}

final class SASQLiteCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool { lock.withLock { cancelled } }

    func cancel() {
        lock.withLock { cancelled = true }
    }

    func check() throws {
        if isCancelled { throw SASQLiteError.cancelled }
    }
}

struct SASQLiteResult: Sendable {
    let columns: [String]
    let rows: [[SASQLiteValue]]
    let changedRows: Int64
    let truncated: Bool
    var columnTypes: [String?] = []
}

struct SASQLiteScriptResult: Sendable {
    let sql: String
    let result: SASQLiteResult?
    let error: String?
}

/// The session confines this handle and all prepared statements to one serial queue.
final class SASQLiteConnection {
    let handle: OpaquePointer
    let readOnly: Bool
    private var ownsHandle = false

    init(url: URL, readOnly: Bool, create: Bool = false) throws {
        guard url.isFileURL, !create || !readOnly else { throw SASQLiteError.invalidFile }
        if create {
            do {
                try Data().write(to: url, options: .withoutOverwriting)
            } catch let error as CocoaError where error.code == .fileWriteFileExists {
                throw SASQLiteError.existingDestination
            }
        }
        var handle: OpaquePointer?
        do {
            guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
                throw SASQLiteError.invalidFile
            }
            let flags = readOnly ? SQLITE_OPEN_READONLY : SQLITE_OPEN_READWRITE
            let code = sqlite3_open_v2(url.path, &handle, flags | SQLITE_OPEN_PRIVATECACHE, nil)
            guard code == SQLITE_OK, let handle else {
                throw Self.error(handle, code)
            }
            guard readOnly || sqlite3_db_readonly(handle, "main") == 0 else {
                throw SASQLiteError.readOnly
            }
            self.handle = handle
            self.readOnly = readOnly

            sqlite3_extended_result_codes(handle, 1)
            sqlite3_busy_timeout(handle, 1500)
            try query("PRAGMA trusted_schema = OFF")
            try query("PRAGMA foreign_keys = ON")
            // Opening a handle alone does not detect malformed or encrypted files.
            try query("SELECT count(*) FROM main.sqlite_schema")
            if create {
                // Force SQLite to write a valid database header even if no tables are created.
                try query("PRAGMA user_version = 0")
            }
            setAuthorization(.workspace)
            ownsHandle = true
        } catch {
            if let handle { sqlite3_close_v2(handle) }
            if create { try? FileManager.default.removeItem(at: url) }
            throw error
        }
    }

    deinit {
        if ownsHandle { sqlite3_close_v2(handle) }
    }

    var inTransaction: Bool { sqlite3_get_autocommit(handle) == 0 }

    func withCancellation<T>(_ cancellation: SASQLiteCancellation, _ work: () throws -> T) throws -> T {
        try cancellation.check()
        sqlite3_progress_handler(handle, 1_000, { context in
            guard let context else { return 0 }
            return Unmanaged<SASQLiteCancellation>.fromOpaque(context).takeUnretainedValue().isCancelled ? 1 : 0
        }, Unmanaged.passUnretained(cancellation).toOpaque())
        defer { sqlite3_progress_handler(handle, 0, nil, nil) }
        return try withExtendedLifetime(cancellation, work)
    }

    @discardableResult
    func query(_ sql: String, bindings: [SASQLiteValue] = [], limit: Int? = nil) throws -> SASQLiteResult {
        guard !sql.utf8.contains(0) else { throw SASQLiteError.invalidInput }
        return try sql.withCString { input in
            guard let statement = try prepare(input) else {
                return SASQLiteResult(columns: [], rows: [], changedRows: 0, truncated: false)
            }
            defer { sqlite3_finalize(statement) }
            return try collect(statement, bindings: bindings, limit: limit)
        }
    }

    func stream(_ sql: String, row: ([SASQLiteValue]) throws -> Void) throws {
        try sql.withCString { input in
            guard let statement = try prepare(input) else { return }
            defer { sqlite3_finalize(statement) }
            while try step(statement) {
                try row(Self.values(statement))
            }
        }
    }

    /// SQLite finds the statement boundaries, including semicolons in trigger bodies.
    func runScript(_ sql: String, limit: Int = 1_000, cancellation: SASQLiteCancellation) throws -> [SASQLiteScriptResult] {
        guard !sql.utf8.contains(0) else { throw SASQLiteError.invalidInput }
        var results: [SASQLiteScriptResult] = []
        var remaining = limit
        sql.withCString { input in
            var start = input
            while start.pointee != 0 {
                var tail: UnsafePointer<CChar>?
                var statementSQL = ""
                do {
                    try cancellation.check()
                    let statement = try prepare(start, tail: &tail)
                    guard let tail, tail > start else { break }
                    statementSQL = String(decoding: UnsafeRawBufferPointer(start: start, count: tail - start), as: UTF8.self)
                    start = tail
                    guard let statement else { continue }
                    defer { sqlite3_finalize(statement) }
                    let result = try collect(statement, bindings: [], limit: remaining)
                    remaining -= result.rows.count
                    results.append(.init(sql: statementSQL, result: result, error: nil))
                } catch {
                    results.append(.init(sql: statementSQL.isEmpty ? String(cString: start) : statementSQL,
                                         result: nil, error: error.localizedDescription))
                    break
                }
            }
        }
        return results
    }

    func requireIdleWriter() throws {
        if readOnly { throw SASQLiteError.readOnly }
        if inTransaction { throw SASQLiteError.openTransaction }
    }

    func writeTransaction<T>(_ work: () throws -> T) throws -> T {
        try requireIdleWriter()
        try query("BEGIN IMMEDIATE")
        do {
            let result = try work()
            guard inTransaction else { throw SASQLiteError.unsafeImport }
            try query("COMMIT")
            return result
        } catch {
            rollbackIfNeeded()
            throw error
        }
    }

    func readSnapshot<T>(_ work: () throws -> T) throws -> T {
        if inTransaction { return try work() }
        try query("BEGIN")
        do {
            let result = try work()
            try query("COMMIT")
            return result
        } catch {
            rollbackIfNeeded()
            throw error
        }
    }

    private func rollbackIfNeeded() {
        guard inTransaction else { return }
        // A cancelled operation must still release its transaction and locks.
        sqlite3_progress_handler(handle, 0, nil, nil)
        _ = try? query("ROLLBACK")
    }

    enum Authorization {
        case workspace
        case importStatement
    }

    func setAuthorization(_ authorization: Authorization) {
        let context = authorization == .importStatement ? UnsafeMutableRawPointer(bitPattern: 1) : nil
        sqlite3_set_authorizer(handle, { context, action, first, second, _, _ in
            let argument = first.map(String.init(cString:))?.lowercased()
            let value = second.map(String.init(cString:))?.lowercased()
            switch action {
            case SQLITE_ATTACH, SQLITE_DETACH:
                return SQLITE_DENY
            case SQLITE_FUNCTION where value == "load_extension":
                return SQLITE_DENY
            case SQLITE_TRANSACTION, SQLITE_SAVEPOINT:
                if context != nil { return SQLITE_DENY }
            case SQLITE_PRAGMA where second != nil:
                if context != nil || ["writable_schema", "trusted_schema", "temp_store_directory", "data_store_directory"].contains(argument) {
                    return SQLITE_DENY
                }
            default:
                break
            }
            return SQLITE_OK
        }, context)
    }

    static func identifier(_ name: String) -> String {
        "\"" + name.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    static func validatedIdentifier(_ name: String) throws -> String {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !name.utf8.contains(0) else { throw SASQLiteError.invalidInput }
        return identifier(name)
    }

    static func error(_ db: OpaquePointer?, _ code: Int32) -> SASQLiteError {
        if code & 0xff == SQLITE_INTERRUPT { return .cancelled }
        let message = db.flatMap { sqlite3_errmsg($0) } ?? sqlite3_errstr(code)
        return .engine(code, message.map(String.init(cString:)) ?? "SQLite \(code)")
    }

    private func prepare(_ input: UnsafePointer<CChar>, tail: UnsafeMutablePointer<UnsafePointer<CChar>?>? = nil) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        let code = sqlite3_prepare_v2(handle, input, -1, &statement, tail)
        guard code == SQLITE_OK else { throw Self.error(handle, code) }
        return statement
    }

    private func collect(_ statement: OpaquePointer, bindings: [SASQLiteValue], limit: Int?) throws -> SASQLiteResult {
        guard sqlite3_bind_parameter_count(statement) == bindings.count else { throw SASQLiteError.invalidInput }
        for (index, value) in bindings.enumerated() {
            try bind(value, to: statement, at: Int32(index + 1))
        }

        var rows: [[SASQLiteValue]] = []
        var truncated = false
        let before = sqlite3_total_changes64(handle)
        while try step(statement) {
            if let limit, rows.count >= limit {
                truncated = true
                // Finish statements with RETURNING so their writes complete.
                if sqlite3_stmt_readonly(statement) != 0 { break }
            } else {
                rows.append(Self.values(statement))
            }
        }
        let indexes = 0..<sqlite3_column_count(statement)
        let columns = indexes.map { String(cString: sqlite3_column_name(statement, $0)) }
        let types = indexes.map { sqlite3_column_decltype(statement, $0).map(String.init(cString:)) }
        return SASQLiteResult(columns: columns, rows: rows, changedRows: sqlite3_total_changes64(handle) - before,
                              truncated: truncated, columnTypes: types)
    }

    private func step(_ statement: OpaquePointer) throws -> Bool {
        let code = sqlite3_step(statement)
        if code == SQLITE_ROW { return true }
        if code == SQLITE_DONE { return false }
        throw Self.error(handle, code)
    }

    private func bind(_ value: SASQLiteValue, to statement: OpaquePointer, at index: Int32) throws {
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        let code: Int32
        switch value {
        case .null: code = sqlite3_bind_null(statement, index)
        case let .integer(value): code = sqlite3_bind_int64(statement, index, value)
        case let .real(value): code = sqlite3_bind_double(statement, index, value)
        case let .text(bytes):
            if bytes.isEmpty {
                code = sqlite3_bind_text(statement, index, "", 0, transient)
            } else {
                code = bytes.withUnsafeBytes {
                    sqlite3_bind_text64(statement, index, $0.baseAddress?.assumingMemoryBound(to: CChar.self),
                                        UInt64(bytes.count), transient, UInt8(SQLITE_UTF8))
                }
            }
        case let .blob(bytes):
            if bytes.isEmpty {
                code = sqlite3_bind_zeroblob(statement, index, 0)
            } else {
                code = bytes.withUnsafeBytes {
                    sqlite3_bind_blob64(statement, index, $0.baseAddress, UInt64(bytes.count), transient)
                }
            }
        }
        guard code == SQLITE_OK else { throw Self.error(handle, code) }
    }

    private static func values(_ statement: OpaquePointer) -> [SASQLiteValue] {
        (0..<sqlite3_column_count(statement)).map { index in
            switch sqlite3_column_type(statement, index) {
            case SQLITE_INTEGER: return .integer(sqlite3_column_int64(statement, index))
            case SQLITE_FLOAT: return .real(sqlite3_column_double(statement, index))
            case SQLITE_TEXT:
                let bytes = sqlite3_column_text(statement, index)
                return .text(bytes.map { Data(bytes: $0, count: Int(sqlite3_column_bytes(statement, index))) } ?? Data())
            case SQLITE_BLOB:
                let bytes = sqlite3_column_blob(statement, index)
                return .blob(bytes.map { Data(bytes: $0, count: Int(sqlite3_column_bytes(statement, index))) } ?? Data())
            default: return .null
            }
        }
    }
}
