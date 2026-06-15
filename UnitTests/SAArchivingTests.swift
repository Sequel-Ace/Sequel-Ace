//
//  SAArchivingTests.swift
//  Unit Tests
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import XCTest
import AppKit

/// Tests for `SAArchiving` — the keyed/secure archiving helper with a
/// backward-compatible legacy (`NSArchiver`) read path.
///
/// The backward-compat tests are the important ones: they prove that user data
/// written by older app versions in the non-keyed format still decodes, so the
/// migration does not silently drop saved editor fonts and theme colours.
final class SAArchivingTests: XCTestCase {

    // MARK: - Keyed round-trip (modern format)

    func testColorKeyedRoundTrip() throws {
        let color = NSColor(calibratedRed: 0.2, green: 0.4, blue: 0.6, alpha: 0.8)
        let data = try XCTUnwrap(SAArchiving.archivedData(forColor: color), "archiving should produce data")
        let decoded = try XCTUnwrap(SAArchiving.color(from: data), "modern data should decode")
        assertColorsEqual(decoded, color)
    }

    func testFontKeyedRoundTrip() throws {
        let font = try XCTUnwrap(NSFont(name: "Menlo", size: 13), "Menlo should be available")
        let data = try XCTUnwrap(SAArchiving.archivedData(forFont: font), "archiving should produce data")
        let decoded = try XCTUnwrap(SAArchiving.font(from: data), "modern data should decode")
        XCTAssertEqual(decoded.fontName, font.fontName)
        XCTAssertEqual(decoded.pointSize, font.pointSize, accuracy: 0.001)
    }

    // MARK: - Backward compatibility (legacy NSArchiver format → still readable)

    func testColorReadsLegacyNonKeyedArchive() throws {
        let color = NSColor(calibratedRed: 0.9, green: 0.1, blue: 0.3, alpha: 1.0)
        let legacyData = legacyArchivedData(color)               // written like an old app version
        // The modern keyed reader cannot read this; the helper must fall back.
        XCTAssertNil(try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: legacyData),
                     "precondition: keyed reader should not understand legacy data")
        let decoded = try XCTUnwrap(SAArchiving.color(from: legacyData), "legacy colour data must still decode")
        assertColorsEqual(decoded, color)
    }

    func testFontReadsLegacyNonKeyedArchive() throws {
        let font = try XCTUnwrap(NSFont(name: "Courier", size: 11))
        let legacyData = legacyArchivedData(font)
        let decoded = try XCTUnwrap(SAArchiving.font(from: legacyData), "legacy font data must still decode")
        XCTAssertEqual(decoded.fontName, font.fontName)
        XCTAssertEqual(decoded.pointSize, font.pointSize, accuracy: 0.001)
    }

    // MARK: - Defensive: bad input

    func testNilDataReturnsNil() {
        XCTAssertNil(SAArchiving.color(from: nil))
        XCTAssertNil(SAArchiving.font(from: nil))
    }

    func testEmptyDataReturnsNil() {
        XCTAssertNil(SAArchiving.color(from: Data()))
        XCTAssertNil(SAArchiving.font(from: Data()))
    }

    func testGarbageDataReturnsNil() {
        let garbage = Data([0x00, 0x01, 0x02, 0xFF, 0xAB, 0xCD, 0xEF])
        XCTAssertNil(SAArchiving.color(from: garbage))
        XCTAssertNil(SAArchiving.font(from: garbage))
    }

    // MARK: - Helpers

    /// Compares two colours in a common colour space to avoid spurious
    /// `isEqual:` mismatches caused by differing source colour spaces.
    private func assertColorsEqual(_ a: NSColor, _ b: NSColor, file: StaticString = #filePath, line: UInt = #line) {
        guard let ca = a.usingColorSpace(.sRGB), let cb = b.usingColorSpace(.sRGB) else {
            XCTFail("colours could not be converted to sRGB", file: file, line: line); return
        }
        XCTAssertEqual(ca.redComponent, cb.redComponent, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(ca.greenComponent, cb.greenComponent, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(ca.blueComponent, cb.blueComponent, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(ca.alphaComponent, cb.alphaComponent, accuracy: 0.001, file: file, line: line)
    }
}

/// Produces data in the legacy non-keyed `NSArchiver` format, mimicking what
/// older app versions wrote to `NSUserDefaults`. Isolated and deprecation-marked
/// so the unavoidable use of `NSArchiver` does not emit a build warning.
@available(macOS, deprecated: 10.13, message: "Generates legacy fixtures for backward-compat tests")
private func legacyArchivedData(_ object: Any) -> Data {
    return NSArchiver.archivedData(withRootObject: object)
}
