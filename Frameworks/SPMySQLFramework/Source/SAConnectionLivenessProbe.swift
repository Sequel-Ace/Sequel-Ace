//
//  SAConnectionLivenessProbe.swift
//  SPMySQLFramework
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//
//  More info at <https://github.com/Sequel-Ace/Sequel-Ace>
//

import Darwin
import Foundation

/// What a connection's socket already knows about its peer, asked without sending anything.
///
/// A connection used within the last thirty seconds is trusted instead of verified before every
/// query, which keeps normal work fast. A VPN going away breaks that assumption silently: the
/// socket stays open, so the next query blocks on a route that no longer exists and the interface
/// freezes with it. This probe reads what the socket itself can answer immediately - a pending
/// error, a peer that closed, a connection the kernel has already torn down - so a connection that
/// is plainly gone gets verified rather than trusted.
///
/// It deliberately does not ask about routes: a reachability lookup costs half a second on its
/// first use, which is the very stall this is meant to prevent, and it answers "reachable" for any
/// address as long as a default route exists.
///
/// Anything the probe cannot answer counts as alive. A wrong "gone" would send every query through
/// a needless connection check, while a missed drop only costs the check that was going to happen
/// anyway once the thirty seconds are up.
@objc(SAConnectionLivenessProbe)
public final class SAConnectionLivenessProbe: NSObject {

    /// How long a connection has to have been quiet before its socket is worth looking at, in seconds.
    ///
    /// Traffic proves a connection far better than any probe does, so a connection that carried a
    /// query moments ago is left alone. This keeps the probe out of batches of small queries, where
    /// it would run between every statement.
    public static let minimumIdleTime: Double = 1

    /// Whether a connection inside its grace period should be verified before the next query.
    /// - Parameters:
    ///   - idleTime: Seconds since the connection last carried traffic.
    ///   - descriptor: The connection's socket descriptor.
    /// - Returns: `true` only for a quiet connection whose socket reports that the peer is gone.
    @objc(shouldVerifyConnectionIdleFor:socket:)
    public static func shouldVerifyConnection(idleFor idleTime: Double, socket descriptor: Int32) -> Bool {
        guard idleTime >= minimumIdleTime else {
            return false
        }
        return socketIsKnownDead(descriptor)
    }

    /// Whether the socket is known to be unusable, judged without sending anything over it.
    /// - Parameter descriptor: The connection's socket descriptor.
    /// - Returns: `true` only when the socket or the routing table reports that the peer is gone.
    static func socketIsKnownDead(_ descriptor: Int32) -> Bool {
        guard descriptor >= 0 else {
            return false
        }

        if pendingSocketError(descriptor) != 0 {
            return true
        }

        if peerHasClosed(descriptor) {
            return true
        }

        return connectionWasTornDown(descriptor)
    }

    /// The error the socket has been holding for its owner, if any.
    ///
    /// Reading the error also clears it, which is why this is only asked when the answer decides
    /// whether the connection gets verified: a socket with a pending error fails its next use in
    /// any case, and the verification that follows reports the failure properly.
    /// - Parameter descriptor: The connection's socket descriptor.
    /// - Returns: The pending `errno` value, or zero when the socket has none.
    private static func pendingSocketError(_ descriptor: Int32) -> Int32 {
        var socketError: Int32 = 0
        var length = socklen_t(MemoryLayout<Int32>.size)
        guard getsockopt(descriptor, SOL_SOCKET, SO_ERROR, &socketError, &length) == 0 else {
            return 0
        }
        return socketError
    }

    /// Whether the peer has closed the connection or the socket refuses to be read.
    ///
    /// The byte is only peeked at, never consumed, so a server that sent something keeps it for
    /// the connection to read as usual.
    /// - Parameter descriptor: The connection's socket descriptor.
    /// - Returns: `true` for an orderly close or an error that ends the connection.
    private static func peerHasClosed(_ descriptor: Int32) -> Bool {
        var byte: UInt8 = 0
        let received = withUnsafeMutablePointer(to: &byte) { pointer in
            recv(descriptor, pointer, 1, MSG_PEEK | MSG_DONTWAIT)
        }

        if received == 0 {
            return true
        }
        if received < 0 {
            switch errno {
            case EAGAIN, EINTR:
                // Nothing to read is the normal state of an idle connection.
                return false
            default:
                return true
            }
        }
        return false
    }

    /// Whether the kernel has already taken the connection out of its established state.
    ///
    /// A socket whose connection the kernel gave up on is unusable even though nothing has been
    /// read from it yet, and asking costs a single call.
    /// - Parameter descriptor: The connection's socket descriptor.
    /// - Returns: `true` only when the kernel reports a TCP connection that is no longer established.
    private static func connectionWasTornDown(_ descriptor: Int32) -> Bool {
        var info = tcp_connection_info()
        var length = socklen_t(MemoryLayout<tcp_connection_info>.size)
        guard getsockopt(descriptor, IPPROTO_TCP, TCP_CONNECTION_INFO, &info, &length) == 0 else {
            // Anything that is not a TCP connection answers this way, and has no state to lose.
            return false
        }
        return info.tcpi_state != UInt8(TCPS_ESTABLISHED)
    }
}
