//  VaultRoleFilterTests.swift
//  Sequel Ace

import XCTest

final class VaultRoleFilterTests: XCTestCase {

    func testSubsequenceMatchesAcrossWords() {
        XCTAssertTrue(VaultRoleFilter.matches(query: "something", candidate: "Small Orient Method Thing"))
        XCTAssertTrue(VaultRoleFilter.matches(query: "SOMETHING", candidate: "small orient method thing"))
    }

    func testNonSubsequenceDoesNotMatch() {
        XCTAssertFalse(VaultRoleFilter.matches(query: "xyz", candidate: "Small Orient Method Thing"))
        // 'q' is absent entirely
        XCTAssertFalse(VaultRoleFilter.matches(query: "q", candidate: "abc"))
    }

    func testEmptyQueryReturnsAllAlphabetical() {
        XCTAssertEqual(VaultRoleFilter.orderedRoles(["b-role", "A-role", "c-role"], query: ""),
                       ["A-role", "b-role", "c-role"])
    }

    func testMatchesFirstThenSeparatorThenRest() {
        let result = VaultRoleFilter.orderedRoles(["zzz", "abc", "abd"], query: "ab")
        XCTAssertEqual(result, ["abc", "abd", VaultRoleFilter.separator, "zzz"])
    }

    func testNoMatchReturnsAllAlphabeticalWithoutSeparator() {
        let result = VaultRoleFilter.orderedRoles(["xyz", "abc"], query: "q")
        XCTAssertEqual(result, ["abc", "xyz"])
        XCTAssertFalse(result.contains(VaultRoleFilter.separator))
    }

    func testAllMatchHasNoSeparator() {
        let result = VaultRoleFilter.orderedRoles(["ab", "ac"], query: "a")
        XCTAssertEqual(result, ["ab", "ac"])
        XCTAssertFalse(result.contains(VaultRoleFilter.separator))
    }

    func testWordBoundaryMatchRanksHigher() {
        // 'a' at a word/segment start (score 11) should rank above a mid-word 'a' (score 1).
        let result = VaultRoleFilter.orderedRoles(["xa", "ax"], query: "a")
        XCTAssertEqual(result, ["ax", "xa"])
    }
}
