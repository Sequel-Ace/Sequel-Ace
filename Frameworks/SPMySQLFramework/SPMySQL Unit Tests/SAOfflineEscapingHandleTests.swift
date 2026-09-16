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

/// How values are escaped without a server, for the character set on record.
final class SAOfflineEscapingHandleTests: XCTestCase {

    private let noBackslashEscapes: UInt32 = 512

    /// Escapes a value through a connection's escaper, as the connection does.
    private func escape(_ bytes: Data, with escaper: SAConnectionEscaper, characterSet: String?, noBackslashEscapes: Bool = false) -> Data? {
        var output = [UInt8](repeating: 0, count: bytes.count * 2 + 1)
        let length = bytes.withUnsafeBytes { source in
            output.withUnsafeMutableBytes { destination in
                escaper.escape(source.baseAddress, length: bytes.count, into: destination.baseAddress!,
                               characterSet: characterSet, noBackslashEscapes: noBackslashEscapes)
            }
        }
        return length < 0 ? nil : Data(output.prefix(length))
    }

    /// The handle takes the character set it is asked for, without a server.
    func testTheHandleFollowsTheCharacterSetOnRecord() throws {
        for characterSet in ["gbk", "latin1", "utf8mb4", "sjis"] {
            let handle = try XCTUnwrap(SAOfflineEscapingHandle.handle(forCharacterSet: characterSet, serverStatus: 0))
            XCTAssertEqual(handle.characterSetName, characterSet)
        }
    }

    /// A character set the client library does not know gives no handle.
    func testAnUnknownCharacterSetGivesNoHandle() {
        XCTAssertNil(SAOfflineEscapingHandle.handle(forCharacterSet: "no-such-character-set", serverStatus: 0))
    }

    /// The handle escapes in the session's mode.
    func testTheHandleTakesOverTheEscapingMode() throws {
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
        let strict = try XCTUnwrap(SAOfflineEscapingHandle.handle(forCharacterSet: "utf8mb4", serverStatus: noBackslashEscapes))
        XCTAssertEqual(strict.escapedBytes(Data("it's a \\".utf8)), Data("it''s a \\".utf8))

        let ordinary = try XCTUnwrap(SAOfflineEscapingHandle.handle(forCharacterSet: "utf8mb4", serverStatus: 0))
        XCTAssertEqual(ordinary.escapedBytes(Data("it's a \\".utf8)), Data("it\\'s a \\\\".utf8))
        XCTAssertEqual(ordinary.escapedBytes(Data()), Data())
    }

    /// The connection's escaper follows the character set and the mode it is given each time.
    func testTheEscaperFollowsTheCharacterSetAndModeOnRecord() {
        let escaper = SAConnectionEscaper()
        let value = Data([0xBF, 0x27])

        XCTAssertEqual(escape(value, with: escaper, characterSet: "gbk"), Data([0x5C, 0xBF, 0x5C, 0x27]))
        XCTAssertEqual(escape(value, with: escaper, characterSet: "latin1"), Data([0xBF, 0x5C, 0x27]))
        XCTAssertEqual(escape(Data("it's".utf8), with: escaper, characterSet: "latin1", noBackslashEscapes: true), Data("it''s".utf8))
        XCTAssertEqual(escape(Data("it's".utf8), with: escaper, characterSet: "latin1"), Data("it\\'s".utf8))
    }

    /// Without a character set the escaper knows, nothing is escaped.
    func testTheEscaperRefusesAnUnknownOrMissingCharacterSet() {
        let escaper = SAConnectionEscaper()
        XCTAssertNil(escape(Data("x".utf8), with: escaper, characterSet: nil))
        XCTAssertNil(escape(Data("x".utf8), with: escaper, characterSet: "no-such-character-set"))
        XCTAssertEqual(escape(Data("x".utf8), with: escaper, characterSet: "utf8mb4"), Data("x".utf8))
    }
}
