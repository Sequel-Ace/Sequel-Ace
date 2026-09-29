//
//  SATableReloadRetryPolicyTests.swift
//  Unit Tests
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import XCTest

final class SATableReloadRetryPolicyTests: XCTestCase {

    /// Checks that a table may reload itself up to the limit and no further.
    func testAllowsUpToTheLimitAndThenRefuses() {
        let policy = SATableReloadRetryPolicy(limit: 3)

        XCTAssertTrue(policy.shouldReload(forTable: "orders"))
        XCTAssertTrue(policy.shouldReload(forTable: "orders"))
        XCTAssertTrue(policy.shouldReload(forTable: "orders"))
        XCTAssertFalse(policy.shouldReload(forTable: "orders"))
        XCTAssertFalse(policy.shouldReload(forTable: "orders"))
        XCTAssertEqual(policy.attemptCount(forTable: "orders"), 3)
    }

    /// Checks that the argument-free initialiser uses the default limit.
    func testDefaultLimitIsUsedWithoutArguments() {
        let policy = SATableReloadRetryPolicy()

        for _ in 0 ..< SATableReloadRetryPolicy.defaultLimit {
            XCTAssertTrue(policy.shouldReload(forTable: "orders"))
        }

        XCTAssertFalse(policy.shouldReload(forTable: "orders"))
    }

    /// Checks that each table brings its own budget.
    func testTablesAreCountedSeparately() {
        let policy = SATableReloadRetryPolicy(limit: 1)

        XCTAssertTrue(policy.shouldReload(forTable: "orders"))
        XCTAssertFalse(policy.shouldReload(forTable: "orders"))
        XCTAssertTrue(policy.shouldReload(forTable: "customers"))
        XCTAssertEqual(policy.attemptCount(forTable: "orders"), 1)
        XCTAssertEqual(policy.attemptCount(forTable: "customers"), 1)
    }

    /// Checks that a reset lets a table reload itself again.
    func testResetGivesOneTableItsBudgetBack() {
        let policy = SATableReloadRetryPolicy(limit: 2)

        XCTAssertTrue(policy.shouldReload(forTable: "orders"))
        XCTAssertTrue(policy.shouldReload(forTable: "orders"))
        XCTAssertFalse(policy.shouldReload(forTable: "orders"))

        policy.reset(forTable: "orders")

        XCTAssertEqual(policy.attemptCount(forTable: "orders"), 0)
        XCTAssertTrue(policy.shouldReload(forTable: "orders"))
    }

    /// Checks that resetting one table does not refill another's budget.
    func testResetOfOneTableLeavesTheOthersAlone() {
        let policy = SATableReloadRetryPolicy(limit: 1)

        XCTAssertTrue(policy.shouldReload(forTable: "orders"))
        XCTAssertTrue(policy.shouldReload(forTable: "customers"))

        policy.reset(forTable: "orders")

        XCTAssertTrue(policy.shouldReload(forTable: "orders"))
        XCTAssertFalse(policy.shouldReload(forTable: "customers"))
    }

    /// Checks that resetting everything refills every table's budget.
    func testResetAllClearsEveryTable() {
        let policy = SATableReloadRetryPolicy(limit: 1)

        XCTAssertTrue(policy.shouldReload(forTable: "orders"))
        XCTAssertTrue(policy.shouldReload(forTable: "customers"))

        policy.resetAll()

        XCTAssertTrue(policy.shouldReload(forTable: "orders"))
        XCTAssertTrue(policy.shouldReload(forTable: "customers"))
    }

    /// Checks that a load without a table name cannot reload endlessly either.
    func testUnnamedTablesShareOneBudget() {
        let policy = SATableReloadRetryPolicy(limit: 1)

        XCTAssertTrue(policy.shouldReload(forTable: nil))
        XCTAssertFalse(policy.shouldReload(forTable: nil))
        XCTAssertEqual(policy.attemptCount(forTable: nil), 1)
    }

    /// Checks that a limit of zero refuses every automatic reload.
    func testAZeroLimitRefusesEveryAutomaticReload() {
        let policy = SATableReloadRetryPolicy(limit: 0)

        XCTAssertFalse(policy.shouldReload(forTable: "orders"))
        XCTAssertEqual(policy.attemptCount(forTable: "orders"), 0)
    }

    /// Checks that a negative limit behaves like zero rather than allowing reloads.
    func testANegativeLimitIsTreatedAsZero() {
        let policy = SATableReloadRetryPolicy(limit: -5)

        XCTAssertFalse(policy.shouldReload(forTable: "orders"))
    }

    /// Checks that parallel askers together still get no more than the limit.
    func testConcurrentReloadsNeverExceedTheLimit() {
        let policy = SATableReloadRetryPolicy(limit: 10)
        let granted = SAReloadPolicyTestCounter()
        let group = DispatchGroup()

        for _ in 0 ..< 200 {
            DispatchQueue.global().async(group: group) {
                if policy.shouldReload(forTable: "orders") {
                    granted.increment()
                }
            }
        }

        XCTAssertEqual(group.wait(timeout: .now() + 10), .success)
        XCTAssertEqual(granted.value, 10)
        XCTAssertEqual(policy.attemptCount(forTable: "orders"), 10)
    }
}


final class SATableReloadCoordinatorTests: XCTestCase {

    /// Checks that a note is only taken once no load is still running.
    func testANoteWaitsForTheLoadAroundItToFinish() {
        let coordinator = SATableReloadCoordinator()

        coordinator.loadDidBegin()
        XCTAssertTrue(coordinator.noteFullReload(forTable: "orders"))
        XCTAssertFalse(coordinator.takeNoteWhenIdle())

        coordinator.loadDidEnd()

        XCTAssertTrue(coordinator.takeNoteWhenIdle())
        XCTAssertFalse(coordinator.takeNoteWhenIdle())
    }

    /// Checks that only the outermost of nested loads may take the note.
    func testNestedLoadsOnlyReleaseTheNoteAtTheOuterEnd() {
        let coordinator = SATableReloadCoordinator()

        coordinator.loadDidBegin()
        coordinator.loadDidBegin()
        XCTAssertTrue(coordinator.noteFullReload(forTable: "orders"))

        coordinator.loadDidEnd()
        XCTAssertFalse(coordinator.takeNoteWhenIdle())

        coordinator.loadDidEnd()
        XCTAssertTrue(coordinator.takeNoteWhenIdle())
    }

    /// Checks that a running reload task keeps the note for its own loop.
    func testAReloadTaskKeepsTheNoteForItself() {
        let coordinator = SATableReloadCoordinator()

        coordinator.reloadTaskDidBegin()
        XCTAssertTrue(coordinator.noteFullReload(forTable: "orders"))
        XCTAssertFalse(coordinator.takeNoteWhenIdle())

        XCTAssertTrue(coordinator.takeNoteForReloadTask())
        XCTAssertFalse(coordinator.takeNoteForReloadTask())
    }

    /// Checks that a note left beside the task survives the task ending.
    ///
    /// The task's own loop takes its notes as it goes, so one still waiting when
    /// the task ends came from a load running beside it and must not be lost.
    func testANoteLeftBesideTheTaskSurvivesItsEnd() {
        let coordinator = SATableReloadCoordinator()

        coordinator.reloadTaskDidBegin()
        XCTAssertTrue(coordinator.noteFullReload(forTable: "orders"))
        coordinator.reloadTaskDidEnd()

        XCTAssertTrue(coordinator.takeNoteWhenIdle())
        XCTAssertFalse(coordinator.takeNoteWhenIdle())
    }

    /// Checks that a task starting clears a note left over from before it.
    func testAStartingTaskClearsAnEarlierNote() {
        let coordinator = SATableReloadCoordinator()

        XCTAssertTrue(coordinator.noteFullReload(forTable: "orders"))
        coordinator.reloadTaskDidBegin()

        XCTAssertFalse(coordinator.takeNoteForReloadTask())
    }

    /// Checks that the budget bounds the reloads a table may run.
    ///
    /// Each note is taken before the next is left, the way a round of reloading
    /// takes the note it was started for.
    func testTheBudgetBoundsTheNotes() {
        let coordinator = SATableReloadCoordinator(policy: SATableReloadRetryPolicy(limit: 2))

        XCTAssertTrue(coordinator.noteFullReload(forTable: "orders"))
        XCTAssertTrue(coordinator.takeNoteWhenIdle())
        XCTAssertTrue(coordinator.noteFullReload(forTable: "orders"))
        XCTAssertTrue(coordinator.takeNoteWhenIdle())

        XCTAssertFalse(coordinator.noteFullReload(forTable: "orders"))
        XCTAssertEqual(coordinator.attemptCount(forTable: "orders"), 2)
    }

    /// Checks that a refused note leaves nothing behind for anyone to take.
    func testARefusedNoteStartsNoReload() {
        let coordinator = SATableReloadCoordinator(policy: SATableReloadRetryPolicy(limit: 0))

        XCTAssertFalse(coordinator.noteFullReload(forTable: "orders"))
        XCTAssertFalse(coordinator.takeNoteWhenIdle())
    }

    /// Checks that a reset refills the budget and forgets a pending note.
    func testResetAllForgetsBudgetAndNote() {
        let coordinator = SATableReloadCoordinator(policy: SATableReloadRetryPolicy(limit: 1))

        XCTAssertTrue(coordinator.noteFullReload(forTable: "orders"))
        coordinator.resetAll()

        XCTAssertFalse(coordinator.takeNoteWhenIdle())
        XCTAssertTrue(coordinator.noteFullReload(forTable: "orders"))
    }

    /// Checks that resetting one table refills only that table's budget.
    func testResetOfOneTableRefillsOnlyThatTable() {
        let coordinator = SATableReloadCoordinator(policy: SATableReloadRetryPolicy(limit: 1))

        XCTAssertTrue(coordinator.noteFullReload(forTable: "orders"))
        XCTAssertTrue(coordinator.takeNoteWhenIdle())
        XCTAssertTrue(coordinator.noteFullReload(forTable: "customers"))
        XCTAssertTrue(coordinator.takeNoteWhenIdle())

        coordinator.reset(forTable: "orders")

        XCTAssertTrue(coordinator.noteFullReload(forTable: "orders"))
        XCTAssertTrue(coordinator.takeNoteWhenIdle())
        XCTAssertFalse(coordinator.noteFullReload(forTable: "customers"))
    }

    /// Checks that a second load sharing a waiting note does not spend from the budget.
    func testASharedNoteIsChargedOnlyOnce() {
        let coordinator = SATableReloadCoordinator(policy: SATableReloadRetryPolicy(limit: 2))

        XCTAssertTrue(coordinator.noteFullReload(forTable: "orders"))
        XCTAssertTrue(coordinator.noteFullReload(forTable: "orders"))
        XCTAssertEqual(coordinator.attemptCount(forTable: "orders"), 1)

        XCTAssertTrue(coordinator.takeNoteWhenIdle())

        XCTAssertTrue(coordinator.noteFullReload(forTable: "orders"))
        XCTAssertEqual(coordinator.attemptCount(forTable: "orders"), 2)
        XCTAssertTrue(coordinator.takeNoteWhenIdle())
        XCTAssertFalse(coordinator.noteFullReload(forTable: "orders"))
    }

    /// Checks that an unbalanced end does not push the load count below zero.
    func testAnExtraLoadEndDoesNotUnbalanceTheCount() {
        let coordinator = SATableReloadCoordinator()

        coordinator.loadDidEnd()
        coordinator.loadDidBegin()
        XCTAssertTrue(coordinator.noteFullReload(forTable: "orders"))
        XCTAssertFalse(coordinator.takeNoteWhenIdle())

        coordinator.loadDidEnd()
        XCTAssertTrue(coordinator.takeNoteWhenIdle())
    }
}

/// A counter several queues may raise, so the concurrency test can total the
/// reloads the policy granted without racing on the total itself.
private final class SAReloadPolicyTestCounter {
    private let lock = NSLock()
    private var count = 0

    /// The total the queues have counted so far.
    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    /// Raises the counter by one.
    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }
}
