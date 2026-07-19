//
//  SPDatabaseConnection.swift
//  Sequel Ace
//
//  Database-agnostic connection protocol (MySQL and PostgreSQL).
//

import Foundation

@objc(SPDatabaseConnectionProxy)
protocol SPDatabaseConnectionProxy: NSObjectProtocol {
    @objc optional func connectionLost(_ connection: Any)
    @objc optional func connectionLostDecision(for connection: Any) -> Int
}

@objc(SPDatabaseResult)
protocol SPDatabaseResult: NSObjectProtocol {
    func numberOfFields() -> UInt
    func numberOfRows() -> UInt64
    func fieldNames() -> [String]
    func seekToRow(_ targetRow: UInt64)
    func getRow() -> Any?
    func getRowAsArray() -> [Any]?
    func getRowAsDictionary() -> [AnyHashable: Any]?
    func queryExecutionTime() -> Double

    @objc optional func setDefaultRowReturnType(_ type: Int)
    @objc optional func setReturnDataAsStrings(_ asStrings: Bool)
}

@objc(SPDatabaseConnection)
protocol SPDatabaseConnection: NSObjectProtocol {
    @objc var host: String? { get set }
    @objc var database: String? { get set }

    // Connectivity
    func connect() -> Bool
    func disconnect()
    func isConnected() -> Bool
    func isConnectedViaSSL() -> Bool

    // Configuration
    func setUsername(_ username: String)
    func setPassword(_ password: String)
    func setPort(_ port: UInt)
    func setTimeout(_ timeout: UInt)
    func setUseSSL(_ useSSL: Bool)
    func setDelegate(_ delegate: SPDatabaseConnectionProxy?)

    // Database selection
    func selectDatabase(_ aDatabase: String) -> Bool
    func databases() -> [String]

    // Querying
    func queryString(_ query: String) -> SPDatabaseResult?
    func streamingQueryString(_ query: String) -> Any?
    func streamingQueryString(_ query: String, useLowMemoryBlockingStreaming fullStreaming: Bool) -> Any?

    func queryErrored() -> Bool
    func lastErrorMessage() -> String?
    func lastErrorID() -> UInt
    func rowsAffectedByLastQuery() -> UInt64
    func lastInsertID() -> UInt64
    func cancelCurrentQuery()

    // Encoding
    func encoding() -> String?
    func setEncoding(_ encoding: String) -> Bool
    func storeEncodingForRestoration()
    func restoreStoredEncoding()
    func preferredUTF8Encoding() -> String

    // Server info
    func serverVersionString() -> String?
    func serverMajorVersion() -> UInt
    func serverMinorVersion() -> UInt
    func serverReleaseVersion() -> UInt
    @objc(serverVersionIsGreaterThanOrEqualTo:minorVersion:releaseVersion:)
    func serverVersionIsGreaterThanOrEqual(to major: UInt, minorVersion minor: UInt, releaseVersion release: UInt) -> Bool
    func getServerVariableValue(_ variable: String) -> String?

    // Collation helpers
    func getCollationsForEncoding(_ encoding: String) -> [Any]

    // Backend type
    func isPostgreSQL() -> Bool
    func identifierQuoteCharacter() -> String

    // MySQL-only helpers (optional for PostgreSQL)
    @objc optional func isMariaDB() -> Bool
    @objc optional func escapeAndQuoteString(_ theString: String) -> String?
    @objc optional var lastQueryWasCancelled: Bool { get }
}
