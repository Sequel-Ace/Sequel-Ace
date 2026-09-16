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
    private func escape(_ bytes: Data, with escaper: SAConnectionEscaper, onRecord characterSet: String?,
                        sessionIsBeingReplaced: Bool = false) -> Data? {
        var output = [UInt8](repeating: 0, count: bytes.count * 2 + 1)
        let length = bytes.withUnsafeBytes { source in
            output.withUnsafeMutableBytes { destination -> Int in
                guard let destination = destination.baseAddress else {
                    return -1
                }
                return escaper.escape(source.baseAddress, length: bytes.count, into: destination,
                                      characterSetOnRecord: characterSet, sessionIsBeingReplaced: sessionIsBeingReplaced)
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

    /// A session that is being replaced is escaped for the record; otherwise a reported change wins.
    func testTheCharacterSetForEscapingFollowsTheSessionWhereItChanged() {
        // A statement changed the character set; the session reports it.
        XCTAssertEqual(SAConnectionEscaper.characterSetForEscaping(onRecord: "utf8mb4", session: "gbk", handshake: "utf8mb4", sessionIsBeingReplaced: false), "gbk")
        // Latin1 transport: the client character set was changed for the session.
        XCTAssertEqual(SAConnectionEscaper.characterSetForEscaping(onRecord: "utf8mb4", session: "latin1", handshake: "utf8mb4", sessionIsBeingReplaced: false), "latin1")
        // A server that does not report changes: the record follows the connection's own changes.
        XCTAssertEqual(SAConnectionEscaper.characterSetForEscaping(onRecord: "gbk", session: "utf8mb4", handshake: "utf8mb4", sessionIsBeingReplaced: false), "gbk")
        // Names differing only in case are the same character set.
        XCTAssertEqual(SAConnectionEscaper.characterSetForEscaping(onRecord: "latin1", session: "UTF8MB4", handshake: "utf8mb4", sessionIsBeingReplaced: false), "latin1")
        // A session about to be replaced follows the record.
        XCTAssertEqual(SAConnectionEscaper.characterSetForEscaping(onRecord: "latin1", session: "utf8mb4", handshake: "latin1", sessionIsBeingReplaced: true), "latin1")
        // Nothing recorded yet.
        XCTAssertEqual(SAConnectionEscaper.characterSetForEscaping(onRecord: nil, session: "utf8mb4", handshake: nil, sessionIsBeingReplaced: false), "utf8mb4")
        XCTAssertNil(SAConnectionEscaper.characterSetForEscaping(onRecord: nil, session: nil, handshake: nil, sessionIsBeingReplaced: false))
    }

    /// The connection's escaper follows what the session reports.
    func testTheEscaperFollowsWhatTheSessionReports() {
        let escaper = SAConnectionEscaper()
        let value = Data([0xBF, 0x27])

        escaper.recordSession(characterSet: "utf8mb4", noBackslashEscapes: false, isHandshake: true)
        XCTAssertEqual(escape(value, with: escaper, onRecord: "gbk"), Data([0x5C, 0xBF, 0x5C, 0x27]))
        XCTAssertEqual(escape(value, with: escaper, onRecord: "latin1"), Data([0xBF, 0x5C, 0x27]))

        // A statement switched the session to gbk behind the connection's back.
        escaper.recordSession(characterSet: "gbk", noBackslashEscapes: false, isHandshake: false)
        XCTAssertEqual(escape(value, with: escaper, onRecord: "utf8mb4"), Data([0x5C, 0xBF, 0x5C, 0x27]))
        XCTAssertEqual(escape(value, with: escaper, onRecord: "utf8mb4", sessionIsBeingReplaced: true), Data([0xBF, 0x5C, 0x27]))

        // And to NO_BACKSLASH_ESCAPES.
        escaper.recordSession(characterSet: "utf8mb4", noBackslashEscapes: true, isHandshake: false)
        XCTAssertEqual(escape(Data("it's".utf8), with: escaper, onRecord: "latin1"), Data("it''s".utf8))
        escaper.recordSession(characterSet: "utf8mb4", noBackslashEscapes: false, isHandshake: false)
        XCTAssertEqual(escape(Data("it's".utf8), with: escaper, onRecord: "latin1"), Data("it\\'s".utf8))
    }

    /// Once the session is closed, values follow the record again.
    func testTheEscaperFollowsTheRecordOnceTheSessionIsClosed() {
        let escaper = SAConnectionEscaper()
        let value = Data([0xBF, 0x27])
        escaper.recordSession(characterSet: "utf8mb4", noBackslashEscapes: false, isHandshake: true)
        escaper.recordSession(characterSet: "gbk", noBackslashEscapes: false, isHandshake: false)
        XCTAssertEqual(escape(value, with: escaper, onRecord: "latin1"), Data([0x5C, 0xBF, 0x5C, 0x27]))

        escaper.forgetSession()
        XCTAssertEqual(escape(value, with: escaper, onRecord: "latin1"), Data([0xBF, 0x5C, 0x27]))
        XCTAssertEqual(SAConnectionEscaper.characterSetForEscaping(onRecord: "latin1", session: nil, handshake: nil, sessionIsBeingReplaced: true), "latin1")
    }

    /// A new session's escaping mode replaces the one the closed session had.
    func testANewSessionsModeReplacesTheClosedSessionsMode() {
        let escaper = SAConnectionEscaper()
        escaper.recordSession(characterSet: "utf8mb4", noBackslashEscapes: true, isHandshake: true)
        XCTAssertEqual(escape(Data("\\'".utf8), with: escaper, onRecord: "utf8mb4"), Data("\\''".utf8))

        escaper.forgetSession()
        escaper.recordSession(characterSet: "utf8mb4", noBackslashEscapes: false, isHandshake: true)
        XCTAssertEqual(escape(Data("\\'".utf8), with: escaper, onRecord: "utf8mb4"), Data("\\\\\\'".utf8))
    }

    /// Without a character set the escaper knows, nothing is escaped.
    func testTheEscaperRefusesAnUnknownOrMissingCharacterSet() {
        let escaper = SAConnectionEscaper()
        XCTAssertNil(escape(Data("x".utf8), with: escaper, onRecord: nil))
        XCTAssertNil(escape(Data("x".utf8), with: escaper, onRecord: "no-such-character-set"))
        XCTAssertEqual(escape(Data("x".utf8), with: escaper, onRecord: "utf8mb4"), Data("x".utf8))
    }
}
