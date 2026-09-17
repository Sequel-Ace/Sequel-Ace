//
//  SACleartextAuthPolicy.swift
//  SPMySQLFramework
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import Foundation

/// Decides how a connection attempt negotiates TLS once the cleartext
/// authentication plugin is in play. That plugin hands the password to the
/// server in plain text, so a connection carrying it is only made over TLS.
@objcMembers
public final class SACleartextAuthPolicy: NSObject {

    /// Returns whether the attempt must require TLS rather than merely prefer it.
    ///
    /// Preferring TLS leaves the choice with the server: the client uses TLS only
    /// when the server announces support for it, so anything able to rewrite that
    /// announcement can move the attempt onto an unencrypted connection.
    @objc(requiresTLSWithCleartextPluginEnabled:sslRequested:)
    public class func requiresTLS(cleartextPluginEnabled: Bool, sslRequested: Bool) -> Bool {
        cleartextPluginEnabled || sslRequested
    }

    /// Returns whether a failed attempt may be tried again with TLS disabled.
    ///
    /// The retry sends the password a second time, so it is withheld from any
    /// attempt that would carry a cleartext password.
    @objc(allowsRetryWithoutTLSWithCleartextPluginEnabled:sslRequested:)
    public class func allowsRetryWithoutTLS(cleartextPluginEnabled: Bool, sslRequested: Bool) -> Bool {
        !cleartextPluginEnabled && !sslRequested
    }
}
