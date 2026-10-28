//
//  SASidebarObjectGlyphTests.swift
//  Unit Tests
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import AppKit
import XCTest

final class SASidebarObjectGlyphTests: XCTestCase {

    // SPTableType raw values (keep in sync with SPConstants.h).
    private let expectedSymbols: [Int: String] = [
        0: "tablecells",  // Table
        1: "eye",         // View
        2: "curlybraces", // Proc
        3: "function",    // Func
        4: "clock"        // Event
    ]

    func testEachObjectTypeMapsToItsSymbol() {
        for (rawValue, symbol) in expectedSymbols {
            XCTAssertEqual(SASidebarObjectGlyph.symbolName(forTableTypeRawValue: rawValue), symbol, "raw value \(rawValue)")
        }
    }

    func testHeadersAndUnknownTypesHaveNoSymbol() {
        for rawValue in [-1, 5, 99] {
            XCTAssertNil(SASidebarObjectGlyph.symbolName(forTableTypeRawValue: rawValue), "raw value \(rawValue)")
            XCTAssertNil(SASidebarObjectGlyph.image(forTableTypeRawValue: rawValue), "raw value \(rawValue)")
        }
    }

    func testImagesAreTemplatesWithAnAccessibilityName() throws {
        for rawValue in expectedSymbols.keys.sorted() {
            let image = try XCTUnwrap(SASidebarObjectGlyph.image(forTableTypeRawValue: rawValue), "raw value \(rawValue)")
            XCTAssertTrue(image.isTemplate, "raw value \(rawValue)")
            XCTAssertFalse((image.accessibilityDescription ?? "").isEmpty, "raw value \(rawValue)")
        }
    }
}
