//
//  SAClaudeLineHeightTests.swift
//  Unit Tests
//

import AppKit
import XCTest

final class SAClaudeLineHeightTests: XCTestCase {

    override func setUp() {
        super.setUp()
        SAClaudeLineHeight.reset()
    }

    private var fonts: [NSFont] {
        var list: [NSFont] = [11, 12, 13, 14].map { NSFont.systemFont(ofSize: $0) }
        list.append(NSFont.monospacedSystemFont(ofSize: 12, weight: .regular))
        if let menlo = NSFont(name: "Menlo", size: 13) { list.append(menlo) }
        if let helvetica = NSFont(name: "Helvetica Neue", size: 17) { list.append(helvetica) }
        return list
    }

    func testHeightMatchesALayoutManager() {
        for font in fonts {
            XCTAssertEqual(SAClaudeLineHeight.height(for: font), NSLayoutManager().defaultLineHeight(for: font), accuracy: 0.0001,
                           "\(font.fontName) \(font.pointSize)")
        }
    }

    func testCeiledHeightRoundsUp() {
        for font in fonts {
            XCTAssertEqual(SAClaudeLineHeight.ceiledHeight(for: font), ceil(NSLayoutManager().defaultLineHeight(for: font)))
        }
    }

    func testSecondCallDoesNotMeasureAgain() {
        let font = NSFont.systemFont(ofSize: 13)
        _ = SAClaudeLineHeight.height(for: font)
        XCTAssertEqual(SAClaudeLineHeight.measurementCount, 1)
        for _ in 0..<50 { _ = SAClaudeLineHeight.height(for: font) }
        XCTAssertEqual(SAClaudeLineHeight.measurementCount, 1)
    }

    func testAnotherInstanceOfTheSameFontHitsTheSameEntry() {
        _ = SAClaudeLineHeight.height(for: NSFont.systemFont(ofSize: 12))
        _ = SAClaudeLineHeight.height(for: NSFont.systemFont(ofSize: 12))
        _ = SAClaudeLineHeight.ceiledHeight(for: NSFont.systemFont(ofSize: 12))
        XCTAssertEqual(SAClaudeLineHeight.measurementCount, 1)
    }

    func testDifferentSizesAreDistinctEntries() {
        let small = SAClaudeLineHeight.height(for: NSFont.systemFont(ofSize: 11))
        let large = SAClaudeLineHeight.height(for: NSFont.systemFont(ofSize: 24))
        XCTAssertEqual(SAClaudeLineHeight.measurementCount, 2)
        XCTAssertLessThan(small, large)
        XCTAssertEqual(SAClaudeLineHeight.height(for: NSFont.systemFont(ofSize: 11)), small)
        XCTAssertEqual(SAClaudeLineHeight.height(for: NSFont.systemFont(ofSize: 24)), large)
        XCTAssertEqual(SAClaudeLineHeight.measurementCount, 2)
    }

    func testDifferentFontsAtOneSizeAreDistinctEntries() throws {
        let system = NSFont.systemFont(ofSize: 13)
        let menlo = try XCTUnwrap(NSFont(name: "Menlo", size: 13))
        XCTAssertEqual(SAClaudeLineHeight.height(for: system), NSLayoutManager().defaultLineHeight(for: system), accuracy: 0.0001)
        XCTAssertEqual(SAClaudeLineHeight.height(for: menlo), NSLayoutManager().defaultLineHeight(for: menlo), accuracy: 0.0001)
        XCTAssertEqual(SAClaudeLineHeight.measurementCount, 2)
    }

    /// A font chosen in Settings is a new name/size, so it is measured fresh and the old entry stays right.
    func testChangingTheFontMeasuresTheNewOneAndKeepsTheOld() throws {
        let before = try XCTUnwrap(NSFont(name: "Menlo", size: 12))
        let after = try XCTUnwrap(NSFont(name: "Menlo", size: 18))
        let beforeHeight = SAClaudeLineHeight.height(for: before)
        let afterHeight = SAClaudeLineHeight.height(for: after)
        XCTAssertGreaterThan(afterHeight, beforeHeight)
        XCTAssertEqual(afterHeight, NSLayoutManager().defaultLineHeight(for: after), accuracy: 0.0001)
        XCTAssertEqual(SAClaudeLineHeight.height(for: before), beforeHeight)
    }

    func testResetForgetsEverything() {
        let font = NSFont.systemFont(ofSize: 12)
        _ = SAClaudeLineHeight.height(for: font)
        SAClaudeLineHeight.reset()
        XCTAssertEqual(SAClaudeLineHeight.measurementCount, 0)
        _ = SAClaudeLineHeight.height(for: font)
        XCTAssertEqual(SAClaudeLineHeight.measurementCount, 1)
    }
}
