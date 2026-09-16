//
//  SAOfflineEscapingHandleTests.swift
//  SPMySQLFramework
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//
//  More info at <https://github.com/Sequel-Ace/Sequel-Ace>
//

import XCTest
@testable import SPMySQL

/// How a handle that is never connected is set up for escaping.
final class SAOfflineEscapingHandleTests: XCTestCase {

    /// The handle takes the character set it is asked for, without a server.
    func testTheHandleFollowsTheCharacterSetOnRecord() throws {
        for characterSet in ["gbk", "latin1", "utf8mb4", "sjis"] {
            let handle = try XCTUnwrap(SAOfflineEscapingHandle.handle(forCharacterSet: characterSet, escapingModeOfConnection: nil))
            XCTAssertEqual(handle.characterSetName, characterSet)
        }
    }

    /// A character set the client library does not know gives no handle.
    func testAnUnknownCharacterSetGivesNoHandle() {
        XCTAssertNil(SAOfflineEscapingHandle.handle(forCharacterSet: "no-such-character-set", escapingModeOfConnection: nil))
    }

    /// The handle escapes in the session's mode.
    func testTheHandleTakesOverTheEscapingMode() throws {
        let noBackslashEscapes: UInt32 = 512
        let strict = try XCTUnwrap(SAOfflineEscapingHandle.handle(forCharacterSet: "utf8mb4", serverStatus: noBackslashEscapes))
        XCTAssertTrue(strict.escapesWithoutBackslashes)

        let ordinary = try XCTUnwrap(SAOfflineEscapingHandle.handle(forCharacterSet: "utf8mb4", serverStatus: 0))
        XCTAssertFalse(ordinary.escapesWithoutBackslashes)
    }

    /// A byte that starts a gbk character is escaped the gbk way, with the quote after it escaped too.
    func testAValueIsEscapedForTheCharacterSetOnRecord() throws {
        let gbk = try XCTUnwrap(SAOfflineEscapingHandle.handle(forCharacterSet: "gbk", serverStatus: 0))
        XCTAssertEqual(gbk.escapedBytes(Data([0xBF, 0x27])), Data([0x5C, 0xBF, 0x5C, 0x27]))

        let latin1 = try XCTUnwrap(SAOfflineEscapingHandle.handle(forCharacterSet: "latin1", serverStatus: 0))
        XCTAssertEqual(latin1.escapedBytes(Data([0xBF, 0x27])), Data([0xBF, 0x5C, 0x27]))
    }

    /// In a session without backslash escapes, quotes are doubled and backslashes left alone.
    func testAValueIsEscapedInTheSessionsMode() throws {
        let strict = try XCTUnwrap(SAOfflineEscapingHandle.handle(forCharacterSet: "utf8mb4", serverStatus: 512))
        XCTAssertEqual(strict.escapedBytes(Data("it's a \\".utf8)), Data("it''s a \\".utf8))

        let ordinary = try XCTUnwrap(SAOfflineEscapingHandle.handle(forCharacterSet: "utf8mb4", serverStatus: 0))
        XCTAssertEqual(ordinary.escapedBytes(Data("it's a \\".utf8)), Data("it\\'s a \\\\".utf8))
        XCTAssertEqual(ordinary.escapedBytes(Data()), Data())
    }

    /// Without a session there is no mode to take over.
    func testWithoutASessionTheOrdinaryModeApplies() throws {
        let handle = try XCTUnwrap(SAOfflineEscapingHandle.handle(forCharacterSet: "utf8mb4", escapingModeOfConnection: nil))
        XCTAssertFalse(handle.escapesWithoutBackslashes)
    }
}
