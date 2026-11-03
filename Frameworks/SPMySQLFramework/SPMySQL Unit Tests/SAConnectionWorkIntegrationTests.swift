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

/// A connection whose report capture on one named thread can be held still - between the
/// statement writing its report on the connection and taking it for its caller - while the main
/// thread's caller returns and reads. Only that thread is held: the main caller's statement runs
/// on the connection's worker, which is not the main thread either, and passes through.
private final class SAReportCaptureHoldingConnection: SPMySQLConnection {
    let backgroundStatementWroteItsReport = DispatchSemaphore(value: 0)
    let letTheBackgroundStatementCapture = DispatchSemaphore(value: 0)
    /// The thread whose next report capture is held.
    var heldThread: Thread?
    /// How the hold ended: let go by the main caller, or timed out.
    var holdEnded: DispatchTimeoutResult?

    @objc(_reportOfLastStatement) func reportOfLastStatementHeld() -> SAStatementReport {
        if let heldThread, Thread.current === heldThread {
            self.heldThread = nil
            backgroundStatementWroteItsReport.signal()
            holdEnded = letTheBackgroundStatementCapture.wait(timeout: .now() + 5)
        }
        // The connection's own report, by way of the runtime: the method is private.
        let selector = NSSelectorFromString("_reportOfLastStatement")
        let implementation = class_getMethodImplementation(SPMySQLConnection.self, selector)!
        typealias Report = @convention(c) (AnyObject, Selector) -> Unmanaged<SAStatementReport>
        return unsafeBitCast(implementation, to: Report.self)(self, selector).takeUnretainedValue()
    }
}

/// A connection on which the user's stop lands the moment a statement has been carried out - after
/// the server answered, before the connection has settled the statement's report.
private final class SAStoppedOnceCarriedOutConnection: SPMySQLConnection {
    /// Whether the next statement carried out has its thread given up on there and then.
    var stopsOnceTheNextStatementIsCarriedOut = false

    @objc(_noteStatementCarriedOut:) func noteStatementCarriedOutAndStop(_ statement: String) {
        // The connection's own note first; its method is private, so it is reached by way of the
        // runtime rather than `super`.
        let selector = NSSelectorFromString("_noteStatementCarriedOut:")
        if let implementation = class_getMethodImplementation(SPMySQLConnection.self, selector) {
            typealias Note = @convention(c) (AnyObject, Selector, NSString) -> Void
            unsafeBitCast(implementation, to: Note.self)(self, selector, statement as NSString)
        }
        if stopsOnceTheNextStatementIsCarriedOut {
            stopsOnceTheNextStatementIsCarriedOut = false
            // The user stops waiting: the thread the statement runs on is given up on.
            Thread.current.cancel()
        }
    }
}

/// A connection that takes a statement's report only once a streaming download that has ended
/// already has let the session go - the shortest download there is, settled before the report.
private final class SAFastStreamSettlingConnection: SPMySQLConnection {
    @objc(_reportOfLastStatement) func reportOfLastStatementOnceSettled() -> SAStatementReport {
        // A download that ends lets the attached report go; a short one does so before this.
        let deadline = Date().addingTimeInterval(2)
        while value(forKey: "currentStatementReport") != nil, Date() < deadline {
            usleep(1_000)
        }
        let selector = NSSelectorFromString("_reportOfLastStatement")
        let implementation = class_getMethodImplementation(SPMySQLConnection.self, selector)!
        typealias Report = @convention(c) (AnyObject, Selector) -> Unmanaged<SAStatementReport>
        return unsafeBitCast(implementation, to: Report.self)(self, selector).takeUnretainedValue()
    }
}

/// A connection that records which thread its connection check ran on.
private final class SACheckWatchingConnection: SPMySQLConnection {
    private(set) var checkThread: Thread?

    @objc(_checkConnectionNow) func checkNowAndRecordTheThread() -> Bool {
        checkThread = Thread.current
        let selector = NSSelectorFromString("_checkConnectionNow")
        let implementation = class_getMethodImplementation(SPMySQLConnection.self, selector)!
        typealias Check = @convention(c) (AnyObject, Selector) -> Bool
        return unsafeBitCast(implementation, to: Check.self)(self, selector)
    }
}

/// A connection whose check fails, with an error written on the connection the way a check writes it.
private final class SAFailingCheckConnection: SPMySQLConnection {
    @objc(_checkConnectionNow) func checkNowAndFail() -> Bool {
        perform(NSSelectorFromString("_updateLastErrorMessage:"), with: "The check failed")
        return false
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
        for row in processes.getAllRows() {
            let columns: [Any] = (row as? [Any]) ?? ((row as? [String: Any]).map { Array($0.values) } ?? [])
            for case let column as String in columns where column.contains(text) {
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
        // The session is set up through the coordinator too; a setup statement that outlasts the quiet
        // wait on a loaded machine asks the delegate to wait before the test's own statement runs.
        let waitsDuringConnect = delegate.timesAskedToWait
        XCTAssertTrue(Thread.isMainThread, "the test stands for the interface")
        // Quick is measured against the coordinator's quiet wait, given room here: on a loaded
        // machine starting the worker thread alone can take longer than the default.
        connection.setValue(5, forKeyPath: "connectionWorkCoordinator.quietWait")

        XCTAssertEqual(connection.getFirstField(fromQuery: "SELECT 'answered'") as? String, "answered")

        XCTAssertEqual(delegate.timesAskedToWait - waitsDuringConnect, 0, "quick work is never handed to the interface")
        let sentOn = try XCTUnwrap(delegate.statementThreads.last, "the statement was sent")
        XCTAssertFalse(sentOn.isMainThread, "on the connection's own thread")
    }

    /// A statement that takes its time is waited for by the delegate, and still answers.
    func testASlowStatementIsWaitedForByTheDelegateAndStillAnswers() throws {
        let delegate = SAWaitingDelegate()
        let connection = try connected(SPMySQLConnection(), delegate: delegate)
        defer { connection.disconnect() }
        // The session is set up through the coordinator too; a setup statement that outlasts the quiet
        // wait on a loaded machine asks the delegate to wait before the test's own statement runs.
        let waitsDuringConnect = delegate.timesAskedToWait

        XCTAssertEqual(connection.getFirstField(fromQuery: "SELECT SLEEP(0.5) + 6") as? String, "6")

        XCTAssertEqual(delegate.timesAskedToWait - waitsDuringConnect, 1, "the interface waited for it")
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

    /// Work that comes in during the wait - an event that queries the same connection from the
    /// thread that is waiting - is refused rather than queued: queued behind a statement whose
    /// result keeps the session until its caller reads it, it would wait for a caller that is
    /// waiting for it. The caller is told so, and the work being waited for still answers.
    func testWorkThatComesInDuringTheWaitIsRefusedAndTheWaitedForWorkStillAnswers() throws {
        let delegate = SAWaitingDelegate()
        let connection = try connected(SPMySQLConnection(), delegate: delegate)
        defer { connection.disconnect() }
        // The session is set up through the coordinator too; a setup statement that outlasts the quiet
        // wait on a loaded machine asks the delegate to wait before the test's own statement runs.
        let waitsDuringConnect = delegate.timesAskedToWait

        var innerAnswer: Any?
        var innerErrorID: UInt?
        var innerError: String?
        var innerWasCancelled: Bool?
        var innerStatementsSent = 0
        delegate.onceWhileWaiting = { _ in
            let before = delegate.statementThreads.count
            innerAnswer = connection.queryString("SELECT 'inner'")
            innerErrorID = connection.lastErrorID()
            innerError = connection.lastErrorMessage()
            innerWasCancelled = connection.lastQueryWasCancelled
            innerStatementsSent = delegate.statementThreads.count - before
        }

        let outerAnswer = connection.getFirstField(fromQuery: "SELECT SLEEP(0.6) + 0, 'outer'") as? String

        XCTAssertNil(innerAnswer, "the work that came in during the wait was refused")
        XCTAssertEqual(innerErrorID, 2013)
        XCTAssertEqual(innerError?.contains("still waiting for an earlier statement"), true, "and told why")
        XCTAssertEqual(innerWasCancelled, false, "a refusal is not a stop")
        XCTAssertEqual(innerStatementsSent, 0, "nothing of it was sent")
        XCTAssertEqual(outerAnswer, "0", "the work being waited for answered")
        XCTAssertFalse(connection.queryErrored(), "and its caller reads its own report, not the refusal")
        XCTAssertEqual(delegate.timesAskedToWait - waitsDuringConnect, 1)
    }

    /// Each caller reads its own statement's report, however the statements of two threads
    /// overlap: a background statement that has written its report on the connection and not yet
    /// taken it for its caller is not written over by the main thread's caller returning from a
    /// statement of its own - a failed write would otherwise read as a success, or a success as
    /// a failure. The background statement is held between the two steps while the main caller
    /// returns and reads.
    func testEachCallerReadsItsOwnReportHoweverTwoThreadsStatementsOverlap() throws {
        let delegate = SAWaitingDelegate()
        let connection = try connected(SAReportCaptureHoldingConnection(), delegate: delegate)
        defer { connection.disconnect() }

        /// Runs the main thread's statement over a background statement held between writing and
        /// taking its report, and reports what each caller read.
        func readings(mainStatement: String, backgroundStatement: String) -> (mainErrored: Bool, mainErrorID: UInt, backgroundErrored: Bool?, backgroundErrorID: UInt?) {
            connection.holdEnded = nil
            let backgroundReturned = expectation(description: "the background statement's caller read its report")
            var backgroundErrored: Bool?
            var backgroundErrorID: UInt?
            // The background statement starts once the main statement's work is done and the
            // session free, and is held before it takes its report: its own thread is the one held.
            delegate.onceWhileWaiting = { mainWorkIsFinished in
                Thread.detachNewThread {
                    while !mainWorkIsFinished() {
                        usleep(1_000)
                    }
                    connection.heldThread = Thread.current
                    _ = connection.queryString(backgroundStatement)
                    backgroundErrored = connection.queryErrored()
                    backgroundErrorID = connection.lastErrorID()
                    backgroundReturned.fulfill()
                }
                // The main caller returns only once the background statement stands held.
                XCTAssertEqual(connection.backgroundStatementWroteItsReport.wait(timeout: .now() + 5), .success,
                               "the background statement wrote its report and is held")
            }

            _ = connection.queryString(mainStatement)
            let mainErrored = connection.queryErrored()
            let mainErrorID = connection.lastErrorID()

            connection.letTheBackgroundStatementCapture.signal()
            wait(for: [backgroundReturned], timeout: 5)
            XCTAssertEqual(connection.holdEnded, .success, "the background statement was held until the main caller had read")
            return (mainErrored, mainErrorID, backgroundErrored, backgroundErrorID)
        }

        let mainSucceeds = readings(mainStatement: "SELECT SLEEP(0.4), 'main'", backgroundStatement: "SELECT * FROM no_such_table_for_the_overlap")
        XCTAssertFalse(mainSucceeds.mainErrored, "the main caller reads its success")
        XCTAssertEqual(mainSucceeds.backgroundErrored, true, "the background caller reads its failure")
        XCTAssertNotEqual(mainSucceeds.backgroundErrorID ?? 0, 0, "the background statement's own failure: no such table, or no database selected")

        let mainFails = readings(mainStatement: "SELECT SLEEP(0.4), (SELECT 1 UNION SELECT 2)", backgroundStatement: "SELECT 'background'")
        XCTAssertTrue(mainFails.mainErrored, "the main caller reads its failure")
        XCTAssertEqual(mainFails.mainErrorID, 1242, "subquery returns more than 1 row")
        XCTAssertEqual(mainFails.backgroundErrored, false, "the background caller reads its success")
    }

    /// A stop that lands once the statement has been carried out - the server answered, the stop
    /// came before the connection settled the report - does not report the statement cancelled:
    /// it undid nothing, and a caller told "cancelled" would try the write again.
    func testAStopThatLandsOnceTheStatementWasCarriedOutDoesNotReportItCancelled() throws {
        let delegate = SAWaitingDelegate()
        let connection = try connected(SAStoppedOnceCarriedOutConnection(), delegate: delegate)
        defer { connection.disconnect() }
        _ = connection.queryString("CREATE TEMPORARY TABLE mysql.sa_carried_out (i INT NOT NULL)")
        XCTAssertFalse(connection.queryErrored(), connection.lastErrorMessage() ?? "")

        let returned = expectation(description: "the statement returned")
        var wasCancelled = true
        var errored = true
        var errorID: UInt = 0
        var affectedRows: UInt64 = 0
        Thread.detachNewThread {
            connection.stopsOnceTheNextStatementIsCarriedOut = true
            _ = connection.queryString("INSERT INTO mysql.sa_carried_out (i) VALUES (1)")
            wasCancelled = connection.lastQueryWasCancelled
            errored = connection.queryErrored()
            errorID = connection.lastErrorID()
            affectedRows = connection.rowsAffectedByLastQuery()
            returned.fulfill()
        }
        wait(for: [returned], timeout: 10)

        XCTAssertFalse(connection.stopsOnceTheNextStatementIsCarriedOut, "the stop landed")
        XCTAssertFalse(wasCancelled, "a statement carried out is not cancelled")
        XCTAssertFalse(errored)
        XCTAssertEqual(errorID, 0)
        XCTAssertEqual(affectedRows, 1)
        XCTAssertEqual((connection.getFirstField(fromQuery: "SELECT COUNT(*) FROM mysql.sa_carried_out") as? NSString)?.integerValue, 1,
                       "the write stands")
    }

    /// A fast streaming statement downloads on a thread of its own from the moment its result
    /// exists; the shortest download ends, and lets the session go, before the statement's report
    /// is taken. That report is the statement's own - settled, not attached to the session - and a
    /// stop of later work on the connection leaves it alone.
    func testAFastStreamSettledBeforeItsReportWasTakenIsLeftAloneByAStopOfLaterWork() throws {
        let delegate = SAWaitingDelegate()
        let connection = try connected(SAFastStreamSettlingConnection(), delegate: delegate)
        let observer = try connected(SPMySQLConnection(), delegate: SAWaitingDelegate())
        defer {
            connection.disconnect()
            observer.disconnect()
        }
        try prepareSlowRows(on: connection)

        let aReturned = DispatchSemaphore(value: 0)
        let laterWorkWasStopped = DispatchSemaphore(value: 0)
        let aRead = expectation(description: "A read its report")
        var aRows = 0
        var aWasCancelled = true
        var aErrored = true
        Thread.detachNewThread {
            if let result = connection.streamingQueryString("SELECT 1", useLowMemoryBlockingStreaming: false) as? SPMySQLStreamingResult {
                while result.getRowAsArray() != nil {
                    aRows += 1
                }
            }
            aReturned.signal()
            _ = laterWorkWasStopped.wait(timeout: .now() + 20)
            aWasCancelled = connection.lastQueryWasCancelled
            aErrored = connection.queryErrored()
            aRead.fulfill()
        }
        XCTAssertEqual(aReturned.wait(timeout: .now() + 10), .success, "A returned")

        // Later work on another thread, stopped while the server is at it - rows that take their
        // time, which the server aborts when the query is killed.
        let bReturned = expectation(description: "B returned")
        var bWasCancelled = false
        Thread.detachNewThread {
            _ = connection.queryString(self.slowRowsStatement)
            bWasCancelled = connection.lastQueryWasCancelled
            bReturned.fulfill()
        }
        var bRuns = false
        for _ in 0..<100 where !bRuns {
            bRuns = try serverRunsAStatementContaining("sa_slow_rows", seenFrom: observer)
            if !bRuns {
                usleep(50_000)
            }
        }
        XCTAssertTrue(bRuns, "B runs on the server")
        connection.cancelCurrentQuery()
        wait(for: [bReturned], timeout: 15)
        XCTAssertTrue(bWasCancelled, "the stop was B's")
        laterWorkWasStopped.signal()
        wait(for: [aRead], timeout: 20)

        XCTAssertEqual(aRows, 1)
        XCTAssertFalse(aWasCancelled, "A's report is its own, settled before B")
        XCTAssertFalse(aErrored)
    }

    /// A failed check asked for on the main thread - which runs on the worker - is read on the
    /// main thread: its error is handed back there, in front of a statement's report handed back
    /// earlier in the same turn.
    func testAFailedCheckAskedForOnTheMainThreadIsReadThere() throws {
        let delegate = SAWaitingDelegate()
        let connection = try connected(SAFailingCheckConnection(), delegate: delegate)
        defer { connection.disconnect() }
        XCTAssertTrue(Thread.isMainThread, "the test stands for the interface")

        _ = connection.queryString("SELECT 1")
        XCTAssertFalse(connection.queryErrored(), "a statement's report is handed back first")

        // The check is due, and fails.
        connection.setValue(0, forKey: "lastConnectionUsedTime")
        XCTAssertFalse(connection.checkIfNecessary())
        XCTAssertTrue(connection.queryErrored(), "the check's error is read where the check was asked for")
        XCTAssertEqual(connection.lastErrorMessage(), "The check failed")

        // A statement stopped earlier in the same turn does not stand in front of the check's error.
        SAStatementReport.handBack(SAStatementReport(errorMessage: "Query cancelled.", errorID: 1317, sqlState: "70100",
                                                     affectedRows: 0, insertID: 0, wasCancelled: true), for: connection)
        connection.setValue(0, forKey: "lastConnectionUsedTime")
        XCTAssertFalse(connection.checkIfNecessary())
        XCTAssertEqual(connection.lastErrorMessage(), "The check failed", "the check's own error, not the earlier stop")
        XCTAssertFalse(connection.lastQueryWasCancelled)
    }

    /// Work the main thread asks for while a streaming result of its own still keeps the session -
    /// its rows not downloaded yet - waits for that session on the worker thread that ran the
    /// streaming statement. Stopping the wait for the later work leaves the earlier statement's
    /// query alone: it is the result's, still being read, and only shares the thread.
    func testStoppingTheWaitForWorkQueuedBehindThisThreadsOwnStreamingResultLeavesThatResultAlone() throws {
        let delegate = SAWaitingDelegate()
        let connection = try connected(SPMySQLConnection(), delegate: delegate)
        defer { connection.disconnect() }
        try prepareSlowRows(on: connection)
        XCTAssertTrue(Thread.isMainThread, "the test stands for the interface")

        // Narrow rows: the download is waited for whole, and a loaded machine takes its time.
        let store = try XCTUnwrap(connection.resultStore(fromQueryString: "SELECT i, SLEEP(0.002) FROM mysql.sa_slow_rows"))
        let storeReport = try XCTUnwrap(SAStatementReport.reportHandedBackToThisThread(for: connection))
        XCTAssertFalse(storeReport.wasCancelled)

        // Later work waits for the session the store keeps; the user stops waiting for it.
        delegate.onceWhileWaiting = { _ in
            connection.cancelCheck()
        }
        let later = connection.queryString("SELECT 'later'")
        XCTAssertNil(later, "the later work was given up on")
        XCTAssertTrue(connection.lastQueryWasCancelled, "and its caller told")

        // The store's rows arrive whole: its query was nobody's to kill.
        store.startDownload()
        let deadline = Date().addingTimeInterval(60)
        while !store.dataDownloaded, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        XCTAssertTrue(store.dataDownloaded)
        XCTAssertEqual(store.numberOfRows(), 900, "every row arrived")
        XCTAssertFalse(storeReport.wasCancelled, "the streaming statement's query was left alone")
        XCTAssertEqual(storeReport.errorID, 0, storeReport.errorMessage ?? "")
    }

    /// A database selection that fails on a connection in a character set other than UTF-8 restores
    /// that character set with a statement of its own, whose report would otherwise stand in front
    /// of the failure; the caller reads the failure.
    func testAFailedDatabaseSelectionIsReadPastTheCharacterSetItRestores() throws {
        let delegate = SAWaitingDelegate()
        let connection = try connected(SPMySQLConnection(), delegate: delegate)
        defer { connection.disconnect() }
        XCTAssertTrue(connection.setEncoding("latin1"))

        XCTAssertFalse(connection.selectDatabase("sa_no_such_database_\(UUID().uuidString.prefix(8))"))
        XCTAssertTrue(connection.queryErrored(), "the selection's failure is read")
        XCTAssertEqual(connection.lastErrorID(), 1049, "unknown database")
    }

    // MARK: - What a statement reports after its report was taken

    /// Gives the connection a table of 900 rows that a streaming statement reads slowly - one row
    /// every 10 ms, each wider than the server's network buffer so that it is sent as soon as it is
    /// produced rather than with the rest at the end - so that something can land while the rows
    /// are still being read. Temporary, so it goes with the session.
    private func prepareSlowRows(on connection: SPMySQLConnection) throws {
        _ = connection.queryString("CREATE TEMPORARY TABLE mysql.sa_slow_rows (i INT NOT NULL)")
        XCTAssertFalse(connection.queryErrored(), connection.lastErrorMessage() ?? "")
        _ = connection.queryString("INSERT INTO mysql.sa_slow_rows WITH RECURSIVE r AS (SELECT 1 AS i UNION ALL SELECT i + 1 FROM r WHERE i < 900) SELECT i FROM r")
        XCTAssertFalse(connection.queryErrored(), connection.lastErrorMessage() ?? "")
        XCTAssertEqual(connection.rowsAffectedByLastQuery(), 900)
    }

    /// The streaming statement over those rows.
    private let slowRowsStatement = "SELECT i, REPEAT('x', 20000) AS padding, SLEEP(0.01) FROM mysql.sa_slow_rows"

    /// A streaming statement's report is taken when the statement returns its result, before its
    /// rows are read, and stays with the connection while the statement holds the session. A stop
    /// during the download is written into it from there - and the caller, reading on its own
    /// thread with that report handed back to it, reads the stop, even once another thread's
    /// statement has run on the connection in between. The caller is a task thread here, like
    /// the exporters, which runs its statement where it asks for it.
    func testAStopDuringAStreamingDownloadIsReadByTheStatementsCaller() throws {
        let delegate = SAWaitingDelegate()
        let connection = try connected(SPMySQLConnection(), delegate: delegate)
        defer { connection.disconnect() }
        try prepareSlowRows(on: connection)

        let tenRowsRead = DispatchSemaphore(value: 0)
        let downloadEnded = DispatchSemaphore(value: 0)
        let anotherStatementRan = DispatchSemaphore(value: 0)
        let finished = expectation(description: "the rows were read to the end")
        var rows = 0
        var wasCancelled = false
        var errored = false
        var errorID: UInt = 0
        Thread.detachNewThread {
            if let result = connection.streamingQueryString(self.slowRowsStatement, useLowMemoryBlockingStreaming: true) as? SPMySQLStreamingResult {
                while result.getRowAsArray() != nil {
                    rows += 1
                    if rows == 10 {
                        tenRowsRead.signal()
                    }
                }
            } else {
                tenRowsRead.signal()
            }
            // Another thread's statement runs on the connection before this caller reads.
            downloadEnded.signal()
            _ = anotherStatementRan.wait(timeout: .now() + 10)
            wasCancelled = connection.lastQueryWasCancelled
            errored = connection.queryErrored()
            errorID = connection.lastErrorID()
            finished.fulfill()
        }
        XCTAssertEqual(tenRowsRead.wait(timeout: .now() + 10), .success, "rows are being read")
        connection.cancelCurrentQuery()
        XCTAssertEqual(downloadEnded.wait(timeout: .now() + 20), .success, "the download ended")
        _ = connection.queryString("SELECT 'another statement'")
        XCTAssertFalse(connection.queryErrored(), "the other statement ran: \(connection.lastErrorMessage() ?? "")")
        anotherStatementRan.signal()
        wait(for: [finished], timeout: 20)

        XCTAssertGreaterThanOrEqual(rows, 10)
        XCTAssertLessThan(rows, 900, "the download was stopped")
        XCTAssertTrue(wasCancelled, "the caller reads the stop")
        XCTAssertTrue(errored)
        XCTAssertEqual(errorID, 1317, "query execution was interrupted")
    }

    /// A connection lost during a streaming download - the SQL export's case - is read by the
    /// statement's caller the same way, as an error that is not a stop, and again once another
    /// thread's statement has been tried on the connection in between.
    func testALostConnectionDuringAStreamingDownloadIsReadByTheStatementsCaller() throws {
        let delegate = SAWaitingDelegate()
        let connection = try connected(SPMySQLConnection(), delegate: delegate)
        let observer = try connected(SPMySQLConnection(), delegate: SAWaitingDelegate())
        defer {
            connection.disconnect()
            observer.disconnect()
        }
        let serverThread = connection.mysqlConnectionThreadId
        try prepareSlowRows(on: connection)

        let tenRowsRead = DispatchSemaphore(value: 0)
        let downloadEnded = DispatchSemaphore(value: 0)
        let anotherStatementRan = DispatchSemaphore(value: 0)
        let finished = expectation(description: "the rows were read to the end")
        var rows = 0
        var wasCancelled = false
        var errored = false
        var errorID: UInt = 0
        Thread.detachNewThread {
            if let result = connection.streamingQueryString(self.slowRowsStatement, useLowMemoryBlockingStreaming: true) as? SPMySQLStreamingResult {
                while result.getRowAsArray() != nil {
                    rows += 1
                    if rows == 10 {
                        tenRowsRead.signal()
                    }
                }
            } else {
                tenRowsRead.signal()
            }
            // Another thread's statement is tried on the connection before this caller reads.
            downloadEnded.signal()
            _ = anotherStatementRan.wait(timeout: .now() + 10)
            wasCancelled = connection.lastQueryWasCancelled
            errored = connection.queryErrored()
            errorID = connection.lastErrorID()
            finished.fulfill()
        }
        XCTAssertEqual(tenRowsRead.wait(timeout: .now() + 10), .success, "rows are being read")
        _ = observer.queryString("KILL \(serverThread)")
        XCTAssertFalse(observer.queryErrored(), "the connection was killed: \(observer.lastErrorMessage() ?? "")")
        XCTAssertEqual(downloadEnded.wait(timeout: .now() + 20), .success, "the download ended")
        // Tried, not necessarily run: the session is gone, and the delegate lets it go.
        _ = connection.queryString("SELECT 'another statement'")
        anotherStatementRan.signal()
        wait(for: [finished], timeout: 20)

        XCTAssertGreaterThanOrEqual(rows, 10)
        XCTAssertLessThan(rows, 900, "the download ended early")
        XCTAssertTrue(errored, "the caller reads the lost connection")
        XCTAssertEqual(errorID, 2013, "lost connection during query")
        XCTAssertFalse(wasCancelled, "a lost connection is not a stop")
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
