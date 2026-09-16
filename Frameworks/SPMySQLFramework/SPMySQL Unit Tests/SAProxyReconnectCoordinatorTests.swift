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
}
