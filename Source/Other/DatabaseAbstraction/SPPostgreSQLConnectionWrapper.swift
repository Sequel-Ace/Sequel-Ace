//
//  SPPostgreSQLConnectionWrapper.swift
//  Sequel Ace
//

import Foundation

@objc(SPPostgreSQLConnectionWrapper)
final class SPPostgreSQLConnectionWrapper: NSObject, SPDatabaseConnection {
    private var conn: OpaquePointer?
    @objc var host: String?
    private var username: String?
    private var password: String?
    @objc var database: String?
    private var port: UInt = 5432
    private var useSSL = false

    private var storedLastErrorMessage: String?
    private var storedLastErrorID: UInt = 0
    private var lastQueryErrored = false
    private var rowsAffected: UInt64 = 0
    private var storedLastInsertID: UInt64 = 0

    @objc override init() {
        super.init()
        conn = sp_postgresql_connection_create()
    }

    deinit {
        if let conn {
            sp_postgresql_connection_destroy(conn)
            self.conn = nil
        }
    }

    @objc static var defaultPort: UInt { 5432 }

    func setUsername(_ username: String) { self.username = username }
    func setPassword(_ password: String) { self.password = password }
    func setPort(_ port: UInt) { self.port = port }
    func setTimeout(_ timeout: UInt) { /* stored by Rust connection on connect if needed */ }
    func setUseSSL(_ useSSL: Bool) { self.useSSL = useSSL }
    func setDelegate(_ delegate: SPDatabaseConnectionProxy?) { }

    func connect() -> Bool {
        if conn == nil { conn = sp_postgresql_connection_create() }
        guard let conn else { return false }

        let hostC = host ?? "localhost"
        let userC = username ?? "postgres"
        let passC = password ?? ""
        let dbC = database ?? "postgres"

        let result = hostC.withCString { hostPtr in
            userC.withCString { userPtr in
                passC.withCString { passPtr in
                    dbC.withCString { dbPtr in
                        sp_postgresql_connection_connect(
                            conn, hostPtr, Int32(port), userPtr, passPtr, dbPtr, useSSL ? 1 : 0
                        )
                    }
                }
            }
        }

        if result == 0 {
            captureLastError()
            return false
        }
        storedLastErrorMessage = nil
        storedLastErrorID = 0
        return true
    }

    func disconnect() {
        if let conn { sp_postgresql_connection_disconnect(conn) }
    }

    func isConnected() -> Bool {
        guard let conn else { return false }
        return sp_postgresql_connection_is_connected(conn) != 0
    }

    func isConnectedViaSSL() -> Bool { useSSL && isConnected() }

    func selectDatabase(_ aDatabase: String) -> Bool {
        if aDatabase == database { return true }
        database = aDatabase
        disconnect()
        return connect()
    }

    func databases() -> [String] {
        guard let conn else { return [] }
        var count: Int32 = 0
        guard let dbs = sp_postgresql_connection_list_databases(conn, &count), count > 0 else {
            return []
        }
        defer { sp_postgresql_free_string_array(dbs, count) }

        var names = [String]()
        for i in 0..<count {
            if let ptr = dbs[Int(i)] {
                names.append(String(cString: ptr))
            }
        }
        return names
    }

    func queryString(_ query: String) -> SPDatabaseResult? {
        guard let conn, isConnected() else {
            storedLastErrorMessage = "Not connected to PostgreSQL server"
            storedLastErrorID = 1
            lastQueryErrored = true
            return nil
        }

        let start = Date.timeIntervalSinceReferenceDate
        let result: OpaquePointer? = query.withCString { queryPtr in
            sp_postgresql_connection_execute_query(conn, queryPtr)
        }
        let elapsed = Date.timeIntervalSinceReferenceDate - start

        guard let result else {
            captureLastError()
            lastQueryErrored = true
            return nil
        }

        lastQueryErrored = false
        storedLastErrorMessage = nil
        storedLastErrorID = 0
        rowsAffected = sp_postgresql_result_affected_rows(result)
        storedLastInsertID = 0

        return SPPostgreSQLResultWrapper(result: result, queryTime: elapsed)
    }

    func streamingQueryString(_ query: String) -> Any? {
        streamingQueryString(query, useLowMemoryBlockingStreaming: true)
    }

    func streamingQueryString(_ query: String, useLowMemoryBlockingStreaming fullStreaming: Bool) -> Any? {
        guard let conn, isConnected() else {
            storedLastErrorMessage = "Not connected to PostgreSQL server"
            storedLastErrorID = 1
            lastQueryErrored = true
            return nil
        }

        let start = Date.timeIntervalSinceReferenceDate
        let batchSize = fullStreaming ? 100 : 1000
        let result: OpaquePointer? = query.withCString { queryPtr in
            sp_postgresql_connection_execute_streaming_query(conn, queryPtr, Int32(batchSize))
        }
        let elapsed = Date.timeIntervalSinceReferenceDate - start

        guard let result else {
            captureLastError()
            lastQueryErrored = true
            return nil
        }

        lastQueryErrored = false
        storedLastErrorMessage = nil
        storedLastErrorID = 0

        return SPPostgreSQLStreamingResultWrapper(streamingResult: result, queryTime: elapsed)
    }

    func queryErrored() -> Bool { lastQueryErrored }
    func lastErrorMessage() -> String? { storedLastErrorMessage }
    func lastErrorID() -> UInt { storedLastErrorID }
    func rowsAffectedByLastQuery() -> UInt64 { rowsAffected }
    func lastInsertID() -> UInt64 { storedLastInsertID }
    func cancelCurrentQuery() { }

    func encoding() -> String? { "utf8" }
    func setEncoding(_ encoding: String) -> Bool { true }
    func storeEncodingForRestoration() { }
    func restoreStoredEncoding() { }
    func preferredUTF8Encoding() -> String { "UTF8" }

    func serverVersionString() -> String? {
        guard let result = queryString("SELECT version()"),
              let row = result.getRowAsArray(),
              let version = row.first as? String else {
            return "PostgreSQL (unknown version)"
        }
        return version
    }

    private func versionComponent(at index: Int) -> UInt {
        guard let ver = serverVersionString() else { return 0 }
        let pattern = "(\\d+)\\.(\\d+)(?:\\.(\\d+))?"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: ver, range: NSRange(ver.startIndex..., in: ver)),
              index + 1 < match.numberOfRanges else { return 0 }
        let range = match.range(at: index + 1)
        guard range.location != NSNotFound, let swiftRange = Range(range, in: ver) else { return 0 }
        return UInt(ver[swiftRange]) ?? 0
    }

    func serverMajorVersion() -> UInt { versionComponent(at: 0) }
    func serverMinorVersion() -> UInt { versionComponent(at: 1) }
    func serverReleaseVersion() -> UInt { versionComponent(at: 2) }

    func serverVersionIsGreaterThanOrEqual(to major: UInt, minorVersion minor: UInt, releaseVersion release: UInt) -> Bool {
        let maj = serverMajorVersion()
        let min = serverMinorVersion()
        let rel = serverReleaseVersion()
        if maj != major { return maj > major }
        if min != minor { return min > minor }
        return rel >= release
    }

    func getServerVariableValue(_ variable: String) -> String? {
        guard let result = queryString("SHOW \(variable)"),
              let row = result.getRowAsArray(),
              let value = row.first as? String else { return nil }
        return value
    }

    func getCollationsForEncoding(_ encoding: String) -> [Any] { [] }

    func isPostgreSQL() -> Bool { true }
    func identifierQuoteCharacter() -> String { "\"" }

    @objc func escapeAndQuoteString(_ theString: String) -> String? {
        let escaped = theString
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "''")
        return "'\(escaped)'"
    }

    @objc var lastQueryWasCancelled: Bool { false }

    private func captureLastError() {
        guard let conn else { return }
        if let errPtr = sp_postgresql_connection_last_error(conn) {
            storedLastErrorMessage = String(cString: errPtr)
            sp_postgresql_free_string(errPtr)
        } else {
            storedLastErrorMessage = "Unknown PostgreSQL error"
        }
        storedLastErrorID = 2
    }
}
