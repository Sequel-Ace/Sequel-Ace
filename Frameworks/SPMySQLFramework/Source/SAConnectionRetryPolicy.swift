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
}
