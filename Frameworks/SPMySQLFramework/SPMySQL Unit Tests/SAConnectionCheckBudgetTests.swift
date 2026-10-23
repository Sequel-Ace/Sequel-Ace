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

/// Replaces only the transport, and records the limit every attempt was given. The check, the
/// decision about the lost connection and the retry loop around them are the framework's own code.
private final class SAFailedCheckRetryConnection: SPMySQLConnection {
    /// The connect timeout each attempt ran on, in the order the attempts were made - the
    /// attempt's own limit where its budget set one, the configured timeout otherwise, which is
    /// how `_connect` reads them.
    var connectTimeouts: [UInt] = []

    @objc(_pingConnectionUsingLoopDelay:timeout:) func failingPing(_ loopDelay: UInt, timeout: UInt) -> Bool {
        false
    }

    @objc(_connect) func recordAttempt() -> Bool {
        let attemptLimit = (value(forKey: "connectTimeoutOverride") as? UInt) ?? 0
        connectTimeouts.append(attemptLimit > 0 ? attemptLimit : timeout)
        setValue(SPMySQLDisconnected.rawValue, forKey: "state")
        return false
    }

    @objc(_disconnectPreservingProxyReconnect:) func closeSession(_ preserveProxy: Bool) {
        setValue(SPMySQLDisconnected.rawValue, forKey: "state")
    }

    @objc(_waitForNetworkConnectionWithTimeout:) func waitForNetwork(_ timeout: Double) -> Bool {
        true
    }
}

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

    /// A keepalive ping is never cut off sooner than the minimum, but may take a longer configured
    /// timeout - and a connection configured without one keeps the thirty seconds it has always
    /// had here. Shortening that to the floor would cost a session with a transaction open its
    /// work twenty seconds sooner than before, on the setting of somebody who said they would wait.
    func testAKeepalivePingGetsAtLeastTheMinimumAndKeepsItsThirtySecondsWithoutATimeout() {
        XCTAssertEqual(SAConnectionCheckBudget.keepAlivePingTimeout(forConfiguredTimeout: 0), 30)
        XCTAssertEqual(SAConnectionCheckBudget.keepAlivePingWithoutTimeout, 30)
        XCTAssertGreaterThan(SAConnectionCheckBudget.keepAlivePingTimeout(forConfiguredTimeout: 0),
                             SAConnectionCheckBudget.keepAlivePingMinimum)
        XCTAssertEqual(SAConnectionCheckBudget.keepAlivePingTimeout(forConfiguredTimeout: 3), SAConnectionCheckBudget.keepAlivePingMinimum)
        XCTAssertEqual(SAConnectionCheckBudget.keepAlivePingTimeout(forConfiguredTimeout: 90), 90)
        // The default timeout stays as it is.
        XCTAssertEqual(SAConnectionCheckBudget.keepAlivePingTimeout(forConfiguredTimeout: 10), 10)
    }

    /// A side connection never waits long to connect, even without a configured timeout.
    func testASideConnectionNeverWaitsLongToConnect() {
        XCTAssertEqual(SAConnectionCheckBudget.sideConnectionConnectTimeout(forConfiguredTimeout: 0), SAConnectionCheckBudget.sideConnectionConnectLimit)
        XCTAssertEqual(SAConnectionCheckBudget.sideConnectionConnectTimeout(forConfiguredTimeout: 30), SAConnectionCheckBudget.sideConnectionConnectLimit)
        XCTAssertEqual(SAConnectionCheckBudget.sideConnectionConnectTimeout(forConfiguredTimeout: 2), 2)
        XCTAssertLessThanOrEqual(SAConnectionCheckBudget.sideConnectionConnectLimit, SAConnectionCheckBudget.connectLimit)
    }

    /// The check stays well below the default timeout.
    func testCheckStaysWellBelowTheDefaultTimeout() {
        let worstCase = Double(SAConnectionCheckBudget.pingTimeout(forConfiguredTimeout: 30))
            + SAConnectionCheckBudget.networkWait(forConfiguredTimeout: 30)
            + Double(SAConnectionCheckBudget.connectTimeout(forConfiguredTimeout: 30))
        XCTAssertLessThan(worstCase, 30)
    }
    /// The check's ping is cut short - but not on a session with a transaction open, where the cut
    /// costs the session and the server rolls the transaction back. Such a session gets the same
    /// floor the keepalive has, for the same reason.
    func testTheCheckPingIsNotCutShortWithATransactionOpen() {
        for configured in [UInt(0), 1, 3, 5, 10, 30, 120] {
            XCTAssertEqual(SAConnectionCheckBudget.checkPingTimeout(forConfiguredTimeout: configured,
                                                                    sessionHasOpenTransaction: false),
                           SAConnectionCheckBudget.pingTimeout(forConfiguredTimeout: configured))
            XCTAssertEqual(SAConnectionCheckBudget.checkPingTimeout(forConfiguredTimeout: configured,
                                                                    sessionHasOpenTransaction: true),
                           SAConnectionCheckBudget.pingTimeoutSparingUncommittedWork(forConfiguredTimeout: configured))
        }
        // The keepalive's thirty seconds for a connection without a configured timeout are not
        // taken over here: somebody is waiting for this one.
        XCTAssertEqual(SAConnectionCheckBudget.checkPingTimeout(forConfiguredTimeout: 0,
                                                                sessionHasOpenTransaction: true),
                       SAConnectionCheckBudget.keepAlivePingMinimum)
        // Concretely: a server that takes eight seconds to answer keeps a session that has work in
        // it, and loses one that has none.
        XCTAssertEqual(SAConnectionCheckBudget.checkPingTimeout(forConfiguredTimeout: 30,
                                                                sessionHasOpenTransaction: true), 30)
        XCTAssertEqual(SAConnectionCheckBudget.checkPingTimeout(forConfiguredTimeout: 30,
                                                                sessionHasOpenTransaction: false),
                       SAConnectionCheckBudget.pingLimit)
        XCTAssertGreaterThan(SAConnectionCheckBudget.checkPingTimeout(forConfiguredTimeout: 1,
                                                                      sessionHasOpenTransaction: true),
                             SAConnectionCheckBudget.pingLimit, "a very short timeout does not shorten it further")
    }

    /// Only an answer from a delegate makes a retry the user's to wait for.
    func testOnlyADelegatesAnswerMakesARetryTheUsersToWaitFor() {
        XCTAssertTrue(SAConnectionCheckBudget.retryKeepsFailedCheckLimits(afterFailedCheck: true,
                                                                           decisionCameFromDelegate: false))
        XCTAssertFalse(SAConnectionCheckBudget.retryKeepsFailedCheckLimits(afterFailedCheck: true,
                                                                            decisionCameFromDelegate: true))
        XCTAssertFalse(SAConnectionCheckBudget.retryKeepsFailedCheckLimits(afterFailedCheck: false,
                                                                            decisionCameFromDelegate: false))
    }

    /// Every attempt a failed check leads to keeps the check's limits, the ones the connection
    /// decides on by itself included: with no delegate to ask it selects a reconnect five times
    /// over, and on a connection with no timeout configured each of those would otherwise wait
    /// with no limit at all - which is the wait the check exists to bound.
    func testEveryRetryOfAFailedCheckKeepsItsLimits() {
        let connection = SAFailedCheckRetryConnection()
        connection.useKeepAlive = false
        connection.timeout = 0
        connection.setValue(SPMySQLConnected.rawValue, forKey: "state")
        defer {
            connection.setValue(SPMySQLDisconnected.rawValue, forKey: "state")
            connection.disconnect()
        }

        XCTAssertFalse(connection.check())

        // The check's own attempt, and the five the connection goes on to decide on.
        XCTAssertEqual(connection.connectTimeouts.count, 6)
        for granted in connection.connectTimeouts {
            XCTAssertNotEqual(granted, 0, "an attempt of a failed check cannot run without a limit")
            XCTAssertLessThanOrEqual(granted, SAConnectionCheckBudget.connectLimit)
        }
    }

}
