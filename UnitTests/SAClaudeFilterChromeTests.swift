//
//  SAClaudeFilterChromeTests.swift
//  Unit Tests
//

import AppKit
import XCTest

final class SAClaudeFilterChromeTests: XCTestCase {

    private typealias C = SAClaudeFilterChrome

    private func rgb(_ c: NSColor) -> (CGFloat, CGFloat, CGFloat) {
        let s = c.usingColorSpace(.sRGB)!
        return (s.redComponent, s.greenComponent, s.blueComponent)
    }

    func testFieldFillIsALittleTowardsText() {
        let fill = C.fieldFill(text: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1), background: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        XCTAssertEqual(rgb(fill).0, 0.035, accuracy: 0.005)
    }

    func testDropHoverFillIsAFaintClay() {
        let fill = C.dropHoverFill(background: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        let (r, g, b) = rgb(fill)
        XCTAssertGreaterThan(r, g)
        XCTAssertGreaterThan(r, b)
        XCTAssertLessThan(r, 0.2)
    }

    func testDropStrokeIsBrighterThanTheHairline() {
        let white = NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        let black = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
        let stroke = C.dropStroke(text: white, background: black)
        XCTAssertEqual(rgb(stroke).0, 0.30, accuracy: 0.01)
        let hairline = SAClaudeEditorChrome.palette(text: white, background: black).hairline
        XCTAssertGreaterThan(rgb(stroke).0, rgb(hairline).0)
    }

    func testControlFrameIsCentred() {
        let frame = C.controlFrame(in: NSRect(x: 10, y: 0, width: 120, height: 32))
        XCTAssertEqual(frame, NSRect(x: 10, y: 4, width: 120, height: 24))
    }

    func testPillTitleRectLeavesRoomForTheSelector() {
        let title = C.pillTitleRect(in: NSRect(x: 0, y: 4, width: 100, height: 24))
        XCTAssertEqual(title.minX, 9)
        XCTAssertEqual(title.maxX, 100 - 14 - 4)
        XCTAssertEqual(title.minY, 4)
        XCTAssertEqual(title.height, 24)
    }

    func testCheckboxRect() {
        XCTAssertEqual(C.checkboxRect(in: NSRect(x: 2, y: 0, width: 20, height: 32)), NSRect(x: 2, y: 9, width: 14, height: 14))
    }
}
