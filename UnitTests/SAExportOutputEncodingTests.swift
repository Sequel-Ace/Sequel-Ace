//
//  SAExportOutputEncodingTests.swift
//  Sequel Ace
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import Foundation
import XCTest

final class SAExportOutputEncodingTests: XCTestCase {

    private let utf8 = String.Encoding.utf8.rawValue
    private let latin1 = String.Encoding.windowsCP1252.rawValue // what SPMySQL maps MySQL's latin1 to
    private let shiftJIS = String.Encoding.shiftJIS.rawValue

    private func encoding(_ format: SAExportOutputFormat, connection: UInt) -> UInt {
        SAExportOutputEncoding.outputEncoding(for: format, connectionEncoding: connection)
    }

    // MARK: - SQL dumps declare utf8mb4, so they are UTF-8 whatever the connection was (#2609)

    func testSQLDumpIsUTF8ForAUTF8Connection() {
        XCTAssertEqual(encoding(.sql, connection: utf8), utf8)
    }

    func testSQLDumpStaysUTF8ForALatin1Connection() {
        XCTAssertEqual(encoding(.sql, connection: latin1), utf8)
    }

    func testSQLDumpStaysUTF8ForAMultibyteConnection() {
        XCTAssertEqual(encoding(.sql, connection: shiftJIS), utf8)
    }

    // MARK: - DOT files are UTF-8 too

    func testDotFileIsUTF8RegardlessOfConnection() {
        XCTAssertEqual(encoding(.dot, connection: utf8), utf8)
        XCTAssertEqual(encoding(.dot, connection: latin1), utf8)
    }

    // MARK: - XML declares encoding="utf-8" in its prolog, so the body is UTF-8 (#2637)

    func testXMLIsUTF8RegardlessOfConnection() {
        XCTAssertEqual(encoding(.xml, connection: utf8), utf8)
        XCTAssertEqual(encoding(.xml, connection: latin1), utf8)
        XCTAssertEqual(encoding(.xml, connection: shiftJIS), utf8)
    }

    // MARK: - CSV has no declaration and follows the connection

    func testCSVFollowsTheConnectionEncoding() {
        XCTAssertEqual(encoding(.csv, connection: utf8), utf8)
        XCTAssertEqual(encoding(.csv, connection: latin1), latin1)
        XCTAssertEqual(encoding(.csv, connection: shiftJIS), shiftJIS)
    }
}
