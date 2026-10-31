//
//  SAFontDisplayNameTests.swift
//  Unit Tests
//
//  System UI fonts get a readable family + style; other fonts keep their
//  displayName.
//

import AppKit
import XCTest

final class SAFontDisplayNameTests: XCTestCase {

    func testSystemMonospacedRegular() {
        let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        XCTAssertEqual(SAFontDisplayName.name(for: font), "SF Mono Regular")
    }

    func testSystemMonospacedBold() {
        let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .bold)
        XCTAssertEqual(SAFontDisplayName.name(for: font), "SF Mono Bold")
    }

    func testSystemFontIsSFPro() {
        let font = NSFont.systemFont(ofSize: 13)
        XCTAssertEqual(SAFontDisplayName.name(for: font), "SF Pro Regular")
    }

    func testOtherFontsKeepTheirDisplayName() throws {
        let font = try XCTUnwrap(NSFont(name: "Menlo-Regular", size: 14))
        XCTAssertEqual(SAFontDisplayName.name(for: font), font.displayName)
        XCTAssertEqual(SAFontDisplayName.name(for: font), "Menlo Regular")
    }
}
