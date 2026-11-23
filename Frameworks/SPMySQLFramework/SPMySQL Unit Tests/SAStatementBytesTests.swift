//
//  SAStatementBytesTests.swift
//  SPMySQLFramework
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//
//  More info at <https://github.com/Sequel-Ace/Sequel-Ace>
//

import XCTest
@testable import SPMySQL

/// A statement that counts how often it is asked for its bytes.
private final class SACountingStatement: NSString {
    private var text: NSString = ""
    private(set) var serialisations = 0

    convenience init(statement: String) {
        self.init()
        text = statement as NSString
    }

    override var length: Int { text.length }

    override func character(at index: Int) -> unichar { text.character(at: index) }

    override func data(using encoding: UInt, allowLossyConversion lossy: Bool) -> Data? {
        serialisations += 1
        return text.data(using: encoding, allowLossyConversion: lossy)
    }
}

/// The bytes of a statement are built for the session that sends them, attempt by attempt.
final class SAStatementBytesTests: XCTestCase {
    private let utf8 = UInt(String.Encoding.utf8.rawValue)
    private let latin1 = UInt(String.Encoding.isoLatin1.rawValue)
    private let noEncodingNamed = SAStatementBytes.encodingOfTheSession

    /// A statement whose caller named no encoding is serialised in the character set the session reads.
    func testAStatementIsSerialisedInTheCharacterSetTheSessionReads() {
        let bytes = SAStatementBytes(statement: "SELECT 'é'", encodingNamedByTheCaller: noEncodingNamed)
        XCTAssertEqual(bytes.encoding, noEncodingNamed, "nothing is built before the first attempt")

        let attempt = bytes.attempt(onSessionReading: utf8, maximumSize: 1024)

        XCTAssertEqual(attempt.bytes.map { Data(referencing: $0) }, "SELECT 'é'".data(using: .utf8))
        XCTAssertEqual(attempt.encoding, utf8)
        XCTAssertEqual(attempt.errorID, 0)
        XCTAssertNil(attempt.message)
        XCTAssertEqual(bytes.encoding, utf8, "the result is read in the encoding the bytes were built in")
    }

    /// A retry after a reconnect lands on a session that may read another character set; the bytes
    /// are built again for it, not sent as they were.
    func testARetryOnASessionReadingAnotherCharacterSetGetsTheStatementBuiltAgain() {
        let bytes = SAStatementBytes(statement: "SELECT 'é'", encodingNamedByTheCaller: noEncodingNamed)
        _ = bytes.attempt(onSessionReading: utf8, maximumSize: 1024)

        let retry = bytes.attempt(onSessionReading: latin1, maximumSize: 1024)

        XCTAssertEqual(retry.bytes.map { Data(referencing: $0) }, "SELECT 'é'".data(using: .isoLatin1))
        XCTAssertEqual(retry.encoding, latin1)
        XCTAssertEqual(bytes.encoding, latin1)
    }

    /// While the session reads the same character set, a retry reuses the bytes already built.
    func testTheBytesAreKeptWhileTheSessionReadsTheSameCharacterSet() {
        let bytes = SAStatementBytes(statement: "SELECT 'é'", encodingNamedByTheCaller: noEncodingNamed)

        let first = bytes.attempt(onSessionReading: utf8, maximumSize: 1024)
        let second = bytes.attempt(onSessionReading: utf8, maximumSize: 1024)

        XCTAssertTrue(first.bytes === second.bytes, "the same bytes, not a second serialisation")
    }

    /// A caller that named an encoding, as the import does for its file, gets that one on any session.
    func testACallerThatNamedAnEncodingGetsItWhateverTheSessionReads() {
        let bytes = SAStatementBytes(statement: "é", encodingNamedByTheCaller: latin1)

        let attempt = bytes.attempt(onSessionReading: utf8, maximumSize: 1024)

        XCTAssertEqual(attempt.bytes.map { Data(referencing: $0) }, Data([0xE9]))
        XCTAssertEqual(attempt.encoding, latin1)
        XCTAssertEqual(bytes.length(onSessionReading: utf8), 1, "measured in the caller's encoding as well")
    }

    /// The bytes measured against the packet limit before the session is held are the ones the
    /// first attempt sends; the statement is not serialised a second time for nothing.
    func testTheBytesMeasuredBeforeTheFirstAttemptAreTheOnesItSends() {
        let statement = SACountingStatement(statement: "SELECT 'é'")
        let bytes = SAStatementBytes(statement: statement, encodingNamedByTheCaller: noEncodingNamed)

        XCTAssertEqual(bytes.length(onSessionReading: utf8), 11)
        let attempt = bytes.attempt(onSessionReading: utf8, maximumSize: 1024)

        XCTAssertEqual(statement.serialisations, 1, "measured once, sent as measured")
        XCTAssertEqual(attempt.bytes.map { Data(referencing: $0) }, "SELECT 'é'".data(using: .utf8))
        XCTAssertEqual(bytes.encoding, utf8)
    }

    /// A session that reads another character set than the statement was measured in - the one a
    /// reconnect in between restored - gets the bytes built again for it.
    func testASessionReadingAnotherCharacterSetThanMeasuredGetsTheBytesBuiltAgain() {
        let statement = SACountingStatement(statement: "SELECT 'é'")
        let bytes = SAStatementBytes(statement: statement, encodingNamedByTheCaller: noEncodingNamed)

        XCTAssertEqual(bytes.length(onSessionReading: utf8), 11)
        let attempt = bytes.attempt(onSessionReading: latin1, maximumSize: 1024)

        XCTAssertEqual(statement.serialisations, 2)
        XCTAssertEqual(attempt.bytes.map { Data(referencing: $0) }, "SELECT 'é'".data(using: .isoLatin1))
        XCTAssertEqual(attempt.encoding, latin1)
    }

    /// The same text needs more bytes in another character set: a statement that fit the session
    /// before is refused on the one a retry lands on, with the error the server would give.
    func testAStatementTheSessionCannotTakeIsRefusedWithThePacketError() {
        let bytes = SAStatementBytes(statement: "éé", encodingNamedByTheCaller: noEncodingNamed)

        let fits = bytes.attempt(onSessionReading: latin1, maximumSize: 3)
        let refused = bytes.attempt(onSessionReading: utf8, maximumSize: 3)

        XCTAssertNotNil(fits.bytes, "two bytes in Latin-1 fit a limit of three")
        XCTAssertEqual(fits.errorID, 0)
        XCTAssertNil(refused.bytes, "four bytes in UTF-8 do not")
        XCTAssertEqual(refused.errorID, 1153)
        XCTAssertEqual(refused.sqlState, "08S01")
        XCTAssertEqual(refused.message, "The query length of 4 bytes is larger than max_allowed_packet size (3).")
        XCTAssertEqual(refused.encoding, utf8)
    }

    /// A refusal is measured against the limit of this attempt, and a statement exactly at the limit goes.
    func testAStatementAtTheLimitIsSent() {
        let bytes = SAStatementBytes(statement: "éé", encodingNamedByTheCaller: noEncodingNamed)

        let attempt = bytes.attempt(onSessionReading: utf8, maximumSize: 4)

        XCTAssertNotNil(attempt.bytes)
        XCTAssertEqual(attempt.errorID, 0)
    }

    /// The statement is serialised by its own conversion, not by a copy's: a statement that reports
    /// when it is being serialised (the live stop test sends one) is still heard.
    func testTheStatementIsSerialisedByItsOwnConversion() {
        let statement = SACountingStatement(statement: "SELECT 1")
        let bytes = SAStatementBytes(statement: statement, encodingNamedByTheCaller: noEncodingNamed)

        let attempt = bytes.attempt(onSessionReading: utf8, maximumSize: 1024)

        XCTAssertEqual(statement.serialisations, 1)
        XCTAssertEqual(attempt.bytes.map { Data(referencing: $0) }, "SELECT 1".data(using: .utf8))
        XCTAssertTrue(bytes.statement === statement)
    }

    /// A character the session's character set lacks is replaced, as the connection always did,
    /// not refused.
    func testACharacterTheCharacterSetLacksIsReplacedNotRefused() {
        let bytes = SAStatementBytes(statement: "€", encodingNamedByTheCaller: noEncodingNamed)

        let attempt = bytes.attempt(onSessionReading: latin1, maximumSize: 1024)

        XCTAssertEqual(attempt.bytes.map { Data(referencing: $0) }, "€".data(using: .isoLatin1, allowLossyConversion: true))
        XCTAssertEqual(attempt.bytes?.length, 1)
    }
}
