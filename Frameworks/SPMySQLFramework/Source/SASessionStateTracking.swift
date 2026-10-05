//
//  SASessionStateTracking.swift
//  SPMySQLFramework
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//
//  More info at <https://github.com/Sequel-Ace/Sequel-Ace>
//

import Foundation
@_implementationOnly import MySQLClient

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
    /// Whether a run of session-state items names the character set statements are read in.
    ///
    /// The server sends system-variable items as name, value, name, value, and only the names
    /// are looked at. `character_set_client` is the one that matters: it is what a statement is
    /// parsed in, and an item carrying it is the only thing that shows this session's changes
    /// reach the client at all - the name the client library holds cannot, because a session
    /// whose reports have stopped keeps naming whatever it was last told.
    /// - Parameter items: One OK packet's items, in the order the server sent them.
    /// - Returns: Whether `character_set_client` is among the names.
    @objc(characterSetIsNamedInItems:)
    public static func characterSetIsNamed(in items: [String]) -> Bool {
        for (position, item) in items.enumerated() where position % 2 == 0 {
            if item == "character_set_client" {
                return true
            }
        }
        return false
    }


    /// Whether the result packet just read named the session's character set.
    ///
    /// The server reports a session-state change alongside the packet that closes a result, and
    /// the client library keeps those items only until the next packet is read - so this is
    /// asked once per result, while the connection is still held, and never afterwards. The
    /// items alternate name and value; what they mean is decided by
    /// ``characterSetIsNamed(in:)``, which this reads them for.
    /// - Parameter rawConnection: The connected handle whose last packet is being looked at.
    /// - Returns: Whether the character set was among the variables the packet named.
    @objc(characterSetIsNamedInTheCurrentResultPacketOf:)
    public static func characterSetIsNamedInTheCurrentResultPacket(of rawConnection: UnsafeMutableRawPointer) -> Bool {
        let connection = rawConnection.assumingMemoryBound(to: MYSQL.self)
        var items: [String] = []
        var item: UnsafePointer<CChar>?
        var length = 0
        var more = mysql_session_track_get_first(connection, SESSION_TRACK_SYSTEM_VARIABLES, &item, &length)
        while more == 0 {
            if let item {
                items.append(String(decoding: UnsafeRawBufferPointer(start: item, count: length), as: UTF8.self))
            } else {
                items.append("")
            }
            more = mysql_session_track_get_next(connection, SESSION_TRACK_SYSTEM_VARIABLES, &item, &length)
        }
        return characterSetIsNamed(in: items)
    }

}
