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
        XCTAssertEqual(SAConnectionEscaper.characterSetForEscaping(onRecord: "utf8mb4", session: "gbk", handshake: "utf8mb4", sessionReportsChanges: false, sessionIsBeingReplaced: false), "gbk")
        // Latin1 transport: the client character set was changed for the session.
        XCTAssertEqual(SAConnectionEscaper.characterSetForEscaping(onRecord: "utf8mb4", session: "latin1", handshake: "utf8mb4", sessionReportsChanges: false, sessionIsBeingReplaced: false), "latin1")
        // A server that does not report changes: the record follows the connection's own changes.
        XCTAssertEqual(SAConnectionEscaper.characterSetForEscaping(onRecord: "gbk", session: "utf8mb4", handshake: "utf8mb4", sessionReportsChanges: false, sessionIsBeingReplaced: false), "gbk")
        // Names differing only in case are the same character set.
        XCTAssertEqual(SAConnectionEscaper.characterSetForEscaping(onRecord: "latin1", session: "UTF8MB4", handshake: "utf8mb4", sessionReportsChanges: false, sessionIsBeingReplaced: false), "latin1")
        // A session about to be replaced follows the record.
        XCTAssertEqual(SAConnectionEscaper.characterSetForEscaping(onRecord: "latin1", session: "utf8mb4", handshake: "latin1", sessionReportsChanges: false, sessionIsBeingReplaced: true), "latin1")
        // Nothing recorded yet.
        XCTAssertEqual(SAConnectionEscaper.characterSetForEscaping(onRecord: nil, session: "utf8mb4", handshake: nil, sessionReportsChanges: false, sessionIsBeingReplaced: false), "utf8mb4")
        XCTAssertNil(SAConnectionEscaper.characterSetForEscaping(onRecord: nil, session: nil, handshake: nil, sessionReportsChanges: false, sessionIsBeingReplaced: false))
    }


    /// Once a server has been seen reporting a change, what it reports stays the guide - also when
    /// it reports the name the session was connected with again.
    ///
    /// Without that, a session switched away from its handshake character set and back would be
    /// escaped for the record, which is where the connection's own last change went. Escaping
    /// `BF 27` for latin1 while the session reads GBK leaves the quote unescaped, because GBK
    /// takes `BF 5C` as one character.
    func testAReportedChangeKeepsTheSessionAuthoritativeEvenBackAtTheHandshakeName() {
        XCTAssertEqual(SAConnectionEscaper.characterSetForEscaping(onRecord: "latin1", session: "gbk", handshake: "gbk", sessionReportsChanges: true, sessionIsBeingReplaced: false), "gbk")
        // a server that never reported a change still leaves the record in charge
        XCTAssertEqual(SAConnectionEscaper.characterSetForEscaping(onRecord: "latin1", session: "gbk", handshake: "gbk", sessionReportsChanges: false, sessionIsBeingReplaced: false), "latin1")
        // and a session about to be replaced still follows the record
        XCTAssertEqual(SAConnectionEscaper.characterSetForEscaping(onRecord: "latin1", session: "gbk", handshake: "gbk", sessionReportsChanges: true, sessionIsBeingReplaced: true), "latin1")
    }

    /// Checks the whole sequence through the escaper: a session connected in GBK, switched to
    /// latin1 by the connection, then put back to GBK by a statement, escapes for GBK.
    func testASessionPutBackToItsHandshakeCharacterSetEscapesForIt() throws {
        let escaper = SAConnectionEscaper()
        escaper.recordSession(characterSet: "gbk", noBackslashEscapes: false, openTransaction: false, isHandshake: true)
        // the connection switches the session, which reports the new name
        escaper.recordSession(characterSet: "latin1", noBackslashEscapes: false, openTransaction: false, isHandshake: false)
        // a statement puts it back
        escaper.recordSession(characterSet: "gbk", noBackslashEscapes: false, openTransaction: false, isHandshake: false)

        let source: [UInt8] = [0xBF, 0x27]
        var destination = [UInt8](repeating: 0, count: 16)
        let written = source.withUnsafeBytes { bytes in
            destination.withUnsafeMutableBytes { out in
                escaper.escape(bytes.baseAddress, length: source.count, into: out.baseAddress!,
                               characterSetOnRecord: "latin1", sessionIsBeingReplaced: false)
            }
        }

        XCTAssertGreaterThan(written, 0)
        // GBK-safe: the lead byte is escaped as well, so the quote cannot be swallowed
        XCTAssertEqual(Array(destination[0..<written]), [0x5C, 0xBF, 0x5C, 0x27])
    }


    /// Checks that a reconnect starts the character-set tracking over.
    ///
    /// A session that reported a change says nothing about the one that replaces it: a reconnect
    /// can land on a server that does not report changes, and carrying the evidence over would
    /// let the handshake name override what the connection sets afterwards.
    func testAReconnectStartsTheCharacterSetTrackingOver() {
        let escaper = SAConnectionEscaper()
        escaper.recordSession(characterSet: "gbk", noBackslashEscapes: false, openTransaction: false, isHandshake: true)
        escaper.recordSession(characterSet: "latin1", noBackslashEscapes: false, openTransaction: false, isHandshake: false)

        // the new session reports only its handshake, as a server that does not report changes does
        escaper.recordSession(characterSet: "latin1", noBackslashEscapes: false, openTransaction: false, isHandshake: true)

        // the connection switched this session to GBK, which the record carries
        let source: [UInt8] = [0xBF, 0x27]
        var destination = [UInt8](repeating: 0, count: 16)
        let written = source.withUnsafeBytes { bytes in
            destination.withUnsafeMutableBytes { out in
                escaper.escape(bytes.baseAddress, length: source.count, into: out.baseAddress!,
                               characterSetOnRecord: "gbk", sessionIsBeingReplaced: false)
            }
        }

        XCTAssertGreaterThan(written, 0)
        XCTAssertEqual(Array(destination[0..<written]), [0x5C, 0xBF, 0x5C, 0x27], "escaped for the record, which is GBK")
    }

    /// Checks that forgetting a session also forgets what it reported.
    func testForgettingASessionForgetsItsTracking() {
        let escaper = SAConnectionEscaper()
        escaper.recordSession(characterSet: "gbk", noBackslashEscapes: false, openTransaction: false, isHandshake: true)
        escaper.recordSession(characterSet: "latin1", noBackslashEscapes: false, openTransaction: false, isHandshake: false)
        escaper.forgetSession()

        XCTAssertEqual(SAConnectionEscaper.characterSetForEscaping(onRecord: "gbk", session: nil, handshake: nil, sessionReportsChanges: false, sessionIsBeingReplaced: false), "gbk")
    }


    /// Checks that a forgotten session leaves the record in charge, which is what the session after
    /// it will be set up with.
    ///
    /// The connection forgets the session when it tears the handle down - on a disconnect, and on a
    /// connect the user cancelled. Without that, a value escaped while the teardown runs would
    /// follow the character set of a session that no longer exists.
    func testAForgottenSessionLeavesTheRecordInCharge() throws {
        let escaper = SAConnectionEscaper()
        escaper.recordSession(characterSet: "latin1", noBackslashEscapes: false, openTransaction: true, isHandshake: true)
        escaper.recordSession(characterSet: "latin1", noBackslashEscapes: false, openTransaction: true, isHandshake: false)

        escaper.forgetSession()

        XCTAssertFalse(escaper.sessionReportedOpenTransaction, "no session, no transaction")

        // the record is GBK, and that is what the value is escaped for - escaping `BF 27` for
        // latin1 would leave the quote for GBK to swallow
        let source: [UInt8] = [0xBF, 0x27]
        var destination = [UInt8](repeating: 0, count: 16)
        let written = source.withUnsafeBytes { bytes in
            destination.withUnsafeMutableBytes { out in
                escaper.escape(bytes.baseAddress, length: source.count, into: out.baseAddress!,
                               characterSetOnRecord: "gbk", sessionIsBeingReplaced: false)
            }
        }

        XCTAssertGreaterThan(written, 0)
        XCTAssertEqual(Array(destination[0..<written]), [0x5C, 0xBF, 0x5C, 0x27])
    }

    /// Checks that forgetting a session keeps the escaping mode sessions start with.
    ///
    /// A forgotten session is followed by a new one, and that one starts from the server's own
    /// default - which is what the last handshake showed. The mode therefore stays while the
    /// session's own character set does not.
    func testForgettingASessionKeepsTheModeSessionsStartWith() throws {
        let escaper = SAConnectionEscaper()
        // a server whose sessions start under NO_BACKSLASH_ESCAPES
        escaper.recordSession(characterSet: "utf8mb4", noBackslashEscapes: true, openTransaction: false, isHandshake: true)
        // a statement turned it off for this session
        escaper.recordSession(characterSet: "utf8mb4", noBackslashEscapes: false, openTransaction: false, isHandshake: false)

        escaper.forgetSession()

        let source = Array("it's".utf8)
        var destination = [UInt8](repeating: 0, count: 32)
        let written = source.withUnsafeBytes { bytes in
            destination.withUnsafeMutableBytes { out in
                escaper.escape(bytes.baseAddress, length: source.count, into: out.baseAddress!,
                               characterSetOnRecord: "utf8mb4", sessionIsBeingReplaced: false)
            }
        }

        XCTAssertGreaterThan(written, 0)
        XCTAssertEqual(String(decoding: destination[0..<written], as: UTF8.self), "it''s",
                       "back to the mode a new session starts in, so the quote is doubled")
    }


    /// Checks that the mode a session starts under can be set after the handshake.
    ///
    /// A server's `init_connect` runs once the handshake has been answered, so it can turn
    /// NO_BACKSLASH_ESCAPES on for every session while the handshake status and the global mode
    /// say nothing about it. The connection records the effective mode after its startup
    /// statements, and that is what a forgotten session falls back to - the mode the session
    /// after it will start under.
    func testTheStartingModeCanBeSetAfterTheHandshake() throws {
        let escaper = SAConnectionEscaper()
        // the handshake does not show it yet
        escaper.recordSession(characterSet: "utf8mb4", noBackslashEscapes: false, openTransaction: false, isHandshake: true)
        // the connection's startup statements reveal it
        escaper.recordStartingMode(noBackslashEscapes: true)

        escaper.forgetSession()

        let source = Array("it's".utf8)
        var destination = [UInt8](repeating: 0, count: 32)
        let written = source.withUnsafeBytes { bytes in
            destination.withUnsafeMutableBytes { out in
                escaper.escape(bytes.baseAddress, length: source.count, into: out.baseAddress!,
                               characterSetOnRecord: "utf8mb4", sessionIsBeingReplaced: false)
            }
        }

        XCTAssertGreaterThan(written, 0)
        XCTAssertEqual(String(decoding: destination[0..<written], as: UTF8.self), "it''s",
                       "the quote is doubled, as it must be for the session that follows")
    }

    /// The connection's escaper follows what the session reports.
    func testTheEscaperFollowsWhatTheSessionReports() {
        let escaper = SAConnectionEscaper()
        let value = Data([0xBF, 0x27])

        escaper.recordSession(characterSet: "utf8mb4", noBackslashEscapes: false, openTransaction: false, isHandshake: true)
        XCTAssertEqual(escape(value, with: escaper, onRecord: "gbk"), Data([0x5C, 0xBF, 0x5C, 0x27]))
        XCTAssertEqual(escape(value, with: escaper, onRecord: "latin1"), Data([0xBF, 0x5C, 0x27]))

        // A statement switched the session to gbk behind the connection's back.
        escaper.recordSession(characterSet: "gbk", noBackslashEscapes: false, openTransaction: false, isHandshake: false)
        XCTAssertEqual(escape(value, with: escaper, onRecord: "utf8mb4"), Data([0x5C, 0xBF, 0x5C, 0x27]))
        XCTAssertEqual(escape(value, with: escaper, onRecord: "utf8mb4", sessionIsBeingReplaced: true), Data([0xBF, 0x5C, 0x27]))

        // And to NO_BACKSLASH_ESCAPES.
        escaper.recordSession(characterSet: "utf8mb4", noBackslashEscapes: true, openTransaction: false, isHandshake: false)
        XCTAssertEqual(escape(Data("it's".utf8), with: escaper, onRecord: "latin1"), Data("it''s".utf8))
        escaper.recordSession(characterSet: "utf8mb4", noBackslashEscapes: false, openTransaction: false, isHandshake: false)
        XCTAssertEqual(escape(Data("it's".utf8), with: escaper, onRecord: "latin1"), Data("it\\'s".utf8))
    }

    /// Once the session is closed, values follow the record again.
    func testTheEscaperFollowsTheRecordOnceTheSessionIsClosed() {
        let escaper = SAConnectionEscaper()
        let value = Data([0xBF, 0x27])
        escaper.recordSession(characterSet: "utf8mb4", noBackslashEscapes: false, openTransaction: false, isHandshake: true)
        escaper.recordSession(characterSet: "gbk", noBackslashEscapes: false, openTransaction: false, isHandshake: false)
        XCTAssertEqual(escape(value, with: escaper, onRecord: "latin1"), Data([0x5C, 0xBF, 0x5C, 0x27]))

        escaper.forgetSession()
        XCTAssertEqual(escape(value, with: escaper, onRecord: "latin1"), Data([0xBF, 0x5C, 0x27]))
        XCTAssertEqual(SAConnectionEscaper.characterSetForEscaping(onRecord: "latin1", session: nil, handshake: nil, sessionReportsChanges: false, sessionIsBeingReplaced: true), "latin1")
    }

    /// A new session's escaping mode replaces the one the closed session had.
    func testANewSessionsModeReplacesTheClosedSessionsMode() {
        let escaper = SAConnectionEscaper()
        escaper.recordSession(characterSet: "utf8mb4", noBackslashEscapes: true, openTransaction: false, isHandshake: true)
        XCTAssertEqual(escape(Data([0x5C, 0x27]), with: escaper, onRecord: "utf8mb4"), Data([0x5C, 0x27, 0x27]))

        escaper.forgetSession()
        escaper.recordSession(characterSet: "utf8mb4", noBackslashEscapes: false, openTransaction: false, isHandshake: true)
        XCTAssertEqual(escape(Data([0x5C, 0x27]), with: escaper, onRecord: "utf8mb4"), Data([0x5C, 0x5C, 0x5C, 0x27]))
    }

    /// A mode a closed session was switched to does not outlive it; values follow the server's own mode.
    func testAClosedSessionsSwitchedModeDoesNotOutliveIt() {
        let escaper = SAConnectionEscaper()
        escaper.recordSession(characterSet: "utf8mb4", noBackslashEscapes: false, openTransaction: false, isHandshake: true)
        // A statement switched the session to NO_BACKSLASH_ESCAPES; then the session was closed.
        escaper.recordSession(characterSet: "utf8mb4", noBackslashEscapes: true, openTransaction: false, isHandshake: false)
        escaper.forgetSession()
        XCTAssertEqual(escape(Data([0x5C, 0x27]), with: escaper, onRecord: "utf8mb4"), Data([0x5C, 0x5C, 0x5C, 0x27]))
    }

    /// A server that starts every session without backslash escapes keeps that mode between sessions.
    func testTheServersOwnModeIsKeptBetweenSessions() {
        let escaper = SAConnectionEscaper()
        escaper.recordSession(characterSet: "utf8mb4", noBackslashEscapes: true, openTransaction: false, isHandshake: true)
        escaper.forgetSession()
        XCTAssertEqual(escape(Data([0x5C, 0x27]), with: escaper, onRecord: "utf8mb4"), Data([0x5C, 0x27, 0x27]))
    }

    /// The mode a session started in, after the server's own start-up statements, is kept between sessions.
    func testTheModeASessionStartedInIsKeptBetweenSessions() {
        let escaper = SAConnectionEscaper()
        escaper.recordSession(characterSet: "utf8mb4", noBackslashEscapes: false, openTransaction: false, isHandshake: true)
        // The server's start-up statement switched the mode after the handshake answered.
        escaper.recordStartingMode(noBackslashEscapes: true)
        // The user switched it back for this session only; then the session was closed.
        escaper.recordSession(characterSet: "utf8mb4", noBackslashEscapes: false, openTransaction: false, isHandshake: false)
        escaper.forgetSession()
        XCTAssertEqual(escape(Data([0x5C, 0x27]), with: escaper, onRecord: "utf8mb4"), Data([0x5C, 0x27, 0x27]))
    }

    /// The escaper keeps what the session said about an open transaction until the session is gone.
    func testTheEscaperKnowsWhetherTheSessionHasAnOpenTransaction() {
        let escaper = SAConnectionEscaper()
        XCTAssertFalse(escaper.sessionReportedOpenTransaction)
        escaper.recordSession(characterSet: "utf8mb4", noBackslashEscapes: false, openTransaction: true, isHandshake: false)
        XCTAssertTrue(escaper.sessionReportedOpenTransaction)
        escaper.forgetSession()
        XCTAssertFalse(escaper.sessionReportedOpenTransaction)
    }

    /// Without a character set the escaper knows, nothing is escaped.
    func testTheEscaperRefusesAnUnknownOrMissingCharacterSet() {
        let escaper = SAConnectionEscaper()
        XCTAssertNil(escape(Data("x".utf8), with: escaper, onRecord: nil))
        XCTAssertNil(escape(Data("x".utf8), with: escaper, onRecord: "no-such-character-set"))
        XCTAssertEqual(escape(Data("x".utf8), with: escaper, onRecord: "utf8mb4"), Data("x".utf8))
    }
    /// A session being replaced follows the record, which is what the next session is connected
    /// with - the state the connection reports while it is disconnecting.
    func testASessionBeingReplacedFollowsTheRecord() throws {
        let escaper = SAConnectionEscaper()
        escaper.recordSession(characterSet: "gbk", noBackslashEscapes: false, openTransaction: false, isHandshake: true)
        // A statement moved the session to latin1, so the escaper has seen this server report
        // changes; the record still says gbk, which the replacement session will use.
        escaper.recordSession(characterSet: "latin1", noBackslashEscapes: false, openTransaction: false, isHandshake: false)

        // BF 27: escaped for latin1 this is BF 5C 27, which GBK reads as one character followed
        // by an unescaped quote.
        let value = Data([0xBF, 0x27])
        let forTheOldSession = try XCTUnwrap(escape(value, with: escaper, onRecord: "gbk", sessionIsBeingReplaced: false))
        XCTAssertEqual(forTheOldSession, Data([0xBF, 0x5C, 0x27]), "the session reported latin1")

        let forTheReplacement = try XCTUnwrap(escape(value, with: escaper, onRecord: "gbk", sessionIsBeingReplaced: true))
        XCTAssertEqual(forTheReplacement, Data([0x5C, 0xBF, 0x5C, 0x27]),
                       "a session being replaced follows the record, so the lead byte is protected")
    }

    /// Latin1 transport with a server that reports nothing - behind a proxy that does not carry
    /// the session-state tracking, where the record is the only guide. The transport character
    /// set is what the server reads a value in, so that is what the record has to carry: escaping
    /// `BF 5C` for GBK leaves it untouched, and latin1 reads the `5C` as a backslash that escapes
    /// the closing quote.
    func testLatin1TransportIsEscapedForLatin1WhenNothingIsReported() throws {
        let escaper = SAConnectionEscaper()
        // A session that only ever reports the character set it was connected with, as one
        // without state tracking does.
        escaper.recordSession(characterSet: "gbk", noBackslashEscapes: false, openTransaction: false, isHandshake: true)

        let gbkCharacter = Data([0xBF, 0x5C])
        let forTheName = try XCTUnwrap(escape(gbkCharacter, with: escaper, onRecord: "gbk"))
        XCTAssertEqual(forTheName, gbkCharacter, "for GBK the pair is one character and stays as it is")

        // What the connection passes once latin1 transport is on.
        let forTheTransport = try XCTUnwrap(escape(gbkCharacter, with: escaper, onRecord: "latin1"))
        XCTAssertEqual(forTheTransport, Data([0xBF, 0x5C, 0x5C]),
                       "for latin1 the second byte is a backslash and has to be doubled")
    }

    /// A session being replaced is followed in its escaping mode no more than in its character
    /// set: the next session starts in the mode this server starts sessions in, and a value built
    /// now may be sent on it. Escaping with backslashes for a session that reads them literally
    /// would let the quote after one end the literal.
    func testASessionBeingReplacedUsesTheModeSessionsStartIn() throws {
        let escaper = SAConnectionEscaper()
        // The server starts sessions without backslash escapes - an init_connect, say - and this
        // session was then switched out of that mode.
        escaper.recordSession(characterSet: "utf8mb4", noBackslashEscapes: true, openTransaction: false, isHandshake: true)
        escaper.recordStartingMode(noBackslashEscapes: true)
        escaper.recordSession(characterSet: "utf8mb4", noBackslashEscapes: false, openTransaction: false, isHandshake: false)

        let quote = Data("it's".utf8)
        let forTheOldSession = try XCTUnwrap(escape(quote, with: escaper, onRecord: "utf8mb4", sessionIsBeingReplaced: false))
        XCTAssertEqual(forTheOldSession, Data("it\\'s".utf8), "the session itself takes backslash escapes")

        let forTheReplacement = try XCTUnwrap(escape(quote, with: escaper, onRecord: "utf8mb4", sessionIsBeingReplaced: true))
        XCTAssertEqual(forTheReplacement, Data("it''s".utf8),
                       "the replacement session starts without them, so the quote is doubled")
    }

}
