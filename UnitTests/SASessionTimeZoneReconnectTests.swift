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
    var failCancellationConnection = false
    var failedCancellationConnections = 0
    var beforeTimeZoneUpdate: (() -> Void)?
    var beforeUserQuery: (() -> Void)?

    @objc(_makeRawMySQLConnectionWithEncoding:isMasterConnection:)
    func makeRawConnection(_ encoding: NSString, isMasterConnection: Bool) -> UnsafeMutableRawPointer? {
        if failCancellationConnection && !isMasterConnection {
            failedCancellationConnections += 1
            return nil
        }
        // The transport factory is private Objective-C API. Forward successful
        // connections to its real implementation and fail only the KILL connection.
        let selector = #selector(makeRawConnection(_:isMasterConnection:))
        guard let method = class_getInstanceMethod(SPMySQLConnection.self, selector) else {
            XCTFail("Missing connection factory")
            return nil
        }
        typealias Factory = @convention(c) (AnyObject, Selector, NSString, Bool) -> UnsafeMutableRawPointer?
        let factory = unsafeBitCast(method_getImplementation(method), to: Factory.self)
        return factory(self, selector, encoding, isMasterConnection)
    }

    override func queryString(_ query: String!) -> SPMySQLResult! {
        if query.hasPrefix("SET time_zone") {
            beforeTimeZoneUpdate?()
            if failNextTimeZoneUpdate {
                failNextTimeZoneUpdate = false
                return super.queryString("SET time_zone = 'SequelAce/InvalidTimeZone'")
            }
        }
        return super.queryString(query)
    }

    override func queryString(_ query: String!, assertingDatabase database: String!) -> SPMySQLResult! {
        if query == "SELECT @@session.time_zone" {
            beforeUserQuery?()
        }
        return super.queryString(query, assertingDatabase: database)
    }
}

final class SASessionTimeZoneIntegrationTests: XCTestCase {
    private func makeConnection() throws -> SASessionTimeZoneLiveConnection {
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
        return connection
    }

    func testLiveReconnectRetainsTimeZoneAcrossRestorationFailureAndRecovery() throws {
        let connection = try makeConnection()
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

    func testConcurrentQueryWaitsForSuccessfulTimeZoneRestoration() throws {
        try assertConcurrentQueryWaits(failRestoration: false)
    }

    func testConcurrentQueryRetriesAfterFailedTimeZoneRestoration() throws {
        try assertConcurrentQueryWaits(failRestoration: true)
    }

    func testFallbackCancellationInterruptsActiveQueryBeforeReconnecting() throws {
        try assertCancellation(failCancellationConnection: true)
    }

    func testKillQueryCancellationKeepsSessionAndTimeZone() throws {
        try assertCancellation(failCancellationConnection: false)
    }

    private func assertCancellation(failCancellationConnection: Bool) throws {
        let connection = try makeConnection()
        let observer = try makeConnection()
        defer {
            connection.disconnect()
            observer.disconnect()
        }
        connection.updateTimeZoneIdentifier("+01:00")
        XCTAssertFalse(connection.queryErrored())
        connection.failCancellationConnection = failCancellationConnection
        let session = connection.mysqlConnectionThreadId
        let queryFinished = expectation(description: "cancelled query returned")
        Thread.detachNewThread {
            _ = connection.queryString("SELECT SLEEP(10)")
            queryFinished.fulfill()
        }

        // Confirm that the real server is executing the query, rather than racing
        // a cancellation against a thread that has not submitted its query yet.
        let runningSQL = "SELECT COUNT(*) FROM information_schema.processlist WHERE ID = \(session) AND INFO = 'SELECT SLEEP(10)'"
        let deadline = Date(timeIntervalSinceNow: 3)
        var running = false
        repeat {
            running = (observer.getFirstField(fromQuery: runningSQL) as? NSString)?.integerValue == 1
            if !running {
                RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
            }
        } while !running && Date() < deadline
        XCTAssertTrue(running)

        let cancellationStarted = Date()
        connection.cancelCurrentQuery()
        XCTAssertLessThan(Date().timeIntervalSince(cancellationStarted), 3,
                          "Fallback cancellation must interrupt the query before waiting for session access")
        wait(for: [queryFinished], timeout: 3)
        if failCancellationConnection {
            XCTAssertGreaterThan(connection.failedCancellationConnections, 0)
            XCTAssertNotEqual(connection.mysqlConnectionThreadId, session)
        } else {
            XCTAssertEqual(connection.failedCancellationConnections, 0)
            XCTAssertEqual(connection.mysqlConnectionThreadId, session)
        }
        XCTAssertEqual(connection.timeZoneIdentifier, "+01:00")
        XCTAssertEqual(connection.getFirstField(fromQuery: "SELECT @@session.time_zone") as? String, "+01:00")
    }

    func testFallbackCancellationDrainsStreamingQueryWithoutRecursing() throws {
        let connection = try makeConnection()
        defer { connection.disconnect() }
        connection.updateTimeZoneIdentifier("+01:00")
        connection.failCancellationConnection = true
        let session = connection.mysqlConnectionThreadId
        // A row larger than the server's network buffer flushes the result header
        // before SLEEP, leaving the result downloader active after queryString returns.
        let result = try XCTUnwrap(connection.streamingQueryString("SELECT REPEAT('x', 20000) UNION ALL SELECT SLEEP(10)"))
        let cancellationStarted = Date()
        connection.cancelCurrentQuery()
        XCTAssertLessThan(Date().timeIntervalSince(cancellationStarted), 3)
        result.cancelLoad()
        XCTAssertGreaterThan(connection.failedCancellationConnections, 0)
        XCTAssertLessThan(connection.failedCancellationConnections, 3, "Cancellation must not recursively reconnect")
        XCTAssertNotEqual(connection.mysqlConnectionThreadId, session)
        XCTAssertEqual(connection.getFirstField(fromQuery: "SELECT @@session.time_zone") as? String, "+01:00")
    }

    private func assertConcurrentQueryWaits(failRestoration: Bool) throws {
        let connection = try makeConnection()
        defer { connection.disconnect() }
        connection.updateTimeZoneIdentifier("+01:00")
        XCTAssertFalse(connection.queryErrored())

        let restoring = expectation(description: "restoring time zone")
        let resumeRestoration = DispatchSemaphore(value: 0)
        let queryStarted = expectation(description: "user query started")
        let queryReturned = DispatchSemaphore(value: 0)
        let reconnectFinished = expectation(description: "reconnect finished")
        let queryFinished = expectation(description: "query finished")
        connection.failNextTimeZoneUpdate = failRestoration
        connection.beforeTimeZoneUpdate = {
            // Pause only the first attempt. The caller may need to retry a failed SET.
            connection.beforeTimeZoneUpdate = nil
            restoring.fulfill()
            XCTAssertEqual(resumeRestoration.wait(timeout: .now() + 5), .success)
        }
        connection.beforeUserQuery = { queryStarted.fulfill() }
        Thread.detachNewThread {
            XCTAssertEqual(connection.reconnect(), !failRestoration)
            reconnectFinished.fulfill()
        }
        wait(for: [restoring], timeout: 5)
        Thread.detachNewThread {
            XCTAssertEqual(connection.getFirstField(fromQuery: "SELECT @@session.time_zone") as? String, "+01:00")
            queryReturned.signal()
            queryFinished.fulfill()
        }
        wait(for: [queryStarted], timeout: 5)
        XCTAssertEqual(queryReturned.wait(timeout: .now() + 0.1), .timedOut,
                       "The query must not reach the new session before its time zone is restored")
        resumeRestoration.signal()
        wait(for: [reconnectFinished, queryFinished], timeout: 5)
    }
}

final class SAConnectionSessionAccessTests: XCTestCase {
    func testReconnectCanRunSetupQueriesAndNestedReconnects() {
        let access = SAConnectionSessionAccess()
        XCTAssertTrue(access.reconnect(allowingRetries: true) {
            XCTAssertEqual(access.performQuery { "setup" } as? String, "setup")
            return access.reconnect(allowingRetries: true) { true }
        })
    }

    func testCancelledQueryWaiterExitsWhileReconnectStillOwnsSession() {
        let access = SAConnectionSessionAccess()
        let owned = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let waiting = DispatchSemaphore(value: 0)
        let cancelled = expectation(description: "cancelled query returned")
        let reconnected = expectation(description: "reconnect completed")
        Thread.detachNewThread {
            _ = access.reconnect(allowingRetries: false) {
                owned.signal()
                XCTAssertEqual(release.wait(timeout: .now() + 5), .success)
                return true
            }
            reconnected.fulfill()
        }
        XCTAssertEqual(owned.wait(timeout: .now() + 5), .success)
        let waiter = Thread {
            waiting.signal()
            XCTAssertNil(access.performQuery {
                XCTFail("A cancelled caller must not execute its query")
                return "unexpected"
            })
            cancelled.fulfill()
        }
        waiter.start()
        XCTAssertEqual(waiting.wait(timeout: .now() + 5), .success)
        waiter.cancel()
        wait(for: [cancelled], timeout: 2)
        release.signal()
        wait(for: [reconnected], timeout: 2)
    }

    func testMainThreadWaitServicesReconnectMainQueueWork() {
        XCTAssertTrue(Thread.isMainThread)
        let access = SAConnectionSessionAccess()
        let owned = DispatchSemaphore(value: 0)
        let mainQueueWork = DispatchSemaphore(value: 0)
        let reconnected = expectation(description: "reconnect completed")
        Thread.detachNewThread {
            _ = access.reconnect(allowingRetries: false) {
                owned.signal()
                DispatchQueue.main.async { mainQueueWork.signal() }
                XCTAssertEqual(mainQueueWork.wait(timeout: .now() + 2), .success)
                return true
            }
            reconnected.fulfill()
        }
        XCTAssertEqual(owned.wait(timeout: .now() + 2), .success)
        XCTAssertEqual(access.performQuery { "ready" } as? String, "ready")
        wait(for: [reconnected], timeout: 2)
    }
}
