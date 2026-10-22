//
//  SAFavoriteColourSelectorLayoutTests.swift
//  Unit Tests
//

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
        XCTAssertLessThanOrEqual(229 + 3, 247)
    }
}
