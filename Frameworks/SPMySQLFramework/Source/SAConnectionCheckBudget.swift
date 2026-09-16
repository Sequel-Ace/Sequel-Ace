//
//  SAConnectionCheckBudget.swift
//  SPMySQLFramework
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//
//  More info at <https://github.com/Sequel-Ace/Sequel-Ace>
//

import Foundation

/// The time limits a connection check runs on before the user is asked about a lost connection.
///
/// A dropped VPN leaves the socket in place: nothing is refused, the packets simply stop arriving,
/// so every step of the check has to end on its own. Each limit stays at or below the connection's
/// configured timeout, and a configured timeout of zero - "wait indefinitely" - still receives the
/// short limit, because an unbounded check is what freezes the application.
///
/// The limits apply to the attempt made before the user is asked. Anything the user then triggers
/// runs on the configured timeout again, because by then someone is watching the progress.
@objc(SAConnectionCheckBudget)
public final class SAConnectionCheckBudget: NSObject {

    /// The longest a connection check waits for a ping reply, in seconds.
    public static let pingLimit: UInt = 5

    /// The longest a check-triggered reconnect waits for a route to the host, in seconds.
    public static let networkWaitLimit: Double = 3

    /// The longest a check-triggered reconnect waits for the connection itself, in seconds.
    public static let connectLimit: UInt = 10

    /// The longest an attempt waits once the user has said they will not wait, in seconds.
    public static let endedWaitConnectLimit: UInt = 1

    /// How soon after the user ended a wait an attempt has to start to count as following it, in seconds.
    ///
    /// The short budget is for the attempt made right after the user stopped waiting, so their
    /// question comes at once. An attempt made later - after the network came back, say - is an
    /// ordinary one, and a single second is often not enough for it.
    public static let endedWaitWindow: TimeInterval = 5

    /// How long a side connection waits for each answer from the server, in seconds.
    ///
    /// A side connection sends one short statement - asking the server to kill a query - while the
    /// query it concerns is held still. A server that accepted the connection and then stopped
    /// answering must not keep that query held for as long as it likes. The client library retries
    /// a read up to three times, so the whole wait is at most three times this.
    public static let sideConnectionAnswerLimit: UInt = 2

    /// The ping timeout a connection check uses on a connection with this timeout.
    /// - Parameter configuredTimeout: The connection's configured timeout in seconds, zero for none.
    /// - Returns: The shorter of the configured timeout and ``pingLimit``, in seconds.
    @objc(pingTimeoutForConfiguredTimeout:)
    public static func pingTimeout(forConfiguredTimeout configuredTimeout: UInt) -> UInt {
        capped(configuredTimeout, to: pingLimit)
    }

    /// The network wait a check-triggered reconnect uses on a connection with this timeout.
    /// - Parameter configuredTimeout: The connection's configured timeout in seconds, zero for none.
    /// - Returns: The shorter of the configured timeout and ``networkWaitLimit``, in seconds.
    @objc(networkWaitForConfiguredTimeout:)
    public static func networkWait(forConfiguredTimeout configuredTimeout: UInt) -> Double {
        configuredTimeout > 0 ? min(Double(configuredTimeout), networkWaitLimit) : networkWaitLimit
    }

    /// The connection timeout a check-triggered reconnect uses on a connection with this timeout.
    /// - Parameter configuredTimeout: The connection's configured timeout in seconds, zero for none.
    /// - Returns: The shorter of the configured timeout and ``connectLimit``, in seconds.
    @objc(connectTimeoutForConfiguredTimeout:)
    public static func connectTimeout(forConfiguredTimeout configuredTimeout: UInt) -> UInt {
        capped(configuredTimeout, to: connectLimit)
    }

    /// The connection timeout for the attempt that follows the user ending a wait.
    ///
    /// The question of what to do about the lost connection has to reach the user now, not after
    /// another timeout: they have just said that waiting is what they do not want. The attempt is
    /// still made, because a connection that comes back immediately spares them the question.
    /// - Parameter configuredTimeout: The connection's configured timeout in seconds, zero for none.
    /// - Returns: The shorter of the configured timeout and ``endedWaitConnectLimit``, in seconds.
    @objc(connectTimeoutAfterEndedWaitForConfiguredTimeout:)
    public static func connectTimeoutAfterEndedWait(forConfiguredTimeout configuredTimeout: UInt) -> UInt {
        capped(configuredTimeout, to: endedWaitConnectLimit)
    }

    /// Whether an attempt gets the short budget that follows the user ending a wait.
    /// - Parameter seconds: How long ago the user ended the wait.
    /// - Returns: `true` only for an attempt that starts within ``endedWaitWindow`` of it.
    @objc(attemptIsShortenedStartingSecondsAfterEndedWait:)
    public static func attemptIsShortened(startingSecondsAfterEndedWait seconds: Double) -> Bool {
        seconds >= 0 && seconds < endedWaitWindow
    }

    /// The read and write timeout for a side connection, which only ever asks the server to kill a query.
    /// - Returns: ``sideConnectionAnswerLimit``, in seconds.
    @objc(sideConnectionAnswerTimeout)
    public static func sideConnectionAnswerTimeout() -> UInt {
        sideConnectionAnswerLimit
    }

    /// Caps a configured timeout at one of the check limits.
    /// - Parameters:
    ///   - configuredTimeout: The connection's configured timeout in seconds, zero for none.
    ///   - limit: The limit this step of the check may not exceed, in seconds.
    /// - Returns: The limit itself for an unlimited timeout, the smaller of the two otherwise.
    private static func capped(_ configuredTimeout: UInt, to limit: UInt) -> UInt {
        configuredTimeout > 0 ? min(configuredTimeout, limit) : limit
    }
}
