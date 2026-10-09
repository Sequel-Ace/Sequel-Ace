//
//  SAConnectionCancellationTests.swift
//  SPMySQLFramework
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//
//  More info at <https://github.com/Sequel-Ace/Sequel-Ace>
//

import XCTest
@testable import SPMySQL

final class SAConnectionCancellationTests: XCTestCase {

    /// A connection stand-in that records what the cancellation logic asks of it.
    private final class SARecordingHost: NSObject, SAConnectionCancellationHost {
        let lock = NSLock()
        var currentQueryGeneration: UInt = 0
        var connectionIsFree = true
        var sessionHasOpenTransaction = false
        var calls: [String] = []
        let killRequested = DispatchSemaphore(value: 0)

        /// Records one call the cancellation logic made.
        func note(_ call: String) {
            lock.lock()
            calls.append(call)
            lock.unlock()
        }

        /// The calls recorded so far, in the order they were made.
        func recordedCalls() -> [String] {
            lock.lock()
            defer { lock.unlock() }
            return calls
        }

        /// Records that the next attempt was asked to be short.
        func noteUserEndedWait() { note("endedWait") }
        /// Records that the running query was marked cancelled.
        func markRunningQueryCancelled() { note("marked") }
        /// Records a kill request, lets the test know it was made, and reports it accepted.
        func killQueryOverSideConnection(forGeneration generation: UInt) -> Bool {
            note("kill \(generation)")
            killRequested.signal()
            return true
        }
        /// Records the attempt to take the connection, which succeeds while it is free.
        func holdConnectionIfFree() -> Bool {
            note("hold")
            return connectionIsFree
        }
        /// Records that the connection was given back.
        func releaseHeldConnection() { note("release") }
        /// Records that the outcome was recorded as cancelled.
        func recordWorkAsCancelled() { note("recorded") }
        /// Records that the session was closed.
        func closeSessionIfConnected() { note("closed") }
        var sessionSocketToken: UInt = 1
        func noteNativeReadEndedByCancellation(onSocket socketToken: UInt) {
            note("recoverNeeded(\(socketToken))")
        }
    }

    /// A connection stand-in whose kill request does not come back until the test lets it, as a
    /// side connection over a route that has gone does not.
    private final class SABlockedKillHost: NSObject, SAConnectionCancellationHost {
        var currentQueryGeneration: UInt = 0
        var sessionHasOpenTransaction = false
        let letTheKillReturn = DispatchSemaphore(value: 0)
        let killHasReturned = DispatchSemaphore(value: 0)
        let socketWasClosed = DispatchSemaphore(value: 0)

        func noteUserEndedWait() {}
        func markRunningQueryCancelled() { socketWasClosed.signal() }
        func killQueryOverSideConnection(forGeneration generation: UInt) -> Bool {
            letTheKillReturn.wait()
            killHasReturned.signal()
            return true
        }
        func holdConnectionIfFree() -> Bool { true }
        func releaseHeldConnection() {}
        func recordWorkAsCancelled() {}
        func closeSessionIfConnected() {}
        var sessionSocketToken: UInt = 1
        func noteNativeReadEndedByCancellation(onSocket socketToken: UInt) {}
    }

    private let host = SARecordingHost()
    private let inFlightQuery = SAInFlightQuery()
    private lazy var cancellation = SAConnectionCancellation(host: host, inFlightQuery: inFlightQuery)

    /// The request is recorded before the server is asked.
    func testTheRequestIsRecordedBeforeTheServerIsAsked() {
        inFlightQuery.beginWaiting(forGeneration: 4, onSocket: -1, serverThread: 11)

        cancellation.requestCancellation(ofGeneration: 4, synchronously: true)

        XCTAssertEqual(host.recordedCalls(), ["kill 4"])
        XCTAssertTrue(inFlightQuery.cancellationWasRequested(forGeneration: 4))
    }

    /// A request is remembered for a query that is between attempts.
    func testARequestIsRememberedForAQueryThatIsBetweenAttempts() {
        cancellation.requestCancellation(ofGeneration: 4, synchronously: true)

        XCTAssertEqual(host.recordedCalls(), ["kill 4"])
        XCTAssertTrue(inFlightQuery.cancellationWasRequested(forGeneration: 4))
        XCTAssertFalse(inFlightQuery.cancellationWasRequested(forGeneration: 5))
    }

    /// The main thread never waits for the server.
    func testTheMainThreadNeverWaitsForTheServer() {
        cancellation.requestCancellation(ofGeneration: 4, synchronously: false)

        XCTAssertEqual(host.killRequested.wait(timeout: .now() + 2), .success)
    }

    /// Nothing is requested without a query.
    func testNothingIsRequestedWithoutAQuery() {
        cancellation.requestCancellation(ofGeneration: 0, synchronously: true)

        XCTAssertEqual(host.recordedCalls(), [])
    }

    /// The grace period runs from the moment stopping was asked for, not from the server's answer.
    ///
    /// A synchronous request is waited for here, and reaching the server over a route that has gone
    /// takes the side connection's own timeouts. If the grace period only started afterwards, the
    /// query's socket would stay open for all of that and two seconds more - the wait this is meant
    /// to bound.
    func testTheGracePeriodDoesNotWaitForTheServer() throws {
        let socket = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        try XCTSkipIf(socket < 0, "no socket to close")
        defer { Darwin.close(socket) }

        let blockedHost = SABlockedKillHost()
        let inFlight = SAInFlightQuery()
        let cancellation = SAConnectionCancellation(host: blockedHost, inFlightQuery: inFlight)
        inFlight.beginWaiting(forGeneration: 7, onSocket: socket, serverThread: 11)

        DispatchQueue.global().async {
            cancellation.requestCancellation(ofGeneration: 7, synchronously: true)
        }

        // The socket is closed once the grace period is over, while the kill is still out there.
        XCTAssertEqual(blockedHost.socketWasClosed.wait(timeout: .now() + SAConnectionCancellation.shutdownGrace + 3),
                       .success, "the grace period waited for the server")
        XCTAssertEqual(blockedHost.killHasReturned.wait(timeout: .now()), .timedOut,
                       "and it did so before the server answered")
        blockedHost.letTheKillReturn.signal()
        XCTAssertEqual(blockedHost.killHasReturned.wait(timeout: .now() + 5), .success)
    }

    /// Stopping the wait stops the query the stopped work started.
    func testStoppingTheWaitStopsTheQueryTheWorkStarted() {
        let coordinator = SAConnectionWorkCoordinator()
        let workStarted = DispatchSemaphore(value: 0)
        _ = coordinator.run({
            self.inFlightQuery.noteLatestGeneration(9)
            workStarted.signal()
            while !Thread.current.isCancelled {
                usleep(1_000)
            }
            return nil
        }, operationStamp: { 9 }, whenSlow: { _ in
            XCTAssertEqual(workStarted.wait(timeout: .now() + 2), .success)
            self.cancellation.userStoppedWaiting(workCoordinator: coordinator)
        }, whenAbandonedWorkFinishes: { _ in })

        XCTAssertEqual(host.killRequested.wait(timeout: .now() + 2), .success)
        XCTAssertEqual(host.recordedCalls(), ["endedWait", "kill 9"])
    }

    /// Stopping the wait leaves a query alone that another thread runs while the work waits for the connection.
    func testStoppingTheWaitLeavesAnotherThreadsQueryAlone() {
        let otherThreadTookTheConnection = expectation(description: "another thread took the connection")
        Thread {
            self.inFlightQuery.noteLatestGeneration(7)
            otherThreadTookTheConnection.fulfill()
        }.start()
        wait(for: [otherThreadTookTheConnection], timeout: 2)

        let coordinator = SAConnectionWorkCoordinator()
        let workStarted = DispatchSemaphore(value: 0)
        _ = coordinator.run({
            workStarted.signal()
            while !Thread.current.isCancelled {
                usleep(1_000)
            }
            return nil
        }, operationStamp: { 7 }, whenSlow: { _ in
            XCTAssertEqual(workStarted.wait(timeout: .now() + 2), .success)
            self.cancellation.userStoppedWaiting(workCoordinator: coordinator)
        }, whenAbandonedWorkFinishes: { _ in })

        XCTAssertEqual(host.killRequested.wait(timeout: .now() + 0.5), .timedOut)
        XCTAssertEqual(host.recordedCalls(), ["endedWait"])
    }

    /// Without work handed to a thread there is no query to stop.
    func testStoppingWithoutWorkStopsNothing() {
        host.currentQueryGeneration = 9
        cancellation.userStoppedWaiting(workCoordinator: nil)

        XCTAssertEqual(host.killRequested.wait(timeout: .now() + 0.5), .timedOut)
        XCTAssertEqual(host.recordedCalls(), ["endedWait"])
    }

    /// Late work is settled while nothing else has run.
    func testLateWorkIsSettledWhileNothingElseHasRun() {
        host.currentQueryGeneration = 3
        cancellation.settleAbandonedWork(fromGeneration: 3)

        XCTAssertEqual(host.recordedCalls(), ["hold", "recorded", "closed", "release"])
    }

    /// Late work leaves a query that came after it alone.
    func testLateWorkLeavesAQueryThatCameAfterItAlone() {
        host.currentQueryGeneration = 4
        cancellation.settleAbandonedWork(fromGeneration: 3)

        XCTAssertEqual(host.recordedCalls(), ["hold", "release"])
    }

    /// Late work leaves a connection that is in use alone.
    func testLateWorkLeavesAConnectionThatIsInUseAlone() {
        host.currentQueryGeneration = 3
        host.connectionIsFree = false
        cancellation.settleAbandonedWork(fromGeneration: 3)

        XCTAssertEqual(host.recordedCalls(), ["hold"])
    }

    /// A cancelled reconnect keeps the connection recoverable.
    func testACancelledReconnectKeepsTheConnectionRecoverable() {
        XCTAssertEqual(recovery(cancelled: true, userDisconnected: false, connected: false, disconnected: true, mayDisconnect: false), .markLost)
        XCTAssertEqual(recovery(cancelled: true, userDisconnected: false, connected: true, disconnected: false, mayDisconnect: true), .discardAndMarkLost)
    }

    /// A connection is only closed where that is safe.
    func testAConnectionIsOnlyClosedWhereThatIsSafe() {
        XCTAssertEqual(recovery(cancelled: true, userDisconnected: false, connected: true, disconnected: false, mayDisconnect: false), .none)
    }
    /// Only a session that will not be used again has its stored encoding put back on record
    /// alone; one still in use is told, or the record and the session would disagree.
    func testOnlyASessionOnItsWayOutIsSpared() {
        XCTAssertTrue(SAConnectionCancellation.storedEncodingOnlyNeedsRecording(
            sessionWillBeReplaced: true, hasNoUsableSession: false),
            "a session marked to be replaced is not worth a statement")
        XCTAssertTrue(SAConnectionCancellation.storedEncodingOnlyNeedsRecording(
            sessionWillBeReplaced: false, hasNoUsableSession: true),
            "and there is nothing to tell when there is no session")
        XCTAssertFalse(SAConnectionCancellation.storedEncodingOnlyNeedsRecording(
            sessionWillBeReplaced: false, hasNoUsableSession: false),
            "a session still in use is told, or it reads statements in one character set while the record says another")
    }

    /// A mark acted on later does not close a session something else has opened a transaction in -
    /// unless the protocol cannot be trusted on it, which no transaction is worth.
    func testAMarkDoesNotCloseASessionWithWorkGoingOnInIt() {
        XCTAssertTrue(SAConnectionCancellation.markedSessionIsClosedNow(sessionHasOpenTransaction: false,
                                                                        sessionIsProtocolInvalid: false),
                      "nothing is open, so the mark is acted on")
        XCTAssertFalse(SAConnectionCancellation.markedSessionIsClosedNow(sessionHasOpenTransaction: true,
                                                                         sessionIsProtocolInvalid: false),
                       "closing it would roll back work somebody is still doing")
        XCTAssertTrue(SAConnectionCancellation.markedSessionIsClosedNow(sessionHasOpenTransaction: true,
                                                                        sessionIsProtocolInvalid: true),
                      "a cut-off ping's answer would be read as the next statement's result, so it goes")
        XCTAssertTrue(SAConnectionCancellation.markedSessionIsClosedNow(sessionHasOpenTransaction: false,
                                                                        sessionIsProtocolInvalid: true))
    }

    /// A query given up on affects nothing, as far as anybody can say.
    ///
    /// The count still described the statement before it, and callers work out success from it:
    /// the content view's row deletion compares it with how many rows it meant to delete and, on
    /// a match, takes them off the screen without asking the error.
    func testAQueryGivenUpOnAffectsNoRows() throws {
        let connection = SPMySQLConnection()
        connection.useKeepAlive = false
        defer {
            connection.setValue(SPMySQLDisconnected.rawValue, forKey: "state")
            connection.disconnect()
        }
        connection.setValue(UInt64(7), forKey: "lastQueryAffectedRowCount")
        XCTAssertEqual(connection.rowsAffectedByLastQuery(), 7, "what the statement before it did")

        connection.perform(NSSelectorFromString("_recordWorkAsCancelled"))

        XCTAssertTrue(connection.lastQueryWasCancelled)
        XCTAssertEqual(connection.rowsAffectedByLastQuery(), 0,
                       "the stopped statement did not do that, and must not look as if it had")
    }

    /// A statement that never reached the server affects nothing either, whichever way out it took.
    ///
    /// Every early return in `_queryString:` - refused for uncommitted work the connection lost,
    /// stopped before it was sent, stopped while the connection was being checked, not allowed to
    /// send at all - used to leave the count describing the statement before it.
    func testAStatementThatNeverRanAffectsNoRows() throws {
        guard let connection = newLocalConnection() else {
            throw XCTSkip("no local MySQL connection configured")
        }
        try XCTSkipUnless(connection.connect(), "local MySQL connection is unavailable")
        defer { connection.disconnect() }

        let database = "sa_rows_\(UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "_"))"
        connection.queryString("CREATE DATABASE \(database)")
        try XCTSkipIf(connection.queryErrored(), "cannot create a database for the regression")
        defer { connection.queryString("DROP DATABASE IF EXISTS \(database)") }
        connection.queryString("USE \(database)")
        connection.queryString("CREATE TABLE t (id INT PRIMARY KEY)")
        try XCTSkipIf(connection.queryErrored(), "cannot create a table for the regression")

        connection.queryString("INSERT INTO t (id) VALUES (1), (2), (3)")
        XCTAssertEqual(connection.rowsAffectedByLastQuery(), 3, "three rows went in")

        // A statement the user stopped before it was sent: the stop is recorded against the next
        // query's number, which is the shape the early returns take.
        connection.setValue(true, forKey: "userTriggeredDisconnect")
        defer { connection.setValue(false, forKey: "userTriggeredDisconnect") }

        XCTAssertNil(connection.queryString("DELETE FROM t WHERE id IN (1, 2, 3)"),
                     "the statement did not run")
        XCTAssertEqual(connection.rowsAffectedByLastQuery(), 0,
                       "and must not report what the INSERT before it did, which the row deletion would read as success")
    }

    /// Only work that used the session outside a transaction leaves it to be replaced.
    func testOnlyWorkThatUsedTheSessionOutsideATransactionLeavesItToBeReplaced() {
        XCTAssertFalse(SAConnectionCancellation.replacesSessionWhenWorkIsGivenUp(sessionUse: .untouched))
        XCTAssertTrue(SAConnectionCancellation.replacesSessionWhenWorkIsGivenUp(sessionUse: .outsideTransaction))
        XCTAssertFalse(SAConnectionCancellation.replacesSessionWhenWorkIsGivenUp(sessionUse: .insideTransaction))
    }

    /// A session kept for a transaction the user had open is closed only once that transaction is over.
    func testASessionKeptForATransactionIsClosedOnlyOnceTheTransactionIsOver() {
        XCTAssertFalse(SAConnectionCancellation.closesSessionOfAbandonedWork(sessionUse: .insideTransaction, sessionHasOpenTransaction: true, markedForReplacement: false))
        XCTAssertTrue(SAConnectionCancellation.closesSessionOfAbandonedWork(sessionUse: .insideTransaction, sessionHasOpenTransaction: false, markedForReplacement: false))
        XCTAssertTrue(SAConnectionCancellation.closesSessionOfAbandonedWork(sessionUse: .insideTransaction, sessionHasOpenTransaction: true, markedForReplacement: true))
    }

    /// A transaction the stopped work opened itself is closed with its session.
    func testATransactionTheStoppedWorkOpenedItselfIsClosedWithItsSession() {
        XCTAssertTrue(SAConnectionCancellation.closesSessionOfAbandonedWork(sessionUse: .outsideTransaction, sessionHasOpenTransaction: true, markedForReplacement: false))
        XCTAssertTrue(SAConnectionCancellation.closesSessionOfAbandonedWork(sessionUse: .outsideTransaction, sessionHasOpenTransaction: false, markedForReplacement: true))
    }

    /// Work that sent nothing leaves the session open, whatever it has open.
    func testWorkThatSentNothingLeavesTheSessionOpen() {
        XCTAssertFalse(SAConnectionCancellation.closesSessionOfAbandonedWork(sessionUse: .untouched, sessionHasOpenTransaction: true, markedForReplacement: false))
        XCTAssertFalse(SAConnectionCancellation.closesSessionOfAbandonedWork(sessionUse: .untouched, sessionHasOpenTransaction: false, markedForReplacement: false))
    }

    /// A session whose ping was cut off before its answer came is replaced; any other is kept.
    func testASessionIsReplacedOnlyAfterAPingCutOffBeforeItsAnswer() {
        XCTAssertTrue(SAConnectionCancellation.replacesSessionAfterPing(cutOff: true, pingSucceeded: false))
        XCTAssertFalse(SAConnectionCancellation.replacesSessionAfterPing(cutOff: true, pingSucceeded: true))
        XCTAssertFalse(SAConnectionCancellation.replacesSessionAfterPing(cutOff: false, pingSucceeded: false))
        XCTAssertFalse(SAConnectionCancellation.replacesSessionAfterPing(cutOff: false, pingSucceeded: true))
    }

    /// Dropping a session loses uncommitted work when a transaction is open or autocommit was turned off.
    func testDroppingASessionLosesUncommittedWorkOnlyWithATransactionOrAutocommitTurnedOff() {
        XCTAssertTrue(SAConnectionCancellation.droppingSessionLosesUncommittedWork(openTransaction: true, autocommit: true, autocommitAtConnect: true))
        XCTAssertTrue(SAConnectionCancellation.droppingSessionLosesUncommittedWork(openTransaction: false, autocommit: false, autocommitAtConnect: true))
        XCTAssertFalse(SAConnectionCancellation.droppingSessionLosesUncommittedWork(openTransaction: false, autocommit: true, autocommitAtConnect: true))
        // A server that starts every session with autocommit off hands the next session the same.
        XCTAssertFalse(SAConnectionCancellation.droppingSessionLosesUncommittedWork(openTransaction: false, autocommit: false, autocommitAtConnect: false))
        XCTAssertTrue(SAConnectionCancellation.droppingSessionLosesUncommittedWork(openTransaction: true, autocommit: false, autocommitAtConnect: false))
    }

    /// Decides with every report pending unless a test says otherwise.
    private func refusal(editor: Bool = true, writes: Bool = true, retries: Bool, sentByConnection: Bool = false, leavesDataAlone: Bool) -> SALostWorkRefusal {
        SAConnectionCancellation.lostWorkRefusal(reportPendingForEditor: editor, reportPendingForWrites: writes,
                                                 retriesStatements: retries, sentByConnection: sentByConnection,
                                                 statementLeavesDataAlone: leavesDataAlone)
    }

    /// After lost uncommitted work, the query editor's next statement is refused, whatever it is.
    func testTheQueryEditorsNextStatementIsRefusedAfterLostWork() {
        XCTAssertEqual(refusal(retries: false, leavesDataAlone: true), .editorStatement)
        XCTAssertEqual(refusal(retries: false, leavesDataAlone: false), .editorStatement)
        XCTAssertEqual(refusal(editor: false, retries: false, leavesDataAlone: false), .none)
    }

    /// The query editor is still told after a write elsewhere was refused for the same loss.
    func testTheQueryEditorIsToldEvenAfterAWriteElsewhereWasRefused() {
        XCTAssertEqual(refusal(writes: false, retries: false, leavesDataAlone: true), .editorStatement)
    }

    /// After lost uncommitted work, the application's writes are refused, and its reads run.
    func testTheApplicationsWritesAreRefusedAfterLostWork() {
        XCTAssertEqual(refusal(retries: true, leavesDataAlone: false), .applicationWrite)
        XCTAssertEqual(refusal(editor: false, retries: true, leavesDataAlone: false), .applicationWrite)
        XCTAssertEqual(refusal(retries: true, leavesDataAlone: true), .none)
        XCTAssertEqual(refusal(writes: false, retries: true, leavesDataAlone: false), .none)
    }

    /// The statements the connection sends itself - setting up a new session, or its upkeep - always
    /// run, and leave the report for the caller.
    func testTheStatementsTheConnectionSendsItselfAlwaysRun() {
        XCTAssertEqual(refusal(retries: false, sentByConnection: true, leavesDataAlone: false), .none)
        XCTAssertEqual(refusal(retries: true, sentByConnection: true, leavesDataAlone: false), .none)
    }

    /// Only a thread other than the main thread restores a lost session when asked whether it is connected.
    func testOnlyBackgroundThreadsRestoreALostSessionWhenAsked() {
        XCTAssertFalse(SAConnectionCancellation.restoresLostSessionWhenAskedIfConnected(onMainThread: true))
        XCTAssertTrue(SAConnectionCancellation.restoresLostSessionWhenAskedIfConnected(onMainThread: false))
    }

    /// A connection without a session answers which server it talks to from what it recorded.
    func testServerQuestionsDoNotNeedTheSessionsHandle() {
        let connection = SPMySQLConnection()
        XCTAssertFalse(connection.isMariaDB())
        XCTAssertTrue(connection.isNotMariadb103())
    }

    /// A session with an open transaction keeps its socket once the server accepted the kill.
    func testAnAcceptedKillLeavesASessionWithAnOpenTransactionToTheServer() {
        XCTAssertFalse(SAConnectionCancellation.closesSocketAfterGrace(killAccepted: true, sessionHasOpenTransaction: true))
        XCTAssertTrue(SAConnectionCancellation.closesSocketAfterGrace(killAccepted: true, sessionHasOpenTransaction: false))
        XCTAssertTrue(SAConnectionCancellation.closesSocketAfterGrace(killAccepted: false, sessionHasOpenTransaction: true))
        XCTAssertTrue(SAConnectionCancellation.closesSocketAfterGrace(killAccepted: false, sessionHasOpenTransaction: false))
    }

    /// An answer that comes before the grace period ends leaves the decision to the grace period.
    func testAnEarlyAnswerIsDecidedWhenTheGracePeriodEnds() {
        let attempt = SAKillAttempt()
        XCTAssertFalse(attempt.finish(accepted: true))
        XCTAssertEqual(attempt.endGrace(waitingForAnswer: true), true)
    }

    /// With a transaction open, an answer that comes after the grace period ended decides when it comes.
    func testALateAnswerDecidesWhenItIsWaitedFor() {
        let attempt = SAKillAttempt()
        XCTAssertNil(attempt.endGrace(waitingForAnswer: true))
        XCTAssertTrue(attempt.finish(accepted: false))
    }

    /// Without a transaction the grace period decides on its own, and a late answer changes nothing.
    func testTheGracePeriodDecidesAloneWhenNoAnswerIsWaitedFor() {
        let attempt = SAKillAttempt()
        XCTAssertEqual(attempt.endGrace(waitingForAnswer: false), false)
        XCTAssertFalse(attempt.finish(accepted: true))
    }

    /// Nothing changes without a cancellation or after the user disconnected.
    func testNothingChangesWithoutACancellationOrAfterTheUserDisconnected() {
        XCTAssertEqual(recovery(cancelled: false, userDisconnected: false, connected: false, disconnected: true, mayDisconnect: true), .none)
        XCTAssertEqual(recovery(cancelled: true, userDisconnected: true, connected: false, disconnected: true, mayDisconnect: true), .none)
    }

    /// Asks the recovery decision with readable argument names.
    private func recovery(cancelled: Bool, userDisconnected: Bool, connected: Bool, disconnected: Bool, mayDisconnect: Bool) -> SAConnectionRecoveryAction {
        SAConnectionCancellation.recoveryAfterCancelledReconnect(threadCancelled: cancelled,
                                                                 userDisconnected: userDisconnected,
                                                                 isConnected: connected,
                                                                 isDisconnected: disconnected,
                                                                 mayDisconnect: mayDisconnect)
    }

    // MARK: - Against a live server

    /// Verifies a session a mark names is kept while a transaction is open in it, and replaced
    /// once there is none.
    ///
    /// The mark is made when work nobody waited for is given up on, and acted on when the session
    /// is next wanted. A query that took the connection over in between can have opened a
    /// transaction: closing the session then rolls that back without a word. The connection id is
    /// the proof either way - it changes exactly when the session is replaced.
    func testAMarkedSessionIsKeptWhileATransactionIsOpenInIt() throws {
        guard let connection = newLocalConnection() else {
            throw XCTSkip("no local MySQL connection configured")
        }
        try XCTSkipUnless(connection.connect(), "local MySQL connection is unavailable")
        defer { connection.disconnect() }

        let theSession = try XCTUnwrap(connection.getFirstField(fromQuery: "SELECT CONNECTION_ID()") as? String)

        // Something else took the connection over and opened a transaction in it.
        connection.queryString("START TRANSACTION")
        XCTAssertFalse(connection.queryErrored())

        // The mark from work that was given up on earlier is still standing.
        connection.setValue(true, forKey: "sessionMustBeReplacedBeforeUse")

        XCTAssertEqual(connection.getFirstField(fromQuery: "SELECT CONNECTION_ID()") as? String, theSession,
                       "the session was kept, so the open transaction was not rolled back")
        XCTAssertTrue(connection.value(forKey: "sessionMustBeReplacedBeforeUse") as? Bool ?? false,
                      "and the mark still stands, for once nothing is open in it")

        connection.queryString("ROLLBACK")
        XCTAssertFalse(connection.queryErrored())

        XCTAssertNotEqual(connection.getFirstField(fromQuery: "SELECT CONNECTION_ID()") as? String, theSession,
                          "with nothing open the mark is acted on and the session is replaced")
    }

    /// Verifies the stored encoding goes back on record without the session being told, when that
    /// session is on its way out - and that a session still in use is told, as before.
    ///
    /// Against a live server, because that is the only place the difference shows: without one,
    /// `setEncoding:` finds nothing to send to and both paths look the same from outside.
    func testTheStoredEncodingIsOnlyRecordedForASessionOnItsWayOut() throws {
        guard let connection = newLocalConnection() else {
            throw XCTSkip("no local MySQL connection configured")
        }
        try XCTSkipUnless(connection.connect(), "local MySQL connection is unavailable")
        defer { connection.disconnect() }

        XCTAssertTrue(connection.setEncoding("utf8mb4"))
        connection.storeEncodingForRestoration()
        XCTAssertTrue(connection.setEncoding("latin1"))

        // This session is on its way out.
        connection.setValue(true, forKey: "sessionMustBeReplacedBeforeUse")
        connection.restoreStoredEncoding()

        XCTAssertEqual(connection.value(forKey: "encoding") as? String, "utf8mb4",
                       "the record is back, for the session that replaces this one")
        connection.setValue(false, forKey: "sessionMustBeReplacedBeforeUse")
        XCTAssertEqual(connection.getFirstField(fromQuery: "SELECT @@character_set_client") as? String,
                       "latin1",
                       "and the session itself was not told, so nothing was sent to tell it")
    }

    /// Verifies a session that is staying is told about the restored encoding, as before.
    func testASessionThatIsStayingIsToldAboutTheRestoredEncoding() throws {
        guard let connection = newLocalConnection() else {
            throw XCTSkip("no local MySQL connection configured")
        }
        try XCTSkipUnless(connection.connect(), "local MySQL connection is unavailable")
        defer { connection.disconnect() }

        XCTAssertTrue(connection.setEncoding("utf8mb4"))
        connection.storeEncodingForRestoration()
        XCTAssertTrue(connection.setEncoding("latin1"))

        connection.setValue(false, forKey: "sessionMustBeReplacedBeforeUse")
        connection.restoreStoredEncoding()

        XCTAssertEqual(connection.value(forKey: "encoding") as? String, "utf8mb4")
        XCTAssertEqual(connection.getFirstField(fromQuery: "SELECT @@character_set_client") as? String,
                       "utf8mb4",
                       "the session was told, which is what keeps record and server in step")
    }

    /// A reconnect's pending restoration is corrected along with the record.
    ///
    /// What to restore is noted when a reconnect starts, so one that started while a temporary
    /// character set was in force holds that temporary one - and a reconnect that was cancelled or
    /// failed keeps that note for its next attempt. Putting the stored encoding back without saying
    /// so leaves that attempt restoring the temporary character set instead of the user's: the
    /// connection would say one and the session it comes back with would be in another.
    func testRestoringTheStoredEncodingCorrectsAPendingReconnectToo() throws {
        guard let connection = newLocalConnection() else {
            throw XCTSkip("no local MySQL connection configured")
        }
        try XCTSkipUnless(connection.connect(), "local MySQL connection is unavailable")
        defer { connection.disconnect() }

        XCTAssertTrue(connection.setEncoding("utf8mb4"))
        connection.storeEncodingForRestoration()
        XCTAssertTrue(connection.setEncoding("latin1"))

        // A reconnect started while the temporary character set was in force and did not finish,
        // so its note still says latin1.
        connection.setValue("latin1", forKey: "encodingToRestore")

        // The session on its way out, which is only recorded.
        connection.setValue(true, forKey: "sessionMustBeReplacedBeforeUse")
        connection.restoreStoredEncoding()
        XCTAssertEqual(connection.value(forKey: "encodingToRestore") as? String, "utf8mb4",
                       "the next reconnect must not restore the temporary character set")

        // And the session that stays, which is told.
        connection.setValue(false, forKey: "sessionMustBeReplacedBeforeUse")
        XCTAssertTrue(connection.setEncoding("latin1"))
        connection.setValue("latin1", forKey: "encodingToRestore")
        connection.restoreStoredEncoding()
        XCTAssertEqual(connection.value(forKey: "encodingToRestore") as? String, "utf8mb4")

        // Nothing is invented where no reconnect is waiting to restore anything.
        XCTAssertTrue(connection.setEncoding("latin1"))
        connection.setValue(nil, forKey: "encodingToRestore")
        connection.restoreStoredEncoding()
        XCTAssertNil(connection.value(forKey: "encodingToRestore"))
    }

    /// A connection to the local server, if one is configured; see the escaping integration tests.
    private func newLocalConnection() -> SPMySQLConnection? {
        let environment = ProcessInfo.processInfo.environment
        var socketPath = environment["SPMYSQL_TEST_SOCKET"]
        let testHost = environment["SPMYSQL_TEST_HOST"]
        if (socketPath?.isEmpty ?? true), (testHost?.isEmpty ?? true) {
            socketPath = ["/tmp/mysql.sock", "/opt/homebrew/var/mysql/mysql.sock"]
                .first(where: { FileManager.default.fileExists(atPath: $0) })
        }
        let connection = SPMySQLConnection()
        let testUser = environment["SPMYSQL_TEST_USER"]
        connection.username = testUser?.isEmpty == false ? testUser : "root"
        connection.password = environment["SPMYSQL_TEST_PASSWORD"]
        connection.useKeepAlive = false
        if let testHost, !testHost.isEmpty {
            connection.useSocket = false
            connection.host = testHost
            if let port = environment["SPMYSQL_TEST_PORT"].flatMap(UInt.init) {
                connection.port = port
            }
            return connection
        }
        guard let socketPath, !socketPath.isEmpty else { return nil }
        connection.useSocket = true
        connection.socketPath = socketPath
        return connection
    }
}
