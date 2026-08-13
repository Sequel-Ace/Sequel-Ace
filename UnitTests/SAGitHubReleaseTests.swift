//
//  SAGitHubReleaseTests.swift
//  Unit Tests
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import XCTest

final class SAGitHubReleaseTests: XCTestCase {
    func testDecodesAutomatedAndHistoricalReleases() throws {
        let data = Data(
            #"""
            [
              {
                "tag_name": "production/5.4.0-20109",
                "name": "5.4.0 (20109) - Release Candidate 2",
                "html_url": "https://github.com/Sequel-Ace/Sequel-Ace/releases/tag/production%2F5.4.0-20109",
                "draft": false,
                "prerelease": true,
                "created_at": "2026-08-12T05:49:29Z",
                "published_at": "2026-08-12T05:49:29Z",
                "author": {
                  "login": "sequel-ace-release-automation[bot]",
                  "type": "Bot"
                },
                "assets": [
                  {
                    "size": 21949789,
                    "browser_download_url": "https://example.com/Sequel-Ace-5.4.0.zip",
                    "label": "",
                    "digest": "sha256:example",
                    "uploader": {
                      "login": "github-actions[bot]",
                      "type": "Bot"
                    }
                  }
                ]
              },
              {
                "tag_name": "2.3.1",
                "name": "2.3.1",
                "html_url": "https://github.com/Sequel-Ace/Sequel-Ace/releases/tag/2.3.1",
                "draft": false,
                "prerelease": false,
                "created_at": "2020-11-20T07:59:27Z",
                "published_at": "2020-11-20T07:59:27Z",
                "author": {
                  "login": "Jason-Morcos",
                  "type": "User"
                },
                "assets": [
                  {
                    "size": 123,
                    "browser_download_url": "https://example.com/Sequel-Ace-2.3.1.zip",
                    "label": null,
                    "uploader": {
                      "login": "Jason-Morcos",
                      "type": "User"
                    }
                  }
                ]
              }
            ]
            """#.utf8
        )

        let releases = try SAGitHubRelease.decodeList(from: data).sorted(by: >)

        XCTAssertEqual(releases.count, 2)
        XCTAssertEqual(releases[0].tagName, "production/5.4.0-20109")
        XCTAssertEqual(releases[0].assets.first?.size, 21_949_789)
        XCTAssertEqual(releases[1].tagName, "2.3.1")
        XCTAssertEqual(releases[1].assets.first?.browserDownloadURL, "https://example.com/Sequel-Ace-2.3.1.zip")
    }

    func testUsesTagAndCreationDateWhenOptionalReleaseMetadataIsNull() throws {
        let data = Data(
            #"""
            [
              {
                "tag_name": "production/5.4.0-20110",
                "name": null,
                "html_url": "https://example.com/release",
                "draft": true,
                "prerelease": false,
                "created_at": "2026-08-13T00:00:00Z",
                "published_at": null,
                "assets": []
              }
            ]
            """#.utf8
        )

        let release = try XCTUnwrap(SAGitHubRelease.decodeList(from: data).first)

        XCTAssertEqual(release.name, release.tagName)
        XCTAssertEqual(release.publishedAt.timeIntervalSince1970, 1_786_579_200)
        XCTAssertTrue(release.matchesInstalledBuild(named: "5.4.0 (20110)"))
        XCTAssertFalse(release.matchesInstalledBuild(named: "5.4.0 (20111)"))
    }

    func testBackgroundAndEphemeralFailuresAreSilent() {
        XCTAssertFalse(SAGitHubReleaseErrorPolicy.shouldPresentError(isUserInitiated: false,
                                                                     statusCode: 404,
                                                                     underlyingError: nil))
        XCTAssertFalse(SAGitHubReleaseErrorPolicy.shouldPresentError(isUserInitiated: true,
                                                                     statusCode: 403,
                                                                     underlyingError: nil))
        XCTAssertFalse(SAGitHubReleaseErrorPolicy.shouldPresentError(isUserInitiated: true,
                                                                     statusCode: 429,
                                                                     underlyingError: nil))
        XCTAssertFalse(SAGitHubReleaseErrorPolicy.shouldPresentError(isUserInitiated: true,
                                                                     statusCode: 503,
                                                                     underlyingError: nil))
        XCTAssertFalse(SAGitHubReleaseErrorPolicy.shouldPresentError(isUserInitiated: true,
                                                                     statusCode: nil,
                                                                     underlyingError: URLError(.networkConnectionLost)))
        XCTAssertFalse(SAGitHubReleaseErrorPolicy.shouldPresentError(
            isUserInitiated: true,
            statusCode: nil,
            underlyingError: NSError(domain: NSURLErrorDomain, code: URLError.Code.timedOut.rawValue)
        ))
    }

    func testUserInitiatedPermanentFailureRemainsVisible() {
        XCTAssertTrue(SAGitHubReleaseErrorPolicy.shouldPresentError(isUserInitiated: true,
                                                                    statusCode: 404,
                                                                    underlyingError: nil))
        XCTAssertTrue(SAGitHubReleaseErrorPolicy.shouldPresentError(isUserInitiated: true,
                                                                    statusCode: nil,
                                                                    underlyingError: NSError(domain: "Decode", code: 1)))
    }
}
