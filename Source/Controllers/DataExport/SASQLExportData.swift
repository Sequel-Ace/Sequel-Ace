//
//  SASQLExportData.swift
//  Sequel Ace
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import Foundation

/// Chooses the string representation of a raw-byte value in a SQL dump.
@objc final class SASQLExportData: NSObject {

    /// Returns text to pass to the connection's string escaper, or nil to preserve
    /// the bytes with its hex escaper. Decoding must never replace invalid bytes.
    ///
    /// MariaDB marks native UUID/INET values as binary in the wire metadata, but
    /// sends their printable text. Hex-encoding those text bytes makes MariaDB
    /// read them as the types' packed binary representation on import (#2786).
    /// Real BLOB/BINARY columns must still honor the option, even if their bytes
    /// happen to spell a UUID or IP address.
    @objc(textFromData:fieldType:encodeBLOBAsHex:connectionEncoding:)
    static func text(from data: Data, fieldType: String?, encodeBLOBAsHex: Bool,
                     connectionEncoding: UInt) -> String? {
        switch fieldType?.uppercased() {
        case "UUID", "INET4", "INET6":
            break
        default:
            guard !encodeBLOBAsHex else { return nil }
        }
        // Use the result encoding (utf8mb4 during SQL export), not the file encoding.
        return String(data: data, encoding: String.Encoding(rawValue: connectionEncoding))
    }
}
