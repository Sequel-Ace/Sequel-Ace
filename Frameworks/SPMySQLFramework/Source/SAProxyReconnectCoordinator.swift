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
