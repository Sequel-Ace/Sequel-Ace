//
//  SAInFlightQuery.swift
//  SPMySQLFramework
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//
//  More info at <https://github.com/Sequel-Ace/Sequel-Ace>
//

import Darwin
import Foundation

/// The query a connection is waiting on the server for, and the socket it is waiting on.
///
/// Ending a wait for a server that has stopped answering means closing the socket underneath it.
/// That is only right for the query somebody asked to stop, and only while it is still waiting:
/// a moment later the connection can be running a different query on the same socket. The query
/// marks when it starts and stops waiting, and the socket is closed under the same lock, so the
/// check and the closing cannot fall on different sides of that change.
@objc(SAInFlightQuery)
public final class SAInFlightQuery: NSObject {

    private let lock = NSLock()
    private var waitingGeneration: UInt = 0
    private var waitingSocket: Int32 = -1
    private var waitingServerThread: UInt = 0
    private var cancellationRequestedGeneration: UInt = 0

    /// Records that a query is about to wait on the server.
    /// - Parameters:
    ///   - generation: The number of the query, as the connection counts them.
    ///   - socket: The socket it waits on.
    ///   - serverThread: The server's number for the session the query runs in.
    @objc(beginWaitingForGeneration:onSocket:serverThread:)
    public func beginWaiting(forGeneration generation: UInt, onSocket socket: Int32, serverThread: UInt) {
        lock.lock()
        defer { lock.unlock() }
        waitingGeneration = generation
        waitingSocket = socket
        waitingServerThread = serverThread
    }

    /// Records that a query no longer waits on the server. Only the query that is recorded as
    /// waiting can end its own record; a stale call changes nothing.
    /// - Parameter generation: The number of the query that stopped waiting.
    @objc(endWaitingForGeneration:)
    public func endWaiting(forGeneration generation: UInt) {
        lock.lock()
        defer { lock.unlock() }
        guard waitingGeneration == generation else {
            return
        }
        waitingGeneration = 0
        waitingSocket = -1
        waitingServerThread = 0
    }

    /// Runs something that concerns a waiting query - asking the server to kill it, say - only
    /// while that query is still waiting, and keeps it waiting until the action is done.
    ///
    /// The query cannot stop waiting, nor another one start, while the action runs, so the action
    /// must be quick: prepare anything slow beforehand.
    /// - Parameters:
    ///   - generation: The number of the query the action is about.
    ///   - action: The action, given the server's number for that query's session.
    /// - Returns: Whether the query was still waiting and the action ran.
    @objc(performIfGenerationIsWaiting:action:)
    @discardableResult
    public func perform(ifGenerationIsWaiting generation: UInt, _ action: (_ serverThread: UInt) -> Void) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard generation != 0, waitingGeneration == generation else {
            return false
        }
        action(waitingServerThread)
        return true
    }

    /// Records that the query with this number was asked to stop.
    ///
    /// A query that loses its connection reconnects and tries again under a new number. It asks
    /// under its original number whether it was asked to stop, so a request made before the retry
    /// began still reaches it.
    /// - Parameters:
    ///   - generation: The number of the query that was asked to stop.
    ///   - whileWaiting: Runs if that query is the one waiting on the server right now, while it
    ///     cannot stop waiting.
    @objc(requestCancellationOfGeneration:whileWaiting:)
    public func requestCancellation(ofGeneration generation: UInt, whileWaiting: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard generation != 0 else {
            return
        }
        cancellationRequestedGeneration = generation
        if waitingGeneration == generation {
            whileWaiting()
        }
    }

    /// Whether the query with this number was asked to stop.
    /// - Parameter generation: The query's original number.
    /// - Returns: Whether stopping was asked for since that query began.
    @objc(cancellationWasRequestedForGeneration:)
    public func cancellationWasRequested(forGeneration generation: UInt) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return generation != 0 && cancellationRequestedGeneration == generation
    }

    /// Closes the socket of a query that is still waiting on the server, and of no other.
    /// - Parameters:
    ///   - generation: The number of the query that was asked to stop.
    ///   - beforeClosing: Runs just before the socket is closed, while nothing else can start,
    ///     so that whatever the query finds when its read fails is already in place.
    /// - Returns: Whether that query was still waiting and its socket was closed.
    @objc(closeSocketIfGenerationIsWaiting:beforeClosing:)
    @discardableResult
    public func closeSocket(ifGenerationIsWaiting generation: UInt, beforeClosing: () -> Void) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard generation != 0, waitingGeneration == generation, waitingSocket >= 0 else {
            return false
        }
        beforeClosing()
        return Darwin.shutdown(waitingSocket, SHUT_RDWR) == 0
    }
}
