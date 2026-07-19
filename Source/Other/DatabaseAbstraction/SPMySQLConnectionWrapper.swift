//
//  SPMySQLConnectionWrapper.swift
//  Sequel Ace
//

import Foundation

@objc(SPMySQLConnectionWrapper)
final class SPMySQLConnectionWrapper: NSObject, SPDatabaseConnection {
    private let connection: SPMySQLConnection

    @objc(initWithConnection:)
    init(connection: SPMySQLConnection) {
        self.connection = connection
        super.init()
    }

    @objc var underlyingConnection: SPMySQLConnection { connection }

    @objc var host: String? {
        get { connection.host }
        set { connection.host = newValue }
    }

    @objc var database: String? {
        get { connection.database }
        set { connection.database = newValue }
    }

    @objc static var defaultPort: UInt { 3306 }

    func connect() -> Bool { connection.connect() }
    func disconnect() { connection.disconnect() }
    func isConnected() -> Bool { connection.isConnected() }
    func isConnectedViaSSL() -> Bool { connection.isConnectedViaSSL() }

    func setUsername(_ username: String) { connection.username = username }
    func setPassword(_ password: String) { connection.password = password }
    func setPort(_ port: UInt) { connection.port = port }
    func setTimeout(_ timeout: UInt) { connection.timeout = timeout }
    func setUseSSL(_ useSSL: Bool) { connection.useSSL = useSSL }

    func setDelegate(_ delegate: SPDatabaseConnectionProxy?) {
        connection.setDelegate(delegate as? SPMySQLConnectionDelegate)
    }

    func selectDatabase(_ aDatabase: String) -> Bool { connection.selectDatabase(aDatabase) }
    func databases() -> [String] { connection.databases() as? [String] ?? [] }

    func queryString(_ query: String) -> SPDatabaseResult? {
        connection.queryString(query) as? SPDatabaseResult
    }

    func streamingQueryString(_ query: String) -> Any? {
        connection.streamingQueryString(query)
    }

    func streamingQueryString(_ query: String, useLowMemoryBlockingStreaming fullStreaming: Bool) -> Any? {
        connection.streamingQueryString(query, useLowMemoryBlockingStreaming: fullStreaming)
    }

    func queryErrored() -> Bool { connection.queryErrored() }
    func lastErrorMessage() -> String? { connection.lastErrorMessage() }
    func lastErrorID() -> UInt { connection.lastErrorID() }
    func rowsAffectedByLastQuery() -> UInt64 { connection.rowsAffectedByLastQuery() }
    func lastInsertID() -> UInt64 { connection.lastInsertID() }
    func cancelCurrentQuery() { connection.cancelCurrentQuery() }

    func encoding() -> String? { connection.encoding() }
    func setEncoding(_ encoding: String) -> Bool { connection.setEncoding(encoding) }
    func storeEncodingForRestoration() { connection.storeEncodingForRestoration() }
    func restoreStoredEncoding() { connection.restoreStoredEncoding() }

    func preferredUTF8Encoding() -> String {
        if connection.serverVersionIsGreaterThanOrEqual(to: 5, minorVersion: 5, releaseVersion: 3) {
            return "utf8mb4"
        }
        return "utf8"
    }

    func serverVersionString() -> String? { connection.serverVersionString() }
    func serverMajorVersion() -> UInt { connection.serverMajorVersion() }
    func serverMinorVersion() -> UInt { connection.serverMinorVersion() }
    func serverReleaseVersion() -> UInt { connection.serverReleaseVersion() }

    func serverVersionIsGreaterThanOrEqual(to major: UInt, minorVersion minor: UInt, releaseVersion release: UInt) -> Bool {
        connection.serverVersionIsGreaterThanOrEqual(to: major, minorVersion: minor, releaseVersion: release)
    }

    func getServerVariableValue(_ variable: String) -> String? {
        let query = "SHOW VARIABLES LIKE '\(variable)'"
        guard let result = connection.queryString(query),
              let row = result.getRowAsArray() as? [Any],
              row.count >= 2 else { return nil }
        return row[1] as? String
    }

    func getCollationsForEncoding(_ encoding: String) -> [Any] { [] }

    func isPostgreSQL() -> Bool { false }
    func identifierQuoteCharacter() -> String { "`" }

    @objc func isMariaDB() -> Bool { connection.isMariaDB() }

    @objc func escapeAndQuoteString(_ theString: String) -> String? {
        connection.escapeAndQuoteString(theString)
    }

    @objc var lastQueryWasCancelled: Bool {
        connection.lastQueryWasCancelled
    }
}
