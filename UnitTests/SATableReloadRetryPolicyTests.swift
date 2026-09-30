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


/// Drives the coordinator through the call sequences `SPTableContent` uses, so
/// the bookkeeping is covered as a whole and not only call by call.
///
/// The controller reports a load with `loadDidBegin`/`loadDidEnd` around
/// `-loadTableValues` and again around `-loadTable:`, notes a mismatch with
/// `noteFullReload`, and asks `takeNoteWhenIdle` at the end of both. A reload
/// task brackets its rounds with `reloadTaskDidBegin`/`reloadTaskDidEnd` and
/// takes its own notes with `takeNoteForReloadTask`.
final class SATableReloadCoordinatorSequenceTests: XCTestCase {

    /// A load of values, as `-loadTableValues` reports it.
    ///
    /// - Parameters:
    ///   - coordinator: The coordinator to report to.
    ///   - mismatch: Whether the column list disagreed with the result.
    ///   - table: The table being loaded.
    /// - Returns: `true` when the mismatch was refused, which is where the
    ///   controller reports that it is giving up.
    @discardableResult
    private func loadValues(_ coordinator: SATableReloadCoordinator,
                            mismatch: Bool,
                            table: String = "orders") -> Bool {
        coordinator.loadDidBegin()
        var gaveUp = false
        if mismatch {
            gaveUp = !coordinator.noteFullReload(forTable: table)
        } else {
            coordinator.reset(forTable: table)
        }
        coordinator.loadDidEnd()
        return gaveUp
    }

    /// A load of a table, as `-loadTable:` wraps `-loadTableValues`.
    @discardableResult
    private func loadTable(_ coordinator: SATableReloadCoordinator,
                           mismatch: Bool,
                           startsReload: inout Bool) -> Bool {
        coordinator.loadDidBegin()
        let gaveUp = loadValues(coordinator, mismatch: mismatch)
        // -loadTableValues asks first and must not take the note here.
        XCTAssertFalse(coordinator.takeNoteWhenIdle(), "the load around it is still running")
        coordinator.loadDidEnd()
        startsReload = coordinator.takeNoteWhenIdle()
        return gaveUp
    }

    /// Runs the reload task's loop, returning how many rounds it loaded.
    private func runReloadTask(_ coordinator: SATableReloadCoordinator,
                               mismatchPerRound: Bool) -> (rounds: Int, gaveUp: Bool) {
        coordinator.reloadTaskDidBegin()
        var rounds = 0
        var gaveUp = false
        var again = true
        while again {
            rounds += 1
            coordinator.loadDidBegin()
            if loadValues(coordinator, mismatch: mismatchPerRound) { gaveUp = true }
            coordinator.loadDidEnd()
            again = coordinator.takeNoteForReloadTask()
            XCTAssertLessThan(rounds, 20, "the task must not loop without end")
        }
        coordinator.reloadTaskDidEnd()
        return (rounds, gaveUp)
    }

    /// Checks that a table whose columns never match reloads three times and stops.
    ///
    /// This is the sequence the endless reload came from: the first load notes a
    /// reload, the task runs the rounds, and the fourth mismatch is refused.
    func testAPersistentMismatchStopsAfterThreeReloads() {
        let coordinator = SATableReloadCoordinator()

        var startsReload = false
        XCTAssertFalse(loadTable(coordinator, mismatch: true, startsReload: &startsReload))
        XCTAssertTrue(startsReload, "the load is through, so its reload may start")

        let (rounds, gaveUp) = runReloadTask(coordinator, mismatchPerRound: true)

        XCTAssertEqual(rounds, 3, "one round per remaining attempt, then the refusal")
        XCTAssertTrue(gaveUp, "the last round reports that it is giving up")
        XCTAssertEqual(coordinator.attemptCount(forTable: "orders"), 3)
        XCTAssertFalse(coordinator.takeNoteWhenIdle(), "nothing is left to start")
    }

    /// Checks that a reload whose columns match ends the rounds and clears the budget.
    func testAMatchingReloadEndsTheRoundsAndRefillsTheBudget() {
        let coordinator = SATableReloadCoordinator()

        var startsReload = false
        loadTable(coordinator, mismatch: true, startsReload: &startsReload)
        XCTAssertTrue(startsReload)

        let (rounds, gaveUp) = runReloadTask(coordinator, mismatchPerRound: false)

        XCTAssertEqual(rounds, 1, "a load that matches asks for nothing further")
        XCTAssertFalse(gaveUp)
        XCTAssertEqual(coordinator.attemptCount(forTable: "orders"), 0, "the budget is back")
        XCTAssertFalse(coordinator.takeNoteWhenIdle())
    }

    /// Checks that a value-only load - filtering, paging, sorting - starts its own reload.
    func testAValueOnlyLoadStartsItsOwnReload() {
        let coordinator = SATableReloadCoordinator()

        loadValues(coordinator, mismatch: true)

        XCTAssertTrue(coordinator.takeNoteWhenIdle(), "no -loadTable: around it, so it starts one")
    }

    /// Checks that a value-only load beside a reload task keeps its note until the task is through.
    func testANoteFromBesideTheTaskIsStartedWhenTheTaskEnds() {
        let coordinator = SATableReloadCoordinator()

        coordinator.reloadTaskDidBegin()
        loadValues(coordinator, mismatch: true)
        XCTAssertFalse(coordinator.takeNoteWhenIdle(), "the task is still running")

        coordinator.reloadTaskDidEnd()

        XCTAssertTrue(coordinator.takeNoteWhenIdle(), "the task is through, so the note is started")
    }

    /// Checks that a user-triggered reload gives a table that gave up its attempts back.
    func testAReloadAskedForFromOutsideRefillsTheBudget() {
        let coordinator = SATableReloadCoordinator()

        var startsReload = false
        loadTable(coordinator, mismatch: true, startsReload: &startsReload)
        let first = runReloadTask(coordinator, mismatchPerRound: true)
        XCTAssertTrue(first.gaveUp)

        // -reloadTable: resets before starting its own task.
        coordinator.reset(forTable: "orders")
        let second = runReloadTask(coordinator, mismatchPerRound: true)

        XCTAssertEqual(second.rounds, 4, "three fresh attempts, then the round that refuses")
        XCTAssertTrue(second.gaveUp)
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
