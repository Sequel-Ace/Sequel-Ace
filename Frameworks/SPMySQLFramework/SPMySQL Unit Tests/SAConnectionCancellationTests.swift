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

    /// A stored character set is only put on record while the session is gone or on its way out.
    func testStoredEncodingIsOnlyRecordedWhileTheSessionIsOnItsWayOut() {
        XCTAssertTrue(SAConnectionCancellation.storedEncodingOnlyNeedsRecording(afterAbandonedWork: true, hasNoUsableSession: false, sessionHasOpenTransaction: false))
        XCTAssertTrue(SAConnectionCancellation.storedEncodingOnlyNeedsRecording(afterAbandonedWork: false, hasNoUsableSession: true, sessionHasOpenTransaction: false))
        XCTAssertFalse(SAConnectionCancellation.storedEncodingOnlyNeedsRecording(afterAbandonedWork: false, hasNoUsableSession: false, sessionHasOpenTransaction: false))
    }

    /// A session with an open transaction is told the character set after its work was abandoned.
    func testASessionWithAnOpenTransactionIsToldTheCharacterSet() {
        XCTAssertFalse(SAConnectionCancellation.storedEncodingOnlyNeedsRecording(afterAbandonedWork: true, hasNoUsableSession: false, sessionHasOpenTransaction: true))
        // A session that is gone, or marked for replacement, is not told, transaction or not.
        XCTAssertTrue(SAConnectionCancellation.storedEncodingOnlyNeedsRecording(afterAbandonedWork: true, hasNoUsableSession: true, sessionHasOpenTransaction: true))
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
    private func refusal(editor: Bool = true, writes: Bool = true, retries: Bool, settingUp: Bool = false, leavesDataAlone: Bool) -> SALostWorkRefusal {
        SAConnectionCancellation.lostWorkRefusal(reportPendingForEditor: editor, reportPendingForWrites: writes,
                                                 retriesStatements: retries, settingUpSession: settingUp,
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

    /// The statements that set up a new session always run, and leave the report for the caller.
    func testTheStatementsThatSetUpANewSessionAlwaysRun() {
        XCTAssertEqual(refusal(retries: false, settingUp: true, leavesDataAlone: false), .none)
        XCTAssertEqual(refusal(retries: true, settingUp: true, leavesDataAlone: false), .none)
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
}
