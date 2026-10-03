//
//  SASessionStateTracking.swift
//  SPMySQLFramework
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//
//  More info at <https://github.com/Sequel-Ace/Sequel-Ace>
//

import Foundation

/// Makes a session report the character set it is actually running in.
///
/// Escaping follows what the session reports, and the client library learns of a change only
/// through the server's session-state tracking: `SET NAMES` does not update the library's own
/// record the way `mysql_set_character_set()` does. A server whose
/// `session_track_system_variables` does not list `character_set_client` therefore leaves a
/// `SET NAMES` the user ran invisible, and values go on being escaped for the character set the
/// connection last set itself. For a session moved to GBK that is the difference between
/// `5C BF 5C 27` and `BF 5C 27`: the second leaves the quote unescaped, because GBK reads
/// `BF 5C` as one character.
///
/// The variable is settable per session, so the connection turns the tracking on for itself
/// rather than relying on the server's configuration.
@objc(SASessionStateTracking)
public final class SASessionStateTracking: NSObject {

    /// The system variables a connection needs reported back to it.
    static let required = ["character_set_client"]

    /// The value to set `session_track_system_variables` to, given what it holds now.
    ///
    /// The server rejects a list with a repeated entry, so an entry already present is not added
    /// again, and a session that already reports everything is left alone.
    /// - Parameter current: The session's current value, as the server reports it.
    /// - Returns: The value to set, or nil when the session already reports what is needed.
    @objc(trackingListToSetGivenCurrentList:)
    public static func trackingListToSet(givenCurrentList current: String?) -> String? {
        let listed = (current ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }

        // "*" tracks every variable, so there is nothing to add.
        if listed.contains("*") {
            return nil
        }
        let missing = required.filter { !listed.contains($0) }
        if missing.isEmpty {
            return nil
        }
        return (listed + missing).joined(separator: ",")
    }
}
