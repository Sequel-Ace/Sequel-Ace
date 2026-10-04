//
//  SAConnectionSocketTimeouts.swift
//  SPMySQLFramework
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//
//  More info at <https://github.com/Sequel-Ace/Sequel-Ace>
//

import Darwin
import Foundation

/// The limits that decide how long the kernel keeps a connection whose peer has stopped answering.
///
/// A query that has already gone out cannot be taken back: the client waits for the reply, and on a
/// route that disappeared - a VPN going away - that reply never comes. Without a limit the socket
/// waits for the full retransmission sequence, minutes during which the interface stands still,
/// because a read timeout is not an option here: it would also cut short the long queries people
/// run on purpose.
///
/// These limits distinguish the two cases instead, and they are not interchangeable.
/// ``retransmitDropTime`` ends the wait for a reply to data that was sent and never acknowledged -
/// the route-disappeared-mid-query case this exists for. The keepalive limits only decide sockets
/// that are *quiet*: genuinely idle, or waiting to read a reply whose request the server did
/// acknowledge.
///
/// So the keepalive limits are deliberately tolerant. An idle session that is dropped loses any
/// transaction it has open, and an ordinary Wi-Fi or VPN handover can take longer than a brief
/// cutoff would allow; keeping that session across the handover takes precedence over noticing an
/// idle failure quickly, because nobody is waiting on an idle session. A query that is waiting is
/// bounded by the explicit checks instead - a ping on the check budget, the liveness probe, and a
/// wait the user can end - which do not destroy a session to find out that it is gone.
@objc(SAConnectionSocketTimeouts)
public final class SAConnectionSocketTimeouts: NSObject {

    /// How long a connection may be quiet before the kernel starts asking whether the peer is there, in seconds.
    ///
    /// Tolerant on purpose: see the note above on why a quiet session is not hurried.
    public static let keepAliveIdle: Int32 = 60

    /// How long the kernel waits between those questions, in seconds.
    public static let keepAliveInterval: Int32 = 10

    /// How many unanswered questions end the connection.
    ///
    /// With the two above, a session that answers nothing while quiet is kept for 110 seconds -
    /// long enough to outlast an ordinary handover, and still an end rather than the server's
    /// `wait_timeout` hours later.
    public static let keepAliveCount: Int32 = 5

    /// How long the kernel retransmits unacknowledged data before dropping the connection, in seconds.
    ///
    /// This is the limit that ends the wait for a reply to a query that was sent onto a route which
    /// no longer exists. A server that is merely slow keeps acknowledging what it received, so its
    /// connection is never affected by this - and on a lossy link, where acknowledgements do
    /// arrive but late, the timer restarts with each one, so a bad connection is not mistaken for a
    /// dead one.
    public static let retransmitDropTime: Int32 = 60

    /// Applies the limits to a connection's socket.
    /// - Parameter descriptor: The connection's socket descriptor.
    /// - Returns: Whether the socket accepted the limits, which only TCP connections do.
    @objc(applyToSocket:)
    @discardableResult
    public static func apply(toSocket descriptor: Int32) -> Bool {
        guard descriptor >= 0 else {
            return false
        }

        guard setOption(descriptor, SOL_SOCKET, SO_KEEPALIVE, 1),
              setOption(descriptor, IPPROTO_TCP, TCP_KEEPALIVE, keepAliveIdle),
              setOption(descriptor, IPPROTO_TCP, TCP_KEEPINTVL, keepAliveInterval),
              setOption(descriptor, IPPROTO_TCP, TCP_KEEPCNT, keepAliveCount),
              setOption(descriptor, IPPROTO_TCP, TCP_RXT_CONNDROPTIME, retransmitDropTime) else {
            // A local socket has none of these, and loses nothing by not having them either.
            return false
        }

        return true
    }

    /// Sets one integer socket option.
    /// - Parameters:
    ///   - descriptor: The socket to set it on.
    ///   - level: The protocol level the option belongs to.
    ///   - option: The option to set.
    ///   - value: The value to set it to, in seconds or as a count.
    /// - Returns: Whether the socket accepted the option.
    private static func setOption(_ descriptor: Int32, _ level: Int32, _ option: Int32, _ value: Int32) -> Bool {
        var setting = value
        return setsockopt(descriptor, level, option, &setting, socklen_t(MemoryLayout<Int32>.size)) == 0
    }
}
