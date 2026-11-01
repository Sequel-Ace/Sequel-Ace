//
//  SADialogAuthTransport.swift
//  SPMySQLFramework
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//
//  More info at <https://github.com/Sequel-Ace/Sequel-Ace>
//

import Foundation
@_implementationOnly import MySQLClient

/// Reports what a raw client handle negotiated, for callers that are handed
/// one by the client library rather than holding an `SPMySQLConnection`.
@objc public final class SADialogAuthTransport: NSObject {

    /// Whether `handle` is carrying its traffic over TLS.
    ///
    /// The client library negotiates TLS before the server names the
    /// authentication plugin it wants, so this is already settled by the time
    /// a `dialog` prompt arrives — which is what decides whether the answer
    /// to that prompt would cross the network in the clear.
    @objc(isEncryptedForHandle:)
    public class func isEncrypted(handle: UnsafeMutableRawPointer) -> Bool {
        mysql_get_ssl_cipher(handle.assumingMemoryBound(to: MYSQL.self)) != nil
    }

    /// A negotiated cipher proves encryption, not who owns the server. Only
    /// VERIFY_IDENTITY checks both the certificate chain and the host name.
    @objc(isServerVerifiedForHandle:)
    public class func isServerVerified(handle: UnsafeMutableRawPointer) -> Bool {
        let mysql = handle.assumingMemoryBound(to: MYSQL.self)
        var mode = SSL_MODE_DISABLED
        return mysql_get_ssl_cipher(mysql) != nil
            && mysql_get_option(mysql, MYSQL_OPT_SSL_MODE, &mode) == 0
            && mode == SSL_MODE_VERIFY_IDENTITY
    }
}
