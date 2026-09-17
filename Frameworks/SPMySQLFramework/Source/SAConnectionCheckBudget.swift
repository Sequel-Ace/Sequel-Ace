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
/// The time one reconnect attempt may spend on each of its steps.
@objc(SAConnectionAttemptBudget)
public final class SAConnectionAttemptBudget: NSObject {

    /// How long the attempt waits for a route to the host, in seconds.
    @objc public let networkWait: Double

    /// How long the attempt may take to connect - through a proxy, if there is one, and to the
    /// server itself - in seconds. Zero means the configured timeout's "no limit".
    @objc public let connectTimeout: UInt

    /// Whether ``connectTimeout`` differs from the connection's configured timeout.
    @objc public let overridesConfiguredTimeout: Bool

    /// Creates a budget.
    /// - Parameters:
    ///   - networkWait: How long to wait for a route, in seconds.
    ///   - connectTimeout: How long connecting may take, in seconds.
    ///   - overridesConfiguredTimeout: Whether that differs from the configured timeout.
    init(networkWait: Double, connectTimeout: UInt, overridesConfiguredTimeout: Bool) {
        self.networkWait = networkWait
        self.connectTimeout = connectTimeout
        self.overridesConfiguredTimeout = overridesConfiguredTimeout
        super.init()
    }
}

@objc(SAConnectionCheckBudget)
public final class SAConnectionCheckBudget: NSObject {

    /// How long an ordinary reconnect attempt waits for a route to the host, in seconds.
    public static let ordinaryNetworkWait: Double = 10

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

    /// The longest a side connection waits to connect, in seconds.
    ///
    /// It connects to a server the main connection reached a moment ago. While a transaction is open,
    /// the stopped query is held until the server has answered the kill, so a route that has gone
    /// must not hold it for a long configured timeout - or, without one, for as long as the system
    /// takes to give up. A kill that cannot connect in time costs that transaction, so the limit is
    /// the one a check-triggered reconnect to the same server gets, not less. A server that accepts
    /// the connection but never greets is tried a second time without TLS, which doubles the wait.
    public static let sideConnectionConnectLimit: UInt = connectLimit

    /// The shortest a keepalive ping may take before it is cut off, in seconds.
    ///
    /// A ping cut off before its answer costs the session - and any transaction it has open - so a
    /// very short connection timeout does not shorten it further. A longer minimum would hold the
    /// connection for that long on a route that has gone, and whatever the user does next waits
    /// behind it; this is the limit a check-triggered reconnect gets.
    public static let keepAlivePingMinimum: UInt = connectLimit

    /// The ping timeout a keepalive uses on a connection with this timeout.
    /// - Parameter configuredTimeout: The connection's configured timeout in seconds, zero for none.
    /// - Returns: The longer of the configured timeout and ``keepAlivePingMinimum``, in seconds.
    @objc(keepAlivePingTimeoutForConfiguredTimeout:)
    public static func keepAlivePingTimeout(forConfiguredTimeout configuredTimeout: UInt) -> UInt {
        max(configuredTimeout, keepAlivePingMinimum)
    }

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

    /// The budget for one reconnect attempt.
    ///
    /// An attempt made right after the user stopped waiting spends almost nothing, so their
    /// question comes at once. One made because a connection check failed spends the check
    /// limits, since the user is still waiting for the interface. Any other attempt - including
    /// every one the user asks for - keeps the connection's configured timeout. The budget covers
    /// the whole attempt, a proxy's connection included.
    /// - Parameters:
    ///   - configuredTimeout: The connection's configured timeout in seconds, zero for none.
    ///   - userEndedWait: Whether the attempt follows the user ending a wait.
    ///   - afterFailedCheck: Whether the attempt follows a failed connection check.
    /// - Returns: The time each step of the attempt may take.
    @objc(attemptBudgetForConfiguredTimeout:userEndedWait:afterFailedCheck:)
    public static func attemptBudget(forConfiguredTimeout configuredTimeout: UInt,
                                     userEndedWait: Bool,
                                     afterFailedCheck: Bool) -> SAConnectionAttemptBudget {
        if userEndedWait {
            return SAConnectionAttemptBudget(networkWait: 0,
                                             connectTimeout: connectTimeoutAfterEndedWait(forConfiguredTimeout: configuredTimeout),
                                             overridesConfiguredTimeout: true)
        }
        if afterFailedCheck {
            return SAConnectionAttemptBudget(networkWait: networkWait(forConfiguredTimeout: configuredTimeout),
                                             connectTimeout: connectTimeout(forConfiguredTimeout: configuredTimeout),
                                             overridesConfiguredTimeout: true)
        }
        return SAConnectionAttemptBudget(networkWait: ordinaryNetworkWait,
                                         connectTimeout: configuredTimeout,
                                         overridesConfiguredTimeout: false)
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

    /// The connection timeout for a side connection on a connection with this timeout.
    /// - Parameter configuredTimeout: The connection's configured timeout in seconds, zero for none.
    /// - Returns: The shorter of the configured timeout and ``sideConnectionConnectLimit``, in seconds.
    @objc(sideConnectionConnectTimeoutForConfiguredTimeout:)
    public static func sideConnectionConnectTimeout(forConfiguredTimeout configuredTimeout: UInt) -> UInt {
        capped(configuredTimeout, to: sideConnectionConnectLimit)
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
