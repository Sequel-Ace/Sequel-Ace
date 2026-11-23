//
//  SASQLExportDataTests.swift
//  Sequel Ace
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import Foundation
import XCTest

final class SASQLExportDataTests: XCTestCase {
    private let uuids = [
        "9df7c4a3-6268-435a-b704-000e547aa2e1",
        "9e841233-ff1e-43af-8ade-0093306507b1"
    ]

    private func text(_ data: Data, type: String?, hex: Bool,
                      encoding: String.Encoding = .utf8) -> String? {
        SASQLExportData.text(from: data, fieldType: type, encodeBLOBAsHex: hex,
                             connectionEncoding: encoding.rawValue)
    }

    /// MariaDB returns the 36 bytes of UUID text, not the UUID's 16-byte storage.
    func testNativeUUIDsRemainTextWithEitherBLOBSetting() {
        for uuid in uuids {
            for type in ["UUID", "uuid"] {
                for hex in [true, false] {
                    XCTAssertEqual(text(Data(uuid.utf8), type: type, hex: hex), uuid,
                                   "type=\(type), hex=\(hex)")
                }
            }
        }
    }

    /// These native MariaDB types also send text with the protocol's binary flag.
    func testNativeIPAddressesRemainTextWithEitherBLOBSetting() {
        let addresses = [
            ("INET4", "192.0.2.1"),
            ("inet4", "0.0.0.0"),
            ("INET6", "2001:db8::1"),
            ("inet6", "::ffff:192.0.2.1"),
            ("INET6", "::")
        ]
        for (type, address) in addresses {
            for hex in [true, false] {
                XCTAssertEqual(text(Data(address.utf8), type: type, hex: hex), address,
                               "type=\(type), hex=\(hex)")
            }
        }
    }

    /// A textual payload must not make a real binary column bypass the hex option.
    func testBinaryColumnsKeepHexEvenWhenTheirBytesLookLikeUUIDText() {
        for type in ["BINARY", "VARBINARY", "TINYBLOB", "BLOB", "MEDIUMBLOB", "LONGBLOB"] {
            XCTAssertNil(text(Data(uuids[0].utf8), type: type, hex: true), type)
            XCTAssertNil(text(Data([0, 255, 39, 92]), type: type, hex: true), type)
        }
    }

    func testUnknownTypesKeepExistingHexBehavior() {
        for type: String? in [nil, "", "FUTURE_TYPE", "VARCHAR", "TEXT"] {
            XCTAssertNil(text(Data("value".utf8), type: type, hex: true))
        }
    }

    func testHexDisabledUsesTheConnectionEncoding() {
        XCTAssertEqual(text(Data([0x63, 0x61, 0x66, 0xe9]), type: "TEXT", hex: false,
                            encoding: .windowsCP1252), "café")
        XCTAssertEqual(text(Data("東京 😀".utf8), type: "TEXT", hex: false), "東京 😀")
    }

    func testInvalidTextFallsBackToHexWithoutLosingBytes() {
        for type in ["UUID", "INET4", "INET6", "BLOB", "VARBINARY", "TEXT"] {
            XCTAssertNil(text(Data([0xff, 0xfe, 0x80]), type: type, hex: false), type)
            XCTAssertNil(text(Data([0xff, 0xfe, 0x80]), type: type, hex: true), type)
        }
    }

    func testDecodedTextPreservesCharactersForTheConnectionEscaper() {
        let value = "quote' backslash\\ nul\0 newline\n"
        XCTAssertEqual(text(Data(value.utf8), type: "BLOB", hex: false), value)
    }
}
