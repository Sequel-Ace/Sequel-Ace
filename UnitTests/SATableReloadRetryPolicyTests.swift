//
//  SATableReloadRetryPolicyTests.swift
//  Unit Tests
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import XCTest

final class SATableReloadRetryPolicyTests: XCTestCase {

    func testAllowsUpToTheLimitAndThenRefuses() {
        let policy = SATableReloadRetryPolicy(limit: 3)

        XCTAssertTrue(policy.shouldReload(forTable: "orders"))
        XCTAssertTrue(policy.shouldReload(forTable: "orders"))
        XCTAssertTrue(policy.shouldReload(forTable: "orders"))
        XCTAssertFalse(policy.shouldReload(forTable: "orders"))
        XCTAssertFalse(policy.shouldReload(forTable: "orders"))
        XCTAssertEqual(policy.attemptCount(forTable: "orders"), 3)
    }

    func testDefaultLimitIsUsedWithoutArguments() {
        let policy = SATableReloadRetryPolicy()

        for _ in 0 ..< SATableReloadRetryPolicy.defaultLimit {
            XCTAssertTrue(policy.shouldReload(forTable: "orders"))
        }

        XCTAssertFalse(policy.shouldReload(forTable: "orders"))
    }

    func testTablesAreCountedSeparately() {
        let policy = SATableReloadRetryPolicy(limit: 1)

        XCTAssertTrue(policy.shouldReload(forTable: "orders"))
        XCTAssertFalse(policy.shouldReload(forTable: "orders"))
        XCTAssertTrue(policy.shouldReload(forTable: "customers"))
        XCTAssertEqual(policy.attemptCount(forTable: "orders"), 1)
        XCTAssertEqual(policy.attemptCount(forTable: "customers"), 1)
    }

    func testResetGivesOneTableItsBudgetBack() {
        let policy = SATableReloadRetryPolicy(limit: 2)

        XCTAssertTrue(policy.shouldReload(forTable: "orders"))
        XCTAssertTrue(policy.shouldReload(forTable: "orders"))
        XCTAssertFalse(policy.shouldReload(forTable: "orders"))

        policy.reset(forTable: "orders")

        XCTAssertEqual(policy.attemptCount(forTable: "orders"), 0)
        XCTAssertTrue(policy.shouldReload(forTable: "orders"))
    }

    func testResetOfOneTableLeavesTheOthersAlone() {
        let policy = SATableReloadRetryPolicy(limit: 1)

        XCTAssertTrue(policy.shouldReload(forTable: "orders"))
        XCTAssertTrue(policy.shouldReload(forTable: "customers"))

        policy.reset(forTable: "orders")

        XCTAssertTrue(policy.shouldReload(forTable: "orders"))
        XCTAssertFalse(policy.shouldReload(forTable: "customers"))
    }

    func testResetAllClearsEveryTable() {
        let policy = SATableReloadRetryPolicy(limit: 1)

        XCTAssertTrue(policy.shouldReload(forTable: "orders"))
        XCTAssertTrue(policy.shouldReload(forTable: "customers"))

        policy.resetAll()

        XCTAssertTrue(policy.shouldReload(forTable: "orders"))
        XCTAssertTrue(policy.shouldReload(forTable: "customers"))
    }

    func testUnnamedTablesShareOneBudget() {
        let policy = SATableReloadRetryPolicy(limit: 1)

        XCTAssertTrue(policy.shouldReload(forTable: nil))
        XCTAssertFalse(policy.shouldReload(forTable: nil))
        XCTAssertEqual(policy.attemptCount(forTable: nil), 1)
    }

    func testAZeroLimitRefusesEveryAutomaticReload() {
        let policy = SATableReloadRetryPolicy(limit: 0)

        XCTAssertFalse(policy.shouldReload(forTable: "orders"))
        XCTAssertEqual(policy.attemptCount(forTable: "orders"), 0)
    }

    func testANegativeLimitIsTreatedAsZero() {
        let policy = SATableReloadRetryPolicy(limit: -5)

        XCTAssertFalse(policy.shouldReload(forTable: "orders"))
    }

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

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }
}
