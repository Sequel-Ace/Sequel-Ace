//
//  SAOfflineEscapingHandle.swift
//  SPMySQLFramework
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//
//  More info at <https://github.com/Sequel-Ace/Sequel-Ace>
//

import Foundation
@_implementationOnly import MySQLClient

/// A client-library handle that escapes values for one character set, without a server.
///
/// A connection whose session is about to be replaced may still follow a character set that is no
/// longer the one on record, while the values it escapes go to the session that replaces it - whose
/// handshake uses the character set on record. Those values are escaped with this handle instead.
/// It is never connected, so the client library changes its character set without asking a
/// server, and it takes over the escaping mode (`NO_BACKSLASH_ESCAPES`) of the connection's current
/// session, as the connection's own handle would.
@objc(SAOfflineEscapingHandle)
public final class SAOfflineEscapingHandle: NSObject {

    private let handle: UnsafeMutablePointer<MYSQL>

    /// Wraps a handle that is ready to escape with; it is closed with this object.
    private init(handle: UnsafeMutablePointer<MYSQL>) {
        self.handle = handle
        super.init()
    }

    /// Closes the handle.
    deinit {
        mysql_close(handle)
    }

    /// Makes a handle for a character set, with the escaping mode of a connection's session.
    /// - Parameters:
    ///   - characterSet: The MySQL name of the character set values are escaped for.
    ///   - rawConnection: The connection's current `MYSQL` handle, if it has one.
    /// - Returns: The handle, or nil if the client library does not know the character set.
    @objc(handleForCharacterSet:escapingModeOfConnection:)
    public static func handle(forCharacterSet characterSet: String,
                              escapingModeOfConnection rawConnection: UnsafeMutableRawPointer?) -> SAOfflineEscapingHandle? {
        let serverStatus = rawConnection?.assumingMemoryBound(to: MYSQL.self).pointee.server_status ?? 0
        return handle(forCharacterSet: characterSet, serverStatus: serverStatus)
    }

    /// Makes a handle for a character set, with a given session status.
    /// - Parameters:
    ///   - characterSet: The MySQL name of the character set values are escaped for.
    ///   - serverStatus: The session status bits the escaping follows.
    /// - Returns: The handle, or nil if the client library does not know the character set.
    static func handle(forCharacterSet characterSet: String, serverStatus: UInt32) -> SAOfflineEscapingHandle? {
        guard let handle = mysql_init(nil) else {
            return nil
        }
        guard mysql_set_character_set(handle, characterSet) == 0 else {
            mysql_close(handle)
            return nil
        }
        handle.pointee.server_status = serverStatus
        return SAOfflineEscapingHandle(handle: handle)
    }

    /// The `MYSQL` handle to escape with. It stays valid for as long as this object lives.
    @objc public var rawHandle: UnsafeMutableRawPointer {
        return UnsafeMutableRawPointer(handle)
    }

    /// The character set the handle escapes for, as the client library names it.
    var characterSetName: String {
        return String(cString: mysql_character_set_name(handle))
    }

    /// Whether the handle escapes for a session in `NO_BACKSLASH_ESCAPES` mode.
    var escapesWithoutBackslashes: Bool {
        return handle.pointee.server_status & UInt32(SERVER_STATUS_NO_BACKSLASH_ESCAPES.rawValue) != 0
    }
}
