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
    private let socketLock = NSLock()
    private var cancellationSocket: Int32 = -1
    private var socketGeneration: UInt = 0
    private var cancellationThreads: Set<ObjectIdentifier> = []

    deinit {
        if cancellationSocket >= 0 {
            Darwin.close(cancellationSocket)
        }
    }

    /// Own a descriptor independently of MYSQL, which may close its descriptor
    /// during query failure or teardown. The duplicate cannot be recycled under us.
    @objc(trackSocket:error:)
    public func trackSocket(_ socket: Int32) throws {
        let duplicate = fcntl(socket, F_DUPFD_CLOEXEC, 0)
        guard duplicate >= 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        socketLock.withLock {
            if cancellationSocket >= 0 {
                Darwin.close(cancellationSocket)
            }
            cancellationSocket = duplicate
            socketGeneration &+= 1
        }
    }

    /// Retire the cancellation handle before disconnect releases MYSQL.
    @objc public func clearSocket() {
        socketLock.withLock {
            if cancellationSocket >= 0 {
                Darwin.close(cancellationSocket)
            }
            cancellationSocket = -1
            socketGeneration &+= 1
        }
    }

    /// Identifies the session that a cancellation was requested against.
    @objc public var socketToken: UInt {
        socketLock.withLock { socketGeneration }
    }

    /// Suppress recursive cancellation only inside this thread's fallback reconnect.
    @objc public var isCancellingOnCurrentThread: Bool {
        socketLock.withLock { cancellationThreads.contains(ObjectIdentifier(Thread.current)) }
    }

    /// Interrupt before waiting for query access. A stale cancellation must not
    /// interrupt a replacement session. Neither shutdown nor teardown reads MYSQL.
    @objc(cancelSocketWithToken:reconnect:)
    public func cancelSocket(token: UInt, reconnect: () -> Void) {
        let thread = ObjectIdentifier(Thread.current)
        let cancellation = socketLock.withLock { () -> (current: Bool, inserted: Bool) in
            guard token == socketGeneration, cancellationSocket >= 0 else {
                return (false, false)
            }
            _ = Darwin.shutdown(cancellationSocket, SHUT_RDWR)
            return (true, cancellationThreads.insert(thread).inserted)
        }
        guard cancellation.current else {
            return
        }
        defer {
            if cancellation.inserted {
                _ = socketLock.withLock { cancellationThreads.remove(thread) }
            }
        }
        reconnect()
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
