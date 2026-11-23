//
//  SAClaudeChromeLayoutTests.swift
//  Unit Tests
//
//  Geometry for the Claude everyday chrome: the loading-overlay card and the window tab content.
//

import XCTest
import AppKit

final class SAClaudeChromeLayoutTests: XCTestCase {
    private typealias H = SAClaudeTaskHUDLayout
    private typealias T = SAClaudeTabContentLayout

    func testHUDWithButton() {
        let f = H.frames(buttonWidth: 64)
        XCTAssertEqual(f.spinner, NSRect(x: 16, y: 22, width: 28, height: 28))
        XCTAssertEqual(f.button, NSRect(x: 280, y: 24, width: 64, height: 24))
        XCTAssertEqual(f.description, NSRect(x: 56, y: 36, width: 212, height: 17))
        XCTAssertEqual(f.duration, NSRect(x: 56, y: 19, width: 212, height: 14))
    }

    func testHUDWithoutButtonGivesTheTextTheRoom() {
        let f = H.frames(buttonWidth: nil)
        XCTAssertNil(f.button)
        XCTAssertEqual(f.description.width, 288)
        XCTAssertEqual(f.duration.width, 288)
    }

    func testButtonWidthFitsItsTitle() {
        XCTAssertEqual(H.buttonWidth(titleWidth: 20), 64)
        XCTAssertEqual(H.buttonWidth(titleWidth: 70.2), 95)
        let long = H.frames(buttonWidth: H.buttonWidth(titleWidth: 70.2))
        XCTAssertEqual(long.button?.maxX, 344)
        XCTAssertEqual(long.description.maxX, (long.button?.minX ?? 0) - 12)
    }

    func testRingFraction() {
        XCTAssertEqual(H.ringFraction(value: 25, maximum: 100), 0.25)
        XCTAssertEqual(H.ringFraction(value: 150, maximum: 100), 1)
        XCTAssertEqual(H.ringFraction(value: -3, maximum: 100), 0)
        XCTAssertEqual(H.ringFraction(value: 5, maximum: 0), 0)
    }

    func testTabContentCentredWithDotAndLock() {
        let f = T.frames(size: NSSize(width: 200, height: 24), titleWidth: 100, hasColour: true, isSSL: true)
        XCTAssertEqual(f.dot, NSRect(x: 37, y: 8, width: 7, height: 7))
        XCTAssertEqual(f.title, NSRect(x: 49, y: 4, width: 100, height: 16))
        XCTAssertEqual(f.lock, NSRect(x: 153, y: 7, width: 10, height: 10))
    }

    func testNarrowTabTruncatesTheTitleNotTheGlyphs() {
        let f = T.frames(size: NSSize(width: 80, height: 24), titleWidth: 100, hasColour: true, isSSL: true)
        XCTAssertEqual(f.dot?.minX, 0)
        XCTAssertEqual(f.title, NSRect(x: 12, y: 4, width: 54, height: 16))
        XCTAssertEqual(f.lock?.minX, 70)
    }

    func testPlainTabTitleOnly() {
        let f = T.frames(size: NSSize(width: 200, height: 24), titleWidth: 100, hasColour: false, isSSL: false)
        XCTAssertNil(f.dot); XCTAssertNil(f.lock)
        XCTAssertEqual(f.title, NSRect(x: 50, y: 4, width: 100, height: 16))
    }
}
