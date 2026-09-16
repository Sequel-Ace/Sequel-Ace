//
//  SAConnectionCheckBudgetTests.swift
//  SPMySQLFramework
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//
//  More info at <https://github.com/Sequel-Ace/Sequel-Ace>
//

import XCTest
@testable import SPMySQL

final class SAConnectionCheckBudgetTests: XCTestCase {
    /// The default timeout is capped at the check limits.
    func testDefaultTimeoutIsCappedAtTheCheckLimits() {
        XCTAssertEqual(SAConnectionCheckBudget.pingTimeout(forConfiguredTimeout: 30), 5)
        XCTAssertEqual(SAConnectionCheckBudget.networkWait(forConfiguredTimeout: 30), 3)
        XCTAssertEqual(SAConnectionCheckBudget.connectTimeout(forConfiguredTimeout: 30), 10)
    }

    /// A shorter configured timeout is kept.
    func testShorterConfiguredTimeoutIsKept() {
        XCTAssertEqual(SAConnectionCheckBudget.pingTimeout(forConfiguredTimeout: 2), 2)
        XCTAssertEqual(SAConnectionCheckBudget.networkWait(forConfiguredTimeout: 2), 2)
        XCTAssertEqual(SAConnectionCheckBudget.connectTimeout(forConfiguredTimeout: 2), 2)
    }

    /// An unlimited timeout still receives the check limits.
    func testUnlimitedTimeoutStillReceivesTheCheckLimits() {
        XCTAssertEqual(SAConnectionCheckBudget.pingTimeout(forConfiguredTimeout: 0), 5)
        XCTAssertEqual(SAConnectionCheckBudget.networkWait(forConfiguredTimeout: 0), 3)
        XCTAssertEqual(SAConnectionCheckBudget.connectTimeout(forConfiguredTimeout: 0), 10)
    }

    /// An attempt nobody waits for is kept to a second.
    func testAnAttemptNobodyWaitsForIsKeptToASecond() {
        XCTAssertEqual(SAConnectionCheckBudget.connectTimeoutAfterEndedWait(forConfiguredTimeout: 30), 1)
        XCTAssertEqual(SAConnectionCheckBudget.connectTimeoutAfterEndedWait(forConfiguredTimeout: 0), 1)
        XCTAssertLessThan(
            SAConnectionCheckBudget.connectTimeoutAfterEndedWait(forConfiguredTimeout: 30),
            SAConnectionCheckBudget.connectTimeout(forConfiguredTimeout: 30)
        )
    }

    /// An attempt after stopping spends almost nothing.
    func testAnAttemptAfterStoppingSpendsAlmostNothing() {
        let budget = SAConnectionCheckBudget.attemptBudget(forConfiguredTimeout: 30, userEndedWait: true, afterFailedCheck: true)
        XCTAssertEqual(budget.networkWait, 0)
        XCTAssertEqual(budget.connectTimeout, 1)
        XCTAssertTrue(budget.overridesConfiguredTimeout)
    }

    /// An attempt after a failed check spends the check limits.
    func testAnAttemptAfterAFailedCheckSpendsTheCheckLimits() {
        let budget = SAConnectionCheckBudget.attemptBudget(forConfiguredTimeout: 30, userEndedWait: false, afterFailedCheck: true)
        XCTAssertEqual(budget.networkWait, 3)
        XCTAssertEqual(budget.connectTimeout, 10)
        XCTAssertTrue(budget.overridesConfiguredTimeout)
    }

    /// An ordinary attempt keeps the configured timeout.
    func testAnOrdinaryAttemptKeepsTheConfiguredTimeout() {
        let budget = SAConnectionCheckBudget.attemptBudget(forConfiguredTimeout: 30, userEndedWait: false, afterFailedCheck: false)
        XCTAssertEqual(budget.networkWait, 10)
        XCTAssertEqual(budget.connectTimeout, 30)
        XCTAssertFalse(budget.overridesConfiguredTimeout)
    }

    /// Only an attempt right after stopping is shortened.
    func testOnlyAnAttemptRightAfterStoppingIsShortened() {
        XCTAssertTrue(SAConnectionCheckBudget.attemptIsShortened(startingSecondsAfterEndedWait: 0.5))
        XCTAssertFalse(SAConnectionCheckBudget.attemptIsShortened(startingSecondsAfterEndedWait: 60))
        XCTAssertFalse(SAConnectionCheckBudget.attemptIsShortened(startingSecondsAfterEndedWait: -1))
    }

    /// A side connection never waits long for an answer.
    func testASideConnectionNeverWaitsLongForAnAnswer() {
        // The client library tries a read three times.
        XCTAssertLessThanOrEqual(SAConnectionCheckBudget.sideConnectionAnswerTimeout() * 3, 10)
        XCTAssertGreaterThan(SAConnectionCheckBudget.sideConnectionAnswerTimeout(), 0)
    }

    /// The check stays well below the default timeout.
    func testCheckStaysWellBelowTheDefaultTimeout() {
        let worstCase = Double(SAConnectionCheckBudget.pingTimeout(forConfiguredTimeout: 30))
            + SAConnectionCheckBudget.networkWait(forConfiguredTimeout: 30)
            + Double(SAConnectionCheckBudget.connectTimeout(forConfiguredTimeout: 30))
        XCTAssertLessThan(worstCase, 30)
    }
}
