//
//  SAProxyReconnectCoordinatorTests.swift
//  SPMySQLFramework
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//
//  More info at <https://github.com/Sequel-Ace/Sequel-Ace>
//

import XCTest
@testable import SPMySQL

/// When a reconnect goes through the tunnel as it is, instead of waiting for it to restart.
final class SAProxyReconnectCoordinatorTests: XCTestCase {
    private let coordinator = SAProxyReconnectCoordinator()

    /// A tunnel still up after only the session was closed is used as it is.
    func testATunnelLeftUpAfterClosingOnlyTheSessionIsReused() {
        XCTAssertTrue(coordinator.reusesConnectedProxy(afterClosingSessionOnly: true, proxyConnected: true))
    }

    /// A tunnel that is not connected is brought up again as before.
    func testATunnelThatIsNotConnectedIsNotReused() {
        XCTAssertFalse(coordinator.reusesConnectedProxy(afterClosingSessionOnly: true, proxyConnected: false))
    }

    /// After any other loss of the session the tunnel is not trusted.
    func testATunnelIsNotReusedAfterTheSessionWasLostOtherwise() {
        XCTAssertFalse(coordinator.reusesConnectedProxy(afterClosingSessionOnly: false, proxyConnected: true))
    }

    /// A tunnel shutting down gets the connection timeout, or the default one when there is none.
    func testTheIdleWaitHasALimitEvenWithoutAConnectionTimeout() {
        XCTAssertEqual(coordinator.idleWaitLimit(forConnectTimeout: 7), 7)
        XCTAssertEqual(coordinator.idleWaitLimit(forConnectTimeout: 0), SAProxyReconnectCoordinator.idleWaitWithoutConnectTimeout)
    }

    /// With a connection timeout, the connect wait ends a second after it, as before.
    func testAConnectWaitWithATimeoutEndsASecondAfterIt() {
        let wait = SAProxyConnectWait(connectTimeout: 5)
        XCTAssertTrue(wait.shouldKeepWaiting(after: 6, proxyState: SPMySQLProxyConnecting, attemptPending: false))
        XCTAssertFalse(wait.shouldKeepWaiting(after: 6.5, proxyState: SPMySQLProxyConnecting, attemptPending: false))
    }

    /// Without a connection timeout, an attempt that keeps going is waited for up to two minutes.
    func testAConnectWaitWithoutATimeoutFollowsTheAttempt() {
        let wait = SAProxyConnectWait(connectTimeout: 0)
        XCTAssertTrue(wait.shouldKeepWaiting(after: 0.1, proxyState: SPMySQLProxyIdle, attemptPending: false))
        XCTAssertTrue(wait.shouldKeepWaiting(after: 1, proxyState: SPMySQLProxyConnecting, attemptPending: false))
        XCTAssertTrue(wait.shouldKeepWaiting(after: 60, proxyState: SPMySQLProxyWaitingForAuth, attemptPending: false))
        XCTAssertTrue(wait.shouldKeepWaiting(after: SAProxyConnectWait.longestWaitWithoutTimeout, proxyState: SPMySQLProxyConnecting, attemptPending: false))
        XCTAssertFalse(wait.shouldKeepWaiting(after: SAProxyConnectWait.longestWaitWithoutTimeout + 1, proxyState: SPMySQLProxyConnecting, attemptPending: false))
    }

    /// Without a connection timeout, an attempt that ends without connecting ends the wait.
    func testAConnectWaitWithoutATimeoutEndsWithTheAttempt() {
        let fellBack = SAProxyConnectWait(connectTimeout: 0)
        XCTAssertTrue(fellBack.shouldKeepWaiting(after: 1, proxyState: SPMySQLProxyConnecting, attemptPending: false))
        XCTAssertFalse(fellBack.shouldKeepWaiting(after: 2, proxyState: SPMySQLProxyIdle, attemptPending: false))

        let failed = SAProxyConnectWait(connectTimeout: 0)
        XCTAssertFalse(failed.shouldKeepWaiting(after: 1, proxyState: SPMySQLProxyForwardingFailed, attemptPending: false))
        XCTAssertFalse(failed.shouldKeepWaiting(after: 1, proxyState: SPMySQLProxyLaunchFailed, attemptPending: false))
    }

    /// Without a connection timeout, a proxy that never starts is given a second, or longer while its attempt is queued.
    func testAConnectWaitWithoutATimeoutGivesAnIdleProxyASecond() {
        let wait = SAProxyConnectWait(connectTimeout: 0)
        XCTAssertTrue(wait.shouldKeepWaiting(after: SAProxyConnectWait.startGrace, proxyState: SPMySQLProxyIdle, attemptPending: false))
        XCTAssertFalse(wait.shouldKeepWaiting(after: SAProxyConnectWait.startGrace + 0.5, proxyState: SPMySQLProxyIdle, attemptPending: false))
        XCTAssertTrue(wait.shouldKeepWaiting(after: SAProxyConnectWait.startGrace + 60, proxyState: SPMySQLProxyIdle, attemptPending: true))
    }
}
