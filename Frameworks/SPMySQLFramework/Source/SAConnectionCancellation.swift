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

    /// The number of the query that holds the connection, or held it last.
    @objc var currentQueryGeneration: UInt { get }

    /// Keeps the next connection attempt short: the user has said they will not wait.
    @objc(noteUserEndedWait)
    func noteUserEndedWait()

    /// Marks the query that holds the connection as cancelled.
    @objc(markRunningQueryCancelled)
    func markRunningQueryCancelled()

    /// Asks the server to kill the query with this number, over a connection of its own.
    /// - Parameter generation: The query to kill.
    /// - Returns: Whether the server accepted the request.
    @objc(killQueryOverSideConnectionForGeneration:)
    func killQueryOverSideConnection(forGeneration generation: UInt) -> Bool

    /// Whether the session last reported an open transaction.
    @objc var sessionHasOpenTransaction: Bool { get }

    /// Takes the connection, provided nothing else holds it.
    /// - Returns: Whether the connection is now held.
    @objc(holdConnectionIfFree)
    func holdConnectionIfFree() -> Bool

    /// Gives back a connection taken with ``holdConnectionIfFree()``.
    @objc(releaseHeldConnection)
    func releaseHeldConnection()

    /// Records that the work on the connection was cancelled, where callers look for the outcome.
    @objc(recordWorkAsCancelled)
    func recordWorkAsCancelled()

    /// Closes the session the connection holds, if it holds one; the connection then counts as lost.
    @objc(closeSessionIfConnected)
    func closeSessionIfConnected()
}

/// What becomes of a connection whose reconnect was cut short by a cancelled thread.
@objc(SAConnectionRecoveryAction)
public enum SAConnectionRecoveryAction: Int {
    /// Nothing to do.
    case none
    /// The connection stays disconnected, but counts as lost so the next query reconnects.
    case markLost
    /// A connection came up after all; it is closed and counts as lost.
    case discardAndMarkLost
}

/// How a connection stops work that nobody wants any more.
///
/// Stopping a query takes three steps, in this order. The request is recorded at once, so that the
/// query does not retry itself while anything slow happens. The server is asked to kill it, over a connection
/// of its own, which a server that is still there answers in milliseconds. And if the query is
/// still waiting a little later, its socket is closed, because a server that has gone away answers
/// neither the query nor the request to kill it. Every step names the query it is about, and only
/// ever reaches that one.
@objc(SAConnectionCancellation)
public final class SAConnectionCancellation: NSObject {

    /// How long a request to kill a query is given before the query's socket is closed, in seconds.
    public static let shutdownGrace: TimeInterval = 2

    private weak var host: SAConnectionCancellationHost?
    private let inFlightQuery: SAInFlightQuery

    /// Creates the cancellation logic for one connection.
    /// - Parameters:
    ///   - host: The connection. It is not retained.
    ///   - inFlightQuery: The connection's record of the query waiting on the server.
    @objc(initWithHost:inFlightQuery:)
    public init(host: SAConnectionCancellationHost, inFlightQuery: SAInFlightQuery) {
        self.host = host
        self.inFlightQuery = inFlightQuery
        super.init()
    }

    /// Stops the work the user has just stopped waiting for.
    ///
    /// Only a query that work started is asked to stop. Work still waiting for the connection -
    /// behind a query another thread runs, say - has not started one, and that other query is not
    /// what the user stopped waiting for; the work itself never runs once it has been given up on.
    /// - Parameter workCoordinator: Where that work runs; it is asked to stop too.
    @objc(userStoppedWaitingWithWorkCoordinator:)
    public func userStoppedWaiting(workCoordinator: SAConnectionWorkCoordinator?) {
        guard let host else {
            return
        }
        host.noteUserEndedWait()
        let workerThread = workCoordinator?.currentWorkerThread
        workCoordinator?.abandonWorkForUserStop()
        guard let workerThread else {
            return
        }
        requestCancellation(ofGeneration: inFlightQuery.latestGeneration(ifTakenOn: workerThread), synchronously: false)
    }

    /// Stops the query with this number: records the request, asks the server to kill it, and closes
    /// its socket if it is still waiting once the grace period is over.
    /// - Parameters:
    ///   - generation: The query to stop, as the connection numbered it when stopping was asked for.
    ///   - synchronously: Whether the request to the server is made before this returns. Callers
    ///     that rely on the request having gone out ask for that; the main thread never should,
    ///     since reaching the server can take as long as the query itself.
    @objc(requestCancellationOfGeneration:synchronously:)
    public func requestCancellation(ofGeneration generation: UInt, synchronously: Bool) {
        guard generation != 0 else {
            return
        }

        // Recorded before anything slow happens: a query that loses its connection meanwhile would
        // otherwise reconnect and run its statement a second time. The query asks for this record
        // itself, so recording it never waits on anything - this may well be the main thread.
        inFlightQuery.requestCancellation(ofGeneration: generation)

        // Once the grace period is over, the socket is closed unless the server accepted the kill for
        // a session with an open transaction. Reaching the server can take longer than the grace
        // period on a slow link. With a transaction open the decision then waits for the answer;
        // without one the answer changes nothing, and a route that has gone would only make the
        // socket stay open for as long as the kill takes to give up.
        let attempt = SAKillAttempt()
        let decideAfterGrace: (_ killAccepted: Bool) -> Void = { [weak self] killAccepted in
            guard let self,
                  Self.closesSocketAfterGrace(killAccepted: killAccepted,
                                              sessionHasOpenTransaction: self.host?.sessionHasOpenTransaction ?? false) else {
                return
            }
            self.closeSocket(ifGenerationIsWaiting: generation)
        }
        let askServer: () -> Void = { [weak self] in
            let accepted = self?.host?.killQueryOverSideConnection(forGeneration: generation) == true
            if attempt.finish(accepted: accepted) {
                decideAfterGrace(accepted)
            }
        }
        if synchronously {
            askServer()
        } else {
            DispatchQueue.global(qos: .userInitiated).async(execute: askServer)
        }

        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + Self.shutdownGrace) { [weak self] in
            let waitsForAnswer = self?.host?.sessionHasOpenTransaction ?? false
            if let accepted = attempt.endGrace(waitingForAnswer: waitsForAnswer) {
                decideAfterGrace(accepted)
            }
        }
    }

    /// Closes the socket of the query with this number, if it is still waiting on the server.
    /// - Parameter generation: The query that was asked to stop.
    private func closeSocket(ifGenerationIsWaiting generation: UInt) {
        inFlightQuery.closeSocket(ifGenerationIsWaiting: generation) { [weak self] in
            // The query ends because it was asked to, so it counts as cancelled rather than
            // failed, and the attempt that follows does not make anybody wait again.
            self?.host?.markRunningQueryCancelled()
            self?.host?.noteUserEndedWait()
        }
    }

    /// Whether a query still waiting once the grace period is over has its socket closed.
    ///
    /// Closing the socket ends the session, and with it a transaction the session has open. A server
    /// that accepted the kill ends the statement on its own - rolling back a large one can take a
    /// while - so such a session is left to it. Without an accepted kill the route is presumed gone,
    /// and the socket is closed as before.
    /// - Parameters:
    ///   - killAccepted: Whether the server accepted the request to kill the query.
    ///   - sessionHasOpenTransaction: Whether the session last reported an open transaction.
    /// - Returns: Whether to close the socket.
    static func closesSocketAfterGrace(killAccepted: Bool, sessionHasOpenTransaction: Bool) -> Bool {
        return !(killAccepted && sessionHasOpenTransaction)
    }

    /// Settles the connection after work that nobody waited for has finished after all.
    ///
    /// The caller was told the work was cancelled, and that has to stay true. The work may also
    /// have changed the session without the connection's record of it changing along. Both are
    /// handled while the connection is held, and only if no other query has taken it since.
    /// - Parameter generation: The query that held the connection when the waiting ended.
    @objc(settleAbandonedWorkFromGeneration:)
    public func settleAbandonedWork(fromGeneration generation: UInt) {
        guard let host, host.holdConnectionIfFree() else {
            return
        }
        defer {
            host.releaseHeldConnection()
        }
        guard host.currentQueryGeneration == generation else {
            return
        }
        host.recordWorkAsCancelled()
        host.closeSessionIfConnected()
    }

    /// Whether putting a stored character set back only has to change the connection's record of it.
    ///
    /// A connection without a usable session - lost in the background, or on its way between two
    /// sessions - connects afresh with the character set on record. So does one whose last work
    /// nobody waited for: that work closes its session once it finishes, and the session is not used
    /// again in any case. Telling the server as well would only wait behind the abandoned work, or
    /// reconnect, for a session that is on its way out.
    ///
    /// Until that session is gone, its handle may still follow the temporary character set, so
    /// values are not escaped with it: the connection escapes them for the character set on record,
    /// which the next session's handshake uses. A session with an open transaction is kept, and is
    /// told the character set as before.
    /// - Parameters:
    ///   - afterAbandonedWork: Whether the calling thread stopped waiting for the work it ran last.
    ///   - hasNoUsableSession: Whether the connection has no session to tell.
    ///   - sessionHasOpenTransaction: Whether the session last reported an open transaction.
    /// - Returns: Whether the record alone is to be changed.
    @objc(storedEncodingOnlyNeedsRecordingAfterAbandonedWork:hasNoUsableSession:sessionHasOpenTransaction:)
    public static func storedEncodingOnlyNeedsRecording(afterAbandonedWork: Bool,
                                                        hasNoUsableSession: Bool,
                                                        sessionHasOpenTransaction: Bool) -> Bool {
        if hasNoUsableSession {
            return true
        }
        return afterAbandonedWork && !keepsSessionOfAbandonedWork(sessionHasOpenTransaction: sessionHasOpenTransaction)
    }

    /// Whether the session of work nobody waited for is kept rather than closed and replaced.
    ///
    /// Closing that session keeps it from being used with changes the connection does not know
    /// about. An open transaction weighs more: closing the session would roll it back without a word,
    /// and a later `COMMIT` would succeed on the new session without committing anything. Such a
    /// session is kept; stopping ends only the statement that was running. A session whose route
    /// has gone is lost either way.
    /// - Parameter sessionHasOpenTransaction: Whether the session last reported an open transaction.
    /// - Returns: Whether to keep the session.
    @objc(keepsSessionOfAbandonedWorkWithOpenTransaction:)
    public static func keepsSessionOfAbandonedWork(sessionHasOpenTransaction: Bool) -> Bool {
        return sessionHasOpenTransaction
    }

    /// Whether asking a connection if it is connected restores a session lost in the background first.
    ///
    /// Restoring it waits for the network. Off the main thread that is what callers have always
    /// relied on; on the main thread it would freeze the interface, so the connection answers that
    /// it is connected and leaves the restoring to the next query, which waits without freezing.
    /// - Parameter onMainThread: Whether the question is asked on the main thread.
    /// - Returns: Whether to restore the session before answering.
    @objc(restoresLostSessionWhenAskedIfConnectedOnMainThread:)
    public static func restoresLostSessionWhenAskedIfConnected(onMainThread: Bool) -> Bool {
        return !onMainThread
    }

    /// Decides what becomes of a connection whose reconnect ended while its thread was cancelled.
    ///
    /// Cancelling there means the user stopped waiting, not that they asked for the connection to
    /// close. A connection left merely disconnected would answer every later query with "no
    /// connection" even once the network is back; one that counts as lost reconnects on next use.
    /// A connection that came up anyway cannot have its session restored - the restoring queries
    /// are work nobody waits for, and do not run - so it is closed rather than used half-restored.
    /// - Parameters:
    ///   - threadCancelled: Whether the thread doing the reconnect was cancelled.
    ///   - userDisconnected: Whether the user asked for the connection to close.
    ///   - isConnected: Whether a connection came up.
    ///   - isDisconnected: Whether the connection is disconnected.
    ///   - mayDisconnect: Whether the caller is in a position to close a connection.
    /// - Returns: What to do with the connection.
    @objc(recoveryAfterCancelledReconnectWithThreadCancelled:userDisconnected:isConnected:isDisconnected:mayDisconnect:)
    public static func recoveryAfterCancelledReconnect(threadCancelled: Bool,
                                                       userDisconnected: Bool,
                                                       isConnected: Bool,
                                                       isDisconnected: Bool,
                                                       mayDisconnect: Bool) -> SAConnectionRecoveryAction {
        guard threadCancelled, !userDisconnected else {
            return .none
        }
        if isConnected {
            return mayDisconnect ? .discardAndMarkLost : .none
        }
        return isDisconnected ? .markLost : .none
    }
}

/// One request to kill a query: whether the server has answered it, and who decides what happens to
/// the query's socket - the end of the grace period, or an answer that comes after it. Exactly one of
/// them decides.
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
