//
//  SAByteStringDecoder.swift
//  SPMySQLFramework
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//
//  More info at <https://github.com/Sequel-Ace/Sequel-Ace>
//

import Foundation

/// Byte-to-string conversion for everything the server sends back: cell values and
/// result-set metadata (column, alias, table and database names). Both entry points
/// preserve embedded NUL bytes and never return nil.
@objcMembers
public final class SAByteStringDecoder: NSObject {
    /// The longest partial character the server can leave behind when it truncates
    /// an identifier at a byte boundary, across every charset the framework maps
    /// (UTF-8, UTF-16, UTF-32 and GB18030 all top out at four bytes per character).
    static let maxPartialCharacterBytes = 4

    /// Decodes cell data. Bytes that are not valid in `encoding` fall back to a
    /// byte-preserving ISO Latin 1 decode so that every byte stays visible: data
    /// must never be shortened.
    @objc(stringForDataBytes:length:encoding:)
    public static func string(forDataBytes bytes: UnsafeRawPointer?, length: Int, encoding: UInt) -> String {
        if let string = decode(bytes, length: length, encoding: encoding) {
            return string
        }
        // ISO Latin 1 maps every byte 0-255 to a code point, so this cannot fail.
        return decode(bytes, length: length, encoding: String.Encoding.isoLatin1.rawValue) ?? ""
    }

    /// Decodes an identifier. The server truncates over-long identifiers, aliases in
    /// particular, at a byte boundary, which can split a multibyte character; NSString
    /// then rejects the whole sequence. Drops up to `maxPartialCharacterBytes` trailing
    /// bytes and marks the loss with an ellipsis. If that does not yield a valid string,
    /// falls back to the byte-preserving decode used for data.
    @objc(stringForIdentifierBytes:length:encoding:)
    public static func string(forIdentifierBytes bytes: UnsafeRawPointer?, length: Int, encoding: UInt) -> String {
        guard let bytes, length > 0 else { return "" }
        if let string = decode(bytes, length: length, encoding: encoding) {
            return string
        }
        var removed = 1
        while removed <= maxPartialCharacterBytes && removed < length {
            if let string = decode(bytes, length: length - removed, encoding: encoding) {
                return string + "\u{2026}"
            }
            removed += 1
        }
        return string(forDataBytes: bytes, length: length, encoding: encoding)
    }

    private static func decode(_ bytes: UnsafeRawPointer?, length: Int, encoding: UInt) -> String? {
        guard let bytes, length > 0 else { return "" }
        return NSString(bytes: bytes, length: length, encoding: encoding) as String?
    }
}
