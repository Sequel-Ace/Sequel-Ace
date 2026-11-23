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

    // MARK: - Checkbox / radio titles

    private typealias T = SAClaudeToggleTitleMetrics

    private func lineWidth(_ line: String) -> CGFloat {
        ceil(NSAttributedString(string: line, attributes: T.attributes).size().width)
    }

    /// Walkthrough 2: "Reset AUTO_INCREMENT after deletion\n(only for Delete ALL ROWS IN TABLE)?" was measured as one string
    /// at the caller's 11pt font and drawn at 12pt, truncated. A title with a newline is measured line by line in the
    /// attributes it is drawn with, and the cell is tall enough for every line.
    func testMultiLineTitleIsMeasuredLineByLineWithTheDrawingAttributes() {
        let title = "Reset AUTO_INCREMENT after deletion\n(only for Delete ALL ROWS IN TABLE)?"
        XCTAssertEqual(T.font, NSFont.systemFont(ofSize: 12))
        let widest = max(lineWidth("Reset AUTO_INCREMENT after deletion"), lineWidth("(only for Delete ALL ROWS IN TABLE)?"))
        let size = T.cellSize(title: title, drawsTitle: true, nativeHeight: 28)
        XCTAssertGreaterThanOrEqual(size.width, C.checkboxSize + T.gap + widest + T.slack)
        // At that width every line fits on one line: two lines' height, and the cell holds them.
        let wrapped = T.wrappedTitleHeight(title, cellWidth: size.width)
        XCTAssertEqual(wrapped, T.wrappedTitleHeight("Ag\nAg", cellWidth: 10_000))
        XCTAssertGreaterThanOrEqual(size.height, wrapped)
        XCTAssertGreaterThan(wrapped, T.lineHeight * 1.5)
        // The caller's own (smaller) font does not change the measurement.
        XCTAssertGreaterThan(size.width, C.checkboxSize + T.gap
            + ceil(NSAttributedString(string: "(only for Delete ALL ROWS IN TABLE)?", attributes: [.font: NSFont.systemFont(ofSize: 11)]).size().width) + T.slack)
        // Other line breaks count too.
        XCTAssertEqual(T.cellSize(title: "Reset AUTO_INCREMENT after deletion\r\n(only for Delete ALL ROWS IN TABLE)?", drawsTitle: true, nativeHeight: 28).width, size.width)
    }

    /// An ordinary one-line title measures exactly as before: box, gap, the title's width, slack; AppKit's height.
    func testOneLineTitleMeasuresAsBefore() {
        let title = "Show this again"
        let size = T.cellSize(title: title, drawsTitle: true, nativeHeight: 18)
        XCTAssertEqual(size.width, C.checkboxSize + T.gap + ceil(NSAttributedString(string: title, attributes: [.font: NSFont.systemFont(ofSize: 12)]).size().width) + T.slack)
        XCTAssertEqual(size.height, 18)
        XCTAssertEqual(T.cellSize(title: title, drawsTitle: true, nativeHeight: 10).height, C.checkboxSize)
        XCTAssertEqual(T.cellSize(title: title, drawsTitle: false, nativeHeight: 18), NSSize(width: C.checkboxSize, height: 18))
        XCTAssertEqual(T.cellSize(title: "", drawsTitle: true, nativeHeight: 18), NSSize(width: C.checkboxSize, height: 18))
    }
}
