//
//  SASessionTimeZoneReconnectTests.swift
//  Unit Tests
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import XCTest
import SPMySQL

/// Replaces only the transport. The public reconnect entry point, session-state
/// restoration, time-zone setter and error accessors are the framework's real code.
private final class SASessionTimeZoneTestConnection: SPMySQLConnection {
    var statements: [String] = []
    var serverTimeZone = "SYSTEM"
    var failNextTimeZoneUpdate = false
    var dropNextTimeZoneUpdate = false
    var restoredDatabase: String?
    var restoredEncoding: String?
    var restoredLatin1Transport = false

    @objc(_connect) func establishSession() -> Bool {
        setValue(SPMySQLConnected.rawValue, forKey: "state")
        setValue(nil, forKey: "queryErrorMessage")
        setValue(0, forKey: "queryErrorID")
        serverTimeZone = "SYSTEM"
        _ = super.setEncoding("utf8")
        return true
    }

    @objc(_disconnectPreservingProxyReconnect:) func closeSession(_ preserveProxy: Bool) {
        setValue(SPMySQLDisconnected.rawValue, forKey: "state")
    }

    @objc(_waitForNetworkConnectionWithTimeout:) func waitForNetwork(_ timeout: Double) -> Bool {
        true
    }

    override func queryString(_ query: String!) -> SPMySQLResult! {
        guard query.hasPrefix("SET time_zone") else { return SPMySQLEmptyResult() }
        statements.append(query)
        if failNextTimeZoneUpdate {
            failNextTimeZoneUpdate = false
            setValue("Time zone restoration failed", forKey: "queryErrorMessage")
            setValue(1298, forKey: "queryErrorID")
            return nil
        }
        if dropNextTimeZoneUpdate {
            dropNextTimeZoneUpdate = false
            return nil
        }
        setValue(nil, forKey: "queryErrorMessage")
        setValue(0, forKey: "queryErrorID")
        serverTimeZone = query == "SET time_zone = @@GLOBAL.time_zone" ? "SYSTEM" : "Europe/London"
        return SPMySQLEmptyResult()
    }

    override func selectDatabase(_ database: String!) -> Bool {
        restoredDatabase = database
        return true
    }

    override func setEncoding(_ encoding: String!) -> Bool {
        restoredEncoding = encoding
        return super.setEncoding(encoding)
    }

    override func setEncodingUsesLatin1Transport(_ useLatin1: Bool) -> Bool {
        restoredLatin1Transport = useLatin1
        return super.setEncodingUsesLatin1Transport(useLatin1)
    }
}

final class SASessionTimeZoneReconnectTests: XCTestCase {
    private func connection(timeZone: String? = "Europe/London") -> SASessionTimeZoneTestConnection {
        let connection = SASessionTimeZoneTestConnection()
        connection.useKeepAlive = false
        XCTAssertTrue(connection.connect())
        connection.setValue("reporting", forKey: "database")
        connection.setValue("utf8mb4", forKey: "encoding")
        connection.setValue(true, forKey: "encodingUsesLatin1Transport")
        connection.setValue(timeZone, forKey: "timeZoneIdentifier")
        return connection
    }

    func testReconnectReappliesMatchingTimeZoneAlongsideDatabaseAndEncoding() {
        let connection = connection()
        defer { connection.disconnect() }

        for _ in 0..<3 {
            XCTAssertTrue(connection.reconnect())
            XCTAssertEqual(connection.serverTimeZone, "Europe/London")
            XCTAssertEqual(connection.timeZoneIdentifier, "Europe/London")
        }
        XCTAssertEqual(connection.statements, Array(repeating: "SET time_zone = 'Europe/London'", count: 3))
        XCTAssertEqual(connection.restoredDatabase, "reporting")
        XCTAssertEqual(connection.restoredEncoding, "utf8mb4")
        XCTAssertTrue(connection.restoredLatin1Transport)
    }

    func testFailedRestoreDoesNotReportSuccessOrForgetTimeZone() {
        let connection = connection()
        defer { connection.disconnect() }
        connection.failNextTimeZoneUpdate = true

        XCTAssertFalse(connection.reconnect())
        XCTAssertEqual(connection.timeZoneIdentifier, "Europe/London")
        XCTAssertEqual(connection.value(forKey: "state") as? UInt, UInt(SPMySQLConnectionLostInBackground.rawValue))
        XCTAssertEqual(connection.lastErrorID(), 1298)

        // The next use takes the real lazy-reconnect path and retries the same preference.
        XCTAssertTrue(connection.isConnected())
        XCTAssertEqual(connection.serverTimeZone, "Europe/London")
        XCTAssertEqual(connection.statements.count, 2)
        XCTAssertEqual(connection.restoredDatabase, "reporting")
        XCTAssertEqual(connection.restoredEncoding, "utf8mb4")
        XCTAssertTrue(connection.restoredLatin1Transport)
    }

    func testMissingQueryResultDoesNotCountAsSuccessfulRestoration() {
        let connection = connection()
        defer { connection.disconnect() }
        connection.dropNextTimeZoneUpdate = true

        XCTAssertFalse(connection.reconnect())
        XCTAssertEqual(connection.timeZoneIdentifier, "Europe/London")
        XCTAssertTrue(connection.isConnected())
        XCTAssertEqual(connection.serverTimeZone, "Europe/London")
    }

    func testRepeatedFailuresKeepPreferenceUntilRestorationSucceeds() {
        let connection = connection()
        defer { connection.disconnect() }
        for _ in 0..<3 {
            connection.failNextTimeZoneUpdate = true
            XCTAssertFalse(connection.reconnect())
            XCTAssertEqual(connection.timeZoneIdentifier, "Europe/London")
        }
        XCTAssertTrue(connection.reconnect())
        XCTAssertEqual(connection.serverTimeZone, "Europe/London")
        XCTAssertEqual(connection.statements.count, 4)
    }

    func testServerDefaultDoesNotSendTimeZoneOverride() {
        for timeZone in [nil, ""] as [String?] {
            let connection = connection(timeZone: timeZone)
            defer { connection.disconnect() }
            XCTAssertTrue(connection.reconnect())
            XCTAssertTrue(connection.statements.isEmpty)
            XCTAssertEqual(connection.serverTimeZone, "SYSTEM")
        }
    }

    func testSwitchingBackToServerDefaultStopsRestoringFixedTimeZone() {
        let connection = connection()
        defer { connection.disconnect() }
        XCTAssertTrue(connection.reconnect())
        connection.updateTimeZoneIdentifier(nil)
        connection.statements.removeAll()

        XCTAssertTrue(connection.reconnect())
        XCTAssertTrue(connection.statements.isEmpty)
        XCTAssertEqual(connection.serverTimeZone, "SYSTEM")
    }

    func testRestorationQuotesIdentifierWithoutChangingRememberedPreference() {
        let connection = connection(timeZone: "a'b")
        defer { connection.disconnect() }
        XCTAssertTrue(connection.reconnect())
        XCTAssertEqual(connection.statements, ["SET time_zone = 'a''b'"])
        XCTAssertEqual(connection.timeZoneIdentifier, "a'b")
    }
}

/// Injects one real server error while leaving connection/reconnection and all
/// other queries untouched. Only this test's session is changed.
private final class SASessionTimeZoneLiveConnection: SPMySQLConnection {
    var failNextTimeZoneUpdate = false

    override func queryString(_ query: String!) -> SPMySQLResult! {
        if failNextTimeZoneUpdate && query.hasPrefix("SET time_zone") {
            failNextTimeZoneUpdate = false
            return super.queryString("SET time_zone = 'SequelAce/InvalidTimeZone'")
        }
        return super.queryString(query)
    }
}

final class SASessionTimeZoneIntegrationTests: XCTestCase {
    func testLiveReconnectRetainsTimeZoneAcrossRestorationFailureAndRecovery() throws {
        let environment = ProcessInfo.processInfo.environment
        let connection = SASessionTimeZoneLiveConnection()
        connection.username = environment["SPMYSQL_TEST_USER"] ?? "root"
        connection.password = environment["SPMYSQL_TEST_PASSWORD"]
        connection.useKeepAlive = false
        connection.timeout = 2
        if let host = environment["SPMYSQL_TEST_HOST"], !host.isEmpty {
            connection.useSocket = false
            connection.host = host
            connection.port = environment["SPMYSQL_TEST_PORT"].flatMap(UInt.init) ?? 3306
        } else {
            let socket = environment["SPMYSQL_TEST_SOCKET"] ?? "/tmp/mysql.sock"
            guard FileManager.default.fileExists(atPath: socket) else {
                throw XCTSkip("Requires a local MySQL server or SPMYSQL_TEST_HOST/SPMYSQL_TEST_SOCKET.")
            }
            connection.useSocket = true
            connection.socketPath = socket
        }
        guard connection.connect() else {
            throw XCTSkip("MySQL test connection unavailable: \(connection.lastErrorMessage() ?? "unknown error")")
        }
        defer { connection.disconnect() }

        // An offset works even on servers without the optional named-zone tables.
        connection.updateTimeZoneIdentifier("+01:00")
        XCTAssertFalse(connection.queryErrored())
        let originalSession = connection.mysqlConnectionThreadId
        XCTAssertTrue(connection.reconnect())
        XCTAssertNotEqual(connection.mysqlConnectionThreadId, originalSession)
        XCTAssertEqual(connection.getFirstField(fromQuery: "SELECT @@session.time_zone") as? String, "+01:00")

        connection.failNextTimeZoneUpdate = true
        XCTAssertFalse(connection.reconnect())
        XCTAssertEqual(connection.lastErrorID(), 1298)
        XCTAssertEqual(connection.timeZoneIdentifier, "+01:00")

        // queryString must reconnect before executing the caller's statement.
        XCTAssertEqual(connection.getFirstField(fromQuery: "SELECT @@session.time_zone") as? String, "+01:00")
        XCTAssertFalse(connection.queryErrored())
        XCTAssertEqual(connection.timeZoneIdentifier, "+01:00")
    }
}
