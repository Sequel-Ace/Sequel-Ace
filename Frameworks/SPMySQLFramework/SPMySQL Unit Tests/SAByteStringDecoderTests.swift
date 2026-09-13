//
//  SAByteStringDecoderTests.swift
//  SPMySQLFramework
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//
//  More info at <https://github.com/Sequel-Ace/Sequel-Ace>
//

import Foundation
import XCTest
@testable import SPMySQL

final class SAByteStringDecoderTests: XCTestCase {
    private let utf8 = String.Encoding.utf8.rawValue

    /// エスキューエル in UTF-8: seven characters of three bytes each.
    private let katakana: [UInt8] = [
        0xE3, 0x82, 0xA8, 0xE3, 0x82, 0xB9, 0xE3, 0x82, 0xAD, 0xE3, 0x83, 0xA5,
        0xE3, 0x83, 0xBC, 0xE3, 0x82, 0xA8, 0xE3, 0x83, 0xAB,
    ]

    private func data(_ bytes: [UInt8], dropLast: Int = 0) -> String {
        bytes.withUnsafeBytes { SAByteStringDecoder.string(forDataBytes: $0.baseAddress, length: bytes.count - dropLast, encoding: utf8) }
    }

    private func identifier(_ bytes: [UInt8], dropLast: Int = 0) -> String {
        bytes.withUnsafeBytes { SAByteStringDecoder.string(forIdentifierBytes: $0.baseAddress, length: bytes.count - dropLast, encoding: utf8) }
    }

    // MARK: Data

    func testDataDecodesValidBytesUntouched() {
        XCTAssertEqual(data(katakana), "エスキューエル")
        XCTAssertEqual(data([]), "")
        XCTAssertEqual(SAByteStringDecoder.string(forDataBytes: nil, length: 0, encoding: utf8), "")
    }

    func testDataPreservesEmbeddedNul() {
        XCTAssertEqual(data([0x61, 0x00, 0x62]), "a\u{0}b")
    }

    func testDataKeepsEveryByteVisibleWhenInvalid() {
        // Cut one byte into the last character: the data decode must not trim.
        let converted = data(katakana, dropLast: 2)
        XCTAssertEqual(converted.utf16.count, katakana.count - 2, "fallback maps each byte to one code point")
        XCTAssertEqual(Array(converted.unicodeScalars.prefix(3)).map(\.value), [0xE3, 0x82, 0xA8], "fallback keeps the byte values as Latin 1 code points")
        XCTAssertFalse(converted.hasSuffix("…"))
    }

    func testDataDecodesBytesInvalidInEveryUnicodeEncoding() {
        XCTAssertEqual(data([0xFF, 0xFE]), "\u{FF}\u{FE}")
    }

    // MARK: Identifiers

    func testIdentifierEmptyInputs() {
        XCTAssertEqual(SAByteStringDecoder.string(forIdentifierBytes: nil, length: 0, encoding: utf8), "")
        XCTAssertEqual(identifier(katakana, dropLast: katakana.count), "")
    }

    func testIdentifierDecodesValidNameUntouched() {
        XCTAssertEqual(identifier(katakana), "エスキューエル")
    }

    func testIdentifierCutOneByteIntoCharacterIsTrimmedAndMarked() {
        XCTAssertEqual(identifier(katakana, dropLast: 2), "エスキューエ…")
    }

    func testIdentifierCutTwoBytesIntoCharacterIsTrimmedAndMarked() {
        XCTAssertEqual(identifier(katakana, dropLast: 1), "エスキューエ…")
    }

    func testIdentifierWithUnrepairableBytesFallsBackToDataDecode() {
        // Invalid bytes in the middle cannot be repaired by trimming the tail; every byte must stay visible.
        let broken: [UInt8] = [0x61, 0x62, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x63, 0x64]
        let converted = identifier(broken)
        XCTAssertEqual(converted.utf16.count, broken.count)
        XCTAssertTrue(converted.hasPrefix("ab") && converted.hasSuffix("cd"))
        XCTAssertFalse(converted.hasSuffix("…"))
    }

    func testIdentifierOnlyPartialBytesIsNotTrimmedToNothing() {
        // A name consisting solely of a partial character has nothing left to show once trimmed,
        // so it falls back to the byte-preserving decode rather than returning a bare ellipsis.
        let converted = identifier([0xE3, 0x82])
        XCTAssertEqual(converted.utf16.count, 2)
        XCTAssertFalse(converted.hasSuffix("…"))
    }
}
