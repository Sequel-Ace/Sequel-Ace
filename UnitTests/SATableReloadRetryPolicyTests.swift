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
