//
//  SASessionTimeZoneReconnectTests.swift
//  Unit Tests
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import XCTest
import SPMySQL
import Darwin

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

/// Models a successful completion that became stale before its caller resumed.
private final class SAStaleReconnectResultConnection: SPMySQLConnection {
    var disconnectBeforeReturning = false

    @objc(_performReconnectAllowingRetries:)
    func completedReconnect(_ allowRetries: Bool) -> Bool {
        if disconnectBeforeReturning {
            setValue(true, forKey: "userTriggeredDisconnect")
        }
        return true
    }
}

final class SASessionTimeZoneReconnectTests: XCTestCase {

    /// Asks whether the connection is connected away from the main thread.
    ///
    /// A session lost in the background is restored on the first use that can afford to wait for
    /// the network. Asking on the main thread is not one of those, so the restore the lazy path
    /// performs is reached from another thread.
    private func isConnectedAwayFromTheMainThread(_ connection: SPMySQLConnection) -> Bool {
        var answer = false
        let finished = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            answer = connection.isConnected()
            finished.signal()
        }
        XCTAssertEqual(finished.wait(timeout: .now() + 10), .success,
                       "the restore must not outlast the test")
        return answer
    }
    func testReconnectRevalidatesSuccessfulCompletionAgainstLiveState() {
        let connection = SAStaleReconnectResultConnection()
        connection.useKeepAlive = false
        defer {
            connection.setValue(SPMySQLDisconnected.rawValue, forKey: "state")
            connection.disconnect()
        }
        connection.setValue(SPMySQLConnected.rawValue, forKey: "state")
        XCTAssertTrue(connection.reconnect())

        connection.setValue(SPMySQLDisconnected.rawValue, forKey: "state")
        XCTAssertFalse(connection.reconnect(), "An earlier success cannot make a disconnected session usable")

        connection.setValue(SPMySQLConnected.rawValue, forKey: "state")
        connection.disconnectBeforeReturning = true
        XCTAssertFalse(connection.reconnect(), "Explicit disconnect must invalidate an earlier success")
    }

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

        // The next use that can wait takes the real lazy-reconnect path and retries the same
        // preference.
        XCTAssertTrue(isConnectedAwayFromTheMainThread(connection))
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
        XCTAssertTrue(isConnectedAwayFromTheMainThread(connection))
        XCTAssertEqual(connection.serverTimeZone, "Europe/London")
    }

    /// Asking on the main thread does not hold the interface for the restore, and does not lose it.
    func testAskingOnTheMainThreadLeavesTheRestoreToTheNextUseThatCanWait() {
        let connection = connection()
        defer { connection.disconnect() }
        connection.failNextTimeZoneUpdate = true
        XCTAssertFalse(connection.reconnect())
        let statementsAfterTheFailedRestore = connection.statements.count

        XCTAssertTrue(Thread.isMainThread)
        XCTAssertTrue(connection.isConnected(), "the connection still counts as connected")
        XCTAssertEqual(connection.statements.count, statementsAfterTheFailedRestore,
                       "but nothing was sent, so the interface did not wait for the network")
        XCTAssertEqual(connection.value(forKey: "state") as? UInt,
                       UInt(SPMySQLConnectionLostInBackground.rawValue),
                       "and the session is still the one to be restored")

        XCTAssertTrue(isConnectedAwayFromTheMainThread(connection))
        XCTAssertEqual(connection.serverTimeZone, "Europe/London")
        XCTAssertEqual(connection.statements.count, statementsAfterTheFailedRestore + 1)
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
    var cancelAfterNextConnectionCheck = false
    var cancelDuringNextTimeZoneUpdate = false
    var beforeCancellationConnection: (() -> Void)?
    var beforeTimeZoneUpdate: (() -> Void)?
    var beforeUserQuery: (() -> Void)?

    override func check() -> Bool {
        let connected = super.check()
        if connected && cancelAfterNextConnectionCheck {
            cancelAfterNextConnectionCheck = false
            // Model a cancellation recorded while the auxiliary KILL connection
            // targets the old session, just before the original query retries.
            (value(forKey: "sessionAccess") as? SAConnectionSessionAccess)?.recordQueryCancellation()
        }
        return connected
    }

    @objc(_makeRawMySQLConnectionWithEncoding:isMasterConnection:)
    func makeRawConnection(_ encoding: NSString, isMasterConnection: Bool) -> UnsafeMutableRawPointer? {
        if !isMasterConnection { beforeCancellationConnection?() }
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
            if cancelDuringNextTimeZoneUpdate {
                cancelDuringNextTimeZoneUpdate = false
                (value(forKey: "sessionAccess") as? SAConnectionSessionAccess)?.cancelQuery { _ in
                    XCTFail("No native statement has been submitted yet")
                    return true
                }
            }
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

    func testExternalKillPreservesThePublicCancellationFlag() throws {
        try assertCancellation(failCancellationConnection: false, externalKill: true)
    }

    private func assertCancellation(failCancellationConnection: Bool, externalKill: Bool = false) throws {
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
        if externalKill {
            // SPDatabaseDocument's structure fast path uses this public setter
            // and sends KILL through its separate cancellation connection.
            connection.lastQueryWasCancelled = true
            _ = observer.queryString("KILL QUERY \(session)")
            XCTAssertFalse(observer.queryErrored())
        } else {
            connection.cancelCurrentQuery()
        }
        XCTAssertLessThan(Date().timeIntervalSince(cancellationStarted), 3,
                          "Fallback cancellation must interrupt the query before waiting for session access")
        wait(for: [queryFinished], timeout: 3)
        XCTAssertTrue(connection.lastQueryWasCancelled)
        XCTAssertEqual(connection.getFirstField(fromQuery: "SELECT @@session.time_zone") as? String, "+01:00")
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
        XCTAssertEqual(connection.getFirstField(fromQuery: "SELECT @@session.time_zone") as? String, "+01:00")
        XCTAssertNotEqual(connection.mysqlConnectionThreadId, session)
    }

    func testFallbackCancellationLeavesLowMemoryResultAliveUntilItDrains() throws {
        let connection = try makeConnection()
        defer { connection.disconnect() }
        connection.updateTimeZoneIdentifier("+01:00")
        connection.failCancellationConnection = true
        let session = connection.mysqlConnectionThreadId
        let result = try XCTUnwrap(connection.streamingQueryString(
            "SELECT REPEAT('x', 20000) UNION ALL SELECT SLEEP(10)",
            useLowMemoryBlockingStreaming: true) as? SPMySQLStreamingResult)
        let started = Date()
        connection.cancelCurrentQuery()
        XCTAssertLessThan(Date().timeIntervalSince(started), 1)
        XCTAssertEqual(connection.failedCancellationConnections, 1)
        XCTAssertEqual(connection.mysqlConnectionThreadId, session,
                       "Cancellation must leave MYSQL alive while the exporter still owns its result")
        result.cancelLoad()
        XCTAssertLessThan(Date().timeIntervalSince(started), 3)
        XCTAssertEqual(connection.getFirstField(fromQuery: "SELECT @@session.time_zone") as? String, "+01:00")
        XCTAssertNotEqual(connection.mysqlConnectionThreadId, session)
        XCTAssertEqual(connection.failedCancellationConnections, 1)
    }

    func testDelayedKillCannotReachTheNextQuery() throws {
        let connection = try makeConnection()
        let observer = try makeConnection()
        defer { connection.disconnect(); observer.disconnect() }
        let session = connection.mysqlConnectionThreadId
        let firstDone = expectation(description: "first query finished")
        let killStarted = expectation(description: "KILL connection paused")
        let cancelDone = expectation(description: "cancellation returned")
        let nextDone = expectation(description: "next query returned")
        let releaseKill = DispatchSemaphore(value: 0)
        let nextReturned = DispatchSemaphore(value: 0)
        connection.beforeCancellationConnection = {
            killStarted.fulfill()
            XCTAssertEqual(releaseKill.wait(timeout: .now() + 5), .success)
        }
        Thread.detachNewThread {
            _ = connection.queryString("SELECT SLEEP(1)")
            firstDone.fulfill()
        }
        let deadline = Date(timeIntervalSinceNow: 3)
        var running = false
        repeat {
            running = (observer.getFirstField(fromQuery:
                "SELECT COUNT(*) FROM information_schema.processlist WHERE ID = \(session) AND INFO = 'SELECT SLEEP(1)'") as? NSString)?.integerValue == 1
            if !running { RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01)) }
        } while !running && Date() < deadline
        XCTAssertTrue(running)
        Thread.detachNewThread {
            connection.cancelCurrentQuery()
            cancelDone.fulfill()
        }
        wait(for: [killStarted, firstDone], timeout: 3)
        Thread.detachNewThread {
            XCTAssertEqual(connection.getFirstField(fromQuery: "SELECT SLEEP(0.2)") as? String, "0")
            XCTAssertFalse(connection.queryErrored())
            nextReturned.signal()
            nextDone.fulfill()
        }
        XCTAssertEqual(nextReturned.wait(timeout: .now() + 0.1), .timedOut,
                       "A later query must wait until the old cancellation finishes")
        releaseKill.signal()
        wait(for: [cancelDone, nextDone], timeout: 3)
        XCTAssertEqual(connection.mysqlConnectionThreadId, session)
    }

    func testCancellationDuringDeferredRecoveryDoesNotSubmitThePendingStatement() throws {
        let connection = try makeConnection()
        defer { connection.disconnect() }
        connection.updateTimeZoneIdentifier("+01:00")
        connection.failCancellationConnection = true
        let result = try XCTUnwrap(connection.streamingQueryString(
            "SELECT REPEAT('x', 20000) UNION ALL SELECT SLEEP(10)",
            useLowMemoryBlockingStreaming: true) as? SPMySQLStreamingResult)
        connection.cancelCurrentQuery()
        result.cancelLoad()
        connection.cancelDuringNextTimeZoneUpdate = true

        XCTAssertNil(connection.queryString("SELECT @deferred_marker := 'submitted'"))
        XCTAssertFalse(connection.cancelDuringNextTimeZoneUpdate)
        XCTAssertTrue(connection.lastQueryWasCancelled)
        XCTAssertEqual(connection.lastErrorID(), 1317)
        XCTAssertEqual(connection.getFirstField(fromQuery: "SELECT @deferred_marker IS NULL") as? String, "1")
        XCTAssertEqual(connection.getFirstField(fromQuery: "SELECT @@session.time_zone") as? String, "+01:00")
    }

    func testCancellationDuringReconnectPreventsResubmittingTheOriginalQuery() throws {
        let connection = try makeConnection()
        let observer = try makeConnection()
        defer {
            connection.disconnect()
            observer.disconnect()
        }
        connection.updateTimeZoneIdentifier("+01:00")
        let session = connection.mysqlConnectionThreadId
        _ = observer.queryString("KILL CONNECTION \(session)")
        XCTAssertFalse(observer.queryErrored())
        connection.cancelAfterNextConnectionCheck = true

        XCTAssertNil(connection.queryString("SELECT @retry_marker := 'retried'"))
        XCTAssertFalse(connection.cancelAfterNextConnectionCheck)
        XCTAssertNotEqual(connection.mysqlConnectionThreadId, session)
        XCTAssertEqual(connection.lastErrorID(), 1317)
        XCTAssertTrue(connection.lastQueryWasCancelled)
        XCTAssertEqual(connection.getFirstField(fromQuery: "SELECT @retry_marker IS NULL") as? String, "1")
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
    func testCancellationPublishesSocketAndServerThreadTogether() throws {
        let access = SAConnectionSessionAccess()
        var sockets = [Int32](repeating: -1, count: 2)
        XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &sockets), 0)
        defer { sockets.forEach { Darwin.close($0) } }
        try access.trackSocket(sockets[0], serverThreadID: 101)
        access.clearSocket()
        let published = expectation(description: "replacement socket published")
        let queryDone = expectation(description: "replacement query done")
        let begin = DispatchSemaphore(value: 0)
        let running = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        Thread.detachNewThread {
            _ = access.performQuery {
                do { try access.trackSocket(sockets[0], serverThreadID: 202) }
                catch { XCTFail("Failed to publish replacement socket: \(error)") }
                published.fulfill()
                XCTAssertEqual(begin.wait(timeout: .now() + 5), .success)
                access.beginNativeQuery()
                running.signal()
                XCTAssertEqual(release.wait(timeout: .now() + 5), .success)
                access.endNativeQuery()
                return nil
            }
            queryDone.fulfill()
        }
        wait(for: [published], timeout: 2)
        access.cancelQuery { _ in XCTFail("Connection setup alone is not an active query"); return true }
        begin.signal()
        XCTAssertEqual(running.wait(timeout: .now() + 2), .success)
        var cancelledThread: UInt = 0
        access.cancelQuery { cancelledThread = $0; return true }
        XCTAssertEqual(cancelledThread, 202, "A new socket must never use the retired server thread ID")
        release.signal()
        wait(for: [queryDone], timeout: 2)
    }

    func testDelayedCancellationBlocksNextQueryAndReconnect() throws {
        let access = SAConnectionSessionAccess()
        var sockets = [Int32](repeating: -1, count: 2)
        XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &sockets), 0)
        defer { sockets.forEach { Darwin.close($0) } }
        try access.trackSocket(sockets[0], serverThreadID: 42)
        access.beginNativeQuery()
        let killing = expectation(description: "KILL in flight")
        let killed = expectation(description: "KILL completed")
        let nextDone = expectation(description: "next query returned")
        let reconnectDone = expectation(description: "reconnect returned")
        let release = DispatchSemaphore(value: 0)
        let nextStarted = DispatchSemaphore(value: 0)
        let reconnectStarted = DispatchSemaphore(value: 0)
        Thread.detachNewThread {
            access.cancelQuery {
                XCTAssertEqual($0, 42)
                killing.fulfill()
                XCTAssertEqual(release.wait(timeout: .now() + 5), .success)
                XCTAssertFalse(access.cancellationIsCurrent, "The first query has already ended")
                return true
            }
            killed.fulfill()
        }
        wait(for: [killing], timeout: 2)
        access.endNativeQuery()
        Thread.detachNewThread {
            _ = access.performQuery { nextStarted.signal(); return nil }
            nextDone.fulfill()
        }
        Thread.detachNewThread {
            _ = access.reconnect(allowingRetries: true) { reconnectStarted.signal(); return true }
            reconnectDone.fulfill()
        }
        XCTAssertEqual(nextStarted.wait(timeout: .now() + 0.1), .timedOut)
        XCTAssertEqual(reconnectStarted.wait(timeout: .now() + 0.1), .timedOut)
        release.signal()
        wait(for: [killed, nextDone, reconnectDone], timeout: 2)
    }

    func testFailedKillDefersRecoveryUntilTheStreamingResultReleasesItsLock() throws {
        let access = SAConnectionSessionAccess()
        var sockets = [Int32](repeating: -1, count: 2)
        XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &sockets), 0)
        defer { sockets.forEach { Darwin.close($0) } }
        try access.trackSocket(sockets[0], serverThreadID: 42)
        access.beginNativeQuery()
        access.cancelQuery { _ in false }
        // Closing the socket and noting that the read was cut off are the caller's under the
        // division settled on #2676: it holds the grace period, and it knows whether the server
        // accepted the kill for a session with a transaction open. SAConnectionCancellation does
        // both against the in-flight query's own duplicate; these two lines stand for it.
        XCTAssertEqual(Darwin.shutdown(sockets[0], SHUT_RDWR), 0)
        access.noteCancellationEndedTheNativeRead(onSocket: access.socketToken)
        var byte: UInt8 = 0
        XCTAssertEqual(recv(sockets[1], &byte, 1, MSG_DONTWAIT), 0)
        let recovered = DispatchSemaphore(value: 0)
        let done = expectation(description: "next query recovered")
        Thread.detachNewThread {
            XCTAssertEqual(access.performQuery({ "next" }, recover: { recovered.signal(); return true }) as? String, "next")
            done.fulfill()
        }
        XCTAssertEqual(recovered.wait(timeout: .now() + 0.1), .timedOut)
        access.endNativeQuery()
        wait(for: [done], timeout: 2)
        XCTAssertEqual(recovered.wait(timeout: .now() + 0.1), .success)
        XCTAssertEqual(access.performQuery { "later" } as? String, "later")
    }

    func testDeferredRecoveryKeepsTheOuterCancellationTokenAcrossSetupQueries() throws {
        let access = SAConnectionSessionAccess()
        var sockets = [Int32](repeating: -1, count: 2)
        XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &sockets), 0)
        defer { sockets.forEach { Darwin.close($0) } }
        try access.trackSocket(sockets[0], serverThreadID: 42)
        access.beginNativeQuery()
        access.cancelQuery { _ in false }
        // Closing the socket and noting that the read was cut off are the caller's under the
        // division settled on #2676: it holds the grace period, and it knows whether the server
        // accepted the kill for a session with a transaction open. SAConnectionCancellation does
        // both against the in-flight query's own duplicate; these two lines stand for it.
        XCTAssertEqual(Darwin.shutdown(sockets[0], SHUT_RDWR), 0)
        access.noteCancellationEndedTheNativeRead(onSocket: access.socketToken)
        access.endNativeQuery()
        _ = access.performQuery({
            XCTAssertTrue(access.currentQueryWasCancelled)
            XCTAssertFalse(access.beginNativeQuery(), "The pending statement must not be submitted")
            access.endNativeQuery()
            return nil
        }, recover: {
            access.cancelActiveQuery {
                access.cancelQuery { _ in XCTFail("Teardown has no native statement to KILL"); return true }
            }
            XCTAssertFalse(access.currentQueryWasCancelled, "Recovery must not cancel its own pending caller")
            _ = access.performQuery {
                access.beginNativeQuery()
                access.cancelQuery { _ in true }
                access.endNativeQuery()
                XCTAssertTrue(access.currentQueryWasCancelled)
                return nil
            }
            _ = access.performQuery {
                XCTAssertFalse(access.currentQueryWasCancelled)
                return nil
            }
            return true
        })
        XCTAssertEqual(access.performQuery { "later" } as? String, "later")
    }

    /// Telling the lease a read was cut off names the session it was cut off on, and a session
    /// that replaced it in the meantime is left alone.
    ///
    /// Closing the socket and saying so are two steps, and a reconnect can put a new session in
    /// place between them. Marking that one would send a session nothing is wrong with through a
    /// reconnect it does not need, rolling back a transaction it had just opened.
    func testRecoveryIsMarkedOnTheSessionThatWasCutOffAndNoOther() throws {
        let access = SAConnectionSessionAccess()
        var old = [Int32](repeating: -1, count: 2)
        var replacement = [Int32](repeating: -1, count: 2)
        XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &old), 0)
        XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &replacement), 0)
        defer { for socket in old + replacement where socket >= 0 { Darwin.close(socket) } }

        try access.trackSocket(old[0], serverThreadID: 41)
        let theSessionThatWasCutOff = access.socketToken

        // The reconnect gets in between the socket closing and the lease being told about it.
        try access.trackSocket(replacement[0], serverThreadID: 42)
        XCTAssertNotEqual(access.socketToken, theSessionThatWasCutOff)

        access.noteCancellationEndedTheNativeRead(onSocket: theSessionThatWasCutOff)

        // The replacement is usable as it stands: nothing was cut off on it.
        var theReplacementRecovered = false
        XCTAssertEqual(access.performQuery({ "next" },
                                           recover: { theReplacementRecovered = true; return true }) as? String,
                       "next")
        XCTAssertFalse(theReplacementRecovered,
                       "a session that replaced the one cut off has nothing to recover from")

        // And the session that was cut off would have been marked, had it still been the one.
        access.noteCancellationEndedTheNativeRead(onSocket: access.socketToken)
        var theCutOffSessionRecovered = false
        XCTAssertEqual(access.performQuery({ "later" },
                                           recover: { theCutOffSessionRecovered = true; return true }) as? String,
                       "later")
        XCTAssertTrue(theCutOffSessionRecovered, "the session that was cut off does recover")
    }

    func testFailedKillDoesNotInterruptAQueryThatFinishedDuringConnectionSetup() throws {
        let access = SAConnectionSessionAccess()
        var sockets = [Int32](repeating: -1, count: 2)
        XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &sockets), 0)
        defer { sockets.forEach { Darwin.close($0) } }
        try access.trackSocket(sockets[0], serverThreadID: 42)
        access.beginNativeQuery()
        access.cancelQuery { _ in access.endNativeQuery(); return false }
        var byte: UInt8 = 0
        XCTAssertEqual(recv(sockets[1], &byte, 1, MSG_DONTWAIT), -1)
        XCTAssertEqual(errno, EAGAIN)
        XCTAssertEqual(access.performQuery { "next" } as? String, "next")
    }

    func testBackgroundLossDisconnectRetiresTrackedSocket() throws {
        let connection = SPMySQLConnection()
        connection.useKeepAlive = false
        let access = try XCTUnwrap(connection.value(forKey: "sessionAccess") as? SAConnectionSessionAccess)
        var sockets = [Int32](repeating: -1, count: 2)
        XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &sockets), 0)
        defer { for socket in sockets where socket >= 0 { Darwin.close(socket) } }
        try access.trackSocket(sockets[0])
        let token = access.socketToken
        connection.setValue(SPMySQLConnectionLostInBackground.rawValue, forKey: "state")

        connection.disconnect()

        XCTAssertNotEqual(access.socketToken, token)
        access.cancelQuery { _ in XCTFail("Background-loss disconnect must retire the cancellation handle"); return false }
    }

    func testSetupQueriesCannotEraseTheirCallersCancellation() {
        let access = SAConnectionSessionAccess()
        _ = access.performQuery {
            XCTAssertFalse(access.currentQueryWasCancelled)
            access.recordQueryCancellation()
            XCTAssertTrue(access.currentQueryWasCancelled)
            _ = access.performQuery {
                XCTAssertFalse(access.currentQueryWasCancelled)
                return nil
            }
            XCTAssertTrue(access.currentQueryWasCancelled)
            return nil
        }
        _ = access.performQuery {
            XCTAssertFalse(access.currentQueryWasCancelled)
            return nil
        }
    }

    func testCancellationSocketSurvivesTheOriginalDescriptorClosing() throws {
        let access = SAConnectionSessionAccess()
        var sockets = [Int32](repeating: -1, count: 2)
        XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &sockets), 0)
        defer { for socket in sockets where socket >= 0 { Darwin.close(socket) } }
        try access.trackSocket(sockets[0], serverThreadID: 42)
        access.beginNativeQuery()
        Darwin.close(sockets[0])
        sockets[0] = -1
        // The handle is a duplicate, so the original going does not retire it: the cancellation
        // is still the current one and still names the session to kill. Closing the socket is
        // the caller's, against a duplicate it holds itself, so nothing is closed from here.
        var killedThread: UInt = 0
        access.cancelQuery {
            killedThread = $0
            XCTAssertTrue(access.cancellationIsCurrent)
            return false
        }
        XCTAssertEqual(killedThread, 42)
        access.endNativeQuery()
        access.clearSocket()
        access.cancelQuery { _ in XCTFail("A cleared socket cannot be cancelled"); return false }
    }

    func testRetiredCancellationCannotInterruptAReplacementSocket() throws {
        let access = SAConnectionSessionAccess()
        var old = [Int32](repeating: -1, count: 2)
        var replacement = [Int32](repeating: -1, count: 2)
        XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &old), 0)
        XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &replacement), 0)
        defer { for socket in old + replacement where socket >= 0 { Darwin.close(socket) } }
        try access.trackSocket(old[0], serverThreadID: 41)
        access.beginNativeQuery()
        access.cancelQuery { thread in
            XCTAssertEqual(thread, 41)
            access.endNativeQuery()
            access.clearSocket()
            try? access.trackSocket(replacement[0], serverThreadID: 42)
            XCTAssertFalse(access.cancellationIsCurrent)
            return false
        }
        var byte: UInt8 = 0
        XCTAssertEqual(recv(replacement[1], &byte, 1, MSG_DONTWAIT), -1)
        XCTAssertEqual(errno, EAGAIN)
        access.beginNativeQuery()
        access.cancelQuery { thread in XCTAssertEqual(thread, 42); return false }
        // Closing the socket and noting that the read was cut off are the caller's under the
        // division settled on #2676: it holds the grace period, and it knows whether the server
        // accepted the kill for a session with a transaction open. SAConnectionCancellation does
        // both against the in-flight query's own duplicate; these two lines stand for it.
        XCTAssertEqual(Darwin.shutdown(replacement[0], SHUT_RDWR), 0)
        access.noteCancellationEndedTheNativeRead(onSocket: access.socketToken)
        access.endNativeQuery()
        XCTAssertEqual(recv(replacement[1], &byte, 1, MSG_DONTWAIT), 0)
    }

    func testFailedSocketReservationKeepsThePublishedCancellationIdentity() throws {
        let access = SAConnectionSessionAccess()
        var sockets = [Int32](repeating: -1, count: 2)
        XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &sockets), 0)
        defer { sockets.forEach { Darwin.close($0) } }
        try access.trackSocket(sockets[0], serverThreadID: 42)
        let token = access.socketToken
        XCTAssertThrowsError(try access.trackSocket(-1, serverThreadID: 99))
        XCTAssertEqual(access.socketToken, token)
        access.beginNativeQuery()
        access.cancelQuery { thread in XCTAssertEqual(thread, 42); return true }
        access.endNativeQuery()
        XCTAssertEqual(access.performQuery { "next" } as? String, "next")
    }

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
