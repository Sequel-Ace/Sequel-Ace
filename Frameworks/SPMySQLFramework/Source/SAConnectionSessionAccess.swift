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
    private var serverThreadID: UInt = 0
    private var nativeQueryGeneration: UInt = 0
    private var activeNativeQuery: UInt?
    private var cancellingQuery: UInt?
    private var cancellingSocketGeneration: UInt = 0
    private var recoveryRequired = false
    private var nativeOnlyCancellationThreads: Set<ObjectIdentifier> = []
    private var queryCancellationGeneration: UInt = 0
    private var queryCancellationTokens: [UInt] = []
    private var questionsAwaitingTheMainThread = 0

    /// Remember cancellation across setup queries run by the interrupted query's
    /// reconnect. Each nested query has its own token; it cannot erase its caller's.
    @objc public func recordQueryCancellation() {
        socketLock.withLock { queryCancellationGeneration &+= 1 }
    }

    @objc public var currentQueryWasCancelled: Bool {
        socketLock.withLock {
            guard let token = queryCancellationTokens.last else {
                return false
            }
            return token != queryCancellationGeneration
        }
    }

    deinit {
        if cancellationSocket >= 0 {
            Darwin.close(cancellationSocket)
        }
    }

    /// Own a descriptor independently of MYSQL, which may close its descriptor
    /// during query failure or teardown. The duplicate cannot be recycled under us.
    @objc(trackSocket:serverThreadID:error:)
    public func trackSocket(_ socket: Int32, serverThreadID: UInt = 0) throws {
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
            self.serverThreadID = serverThreadID
            recoveryRequired = false
        }
    }

    /// Retire the cancellation handle before disconnect releases MYSQL.
    @objc public func clearSocket() {
        socketLock.withLock {
            if cancellationSocket >= 0 {
                Darwin.close(cancellationSocket)
            }
            cancellationSocket = -1
            serverThreadID = 0
            recoveryRequired = false
            socketGeneration &+= 1
        }
    }

    /// Identifies the session that a cancellation was requested against.
    @objc public var socketToken: UInt {
        socketLock.withLock { socketGeneration }
    }

    /// Called with the native connection locked, before any statement is sent.
    /// The socket and server ID were published together from the same MYSQL handle.
    @discardableResult
    @objc public func beginNativeQuery() -> Bool {
        socketLock.withLock {
            nativeQueryGeneration &+= 1
            activeNativeQuery = nativeQueryGeneration
            return queryCancellationTokens.last.map { $0 == queryCancellationGeneration } ?? true
        }
    }

    /// Streaming results keep this record until their final native-lock release.
    @objc public func endNativeQuery() {
        socketLock.withLock { activeNativeQuery = nil }
    }

    /// Recheck after the auxiliary connection is opened. An already completed or
    /// retired query needs no KILL; a later query cannot enter while we own this lease.
    @objc public var cancellationIsCurrent: Bool {
        socketLock.withLock {
            cancellingQuery != nil && cancellingQuery == activeNativeQuery
                && cancellingSocketGeneration == socketGeneration && cancellationSocket >= 0
        }
    }

    /// Internal teardown cancels a native read, not the pending caller whose
    /// reconnect is performing that teardown. Scope this distinction to its thread.
    @objc(cancelActiveQuery:)
    public func cancelActiveQuery(_ operation: () -> Void) {
        let thread = ObjectIdentifier(Thread.current)
        let inserted = socketLock.withLock { nativeOnlyCancellationThreads.insert(thread).inserted }
        defer {
            if inserted { _ = socketLock.withLock { nativeOnlyCancellationThreads.remove(thread) } }
        }
        operation()
    }

    /// Own cancellation through the auxiliary KILL, including its connection setup.
    /// Query admission and reconnect both wait for this lease to end. Failure only
    /// interrupts the socket: the next use recovers after the native result is done.
    @objc(cancelQueryUsingKill:)
    public func cancelQuery(usingKill kill: (UInt) -> Bool) {
        let target = socketLock.withLock { () -> (query: UInt, socket: UInt, thread: UInt)? in
            guard cancellingQuery == nil else { return nil }
            guard let query = activeNativeQuery,
                  cancellationSocket >= 0, serverThreadID != 0 else {
                // A caller can stop during connection setup, before there is a
                // native statement to KILL. Keep that stop on the outer query.
                if !queryCancellationTokens.isEmpty
                    && !nativeOnlyCancellationThreads.contains(ObjectIdentifier(Thread.current)) {
                    queryCancellationGeneration &+= 1
                }
                return nil
            }
            cancellingQuery = query
            cancellingSocketGeneration = socketGeneration
            queryCancellationGeneration &+= 1
            return (query, socketGeneration, serverThreadID)
        }
        guard let target else { return }
        let succeeded = kill(target.thread)
        socketLock.withLock {
            if !succeeded && activeNativeQuery == target.query
                && socketGeneration == target.socket && cancellationSocket >= 0 {
                _ = Darwin.shutdown(cancellationSocket, SHUT_RDWR)
                recoveryRequired = true
            }
            cancellingQuery = nil
        }
    }

    /// Marks, for this thread only, that the session was refused rather than the work having
    /// simply returned nothing.
    private static let refusalMarker = "SAConnectionSessionAccess.theSessionWasRefused"

    /// Whether this thread's last attempt was refused the session, rather than its work running
    /// and returning nothing.
    ///
    /// Both come back as nothing, and a caller that cannot tell them apart would read a
    /// statement that was never sent as one that ran and changed nothing. Asked right after a
    /// call that came back empty, on the thread that made it.
    @objc public var theSessionWasRefusedToThisThread: Bool {
        (Thread.current.threadDictionary[Self.refusalMarker] as? Bool) ?? false
    }

    /// Records that a question about this connection has gone to the main thread.
    ///
    /// The session stays held while it is asked - what is being asked about is this session -
    /// but the answer can only come through the main thread. A main-thread caller that waited
    /// for the session meanwhile would be the one holding that answer up, so from here until
    /// the answer is in, such a caller is turned away instead of made to wait. Paired with
    /// ``noteTheQuestionWasAnswered()``, and nested questions are counted.
    @objc public func noteAQuestionWentToTheMainThread() {
        socketLock.withLock { questionsAwaitingTheMainThread += 1 }
    }

    /// Records that the question is answered and the main thread is free to wait again.
    @objc public func noteTheQuestionWasAnswered() {
        socketLock.withLock {
            if questionsAwaitingTheMainThread > 0 { questionsAwaitingTheMainThread -= 1 }
        }
    }

    /// Runs a query only after the current reconnect (including restoration) ends.
    @objc(performQuery:)
    public func performQuery(_ operation: () -> Any?) -> Any? {
        performQuery(operation, recover: { false })
    }

    @objc(performQuery:recover:)
    public func performQuery(_ operation: () -> Any?, recover: () -> Bool) -> Any? {
        guard acquire() else { return nil }
        socketLock.withLock { queryCancellationTokens.append(queryCancellationGeneration) }
        defer {
            socketLock.withLock { _ = queryCancellationTokens.popLast() }
            sessionLock.unlock()
        }
        let needsRecovery = takeRecoveryRequirement()
        if needsRecovery && !recover() { return nil }
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

        let needsRecovery = takeRecoveryRequirement()
        let completion = completionLock.withLock { (generation, reconnectSucceeded) }
        if !needsRecovery && completion.0 != previousGeneration && (completion.1 || !allowingRetries) {
            return completion.1
        }

        let succeeded = operation()
        completionLock.withLock {
            generation &+= 1
            reconnectSucceeded = succeeded
        }
        return succeeded
    }

    /// Whether the session has to be recovered before it is used again, using up that record.
    ///
    /// Asked once by the reconnect that acts on it: a read that was cut off cannot be carried
    /// on with, and the next use has to recover rather than pick it up. Taking the record is
    /// what keeps a second reconnect from recovering a session that has already been restored.
    /// - Returns: Whether recovery was required.
    private func takeRecoveryRequirement() -> Bool {
        socketLock.withLock {
            let required = recoveryRequired
            recoveryRequired = false
            return required
        }
    }

    /// Waiting must remain cancellable: disconnect can be waiting for a keepalive
    /// thread to exit. The main thread also services SSH authentication/teardown.
    private func acquire() -> Bool {
        Thread.current.threadDictionary[Self.refusalMarker] = false
        while !Thread.current.isCancelled {
            if sessionLock.try() {
                let ready = socketLock.withLock { cancellingQuery == nil && activeNativeQuery == nil }
                if ready { return true }
                sessionLock.unlock()
            }
            // A question about this connection is out, and the main thread is what answers it.
            // Waiting here would hold up that answer, and the session is not let go until the
            // answer is in - neither side would ever move. The caller is told there is no
            // session to be had instead, which is what the user is being asked about, and the
            // refusal is marked so it is not read as work that ran and did nothing.
            if Thread.isMainThread,
               socketLock.withLock({ questionsAwaitingTheMainThread > 0 }) {
                Thread.current.threadDictionary[Self.refusalMarker] = true
                return false
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
