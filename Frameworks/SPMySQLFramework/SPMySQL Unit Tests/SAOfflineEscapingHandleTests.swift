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

    /// Models the connection running its own `SET NAMES`: the statement's report lands first -
    /// every statement produces one, whether or not it carries a character set - and the
    /// connection then judges whether the session followed, against the count it took before.
    /// - Parameters:
    ///   - characterSet: The character set the connection sets.
    ///   - escaper: The escaper to drive.
    ///   - reported: The character set the session names afterwards.
    ///   - wasReported: Whether the server sent a character set item with the statement.
    private func connectionSets(_ characterSet: String, on escaper: SAConnectionEscaper,
                                sessionThenNames reported: String?, wasReported: Bool = false) {
        let before = escaper.reportsSoFar
        escaper.recordSession(characterSet: reported, noBackslashEscapes: false, openTransaction: false,
                              isHandshake: false, characterSetWasReported: wasReported)
        escaper.recordCharacterSetSetByConnection(characterSet, reportsBefore: before)
    }

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
        XCTAssertEqual(SAConnectionEscaper.characterSetForEscaping(onRecord: "utf8mb4", session: "gbk", handshake: "utf8mb4", aCharacterSetHasBeenReported: false, sessionReportIsStale: false, sessionIsBeingReplaced: false), "gbk")
        // Latin1 transport: the client character set was changed for the session.
        XCTAssertEqual(SAConnectionEscaper.characterSetForEscaping(onRecord: "utf8mb4", session: "latin1", handshake: "utf8mb4", aCharacterSetHasBeenReported: false, sessionReportIsStale: false, sessionIsBeingReplaced: false), "latin1")
        // A server that does not report changes: the record follows the connection's own changes.
        XCTAssertEqual(SAConnectionEscaper.characterSetForEscaping(onRecord: "gbk", session: "utf8mb4", handshake: "utf8mb4", aCharacterSetHasBeenReported: false, sessionReportIsStale: false, sessionIsBeingReplaced: false), "gbk")
        // Names differing only in case are the same character set.
        XCTAssertEqual(SAConnectionEscaper.characterSetForEscaping(onRecord: "latin1", session: "UTF8MB4", handshake: "utf8mb4", aCharacterSetHasBeenReported: false, sessionReportIsStale: false, sessionIsBeingReplaced: false), "latin1")
        // A session about to be replaced follows the record.
        XCTAssertEqual(SAConnectionEscaper.characterSetForEscaping(onRecord: "latin1", session: "utf8mb4", handshake: "latin1", aCharacterSetHasBeenReported: false, sessionReportIsStale: false, sessionIsBeingReplaced: true), "latin1")
        // Nothing recorded yet.
        XCTAssertEqual(SAConnectionEscaper.characterSetForEscaping(onRecord: nil, session: "utf8mb4", handshake: nil, aCharacterSetHasBeenReported: false, sessionReportIsStale: false, sessionIsBeingReplaced: false), "utf8mb4")
        XCTAssertNil(SAConnectionEscaper.characterSetForEscaping(onRecord: nil, session: nil, handshake: nil, aCharacterSetHasBeenReported: false, sessionReportIsStale: false, sessionIsBeingReplaced: false))
    }


    /// Once a server has been seen reporting a change, what it reports stays the guide - also when
    /// it reports the name the session was connected with again.
    ///
    /// Without that, a session switched away from its handshake character set and back would be
    /// escaped for the record, which is where the connection's own last change went. Escaping
    /// `BF 27` for latin1 while the session reads GBK leaves the quote unescaped, because GBK
    /// takes `BF 5C` as one character.
    func testAReportedChangeKeepsTheSessionAuthoritativeEvenBackAtTheHandshakeName() {
        XCTAssertEqual(SAConnectionEscaper.characterSetForEscaping(onRecord: "latin1", session: "gbk", handshake: "gbk", aCharacterSetHasBeenReported: true, sessionReportIsStale: false, sessionIsBeingReplaced: false), "gbk")
        // a server that never reported a change still leaves the record in charge
        XCTAssertEqual(SAConnectionEscaper.characterSetForEscaping(onRecord: "latin1", session: "gbk", handshake: "gbk", aCharacterSetHasBeenReported: false, sessionReportIsStale: false, sessionIsBeingReplaced: false), "latin1")
        // and a session about to be replaced still follows the record
        XCTAssertEqual(SAConnectionEscaper.characterSetForEscaping(onRecord: "latin1", session: "gbk", handshake: "gbk", aCharacterSetHasBeenReported: true, sessionReportIsStale: false, sessionIsBeingReplaced: true), "latin1")
    }

    /// Checks the whole sequence through the escaper: a session connected in GBK, switched to
    /// latin1 by the connection, then put back to GBK by a statement, escapes for GBK.
    func testASessionPutBackToItsHandshakeCharacterSetEscapesForIt() throws {
        let escaper = SAConnectionEscaper()
        escaper.recordSession(characterSet: "gbk", noBackslashEscapes: false, openTransaction: false, isHandshake: true, characterSetWasReported: false)
        // the connection switches the session, which reports the new name
        escaper.recordSession(characterSet: "latin1", noBackslashEscapes: false, openTransaction: false, isHandshake: false, characterSetWasReported: false)
        // a statement puts it back
        escaper.recordSession(characterSet: "gbk", noBackslashEscapes: false, openTransaction: false, isHandshake: false, characterSetWasReported: false)

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
        escaper.recordSession(characterSet: "gbk", noBackslashEscapes: false, openTransaction: false, isHandshake: true, characterSetWasReported: false)
        escaper.recordSession(characterSet: "latin1", noBackslashEscapes: false, openTransaction: false, isHandshake: false, characterSetWasReported: false)

        // the new session reports only its handshake, as a server that does not report changes does
        escaper.recordSession(characterSet: "latin1", noBackslashEscapes: false, openTransaction: false, isHandshake: true, characterSetWasReported: false)

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
        escaper.recordSession(characterSet: "gbk", noBackslashEscapes: false, openTransaction: false, isHandshake: true, characterSetWasReported: false)
        escaper.recordSession(characterSet: "latin1", noBackslashEscapes: false, openTransaction: false, isHandshake: false, characterSetWasReported: false)
        escaper.forgetSession()

        XCTAssertEqual(SAConnectionEscaper.characterSetForEscaping(onRecord: "gbk", session: nil, handshake: nil, aCharacterSetHasBeenReported: false, sessionReportIsStale: false, sessionIsBeingReplaced: false), "gbk")
    }


    /// Checks that a forgotten session leaves the record in charge, which is what the session after
    /// it will be set up with.
    ///
    /// The connection forgets the session when it tears the handle down - on a disconnect, and on a
    /// connect the user cancelled. Without that, a value escaped while the teardown runs would
    /// follow the character set of a session that no longer exists.
    func testAForgottenSessionLeavesTheRecordInCharge() throws {
        let escaper = SAConnectionEscaper()
        escaper.recordSession(characterSet: "latin1", noBackslashEscapes: false, openTransaction: true, isHandshake: true, characterSetWasReported: false)
        escaper.recordSession(characterSet: "latin1", noBackslashEscapes: false, openTransaction: true, isHandshake: false, characterSetWasReported: false)

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
        escaper.recordSession(characterSet: "utf8mb4", noBackslashEscapes: true, openTransaction: false, isHandshake: true, characterSetWasReported: false)
        // a statement turned it off for this session
        escaper.recordSession(characterSet: "utf8mb4", noBackslashEscapes: false, openTransaction: false, isHandshake: false, characterSetWasReported: false)

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
        escaper.recordSession(characterSet: "utf8mb4", noBackslashEscapes: false, openTransaction: false, isHandshake: true, characterSetWasReported: false)
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

        escaper.recordSession(characterSet: "utf8mb4", noBackslashEscapes: false, openTransaction: false, isHandshake: true, characterSetWasReported: false)
        XCTAssertEqual(escape(value, with: escaper, onRecord: "gbk"), Data([0x5C, 0xBF, 0x5C, 0x27]))
        XCTAssertEqual(escape(value, with: escaper, onRecord: "latin1"), Data([0xBF, 0x5C, 0x27]))

        // A statement switched the session to gbk behind the connection's back.
        escaper.recordSession(characterSet: "gbk", noBackslashEscapes: false, openTransaction: false, isHandshake: false, characterSetWasReported: false)
        XCTAssertEqual(escape(value, with: escaper, onRecord: "utf8mb4"), Data([0x5C, 0xBF, 0x5C, 0x27]))
        XCTAssertEqual(escape(value, with: escaper, onRecord: "utf8mb4", sessionIsBeingReplaced: true), Data([0xBF, 0x5C, 0x27]))

        // And to NO_BACKSLASH_ESCAPES.
        escaper.recordSession(characterSet: "utf8mb4", noBackslashEscapes: true, openTransaction: false, isHandshake: false, characterSetWasReported: false)
        XCTAssertEqual(escape(Data("it's".utf8), with: escaper, onRecord: "latin1"), Data("it''s".utf8))
        escaper.recordSession(characterSet: "utf8mb4", noBackslashEscapes: false, openTransaction: false, isHandshake: false, characterSetWasReported: false)
        XCTAssertEqual(escape(Data("it's".utf8), with: escaper, onRecord: "latin1"), Data("it\\'s".utf8))
    }

    /// Once the session is closed, values follow the record again.
    func testTheEscaperFollowsTheRecordOnceTheSessionIsClosed() {
        let escaper = SAConnectionEscaper()
        let value = Data([0xBF, 0x27])
        escaper.recordSession(characterSet: "utf8mb4", noBackslashEscapes: false, openTransaction: false, isHandshake: true, characterSetWasReported: false)
        escaper.recordSession(characterSet: "gbk", noBackslashEscapes: false, openTransaction: false, isHandshake: false, characterSetWasReported: false)
        XCTAssertEqual(escape(value, with: escaper, onRecord: "latin1"), Data([0x5C, 0xBF, 0x5C, 0x27]))

        escaper.forgetSession()
        XCTAssertEqual(escape(value, with: escaper, onRecord: "latin1"), Data([0xBF, 0x5C, 0x27]))
        XCTAssertEqual(SAConnectionEscaper.characterSetForEscaping(onRecord: "latin1", session: nil, handshake: nil, aCharacterSetHasBeenReported: false, sessionReportIsStale: false, sessionIsBeingReplaced: true), "latin1")
    }

    /// A new session's escaping mode replaces the one the closed session had.
    func testANewSessionsModeReplacesTheClosedSessionsMode() {
        let escaper = SAConnectionEscaper()
        escaper.recordSession(characterSet: "utf8mb4", noBackslashEscapes: true, openTransaction: false, isHandshake: true, characterSetWasReported: false)
        XCTAssertEqual(escape(Data([0x5C, 0x27]), with: escaper, onRecord: "utf8mb4"), Data([0x5C, 0x27, 0x27]))

        escaper.forgetSession()
        escaper.recordSession(characterSet: "utf8mb4", noBackslashEscapes: false, openTransaction: false, isHandshake: true, characterSetWasReported: false)
        XCTAssertEqual(escape(Data([0x5C, 0x27]), with: escaper, onRecord: "utf8mb4"), Data([0x5C, 0x5C, 0x5C, 0x27]))
    }

    /// A mode a closed session was switched to does not outlive it; values follow the server's own mode.
    func testAClosedSessionsSwitchedModeDoesNotOutliveIt() {
        let escaper = SAConnectionEscaper()
        escaper.recordSession(characterSet: "utf8mb4", noBackslashEscapes: false, openTransaction: false, isHandshake: true, characterSetWasReported: false)
        // A statement switched the session to NO_BACKSLASH_ESCAPES; then the session was closed.
        escaper.recordSession(characterSet: "utf8mb4", noBackslashEscapes: true, openTransaction: false, isHandshake: false, characterSetWasReported: false)
        escaper.forgetSession()
        XCTAssertEqual(escape(Data([0x5C, 0x27]), with: escaper, onRecord: "utf8mb4"), Data([0x5C, 0x5C, 0x5C, 0x27]))
    }

    /// A server that starts every session without backslash escapes keeps that mode between sessions.
    func testTheServersOwnModeIsKeptBetweenSessions() {
        let escaper = SAConnectionEscaper()
        escaper.recordSession(characterSet: "utf8mb4", noBackslashEscapes: true, openTransaction: false, isHandshake: true, characterSetWasReported: false)
        escaper.forgetSession()
        XCTAssertEqual(escape(Data([0x5C, 0x27]), with: escaper, onRecord: "utf8mb4"), Data([0x5C, 0x27, 0x27]))
    }

    /// The mode a session started in, after the server's own start-up statements, is kept between sessions.
    func testTheModeASessionStartedInIsKeptBetweenSessions() {
        let escaper = SAConnectionEscaper()
        escaper.recordSession(characterSet: "utf8mb4", noBackslashEscapes: false, openTransaction: false, isHandshake: true, characterSetWasReported: false)
        // The server's start-up statement switched the mode after the handshake answered.
        escaper.recordStartingMode(noBackslashEscapes: true)
        // The user switched it back for this session only; then the session was closed.
        escaper.recordSession(characterSet: "utf8mb4", noBackslashEscapes: false, openTransaction: false, isHandshake: false, characterSetWasReported: false)
        escaper.forgetSession()
        XCTAssertEqual(escape(Data([0x5C, 0x27]), with: escaper, onRecord: "utf8mb4"), Data([0x5C, 0x27, 0x27]))
    }

    /// The escaper keeps what the session said about an open transaction until the session is gone.
    func testTheEscaperKnowsWhetherTheSessionHasAnOpenTransaction() {
        let escaper = SAConnectionEscaper()
        XCTAssertFalse(escaper.sessionReportedOpenTransaction)
        escaper.recordSession(characterSet: "utf8mb4", noBackslashEscapes: false, openTransaction: true, isHandshake: false, characterSetWasReported: false)
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
        escaper.recordSession(characterSet: "gbk", noBackslashEscapes: false, openTransaction: false, isHandshake: true, characterSetWasReported: false)
        // A statement moved the session to latin1, so the escaper has seen this server report
        // changes; the record still says gbk, which the replacement session will use.
        escaper.recordSession(characterSet: "latin1", noBackslashEscapes: false, openTransaction: false, isHandshake: false, characterSetWasReported: false)

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
        escaper.recordSession(characterSet: "gbk", noBackslashEscapes: false, openTransaction: false, isHandshake: true, characterSetWasReported: false)

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
        escaper.recordSession(characterSet: "utf8mb4", noBackslashEscapes: true, openTransaction: false, isHandshake: true, characterSetWasReported: false)
        escaper.recordStartingMode(noBackslashEscapes: true)
        escaper.recordSession(characterSet: "utf8mb4", noBackslashEscapes: false, openTransaction: false, isHandshake: false, characterSetWasReported: false)

        let quote = Data("it's".utf8)
        let forTheOldSession = try XCTUnwrap(escape(quote, with: escaper, onRecord: "utf8mb4", sessionIsBeingReplaced: false))
        XCTAssertEqual(forTheOldSession, Data("it\\'s".utf8), "the session itself takes backslash escapes")

        let forTheReplacement = try XCTUnwrap(escape(quote, with: escaper, onRecord: "utf8mb4", sessionIsBeingReplaced: true))
        XCTAssertEqual(forTheReplacement, Data("it''s".utf8),
                       "the replacement session starts without them, so the quote is doubled")
    }

    /// Codex's case: a session that reports a change leading back to the name it was connected
    /// with. The escaper cannot see that as a change by the name alone, so the report the server
    /// sent with the statement is what keeps it following the session rather than a record the
    /// session has moved away from.
    func testAReportedChangeBackToTheHandshakeNameIsFollowed() throws {
        let escaper = SAConnectionEscaper()
        escaper.recordSession(characterSet: "latin1", noBackslashEscapes: false, openTransaction: false, isHandshake: true, characterSetWasReported: false)
        // The connection moved the record to gbk, then a raw SET NAMES took the session back to
        // latin1 - the name it started in - and the server reported it.
        escaper.recordSession(characterSet: "latin1", noBackslashEscapes: false, openTransaction: false, isHandshake: false, characterSetWasReported: true)

        // BF 27 escaped for latin1 adds the backslash before the quote; escaped for gbk the BF
        // would be taken as a lead byte and protected instead.
        let value = Data([0xBF, 0x27])
        XCTAssertEqual(try XCTUnwrap(escape(value, with: escaper, onRecord: "gbk")), Data([0xBF, 0x5C, 0x27]),
                       "the server reported latin1, so latin1 is what it is escaped for")
    }

    /// Without that report the same names mean something else entirely: reporting being switched
    /// on says nothing about a character set that was set before it was, which is what an
    /// `init_connect` leaves behind. The record is then the only ground truth, and escaping for a
    /// multi-byte character set on a single-byte session merely adds a backslash, where the
    /// reverse can let a quote out of its literal.
    func testTrackingBeingOnIsNotAReport() throws {
        let escaper = SAConnectionEscaper()
        escaper.recordSession(characterSet: "latin1", noBackslashEscapes: false, openTransaction: false, isHandshake: true, characterSetWasReported: false)
        // Statements run, the tracking is on, and none of them reports a character set - which is
        // what a session set up by an init_connect before the tracking existed looks like.
        escaper.recordSession(characterSet: "latin1", noBackslashEscapes: false, openTransaction: false, isHandshake: false, characterSetWasReported: false)

        XCTAssertEqual(try XCTUnwrap(escape(Data([0xBF, 0x27]), with: escaper, onRecord: "gbk")),
                       Data([0x5C, 0xBF, 0x5C, 0x27]),
                       "nothing was reported, so the record decides")
    }

    /// Without being told, the same sequence falls back to the record - which is why the
    /// connection tells it. Pinned so the fallback's limit stays visible.
    func testWithoutBeingToldTheSameSequenceFollowsTheRecord() throws {
        let escaper = SAConnectionEscaper()
        escaper.recordSession(characterSet: "latin1", noBackslashEscapes: false, openTransaction: false, isHandshake: true, characterSetWasReported: false)
        escaper.recordSession(characterSet: "latin1", noBackslashEscapes: false, openTransaction: false, isHandshake: false, characterSetWasReported: false)

        let escaped = try XCTUnwrap(escape(Data([0xBF, 0x27]), with: escaper, onRecord: "gbk"))
        XCTAssertEqual(escaped, Data([0x5C, 0xBF, 0x5C, 0x27]), "escaped for the record, gbk")
    }

    /// Where the session's name, the handshake and the record all agree, the flag cannot change
    /// the answer - which is the case a `SET NAMES` typed by the user leaves behind on a server
    /// that does not report it. Where the connection sets the character set itself they do not
    /// agree, and the test below covers that.
    func testWhereNothingDisagreesTheFlagCannotChangeTheAnswer() {
        for recordAndSession in ["latin1", "gbk", "utf8mb4", "sjis"] {
            for reports in [true, false] {
                XCTAssertEqual(
                    SAConnectionEscaper.characterSetForEscaping(onRecord: recordAndSession,
                                                                session: recordAndSession,
                                                                handshake: recordAndSession,
                                                                aCharacterSetHasBeenReported: reports,
                                                                sessionReportIsStale: false,
                                                                sessionIsBeingReplaced: false),
                    recordAndSession,
                    "a session still on the name the client set reads the same either way")
            }
        }
    }

    /// A character set the connection sets itself settles whether the session reports its
    /// changes, for nothing: the statement goes out through the query path, so the client library
    /// follows it only if the session reported it.
    func testSettingTheCharacterSetSettlesWhetherTheSessionReports() {
        let escaper = SAConnectionEscaper()
        escaper.recordSession(characterSet: "latin1", noBackslashEscapes: false, openTransaction: false, isHandshake: true, characterSetWasReported: false)

        // A session that followed the statement reports its changes.
        connectionSets("gbk", on: escaper, sessionThenNames: "gbk")
        XCTAssertEqual(escape(Data([0xBF, 0x27]), with: escaper, onRecord: "gbk"), Data([0x5C, 0xBF, 0x5C, 0x27]))

        // One that still names the character set from before does not, whatever it claimed.
        let unreported = SAConnectionEscaper()
        unreported.recordSession(characterSet: "latin1", noBackslashEscapes: false, openTransaction: false, isHandshake: true, characterSetWasReported: false)
        connectionSets("gbk", on: unreported, sessionThenNames: "latin1")
        // The record is now gbk and the handle is still latin1; the value follows the record.
        XCTAssertEqual(escape(Data([0xBF, 0x27]), with: unreported, onRecord: "gbk"), Data([0x5C, 0xBF, 0x5C, 0x27]),
                       "the stale handle must not decide")
    }

    /// `utf8` and `utf8mb3` are one character set under two names, so a server that renamed it in
    /// its report is not taken for one whose report did not follow.
    func testTheRenamedUTF8CountsAsTheSameCharacterSet() {
        XCTAssertTrue(SAConnectionEscaper.namesTheSameCharacterSet("utf8mb3", "utf8"))
        XCTAssertTrue(SAConnectionEscaper.namesTheSameCharacterSet("utf8", "utf8mb3"))
        XCTAssertTrue(SAConnectionEscaper.namesTheSameCharacterSet("UTF8MB3", "utf8"))
        XCTAssertTrue(SAConnectionEscaper.namesTheSameCharacterSet("gbk", "GBK"))
        XCTAssertFalse(SAConnectionEscaper.namesTheSameCharacterSet("utf8", "utf8mb4"))
        XCTAssertFalse(SAConnectionEscaper.namesTheSameCharacterSet("latin1", "gbk"))
        XCTAssertFalse(SAConnectionEscaper.namesTheSameCharacterSet(nil, "gbk"))
    }

    /// A report the connection has caught out stays caught out, and no statement afterwards
    /// brings it back.
    ///
    /// The fallback reads a reported name that differs from the handshake as a reported change,
    /// and a stale name usually does differ - so without remembering which name was caught out,
    /// the next statement would re-enable the report and the stale name would decide after all.
    func testAReportCaughtOutStaysCaughtOut() {
        let escaper = SAConnectionEscaper()
        let value = Data([0xBF, 0x27])

        // Connected in utf8mb4 on a server whose changes do reach the client.
        escaper.recordSession(characterSet: "utf8mb4", noBackslashEscapes: false, openTransaction: false, isHandshake: true, characterSetWasReported: false)
        connectionSets("latin1", on: escaper, sessionThenNames: "latin1")
        XCTAssertEqual(escape(value, with: escaper, onRecord: "latin1"), Data([0xBF, 0x5C, 0x27]),
                       "while the report follows, it is the guide")

        // The tracking is turned off, and the connection moves the session to gbk. The statement
        // goes out, the client's view does not follow.
        connectionSets("gbk", on: escaper, sessionThenNames: "latin1")
        XCTAssertEqual(escape(value, with: escaper, onRecord: "gbk"), Data([0x5C, 0xBF, 0x5C, 0x27]),
                       "a caught-out report must not decide")

        // The next statement reports the same stale name again.
        escaper.recordSession(characterSet: "latin1", noBackslashEscapes: false, openTransaction: false, isHandshake: false, characterSetWasReported: false)
        XCTAssertEqual(escape(value, with: escaper, onRecord: "gbk"), Data([0x5C, 0xBF, 0x5C, 0x27]),
                       "and still must not, however many statements report it")
    }

    /// A report that moves off the name caught out is believed again: the client's view followed
    /// something, so the server is reporting after all.
    func testAReportThatMovesOnIsBelievedAgain() {
        let escaper = SAConnectionEscaper()
        let value = Data([0xBF, 0x27])
        escaper.recordSession(characterSet: "utf8mb4", noBackslashEscapes: false, openTransaction: false, isHandshake: true, characterSetWasReported: false)
        connectionSets("latin1", on: escaper, sessionThenNames: "utf8mb4")
        XCTAssertEqual(escape(value, with: escaper, onRecord: "latin1"), Data([0xBF, 0x5C, 0x27]),
                       "caught out, so the record decides")

        // The tracking comes back and a statement moves the session to gbk, which it reports.
        escaper.recordSession(characterSet: "gbk", noBackslashEscapes: false, openTransaction: false, isHandshake: false, characterSetWasReported: false)
        XCTAssertEqual(escape(value, with: escaper, onRecord: "latin1"), Data([0x5C, 0xBF, 0x5C, 0x27]),
                       "the report moved, so it is the guide again")
    }

    /// A new session starts with a clean slate, and a closed one leaves none behind.
    func testTheCaughtOutStateDoesNotOutliveItsSession() {
        for closeIt in [true, false] {
            let escaper = SAConnectionEscaper()
            escaper.recordSession(characterSet: "utf8mb4", noBackslashEscapes: false, openTransaction: false, isHandshake: true, characterSetWasReported: false)
            connectionSets("latin1", on: escaper, sessionThenNames: "utf8mb4")
            if closeIt {
                escaper.forgetSession()
            }
            // The next session connects in gbk and reports it.
            escaper.recordSession(characterSet: "gbk", noBackslashEscapes: false, openTransaction: false, isHandshake: true, characterSetWasReported: false)
            escaper.recordSession(characterSet: "gbk", noBackslashEscapes: false, openTransaction: false, isHandshake: false, characterSetWasReported: false)
            connectionSets("gbk", on: escaper, sessionThenNames: "gbk", wasReported: true)
            XCTAssertEqual(escape(Data([0xBF, 0x27]), with: escaper, onRecord: "gbk"), Data([0x5C, 0xBF, 0x5C, 0x27]),
                           closeIt ? "after the session was closed" : "after a fresh handshake")
        }
    }

    /// A caught-out report decides nothing even where the record is missing: the value is refused
    /// rather than escaped for a character set the session is not in.
    func testACaughtOutReportWithNoRecordRefusesTheValue() {
        XCTAssertNil(SAConnectionEscaper.characterSetForEscaping(onRecord: nil,
                                                                 session: "latin1",
                                                                 handshake: "utf8mb4",
                                                                 aCharacterSetHasBeenReported: true,
                                                                 sessionReportIsStale: true,
                                                                 sessionIsBeingReplaced: false))
        XCTAssertEqual(SAConnectionEscaper.characterSetForEscaping(onRecord: "gbk",
                                                                   session: "latin1",
                                                                   handshake: "utf8mb4",
                                                                   aCharacterSetHasBeenReported: true,
                                                                   sessionReportIsStale: true,
                                                                   sessionIsBeingReplaced: false), "gbk",
                       "stale outranks a report that claims to be followed")
    }

    /// A report the server sent itself settles that it is this session's, whatever it names.
    ///
    /// The sequence that needs it: a session reporting `gbk`, its tracking turned off by hand, the
    /// connection moved to latin1 - which the report does not follow, so it is caught out - the
    /// tracking turned back on, and a raw `SET NAMES gbk`. The report then carries `gbk` again,
    /// which is the same name it carried while frozen, so no rule over the name can tell the two
    /// apart. The tracking item the server sent with the statement can.
    func testAReportTheServerSentSettlesItWhateverItNames() {
        let escaper = SAConnectionEscaper()
        let value = Data([0xBF, 0x27])
        escaper.recordSession(characterSet: "utf8mb4", noBackslashEscapes: false, openTransaction: false,
                              isHandshake: true, characterSetWasReported: false)
        connectionSets("gbk", on: escaper, sessionThenNames: "gbk", wasReported: true)

        // The tracking is turned off and the connection moves the session to latin1; the report
        // stays on gbk and is caught out.
        connectionSets("latin1", on: escaper, sessionThenNames: "gbk")
        XCTAssertEqual(escape(value, with: escaper, onRecord: "latin1"), Data([0xBF, 0x5C, 0x27]),
                       "the record decides while the report is caught out")

        // The tracking comes back and a raw SET NAMES gbk is reported - the same name as before.
        escaper.recordSession(characterSet: "gbk", noBackslashEscapes: false, openTransaction: false,
                              isHandshake: false, characterSetWasReported: true)
        XCTAssertEqual(escape(value, with: escaper, onRecord: "latin1"), Data([0x5C, 0xBF, 0x5C, 0x27]),
                       "a report the server sent is this session's, so it decides again")
    }

    /// Without such an item nothing changes: a statement that reports nothing leaves a caught-out
    /// report caught out, which is the case the memory exists for.
    func testAStatementThatReportsNothingLeavesTheStateAlone() {
        let escaper = SAConnectionEscaper()
        let value = Data([0xBF, 0x27])
        escaper.recordSession(characterSet: "utf8mb4", noBackslashEscapes: false, openTransaction: false,
                              isHandshake: true, characterSetWasReported: false)
        connectionSets("latin1", on: escaper, sessionThenNames: "utf8mb4")
        for _ in 0..<3 {
            escaper.recordSession(characterSet: "utf8mb4", noBackslashEscapes: false, openTransaction: false,
                                  isHandshake: false, characterSetWasReported: false)
            XCTAssertEqual(escape(value, with: escaper, onRecord: "latin1"), Data([0xBF, 0x5C, 0x27]))
        }
    }

    /// And a reported item makes the session authoritative even where the name matches the
    /// handshake, which the old fallback could never see.
    func testAReportedChangeBackToTheHandshakeNameIsSeen() {
        let escaper = SAConnectionEscaper()
        escaper.recordSession(characterSet: "gbk", noBackslashEscapes: false, openTransaction: false,
                              isHandshake: true, characterSetWasReported: false)
        // The connection put latin1 on record; the session was then moved back to gbk and said so.
        connectionSets("latin1", on: escaper, sessionThenNames: "gbk")
        escaper.recordSession(characterSet: "gbk", noBackslashEscapes: false, openTransaction: false,
                              isHandshake: false, characterSetWasReported: true)
        XCTAssertEqual(escape(Data([0xBF, 0x27]), with: escaper, onRecord: "latin1"),
                       Data([0x5C, 0xBF, 0x5C, 0x27]))
    }

    /// A statement that lands between the connection's own `SET NAMES` and the judgement about it
    /// makes that judgement meaningless, so none is drawn.
    ///
    /// The judgement happens after the statement has let go of the connection, so another thread
    /// can get a statement in. Its report then names *its* character set, and comparing that with
    /// what this statement set would mark a perfectly fresh report as caught out - sending the
    /// next value out for the character set this statement asked for while the session is in the
    /// other one.
    func testAStatementInBetweenMakesTheJudgementMeaningless() {
        let escaper = SAConnectionEscaper()
        let value = Data([0xBF, 0x27])
        escaper.recordSession(characterSet: "utf8mb4", noBackslashEscapes: false, openTransaction: false,
                              isHandshake: true, characterSetWasReported: false)

        // This connection is about to set latin1 and takes the count first.
        let before = escaper.reportsSoFar
        // Its own statement reports latin1 ...
        escaper.recordSession(characterSet: "latin1", noBackslashEscapes: false, openTransaction: false,
                              isHandshake: false, characterSetWasReported: true)
        // ... and another thread's SET NAMES gbk lands before the judgement is made.
        escaper.recordSession(characterSet: "gbk", noBackslashEscapes: false, openTransaction: false,
                              isHandshake: false, characterSetWasReported: true)
        escaper.recordCharacterSetSetByConnection("latin1", reportsBefore: before)

        // The session is in gbk and said so; nothing here may send a value out for latin1.
        XCTAssertEqual(escape(value, with: escaper, onRecord: "latin1"), Data([0x5C, 0xBF, 0x5C, 0x27]),
                       "the newer report stands, and the value follows the session")
    }

    /// Without anything in between the judgement is drawn as before, so the guard does not simply
    /// switch the mechanism off.
    func testWithNothingInBetweenTheJudgementStillCounts() {
        let escaper = SAConnectionEscaper()
        escaper.recordSession(characterSet: "utf8mb4", noBackslashEscapes: false, openTransaction: false,
                              isHandshake: true, characterSetWasReported: false)
        // The session does not follow what the connection sets, which is what being caught out is.
        connectionSets("gbk", on: escaper, sessionThenNames: "utf8mb4")
        XCTAssertEqual(escape(Data([0xBF, 0x27]), with: escaper, onRecord: "gbk"), Data([0x5C, 0xBF, 0x5C, 0x27]),
                       "caught out, so the record decides")
    }

}
