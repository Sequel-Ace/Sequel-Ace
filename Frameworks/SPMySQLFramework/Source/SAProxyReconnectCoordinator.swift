//
//  SAProxyReconnectCoordinator.swift
//  SPMySQLFramework
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import Foundation

/// Owns the decisions and proxy routing used while an interrupted MySQL
/// connection waits for its prerequisite proxy to reconnect.
@objcMembers
public final class SAProxyReconnectCoordinator: NSObject {

    /// Returns whether the reconnect must stop before doing more proxy work.
    @objc(shouldAbortReconnectWithThreadCancelled:userTriggeredDisconnect:)
    public func shouldAbortReconnect(
        threadCancelled: Bool,
        userTriggeredDisconnect: Bool
    ) -> Bool {
        threadCancelled || userTriggeredDisconnect
    }

    /// Reports whether the proxy accepted a connect request but intentionally
    /// deferred launching it while an earlier attempt finishes cleanup.
    @objc(connectionAttemptPendingForProxy:)
    public func connectionAttemptPending(for proxy: SPMySQLConnectionProxy) -> Bool {
        proxy.connectionAttemptPending?() ?? false
    }

    /// Excludes user interaction and intentional proxy cleanup from the network
    /// connection timeout while leaving cancellation as an independent decision.
    @objc(shouldExcludeWaitTimeForAuthentication:connectionAttemptPending:)
    public func shouldExcludeWaitTime(
        waitingForAuthentication: Bool,
        connectionAttemptPending: Bool
    ) -> Bool {
        waitingForAuthentication || connectionAttemptPending
    }

    /// Returns whether a reconnect can go through the proxy as it is.
    ///
    /// Closing only the session - after work nobody waited for - leaves the tunnel up. Waiting for
    /// a connected tunnel to become idle would wait out the whole connection timeout, and asking it
    /// to connect again does nothing, so its current port is used straight away.
    @objc(reusesConnectedProxyAfterClosingSessionOnly:proxyConnected:)
    public func reusesConnectedProxy(
        afterClosingSessionOnly sessionClosedOnly: Bool,
        proxyConnected: Bool
    ) -> Bool {
        sessionClosedOnly && proxyConnected
    }

    /// How long a reconnect without a connection timeout waits for its proxy to finish shutting
    /// down, in seconds - as long as it would with the default timeout.
    public static let idleWaitWithoutConnectTimeout: TimeInterval = 10

    /// Returns how long a reconnect waits for its proxy to become idle before asking it to connect.
    ///
    /// The wait lets a tunnel that is shutting down finish, so that the reconnect does not go
    /// through the tunnel on its way out. A connection timeout of zero means no limit for the
    /// connection, not no time for the tunnel.
    /// - Parameter connectTimeout: The attempt's connection timeout in seconds; zero for none.
    /// - Returns: The longest wait, in seconds.
    @objc(idleWaitLimitForConnectTimeout:)
    public func idleWaitLimit(forConnectTimeout connectTimeout: UInt) -> TimeInterval {
        connectTimeout > 0 ? TimeInterval(connectTimeout) : Self.idleWaitWithoutConnectTimeout
    }

    /// Routes proxy teardown through the main thread. Internal reconnect cleanup
    /// preserves a request queued behind the current proxy lifecycle when the
    /// proxy supports that distinction; explicit teardown always cancels it.
    @objc(disconnectProxy:preservingReconnect:)
    public func disconnect(
        proxy: SPMySQLConnectionProxy,
        preservingReconnect: Bool
    ) {
        let disconnect = {
            if preservingReconnect, proxy.disconnectForReconnect?() != nil {
                return
            }
            proxy.disconnect()
        }

        if Thread.isMainThread {
            disconnect()
        } else {
            Self.runOnMainRunLoopAndWait(disconnect)
        }
    }

    /// Runs a block on the main thread and waits for it, by way of the main run loop.
    ///
    /// Connection work can run on its own thread while the main thread waits for it from inside a
    /// block on the main queue. That queue runs one block at a time, so `DispatchQueue.main.sync`
    /// would wait for a wait that is waiting for it. The main run loop keeps turning meanwhile, and
    /// a run loop block does not need the main queue to be free. The application does the same for
    /// what it asks the main thread from connection work (`SAMainRunLoop`).
    /// - Parameter block: The work to do on the main thread.
    private static func runOnMainRunLoopAndWait(_ block: @escaping () -> Void) {
        let finished = DispatchSemaphore(value: 0)
        RunLoop.main.perform(inModes: [.common]) {
            block()
            finished.signal()
        }

        // A block handed to a run loop does not wake it.
        CFRunLoopWakeUp(CFRunLoopGetMain())
        finished.wait()
    }
}

/// Decides how long a reconnect waits for its proxy to connect.
///
/// With a connection timeout, the proxy gets that long and one second more, as before. Without one,
/// the wait ends with the attempt instead: once the proxy has started and falls back to idle, or
/// reports that it failed - or after two minutes, in case a server takes the connection but never
/// finishes the handshake and nothing else would end the wait. The attempt starts on a thread of the proxy's own, so a
/// proxy still idle right after the request is given a second to begin - as long as every attempt
/// without a timeout was given before.
@objc(SAProxyConnectWait)
public final class SAProxyConnectWait: NSObject {

    /// How long a proxy that has not started yet is waited for, in seconds, when there is no timeout.
    public static let startGrace: TimeInterval = 1

    /// The longest wait for a proxy without a timeout, in seconds.
    public static let longestWaitWithoutTimeout: TimeInterval = 120

    private let connectTimeout: UInt
    private var attemptHasStarted = false

    /// Starts deciding for one connect request.
    /// - Parameter connectTimeout: The attempt's connection timeout in seconds; zero for none.
    @objc(initWithConnectTimeout:)
    public init(connectTimeout: UInt) {
        self.connectTimeout = connectTimeout
        super.init()
    }

    /// Returns whether the reconnect keeps waiting for the proxy.
    /// - Parameters:
    ///   - elapsed: Seconds since the connect request, not counting prompts or a queued attempt.
    ///   - proxyState: The proxy's state now.
    ///   - attemptPending: Whether the proxy accepted the request but has not started it yet.
    /// - Returns: Whether to keep waiting.
    @objc(shouldKeepWaitingAfter:proxyState:attemptPending:)
    public func shouldKeepWaiting(after elapsed: TimeInterval,
                                  proxyState: SPMySQLConnectionProxyState,
                                  attemptPending: Bool) -> Bool {
        if connectTimeout > 0 {
            return elapsed <= TimeInterval(connectTimeout) + 1
        }
        if elapsed > Self.longestWaitWithoutTimeout
            || proxyState == SPMySQLProxyForwardingFailed || proxyState == SPMySQLProxyLaunchFailed {
            return false
        }
        if proxyState != SPMySQLProxyIdle {
            attemptHasStarted = true
            return true
        }
        if attemptPending {
            return true
        }
        return !attemptHasStarted && elapsed <= Self.startGrace
    }
}
