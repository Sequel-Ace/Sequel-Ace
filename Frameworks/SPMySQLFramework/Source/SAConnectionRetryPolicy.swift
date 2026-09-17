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

    /// The client errors with which the TLS negotiation of an attempt fails.
    private static let tlsNegotiationErrorIDs: Set<UInt> = [
        UInt(CR_SSL_CONNECTION_ERROR),  // the TLS handshake failed
        UInt(CR_SERVER_LOST),           // the server closed the connection during the handshake
        UInt(CR_SERVER_LOST_EXTENDED),  // the same, with the system error
        UInt(CR_SERVER_GONE_ERROR)      // the server was gone when the handshake was written
    ]

    /// Whether a connection attempt that failed with this error should be repeated without TLS.
    /// - Parameter errorID: The client or server error the attempt ended with.
    /// - Returns: `true` only for errors with which the TLS negotiation fails.
    @objc(shouldRetryWithoutTLSAfterErrorID:)
    public static func shouldRetryWithoutTLS(afterErrorID errorID: UInt) -> Bool {
        tlsNegotiationErrorIDs.contains(errorID)
    }
}
