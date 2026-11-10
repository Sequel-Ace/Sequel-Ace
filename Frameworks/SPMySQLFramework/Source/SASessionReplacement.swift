//
//  SASessionReplacement.swift
//  SPMySQLFramework
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//
//  More info at <https://github.com/Sequel-Ace/Sequel-Ace>
//

import Foundation

/// What closing a session marked to be replaced asks of the connection, without handing over its
/// internals: plain readings of the native handle, and one narrow accessor for each piece of state
/// that goes with the session - a step each, nothing decided in any of them.
@objc(SASessionReplacementHost)
public protocol SASessionReplacementHost: AnyObject {

    /// How the session is to be replaced - one word, read once.
    @objc var sessionReplacementMark: SASessionReplacementMark { get }

    /// Whether a tunnel, or another proxy, carries the connection.
    @objc var hasProxy: Bool { get }

    /// Whether the native handle's net layer reports a read or write in progress; `false` with no handle.
    @objc var nativeHandleIsReadingOrWriting: Bool { get }

    /// Whether the native handle still has its transport; `false` with no handle.
    @objc var nativeHandleHasTransport: Bool { get }

    /// Whether the native handle still has its net buffer; `false` with no handle.
    @objc var nativeHandleHasBuffer: Bool { get }

    /// Retires the lease's own handle on the session's socket.
    @objc(retireSessionLease) func retireSessionLease()

    /// Closes the native handle - a goodbye to the server, its transport freed - and forgets it.
    @objc(closeNativeHandle) func closeNativeHandle()

    /// Forgets the native handle without closing it.
    @objc(leaveNativeHandleBehind) func leaveNativeHandleBehind()

    /// Records the session as lost in the background, to be restored on its next use - on the
    /// limits of a failed check when the session was lost to one.
    /// - Parameter afterFailedCheck: Whether a failed connection check lost the session.
    @objc(recordSessionLostAfterFailedCheck:) func recordSessionLost(afterFailedCheck: Bool)

    /// Records whether the proxy was left as it stands, so that the reconnect connects through it
    /// rather than waiting for it to go idle.
    /// - Parameter untouched: Whether there is a proxy, and it was left alone.
    @objc(recordProxyUntouchedBySessionReplacement:) func recordProxyUntouched(bySessionReplacement untouched: Bool)

    /// Forgets what the session reported about its server.
    @objc(forgetServerVersion) func forgetServerVersion()

    /// Clears the mark, which was about the session that is gone.
    @objc(clearSessionReplacementMark) func clearSessionReplacementMark()

    /// Lets values follow the record again, until the next session reports its own character set.
    @objc(forgetEscapedSession) func forgetEscapedSession()
}

/// Closes a session marked to be replaced: the steps, in the order they have to go, and what each
/// of them decides. Run with the connection held, so that nothing can use the session in between.
@objc(SASessionReplacement)
public final class SASessionReplacement: NSObject {

    /// Closes the marked session on this connection. The next use reconnects, and restores the
    /// connection's record on the new session.
    ///
    /// The lease's own handle goes before the handle it belongs to is released - the contract
    /// every other disconnect follows. Left behind, it would still name a server session that no
    /// longer exists, and whose number the server is free to give to another client. The native
    /// handle is closed, or left behind when a cut-off ping left it in the middle of a read, as
    /// ``SAConnectionCancellation`` decides: closing such a handle has crashed before. Only the
    /// MySQL session goes: a tunnel under it stays as it is, and the reconnect that follows
    /// connects through it rather than waiting for it to go idle, which a connected tunnel never
    /// does on its own. What the session reported about its server goes with it, so that the
    /// version readings answer "no connection" until the next session reports its own, rather
    /// than the closed session's version for a connection that may never come back; so does the
    /// character set the escaper had from it. The mark was about this session: it is read first,
    /// because it says why the session went - one lost to a failed check is restored on that
    /// check's limits - and cleared last.
    /// - Parameter host: The connection, holding its lock.
    @objc(closeMarkedSessionOnHost:)
    public static func closeMarkedSession(on host: SASessionReplacementHost) {
        let mark = host.sessionReplacementMark
        host.retireSessionLease()
        if SAConnectionCancellation.closedSessionHandleIsClosed(readingOrWriting: host.nativeHandleIsReadingOrWriting,
                                                                hasTransport: host.nativeHandleHasTransport,
                                                                hasBuffer: host.nativeHandleHasBuffer) {
            host.closeNativeHandle()
        } else {
            host.leaveNativeHandleBehind()
        }
        host.recordSessionLost(afterFailedCheck: SAConnectionCancellation.replacementFollowsFailedCheck(mark: mark))
        host.recordProxyUntouched(bySessionReplacement: host.hasProxy)
        host.forgetServerVersion()
        host.clearSessionReplacementMark()
        host.forgetEscapedSession()
    }
}
