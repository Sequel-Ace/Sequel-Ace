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
/// It is never connected, so the client library changes its character set without asking a
/// server, and it escapes in the mode (`NO_BACKSLASH_ESCAPES` or not) it is given.
final class SAOfflineEscapingHandle {

    private let handle: UnsafeMutablePointer<MYSQL>

    /// Wraps a handle that is ready to escape with; it is closed with this object.
    private init(handle: UnsafeMutablePointer<MYSQL>) {
        self.handle = handle
    }

    /// Closes the handle.
    deinit {
        mysql_close(handle)
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
    /// are then doubled instead, for a literal in single quotes.
    /// - Parameters:
    ///   - source: The value, already in the handle's character set.
    ///   - length: The number of bytes in the value.
    ///   - destination: Room for at least twice the value's length and one more byte.
    /// - Returns: The number of escaped bytes written, or -1 if the value could not be escaped.
    func escape(_ source: UnsafeRawPointer?, length: Int, into destination: UnsafeMutableRawPointer) -> Int {
        guard length > 0, let source else {
            return 0
        }
        let from = source.assumingMemoryBound(to: CChar.self)
        let to = destination.assumingMemoryBound(to: CChar.self)
        let failed = UInt.max
        var escaped = mysql_real_escape_string(handle, to, from, UInt(length))
        if escaped == failed, mysql_errno(handle) == UInt32(CR_INSECURE_API_ERR) {
            escaped = mysql_real_escape_string_quote(handle, to, from, UInt(length), CChar(UInt8(ascii: "'")))
        }
        return escaped == failed ? -1 : Int(escaped)
    }

    /// Escapes a value held in `Data`; see ``escape(_:length:into:)``.
    /// - Parameter bytes: The value, already in the handle's character set.
    /// - Returns: The escaped bytes, without surrounding quotes, or nil if they could not be escaped.
    func escapedBytes(_ bytes: Data) -> Data? {
        var output = [UInt8](repeating: 0, count: bytes.count * 2 + 1)
        let length = bytes.withUnsafeBytes { source in
            output.withUnsafeMutableBytes { destination in
                escape(source.baseAddress, length: bytes.count, into: destination.baseAddress!)
            }
        }
        return length < 0 ? nil : Data(output.prefix(length))
    }

    /// The character set the handle escapes for, as the client library names it.
    var characterSetName: String {
        return String(cString: mysql_character_set_name(handle))
    }

    /// Whether the handle escapes for a session in `NO_BACKSLASH_ESCAPES` mode.
    var escapesWithoutBackslashes: Bool {
        return handle.pointee.server_status & Self.noBackslashEscapesStatus != 0
    }

    /// The session status bit for `NO_BACKSLASH_ESCAPES`.
    static let noBackslashEscapesStatus = UInt32(SERVER_STATUS_NO_BACKSLASH_ESCAPES.rawValue)
}

/// Escapes a connection's values without touching its session.
///
/// The session's own handle can be in use by work nobody waits for any more, or be closed by that
/// work, while a value is escaped on another thread; and a session that is about to be replaced may
/// follow a character set that is no longer the one on record, which the next session's handshake
/// uses. So values are escaped with a handle of the connection's own that is never connected, set
/// up for the character set on record and the escaping mode of the latest session, and set up again
/// when either changes.
@objc(SAConnectionEscaper)
public final class SAConnectionEscaper: NSObject {

    private let lock = NSLock()
    private var characterSet: String?
    private var noBackslashEscapes = false
    private var handle: SAOfflineEscapingHandle?

    /// Escapes bytes for a string literal.
    /// - Parameters:
    ///   - source: The value, already in the character set on record.
    ///   - length: The number of bytes in the value.
    ///   - destination: Room for at least twice the value's length and one more byte.
    ///   - characterSet: The connection's character set on record.
    ///   - noBackslashEscapes: Whether the latest session was in `NO_BACKSLASH_ESCAPES` mode.
    /// - Returns: The number of escaped bytes written, or -1 if the value could not be escaped -
    ///   when there is no character set on record, or the client library does not know it.
    @objc(escapeBytes:length:into:characterSet:noBackslashEscapes:)
    public func escape(_ source: UnsafeRawPointer?,
                       length: Int,
                       into destination: UnsafeMutableRawPointer,
                       characterSet: String?,
                       noBackslashEscapes: Bool) -> Int {
        guard let characterSet else {
            return -1
        }
        lock.lock()
        defer { lock.unlock() }
        if handle == nil || self.characterSet != characterSet || self.noBackslashEscapes != noBackslashEscapes {
            handle = SAOfflineEscapingHandle.handle(
                forCharacterSet: characterSet,
                serverStatus: noBackslashEscapes ? SAOfflineEscapingHandle.noBackslashEscapesStatus : 0
            )
            self.characterSet = characterSet
            self.noBackslashEscapes = noBackslashEscapes
        }
        guard let handle else {
            return -1
        }
        return handle.escape(source, length: length, into: destination)
    }
}
