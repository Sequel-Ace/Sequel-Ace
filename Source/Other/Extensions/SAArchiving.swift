//
//  SAArchiving.swift
//  Sequel Ace
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//
//  More info at <https://github.com/Sequel-Ace/Sequel-Ace>
//

import AppKit
import Foundation

/// Centralised keyed + secure archiving for values persisted in `NSUserDefaults`,
/// with backward-compatible reading of legacy non-keyed (`NSArchiver`) data.
///
/// Historically Sequel Ace stored the query-editor font and the syntax-highlight
/// colours via the deprecated `NSArchiver` / `NSUnarchiver`. That non-keyed format
/// is **not** readable by `NSKeyedUnarchiver`, so naively switching readers would
/// silently drop every existing user's saved theme and editor font.
///
/// This helper always *writes* the modern keyed + secure format, while *reading*
/// the modern format first and transparently falling back to the legacy format.
/// Existing preferences therefore survive the upgrade and migrate to the keyed
/// format the next time the user changes the relevant setting.
@objc final class SAArchiving: NSObject {

    // MARK: - Writing (keyed, secure)

    /// Archives a colour using `NSKeyedArchiver` with secure coding.
    @objc(archivedDataForColor:)
    static func archivedData(forColor color: NSColor) -> Data? {
        return try? NSKeyedArchiver.archivedData(withRootObject: color, requiringSecureCoding: true)
    }

    /// Archives a font using `NSKeyedArchiver` with secure coding.
    @objc(archivedDataForFont:)
    static func archivedData(forFont font: NSFont) -> Data? {
        return try? NSKeyedArchiver.archivedData(withRootObject: font, requiringSecureCoding: true)
    }

    // MARK: - Reading (keyed first, then legacy fallback)

    /// Decodes a colour written by either the modern keyed archiver or the legacy
    /// `NSArchiver`. Returns `nil` for missing, empty, or undecodable data.
    @objc(colorFromData:)
    static func color(from data: Data?) -> NSColor? {
        return unarchive(data, as: NSColor.self)
    }

    /// Decodes a font written by either the modern keyed archiver or the legacy
    /// `NSArchiver`. Returns `nil` for missing, empty, or undecodable data.
    @objc(fontFromData:)
    static func font(from data: Data?) -> NSFont? {
        return unarchive(data, as: NSFont.self)
    }

    // MARK: - Private

    private static func unarchive<T>(_ data: Data?, as cls: T.Type) -> T?
    where T: NSObject, T: NSCoding {
        guard let data = data, !data.isEmpty else { return nil }

        // Modern keyed path. Secure decoding only requires that the *decoded*
        // object is of the expected NSSecureCoding class; it does not require the
        // archive to have been written with `requiringSecureCoding`. So this also
        // reads keyed data produced by the older non-secure `NSKeyedArchiver`
        // convenience API (verified by `testReadsNonSecureKeyedArchive`).
        if let value = try? NSKeyedUnarchiver.unarchivedObject(ofClass: cls, from: data) {
            return value
        }

        // Legacy non-keyed (`NSArchiver`) fallback for data written by older versions.
        return legacyUnarchive(data) as? T
    }
}

/// Reads legacy non-keyed archives written by `NSArchiver` in older app versions.
///
/// This is the single, deliberately retained use of the deprecated `NSUnarchiver`:
/// it is the only API able to read the pre-keyed-archive format, so it must stay
/// until that data is fully migrated. Marking the function `@available(deprecated:)`
/// confines the deprecation warning to this one isolated, intentional site.
@available(macOS, deprecated: 10.13, message: "Only for reading pre-keyed-archive user data")
private func legacyUnarchive(_ data: Data) -> Any? {
    return NSUnarchiver.unarchiveObject(with: data)
}
