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
/// A server that refuses TLS is worth a second attempt without it, and that fallback is why the
/// framework connects twice. A host that never answered is not: the second attempt takes the same
/// route as the first, waits the same connection timeout and fails the same way, which doubles the
/// time the interface stands still before the user is told the connection is gone.
@objc(SAConnectionRetryPolicy)
public final class SAConnectionRetryPolicy: NSObject {

    /// The client errors that mean the server was never reached, so TLS cannot have been the reason.
    private static let unreachableErrorIDs: Set<UInt> = [
        UInt(CR_CONNECTION_ERROR),  // the local socket could not be used
        UInt(CR_CONN_HOST_ERROR),   // the host did not answer
        UInt(CR_UNKNOWN_HOST)       // the host could not be resolved
    ]

    /// Whether a connection attempt that failed with this error should be repeated without TLS.
    /// - Parameter errorID: The client or server error the attempt ended with.
    /// - Returns: `false` only for errors that report a server the client never reached.
    @objc(shouldRetryWithoutTLSAfterErrorID:)
    public static func shouldRetryWithoutTLS(afterErrorID errorID: UInt) -> Bool {
        !unreachableErrorIDs.contains(errorID)
    }
}
