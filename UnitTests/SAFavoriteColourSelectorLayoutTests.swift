//
//  SAFavoriteColourSelectorLayoutTests.swift
//  Unit Tests
//

import AppKit
import XCTest

final class SAFavoriteColourSelectorLayoutTests: XCTestCase {

    private func tags(colourCount: Int) -> [Int] {
        let count = SAFavoriteColourSelectorLayout.slotCount(colourCount: colourCount)
        return (0..<count).map { SAFavoriteColourSelectorLayout.tag(forSlot: $0, colourCount: colourCount) }
    }

    func testSlotsFollowRainbowOrder() {
        XCTAssertEqual(SAFavoriteColourSelectorLayout.slotCount(colourCount: 10), 11)
        XCTAssertEqual(tags(colourCount: 10), [-1, 0, 1, 2, 3, 7, 4, 8, 5, 9, 6])
    }

    func testShorterListSkipsMissingIndices() {
        XCTAssertEqual(SAFavoriteColourSelectorLayout.slotCount(colourCount: 7), 8)
        XCTAssertEqual(tags(colourCount: 7), [-1, 0, 1, 2, 3, 4, 5, 6])
    }

    func testSlotForTagRoundTrips() {
        for count in [0, 7, 10] {
            for slot in 0..<SAFavoriteColourSelectorLayout.slotCount(colourCount: count) {
                let tag = SAFavoriteColourSelectorLayout.tag(forSlot: slot, colourCount: count)
                XCTAssertEqual(SAFavoriteColourSelectorLayout.slot(forTag: tag, colourCount: count), slot,
                               "count \(count) slot \(slot)")
            }
        }
    }

    func testUnknownTagHasNoSlot() {
        for tag in [10, -5, 99] {
            XCTAssertEqual(SAFavoriteColourSelectorLayout.slot(forTag: tag, colourCount: 10), NSNotFound, "tag \(tag)")
        }
        XCTAssertEqual(SAFavoriteColourSelectorLayout.slot(forTag: 8, colourCount: 7), NSNotFound)
        XCTAssertEqual(SAFavoriteColourSelectorLayout.tag(forSlot: 11, colourCount: 10), NSNotFound)
        XCTAssertEqual(SAFavoriteColourSelectorLayout.tag(forSlot: -1, colourCount: 10), NSNotFound)
    }

    func testElevenSlotsFitTheStylerWidth() {
        XCTAssertEqual(SAFavoriteColourSelectorLayout.contentWidth(colourCount: 10), 229)
        XCTAssertEqual(SAFavoriteColourSelectorLayout.rect(forSlot: 10), NSRect(x: 213, y: 2, width: 16, height: 16))
        XCTAssertLessThanOrEqual(SAFavoriteColourSelectorLayout.contentWidth(colourCount: 10) + 3, 247)
    }

    // MARK: Narrow controls

    /// The height the styler gives the colour control (`colourSelectorHeight`).
    private static let viewHeight: CGFloat = 22

    /// The slots of a control `width` wide, as (rect, last slot).
    private func slotRects(colourCount: Int = 10, width: CGFloat) -> [NSRect] {
        (0..<SAFavoriteColourSelectorLayout.slotCount(colourCount: colourCount)).map {
            SAFavoriteColourSelectorLayout.rect(forSlot: $0, colourCount: colourCount, width: width, height: Self.viewHeight)
        }
    }

    private func assertFits(_ width: CGFloat, colourCount: Int = 10, file: StaticString = #filePath, line: UInt = #line) {
        let rects = slotRects(colourCount: colourCount, width: width)
        XCTAssertLessThanOrEqual((rects.last?.maxX ?? 0) + SAFavoriteColourSelectorLayout.originX, width + 0.001,
                                 "last dot inside \(width)", file: file, line: line)
        for (a, b) in zip(rects, rects.dropFirst()) {
            XCTAssertLessThanOrEqual(a.maxX, b.minX, "slots do not overlap at \(width)", file: file, line: line)
        }
        XCTAssertGreaterThanOrEqual(rects[1].width, SAFavoriteColourSelectorLayout.visualDotSize - 1,
                                    "dots keep their size at \(width)", file: file, line: line)
    }

    func testRoomyControlKeepsTheFullSizeSlots() {
        for width in [232, 247] as [CGFloat] {
            for slot in 0..<11 {
                let rect = SAFavoriteColourSelectorLayout.rect(forSlot: slot, colourCount: 10, width: width, height: Self.viewHeight)
                let full = SAFavoriteColourSelectorLayout.rect(forSlot: slot)
                XCTAssertEqual([rect.minX, rect.width, rect.height], [full.minX, full.width, full.height], "slot \(slot) at \(width)")
            }
        }
    }

    func testSlotsAreCentredVerticallyAtEveryWidth() {
        for width in [157, 170, 176, 208, 212, 232] as [CGFloat] {
            for rect in slotRects(width: width) {
                XCTAssertEqual(rect.midY, Self.viewHeight / 2, accuracy: 0.001, "width \(width)")
            }
        }
        XCTAssertEqual(SAFavoriteColourSelectorLayout.rect(forSlot: 0, colourCount: 10, width: 170, height: 30).midY, 15, accuracy: 0.001)
    }

    func testDotsFitTheNarrowestControl() {
        let narrowest = SAFavoriteColourSelectorLayout.minimumWidth(colourCount: 10)
        XCTAssertEqual(narrowest, 157)
        assertFits(narrowest)
        assertFits(narrowest, colourCount: 7)
        for width in stride(from: narrowest, through: 247, by: 1) { assertFits(width) }
    }

    /// The colour row's control in the real panel layout at the widths the panel can take (one column
    /// from 320, two columns from 620): the eleven dots fit all of them.
    func testDotsFitTheColourControlAtEveryPanelWidth() {
        let rows = [SAClaudeConnectionRowSpec(id: "colour", label: "Colour", kind: .colour, section: .advanced),
                    SAClaudeConnectionRowSpec(id: "timeZone", label: "Time zone", kind: .field, section: .advanced)]
        let narrowest = SAFavoriteColourSelectorLayout.minimumWidth(colourCount: 10)
        for panel in [320, 376, 445, 620, 696, 744, 1000] as [CGFloat] {
            let frames = SAClaudeConnectionPanelLayout.frames(type: .tcpip, rows: rows, width: panel, advancedOpen: true, tabsWidth: 200)
            let control = frames.rows.first { $0.id == "colour" }!.control
            XCTAssertGreaterThanOrEqual(control.width, narrowest, "panel \(panel)")
            assertFits(min(control.width, 247))
        }
    }
}
