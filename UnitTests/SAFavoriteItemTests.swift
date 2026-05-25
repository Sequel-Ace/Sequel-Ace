//
//  SAFavoriteItemTests.swift
//  Unit Tests
//
//  Covers the pure value-model layer of the SwiftUI favorites list
//  (Phase C1b): search filtering and the flatten / lookup helpers.
//  The `SPTreeNode` → `SAFavoriteItem` builder (`SAFavoriteItem+Tree`)
//  is *not* covered here — constructing `SPTreeNode` from the test
//  target hits the known bridging-header sharp edge (see B2b in the
//  modernization plan). End-to-end matching semantics are pinned by
//  `SAFavoriteSearchMatcherTests`.
//

import XCTest

final class SAFavoriteItemTests: XCTestCase {

    // MARK: - Fixtures

    /// quickConnect
    /// fav: "Local" @ 127.0.0.1
    /// group "Prod"
    ///   fav: "Web" @ db.example.com
    ///   fav: "Cache" @ redis.example.com
    /// group "Empty"
    ///   (no children)
    private func sampleForest() -> [SAFavoriteItem] {
        [
            SAFavoriteItem(id: "quickConnect", kind: .quickConnect, name: "QUICK CONNECT"),
            SAFavoriteItem(id: "fav:1", kind: .favorite, name: "Local", host: "127.0.0.1", favoriteID: "1"),
            SAFavoriteItem(id: "grp:0", kind: .group, name: "Prod", children: [
                SAFavoriteItem(id: "fav:2", kind: .favorite, name: "Web", host: "db.example.com", favoriteID: "2"),
                SAFavoriteItem(id: "fav:3", kind: .favorite, name: "Cache", host: "redis.example.com", favoriteID: "3"),
            ]),
            SAFavoriteItem(id: "grp:1", kind: .group, name: "Empty", children: []),
        ]
    }

    // MARK: - Identity / Hashable

    func testIdentifiableUsesIDField() {
        let item = SAFavoriteItem(id: "fav:42", kind: .favorite, name: "x")
        XCTAssertEqual(item.id, "fav:42")
    }

    // MARK: - Flatten / lookup

    func testFlattenedVisitsEveryNodeDepthFirst() {
        let ids = sampleForest().flattened().map(\.id)
        XCTAssertEqual(ids, ["quickConnect", "fav:1", "grp:0", "fav:2", "fav:3", "grp:1"])
    }

    func testFirstByIDFindsNestedFavorite() {
        let found = sampleForest().first(byID: "fav:3")
        XCTAssertEqual(found?.name, "Cache")
    }

    func testFirstByIDReturnsNilForUnknown() {
        XCTAssertNil(sampleForest().first(byID: "nope"))
    }

    // MARK: - Filtering: inactive query

    func testInactiveQueryReturnsEverythingUnchanged() {
        let forest = sampleForest()
        XCTAssertEqual(forest.filtered(query: "").map(\.id), forest.map(\.id))
        XCTAssertEqual(forest.filtered(query: "   ").map(\.id), forest.map(\.id))
    }

    // MARK: - Filtering: favorites

    func testFilterKeepsMatchingFavoriteByName() {
        let result = sampleForest().filtered(query: "local")
        // "Local" leaf kept; Quick Connect always kept; groups have no
        // matching descendants so they drop.
        XCTAssertEqual(result.map(\.id), ["quickConnect", "fav:1"])
    }

    func testFilterMatchesOnHost() {
        let result = sampleForest().filtered(query: "redis")
        // Only the Cache favorite (host redis.example.com), inside Prod.
        XCTAssertEqual(result.map(\.id), ["quickConnect", "grp:0"])
        let prod = result.first { $0.id == "grp:0" }
        XCTAssertEqual(prod?.children?.map(\.id), ["fav:3"])
    }

    // MARK: - Filtering: groups

    func testGroupKeptOnlyWhenADescendantMatches() {
        let result = sampleForest().filtered(query: "web")
        XCTAssertEqual(result.map(\.id), ["quickConnect", "grp:0"])
        XCTAssertEqual(result.first { $0.id == "grp:0" }?.children?.map(\.id), ["fav:2"])
    }

    func testGroupNameItselfIsNotMatched() {
        // "Prod" is a group name; matching it must NOT surface the
        // group (mirrors the AppKit walker's leaf-only rule).
        let result = sampleForest().filtered(query: "prod")
        XCTAssertEqual(result.map(\.id), ["quickConnect"])
    }

    func testEmptyGroupIsAlwaysPrunedUnderActiveQuery() {
        let result = sampleForest().filtered(query: "example")
        XCTAssertFalse(result.contains { $0.id == "grp:1" })
    }

    // MARK: - Filtering: quick connect

    func testQuickConnectSurvivesEvenWhenNothingMatches() {
        let result = sampleForest().filtered(query: "zzzzz-no-match")
        XCTAssertEqual(result.map(\.id), ["quickConnect"])
    }

    // MARK: - Filtering: multi-token AND

    func testMultiTokenMatchesAcrossNameAndHost() {
        // "cache" (name) + "redis" (host) both match the same leaf.
        let result = sampleForest().filtered(query: "cache redis")
        XCTAssertEqual(result.first { $0.id == "grp:0" }?.children?.map(\.id), ["fav:3"])
    }

    func testMultiTokenWithUnsatisfiedTokenDropsLeaf() {
        let result = sampleForest().filtered(query: "cache nope")
        XCTAssertEqual(result.map(\.id), ["quickConnect"])
    }
}
