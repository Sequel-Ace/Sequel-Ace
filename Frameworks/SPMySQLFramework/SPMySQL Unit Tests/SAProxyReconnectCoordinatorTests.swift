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

/// A proxy that records the thread it was told to disconnect on.
private final class SADisconnectRecordingProxy: NSObject, SPMySQLConnectionProxy {
    private(set) var disconnectedOn: Thread?

    func connect() {}
    func disconnect() { disconnectedOn = Thread.current }
    func state() -> SPMySQLConnectionProxyState { SPMySQLProxyConnected }
    func localPort() -> UInt { 3306 }
    func setConnectionStateChange(_ theStateChangeSelector: Selector!, delegate theDelegate: Any!) -> Bool { true }
}

/// Which proxy a reconnect goes through as it stands, and which it waits for and connects again.
final class SAProxyReconnectCoordinatorTests: XCTestCase {
    private let coordinator = SAProxyReconnectCoordinator()

    /// A proxy is told to go on the main thread even while the main queue is busy: the reconnect
    /// that tells it runs on the connection's own thread, and the main thread can be waiting for
    /// that reconnect from inside a block on the main queue - as it is when a row is saved from a
    /// main-queue block and the connection has to come back first. The main run loop keeps turning
    /// during such a wait; the main queue does not.
    func testAProxyIsDisconnectedThroughTheMainRunLoopWhileTheMainQueueIsBusy() {
        let proxy = SADisconnectRecordingProxy()
        let teardownReturned = DispatchSemaphore(value: 0)
        let mainQueueBlockEnded = expectation(description: "the main-queue block ended")
        var returnedWhileTheMainQueueWasBusy = false

        DispatchQueue.main.async { [coordinator] in
            // The main queue is busy with this block, which waits for the reconnect the way the
            // wait sheet does: by turning the main run loop.
            Thread.detachNewThread {
                coordinator.disconnect(proxy: proxy, preservingReconnect: false)
                teardownReturned.signal()
            }
            let giveUp = Date(timeIntervalSinceNow: 3)
            while !returnedWhileTheMainQueueWasBusy && Date() < giveUp {
                returnedWhileTheMainQueueWasBusy = teardownReturned.wait(timeout: .now()) == .success
                RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
            }
            mainQueueBlockEnded.fulfill()
        }

        wait(for: [mainQueueBlockEnded], timeout: 5)
        XCTAssertTrue(returnedWhileTheMainQueueWasBusy, "the teardown did not wait for the main queue")
        XCTAssertTrue(proxy.disconnectedOn?.isMainThread ?? false, "and ran on the main thread")
    }

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
