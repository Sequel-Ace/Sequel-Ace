//
//  SATypeAheadMatcherTests.swift
//  Unit Tests
//
//  Created by Sequel Ace on July 27, 2026.
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import XCTest

final class SATypeAheadMatcherTests: XCTestCase {

    private let tables = ["", "customers", "mesajlar", "messages", "orders", "user_messages", "users"]

    // MARK: - Stateless matching

    func testPrefixMatchWinsOverSubstringMatch() {
        // "me" is a prefix of "mesajlar" and a substring of "user_messages"
        XCTAssertEqual(SATypeAheadMatcher.bestMatch(for: "me", in: tables), 2)
    }

    func testSubstringMatchWhenNoPrefixMatch() {
        XCTAssertEqual(SATypeAheadMatcher.bestMatch(for: "_mes", in: tables), 5)
    }

    func testSubsequenceMatchWhenNoSubstringMatch() {
        // m-s-j appear in order in "mesajlar" only
        XCTAssertEqual(SATypeAheadMatcher.bestMatch(for: "msj", in: tables), 2)
    }

    func testFirstCandidateWinsWithinATier() {
        XCTAssertEqual(SATypeAheadMatcher.bestMatch(for: "users", in: tables), 6)
        XCTAssertEqual(SATypeAheadMatcher.bestMatch(for: "user", in: tables), 5)
    }

    func testMatchingIsCaseInsensitive() {
        XCTAssertEqual(SATypeAheadMatcher.bestMatch(for: "MES", in: tables), 2)
        XCTAssertEqual(SATypeAheadMatcher.bestMatch(for: "me", in: ["MESAJLAR"]), 0)
    }

    func testNoMatchReturnsNotFound() {
        XCTAssertEqual(SATypeAheadMatcher.bestMatch(for: "xyz", in: tables), NSNotFound)
    }

    func testEmptyPatternNeverMatches() {
        XCTAssertEqual(SATypeAheadMatcher.bestMatch(for: "", in: tables), NSNotFound)
    }

    func testEmptyCandidateNeverMatches() {
        XCTAssertEqual(SATypeAheadMatcher.bestMatch(for: "a", in: ["", "a"]), 1)
        XCTAssertEqual(SATypeAheadMatcher.bestMatch(for: "a", in: [""]), NSNotFound)
    }

    // MARK: - Keystroke accumulation

    func testKeystrokesWithinResetIntervalAccumulate() {
        let matcher = SATypeAheadMatcher(resetInterval: 0.3)

        XCTAssertEqual(matcher.bestMatch(appending: "m", candidates: tables, atTime: 10.0), 2)
        XCTAssertEqual(matcher.bestMatch(appending: "e", candidates: tables, atTime: 10.2), 2)
        XCTAssertEqual(matcher.currentSearchString, "me")
        XCTAssertEqual(matcher.bestMatch(appending: "ss", candidates: tables, atTime: 10.4), 3)
        XCTAssertEqual(matcher.currentSearchString, "mess")
    }

    func testPauseLongerThanResetIntervalStartsANewSearch() {
        let matcher = SATypeAheadMatcher(resetInterval: 0.3)

        XCTAssertEqual(matcher.bestMatch(appending: "m", candidates: tables, atTime: 10.0), 2)
        XCTAssertEqual(matcher.bestMatch(appending: "o", candidates: tables, atTime: 10.5), 4)
        XCTAssertEqual(matcher.currentSearchString, "o")
    }

    func testIsActiveTracksResetInterval() {
        let matcher = SATypeAheadMatcher(resetInterval: 0.3)

        XCTAssertFalse(matcher.isActive(atTime: 10.0))
        _ = matcher.bestMatch(appending: "m", candidates: tables, atTime: 10.0)
        XCTAssertTrue(matcher.isActive(atTime: 10.2))
        XCTAssertFalse(matcher.isActive(atTime: 10.4))
    }

    func testResetForgetsTheSearchString() {
        let matcher = SATypeAheadMatcher(resetInterval: 0.3)

        _ = matcher.bestMatch(appending: "m", candidates: tables, atTime: 10.0)
        matcher.reset()

        XCTAssertFalse(matcher.isActive(atTime: 10.1))
        XCTAssertEqual(matcher.bestMatch(appending: "o", candidates: tables, atTime: 10.1), 4)
        XCTAssertEqual(matcher.currentSearchString, "o")
    }

    func testNoMatchKeepsAccumulatingUntilReset() {
        let matcher = SATypeAheadMatcher(resetInterval: 0.3)

        XCTAssertEqual(matcher.bestMatch(appending: "x", candidates: tables, atTime: 10.0), NSNotFound)
        XCTAssertEqual(matcher.bestMatch(appending: "y", candidates: tables, atTime: 10.1), NSNotFound)
        XCTAssertEqual(matcher.currentSearchString, "xy")
    }
}
