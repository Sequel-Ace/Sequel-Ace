//
//  SAConnectionSessionAccess.swift
//  SPMySQLFramework
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import Foundation
import Darwin

/// Keeps queries out of a partially restored session. Recursive access lets the
/// reconnect owner run its own setup queries and recover from another disconnect.
@objc public final class SAConnectionSessionAccess: NSObject {
    private let sessionLock = NSRecursiveLock()
    private let completionLock = NSLock()
    private var generation: UInt64 = 0
    private var reconnectSucceeded = false

    /// Wake an active query before waiting for its session access during fallback
    /// cancellation. Shutdown leaves the descriptor and MYSQL owned by the query;
    /// reconnect closes them only after that query has unwound and released access.
    @objc(interruptSocket:)
    public static func interruptSocket(_ socket: Int32) {
        _ = Darwin.shutdown(socket, SHUT_RDWR)
    }

    /// Runs a query only after the current reconnect (including restoration) ends.
    @objc(performQuery:)
    public func performQuery(_ operation: () -> Any?) -> Any? {
        guard acquire() else {
            return nil
        }
        defer { sessionLock.unlock() }
        return operation()
    }

    /// Coalesces callers waiting for the same reconnect while allowing a foreground
    /// caller to retry a failed background attempt, as the connection previously did.
    @objc(reconnectAllowingRetries:operation:)
    public func reconnect(allowingRetries: Bool, operation: () -> Bool) -> Bool {
        let previousGeneration = completionLock.withLock { generation }
        guard acquire() else {
            return false
        }
        defer { sessionLock.unlock() }

        let completion = completionLock.withLock { (generation, reconnectSucceeded) }
        if completion.0 != previousGeneration && (completion.1 || !allowingRetries) {
            return completion.1
        }

        let succeeded = operation()
        completionLock.withLock {
            generation &+= 1
            reconnectSucceeded = succeeded
        }
        return succeeded
    }

    /// Waiting must remain cancellable: disconnect can be waiting for a keepalive
    /// thread to exit. The main thread also services SSH authentication/teardown.
    private func acquire() -> Bool {
        while !Thread.current.isCancelled {
            if sessionLock.try() {
                return true
            }
            let deadline = Date(timeIntervalSinceNow: 0.01)
            if Thread.isMainThread {
                // Default mode services main-queue work and the keepalive timer's
                // synchronous main-thread setup/teardown even without a modal panel.
                RunLoop.current.run(mode: .default, before: deadline)
            }
            let remaining = deadline.timeIntervalSinceNow
            if remaining > 0 {
                Thread.sleep(forTimeInterval: remaining)
            }
        }
        return false
    }
}
