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
/// internals: its lock and its check, forwarded, and plain readings of its state made while the
/// lock is held.
@objc(SASessionGateHost)
public protocol SASessionGateHost: AnyObject {

    /// Takes the connection lock, waiting for it.
    @objc(lockConnectionForGate) func lockConnection()

    /// Releases the connection lock.
    @objc(unlockConnectionForGate) func unlockConnection()

    /// Takes the connection lock if it is free, without waiting.
    /// - Returns: Whether it is held now.
    @objc(tryLockConnectionForGate) func tryLockConnection() -> Bool

    /// Whether there is a session to use: connected, and not lost in the background.
    @objc var hasSessionToUse: Bool { get }

    /// How the session is to be replaced before its next use - one word, read once.
    @objc var sessionReplacementMark: SASessionReplacementMark { get }

    /// Whether the session reports a transaction open now, read from its handle while it is held.
    @objc var sessionReportsOpenTransaction: Bool { get }

    /// Closes a session marked to be replaced, while the connection is held.
    @objc(closeMarkedSessionForGate) func closeSessionMarkedForReplacement()

    /// Restores a session that was closed or lost, if one is needed.
    /// - Returns: Whether there is a session afterwards.
    @objc(checkConnectionForGate) func checkIfNecessary() -> Bool
}

/// Which session a value escaped now is escaped for.
@objc(SAEscapingSession)
public enum SAEscapingSession: Int {
    /// The session the connection has.
    case theSessionThere = 0
    /// The session that replaces it before the next statement.
    case theReplacement = 1
    /// Cannot be told: the session goes unless something is open in it, and a statement running
    /// right now may open something. The value is refused rather than escaped for a guess.
    case undecidable = 2
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
    /// the statement runs. Once the checks are spent, a session marked to go meanwhile - by a
    /// keepalive that gave up on it before the lock came back - is not spoken on either: it is
    /// closed, so the next use reconnects, and this statement is refused.
    /// - Parameter host: The connection.
    /// - Returns: Whether the connection is held with a usable session; `false` leaves it released.
    @objc(lockHost:)
    public static func lock(_ host: SASessionGateHost) -> Bool {
        host.lockConnection()

        for _ in 0..<checks {
            if host.hasSessionToUse {
                if !sessionGoes(on: host) {
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
            if !sessionGoes(on: host) {
                return true
            }
            host.closeSessionMarkedForReplacement()
        }
        host.unlockConnection()
        return false
    }

    /// The session a value escaped now will be sent on - asked the way the gate asks when the
    /// statement takes the session, from the session's own answer with the connection held, so
    /// that escaping and the gate cannot disagree about the same session.
    ///
    /// A session marked to go once nothing is open in it is the one case that needs the lock: a
    /// statement running right now may open something, and until it has ended nobody can tell.
    /// Escaping does not wait for it - it is called from threads that must not block behind a
    /// statement, and from the thread that holds the lock while it reads a streaming result - so
    /// a busy connection makes the answer undecidable, and the value is refused.
    /// - Parameter host: The connection.
    /// - Returns: Which session to escape for, or that it cannot be told.
    @objc(sessionForEscapingOnHost:)
    public static func sessionForEscaping(on host: SASessionGateHost) -> SAEscapingSession {
        switch host.sessionReplacementMark {
        case .notMarked:
            return .theSessionThere
        case .regardless:
            return .theReplacement
        case .whenNothingIsOpen:
            guard host.tryLockConnection() else {
                return .undecidable
            }
            defer { host.unlockConnection() }
            return host.sessionReportsOpenTransaction ? .theSessionThere : .theReplacement
        @unknown default:
            return .undecidable
        }
    }

    /// Whether the session the host has goes before it is used, by its mark and what is open in it.
    ///
    /// The mark can be much older than this moment, and a query that took the connection over in
    /// between can have opened a transaction of its own. The connection is held here, so the
    /// session's own answer is the one to go by.
    /// - Parameter host: The connection, holding its lock.
    /// - Returns: Whether the session is replaced rather than used.
    private static func sessionGoes(on host: SASessionGateHost) -> Bool {
        let mark = host.sessionReplacementMark
        guard mark != .notMarked else {
            return false
        }
        return SAConnectionCancellation.sessionIsReplacedBeforeUse(mark: mark,
                                                                   sessionHasOpenTransaction: host.sessionReportsOpenTransaction)
    }
}
