//
//  SAExportOutputEncoding.swift
//  Sequel Ace
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import Foundation

/// The export formats that write text files. Mirrors the subset of `SPExportType`
/// (SPConstants.h) that has an exporter; SPExportController maps between the two.
@objc enum SAExportOutputFormat: Int {
    case sql
    case csv
    case xml
    case dot
}

/// Decides which encoding an exporter writes its output file in.
///
/// A file has one encoding. Which one depends on the format:
///
/// - SQL dumps declare `SET NAMES utf8mb4` in their header and the exporter switches the
///   connection to utf8mb4 before fetching anything, so the file is UTF-8 whatever the
///   connection encoding was when the export started. Using the pre-export connection encoding
///   here used to leave the DROP/LOCK statements and comments in one encoding and the rest of
///   the dump in UTF-8 (#2609).
/// - DOT files are UTF-8 as well; the exporter switches the connection the same way.
/// - CSV has no way to declare an encoding and follows the connection encoding.
/// - XML follows the connection encoding for now; its header claims UTF-8, which is a separate
///   fix (#2637).
@objc final class SAExportOutputEncoding: NSObject {

    private static let utf8 = String.Encoding.utf8.rawValue

    /// - Parameters:
    ///   - format: The export format being written.
    ///   - connectionEncoding: The connection's `stringEncoding` at the time the exporters are set up.
    /// - Returns: The `NSStringEncoding` the exporter's `writeString:` has to use.
    @objc(outputEncodingForFormat:connectionEncoding:)
    static func outputEncoding(for format: SAExportOutputFormat, connectionEncoding: UInt) -> UInt {
        switch format {
        case .sql, .dot:
            return utf8
        case .csv, .xml:
            return connectionEncoding
        }
    }
}
