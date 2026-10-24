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

/// Which proxy a reconnect goes through as it stands, and which it waits for and connects again.
final class SAProxyReconnectCoordinatorTests: XCTestCase {
    private let coordinator = SAProxyReconnectCoordinator()

    /// Only the MySQL session over a connected tunnel was replaced: the tunnel is used as it is.
    func testAConnectedProxyLeftAloneByASessionReplacementIsUsedAsItStands() {
        XCTAssertTrue(coordinator.reconnectsThroughProxy(in: SPMySQLProxyConnected, untouchedBySessionReplacement: true))
    }

    /// A proxy that was told to disconnect is waited for and connected again, connected or not.
    func testAProxyThatWasToldToDisconnectIsWaitedFor() {
        XCTAssertFalse(coordinator.reconnectsThroughProxy(in: SPMySQLProxyConnected, untouchedBySessionReplacement: false))
        XCTAssertFalse(coordinator.reconnectsThroughProxy(in: SPMySQLProxyIdle, untouchedBySessionReplacement: false))
    }

    /// A tunnel that went down, or is still coming up, while the session was replaced is not the
    /// one to connect through: it is waited for and connected as before.
    func testAProxyNotConnectedIsWaitedForEvenAfterASessionReplacement() {
        for state in [SPMySQLProxyIdle, SPMySQLProxyConnecting, SPMySQLProxyWaitingForAuth, SPMySQLProxyForwardingFailed, SPMySQLProxyLaunchFailed] {
            XCTAssertFalse(coordinator.reconnectsThroughProxy(in: state, untouchedBySessionReplacement: true), "state \(state.rawValue)")
        }
    }
}
