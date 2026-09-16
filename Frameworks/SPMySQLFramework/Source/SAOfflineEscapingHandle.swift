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
            output.withUnsafeMutableBytes { destination -> Int in
                guard let destination = destination.baseAddress else {
                    return -1
                }
                return escape(source.baseAddress, length: bytes.count, into: destination)
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
/// work, while a value is escaped on another thread. So values are escaped with a handle of the
/// connection's own that is never connected, set up again whenever the character set or the
/// escaping mode changes. What the session reports - its character set, which the client library
/// follows through session tracking, and its `NO_BACKSLASH_ESCAPES` mode - is recorded while the
/// connection is held, after it connects and after every statement.
@objc(SAConnectionEscaper)
public final class SAConnectionEscaper: NSObject {

    private let lock = NSLock()
    private var handshakeCharacterSet: String?
    private var sessionCharacterSet: String?
    private var sessionUsesNoBackslashEscapes = false
    private var lastHandshakeUsedNoBackslashEscapes = false
    private var sessionHasOpenTransaction = false
    private var handleCharacterSet: String?
    private var handleUsesNoBackslashEscapes = false
    private var handle: SAOfflineEscapingHandle?

    /// Decides which character set a value is escaped for.
    ///
    /// A session that is about to be replaced may follow a character set that is no longer the one
    /// on record, which the next session's handshake uses; its values follow the record. Otherwise a
    /// session whose character set differs from the one it was connected with has been told about a
    /// change - by the connection, or by a statement the user ran - and the client library followed
    /// it; that is what the session reads values in. A session still on its handshake character set
    /// either had no change, or runs on a server that does not report changes, where the record,
    /// which follows every change the connection makes, is the better guide.
    /// - Parameters:
    ///   - characterSetOnRecord: The connection's character set on record.
    ///   - sessionCharacterSet: The character set the session last reported, if known.
    ///   - handshakeCharacterSet: The character set the session was connected with, if known.
    ///   - sessionIsBeingReplaced: Whether the session is to be replaced before its next use.
    /// - Returns: The character set to escape for, or nil if there is none.
    static func characterSetForEscaping(onRecord characterSetOnRecord: String?,
                                        session sessionCharacterSet: String?,
                                        handshake handshakeCharacterSet: String?,
                                        sessionIsBeingReplaced: Bool) -> String? {
        if sessionIsBeingReplaced {
            return characterSetOnRecord
        }
        if let sessionCharacterSet, let handshakeCharacterSet,
           sessionCharacterSet.caseInsensitiveCompare(handshakeCharacterSet) != .orderedSame {
            return sessionCharacterSet
        }
        return characterSetOnRecord ?? sessionCharacterSet
    }

    /// Records what the session reports. Called while the connection is held.
    /// - Parameters:
    ///   - characterSet: The session's character set as the client library names it.
    ///   - noBackslashEscapes: Whether the session is in `NO_BACKSLASH_ESCAPES` mode.
    ///   - openTransaction: Whether the session has a transaction open.
    ///   - isHandshake: Whether the session has just been connected.
    @objc(recordSessionCharacterSet:noBackslashEscapes:openTransaction:isHandshake:)
    public func recordSession(characterSet: String?, noBackslashEscapes: Bool, openTransaction: Bool, isHandshake: Bool) {
        lock.lock()
        defer { lock.unlock() }
        if isHandshake {
            handshakeCharacterSet = characterSet
            lastHandshakeUsedNoBackslashEscapes = noBackslashEscapes
        }
        sessionCharacterSet = characterSet
        sessionUsesNoBackslashEscapes = noBackslashEscapes
        sessionHasOpenTransaction = openTransaction
    }

    /// Whether the session last reported an open transaction.
    @objc public var sessionReportedOpenTransaction: Bool {
        lock.lock()
        defer { lock.unlock() }
        return sessionHasOpenTransaction
    }

    /// Forgets what a session reported, once that session is closed. Until the next session
    /// connects, values follow the record, which that session's handshake uses, and the escaping mode
    /// the last handshake reported - the server's own, which a mode the closed session was switched
    /// to does not outlive.
    @objc public func forgetSession() {
        lock.lock()
        defer { lock.unlock() }
        handshakeCharacterSet = nil
        sessionCharacterSet = nil
        sessionUsesNoBackslashEscapes = lastHandshakeUsedNoBackslashEscapes
        sessionHasOpenTransaction = false
    }

    /// Escapes bytes for a string literal.
    /// - Parameters:
    ///   - source: The value, already in the connection's string encoding.
    ///   - length: The number of bytes in the value.
    ///   - destination: Room for at least twice the value's length and one more byte.
    ///   - characterSetOnRecord: The connection's character set on record.
    ///   - sessionIsBeingReplaced: Whether the session is to be replaced before its next use.
    /// - Returns: The number of escaped bytes written, or -1 if the value could not be escaped -
    ///   when there is no character set to escape for, or the client library does not know it.
    @objc(escapeBytes:length:into:characterSetOnRecord:sessionIsBeingReplaced:)
    public func escape(_ source: UnsafeRawPointer?,
                       length: Int,
                       into destination: UnsafeMutableRawPointer,
                       characterSetOnRecord: String?,
                       sessionIsBeingReplaced: Bool) -> Int {
        lock.lock()
        defer { lock.unlock() }
        guard let characterSet = Self.characterSetForEscaping(onRecord: characterSetOnRecord,
                                                              session: sessionCharacterSet,
                                                              handshake: handshakeCharacterSet,
                                                              sessionIsBeingReplaced: sessionIsBeingReplaced) else {
            return -1
        }
        let noBackslashEscapes = sessionUsesNoBackslashEscapes
        if handle == nil || handleCharacterSet != characterSet || handleUsesNoBackslashEscapes != noBackslashEscapes {
            handle = SAOfflineEscapingHandle.handle(
                forCharacterSet: characterSet,
                serverStatus: noBackslashEscapes ? SAOfflineEscapingHandle.noBackslashEscapesStatus : 0
            )
            handleCharacterSet = characterSet
            handleUsesNoBackslashEscapes = noBackslashEscapes
        }
        guard let handle else {
            return -1
        }
        return handle.escape(source, length: length, into: destination)
    }
}
