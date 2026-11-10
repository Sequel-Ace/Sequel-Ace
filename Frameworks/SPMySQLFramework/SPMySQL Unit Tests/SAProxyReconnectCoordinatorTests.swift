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

/// A proxy that stands for a tunnel which is up and stays up, and records whether anybody asked
/// it to connect or disconnect.
private final class SAStandingTunnel: NSObject, SPMySQLConnectionProxy {
    private(set) var connectRequests = 0
    private(set) var disconnectRequests = 0

    func connect() { connectRequests += 1 }
    func disconnect() { disconnectRequests += 1 }
    func state() -> SPMySQLConnectionProxyState { SPMySQLProxyConnected }
    func localPort() -> UInt { 3306 }
    func setConnectionStateChange(_ theStateChangeSelector: Selector!, delegate theDelegate: Any!) -> Bool { true }
}

/// A connection whose every handshake fails, counting the attempts; the proxy handling around
/// them is the framework's own.
private final class SAHandshakeFailingConnection: SPMySQLConnection {
    private(set) var handshakes = 0

    @objc(_connectUsingConnectTimeout:) func failHandshake(_ connectTimeoutOrZero: UInt) -> Bool {
        handshakes += 1
        setValue(SPMySQLDisconnected.rawValue, forKey: "state")
        return false
    }

    @objc(_waitForNetworkConnectionWithTimeout:) func waitForNetwork(_ timeout: Double) -> Bool {
        true
    }
}

/// Which proxy a reconnect goes through as it stands, and which it waits for and connects again.
final class SAProxyReconnectCoordinatorTests: XCTestCase {
    private let coordinator = SAProxyReconnectCoordinator()

    /// A session replaced over a tunnel that stayed up is reconnected through it as it stands -
    /// and so is the retry after a handshake that failed: nothing asked the tunnel to go in
    /// between, so there is still nothing to wait for. Waiting for it to go idle would spend the
    /// whole attempt's budget on a tunnel that never goes idle on its own, with nothing left for
    /// the connect, and then ask it to connect, which a connected tunnel ignores.
    func testTheRetryAfterAFailedHandshakeStillGoesThroughTheStandingTunnel() {
        let tunnel = SAStandingTunnel()
        let connection = SAHandshakeFailingConnection()
        connection.useKeepAlive = false
        connection.timeout = 3
        connection.setProxy(tunnel)
        connection.setValue(SPMySQLConnected.rawValue, forKey: "state")
        connection.setValue(SASessionReplacementMark.regardless.rawValue, forKey: "sessionReplacement")
        // One retry after the attempt, then the connection gives up on its own.
        connection.setValue(4, forKey: "reconnectionRetryAttempts")
        defer {
            connection.setValue(SPMySQLDisconnected.rawValue, forKey: "state")
            connection.setProxy(nil)
            connection.disconnect()
        }

        let started = Date()
        XCTAssertFalse(connection.checkIfNecessary())
        let elapsed = Date().timeIntervalSince(started)

        XCTAssertEqual(connection.handshakes, 2, "the attempt and its retry")
        XCTAssertLessThan(elapsed, 2, "neither waited for the tunnel to go idle")
        XCTAssertEqual(tunnel.connectRequests, 0, "and neither asked the tunnel to connect")
        XCTAssertEqual(tunnel.disconnectRequests, 0)
    }

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
