//  SAVaultRoleFilterTests.swift
//  Sequel Ace

import XCTest

final class SAVaultRoleFilterTests: XCTestCase {

    func testSubsequenceMatchesAcrossWords() {
        XCTAssertTrue(SAVaultRoleFilter.matches(query: "something", candidate: "Small Orient Method Thing"))
        XCTAssertTrue(SAVaultRoleFilter.matches(query: "SOMETHING", candidate: "small orient method thing"))
    }

    func testNonSubsequenceDoesNotMatch() {
        XCTAssertFalse(SAVaultRoleFilter.matches(query: "xyz", candidate: "Small Orient Method Thing"))
        // 'q' is absent entirely
        XCTAssertFalse(SAVaultRoleFilter.matches(query: "q", candidate: "abc"))
    }

    func testEmptyQueryReturnsAllAlphabetical() {
        XCTAssertEqual(SAVaultRoleFilter.orderedRoles(["b-role", "A-role", "c-role"], query: ""),
                       ["A-role", "b-role", "c-role"])
    }

    func testMatchesFirstThenSeparatorThenRest() {
        let result = SAVaultRoleFilter.orderedRoles(["zzz", "abc", "abd"], query: "ab")
        XCTAssertEqual(result, ["abc", "abd", SAVaultRoleFilter.separator, "zzz"])
    }

    func testNoMatchReturnsAllAlphabeticalWithoutSeparator() {
        let result = SAVaultRoleFilter.orderedRoles(["xyz", "abc"], query: "q")
        XCTAssertEqual(result, ["abc", "xyz"])
        XCTAssertFalse(result.contains(SAVaultRoleFilter.separator))
    }

    func testAllMatchHasNoSeparator() {
        let result = SAVaultRoleFilter.orderedRoles(["ab", "ac"], query: "a")
        XCTAssertEqual(result, ["ab", "ac"])
        XCTAssertFalse(result.contains(SAVaultRoleFilter.separator))
    }

    func testWordBoundaryMatchRanksHigher() {
        // 'a' at a word/segment start (score 11) should rank above a mid-word 'a' (score 1).
        let result = SAVaultRoleFilter.orderedRoles(["xa", "ax"], query: "a")
        XCTAssertEqual(result, ["ax", "xa"])
    }
}
