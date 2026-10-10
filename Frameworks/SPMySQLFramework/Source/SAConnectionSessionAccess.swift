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

    /// Runs `work` while `socketToken` still names the current session, under the lock a new
    /// session is put in place under.
    ///
    /// Reading ``socketToken`` and then acting on the answer is not the same thing: a reconnect
    /// can finish in between, and what was recorded about the session that has gone would be
    /// recorded against the one that replaced it - which is how a healthy session comes to be
    /// closed, and a transaction somebody else had just opened rolled back.
    /// - Parameters:
    ///   - socketToken: ``socketToken`` as it was when the caller started out.
    ///   - work: What to record. It runs under the lock, so it must not wait for anything.
    /// - Returns: Whether it ran, which is whether that session is still the current one.
    @objc(whileStillOnSocket:perform:)
    @discardableResult
    public func whileStillOnSocket(_ socketToken: UInt, perform work: () -> Void) -> Bool {
        socketLock.withLock {
            guard socketGeneration == socketToken else { return false }
            work()
            return true
        }
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
    ///
    /// - Parameter kill: Sends the request for the server session it is given, and reports whether
    ///   the server accepted it. Not called when this cancellation does not own the query.
    /// - Returns: Whether this cancellation is the one the query belongs to. `false` says another
    ///   cancellation for the same query already holds it and its request may still be accepted -
    ///   so the caller must leave that query's socket alone, where closing it would end the
    ///   session and roll back a transaction open in it on the strength of a failure this call
    ///   never observed. `true` when the request went out, and when there was no native statement
    ///   to send one for.
    @discardableResult
    @objc(cancelQueryUsingKill:)
    public func cancelQuery(usingKill kill: (UInt) -> Bool) -> Bool {
        var anotherCancellationHoldsTheQuery = false
        let target = socketLock.withLock { () -> (query: UInt, socket: UInt, thread: UInt)? in
            guard cancellingQuery == nil else {
                anotherCancellationHoldsTheQuery = true
                return nil
            }
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
        guard let target else { return !anotherCancellationHoldsTheQuery }
        // What happens when the server cannot be reached is the caller's: it holds the grace
        // period the query is given before its socket is closed, and it knows whether the server
        // accepted the kill for a session with a transaction open - one that must be left to end
        // its own statement rather than have its session taken away. This reserves the
        // cancellation, hands out the thread to kill, and lets go again.
        _ = kill(target.thread)
        socketLock.withLock {
            cancellingQuery = nil
        }
        return true
    }

    /// Records that the caller ended the native read itself, so the next use recovers.
    ///
    /// The decision belongs to the caller, for the reasons above; what is kept here is the
    /// consequence - a read that was cut off cannot simply be carried on with.
    ///
    /// It is the session that was cut off that has to recover. A reconnect can put a new one in
    /// place between the socket closing and this being told about it, and marking that one would
    /// send a session nothing is wrong with through a reconnect it does not need - rolling back a
    /// transaction it had just opened. The token names the session the caller closed.
    /// - Parameter socketToken: ``socketToken`` as it was when the caller closed the socket.
    @objc(noteCancellationEndedTheNativeReadOnSocket:)
    public func noteCancellationEndedTheNativeRead(onSocket socketToken: UInt) {
        socketLock.withLock {
            guard socketGeneration == socketToken else { return }
            recoveryRequired = true
        }
    }

    /// Marks, for this thread only, that the session was refused rather than the work having
    /// simply returned nothing.
    private static let refusalMarker = "SAConnectionSessionAccess.theSessionWasRefused"

    /// Takes the record of whether the call this thread just made was refused the session,
    /// rather than its work running and returning nothing.
    ///
    /// Both come back as nothing, and a caller that cannot tell them apart would read a
    /// statement that was never sent as one that ran and changed nothing. Asked right after a
    /// call that came back empty, on the thread that made it.
    ///
    /// It speaks for that one call. Waiting for the session pumps the main thread's run loop,
    /// and a query delivered in there can be refused while this one goes on to succeed; a
    /// refusal from inside is cleared rather than left to answer for its caller. Reading it
    /// takes it, so a refusal nobody asked about cannot answer for a later call either.
    /// - Returns: Whether that call was refused.
    @objc public func takeTheRefusalOfThisThreadsLastCall() -> Bool {
        let refused = (Thread.current.threadDictionary[Self.refusalMarker] as? Bool) ?? false
        forgetAnyRefusal()
        return refused
    }

    /// Whether a question about the connection is out to the main thread and still unanswered.
    ///
    /// The thread that asked keeps the session until it has an answer. A caller that would hand
    /// its work to another thread asks this first: handing it over does not get around the wait,
    /// it only changes who waits, and the main thread is still the one that has to answer.
    @objc public var aQuestionAwaitsTheMainThread: Bool {
        socketLock.withLock { questionsAwaitingTheMainThread > 0 }
    }

    /// Forgets a refusal this thread was told about earlier, so that what is read after this call
    /// can only describe the call that follows it.
    ///
    /// A refusal is marked on the thread that was turned away, and only the statement path reads
    /// that mark. The connection's other work - a check, a session replacement - is turned away by
    /// the same gate and reads nothing, so a mark left standing there would be read by the next
    /// statement on that thread and reported as its own.
    @objc public func forgetAnyRefusalOfThisThread() {
        forgetAnyRefusal()
    }

    /// Records that this thread's call was refused the session, for a caller that turned it away
    /// before it reached ``performQuery(_:recover:)``.
    ///
    /// The refusal has to read the same whichever side of a hand-off turned the call away: a
    /// statement that was never sent must not be taken for one that ran and returned nothing.
    @objc public func noteThisThreadsCallWasRefused() {
        Thread.current.threadDictionary[Self.refusalMarker] = true
    }

    /// Forgets a refusal recorded on this thread, so it cannot speak for a later call.
    private func forgetAnyRefusal() {
        Thread.current.threadDictionary[Self.refusalMarker] = false
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
        // Anything refused while this call waited was somebody else's call, delivered by the
        // run loop this one pumped. It has been reported where it happened.
        forgetAnyRefusal()
        socketLock.withLock { queryCancellationTokens.append(queryCancellationGeneration) }
        defer {
            // And anything refused inside the work answers for itself, not for this call.
            forgetAnyRefusal()
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
        forgetAnyRefusal()
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
