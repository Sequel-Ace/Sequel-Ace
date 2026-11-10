//
//  SAConnectionSetupDeadline.swift
//  SPMySQLFramework
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//
//  More info at <https://github.com/Sequel-Ace/Sequel-Ace>
//

import Darwin
import Foundation

/// A finite wait for the statements that set a session up once the handshake is through.
///
/// After the handshake a connection reads the server's variables and the largest query size, and
/// a reconnect then restores the database, the character set and the time zone - ordinary
/// statements all, read with no deadline, because the main connection carries none: a read
/// timeout would also cut short the long queries people run on purpose. The connect timeout
/// bounds the handshake alone, and the socket limits (``SAConnectionSocketTimeouts``) bound a
/// route that has gone - not a tunnel or relay whose near end keeps acknowledging while its far
/// end has stopped replying. Behind one of those, setup waited with no limit at all.
///
/// The deadline bounds setup without a read timeout. Armed before it, the deadline shuts the
/// socket down once the budget runs out, which ends the blocking read with the error the
/// connection already treats as a lost connection; disarmed after it, the deadline leaves the
/// socket as it found it, so the statements that follow run with no limit, as before. The client
/// library's own read timeout would not do here: on this client it is applied when the connection
/// is made and cannot be lifted again afterwards.
///
/// It holds a duplicate of the descriptor rather than its number. The connection may close its
/// descriptor while the deadline stands, and the number be given to another socket; the
/// duplicate still names the socket it was taken from, and shutting that one down after it was
/// closed changes nothing.
///
/// A statement that loses the session while the deadline stands - to the deadline, or to the
/// route - reports it here rather than recovering the session it was setting up: that recovery
/// would be a second attempt nested inside the first, with its own retries and its own question
/// for the user, once per statement. The attempt the setup belongs to fails instead, and that
/// attempt has both already.
@objc(SAConnectionSetupDeadline)
public final class SAConnectionSetupDeadline: NSObject {

    private let lock = NSLock()
    private var duplicate: Int32
    private var armed = true
    private var endedTheWait = false
    private var statementLostTheSession = false
    private var expiry: DispatchWorkItem?

    /// Whether the budget ran out, and the socket was shut down to end the wait on it.
    @objc public var endedTheWaitOnTheSocket: Bool {
        lock.withLock { endedTheWait }
    }

    /// Whether a statement run while the deadline stood lost the session.
    @objc public var aStatementLostTheSession: Bool {
        lock.withLock { statementLostTheSession }
    }

    /// Records that a statement run while the deadline stood lost the session.
    @objc public func noteAStatementLostTheSession() {
        lock.withLock { statementLostTheSession = true }
    }

    /// Whether the phase goes on after a statement: the session is still connected, and no
    /// statement of the phase has lost it.
    /// - Parameter connected: Whether the connection still reports its session as connected.
    @objc(phaseContinuesWhileConnected:)
    public func phaseContinues(whileConnected connected: Bool) -> Bool {
        connected && !aStatementLostTheSession
    }

    /// Ends the phase: lifts the deadline, and says whether the session came through - still
    /// connected, no statement having lost it, and the deadline not having had to end a wait.
    /// That last it can have done after the last reply was in; the socket is shut down all the
    /// same, and a session on it is nothing a caller can use.
    /// - Parameter connected: Whether the connection still reports its session as connected.
    @objc(endPhaseWhileConnected:)
    public func endPhase(whileConnected connected: Bool) -> Bool {
        let theSocketWasShutDown = disarm()
        return connected && !theSocketWasShutDown && !aStatementLostTheSession
    }

    /// Arms a deadline on a connection's socket.
    /// - Parameters:
    ///   - descriptor: The connection's socket descriptor.
    ///   - seconds: How long the statements may take before the socket is shut down.
    /// - Throws: The POSIX error that kept the descriptor from being duplicated - none given, or
    ///   none left to the process. A setup that cannot be bounded is not run, so the caller is
    ///   told why rather than handed nothing.
    /// - Returns: The armed deadline.
    @objc(deadlineForSocket:seconds:error:)
    public static func deadline(forSocket descriptor: Int32, seconds: TimeInterval) throws -> SAConnectionSetupDeadline {
        guard descriptor >= 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(EBADF))
        }
        let duplicate = fcntl(descriptor, F_DUPFD_CLOEXEC, 0)
        guard duplicate >= 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        return SAConnectionSetupDeadline(duplicate: duplicate, seconds: seconds)
    }

    private init(duplicate: Int32, seconds: TimeInterval) {
        self.duplicate = duplicate
        super.init()
        // Held weakly: a deadline nothing refers to any more has been dropped, not armed, and
        // stands down with the duplicate rather than firing at a socket nobody is waiting on.
        let expiry = DispatchWorkItem { [weak self] in
            self?.expire()
        }
        self.expiry = expiry
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + max(seconds, 0), execute: expiry)
    }

    deinit {
        if duplicate >= 0 {
            Darwin.close(duplicate)
        }
    }

    /// Lifts the deadline: from here on the socket is left as it is.
    /// - Returns: Whether the budget had already run out, and the socket been shut down.
    @objc
    @discardableResult
    public func disarm() -> Bool {
        lock.withLock {
            expiry?.cancel()
            expiry = nil
            guard armed else {
                return endedTheWait
            }
            armed = false
            Darwin.close(duplicate)
            duplicate = -1
            return false
        }
    }

    /// Ends the wait: the socket is shut down, so a read blocked on it returns at once.
    private func expire() {
        lock.withLock {
            guard armed else {
                return
            }
            armed = false
            endedTheWait = true
            _ = Darwin.shutdown(duplicate, SHUT_RDWR)
            Darwin.close(duplicate)
            duplicate = -1
        }
    }
}
