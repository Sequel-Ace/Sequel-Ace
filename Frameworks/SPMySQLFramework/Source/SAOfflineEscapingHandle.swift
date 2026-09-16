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

    /// Escapes bytes for a string literal, in the handle's character set and escaping mode.
    ///
    /// In `NO_BACKSLASH_ESCAPES` mode the client library refuses to escape with backslashes; quotes
    /// are then doubled instead, for a literal in single quotes, as the connection does for its own
    /// handle.
    /// - Parameter bytes: The value, already in the handle's character set.
    /// - Returns: The escaped bytes, without surrounding quotes, or nil if they could not be escaped.
    @objc(escapedBytes:)
    public func escapedBytes(_ bytes: Data) -> Data? {
        if bytes.isEmpty {
            return Data()
        }
        var output = [CChar](repeating: 0, count: bytes.count * 2 + 1)
        let failed = UInt.max
        let length: UInt = bytes.withUnsafeBytes { rawSource in
            let source = rawSource.bindMemory(to: CChar.self).baseAddress
            let sourceLength = UInt(bytes.count)
            let escaped = mysql_real_escape_string(handle, &output, source, sourceLength)
            guard escaped == failed, mysql_errno(handle) == UInt32(CR_INSECURE_API_ERR) else {
                return escaped
            }
            return mysql_real_escape_string_quote(handle, &output, source, sourceLength, CChar(UInt8(ascii: "'")))
        }
        guard length != failed else {
            return nil
        }
        return Data(bytes: output, count: Int(length))
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
