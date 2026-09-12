//
//  SAProfilingFollowupTests.swift
//  Unit Tests
//
//  Created by Sequel-Ace contributors on 2026.09.09.
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import AppKit
import XCTest

final class SAAppearancePreferenceTests: XCTestCase {

    override func setUp() {
        super.setUp()
        SAAppearancePreference.resetForTesting()
    }

    override func tearDown() {
        SAAppearancePreference.resetForTesting()
        super.tearDown()
    }

    /// Verifies the preference selections map to the documented appearances.
    func testSelectionMapsToAppearanceName() {
        XCTAssertEqual(SAAppearancePreference.appearanceName(for: 1), .aqua)
        XCTAssertEqual(SAAppearancePreference.appearanceName(for: 2), .darkAqua)
        XCTAssertNil(SAAppearancePreference.appearanceName(for: 0), "0 follows the system")
        XCTAssertNil(SAAppearancePreference.appearanceName(for: 3))
        XCTAssertNil(SAAppearancePreference.appearanceName(for: -1))
    }

    /// Verifies repeated identical selections are skipped and changes always apply.
    func testRedundantSelectionsAreSkipped() {
        XCTAssertTrue(SAAppearancePreference.shouldApply(2), "first application always runs")
        XCTAssertFalse(SAAppearancePreference.shouldApply(2), "unchanged selection is skipped")
        XCTAssertTrue(SAAppearancePreference.shouldApply(1))
        XCTAssertFalse(SAAppearancePreference.shouldApply(1))
        XCTAssertTrue(SAAppearancePreference.shouldApply(2), "flipping back applies again")
    }
}

final class SATooltipDismissalPolicyTests: XCTestCase {

    /// Verifies the event types that close a tooltip outright.
    func testImmediateCloseEvents() {
        XCTAssertTrue(SATooltipDismissalPolicy.closesImmediately(.keyDown))
        XCTAssertTrue(SATooltipDismissalPolicy.closesImmediately(.leftMouseDown))
        XCTAssertTrue(SATooltipDismissalPolicy.closesImmediately(.rightMouseDown))
        XCTAssertTrue(SATooltipDismissalPolicy.closesImmediately(.otherMouseDown))
        XCTAssertTrue(SATooltipDismissalPolicy.closesImmediately(.scrollWheel))
        XCTAssertFalse(SATooltipDismissalPolicy.closesImmediately(.mouseMoved))
        XCTAssertFalse(SATooltipDismissalPolicy.closesImmediately(.leftMouseUp))
        XCTAssertFalse(SATooltipDismissalPolicy.closesImmediately(.keyUp))
    }

    /// Verifies movement within the grace period neither closes nor anchors.
    func testMouseMoveIgnoredWithinGracePeriod() {
        let opened = Date()
        let verdict = SATooltipDismissalPolicy.evaluateMouseMove(openedAt: opened, now: opened.addingTimeInterval(0.01), anchor: nil, location: NSPoint(x: 100, y: 100))
        XCTAssertFalse(verdict.close)
        XCTAssertNil(verdict.anchor)
    }

    /// Verifies the first movement after the grace period only anchors.
    func testFirstMoveAnchorsWithoutClosing() {
        let opened = Date()
        let verdict = SATooltipDismissalPolicy.evaluateMouseMove(openedAt: opened, now: opened.addingTimeInterval(0.1), anchor: nil, location: NSPoint(x: 100, y: 100))
        XCTAssertFalse(verdict.close)
        XCTAssertEqual(verdict.anchor, NSPoint(x: 100, y: 100))
    }

    /// Verifies only movement beyond the 10 pt radius around the anchor closes.
    func testMoveBeyondThresholdCloses() {
        let opened = Date()
        let now = opened.addingTimeInterval(0.1)
        let anchor = NSPoint(x: 100, y: 100)
        XCTAssertFalse(SATooltipDismissalPolicy.evaluateMouseMove(openedAt: opened, now: now, anchor: anchor, location: NSPoint(x: 107, y: 107)).close, "~9.9 pt stays open")
        XCTAssertTrue(SATooltipDismissalPolicy.evaluateMouseMove(openedAt: opened, now: now, anchor: anchor, location: NSPoint(x: 111, y: 100)).close)
        let kept = SATooltipDismissalPolicy.evaluateMouseMove(openedAt: opened, now: now, anchor: anchor, location: NSPoint(x: 111, y: 100))
        XCTAssertEqual(kept.anchor, anchor, "the anchor never moves once set")
    }
}

final class SAQueryHistoryMergerTests: XCTestCase {

    /// Verifies a new entry lands at the front of the stored history.
    func testNewEntryGoesToFront() {
        XCTAssertEqual(SAQueryHistoryMerger.merged(newEntries: ["c"], existing: ["a", "b"], limit: 10), ["c", "a", "b"])
    }

    /// Verifies an older duplicate of a new entry is removed from its old position.
    func testDuplicateOfNewEntryMovesToFront() {
        XCTAssertEqual(SAQueryHistoryMerger.merged(newEntries: ["b"], existing: ["a", "b", "c"], limit: 10), ["b", "a", "c"])
    }

    /// Verifies several new entries end up in reverse order - parity with the
    /// old insertItemWithTitle:atIndex:0 loop the popup performed.
    func testSeveralNewEntriesEndUpReversed() {
        XCTAssertEqual(SAQueryHistoryMerger.merged(newEntries: ["x", "y"], existing: ["a"], limit: 10), ["y", "x", "a"])
    }

    /// Verifies duplicates inside the existing list keep the later occurrence,
    /// as NSPopUpButton's addItemsWithTitles: did.
    func testExistingDuplicatesKeepTheLaterOccurrence() {
        XCTAssertEqual(SAQueryHistoryMerger.merged(newEntries: [], existing: ["a", "b", "a"], limit: 10), ["b", "a"])
    }

    /// Verifies trimming drops the oldest (rearmost) entries.
    func testLimitTrimsFromTheEnd() {
        XCTAssertEqual(SAQueryHistoryMerger.merged(newEntries: ["d"], existing: ["a", "b", "c"], limit: 3), ["d", "a", "b"])
    }

    /// Verifies the historic edge cases: limit 0 empties, a negative limit never trims.
    func testZeroAndNegativeLimits() {
        XCTAssertEqual(SAQueryHistoryMerger.merged(newEntries: ["a"], existing: ["b"], limit: 0), [])
        XCTAssertEqual(SAQueryHistoryMerger.merged(newEntries: ["a"], existing: ["b", "c"], limit: -1), ["a", "b", "c"])
    }

    /// Verifies non-string elements - possible in hand-edited preference or
    /// .spf session plists - are dropped instead of trapping in the bridge.
    func testNonStringElementsAreDropped() {
        let existing: [Any] = ["a", NSNumber(value: 42), NSNull(), "b"]
        XCTAssertEqual(SAQueryHistoryMerger.merged(newEntries: ["c"], existing: existing, limit: 10), ["c", "a", "b"])
    }

    /// Verifies repeated empty strings survive, as NSPopUpButton keeps
    /// duplicate empty titles while de-duplicating every other title.
    func testEmptyStringsAreNotDeduplicated() {
        let merged = SAQueryHistoryMerger.merged(newEntries: ["SELECT 2;"], existing: ["", "SELECT 1;", ""], limit: 3)
        XCTAssertEqual(merged, ["SELECT 2;", "", "SELECT 1;"])
    }
}
