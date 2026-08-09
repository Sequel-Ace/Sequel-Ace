//
//  SAHelpViewerOnlineURLBuilderTests.swift
//  Unit Tests
//
//  Created by Codex on 17.06.26.
//  Copyright (c) 2026 Sequel Ace. All rights reserved.
//

import XCTest

final class SAHelpViewerOnlineURLBuilderTests: XCTestCase {

    func testMySQLDocumentIDSelectionKeepsVersionSpecificDocs() {
        XCTAssertEqual(SAHelpViewerOnlineURLBuilder.mysqlDocumentID(major: 5, minor: 6, release: 51), 11)
        XCTAssertEqual(SAHelpViewerOnlineURLBuilder.mysqlDocumentID(major: 5, minor: 7, release: 44), 12)
        XCTAssertEqual(SAHelpViewerOnlineURLBuilder.mysqlDocumentID(major: 8, minor: 0, release: 37), 201)
        XCTAssertEqual(SAHelpViewerOnlineURLBuilder.mysqlDocumentID(major: 8, minor: 4, release: 0), 371)
        XCTAssertEqual(SAHelpViewerOnlineURLBuilder.mysqlDocumentID(major: 9, minor: 0, release: 0), 515)
    }

    func testMySQLDocumentIDDefaultsOlderUnsupportedServersTo80Docs() {
        XCTAssertEqual(SAHelpViewerOnlineURLBuilder.mysqlDocumentID(major: 5, minor: 5, release: 62), 201)
        XCTAssertEqual(SAHelpViewerOnlineURLBuilder.mysqlDocumentID(major: 4, minor: 1, release: 22), 201)
    }

    func testMySQLOnlineHelpURLUsesSelectedDocumentID() {
        let url = SAHelpViewerOnlineURLBuilder.onlineHelpURL(
            forTopic: "SELECT",
            serverVersionString: "8.4.0",
            mysqlMajorVersion: 8,
            mysqlMinorVersion: 4,
            mysqlReleaseVersion: 0
        )

        XCTAssertEqual(url?.absoluteString, "https://dev.mysql.com/doc/search/?d=371&p=1&q=SELECT")
    }

    func testMySQL9AndNewerUseCurrentInnovationDocs() {
        let url = SAHelpViewerOnlineURLBuilder.onlineHelpURL(
            forTopic: "CREATE TABLE",
            serverVersionString: "9.0.1",
            mysqlMajorVersion: 9,
            mysqlMinorVersion: 0,
            mysqlReleaseVersion: 1
        )

        XCTAssertEqual(url?.absoluteString, "https://dev.mysql.com/doc/search/?d=515&p=1&q=CREATE%20TABLE")
    }

    func testMySQLOnlineHelpURLPercentEncodesQueryDelimitersInTopic() {
        // Topics containing query delimiters (`&`, `=`, `+`) must be percent-encoded
        // so they survive as the `q` value instead of being spliced into the URL
        // structure — regression: a bare `&`/`=` truncated the query, `+` read as a space.
        let combined = SAHelpViewerOnlineURLBuilder.onlineHelpURL(
            forTopic: "a&b=c+d",
            serverVersionString: "8.4.0",
            mysqlMajorVersion: 8,
            mysqlMinorVersion: 4,
            mysqlReleaseVersion: 0
        )
        XCTAssertEqual(combined?.absoluteString, "https://dev.mysql.com/doc/search/?d=371&p=1&q=a%26b%3Dc%2Bd")

        let plusOnly = SAHelpViewerOnlineURLBuilder.mysqlOnlineHelpURL(forTopic: "a+b", documentID: 12)
        XCTAssertEqual(plusOnly?.absoluteString, "https://dev.mysql.com/doc/search/?d=12&p=1&q=a%2Bb")

        // A topic mixing a space with a delimiter: the space still encodes to `%20`
        // alongside the now-escaped delimiter.
        let withSpace = SAHelpViewerOnlineURLBuilder.mysqlOnlineHelpURL(forTopic: "GRANT & REVOKE", documentID: 201)
        XCTAssertEqual(withSpace?.absoluteString, "https://dev.mysql.com/doc/search/?d=201&p=1&q=GRANT%20%26%20REVOKE")

        // Round-trip: the escaped value must parse back as a single `q` item equal to
        // the original topic — i.e. the delimiter did not split the query.
        let parsed = URLComponents(url: URL(string: combined?.absoluteString ?? "")!, resolvingAgainstBaseURL: false)
        XCTAssertEqual(parsed?.queryItems?.first { $0.name == "q" }?.value, "a&b=c+d")
    }

    func testMariaDBVersionDetectionUsesCachedVersionString() {
        XCTAssertTrue(SAHelpViewerOnlineURLBuilder.isMariaDBServerVersion("10.11.8-MariaDB"))
        XCTAssertTrue(SAHelpViewerOnlineURLBuilder.isMariaDBServerVersion("11.4.5-mariadb-ubu2404"))
        XCTAssertFalse(SAHelpViewerOnlineURLBuilder.isMariaDBServerVersion("8.4.0"))
        XCTAssertFalse(SAHelpViewerOnlineURLBuilder.isMariaDBServerVersion(nil))
    }

    func testMariaDBOnlineHelpURLUsesTopicSlug() {
        let url = SAHelpViewerOnlineURLBuilder.onlineHelpURL(
            forTopic: "JSON TABLE",
            serverVersionString: "10.11.8-MariaDB",
            mysqlMajorVersion: 10,
            mysqlMinorVersion: 11,
            mysqlReleaseVersion: 8
        )

        XCTAssertEqual(url?.absoluteString, "https://mariadb.com/kb/en/json-table/")
    }

    func testMariaDBOnlineHelpURLSanitizesTopicPunctuation() {
        let url = SAHelpViewerOnlineURLBuilder.mariaDBOnlineHelpURL(forTopic: "JSON_TABLE()!")

        XCTAssertEqual(url?.absoluteString, "https://mariadb.com/kb/en/json_table/")
    }

    func testMariaDBOnlineHelpURLFallsBackToSearchForPunctuationOnlyTopics() {
        let url = SAHelpViewerOnlineURLBuilder.mariaDBOnlineHelpURL(forTopic: "???")

        XCTAssertEqual(url?.absoluteString, "https://mariadb.com/docs?q=%3F%3F%3F")
    }

    func testMariaDBOnlineHelpURLFallsBackToServerDocsForBlankTopics() {
        let url = SAHelpViewerOnlineURLBuilder.mariaDBOnlineHelpURL(forTopic: " \n\t ")

        XCTAssertEqual(url?.absoluteString, "https://mariadb.com/kb/en/server/")
    }

    func testMariaDBRoutingWinsOverMySQLVersionNumbers() {
        let url = SAHelpViewerOnlineURLBuilder.onlineHelpURL(
            forTopic: "SELECT",
            serverVersionString: "10.11.8-MariaDB",
            mysqlMajorVersion: 10,
            mysqlMinorVersion: 11,
            mysqlReleaseVersion: 8
        )

        XCTAssertEqual(url?.absoluteString, "https://mariadb.com/kb/en/select/")
    }
}
