//
//  SAKeyedArchiveCompatTests.swift
//  Unit Tests
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//
//  More info at <https://github.com/Sequel-Ace/Sequel-Ace>
//

import Foundation
import XCTest

/// Pins the spf session-data wire format across the migration from the
/// deprecated `initForWritingWithMutableData:` / `initForReadingWithData:`
/// pair to `initRequiringSecureCoding:` / `initForReadingFromData:error:`
/// (see SPDatabaseDocument's session save/restore).
///
/// The format contract: a non-secure keyed archive with the payload encoded
/// under the `"data"` key. Files written by old versions must decode with the
/// new reader, and files written by the new code must remain readable by old
/// versions (same keyed format, same key).
final class SAKeyedArchiveCompatTests: XCTestCase {

    /// Generated with the deprecated `NSKeyedArchiver(forWritingWith:)` +
    /// `encode(_:forKey: "data")` — the exact pattern shipped in releases up
    /// to and including 5.x. Payload mirrors a session contentSelection dict.
    private let legacyArchiveBase64 = """
        YnBsaXN0MDDUAQIDBAUGBwpYJHZlcnNpb25ZJGFyY2hpdmVyVCR0b3BYJG9iamVjdHMSAAGGoF8QD05TS2V5ZWRBcmNoaXZlctEICVRkYXRhgAGvEBcLDB0eHyAhIiorLC0zNDU2PD9AQUJHSFUkbnVsbNMNDg8QFhxXTlMua2V5c1pOUy5vYmplY3RzViRjbGFzc6UREhMUFYACgAOABIAFgAalFxgZGhuAB4ARgBKAE4AUgBBfEBBjb250ZW50U2VsZWN0aW9uWGRhdGFiYXNlXxAdd2luZG93VmVydGljYWxEaXZpZGVyUG9zaXRpb25VdGFibGVVdmlld3PTDQ4PIyYcoiQlgAiACaInKIAKgAuAEFR0eXBlVHJvd3NacHJpbWFyeWtledIODy4yoy8wMYAMgA2ADoAPEAEQBRAq0jc4OTpaJGNsYXNzbmFtZVgkY2xhc3Nlc1dOU0FycmF5ojk7WE5TT2JqZWN00jc4PT5cTlNEaWN0aW9uYXJ5oj07V3Rlc3RfZGIjQGrQAAAAAABZY3VzdG9tZXJz0g4PQzKiREWAFYAWgA9Zc3RydWN0dXJlV2NvbnRlbnQACAARABoAJAApADIANwBJAEwAUQBTAG0AcwB6AIIAjQCUAJoAnACeAKAAogCkAKoArACuALAAsgC0ALYAyQDSAPIA+AD+AQUBCAEKAQwBDwERARMBFQEaAR8BKgEvATMBNQE3ATkBOwE9AT8BQQFGAVEBWgFiAWUBbgFzAYABgwGLAZQBngGjAaYBqAGqAawBtgAAAAAAAAIBAAAAAAAAAEkAAAAAAAAAAAAAAAAAAAG+
        """

    private var legacyArchive: Data {
        Data(base64Encoded: legacyArchiveBase64.replacingOccurrences(of: "\n", with: "").trimmingCharacters(in: .whitespaces))!
    }

    /// The reader pattern now used in SPDatabaseDocument.
    private func decodeSessionData(_ data: Data) -> Any? {
        guard let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        unarchiver.requiresSecureCoding = false
        let decoded = unarchiver.decodeObject(forKey: "data")
        unarchiver.finishDecoding()
        return decoded
    }

    /// The writer pattern now used in SPDatabaseDocument.
    private func encodeSessionData(_ payload: Any) -> Data {
        let archiver = NSKeyedArchiver(requiringSecureCoding: false)
        archiver.encode(payload, forKey: "data")
        archiver.finishEncoding()
        return archiver.encodedData
    }

    func testLegacyArchiveDecodesWithNewReader() throws {
        let decoded = try XCTUnwrap(decodeSessionData(legacyArchive) as? [String: Any])

        XCTAssertEqual(decoded["database"] as? String, "test_db")
        XCTAssertEqual(decoded["table"] as? String, "customers")
        XCTAssertEqual(decoded["views"] as? [String], ["structure", "content"])
        XCTAssertEqual(decoded["windowVerticalDividerPosition"] as? Double, 214.5)

        let selection = try XCTUnwrap(decoded["contentSelection"] as? [String: Any])
        XCTAssertEqual(selection["type"] as? String, "primarykey")
        XCTAssertEqual(selection["rows"] as? [Int], [1, 5, 42])
    }

    func testNewWriterRoundTripsThroughNewReader() throws {
        let payload: [String: Any] = [
            "database": "roundtrip_db",
            "contentSelection": ["rows": [7, 9]],
        ]

        let decoded = try XCTUnwrap(decodeSessionData(encodeSessionData(payload)) as? [String: Any])

        XCTAssertEqual(decoded["database"] as? String, "roundtrip_db")
        XCTAssertEqual((decoded["contentSelection"] as? [String: Any])?["rows"] as? [Int], [7, 9])
    }

    func testNewWriterKeepsLegacyWireFormat() throws {
        // Old app versions read via initForReadingWithData: + decodeObjectForKey:@"data",
        // which requires a standard NSKeyedArchiver plist with "data" in $top.
        let plist = try XCTUnwrap(
            try PropertyListSerialization.propertyList(from: encodeSessionData(["k": "v"]), format: nil) as? [String: Any]
        )

        XCTAssertEqual(plist["$archiver"] as? String, "NSKeyedArchiver")
        let top = try XCTUnwrap(plist["$top"] as? [String: Any])
        XCTAssertNotNil(top["data"], "payload must live under the \"data\" key old readers expect")
    }

    func testGarbageDataFailsGracefully() {
        XCTAssertNil(decodeSessionData(Data("definitely not an archive".utf8)))
    }
}
