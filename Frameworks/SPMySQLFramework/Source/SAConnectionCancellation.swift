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
    @objc(killQueryOverSideConnectionForGeneration:)
    func killQueryOverSideConnection(forGeneration generation: UInt)

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
    /// - Parameter workCoordinator: Where that work runs; it is asked to stop too.
    @objc(userStoppedWaitingWithWorkCoordinator:)
    public func userStoppedWaiting(workCoordinator: SAConnectionWorkCoordinator?) {
        guard let host else {
            return
        }
        host.noteUserEndedWait()
        workCoordinator?.abandonWorkForUserStop()
        requestCancellation(ofGeneration: host.currentQueryGeneration, synchronously: false)
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

        let askServer: () -> Void = { [weak self] in
            self?.host?.killQueryOverSideConnection(forGeneration: generation)
        }
        if synchronously {
            askServer()
        } else {
            DispatchQueue.global(qos: .userInitiated).async(execute: askServer)
        }

        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + Self.shutdownGrace) { [weak self] in
            guard let self else {
                return
            }
            self.inFlightQuery.closeSocket(ifGenerationIsWaiting: generation) {
                // The query ends because it was asked to, so it counts as cancelled rather than
                // failed, and the attempt that follows does not make anybody wait again.
                self.host?.markRunningQueryCancelled()
                self.host?.noteUserEndedWait()
            }
        }
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
    /// nothing is escaped with it: the connection replaces a session marked like this before it
    /// escapes a value, and the value is escaped for the character set on record.
    /// - Parameters:
    ///   - afterAbandonedWork: Whether the calling thread stopped waiting for the work it ran last.
    ///   - hasNoUsableSession: Whether the connection has no session to tell.
    /// - Returns: Whether the record alone is to be changed.
    @objc(storedEncodingOnlyNeedsRecordingAfterAbandonedWork:hasNoUsableSession:)
    public static func storedEncodingOnlyNeedsRecording(afterAbandonedWork: Bool,
                                                        hasNoUsableSession: Bool) -> Bool {
        return afterAbandonedWork || hasNoUsableSession
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
