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
/// Stopping a query means acting on exactly that query: asking the server to kill it, or closing
/// the socket underneath it when the server no longer answers. A moment later the connection can
/// be running a different query in the same server session and on the same socket, so every such
/// action checks, under one lock, that its query is still the one waiting.
///
/// The lock is never held while anything goes over the network. A kill request reserves the
/// waiting query instead, sends outside the lock, and gives the reservation back; a query that
/// wants to start waiting meanwhile waits for that on its own thread. Everything else here -
/// including whatever the main thread calls - only ever holds the lock for a moment.
@objc(SAInFlightQuery)
public final class SAInFlightQuery: NSObject {

    private let condition = NSCondition()
    private var waitingGeneration: UInt = 0
    private var waitingSocket: Int32 = -1
    private var waitingServerThread: UInt = 0
    private var killInProgress = false

    private let requestLock = NSLock()
    private var cancellationRequestedGeneration: UInt = 0
    private var storedLatestGeneration: UInt = 0
    private weak var latestGenerationThread: Thread?
    private var connectionHolder: pthread_t?

    /// Records that a query is about to wait on the server.
    ///
    /// If a kill request is on its way to the server, this waits until it has arrived: the request
    /// names a server session, and this query would otherwise be the one it hits.
    /// - Parameters:
    ///   - generation: The number of the query, as the connection counts them.
    ///   - socket: The socket it waits on.
    ///   - serverThread: The server's number for the session the query runs in.
    @objc(beginWaitingForGeneration:onSocket:serverThread:)
    public func beginWaiting(forGeneration generation: UInt, onSocket socket: Int32, serverThread: UInt) {
        condition.lock()
        defer { condition.unlock() }
        while killInProgress {
            condition.wait()
        }
        waitingGeneration = generation
        waitingSocket = socket
        waitingServerThread = serverThread
    }

    /// Records that a query no longer waits on the server. Only the query that is recorded as
    /// waiting can end its own record; a stale call changes nothing. Never waits.
    /// - Parameter generation: The number of the query that stopped waiting.
    @objc(endWaitingForGeneration:)
    public func endWaiting(forGeneration generation: UInt) {
        condition.lock()
        defer { condition.unlock() }
        guard waitingGeneration == generation else {
            return
        }
        waitingGeneration = 0
        waitingSocket = -1
        waitingServerThread = 0
    }

    /// Reserves a waiting query for a kill request, so that no other query can start waiting in
    /// the same session until the request has gone out.
    /// - Parameter generation: The number of the query to kill.
    /// - Returns: The server's number for that query's session, or 0 if the query is not waiting
    ///   (or another kill request is already on its way). Anything but 0 must be followed by
    ///   ``endKill(forGeneration:succeeded:whileStillWaiting:)``.
    @objc(beginKillIfGenerationIsWaiting:)
    public func beginKill(ifGenerationIsWaiting generation: UInt) -> UInt {
        condition.lock()
        defer { condition.unlock() }
        guard generation != 0, waitingGeneration == generation, !killInProgress else {
            return 0
        }
        killInProgress = true
        return waitingServerThread
    }

    /// Gives back a reservation made by ``beginKill(ifGenerationIsWaiting:)``.
    /// - Parameters:
    ///   - generation: The query the kill request was about.
    ///   - succeeded: Whether the server accepted the request.
    ///   - whileStillWaiting: Runs if the request succeeded and that query is still the one
    ///     waiting, before any other query can start - so whatever marks it cancelled marks that
    ///     query and no other.
    @objc(endKillForGeneration:succeeded:whileStillWaiting:)
    public func endKill(forGeneration generation: UInt, succeeded: Bool, whileStillWaiting: () -> Void) {
        condition.lock()
        defer { condition.unlock() }
        if succeeded, generation != 0, waitingGeneration == generation {
            whileStillWaiting()
        }
        killInProgress = false
        condition.broadcast()
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
        condition.lock()
        defer { condition.unlock() }
        guard generation != 0, waitingGeneration == generation, waitingSocket >= 0 else {
            return false
        }
        beforeClosing()
        return Darwin.shutdown(waitingSocket, SHUT_RDWR) == 0
    }

    /// Records that the query with this number was asked to stop. Never waits.
    ///
    /// A query that loses its connection reconnects and tries again under a new number. It asks
    /// under its original number whether it was asked to stop, so a request made before the retry
    /// began still reaches it.
    /// - Parameter generation: The number of the query that was asked to stop.
    @objc(requestCancellationOfGeneration:)
    public func requestCancellation(ofGeneration generation: UInt) {
        requestLock.lock()
        defer { requestLock.unlock() }
        guard generation != 0 else {
            return
        }
        cancellationRequestedGeneration = generation
    }

    /// Whether the query with this number was asked to stop. Never waits.
    /// - Parameter generation: The query's original number.
    /// - Returns: Whether stopping was asked for since that query began.
    @objc(cancellationWasRequestedForGeneration:)
    public func cancellationWasRequested(forGeneration generation: UInt) -> Bool {
        requestLock.lock()
        defer { requestLock.unlock() }
        return generation != 0 && cancellationRequestedGeneration == generation
    }

    /// Whether a query that may be on a retry was asked to stop. Never waits.
    ///
    /// Whoever asks names the number the connection reported at that moment: the query's original
    /// number, the retry's, or - while the query reconnects before its retry - the number of one of
    /// the queries the reconnect runs. All of them are part of this query.
    /// - Parameters:
    ///   - generation: The query's original number.
    ///   - attempt: The number of the attempt that is running.
    /// - Returns: Whether stopping was asked for under any number from the first to the last.
    @objc(cancellationWasRequestedForGenerationsFrom:through:)
    public func cancellationWasRequested(forGenerationsFrom generation: UInt, through attempt: UInt) -> Bool {
        requestLock.lock()
        defer { requestLock.unlock() }
        let requested = cancellationRequestedGeneration
        return requested != 0 && generation <= requested && requested <= attempt
    }

    /// The number of the query or attempt that took the connection last. Never waits: it is read
    /// by whoever wants to stop that query, which must not wait for the query itself.
    @objc public var latestGeneration: UInt {
        requestLock.lock()
        defer { requestLock.unlock() }
        return storedLatestGeneration
    }

    /// Records the number of the query or attempt that has just taken the connection, on the
    /// thread that took it.
    /// - Parameter generation: Its number.
    @objc(noteLatestGeneration:)
    public func noteLatestGeneration(_ generation: UInt) {
        requestLock.lock()
        defer { requestLock.unlock() }
        storedLatestGeneration = generation
        latestGenerationThread = Thread.current
    }

    /// The number of the query that took the connection last, if a given thread took it.
    /// - Parameter thread: The thread the query has to have run on.
    /// - Returns: The query's number, or 0 if the connection was taken last by another thread.
    func latestGeneration(ifTakenOn thread: Thread) -> UInt {
        requestLock.lock()
        defer { requestLock.unlock() }
        return latestGenerationThread === thread ? storedLatestGeneration : 0
    }

    /// Records which thread has just taken the connection, or that it was given back.
    /// - Parameter held: Whether the current thread now holds the connection.
    @objc(noteConnectionHeldByCurrentThread:)
    public func noteConnectionHeld(byCurrentThread held: Bool) {
        requestLock.lock()
        defer { requestLock.unlock() }
        connectionHolder = held ? pthread_self() : nil
    }

    /// Whether the current thread is the one holding the connection - a streaming result it is
    /// still reading, say. Such a thread must not wait for the connection. Never waits.
    @objc public var connectionIsHeldByCurrentThread: Bool {
        requestLock.lock()
        defer { requestLock.unlock() }
        guard let connectionHolder else {
            return false
        }
        return pthread_equal(connectionHolder, pthread_self()) != 0
    }
}
