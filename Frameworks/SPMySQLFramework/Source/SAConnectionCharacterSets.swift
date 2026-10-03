//
//  SAConnectionCharacterSets.swift
//  SPMySQLFramework
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//
//  More info at <https://github.com/Sequel-Ace/Sequel-Ace>
//

import Foundation

/// The MySQL character sets this framework can carry values in.
///
/// A connection reads and writes values by converting them between the session's character set
/// and a macOS string encoding. That only works for a character set macOS has a matching encoding
/// for: for the rest there is nothing to convert with, and assuming UTF-8 does not read the
/// session's bytes, it reinterprets them - `swe7`, for instance, puts Swedish letters where ASCII
/// has `@ [ \ ] ^ { | } ~`, so even plain ASCII comes out as different characters. Such a
/// character set is better refused for the connection than used silently: the data itself stays
/// reachable, because the server converts between a table's character set and the session's.
@objc(SAConnectionCharacterSets)
public final class SAConnectionCharacterSets: NSObject {

    /// The character sets `+[SPMySQLConnection stringEncodingForMySQLCharset:]` has a macOS
    /// string encoding for, in MySQL's own spelling, including the pre-4.1 names the server can
    /// still report. A name outside this set either has no encoding that carries it, or is one
    /// this framework has not been taught; neither can be converted with any confidence.
    private static let carriable: Set<String> = [
        // 4.1 and later
        "ascii", "big5", "binary", "cp1250", "cp1251", "cp1256", "cp1257", "cp850", "cp852",
        "cp866", "cp932", "dec8", "eucjpms", "euckr", "gb18030", "gb2312", "gbk", "greek",
        "hebrew", "koi8r", "koi8u", "latin1", "latin2", "latin5", "latin7", "macce", "macroman",
        "sjis", "tis620", "ucs2", "ujis", "utf16", "utf16le", "utf32", "utf8", "utf8mb3",
        "utf8mb4",
        // pre-4.1 names
        "croat", "czech", "danish", "dos", "estonia", "euc_kr", "german1", "hungarian",
        "koi8_ru", "koi8_ukr", "latin1_de", "usa7", "win1250", "win1251", "win1251ukr",
    ]

    /// The name to run a session under, for a character set values can be converted for.
    ///
    /// The name comes back in the spelling the encoding table is keyed by, which matches it
    /// case-sensitively: a session set up as `LATIN5` would otherwise pass this check and then
    /// find no encoding, leaving its values converted as UTF-8.
    /// - Parameter name: The character set's MySQL name, in any case.
    /// - Returns: The name to use, or nil when this framework has no string encoding for it.
    @objc(carriableNameForCharacterSet:)
    public static func carriableName(forCharacterSet name: String?) -> String? {
        guard let name, !name.isEmpty else {
            return nil
        }
        let normalized = name.lowercased()
        return carriable.contains(normalized) ? normalized : nil
    }

    /// Whether values can be converted for a character set, so that it is safe to run a session
    /// in it.
    /// - Parameter name: The character set's MySQL name.
    /// - Returns: `true` when this framework has a string encoding that carries it.
    @objc(canCarryValuesForCharacterSet:)
    public static func canCarryValues(forCharacterSet name: String?) -> Bool {
        return carriableName(forCharacterSet: name) != nil
    }

    /// The character sets whose string encoding is only reachable through CoreFoundation, so
    /// that naming one is a lookup rather than a constant: which MySQL character set a value in
    /// that encoding belongs to.
    ///
    /// Windows-1253 and Windows-1254 are deliberately absent. They were once named for `greek`
    /// and `latin5`, the code pages those character sets were wrongly converted with, and they
    /// disagree with the real ones over 22 and 25 bytes - an import declared that way is read
    /// as something it is not.
    private static let characterSetsByEncoding: [UInt: String] = {
        var table: [UInt: String] = [:]
        for (encoding, name) in [(CFStringEncodings.isoLatinGreek, "greek"),
                                 (CFStringEncodings.isoLatin5, "latin5")] {
            let value = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(encoding.rawValue))
            guard value != kCFStringEncodingInvalidId else {
                continue
            }
            table[value] = name
        }
        return table
    }()

    /// The MySQL character set a value in a string encoding belongs to, for the encodings that
    /// have no constant to switch on.
    /// - Parameter stringEncoding: The `NSStringEncoding` value.
    /// - Returns: The character set's MySQL name, or nil if this table does not name one. The
    ///   caller's own table is asked next.
    @objc(characterSetNameForStringEncoding:)
    public static func characterSetName(forStringEncoding stringEncoding: UInt) -> String? {
        return characterSetsByEncoding[stringEncoding]
    }

    /// The character set a connection falls back to when the one asked for cannot be carried.
    ///
    /// Every server that offers more than the pre-4.1 character sets offers this one, and the
    /// server converts between it and whatever character set a table is in, so no data goes out
    /// of reach by connecting in it.
    @objc public static let fallbackCharacterSet = "utf8mb4"
}
