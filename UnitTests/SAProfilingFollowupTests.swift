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

final class SATooltipLifecycleTests: XCTestCase {

    /// Verifies a new tooltip hides whatever is still on screen - a visible or
    /// a fading tooltip - so the new content is never measured in a visible,
    /// screen-sized window, and that the previous monitor is detached.
    func testReplacementHidesAVisibleOrFadingTooltip() {
        let lifecycle = SATooltipLifecycle()
        XCTAssertFalse(lifecycle.prepareForNewTooltip(isVisible: false, isFading: false), "nothing on screen")
        XCTAssertTrue(lifecycle.prepareForNewTooltip(isVisible: false, isFading: true), "a running fade-out must end now")

        lifecycle.beginDismissalMonitoring(keyWindow: nil) {}
        XCTAssertTrue(lifecycle.isMonitoring)
        XCTAssertTrue(lifecycle.prepareForNewTooltip(isVisible: true, isFading: false), "a visible tooltip is hidden before the new content is measured")
        XCTAssertFalse(lifecycle.isMonitoring, "the previous monitor is detached")
        XCTAssertTrue(lifecycle.prepareForNewTooltip(isVisible: true, isFading: true))
    }

    /// Verifies starting a new monitor replaces the previous one and detaching is idempotent.
    func testMonitoringReplacesAndDetachesIdempotently() {
        let lifecycle = SATooltipLifecycle()
        lifecycle.beginDismissalMonitoring(keyWindow: nil) {}
        lifecycle.beginDismissalMonitoring(keyWindow: nil) {}
        XCTAssertTrue(lifecycle.isMonitoring)

        lifecycle.detachDismissalMonitor()
        lifecycle.detachDismissalMonitor()
        XCTAssertFalse(lifecycle.isMonitoring)
    }

    /// Verifies a fade continues only while partly visible and not superseded,
    /// and that closing never drives the count below zero.
    func testFadeContinuesOnlyForTheSingleVisibleTooltip() {
        let lifecycle = SATooltipLifecycle()
        _ = lifecycle.prepareForNewTooltip(isVisible: false, isFading: false)
        XCTAssertTrue(lifecycle.fadeMayContinue(alpha: 0.5))
        XCTAssertFalse(lifecycle.fadeMayContinue(alpha: 0))

        lifecycle.tooltipDidClose()
        XCTAssertFalse(lifecycle.fadeMayContinue(alpha: 0.5), "no tooltip left to fade")
        lifecycle.tooltipDidClose()

        _ = lifecycle.prepareForNewTooltip(isVisible: false, isFading: false)
        XCTAssertTrue(lifecycle.fadeMayContinue(alpha: 0.5), "a new tooltip fades again after extra closes")
    }

    /// Verifies repeated replacements reset the count instead of accumulating
    /// it - an accumulated count would skip every later fade-out.
    func testRepeatedReplacementsDoNotAccumulate() {
        let lifecycle = SATooltipLifecycle()
        for _ in 0..<5 {
            _ = lifecycle.prepareForNewTooltip(isVisible: false, isFading: false)
        }
        XCTAssertTrue(lifecycle.fadeMayContinue(alpha: 0.5))
    }

    /// Verifies only work for the web view currently showing the tooltip
    /// applies - stale callbacks and measurements of replaced web views do not.
    func testWorkForReplacedWebViewsIsIgnored() {
        let current = NSObject()
        XCTAssertTrue(SATooltipLifecycle.isCurrent(webView: current, currentWebView: current))
        XCTAssertFalse(SATooltipLifecycle.isCurrent(webView: NSObject(), currentWebView: current))
        XCTAssertFalse(SATooltipLifecycle.isCurrent(webView: current, currentWebView: nil), "closing cleared the content view")
    }

    /// Verifies a superseded navigation keeps the tooltip while real load failures close it.
    func testOnlyNonCancellationFailuresClose() {
        XCTAssertFalse(SATooltipLifecycle.shouldCloseAfterNavigationFailure(NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)))
        XCTAssertTrue(SATooltipLifecycle.shouldCloseAfterNavigationFailure(NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)))
        XCTAssertTrue(SATooltipLifecycle.shouldCloseAfterNavigationFailure(NSError(domain: "WebKitErrorDomain", code: NSURLErrorCancelled)))
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

    /// Verifies a row-id-keyed history comes back newest (highest id) first,
    /// and an empty history stays empty.
    func testRowKeyedHistoryIsOrderedNewestFirst() {
        XCTAssertEqual(SAQueryHistoryMerger.newestFirst(rowKeyedHistory: [3: "c", 1: "a", 2: "b"]), ["c", "b", "a"])
        XCTAssertEqual(SAQueryHistoryMerger.newestFirst(rowKeyedHistory: [:]), [])
    }

    /// Verifies row ids beyond the 32-bit range still order correctly - SQLite
    /// row ids are Int64, and a narrowing comparison would sort them as oldest.
    func testRowKeyedHistoryComparesFullInt64Width() {
        let history: [Int64: String] = [2_147_483_647: "older", 2_147_483_648: "newer"]
        XCTAssertEqual(SAQueryHistoryMerger.newestFirst(rowKeyedHistory: history), ["newer", "older"])
    }

    /// Verifies the ordered snapshot feeds the merger so the limit trims the
    /// actual oldest entry.
    func testOrderedSnapshotLetsTheLimitTrimTheOldestEntry() {
        let existing = SAQueryHistoryMerger.newestFirst(rowKeyedHistory: [10: "old", 20: "new"])
        XCTAssertEqual(SAQueryHistoryMerger.merged(newEntries: ["fresh"], existing: existing, limit: 2), ["fresh", "new"])
    }
}
