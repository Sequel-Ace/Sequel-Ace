//
//  SAVividPaletteTests.swift
//  Unit Tests
//

import XCTest
import AppKit

final class SAVividPaletteTests: XCTestCase {

    /// The tint is lighter on a light surface than on a dark one.
    func testTintAlphas() {
        XCTAssertEqual(SAVividColor.tintAlphaDark, 0.16)
        XCTAssertEqual(SAVividColor.tintAlphaLight, 0.12)
    }
}
