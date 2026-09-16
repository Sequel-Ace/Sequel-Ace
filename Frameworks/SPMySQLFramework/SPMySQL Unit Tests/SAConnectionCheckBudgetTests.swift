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
    func testDefaultTimeoutIsCappedAtTheCheckLimits() {
        XCTAssertEqual(SAConnectionCheckBudget.pingTimeout(forConfiguredTimeout: 30), 5)
        XCTAssertEqual(SAConnectionCheckBudget.networkWait(forConfiguredTimeout: 30), 3)
        XCTAssertEqual(SAConnectionCheckBudget.connectTimeout(forConfiguredTimeout: 30), 10)
    }

    func testShorterConfiguredTimeoutIsKept() {
        XCTAssertEqual(SAConnectionCheckBudget.pingTimeout(forConfiguredTimeout: 2), 2)
        XCTAssertEqual(SAConnectionCheckBudget.networkWait(forConfiguredTimeout: 2), 2)
        XCTAssertEqual(SAConnectionCheckBudget.connectTimeout(forConfiguredTimeout: 2), 2)
    }

    func testUnlimitedTimeoutStillReceivesTheCheckLimits() {
        XCTAssertEqual(SAConnectionCheckBudget.pingTimeout(forConfiguredTimeout: 0), 5)
        XCTAssertEqual(SAConnectionCheckBudget.networkWait(forConfiguredTimeout: 0), 3)
        XCTAssertEqual(SAConnectionCheckBudget.connectTimeout(forConfiguredTimeout: 0), 10)
    }

    func testAnAttemptNobodyWaitsForIsKeptToASecond() {
        XCTAssertEqual(SAConnectionCheckBudget.connectTimeoutAfterEndedWait(forConfiguredTimeout: 30), 1)
        XCTAssertEqual(SAConnectionCheckBudget.connectTimeoutAfterEndedWait(forConfiguredTimeout: 0), 1)
        XCTAssertLessThan(
            SAConnectionCheckBudget.connectTimeoutAfterEndedWait(forConfiguredTimeout: 30),
            SAConnectionCheckBudget.connectTimeout(forConfiguredTimeout: 30)
        )
    }

    func testCheckStaysWellBelowTheDefaultTimeout() {
        let worstCase = Double(SAConnectionCheckBudget.pingTimeout(forConfiguredTimeout: 30))
            + SAConnectionCheckBudget.networkWait(forConfiguredTimeout: 30)
            + Double(SAConnectionCheckBudget.connectTimeout(forConfiguredTimeout: 30))
        XCTAssertLessThan(worstCase, 30)
    }
}
