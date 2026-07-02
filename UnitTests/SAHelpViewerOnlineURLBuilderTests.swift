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
