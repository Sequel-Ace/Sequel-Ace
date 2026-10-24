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
    /// How many operations are between entering ``performQuery(_:recover:)`` and leaving it,
    /// on any thread - waiting for the session included. A stop recorded while one of them waits
    /// reaches it; one recorded while none is pending reaches nothing.
    private var pendingOperations = 0
    /// The native query the server already accepted a request to kill, while it is still running.
    private var queryWithAcceptedKill: UInt?
    private var questionsAwaitingTheMainThread = 0

    /// The key under which a thread keeps the tokens of the operations it is inside, outermost
    /// first. One stack per thread: an operation waiting for the session on one thread must not
    /// read the token of a query another thread is running.
    private static let operationTokensKey = "SAConnectionSessionAccess.operationTokens"

    /// The tokens of the operations the current thread is inside, outermost first.
    private var operationTokensOfThisThread: [UInt] {
        get { (Thread.current.threadDictionary[Self.operationTokensKey] as? [UInt]) ?? [] }
        set { Thread.current.threadDictionary[Self.operationTokensKey] = newValue.isEmpty ? nil : newValue }
    }

    /// Gives the operation this thread is entering its identity: the cancellation generation as
    /// it stands now. A stop recorded from here on - while the operation waits for the session,
    /// or runs - moves the generation past it; one recorded before it began does not.
    private func enterOperation() {
        let token = socketLock.withLock { () -> UInt in
            pendingOperations += 1
            return queryCancellationGeneration
        }
        operationTokensOfThisThread.append(token)
    }

    /// Ends the operation this thread entered last.
    private func leaveOperation() {
        socketLock.withLock { pendingOperations -= 1 }
        var tokens = operationTokensOfThisThread
        _ = tokens.popLast()
        operationTokensOfThisThread = tokens
    }

    /// Remember cancellation across setup queries run by the interrupted query's
    /// reconnect. Each nested query has its own token; it cannot erase its caller's.
    @objc public func recordQueryCancellation() {
        socketLock.withLock { queryCancellationGeneration &+= 1 }
    }

    @objc public var currentQueryWasCancelled: Bool {
        guard let token = operationTokensOfThisThread.last else {
            return false
        }
        return socketLock.withLock { token != queryCancellationGeneration }
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
        let token = operationTokensOfThisThread.last
        return socketLock.withLock {
            nativeQueryGeneration &+= 1
            activeNativeQuery = nativeQueryGeneration
            return token.map { $0 == queryCancellationGeneration } ?? true
        }
    }

    /// Streaming results keep this record until their final native-lock release.
    @objc public func endNativeQuery() {
        socketLock.withLock {
            if queryWithAcceptedKill == activeNativeQuery {
                queryWithAcceptedKill = nil
            }
            activeNativeQuery = nil
        }
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

    /// Reserves the cancellation of the native query that is running, and records the request to
    /// stop whatever is pending.
    ///
    /// The lease keeps the books: which query the cancellation is about, which session it runs
    /// in, that nothing else gets the session while a request is on its way, and whether the
    /// server has already accepted a request for that query. What to do when the server cannot
    /// be reached is the caller's - it holds the grace period the query is given before its
    /// socket is closed, and it leaves a query whose kill the server accepted to the server.
    ///
    /// A caller can stop during connection setup, or while an operation still waits for the
    /// session, before there is a native statement to KILL. Every stop is recorded against the
    /// operations pending now, outermost query included, and reaches nothing that begins later -
    /// also a stop asked for while another's request is still on its way, since an operation can
    /// have begun waiting for the session in between.
    /// - Returns: What this cancellation was given. A hold that does not hold the query belongs
    ///   to another cancellation already under way for it, whose request may yet be accepted;
    ///   the caller then leaves that query's socket alone.
    @objc public func reserveCancellation() -> SACancellationHold {
        socketLock.withLock {
            guard cancellingQuery == nil else {
                // A request for the query is already on its way, and no second one is sent. The
                // stop still reaches whatever is pending: an operation that began waiting for the
                // session after the first stop, which that stop could not know of, must not send
                // its statement once the request is answered and the session is free.
                recordStopAgainstPendingOperations()
                return SACancellationHold(query: 0, session: 0, serverThread: 0,
                                          holdsTheQuery: false, killWasAlreadyAccepted: false)
            }
            guard let query = activeNativeQuery,
                  cancellationSocket >= 0, serverThreadID != 0 else {
                // A caller can stop during connection setup, before there is a
                // native statement to KILL. Keep that stop on the outer query.
                recordStopAgainstPendingOperations()
                return SACancellationHold(query: 0, session: 0, serverThread: 0,
                                          holdsTheQuery: true, killWasAlreadyAccepted: false)
            }
            if queryWithAcceptedKill == query {
                // The server has the request already. Reporting a failure instead - which is
                // what sending nothing used to amount to - would have the caller close the
                // query's socket, ending the session and rolling back a transaction open in it.
                return SACancellationHold(query: query, session: socketGeneration, serverThread: 0,
                                          holdsTheQuery: true, killWasAlreadyAccepted: true)
            }
            cancellingQuery = query
            cancellingSocketGeneration = socketGeneration
            queryCancellationGeneration &+= 1
            return SACancellationHold(query: query, session: socketGeneration, serverThread: serverThreadID,
                                      holdsTheQuery: true, killWasAlreadyAccepted: false)
        }
    }

    /// Records a stop against the operations pending now, so that none of them sends its statement
    /// once it has the session. Called under the socket lock. A thread cancelling a native read of
    /// its own - a reconnect's teardown - is not stopping the caller it works for, and records
    /// nothing here.
    private func recordStopAgainstPendingOperations() {
        if pendingOperations > 0
            && !nativeOnlyCancellationThreads.contains(ObjectIdentifier(Thread.current)) {
            queryCancellationGeneration &+= 1
        }
    }

    /// Gives a reservation back, once the request has been sent or could not be.
    /// - Parameters:
    ///   - hold: What ``reserveCancellation()`` gave.
    ///   - killAccepted: Whether the server accepted the request, which is remembered for the
    ///     next cancellation of the same query for as long as it runs.
    @objc(completeCancellation:killAccepted:)
    public func completeCancellation(_ hold: SACancellationHold, killAccepted: Bool) {
        socketLock.withLock {
            guard hold.holdsTheQuery, hold.query != 0, cancellingQuery == hold.query else { return }
            if killAccepted {
                queryWithAcceptedKill = hold.query
            }
            cancellingQuery = nil
        }
    }

    /// Shuts the socket of a native query down, provided it is still the one running on the
    /// session it was running on: the step a caller takes once its grace period is over and the
    /// server has not ended the query. The read on it fails at once, and the next use recovers.
    ///
    /// Both the query and the session are checked under the lock. The query can have finished and
    /// another taken the session since the stop was asked for, and a reconnect can have put a new
    /// session in place; ending either would take a session nobody asked about, and roll back a
    /// transaction open in it.
    /// - Parameters:
    ///   - query: The native query the stop was about, from its hold.
    ///   - session: The session it was running in, from the same hold.
    /// - Returns: Whether the socket was shut down.
    @objc(shutDownSocketOfQuery:onSession:)
    @discardableResult
    public func shutDownSocket(ofQuery query: UInt, onSession session: UInt) -> Bool {
        socketLock.withLock {
            guard query != 0, activeNativeQuery == query, socketGeneration == session,
                  cancellationSocket >= 0 else {
                return false
            }
            _ = Darwin.shutdown(cancellationSocket, SHUT_RDWR)
            recoveryRequired = true
            return true
        }
    }

    /// Own cancellation through the auxiliary KILL, including its connection setup.
    /// Query admission and reconnect both wait for this lease to end.
    ///
    /// The composed form of ``reserveCancellation()`` and ``completeCancellation(_:killAccepted:)``,
    /// for a caller that sends its request at once and leaves what follows to the lease's books:
    /// a request the server refused is not acted on here - closing the socket is the caller's,
    /// through ``shutDownSocket(ofQuery:onSession:)``.
    /// - Parameter kill: Sends the request for the server session it is given, and reports whether
    ///   the server accepted it. Not called when this cancellation does not own the query, and not
    ///   when there is no native statement to send one for.
    /// - Returns: Whether this cancellation is the one the query belongs to.
    @discardableResult
    @objc(cancelQueryUsingKill:)
    public func cancelQuery(usingKill kill: (UInt) -> Bool) -> Bool {
        let hold = reserveCancellation()
        guard hold.holdsTheQuery else { return false }
        guard hold.serverThread != 0 else { return true }
        let accepted = kill(hold.serverThread)
        completeCancellation(hold, killAccepted: accepted)
        return true
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
        // The operation exists from here, before it waits for the session: a stop asked for while
        // it waits - behind a reconnect, say - reaches it, and its statement is never sent. A stop
        // asked for before it began does not.
        enterOperation()
        defer { leaveOperation() }
        guard acquire() else { return nil }
        // Anything refused while this call waited was somebody else's call, delivered by the
        // run loop this one pumped. It has been reported where it happened.
        forgetAnyRefusal()
        defer {
            // And anything refused inside the work answers for itself, not for this call.
            forgetAnyRefusal()
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

/// What one cancellation was given by the lease: the native query it is about, the session that
/// query runs in, and whether this cancellation is the one that holds it.
///
/// Asking to kill a query has three outcomes, and a single yes or no could only ever report two
/// of them: a request is to be sent, the server has already accepted one for the same query, or
/// another cancellation holds the query and its request may yet be accepted. The last two used to
/// read as a failure, which a caller acts on by closing the query's socket.
@objc(SACancellationHold)
public final class SACancellationHold: NSObject {

    /// The native query the cancellation is about, as the lease numbers them; 0 when there is none.
    @objc public let query: UInt

    /// The session that query runs in - the lease's ``SAConnectionSessionAccess/socketToken`` -
    /// or 0 when there is no query.
    @objc public let session: UInt

    /// The server's number for that session, to send the request for; 0 when nothing is to be sent.
    @objc public let serverThread: UInt

    /// Whether this cancellation holds the query. When it does not, another cancellation for the
    /// same query holds it and its request may yet be accepted: the caller leaves the socket alone.
    @objc public let holdsTheQuery: Bool

    /// Whether the server already accepted a request to kill this query, from an earlier
    /// cancellation. Nothing is sent, and the socket is left to the server, which is ending the
    /// statement on its own time.
    @objc public let killWasAlreadyAccepted: Bool

    /// - Parameters:
    ///   - query: The native query, or 0 for none.
    ///   - session: The session it runs in, or 0.
    ///   - serverThread: The session to send the request for, or 0 for none.
    ///   - holdsTheQuery: Whether this cancellation holds the query.
    ///   - killWasAlreadyAccepted: Whether a request for the same query was already accepted.
    init(query: UInt, session: UInt, serverThread: UInt, holdsTheQuery: Bool, killWasAlreadyAccepted: Bool) {
        self.query = query
        self.session = session
        self.serverThread = serverThread
        self.holdsTheQuery = holdsTheQuery
        self.killWasAlreadyAccepted = killWasAlreadyAccepted
        super.init()
    }
}
