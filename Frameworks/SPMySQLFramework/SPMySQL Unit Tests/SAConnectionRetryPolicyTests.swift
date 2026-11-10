//
//  SAConnectionRetryPolicyTests.swift
//  SPMySQLFramework
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//
//  More info at <https://github.com/Sequel-Ace/Sequel-Ace>
//

import XCTest
@testable import SPMySQL

final class SAConnectionRetryPolicyTests: XCTestCase {
    /// A host that was never reached is not tried again.
    func testAHostThatWasNeverReachedIsNotTriedAgain() {
        XCTAssertFalse(SAConnectionRetryPolicy.shouldRetryWithoutTLS(afterErrorID: 2002)) // CR_CONNECTION_ERROR
        XCTAssertFalse(SAConnectionRetryPolicy.shouldRetryWithoutTLS(afterErrorID: 2003)) // CR_CONN_HOST_ERROR
        XCTAssertFalse(SAConnectionRetryPolicy.shouldRetryWithoutTLS(afterErrorID: 2005)) // CR_UNKNOWN_HOST
    }

    /// A failed TLS negotiation is tried without TLS.
    func testAFailedTLSNegotiationIsTriedWithoutTLS() {
        XCTAssertTrue(SAConnectionRetryPolicy.shouldRetryWithoutTLS(afterErrorID: 2026)) // CR_SSL_CONNECTION_ERROR
    }

    /// A connection lost after the negotiation may already have carried the credentials over TLS,
    /// so it is not repeated without TLS.
    func testAConnectionLostAfterTheNegotiationIsNotTriedWithoutTLS() {
        XCTAssertFalse(SAConnectionRetryPolicy.shouldRetryWithoutTLS(afterErrorID: 2013)) // CR_SERVER_LOST
        XCTAssertFalse(SAConnectionRetryPolicy.shouldRetryWithoutTLS(afterErrorID: 2055)) // CR_SERVER_LOST_EXTENDED
        XCTAssertFalse(SAConnectionRetryPolicy.shouldRetryWithoutTLS(afterErrorID: 2006)) // CR_SERVER_GONE_ERROR
    }

    /// Rejected credentials and any other or unknown error are not sent again without TLS.
    func testRejectedCredentialsAndOtherErrorsAreNotTriedWithoutTLS() {
        XCTAssertFalse(SAConnectionRetryPolicy.shouldRetryWithoutTLS(afterErrorID: 1045)) // ER_ACCESS_DENIED_ERROR
        XCTAssertFalse(SAConnectionRetryPolicy.shouldRetryWithoutTLS(afterErrorID: 1044)) // ER_DBACCESS_DENIED_ERROR
        XCTAssertFalse(SAConnectionRetryPolicy.shouldRetryWithoutTLS(afterErrorID: 1130)) // ER_HOST_NOT_PRIVILEGED
        XCTAssertFalse(SAConnectionRetryPolicy.shouldRetryWithoutTLS(afterErrorID: 2059)) // CR_AUTH_PLUGIN_CANNOT_LOAD
        XCTAssertFalse(SAConnectionRetryPolicy.shouldRetryWithoutTLS(afterErrorID: 2061)) // CR_AUTH_PLUGIN_ERR
        XCTAssertFalse(SAConnectionRetryPolicy.shouldRetryWithoutTLS(afterErrorID: 0))
    }
    /// The retry without TLS runs on what is left of the attempt's budget, so an attempt cannot
    /// take it twice.
    func testTheRetryWithoutTLSGetsWhatIsLeftOfTheBudget() {
        // Nothing spent yet: the retry has the whole budget.
        XCTAssertEqual(SAConnectionRetryPolicy.retryConnectTimeout(forConnectTimeout: 10, secondsSpent: 0)?.uintValue, 10)
        // Half of it gone.
        XCTAssertEqual(SAConnectionRetryPolicy.retryConnectTimeout(forConnectTimeout: 10, secondsSpent: 4)?.uintValue, 6)
        // Rounded up to the whole seconds the client counts in.
        XCTAssertEqual(SAConnectionRetryPolicy.retryConnectTimeout(forConnectTimeout: 10, secondsSpent: 4.7)?.uintValue, 6)
    }

    /// A budget of one second still gets its retry. That is what an attempt is given just after
    /// the user has ended a wait, and rounding the remainder down would suppress the retry on
    /// every real attempt, since every one of them takes some time.
    func testASecondsBudgetStillGetsItsRetry() {
        XCTAssertEqual(SAConnectionRetryPolicy.retryConnectTimeout(forConnectTimeout: 1, secondsSpent: 0.05)?.uintValue, 1)
        XCTAssertEqual(SAConnectionRetryPolicy.retryConnectTimeout(forConnectTimeout: 1, secondsSpent: 0.95)?.uintValue, 1)
        XCTAssertNil(SAConnectionRetryPolicy.retryConnectTimeout(forConnectTimeout: 1, secondsSpent: 1))
    }

    /// Once the budget is gone the retry is not made at all: the first attempt reached the
    /// server's TLS, so the question is more use to the user than another wait.
    func testTheRetryIsSkippedOnceTheBudgetIsGone() {
        XCTAssertNil(SAConnectionRetryPolicy.retryConnectTimeout(forConnectTimeout: 10, secondsSpent: 10))
        XCTAssertEqual(SAConnectionRetryPolicy.retryConnectTimeout(forConnectTimeout: 10, secondsSpent: 9.5)?.uintValue, 1,
                       "part of a second left is still an attempt")
        XCTAssertNil(SAConnectionRetryPolicy.retryConnectTimeout(forConnectTimeout: 10, secondsSpent: 40),
                     "and an attempt that overran its budget gets nothing")
    }

    /// A connection with no limit keeps none for the retry either.
    func testAnUnlimitedBudgetStaysUnlimited() {
        XCTAssertEqual(SAConnectionRetryPolicy.retryConnectTimeout(forConnectTimeout: 0, secondsSpent: 0)?.uintValue, 0)
        XCTAssertEqual(SAConnectionRetryPolicy.retryConnectTimeout(forConnectTimeout: 0, secondsSpent: 600)?.uintValue, 0)
    }

    /// A clock that went backwards is not taken for budget earned back.
    func testTimeThatWentBackwardsEarnsNothing() {
        XCTAssertEqual(SAConnectionRetryPolicy.retryConnectTimeout(forConnectTimeout: 10, secondsSpent: -5)?.uintValue, 10)
    }

}
