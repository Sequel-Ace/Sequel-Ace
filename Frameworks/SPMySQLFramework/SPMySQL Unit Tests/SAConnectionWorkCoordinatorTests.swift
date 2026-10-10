//
//  SAConnectionWorkCoordinatorTests.swift
//  SPMySQLFramework
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//
//  More info at <https://github.com/Sequel-Ace/Sequel-Ace>
//

import XCTest
@testable import SPMySQL

final class SAConnectionWorkCoordinatorTests: XCTestCase {
    private let coordinator = SAConnectionWorkCoordinator()

    /// Waits for the work the way the application's wait sheet does.
    ///
    /// The coordinator gives up on work that is still running when the interface's wait returns,
    /// and that is only 0.15 s after the hand-off. Trivial work can exceed it on a loaded machine -
    /// starting the worker thread alone can - so a test that asks for the work's result says here
    /// that it waits for it. A test about work being given up on keeps the default instead.
    private static let waitingForTheWork: (_ isFinished: @escaping () -> Bool) -> Void = { isFinished in
        while !isFinished() {
            usleep(1_000)
        }
    }

    /// Runs work with a fixed operation stamp and an interface that never waits.
    private func run(_ work: @escaping () -> Any?,
                     stamp: @escaping () -> UInt = { 1 },
                     whenSlow: (_ isFinished: @escaping () -> Bool) -> Void = { _ in },
                     whenAbandonedWorkFinishes: @escaping (_ abandonedAtStamp: UInt) -> Void = { _ in }) -> SAConnectionWorkOutcome {
        coordinator.run(work, operationStamp: stamp, whenSlow: whenSlow, whenAbandonedWorkFinishes: whenAbandonedWorkFinishes)
    }

    /// Quick work is never handed to the interface.
    func testQuickWorkIsNeverHandedToTheInterface() {
        var interfaceWasAsked = false
        let outcome = run({ "done" }, whenSlow: { _ in interfaceWasAsked = true })

        XCTAssertTrue(outcome.finished)
        XCTAssertEqual(outcome.result as? String, "done")
        XCTAssertFalse(interfaceWasAsked)
    }

    /// Work runs away from the calling thread.
    func testWorkRunsAwayFromTheCallingThread() {
        let callingThread = Thread.current
        let outcome = run({ Thread.current == callingThread }, whenSlow: Self.waitingForTheWork)

        XCTAssertEqual(outcome.result as? Bool, false)
    }

    /// Slow work is waited for by the interface.
    func testSlowWorkIsWaitedForByTheInterface() {
        let outcome = run({
            Thread.sleep(forTimeInterval: 0.4)
            return "late"
        }, whenSlow: { isFinished in
            while !isFinished() {
                usleep(5_000)
            }
        })

        XCTAssertTrue(outcome.finished)
        XCTAssertEqual(outcome.result as? String, "late")
    }

    /// An interface that stops waiting gets no result.
    func testAnInterfaceThatStopsWaitingGetsNoResult() {
        let workStarted = DispatchSemaphore(value: 0)
        let workMayFinish = DispatchSemaphore(value: 0)
        let lateCompletionReported = DispatchSemaphore(value: 0)

        let outcome = run({
            workStarted.signal()
            workMayFinish.wait()
            return "too late"
        }, whenAbandonedWorkFinishes: { abandonedAtStamp in
            XCTAssertEqual(abandonedAtStamp, 1)
            lateCompletionReported.signal()
        })

        XCTAssertFalse(outcome.finished)
        XCTAssertTrue(outcome.wasAbandoned)
        XCTAssertNil(outcome.result)

        XCTAssertEqual(workStarted.wait(timeout: .now() + 2), .success)
        workMayFinish.signal()

        // Nothing else happened on the connection, so the work that nobody waited for says so.
        XCTAssertEqual(lateCompletionReported.wait(timeout: .now() + 2), .success)
        XCTAssertNil(outcome.result)
    }

    /// A late completion leaves a newer operation alone.
    func testALateCompletionLeavesANewerOperationAlone() throws {
        var currentOperation: UInt = 1
        let operationLock = NSLock()
        let stamp: () -> UInt = {
            operationLock.lock()
            defer { operationLock.unlock() }
            return currentOperation
        }
        let workStarted = DispatchSemaphore(value: 0)
        let workMayFinish = DispatchSemaphore(value: 0)
        let workFinished = DispatchSemaphore(value: 0)
        let lateCompletionLock = NSLock()
        var lateCompletionCalled = false
        var abandonedWorkThread: Thread?

        _ = run({
            abandonedWorkThread = Thread.current
            workStarted.signal()
            workMayFinish.wait()
            return nil
        }, stamp: stamp, whenAbandonedWorkFinishes: { _ in
            lateCompletionLock.lock()
            lateCompletionCalled = true
            lateCompletionLock.unlock()
        })
        XCTAssertEqual(workStarted.wait(timeout: .now() + 2), .success)

        // Another operation takes over the connection before the abandoned work finishes.
        operationLock.lock()
        currentOperation = 2
        operationLock.unlock()

        _ = run({
            workFinished.signal()
            return nil
        }, stamp: stamp)
        workMayFinish.signal()
        XCTAssertEqual(workFinished.wait(timeout: .now() + 2), .success)

        // The newer operation runs on a thread of its own. The abandoned work's thread, which was
        // given up on, ends once that work has decided whether to report its completion.
        let thread = try XCTUnwrap(abandonedWorkThread)
        let deadline = Date().addingTimeInterval(3)
        while !thread.isFinished && Date() < deadline {
            usleep(5_000)
        }
        XCTAssertTrue(thread.isFinished)

        lateCompletionLock.lock()
        defer { lateCompletionLock.unlock() }
        XCTAssertFalse(lateCompletionCalled)
    }

    /// Queued work that was abandoned never acts as if it were still wanted.
    func testQueuedWorkThatWasAbandonedNeverActsAsIfItWereStillWanted() {
        let firstWorkMayFinish = DispatchSemaphore(value: 0)
        let queuedWorkRan = DispatchSemaphore(value: 0)
        var queuedWorkSawItselfAbandoned = false

        // A nested wait queues a second piece of work behind the first on the same thread, and
        // gives up on it while it is still queued.
        _ = run({
            firstWorkMayFinish.wait()
            return nil
        }, whenSlow: { _ in
            _ = self.run({
                queuedWorkSawItselfAbandoned = SAConnectionWorkCoordinator.currentWorkHasBeenAbandoned
                queuedWorkRan.signal()
                return nil
            })
        })

        firstWorkMayFinish.signal()

        // The thread it was queued on has been given up, so the work either never runs at all or
        // runs knowing that nobody wants it any more. Either way it must not act as if it were.
        if queuedWorkRan.wait(timeout: .now() + 1) == .success {
            XCTAssertTrue(queuedWorkSawItselfAbandoned)
        }
    }

    /// Work is not abandoned on the caller's thread.
    func testWorkIsNotAbandonedOnTheCallersThread() {
        XCTAssertFalse(SAConnectionWorkCoordinator.currentWorkHasBeenAbandoned)
    }

    /// Work that was abandoned does not hold up what follows.
    func testWorkThatWasAbandonedDoesNotHoldUpWhatFollows() {
        let stuckWorkMayFinish = DispatchSemaphore(value: 0)

        _ = run({
            stuckWorkMayFinish.wait()
            return nil
        })

        // The thread the abandoned work sits on must not be the one the next work waits for.
        let outcome = run({ "next" }, whenSlow: Self.waitingForTheWork)

        XCTAssertTrue(outcome.finished)
        XCTAssertEqual(outcome.result as? String, "next")

        stuckWorkMayFinish.signal()
    }

    /// Work the user stops never counts as finished, even when it returns before the waiting ends.
    func testWorkStoppedByTheUserNeverCountsAsFinished() {
        let workReturned = DispatchSemaphore(value: 0)
        var waitEndedAtOnce = false
        let outcome = run({
            // Stands in for work that notices the stop and returns early without saying why.
            while !Thread.current.isCancelled {
                usleep(1_000)
            }
            workReturned.signal()
            return "stopped early"
        }, whenSlow: { isFinished in
            coordinator.abandonWorkForUserStop()
            waitEndedAtOnce = isFinished()

            // The work returns before the interface is done with its wait.
            XCTAssertEqual(workReturned.wait(timeout: .now() + 2), .success)
        })

        XCTAssertTrue(waitEndedAtOnce)
        XCTAssertFalse(outcome.finished)
        XCTAssertTrue(outcome.wasAbandoned)
        XCTAssertNil(outcome.result)
    }

    /// Runs work that sends one statement in each of the given transaction states, then waits until
    /// the user stops it, and reports how it used the session.
    /// - Parameter transactionStates: Whether a transaction is open before each statement.
    /// - Returns: The work's outcome once the user stopped it.
    private func stoppedWork(sendingWithOpenTransaction transactionStates: [Bool]) -> SAConnectionWorkOutcome {
        let statementsSent = DispatchSemaphore(value: 0)
        return run({
            for isOpen in transactionStates {
                _ = SAConnectionWorkCoordinator.currentWorkMaySend(sessionHasOpenTransaction: isOpen, statementMayChangeData: false)
            }
            statementsSent.signal()
            while !Thread.current.isCancelled {
                usleep(1_000)
            }
            return nil
        }, whenSlow: { _ in
            XCTAssertEqual(statementsSent.wait(timeout: .now() + 2), .success)
            coordinator.abandonWorkForUserStop()
        })
    }

    /// Work that sent nothing before it was stopped left the session untouched.
    func testWorkStoppedBeforeItSentAnythingLeftTheSessionUntouched() {
        XCTAssertEqual(stoppedWork(sendingWithOpenTransaction: []).sessionUse, .untouched)
    }

    /// Stopped work reports the transaction that was open before its first statement.
    func testStoppedWorkReportsTheTransactionBeforeItsFirstStatement() {
        XCTAssertEqual(stoppedWork(sendingWithOpenTransaction: [true]).sessionUse, .insideTransaction)
        XCTAssertEqual(stoppedWork(sendingWithOpenTransaction: [false]).sessionUse, .outsideTransaction)
    }

    /// A transaction the work opened with its first statement does not count as one it found.
    func testATransactionTheWorkOpenedItselfDoesNotCountAsOneItFound() {
        XCTAssertEqual(stoppedWork(sendingWithOpenTransaction: [false, true]).sessionUse, .outsideTransaction)
    }

    /// Work that was stopped may send nothing more, and its use of the session stays as it was.
    func testStoppedWorkMaySendNothingMore() {
        let workWasStopped = DispatchSemaphore(value: 0)
        let askedAfterTheStop = DispatchSemaphore(value: 0)
        var maySendAfterTheStop = true

        let outcome = run({
            workWasStopped.wait()
            maySendAfterTheStop = SAConnectionWorkCoordinator.currentWorkMaySend(sessionHasOpenTransaction: true, statementMayChangeData: false)
            askedAfterTheStop.signal()
            return nil
        }, whenSlow: { _ in
            coordinator.abandonWorkForUserStop()
            workWasStopped.signal()
        })

        XCTAssertEqual(askedAfterTheStop.wait(timeout: .now() + 2), .success)
        XCTAssertFalse(maySendAfterTheStop)
        XCTAssertEqual(outcome.sessionUse, .untouched)
    }

    /// Statements from outside the application stay marked as such on the worker, and only those.
    func testWorkFromOutsideTheApplicationStaysMarkedOnTheWorker() {
        var markedOnWorker: Bool?
        SAOutsideStatements.run {
            XCTAssertTrue(SAOutsideStatements.areRunningOnCurrentThread)
            markedOnWorker = run({ SAOutsideStatements.areRunningOnCurrentThread }).result as? Bool
        }
        XCTAssertEqual(markedOnWorker, true)
        XCTAssertEqual(run({ SAOutsideStatements.areRunningOnCurrentThread }).result as? Bool, false)
        XCTAssertFalse(SAOutsideStatements.areRunningOnCurrentThread)
    }

    /// The connection's own upkeep stays marked as such on the worker, and so does work that is both.
    func testUpkeepStaysMarkedOnTheWorker() {
        var upkeepOnWorker: Bool?
        var bothOnWorker: [Bool]?
        SAConnectionUpkeepStatements.run {
            XCTAssertTrue(SAConnectionUpkeepStatements.areRunningOnCurrentThread)
            upkeepOnWorker = run({ SAConnectionUpkeepStatements.areRunningOnCurrentThread }).result as? Bool
            SAOutsideStatements.run {
                bothOnWorker = run({
                    [SAConnectionUpkeepStatements.areRunningOnCurrentThread, SAOutsideStatements.areRunningOnCurrentThread]
                }).result as? [Bool]
            }
        }
        XCTAssertEqual(upkeepOnWorker, true)
        XCTAssertEqual(bothOnWorker, [true, true])
        XCTAssertEqual(run({ SAConnectionUpkeepStatements.areRunningOnCurrentThread }).result as? Bool, false)
        XCTAssertFalse(SAConnectionUpkeepStatements.areRunningOnCurrentThread)
    }

    /// The upkeep mark survives nested runs, ends with the outermost one, and is not the outside mark.
    func testTheUpkeepMarkEndsWithTheOutermostRun() {
        SAConnectionUpkeepStatements.run {
            SAConnectionUpkeepStatements.run {}
            XCTAssertTrue(SAConnectionUpkeepStatements.areRunningOnCurrentThread)
            XCTAssertFalse(SAOutsideStatements.areRunningOnCurrentThread)
        }
        XCTAssertFalse(SAConnectionUpkeepStatements.areRunningOnCurrentThread)
    }

    /// The mark survives nested runs and ends with the outermost one.
    func testTheOutsideMarkEndsWithTheOutermostRun() {
        SAOutsideStatements.run {
            SAOutsideStatements.run {}
            XCTAssertTrue(SAOutsideStatements.areRunningOnCurrentThread)
        }
        XCTAssertFalse(SAOutsideStatements.areRunningOnCurrentThread)
    }

    /// Work that no coordinator runs may always send and never records a use of the session.
    func testWorkOutsideACoordinatorMayAlwaysSend() {
        XCTAssertTrue(SAConnectionWorkCoordinator.currentWorkMaySend(sessionHasOpenTransaction: false, statementMayChangeData: false))
        XCTAssertEqual(SAConnectionWorkCoordinator.currentWorkSessionUse, .untouched)
    }

    /// The next piece of work still runs after a cancellation.
    func testTheNextPieceOfWorkStillRunsAfterACancellation() {
        coordinator.cancel()

        let outcome = run({ 42 })

        XCTAssertTrue(outcome.finished)
        XCTAssertEqual(outcome.result as? Int, 42)
    }

    /// Work asked for away from the main thread runs where it was asked for.
    func testWorkAwayFromTheMainThreadIsNotHandedOver() {
        XCTAssertFalse(SAConnectionWorkCoordinator.workShouldRunOffMainThread(
            isMainThread: false, delegateShowsTheWait: true, threadIsSettingUpTheSession: false))
    }

    /// Without a delegate there is nobody to show the wait, so there is nothing to gain.
    func testWorkIsNotHandedOverWithNobodyToShowTheWait() {
        XCTAssertFalse(SAConnectionWorkCoordinator.workShouldRunOffMainThread(
            isMainThread: true, delegateShowsTheWait: false, threadIsSettingUpTheSession: false))
    }

    /// Main-thread work that would wait for a server is handed over.
    func testMainThreadWorkIsHandedOver() {
        XCTAssertTrue(SAConnectionWorkCoordinator.workShouldRunOffMainThread(
            isMainThread: true, delegateShowsTheWait: true, threadIsSettingUpTheSession: false))
    }

    /// The thread setting the new session up keeps its own queries.
    ///
    /// It holds the session until its setup is done, so a setup query handed to another thread
    /// would wait there for a session held by the thread waiting for that query.
    func testTheThreadSettingUpTheSessionKeepsItsOwnQueries() {
        XCTAssertFalse(SAConnectionWorkCoordinator.workShouldRunOffMainThread(
            isMainThread: true, delegateShowsTheWait: true, threadIsSettingUpTheSession: true),
                       "a main-thread reconnect's setup query must not be handed over")
        XCTAssertFalse(SAConnectionWorkCoordinator.workShouldRunOffMainThread(
            isMainThread: false, delegateShowsTheWait: true, threadIsSettingUpTheSession: true))
    }


    /// Work that sent something able to change data says so, so that giving up on it is not
    /// reported as though nothing had happened.
    ///
    /// Stopping the wait does not take back what was sent: the statement goes on running and the
    /// server may carry it out. A caller told only that its query was cancelled offers to do it
    /// again, which for a row save means inserting it twice.
    func testWorkRemembersHavingSentSomethingThatMayHaveChangedData() {
        let outcome = SAConnectionWorkOutcome()
        XCTAssertFalse(outcome.sentSomethingThatMayHaveChangedData, "nothing has been sent yet")

        XCTAssertTrue(outcome.beginSessionUse(sessionHasOpenTransaction: false,
                                              statementMayChangeData: false))
        XCTAssertFalse(outcome.sentSomethingThatMayHaveChangedData,
                       "a statement that only reads leaves nothing behind")

        XCTAssertTrue(outcome.beginSessionUse(sessionHasOpenTransaction: false,
                                              statementMayChangeData: true))
        XCTAssertTrue(outcome.sentSomethingThatMayHaveChangedData)

        XCTAssertTrue(outcome.beginSessionUse(sessionHasOpenTransaction: false,
                                              statementMayChangeData: false))
        XCTAssertTrue(outcome.sentSomethingThatMayHaveChangedData,
                      "and a read after it does not take that back")
    }

    // MARK: - The hand-off itself, through the public query path

    /// Stands in for the application: answers the lost-connection question on the main thread,
    /// runs the test's own work while being asked, and shows the wait for connection work, which
    /// is what makes the connection hand a main-thread query to its worker at all.
    private final class WaitingDelegate: NSObject {
        var whileBeingAsked: (() -> Void)?
        private(set) var timesAsked = 0

        @objc func connectionLost(_ connection: Any) -> SPMySQLConnectionLostDecision {
            timesAsked += 1
            whileBeingAsked?()
            return SPMySQLConnectionLostDisconnect
        }

        @objc(connection:waitForConnectionWorkUntilFinished:)
        func connection(_ connection: Any, waitForConnectionWorkUntilFinished isFinished: @escaping () -> Bool) {
            while !isFinished() {
                RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
            }
        }
    }

    /// Verifies a main-thread query is refused before it is handed to the worker while a question
    /// about the connection is still out to the main thread.
    ///
    /// The lease turns a main-thread caller away, but the hand-off happens first and the session
    /// is then asked for on the worker, where that refusal no longer recognises the caller. This
    /// drives the whole chain through the public `queryString:`.
    ///
    /// The thread that asks holds the session while it asks, as a reconnect does - which is what
    /// makes the two sides cross. Without the refusal the worker waits in the lease for a session
    /// the asking thread is holding, the main thread waits for the worker inside the delegate's
    /// own wait, and the answer that would release the session cannot arrive until the main thread
    /// returns from being asked. Neither side moves, and the test hangs rather than failing an
    /// assertion. Holding the session is therefore not decoration here: without it the worker
    /// would take the free lease at once and nothing would be reproduced.
    func testAMainThreadQueryIsRefusedBeforeItIsHandedToTheWorkerWhileTheQuestionIsOpen() throws {
        let connection = SPMySQLConnection()
        connection.useKeepAlive = false
        defer {
            connection.setValue(SPMySQLDisconnected.rawValue, forKey: "state")
            connection.disconnect()
        }
        let delegate = WaitingDelegate()
        connection.perform(NSSelectorFromString("setDelegate:"), with: delegate)
        XCTAssertTrue(connection.value(forKey: "delegateSupportsConnectionCheckProgress") as? Bool ?? false,
                      "the connection only hands work over when the delegate shows the wait")

        // What the main thread finds when it comes back in while the question is open.
        var theQueryCameBackEmpty: Bool?
        var theConnectionReportedAnError: Bool?
        var itWasNotTakenForAUserStop: Bool?
        delegate.whileBeingAsked = {
            theQueryCameBackEmpty = connection.queryString("UPDATE t SET a = 1") == nil
            theConnectionReportedAnError = connection.queryErrored()
            itWasNotTakenForAUserStop = !connection.lastQueryWasCancelled
        }

        // The question goes out the way the connection puts it, from a worker.
        let theQuestionCameBack = expectation(description: "the question was answered")
        let theDecision = NSSelectorFromString("_delegateDecisionForLostConnection")
        XCTAssertTrue(connection.responds(to: theDecision))
        let access = connection.value(forKey: "sessionAccess") as? SAConnectionSessionAccess
        XCTAssertNotNil(access, "the lease is what the two sides contend for")
        Thread.detachNewThread {
            // Asked while holding the session, the way the reconnect that asks this question does.
            _ = access?.performQuery {
                connection.perform(theDecision)
                return nil
            }
            theQuestionCameBack.fulfill()
        }

        // The hand-off waits on this thread's run loop, so it has to be run for the question to
        // arrive - which is what the application's modal loop does.
        let giveUp = Date(timeIntervalSinceNow: 20)
        while delegate.timesAsked == 0 && Date() < giveUp {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.02))
        }

        XCTAssertEqual(delegate.timesAsked, 1, "the question reached the delegate")
        XCTAssertEqual(theQueryCameBackEmpty, true, "the query was turned away")
        XCTAssertEqual(theConnectionReportedAnError, true,
                       "and said so, rather than looking like a statement that changed nothing")
        XCTAssertEqual(itWasNotTakenForAUserStop, true,
                       "a refusal is not a query the user stopped, which callers stay quiet about")

        wait(for: [theQuestionCameBack], timeout: 20)
    }

    /// Verifies the policy itself: only the thread that answers is turned away, and only while a
    /// question is out.
    func testOnlyTheAnsweringThreadIsTurnedAwayAndOnlyWhileAQuestionIsOut() {
        XCTAssertTrue(SAConnectionWorkCoordinator.mainThreadWorkMustBeRefused(
            isMainThread: true, aQuestionAwaitsTheMainThread: true))
        XCTAssertFalse(SAConnectionWorkCoordinator.mainThreadWorkMustBeRefused(
            isMainThread: true, aQuestionAwaitsTheMainThread: false),
            "with no question out the main thread hands its work over as before")
        XCTAssertFalse(SAConnectionWorkCoordinator.mainThreadWorkMustBeRefused(
            isMainThread: false, aQuestionAwaitsTheMainThread: true),
            "a worker does not answer the question, so it may wait for the session")
    }
}

/// Hands work over the way the connection does.
@objc private protocol SAWorkHandOff {
    @objc(_runWorkKeepingInterfaceAlive:)
    func runWorkKeepingInterfaceAlive(_ work: @escaping () -> Any?) -> Any?
}

/// A refusal belongs to the call it was about.
final class SARefusalMarkerTests: XCTestCase {

    /// The mark is read by the statement path alone, and the connection's other work is turned
    /// away by the same gate without reading it. Left standing, such a mark would be read by the
    /// next statement on that thread and reported as that statement's own - a statement that was
    /// never refused would say it was, and the cancellation the caller had recorded for it would
    /// be cleared along the way.
    func testWorkHandedOverForgetsARefusalThatWasNotAboutIt() throws {
        let connection = SPMySQLConnection()
        connection.useKeepAlive = false
        defer { connection.disconnect() }
        let access = try XCTUnwrap(connection.value(forKey: "sessionAccess") as? SAConnectionSessionAccess)

        // What an earlier call that was turned away leaves behind on this thread.
        access.noteThisThreadsCallWasRefused()

        var theWorkRan = false
        _ = unsafeBitCast(connection, to: SAWorkHandOff.self).runWorkKeepingInterfaceAlive {
            theWorkRan = true
            return nil
        }

        XCTAssertTrue(theWorkRan, "with nobody to show the wait the work runs where it was asked for")
        XCTAssertFalse(access.takeTheRefusalOfThisThreadsLastCall(),
                       "and the mark from before is gone, so it cannot be read as this work's")
    }
}
