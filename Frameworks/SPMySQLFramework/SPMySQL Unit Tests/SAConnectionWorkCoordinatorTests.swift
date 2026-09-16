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
        let outcome = run({ Thread.current == callingThread })

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
    func testALateCompletionLeavesANewerOperationAlone() {
        var currentOperation: UInt = 1
        let operationLock = NSLock()
        let stamp: () -> UInt = {
            operationLock.lock()
            defer { operationLock.unlock() }
            return currentOperation
        }
        let workMayFinish = DispatchSemaphore(value: 0)
        let workFinished = DispatchSemaphore(value: 0)
        var lateCompletionCalled = false

        _ = run({
            workMayFinish.wait()
            return nil
        }, stamp: stamp, whenAbandonedWorkFinishes: { _ in
            lateCompletionCalled = true
        })

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
        Thread.sleep(forTimeInterval: 0.2)

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
        let outcome = run({ "next" })

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

    /// The next piece of work still runs after a cancellation.
    func testTheNextPieceOfWorkStillRunsAfterACancellation() {
        coordinator.cancel()

        let outcome = run({ 42 })

        XCTAssertTrue(outcome.finished)
        XCTAssertEqual(outcome.result as? Int, 42)
    }
}
