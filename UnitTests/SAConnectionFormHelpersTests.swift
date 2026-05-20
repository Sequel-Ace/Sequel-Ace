//
//  SAConnectionFormHelpersTests.swift
//  Unit Tests
//
//  Pins the three small pure helpers lifted out of
//  SPConnectionController: favorite-ID generation, user-string
//  sanitization, and auto-name generation.
//

import XCTest

final class SAConnectionFormHelpersTests: XCTestCase {

    // MARK: - newFavoriteID

    /// The ID has to round-trip through `NSNumber.integerValue` —
    /// `Int` on 64-bit Macs is `Int64`, but historically the IDs
    /// have been stored as `NSInteger` (signed Int), and an upgrade
    /// must not produce values that look different in the plist.
    func testNewFavoriteIDIsNonZeroAndStableShape() {
        let id = SAConnectionFormHelpers.newFavoriteID()
        // Hashes of the time-interval-since-1970 string are essentially
        // never zero — guard against an accidental "always 0" regression.
        XCTAssertNotEqual(id.intValue, 0, "favorite ID hash collided with zero — extremely unlikely, suggests a regression")
    }

    /// Two IDs generated back-to-back should differ — the timestamp
    /// has microsecond precision via `%f`, so even fast calls yield
    /// distinct strings and (with overwhelming probability) distinct
    /// hashes. If this test gets flaky on a future macOS where
    /// `timeIntervalSince1970` no longer changes between calls, the
    /// hashing shape itself needs revisiting.
    func testNewFavoriteIDProgressesOverTime() {
        let first = SAConnectionFormHelpers.newFavoriteID()
        // Small sleep to guarantee the timestamp ticks.
        Thread.sleep(forTimeInterval: 0.01)
        let second = SAConnectionFormHelpers.newFavoriteID()
        XCTAssertNotEqual(first, second)
    }

    // MARK: - stripInvalidCharacters

    func testStripLeavesCleanStringUntouched() {
        XCTAssertEqual(SAConnectionFormHelpers.stripInvalidCharacters("Production DB"), "Production DB")
    }

    func testStripTrimsLeadingAndTrailingWhitespace() {
        XCTAssertEqual(SAConnectionFormHelpers.stripInvalidCharacters("   Production   "), "Production")
    }

    func testStripTrimsLeadingAndTrailingNewlines() {
        XCTAssertEqual(SAConnectionFormHelpers.stripInvalidCharacters("\nProduction\n"), "Production")
    }

    func testStripRemovesEmbeddedNewlines() {
        // Embedded newlines are not trimmed by stringByTrimming...; they
        // need the explicit replace pass. The original code did
        // trim-then-replace in that order, so a value like
        // "  foo\nbar  " becomes "foobar" (not "foo\nbar"). Pin this.
        XCTAssertEqual(SAConnectionFormHelpers.stripInvalidCharacters("  foo\nbar  "), "foobar")
    }

    func testStripPreservesEmbeddedWhitespace() {
        // Spaces inside the string survive — only newlines are stripped.
        XCTAssertEqual(SAConnectionFormHelpers.stripInvalidCharacters("hello world"), "hello world")
    }

    func testStripHandlesEmptyString() {
        XCTAssertEqual(SAConnectionFormHelpers.stripInvalidCharacters(""), "")
    }

    func testStripHandlesWhitespaceOnly() {
        XCTAssertEqual(SAConnectionFormHelpers.stripInvalidCharacters("   \n\t  "), "")
    }

    // MARK: - generateName

    func testGenerateNameTCPIPRequiresHost() {
        XCTAssertNil(SAConnectionFormHelpers.generateName(type: .tcpIP, host: "", database: ""))
    }

    func testGenerateNameSSHTunnelRequiresHost() {
        XCTAssertNil(SAConnectionFormHelpers.generateName(type: .sshTunnel, host: "", database: ""))
    }

    func testGenerateNameAWSIAMRequiresHost() {
        XCTAssertNil(SAConnectionFormHelpers.generateName(type: .awsIAM, host: "", database: ""))
    }

    func testGenerateNameSocketAlwaysReturnsLocalhost() {
        // Socket connections name themselves "localhost" regardless
        // of host field — the host doesn't apply to UNIX sockets.
        XCTAssertEqual(SAConnectionFormHelpers.generateName(type: .socket, host: "", database: ""), "localhost")
    }

    func testGenerateNameSocketIgnoresProvidedHost() {
        // Even if a host is in the form, socket connections still use
        // "localhost" — the form code clears host for socket types
        // but defensive correctness matters here.
        XCTAssertEqual(
            SAConnectionFormHelpers.generateName(type: .socket, host: "ignored.example.com", database: ""),
            "localhost"
        )
    }

    func testGenerateNameTCPIPUsesHost() {
        XCTAssertEqual(
            SAConnectionFormHelpers.generateName(type: .tcpIP, host: "db.example.com", database: ""),
            "db.example.com"
        )
    }

    func testGenerateNameAppendsDatabaseWithSlash() {
        XCTAssertEqual(
            SAConnectionFormHelpers.generateName(type: .tcpIP, host: "db.example.com", database: "orders"),
            "db.example.com/orders"
        )
    }

    func testGenerateNameSocketWithDatabaseAppends() {
        XCTAssertEqual(
            SAConnectionFormHelpers.generateName(type: .socket, host: "", database: "orders"),
            "localhost/orders"
        )
    }

    func testGenerateNameEmptyDatabaseIsOmitted() {
        // Empty database string is treated as "no database" — the
        // original code used `[[self database] length]` so this
        // matches that behavior (no stray "host/" suffix).
        XCTAssertEqual(
            SAConnectionFormHelpers.generateName(type: .tcpIP, host: "db.example.com", database: ""),
            "db.example.com"
        )
    }
}
