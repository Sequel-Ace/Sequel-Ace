//
//  SAFavoriteSearchMatcherTests.swift
//  Unit Tests
//
//  Pins the favorites-search semantics extracted from
//  SAFavoritesListDataSource.rebuildVisibleNodes / collectMatchingNodes.
//  The matcher is the user-facing contract for the sidebar's search
//  field — getting these wrong silently hides favorites.
//

import XCTest

final class SAFavoriteSearchMatcherTests: XCTestCase {

    // MARK: - isActive

    func testEmptyQueryIsNotActive() {
        XCTAssertFalse(SAFavoriteSearchMatcher(query: "").isActive)
    }

    func testWhitespaceOnlyQueryIsNotActive() {
        // Multiple kinds of whitespace — must all be treated as separators
        // and never produce a non-empty token.
        XCTAssertFalse(SAFavoriteSearchMatcher(query: "   ").isActive)
        XCTAssertFalse(SAFavoriteSearchMatcher(query: "\t\n").isActive)
    }

    func testSingleTokenIsActive() {
        XCTAssertTrue(SAFavoriteSearchMatcher(query: "prod").isActive)
    }

    func testMultipleTokensAreActive() {
        XCTAssertTrue(SAFavoriteSearchMatcher(query: "staging maja").isActive)
    }

    // MARK: - Inactive-matcher behavior

    /// When the filter is inactive, every candidate must pass — the
    /// data source skips filtering entirely in that case, and any code
    /// that asks the matcher directly must agree.
    func testInactiveMatcherMatchesEverything() {
        let matcher = SAFavoriteSearchMatcher(query: "")
        XCTAssertTrue(matcher.matches(name: "", host: ""))
        XCTAssertTrue(matcher.matches(name: "anything", host: "anywhere"))
    }

    // MARK: - Token parsing

    func testTokensAreLowercased() {
        XCTAssertEqual(SAFavoriteSearchMatcher(query: "ProD STG").tokens, ["prod", "stg"])
    }

    func testTokensCollapseAdjacentWhitespace() {
        // Adjacent runs of whitespace must collapse to a single
        // separator (not produce empty-string tokens that would
        // accidentally match everything).
        let matcher = SAFavoriteSearchMatcher(query: "  staging   maja  ")
        XCTAssertEqual(matcher.tokens, ["staging", "maja"])
    }

    func testTokensSplitOnMixedWhitespace() {
        let matcher = SAFavoriteSearchMatcher(query: "a\tb\nc d")
        XCTAssertEqual(matcher.tokens, ["a", "b", "c", "d"])
    }

    // MARK: - Single-token match

    func testSingleTokenMatchesByName() {
        let matcher = SAFavoriteSearchMatcher(query: "prod")
        XCTAssertTrue(matcher.matches(name: "Production", host: "10.0.0.1"))
    }

    func testSingleTokenMatchesByHost() {
        let matcher = SAFavoriteSearchMatcher(query: "internal")
        XCTAssertTrue(matcher.matches(name: "MyDB", host: "db.internal.example.com"))
    }

    func testSingleTokenIsCaseInsensitiveOnBothSides() {
        let matcher = SAFavoriteSearchMatcher(query: "PROD")
        XCTAssertTrue(matcher.matches(name: "production", host: ""))

        let matcher2 = SAFavoriteSearchMatcher(query: "prod")
        XCTAssertTrue(matcher2.matches(name: "PRODUCTION", host: ""))
    }

    func testSingleTokenMissBothFields() {
        let matcher = SAFavoriteSearchMatcher(query: "missing")
        XCTAssertFalse(matcher.matches(name: "Production", host: "10.0.0.1"))
    }

    // MARK: - Multi-token (AND) match

    /// Multi-token queries are an AND across tokens, but each token can
    /// match either field. The advertised example: "staging maja"
    /// narrows to "[Staging] Majapahit" on host "majapahit.internal".
    func testMultipleTokensRequireAllToMatchSomewhere() {
        let matcher = SAFavoriteSearchMatcher(query: "staging maja")
        XCTAssertTrue(matcher.matches(name: "[Staging] Majapahit", host: "majapahit.internal"))
    }

    func testMultipleTokensMixedNameAndHost() {
        // One token matches the name, the other matches the host.
        let matcher = SAFavoriteSearchMatcher(query: "prod example")
        XCTAssertTrue(matcher.matches(name: "Production", host: "db.example.com"))
    }

    func testMultipleTokensFailWhenOneMisses() {
        let matcher = SAFavoriteSearchMatcher(query: "prod ghost")
        XCTAssertFalse(matcher.matches(name: "Production", host: "db.example.com"))
    }

    // MARK: - Edge cases

    func testEmptyNameAndHostNeverMatchActiveQuery() {
        let matcher = SAFavoriteSearchMatcher(query: "anything")
        XCTAssertFalse(matcher.matches(name: "", host: ""))
    }

    func testSubstringMatchAcrossWordBoundary() {
        // The matcher is substring-based, not word-based — "prodb"
        // should match "production-db" because the chars are contiguous.
        let matcher = SAFavoriteSearchMatcher(query: "prodb")
        XCTAssertFalse(matcher.matches(name: "Production-DB", host: ""))
        // But the substring "prod-d" does occur literally:
        let matcher2 = SAFavoriteSearchMatcher(query: "tion-d")
        XCTAssertTrue(matcher2.matches(name: "Production-DB", host: ""))
    }
}
