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

    /// Whether the reconnect goes through the proxy as it stands, without waiting for it to go
    /// idle and connecting it again: when only the MySQL session over it was replaced, nothing
    /// was asked of the proxy, and one that still reports a connection is the tunnel to use -
    /// the wait for idle would run until the attempt's budget is out, with nothing left for the
    /// connect itself, and `connect` on a connected tunnel does nothing anyway. A proxy in any
    /// other state, or one that was told to disconnect, is waited for and connected as before.
    @objc(reconnectsThroughProxyInState:untouchedBySessionReplacement:)
    public func reconnectsThroughProxy(
        in state: SPMySQLConnectionProxyState,
        untouchedBySessionReplacement: Bool
    ) -> Bool {
        untouchedBySessionReplacement && state == SPMySQLProxyConnected
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
            DispatchQueue.main.sync(execute: disconnect)
        }
    }
}
