//
//  SAConnectionWorkIntegrationTests.swift
//  SPMySQLFramework
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//
//  More info at <https://github.com/Sequel-Ace/Sequel-Ace>
//

import XCTest
@testable import SPMySQL

/// Stands in for the application: shows the wait for connection work by running the main thread's
/// run loop until the work is done - which is what lets the connection hand a main-thread query to
/// its worker - and records what it was asked. A test can give it something to do while it waits,
/// once: an event that comes in during the wait, or the user pressing Stop.
private final class SAWaitingDelegate: NSObject {
    private(set) var timesAskedToWait = 0
    /// What the delegate does during the first wait, once the wait has begun; given the block
    /// that says whether the work being waited for has finished.
    var onceWhileWaiting: ((_ isFinished: @escaping () -> Bool) -> Void)?
    /// The thread each statement was sent on, in the order they were sent.
    private(set) var statementThreads: [Thread] = []
    private let lock = NSLock()

    @objc func willQueryString(_ query: String, connection: Any) {
        lock.lock()
        statementThreads.append(Thread.current)
        lock.unlock()
    }

    @objc(connection:waitForConnectionWorkUntilFinished:)
    func connection(_ connection: Any, waitForConnectionWorkUntilFinished isFinished: @escaping () -> Bool) {
        timesAskedToWait += 1
        if let onceWhileWaiting {
            self.onceWhileWaiting = nil
            onceWhileWaiting(isFinished)
        }
        while !isFinished() {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
        }
    }

    @objc func connectionLost(_ connection: Any) -> SPMySQLConnectionLostDecision {
        SPMySQLConnectionLostDisconnect
    }
}

/// A connection that records which thread its connection check ran on.
private final class SACheckWatchingConnection: SPMySQLConnection {
    private(set) var checkThread: Thread?

    override func check() -> Bool {
        checkThread = Thread.current
        return super.check()
    }
}

/// Connection work asked for on the main thread, against the local server: where it runs, who
/// waits for it, what a stop makes of it, and work that comes in during the wait.
final class SAConnectionWorkIntegrationTests: XCTestCase {

    /// Connects with a delegate that shows the wait, or skips when no local server is configured.
    private func connected<T: SPMySQLConnection>(_ connection: T, delegate: SAWaitingDelegate) throws -> T {
        try configureForTheLocalServer(connection)
        connection.perform(NSSelectorFromString("setDelegate:"), with: delegate)
        if !connection.connect() {
            throw XCTSkip("Local MySQL connection is unavailable: \(connection.lastErrorMessage() ?? "no error")")
        }
        return connection
    }

    /// Whether a statement with this text is running on the server, as a second connection sees it.
    /// A process list that cannot be read is a failed observation, not an absent statement.
    private func serverRunsAStatementContaining(_ text: String, seenFrom observer: SPMySQLConnection) throws -> Bool {
        let processes = try XCTUnwrap(observer.queryString("SHOW FULL PROCESSLIST"),
                                      "the process list could not be read: \(observer.lastErrorMessage() ?? "no error")")
        for case let row as [Any] in processes.getAllRows() {
            for case let column as String in row where column.contains(text) {
                return true
            }
        }
        return false
    }

    /// A statement asked for on the main thread runs on the worker, and answers as before: quick
    /// work is simply waited for, and the delegate is never told about it.
    func testAStatementAskedForOnTheMainThreadRunsOnTheWorkerAndAnswers() throws {
        let delegate = SAWaitingDelegate()
        let connection = try connected(SPMySQLConnection(), delegate: delegate)
        defer { connection.disconnect() }
        XCTAssertTrue(Thread.isMainThread, "the test stands for the interface")

        XCTAssertEqual(connection.getFirstField(fromQuery: "SELECT 'answered'") as? String, "answered")

        XCTAssertEqual(delegate.timesAskedToWait, 0, "quick work is never handed to the interface")
        let sentOn = try XCTUnwrap(delegate.statementThreads.last, "the statement was sent")
        XCTAssertFalse(sentOn.isMainThread, "on the connection's own thread")
    }

    /// A statement that takes its time is waited for by the delegate, and still answers.
    func testASlowStatementIsWaitedForByTheDelegateAndStillAnswers() throws {
        let delegate = SAWaitingDelegate()
        let connection = try connected(SPMySQLConnection(), delegate: delegate)
        defer { connection.disconnect() }

        XCTAssertEqual(connection.getFirstField(fromQuery: "SELECT SLEEP(0.5) + 6") as? String, "6")

        XCTAssertEqual(delegate.timesAskedToWait, 1, "the interface waited for it")
    }

    /// A connection check asked for on the main thread runs on the worker too.
    func testACheckAskedForOnTheMainThreadRunsOnTheWorker() throws {
        let delegate = SAWaitingDelegate()
        let connection = try connected(SACheckWatchingConnection(), delegate: delegate)
        defer { connection.disconnect() }
        connection.setValue(0, forKey: "lastConnectionUsedTime")

        XCTAssertTrue(connection.checkIfNecessary())

        let checkedOn = try XCTUnwrap(connection.checkThread, "the check ran")
        XCTAssertFalse(checkedOn.isMainThread)
    }

    /// Stopping the wait tells the caller at once that its statement was cancelled, and stops the
    /// statement on the server; the connection is usable again afterwards.
    func testStoppingTheWaitCancelsTheStatementAndTellsTheCallerAtOnce() throws {
        let delegate = SAWaitingDelegate()
        let connection = try connected(SPMySQLConnection(), delegate: delegate)
        defer { connection.disconnect() }
        let observer = try connected(SPMySQLConnection(), delegate: SAWaitingDelegate())
        defer { observer.disconnect() }

        delegate.onceWhileWaiting = { _ in
            // The user presses Stop Waiting as soon as the sheet is up.
            connection.cancelCheck()
        }

        let started = Date()
        let result = connection.queryString("SELECT SLEEP(8), 'stopped'")
        let elapsed = Date().timeIntervalSince(started)

        XCTAssertNil(result)
        XCTAssertLessThan(elapsed, 3, "the caller was told at once, not after the statement")
        XCTAssertTrue(connection.lastQueryWasCancelled)
        XCTAssertTrue(connection.queryErrored())
        XCTAssertEqual(connection.lastErrorID(), 1317)

        // The statement itself is stopped on the server, by the request that went out behind the caller.
        let giveUp = Date(timeIntervalSinceNow: 5)
        while try serverRunsAStatementContaining("'stopped'", seenFrom: observer) && Date() < giveUp {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
        }
        XCTAssertFalse(try serverRunsAStatementContaining("'stopped'", seenFrom: observer), "the SLEEP was killed")

        // And the connection answers the next statement, on this session or a replacement.
        XCTAssertEqual(connection.getFirstField(fromQuery: "SELECT 'again'") as? String, "again")
    }

    /// Stopping the wait for work that was queued behind another thread's statement stops that
    /// work alone: the other thread's statement runs to its end and answers, unkilled, and the
    /// operations the stop was not about keep their turn.
    func testStoppingTheWaitLeavesAnotherThreadsStatementAlone() throws {
        let delegate = SAWaitingDelegate()
        let connection = try connected(SPMySQLConnection(), delegate: delegate)
        defer { connection.disconnect() }

        // A statement of another thread's holds the session - a table load, say.
        let otherStarted = DispatchSemaphore(value: 0)
        let otherAnswered = expectation(description: "the other thread's statement answered")
        var otherAnswer: String?
        var otherErrored: Bool?
        var otherWasCancelled: Bool?
        Thread.detachNewThread {
            otherStarted.signal()
            otherAnswer = connection.getFirstField(fromQuery: "SELECT SLEEP(1.5) + 0, 'other'") as? String
            otherErrored = connection.queryErrored()
            otherWasCancelled = connection.lastQueryWasCancelled
            otherAnswered.fulfill()
        }
        XCTAssertEqual(otherStarted.wait(timeout: .now() + 2), .success)
        Thread.sleep(forTimeInterval: 0.2)

        // The main thread's statement queues behind it; the user stops waiting for it at once.
        delegate.onceWhileWaiting = { _ in connection.cancelCheck() }
        let started = Date()
        let mine = connection.queryString("SELECT 'mine'")
        let elapsed = Date().timeIntervalSince(started)

        XCTAssertNil(mine, "the stopped statement answers nothing")
        XCTAssertLessThan(elapsed, 1.2, "and the caller was told at once, not after the other statement")
        XCTAssertTrue(connection.lastQueryWasCancelled)

        wait(for: [otherAnswered], timeout: 5)
        XCTAssertEqual(otherAnswer, "0", "the other thread's statement ran to its end")
        XCTAssertEqual(otherErrored, false, "unkilled")
        XCTAssertEqual(otherWasCancelled, false, "and not reported as stopped")
    }

    /// A statement that comes in during the wait leaves the waited-for statement's report alone:
    /// each statement's caller reads what that statement reported, not what the other did.
    func testWorkThatComesInDuringTheWaitLeavesTheOuterStatementsReportAlone() throws {
        let delegate = SAWaitingDelegate()
        let connection = try connected(SPMySQLConnection(), delegate: delegate)
        defer { connection.disconnect() }

        var innerFailed: Bool?
        delegate.onceWhileWaiting = { _ in
            _ = connection.queryString("SELECT * FROM no_such_table_for_the_wait")
            innerFailed = connection.queryErrored()
        }

        let outerAnswer = connection.getFirstField(fromQuery: "SELECT SLEEP(0.6) + 0, 'outer'") as? String

        XCTAssertEqual(innerFailed, true, "the statement that came in during the wait failed, and said so to its caller")
        XCTAssertEqual(outerAnswer, "0", "the waited-for statement answered")
        XCTAssertFalse(connection.queryErrored(), "and its caller reads its own report, not the failed one's")
        XCTAssertNil(connection.lastErrorMessage())
        XCTAssertFalse(connection.lastQueryWasCancelled)
    }

    /// The other way round as well: a waited-for statement that fails keeps its failure for its
    /// caller through a statement that succeeded during the wait - which is the case the content
    /// view's row deletion reads, from `queryErrored` alone.
    func testAFailedStatementKeepsItsReportThroughASuccessfulNestedOne() throws {
        let delegate = SAWaitingDelegate()
        let connection = try connected(SPMySQLConnection(), delegate: delegate)
        defer { connection.disconnect() }

        var innerAnswer: String?
        delegate.onceWhileWaiting = { _ in
            innerAnswer = connection.getFirstField(fromQuery: "SELECT 'inner'") as? String
        }

        // Slow, then failing: the sleep comes first in the select list, the subquery that returns
        // two rows after it.
        let outerResult = connection.queryString("SELECT SLEEP(0.6), (SELECT 1 UNION SELECT 2)")

        XCTAssertGreaterThanOrEqual(delegate.timesAskedToWait, 1, "the failing statement was waited for")
        XCTAssertEqual(innerAnswer, "inner", "the statement that came in during the wait answered")
        XCTAssertNil(outerResult)
        XCTAssertTrue(connection.queryErrored(), "the waited-for statement's caller reads its own failure")
        XCTAssertEqual(connection.lastErrorID(), 1242, "subquery returns more than 1 row")
    }

    /// Work that comes in during the wait - an event that queries the same connection on the main
    /// thread - runs after the work being waited for, and both answer.
    func testWorkThatComesInDuringTheWaitRunsAfterTheWorkBeingWaitedFor() throws {
        let delegate = SAWaitingDelegate()
        let connection = try connected(SPMySQLConnection(), delegate: delegate)
        defer { connection.disconnect() }

        var innerAnswer: String?
        var outerHadFinishedWhenTheInnerAnswered: Bool?
        delegate.onceWhileWaiting = { outerIsFinished in
            innerAnswer = connection.getFirstField(fromQuery: "SELECT 'inner'") as? String
            outerHadFinishedWhenTheInnerAnswered = outerIsFinished()
        }

        let outerAnswer = connection.getFirstField(fromQuery: "SELECT SLEEP(0.6) + 0, 'outer'") as? String

        XCTAssertEqual(innerAnswer, "inner", "the work that came in during the wait answered")
        XCTAssertEqual(outerHadFinishedWhenTheInnerAnswered, true, "after the work being waited for")
        XCTAssertEqual(outerAnswer, "0", "which answered too")
        XCTAssertEqual(delegate.timesAskedToWait, 2, "each wait was shown")
        // The statements the connection sent to set its session up came first, on this thread.
        let theTwo = delegate.statementThreads.suffix(2)
        XCTAssertEqual(theTwo.count, 2)
        XCTAssertTrue(theTwo.allSatisfy { !$0.isMainThread }, "both ran on the worker")
    }

    // MARK: - The local server

    /// Points a connection at the local server named by the environment, or at the usual socket.
    private func configureForTheLocalServer(_ connection: SPMySQLConnection) throws {
        let environment = ProcessInfo.processInfo.environment
        var socketPath = environment["SPMYSQL_TEST_SOCKET"]
        let testHost = environment["SPMYSQL_TEST_HOST"]
        if (socketPath?.isEmpty ?? true), (testHost?.isEmpty ?? true) {
            socketPath = ["/tmp/mysql.sock", "/opt/homebrew/var/mysql/mysql.sock"]
                .first(where: { FileManager.default.fileExists(atPath: $0) })
        }
        let testUser = environment["SPMYSQL_TEST_USER"]
        connection.username = testUser?.isEmpty == false ? testUser : "root"
        connection.password = environment["SPMYSQL_TEST_PASSWORD"]
        connection.useKeepAlive = false
        connection.timeout = 5
        if let testHost, !testHost.isEmpty {
            connection.useSocket = false
            connection.host = testHost
            if let port = environment["SPMYSQL_TEST_PORT"].flatMap(UInt.init) {
                connection.port = port
            }
        } else if let socketPath, !socketPath.isEmpty {
            connection.useSocket = true
            connection.socketPath = socketPath
        } else {
            throw XCTSkip("No local MySQL connection configured. Set SPMYSQL_TEST_SOCKET or SPMYSQL_TEST_HOST to run this regression.")
        }
    }
}
