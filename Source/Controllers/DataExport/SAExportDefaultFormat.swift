//
//  SAExportDefaultFormat.swift
//  Sequel Ace
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import Foundation

/// The values of the "Default Export Format" preference. The raw values are persisted in user
/// defaults and are the menu item tags in Preferences.xib, so they must not change. `automatic`
/// is 0 so that a missing preference keeps the original behaviour.
@objc enum SAExportDefaultFormat: Int {
    case automatic = 0
    case sql
    case csv
    case xml
    case dot
}

/// Decides which format File > Export opens on (#1622).
///
/// `automatic` is the original behaviour: CSV when the Content or Query view is showing rows,
/// otherwise whichever format the last export used. Any other value always wins.
@objc final class SAExportDefaultFormatResolver: NSObject {

    /// - Parameters:
    ///   - preference: The stored preference value. Unknown values count as `automatic`.
    ///   - isResultDisplayed: Whether the Content or Query view is active and showing rows.
    /// - Returns: The format to open on. `automatic` means keep the last export's format.
    @objc(formatForPreference:isResultDisplayed:)
    static func format(forPreference preference: Int, isResultDisplayed: Bool) -> SAExportDefaultFormat {
        let format = SAExportDefaultFormat(rawValue: preference) ?? .automatic

        if format == .automatic && isResultDisplayed {
            return .csv
        }

        return format
    }

    /// Whether a format can export the displayed result rather than tables. SQL and Dot are
    /// table-only: SQL falls back to the tables selected in the table list, Dot to all tables.
    @objc(formatCanExportDisplayedResult:)
    static func canExportDisplayedResult(_ format: SAExportDefaultFormat) -> Bool {
        switch format {
        case .csv, .xml:
            return true
        case .automatic, .sql, .dot:
            return false
        }
    }
}
