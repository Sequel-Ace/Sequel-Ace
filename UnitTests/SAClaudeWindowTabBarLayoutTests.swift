//
//  SAClaudeWindowTabBarLayoutTests.swift
//  Unit Tests
//
//  Geometry and reorder maths for the Claude window tab bar.
//

import XCTest
import AppKit

final class SAClaudeWindowTabBarLayoutTests: XCTestCase {
    private typealias L = SAClaudeWindowTabBarLayout

    private func apply(_ steps: [L.Step], to order: [Int]) -> [Int] {
        var working = order
        for step in steps {
            working.removeAll { $0 == step.id }
            working.insert(step.id, at: step.index)
        }
        return working
    }

    func testChipsFitTheirContentPackedFromTheLeft() {
        let f = L.frames(preferredWidths: [150, 180, 120], barWidth: 800)
        XCTAssertEqual(f.scrollArea, NSRect(x: 8, y: 0, width: 752, height: 36))
        XCTAssertEqual(f.chips.map(\.width), [150, 180, 120])
        XCTAssertEqual(f.chips.map(\.minX), [0, 156, 342])
        XCTAssertEqual(f.chips[0], NSRect(x: 0, y: 4, width: 150, height: 28))
        XCTAssertEqual(f.contentWidth, 462)
        XCTAssertFalse(f.scrolls)
        XCTAssertEqual(f.plus, NSRect(x: 476, y: 6, width: 24, height: 24))   // right after the last chip
    }

    func testPreferredWidthsAreClamped() {
        let f = L.frames(preferredWidths: [300, 90], barWidth: 800)
        XCTAssertEqual(f.chips.map(\.width), [220, 100])
        XCTAssertEqual(f.chips.map(\.minX), [0, 226])
        XCTAssertFalse(f.scrolls)
    }

    func testChipsShrinkProportionallyBeforeScrolling() {
        // Available 752, gaps 24, sum 1000: each 200 * 0.728 = 145.6, floored.
        let f = L.frames(preferredWidths: Array(repeating: 200, count: 5), barWidth: 800)
        XCTAssertEqual(f.chips.map(\.width), Array(repeating: 145, count: 5))
        XCTAssertEqual(f.contentWidth, 749)
        XCTAssertEqual(f.chips[4].maxX, 749)
        XCTAssertFalse(f.scrolls)
    }

    func testManyTabsScrollAtTheMinimumWidth() {
        let f = L.frames(preferredWidths: Array(repeating: 200, count: 12), barWidth: 800)
        XCTAssertEqual(f.chips.map(\.width), Array(repeating: 100, count: 12))
        XCTAssertEqual(f.contentWidth, 1266)
        XCTAssertTrue(f.scrolls)
        XCTAssertEqual(f.plus, NSRect(x: 768, y: 6, width: 24, height: 24))   // pinned at the right edge
    }

    func testNoTabs() {
        let f = L.frames(preferredWidths: [], barWidth: 800)
        XCTAssertTrue(f.chips.isEmpty)
        XCTAssertEqual(f.contentWidth, 0)
        XCTAssertFalse(f.scrolls)
    }

    func testInsertionIndex() {
        let chips = L.frames(preferredWidths: [150, 180, 120], barWidth: 800).chips   // midX 75, 246, 402
        XCTAssertEqual(L.insertionIndex(x: -20, chips: chips), 0)
        XCTAssertEqual(L.insertionIndex(x: 100, chips: chips), 1)
        XCTAssertEqual(L.insertionIndex(x: 300, chips: chips), 2)
        XCTAssertEqual(L.insertionIndex(x: 500, chips: chips), 3)
    }

    func testTargetOrder() {
        XCTAssertEqual(L.target(order: [1, 2, 3], moving: 3, toInsertion: 1), [1, 3, 2])
        XCTAssertEqual(L.target(order: [1, 2, 3], moving: 1, toInsertion: 3), [2, 3, 1])
        XCTAssertEqual(L.target(order: [1, 2, 3], moving: 2, toInsertion: 1), [1, 2, 3])   // onto itself
        XCTAssertEqual(L.target(order: [1, 2, 3], moving: 2, toInsertion: 2), [1, 2, 3])   // just after itself
        XCTAssertEqual(L.target(order: [1, 2, 3], moving: 1, toInsertion: 9), [2, 3, 1])   // clamped to the end
        XCTAssertEqual(L.target(order: [1, 2, 3], moving: 3, toInsertion: -4), [3, 1, 2])  // clamped to the front
    }

    func testMovingANonSelectedTabIsOneStep() {
        let steps = L.reorderSteps(order: [1, 2, 3], target: [1, 3, 2], selected: 1)
        XCTAssertEqual(steps, [L.Step(id: 3, index: 1)])
        XCTAssertEqual(apply(steps, to: [1, 2, 3]), [1, 3, 2])
    }

    func testMovingTheSelectedTabMovesTheOthersAroundIt() {
        let order = [1, 2, 3], target = [2, 3, 1]          // the selected tab 1 goes to the end
        let steps = L.reorderSteps(order: order, target: target, selected: 1)
        XCTAssertFalse(steps.contains { $0.id == 1 })
        XCTAssertEqual(apply(steps, to: order), target)
        let order2 = [1, 2, 3, 4], target2 = [2, 1, 4, 3]  // a general shuffle with 2 selected
        let steps2 = L.reorderSteps(order: order2, target: target2, selected: 2)
        XCTAssertFalse(steps2.contains { $0.id == 2 })
        XCTAssertEqual(apply(steps2, to: order2), target2)
    }

    func testNoStepsWhenUnchanged() {
        XCTAssertEqual(L.reorderSteps(order: [1, 2, 3], target: [1, 2, 3], selected: 2), [])
    }
}
