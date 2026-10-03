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
/// These limits distinguish the two cases instead. A peer that answers keeps the connection alive
/// however long its query runs, because answering a keepalive probe costs the server nothing and
/// happens even while a statement is still executing. A peer that answers nothing at all loses the
/// connection in seconds, which turns a frozen window into the question the user can act on.
@objc(SAConnectionSocketTimeouts)
public final class SAConnectionSocketTimeouts: NSObject {

    /// How long a connection may be quiet before the kernel starts asking whether the peer is there, in seconds.
    public static let keepAliveIdle: Int32 = 10

    /// How long the kernel waits between those questions, in seconds.
    public static let keepAliveInterval: Int32 = 3

    /// How many unanswered questions end the connection.
    public static let keepAliveCount: Int32 = 3

    /// How long the kernel retransmits unacknowledged data before dropping the connection, in seconds.
    ///
    /// This is the limit that ends the wait for a reply to a query that was sent onto a route which
    /// no longer exists. A server that is merely slow keeps acknowledging what it received, so its
    /// connection is never affected by this.
    public static let retransmitDropTime: Int32 = 10

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
