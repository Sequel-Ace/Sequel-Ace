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

    /// Without a session there is no mode to take over.
    func testWithoutASessionTheOrdinaryModeApplies() throws {
        let handle = try XCTUnwrap(SAOfflineEscapingHandle.handle(forCharacterSet: "utf8mb4", escapingModeOfConnection: nil))
        XCTAssertFalse(handle.escapesWithoutBackslashes)
    }
}
