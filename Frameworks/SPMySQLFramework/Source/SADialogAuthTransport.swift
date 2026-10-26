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
}
