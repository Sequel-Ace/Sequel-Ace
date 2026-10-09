//
//  SAConnectionRetryPolicy.swift
//  SPMySQLFramework
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//
//  More info at <https://github.com/Sequel-Ace/Sequel-Ace>
//

import Foundation
@_implementationOnly import MySQLClient

/// Whether a failed connection attempt is worth repeating without TLS.
///
/// A server whose TLS the client cannot negotiate is worth a second attempt without it, and that
/// fallback is why the framework connects twice. Nothing else is: a host that never answered fails
/// the same way again and doubles the time the interface stands still, and a server that refused the
/// credentials would only receive them a second time, unencrypted - in plain text where the cleartext
/// authentication plugin is enabled.
@objc(SAConnectionRetryPolicy)
public final class SAConnectionRetryPolicy: NSObject {

    /// Whether a connection attempt that failed with this error should be repeated without TLS.
    ///
    /// Only `CR_SSL_CONNECTION_ERROR` qualifies: the client reports every failure of the TLS
    /// negotiation with it - a reset or an unexpected end while the server is asked for TLS or
    /// during the handshake - before any credential leaves it. A connection lost later, reported as
    /// `CR_SERVER_LOST`, may already have carried the credentials over TLS, and repeating them
    /// without TLS is what the fallback must not do.
    /// - Parameter errorID: The client or server error the attempt ended with.
    /// - Returns: `true` only for a failed TLS negotiation.
    @objc(shouldRetryWithoutTLSAfterErrorID:)
    public static func shouldRetryWithoutTLS(afterErrorID errorID: UInt) -> Bool {
        errorID == UInt(CR_SSL_CONNECTION_ERROR)
    }
    /// What the retry without TLS may still spend of the attempt's connect budget.
    ///
    /// A failed `mysql_real_connect` keeps the options set on the handle when the client asks it
    /// to, but what it keeps is the timeout's *value*, not a deadline. So a TLS negotiation that
    /// spent the whole budget before failing would be followed by a second attempt entitled to all
    /// of it again, and a check-triggered reconnect could take twice its budget before the user is
    /// asked anything. The retry is given what is left instead, and is not made at all once the
    /// budget is gone - the first attempt reached the server's TLS and the question is more use
    /// than another wait.
    /// - Parameters:
    ///   - connectTimeoutOrZero: The attempt's connect timeout in seconds, zero for no limit.
    ///   - secondsSpent: How long the first attempt took.
    /// - Returns: The retry's connect timeout in seconds - zero where there is no limit - or nil
    ///   when nothing is left and the retry is to be skipped.
    @objc(retryConnectTimeoutForConnectTimeout:secondsSpent:)
    public static func retryConnectTimeout(forConnectTimeout connectTimeoutOrZero: UInt,
                                           secondsSpent: Double) -> NSNumber? {
        guard connectTimeoutOrZero > 0 else {
            return NSNumber(value: UInt(0))
        }
        let remaining = Double(connectTimeoutOrZero) - max(0, secondsSpent)
        guard remaining > 0 else {
            return nil
        }
        // Rounded up, because the client counts in whole seconds and rounding down would suppress
        // the retry outright on a budget of one second - which is what an attempt gets just after
        // the user has ended a wait. Overshooting by under a second is the lesser cost.
        return NSNumber(value: UInt(remaining.rounded(.up)))
    }

}
