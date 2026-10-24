//
//  SASessionGate.swift
//  SPMySQLFramework
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//
//  More info at <https://github.com/Sequel-Ace/Sequel-Ace>
//

import Foundation

/// What taking the connection for a statement asks of the connection, without handing over its
/// internals. The lock and the check are the connection's own; the rest are plain readings of its
/// state, made while the lock is held.
@objc(SASessionGateHost)
public protocol SASessionGateHost: AnyObject {

    /// Takes the connection lock, waiting for it.
    @objc(_lockConnection) func lockConnection()

    /// Releases the connection lock.
    @objc(_unlockConnection) func unlockConnection()

    /// Whether there is a session to use: connected, and not lost in the background.
    @objc var hasSessionToUse: Bool { get }

    /// Whether the session is marked to be replaced before its next use.
    @objc var sessionIsMarkedForReplacement: Bool { get }

    /// Whether an answer nobody read may still be on its way in this session.
    @objc var sessionProtocolCannotBeTrusted: Bool { get }

    /// Whether the session reports a transaction open now, read from its handle while it is held.
    @objc var sessionReportsOpenTransaction: Bool { get }

    /// Closes a session marked to be replaced, while the connection is held.
    @objc(_closeSessionMarkedForReplacement) func closeSessionMarkedForReplacement()

    /// Restores a session that was closed or lost, if one is needed.
    /// - Returns: Whether there is a session afterwards.
    @objc(checkConnectionIfNecessary) func checkIfNecessary() -> Bool
}

/// The gate a statement passes to take the session: on the way out the connection is held with a
/// session that can be used, or released with none.
@objc(SASessionGate)
public final class SASessionGate: NSObject {

    /// How many times the gate has the connection checked before it gives up: once for a session
    /// it closed or found lost, and once more should the restored session be lost again at once.
    static let checks = 2

    /// Takes the connection for a statement, replacing a session that is marked to be replaced first.
    ///
    /// A marked session with a transaction open is kept, and the mark left standing: closing it
    /// would roll back work somebody is still doing, and the session is still replaced once nothing
    /// is open in it. One the protocol cannot be trusted on goes regardless. A session that is
    /// closed here, or was lost in the background, is restored through the ordinary check before
    /// the statement runs.
    /// - Parameter host: The connection.
    /// - Returns: Whether the connection is held with a usable session; `false` leaves it released.
    @objc(lockHost:)
    public static func lock(_ host: SASessionGateHost) -> Bool {
        host.lockConnection()

        for _ in 0..<checks {
            if host.hasSessionToUse {
                if !host.sessionIsMarkedForReplacement {
                    return true
                }
                // The mark can be much older than this moment, and a query that took the
                // connection over in between can have opened a transaction of its own. The
                // connection is held here, so the session's own answer is the one to go by.
                if !SAConnectionCancellation.markedSessionIsClosedNow(sessionHasOpenTransaction: host.sessionReportsOpenTransaction,
                                                                      sessionIsProtocolInvalid: host.sessionProtocolCannotBeTrusted) {
                    return true
                }
                host.closeSessionMarkedForReplacement()
            }

            host.unlockConnection()
            guard host.checkIfNecessary() else {
                return false
            }
            host.lockConnection()
        }

        if host.hasSessionToUse {
            return true
        }
        host.unlockConnection()
        return false
    }
}
