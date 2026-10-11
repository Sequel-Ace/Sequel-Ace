//
//  SASessionTimeZoneRestorer.swift
//  SPMySQLFramework
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import Foundation

/// Reapplies session state without changing the remembered connection preference.
@objc public final class SASessionTimeZoneRestorer: NSObject {
    @objc(restoreTimeZoneIdentifier:onConnection:)
    public static func restore(timeZoneIdentifier: String?, on connection: SPMySQLConnection) -> Bool {
        guard let identifier = timeZoneIdentifier, !identifier.isEmpty else {
            return true
        }

        // A fresh MySQL session needs SET even when the remembered identifier matches.
        // Do not clear that identifier to bypass updateTimeZoneIdentifier's equality
        // guard: a failed SET (or a reconnect inside it) must not forget the preference.
        // Swift imports -mySQLTickQuotedString as mySQLTickQuoted().
        guard let quotedIdentifier = (identifier as NSString).mySQLTickQuoted() else {
            return false
        }
        let result = connection.queryString("SET time_zone = \(quotedIdentifier)")
        // An interrupted query can return nil without installing a new error.
        return result != nil && !connection.queryErrored()
    }
}
