//
//  SAConnectionCancellation.swift
//  SPMySQLFramework
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//
//  More info at <https://github.com/Sequel-Ace/Sequel-Ace>
//

import Foundation

/// What a connection lets its cancellation logic do to it, without handing over its internals.
@objc(SAConnectionCancellationHost)
public protocol SAConnectionCancellationHost: AnyObject {

    /// The lease that keeps the session's books: the native query that runs, the session it runs
    /// in, and the socket to end the wait on.
    @objc var sessionAccess: SAConnectionSessionAccess { get }

    /// Asks the server to kill the query running in this server session, over a connection of its own.
    /// - Parameter serverThread: The server's number for the session.
    /// - Returns: Whether the server accepted the request.
    @objc(killQueryOnServerThread:)
    func killQuery(onServerThread serverThread: UInt) -> Bool

    /// Whether the session last reported an open transaction.
    @objc var sessionHasOpenTransaction: Bool { get }

    /// Marks the query that holds the connection as cancelled, where callers look for it.
    @objc func markRunningQueryCancelled()
}

/// How a connection stops the query it is running, or the operation still waiting to run one.
///
/// Stopping takes three steps, in this order. The request is recorded at once, under the lease's
/// lock and without waiting on anything, so that an operation still waiting for the session never
/// sends its statement and a query losing its connection meanwhile does not reconnect and run its
/// statement a second time. The server is asked to kill the query, over a connection of its own,
/// which a server that is still there answers in milliseconds. And if the query is still waiting
/// once a grace period is over, its socket is shut down, because a server that has gone away
/// answers neither the query nor the request to kill it.
///
/// The lease keeps the books - which query, which session, whether another request is already on
/// its way or was accepted - and every step names the query and the session it is about, so a
/// query that finished and another that took its place are never confused: that would take a
/// session nobody asked about, and roll back a transaction open in it.
@objc(SAConnectionCancellation)
public final class SAConnectionCancellation: NSObject {

    /// How long a request to kill a query is given before the query's socket is shut down, in seconds.
    public static let shutdownGrace: TimeInterval = 2

    private weak var host: SAConnectionCancellationHost?

    /// Creates the cancellation logic for one connection.
    /// - Parameter host: The connection. It is not retained.
    @objc(initWithHost:)
    public init(host: SAConnectionCancellationHost) {
        self.host = host
        super.init()
    }

    /// Stops the query the connection is running, or the operation still waiting to run one.
    /// - Parameter synchronously: Whether the request to the server is made before this returns.
    ///   Callers that rely on the request having gone out ask for that; the main thread never
    ///   should, since reaching the server can take as long as the query itself. The grace period
    ///   runs from this call either way, not from the server's answer.
    @objc(requestCancellationSynchronously:)
    public func requestCancellation(synchronously: Bool) {
        guard let host else {
            return
        }
        let lease = host.sessionAccess

        // Recorded first, and without waiting: the stop reaches whatever is pending, outermost
        // query included, and names the native query and the session to act on from here.
        let hold = lease.reserveCancellation()
        guard hold.holdsTheQuery, hold.query != 0 else {
            // Nothing native is running - the stop is recorded against the operations waiting
            // for the session, and there is nothing to kill or to shut down - or another stop for
            // the same query holds it and its request may yet be accepted, so nothing here may act
            // on a failure it never observed.
            return
        }

        // The query counts as cancelled from here, however its statement ends: callers running a
        // batch stop on this.
        host.markRunningQueryCancelled()

        guard !hold.killWasAlreadyAccepted else {
            // The server is ending the statement on its own time; the socket is left to it.
            return
        }

        // Once the grace period is over, the socket is shut down unless the server accepted the
        // kill for a session with an open transaction. Reaching the server can take longer than
        // the grace period on a slow link. With a transaction open the decision then waits for
        // the answer; without one the answer changes nothing, and a route that has gone would
        // only make the socket stay open for as long as the kill takes to give up.
        let attempt = SAKillAttempt()
        let decideAfterGrace: (_ killAccepted: Bool) -> Void = { [weak host] killAccepted in
            guard let host,
                  Self.closesSocketAfterGrace(killAccepted: killAccepted,
                                              sessionHasOpenTransaction: host.sessionHasOpenTransaction) else {
                return
            }
            // The lease checks that it is still that query on that session; the read on it then
            // fails at once, and the next use recovers the session.
            if lease.shutDownSocket(ofQuery: hold.query, onSession: hold.session) {
                host.markRunningQueryCancelled()
            }
        }
        let askServer: () -> Void = { [weak host] in
            let accepted = host?.killQuery(onServerThread: hold.serverThread) == true
            lease.completeCancellation(hold, killAccepted: accepted)
            if attempt.finish(accepted: accepted) {
                decideAfterGrace(accepted)
            }
        }
        // The grace period starts now, before the server is asked, because asking it can take
        // longer than the grace period and a synchronous request is waited for here. Counting from
        // the answer instead would keep the query's socket open for the side connection's own
        // timeouts and the grace period on top, which is exactly the wait this is meant to bound.
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + Self.shutdownGrace) { [weak host] in
            let waitsForAnswer = host?.sessionHasOpenTransaction ?? false
            if let accepted = attempt.endGrace(waitingForAnswer: waitsForAnswer) {
                decideAfterGrace(accepted)
            }
        }

        if synchronously {
            askServer()
        } else {
            DispatchQueue.global(qos: .userInitiated).async(execute: askServer)
        }
    }

    /// Whether a query still waiting once the grace period is over has its socket shut down.
    ///
    /// Shutting the socket down ends the session, and with it a transaction the session has open.
    /// A server that accepted the kill ends the statement on its own - rolling back a large one
    /// can take a while - so such a session is left to it. Without an accepted kill the route is
    /// presumed gone, and the socket is shut down.
    /// - Parameters:
    ///   - killAccepted: Whether the server accepted the request to kill the query.
    ///   - sessionHasOpenTransaction: Whether the session last reported an open transaction.
    /// - Returns: Whether to shut the socket down.
    static func closesSocketAfterGrace(killAccepted: Bool, sessionHasOpenTransaction: Bool) -> Bool {
        return !(killAccepted && sessionHasOpenTransaction)
    }

    /// Whether the session a replacement mark names is closed now, or kept because something is
    /// going on in it.
    ///
    /// The mark is made when a session may be out of step with what the connection knows of it,
    /// and acted on when the session is next wanted - which can be much later. A query that took
    /// the connection over in between can have opened a transaction of its own: closing the
    /// session then rolls that work back without a word, while whoever opened it is still going,
    /// and what the mark guards against is not worth that. The mark stays, so the session is still
    /// replaced once nothing is open in it. A session the protocol cannot be trusted on is a
    /// different matter: a ping cut off before its answer came may still get that answer, and the
    /// next statement would read it as its own result. Keeping such a session to save a
    /// transaction would hand that transaction's caller somebody else's reply. It goes, and the
    /// transaction is lost with it and reported like any other loss.
    /// - Parameters:
    ///   - sessionHasOpenTransaction: Whether the session reports a transaction open now.
    ///   - sessionIsProtocolInvalid: Whether an answer nobody read may still be on its way.
    /// - Returns: Whether to close it now.
    @objc(markedSessionIsClosedNowWithOpenTransaction:sessionIsProtocolInvalid:)
    public static func markedSessionIsClosedNow(sessionHasOpenTransaction: Bool,
                                                sessionIsProtocolInvalid: Bool) -> Bool {
        return sessionIsProtocolInvalid || !sessionHasOpenTransaction
    }

    /// Whether a session is replaced after a ping to it was cut off.
    ///
    /// A ping stopped while it waited - because it ran out of time - may still have its answer on
    /// the way. The next statement would read that answer as its own, and every answer after it
    /// would belong to the statement before. A ping that got its answer leaves nothing behind;
    /// one that did not, whatever else happens, leaves the session unusable.
    /// - Parameters:
    ///   - pingWasCutOff: Whether the ping was cancelled or its thread stopped.
    ///   - pingSucceeded: Whether the ping got its answer.
    /// - Returns: Whether to replace the session before it is used again.
    @objc(replacesSessionAfterPingCutOff:pingSucceeded:)
    public static func replacesSessionAfterPing(cutOff pingWasCutOff: Bool, pingSucceeded: Bool) -> Bool {
        return pingWasCutOff && !pingSucceeded
    }
}

/// One request to kill a query: whether the server has answered it, and who decides what happens
/// to the query's socket - the end of the grace period, or an answer that comes after it. Exactly
/// one of them decides.
final class SAKillAttempt {
    private let lock = NSLock()
    private var answer: Bool?
    private var answerDecides = false
    private var decided = false

    /// Records the server's answer.
    /// - Parameter accepted: Whether the server accepted the request.
    /// - Returns: Whether this answer decides now, because the grace period ended waiting for it.
    func finish(accepted: Bool) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        answer = accepted
        guard answerDecides, !decided else {
            return false
        }
        decided = true
        return true
    }

    /// Records that the grace period is over.
    /// - Parameter waitingForAnswer: Whether an answer that has not come yet is to be waited for.
    /// - Returns: What to decide with now - the answer if it has come, "not accepted" if it is not
    ///   waited for - or nil if the answer decides when it comes.
    func endGrace(waitingForAnswer: Bool) -> Bool? {
        lock.lock()
        defer { lock.unlock() }
        if let answer {
            decided = true
            return answer
        }
        if waitingForAnswer {
            answerDecides = true
            return nil
        }
        decided = true
        return false
    }
}
