//
//  SAGitHubReleaseTests.swift
//  Unit Tests
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import XCTest

final class SAGitHubReleaseTests: XCTestCase {
    func testAutomaticAndRetryChecksRequirePreferenceWhileManualChecksDoNot() {
        XCTAssertFalse(SAGitHubReleaseCheckPolicy.shouldCheck(isUserInitiated: false,
                                                              automaticChecksEnabled: false,
                                                              isAppStoreInstall: false))
        XCTAssertTrue(SAGitHubReleaseCheckPolicy.shouldCheck(isUserInitiated: false,
                                                             automaticChecksEnabled: true,
                                                             isAppStoreInstall: false))
        XCTAssertTrue(SAGitHubReleaseCheckPolicy.shouldCheck(isUserInitiated: true,
                                                             automaticChecksEnabled: false,
                                                             isAppStoreInstall: false))
    }

    func testAppStoreInstallNeverUsesGitHubUpdater() {
        XCTAssertFalse(SAGitHubReleaseCheckPolicy.shouldCheck(isUserInitiated: false,
                                                              automaticChecksEnabled: true,
                                                              isAppStoreInstall: true))
        XCTAssertFalse(SAGitHubReleaseCheckPolicy.shouldCheck(isUserInitiated: true,
                                                              automaticChecksEnabled: false,
                                                              isAppStoreInstall: true))
    }

    func testAutomaticRolloutMatchesAppleSevenDayPercentages() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let oneDay: TimeInterval = 24 * 60 * 60

        XCTAssertEqual(SAGitHubReleaseRolloutPolicy.rolloutPercentage(
            at: start.addingTimeInterval(-1),
            startedAt: start
        ), 0)
        for (dayIndex, percentage) in [1, 2, 5, 10, 20, 50, 100].enumerated() {
            XCTAssertEqual(SAGitHubReleaseRolloutPolicy.rolloutPercentage(
                at: start.addingTimeInterval(Double(dayIndex) * oneDay),
                startedAt: start
            ), percentage)
        }
        XCTAssertEqual(SAGitHubReleaseRolloutPolicy.rolloutPercentage(
            at: start.addingTimeInterval(30 * oneDay),
            startedAt: start
        ), 100)
    }

    func testAutomaticRolloutUsesStableReleaseSpecificCohorts() {
        let seed = "4C55C2A6-C1E3-42AB-BCB1-30F0A2B989C1"
        let firstBucket = SAGitHubReleaseRolloutPolicy.cohortBucket(
            installationSeed: seed,
            releaseTag: "production/6.0.0-20112"
        )

        XCTAssertEqual(firstBucket, 4_032)
        XCTAssertEqual(SAGitHubReleaseRolloutPolicy.cohortBucket(
            installationSeed: seed,
            releaseTag: "production/6.0.0-20112"
        ), 4_032)
        XCTAssertEqual(SAGitHubReleaseRolloutPolicy.cohortBucket(
            installationSeed: seed,
            releaseTag: "production/6.0.1-20113"
        ), 6_416)
        XCTAssertTrue((0..<10_000).contains(firstBucket))
    }

    func testManualChecksBypassPhasingButAutomaticChecksRespectCohort() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let releaseTag = "production/6.0.0-20112"
        let earlySeed = "00000000-0000-4000-8000-000000000076"
        let lateSeed = "00000000-0000-4000-8000-000000000000"

        XCTAssertTrue(SAGitHubReleaseRolloutPolicy.shouldOffer(
            releaseTag: releaseTag,
            rolloutStartedAt: start,
            at: start,
            installationSeed: nil,
            isUserInitiated: true
        ))
        XCTAssertFalse(SAGitHubReleaseRolloutPolicy.shouldOffer(
            releaseTag: releaseTag,
            rolloutStartedAt: start,
            at: start,
            installationSeed: lateSeed,
            isUserInitiated: false
        ))
        XCTAssertTrue(SAGitHubReleaseRolloutPolicy.shouldOffer(
            releaseTag: releaseTag,
            rolloutStartedAt: start,
            at: start,
            installationSeed: earlySeed,
            isUserInitiated: false
        ))
        XCTAssertTrue(SAGitHubReleaseRolloutPolicy.shouldOffer(
            releaseTag: releaseTag,
            rolloutStartedAt: start,
            at: start.addingTimeInterval(6 * 24 * 60 * 60),
            installationSeed: lateSeed,
            isUserInitiated: false
        ))
    }

    func testRolloutSeedPersistsLocally() throws {
        let suiteName = "SAGitHubReleaseRolloutPolicyTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let firstSeed = SAGitHubReleaseRolloutPolicy.installationSeed(in: defaults)
        let secondSeed = SAGitHubReleaseRolloutPolicy.installationSeed(in: defaults)

        XCTAssertNotNil(UUID(uuidString: firstSeed))
        XCTAssertEqual(firstSeed, secondSeed)
        XCTAssertEqual(defaults.string(
            forKey: SAGitHubReleaseRolloutPolicy.installationSeedPreferenceKey
        ), firstSeed)
    }

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
                    "name": "Sequel-Ace-5.4.0.zip",
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
                    "name": "Sequel-Ace-2.3.1-release.zip",
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
        XCTAssertEqual(releases[0].assets.first?.name, "Sequel-Ace-5.4.0.zip")
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
        XCTAssertFalse(release.matchesInstalledBuild(named: "5.4.0 (2011)"))
        XCTAssertNil(release.compatibleAppZip(for: .production))
        XCTAssertNil(release.compatibleAppZip(for: .beta))
    }

    func testSelectsAppZipMatchingInstalledVariant() throws {
        let data = Data(
            #"""
            [
              {
                "tag_name": "beta/5.4.0-20110",
                "name": "5.4.0 (20110) Beta 3",
                "html_url": "https://example.com/beta-release",
                "draft": false,
                "prerelease": true,
                "created_at": "2026-08-13T00:00:00Z",
                "published_at": "2026-08-13T00:00:00Z",
                "assets": [
                  {
                    "name": "Sequel-Ace-5.4.0-beta3-alpha.zip",
                    "size": 200,
                    "browser_download_url": "https://example.com/beta.zip"
                  },
                  {
                    "name": "Sequel-Ace-5.4.0-beta3.zip",
                    "size": 100,
                    "browser_download_url": "https://example.com/production.zip"
                  },
                  {
                    "name": "checksums.zip",
                    "size": 10,
                    "browser_download_url": "https://example.com/checksums.zip"
                  }
                ]
              },
              {
                "tag_name": "production/5.5.0-20111",
                "name": "5.5.0 (20111)",
                "html_url": "https://example.com/mixed-release",
                "draft": false,
                "prerelease": false,
                "created_at": "2026-08-14T00:00:00Z",
                "published_at": "2026-08-14T00:00:00Z",
                "assets": [
                  {
                    "name": "Sequel-Ace-5.5.0.zip",
                    "size": 100,
                    "browser_download_url": "https://example.com/stable.zip"
                  },
                  {
                    "name": "Sequel-Ace-5.5.0-beta.zip",
                    "size": 200,
                    "browser_download_url": "https://example.com/explicit-beta.zip"
                  }
                ]
              }
            ]
            """#.utf8
        )

        let releases = try SAGitHubRelease.decodeList(from: data)
        let canonicalBetaRelease = try XCTUnwrap(releases.first)
        let explicitlyMixedRelease = try XCTUnwrap(releases.last)

        XCTAssertEqual(canonicalBetaRelease.compatibleAppZip(for: .production)?.name,
                       "Sequel-Ace-5.4.0-beta3.zip")
        XCTAssertEqual(canonicalBetaRelease.compatibleAppZip(for: .beta)?.name,
                       "Sequel-Ace-5.4.0-beta3-alpha.zip")
        XCTAssertTrue(canonicalBetaRelease.matchesInstalledBuild(named: "5.4.0 (20110)"))
        XCTAssertTrue(canonicalBetaRelease.matchesInstalledBuild(named: "5.4.0 (30576)",
                                                                 releaseTag: "beta/5.4.0-20110"))
        XCTAssertFalse(canonicalBetaRelease.matchesInstalledBuild(named: "5.4.0 (30576)",
                                                                  releaseTag: "beta/5.4.0-20111"))
        XCTAssertEqual(explicitlyMixedRelease.compatibleAppZip(for: .production)?.name,
                       "Sequel-Ace-5.5.0.zip")
        XCTAssertEqual(explicitlyMixedRelease.compatibleAppZip(for: .beta)?.name,
                       "Sequel-Ace-5.5.0-beta.zip")
    }

    func testCanonicalBetaSelectsAvailableVariantWhileLegacyBetaAllowsOne() throws {
        let data = Data(
            #"""
            [
              {
                "tag_name": "beta/5.4.0-20110",
                "name": "A title chosen by a release admin",
                "html_url": "https://example.com/canonical-beta",
                "draft": false,
                "prerelease": true,
                "created_at": "2026-08-13T00:00:00Z",
                "published_at": "2026-08-13T00:00:00Z",
                "assets": [
                  {
                    "name": "Sequel-Ace-5.4.0-beta1.zip",
                    "size": 100,
                    "browser_download_url": "https://example.com/production.zip"
                  }
                ]
              },
              {
                "tag_name": "beta/5.3.0-20101",
                "name": "5.3.0 (20101) Beta 1",
                "html_url": "https://example.com/legacy-beta",
                "draft": false,
                "prerelease": true,
                "created_at": "2026-06-08T00:00:00Z",
                "published_at": "2026-06-08T00:00:00Z",
                "assets": [
                  {
                    "name": "Sequel-Ace-5.3.0-beta1.zip",
                    "size": 100,
                    "browser_download_url": "https://example.com/legacy-beta.zip"
                  }
                ]
              },
              {
                "tag_name": "beta/5.4.1-20111",
                "name": "Another title chosen by a release bot",
                "html_url": "https://example.com/canonical-alpha",
                "draft": false,
                "prerelease": true,
                "created_at": "2026-08-14T00:00:00Z",
                "published_at": "2026-08-14T00:00:00Z",
                "assets": [
                  {
                    "name": "Sequel-Ace-5.4.1-beta2-alpha.zip",
                    "size": 100,
                    "browser_download_url": "https://example.com/alpha.zip"
                  }
                ]
              }
            ]
            """#.utf8
        )

        let releases = try SAGitHubRelease.decodeList(from: data)
        let partiallyUploadedCanonicalBeta = try XCTUnwrap(releases.first)
        let legacyBeta = releases[1]
        let alphaOnlyCanonicalBeta = try XCTUnwrap(releases.last)

        XCTAssertEqual(partiallyUploadedCanonicalBeta.compatibleAppZip(for: .production)?.name,
                       "Sequel-Ace-5.4.0-beta1.zip")
        XCTAssertNil(partiallyUploadedCanonicalBeta.compatibleAppZip(for: .beta))
        XCTAssertNil(legacyBeta.compatibleAppZip(for: .production))
        XCTAssertEqual(legacyBeta.compatibleAppZip(for: .beta)?.name,
                       "Sequel-Ace-5.3.0-beta1.zip")
        XCTAssertNil(alphaOnlyCanonicalBeta.compatibleAppZip(for: .production))
        XCTAssertEqual(alphaOnlyCanonicalBeta.compatibleAppZip(for: .beta)?.name,
                       "Sequel-Ace-5.4.1-beta2-alpha.zip")
    }

    func testReleaseSettlesAfterNewestAssetChange() throws {
        let data = Data(
            #"""
            [
              {
                "tag_name": "production/5.5.0-20111",
                "name": "5.5.0 (20111)",
                "html_url": "https://example.com/release",
                "draft": false,
                "prerelease": false,
                "created_at": "2026-08-13T00:00:00Z",
                "published_at": "2026-08-13T00:00:00Z",
                "assets": [
                  {
                    "name": "Sequel-Ace-5.5.0.zip",
                    "size": 100,
                    "browser_download_url": "https://example.com/release.zip",
                    "created_at": "2026-08-13T01:00:00Z",
                    "updated_at": "2026-08-13T01:05:00Z"
                  }
                ]
              }
            ]
            """#.utf8
        )
        let release = try XCTUnwrap(SAGitHubRelease.decodeList(from: data).first)
        let calendar = Calendar(identifier: .gregorian)
        let newestAssetChange = try XCTUnwrap(calendar.date(from: DateComponents(
            timeZone: TimeZone(secondsFromGMT: 0),
            year: 2026,
            month: 8,
            day: 13,
            hour: 1,
            minute: 5
        )))

        XCTAssertFalse(release.isSettled(at: newestAssetChange.addingTimeInterval(
            SAGitHubRelease.settlingInterval - 1
        )))
        XCTAssertEqual(release.settlingTimeRemaining(at: newestAssetChange.addingTimeInterval(
            SAGitHubRelease.settlingInterval - 1
        )), 1)
        XCTAssertTrue(release.isSettled(at: newestAssetChange.addingTimeInterval(
            SAGitHubRelease.settlingInterval
        )))
        XCTAssertNil(release.settlingTimeRemaining(at: newestAssetChange.addingTimeInterval(
            SAGitHubRelease.settlingInterval
        )))
        XCTAssertEqual(
            release.phasedRolloutStartedAt,
            newestAssetChange.addingTimeInterval(SAGitHubRelease.settlingInterval)
        )
    }

    func testSettlingPolicyRetriesOnlyForTheNewestCandidateUpdate() throws {
        let data = Data(
            #"""
            [
              {
                "tag_name": "production/5.4.0-20109",
                "name": "5.4.0 (20109)",
                "html_url": "https://example.com/current",
                "draft": false,
                "prerelease": false,
                "published_at": "2026-08-13T01:00:00Z",
                "assets": [
                  {
                    "name": "Sequel-Ace-5.4.0.zip",
                    "size": 100,
                    "browser_download_url": "https://example.com/current.zip"
                  }
                ]
              },
              {
                "tag_name": "production/5.5.0-20111",
                "name": "5.5.0 (20111)",
                "html_url": "https://example.com/update",
                "draft": false,
                "prerelease": false,
                "published_at": "2026-08-13T01:00:00Z",
                "assets": [
                  {
                    "name": "Sequel-Ace-5.5.0.zip",
                    "size": 100,
                    "browser_download_url": "https://example.com/update.zip"
                  }
                ]
              }
            ]
            """#.utf8
        )
        let releases = try SAGitHubRelease.decodeList(from: data)
        let currentRelease = releases[0]
        let updateRelease = releases[1]
        let publishedAt = updateRelease.publishedAt

        XCTAssertNotEqual(currentRelease, updateRelease)
        XCTAssertTrue(updateRelease > currentRelease)
        XCTAssertEqual(SAGitHubReleaseSettlingPolicy.retryDelay(
            at: publishedAt,
            currentRelease: currentRelease,
            candidateReleases: [currentRelease, updateRelease]
        ), SAGitHubRelease.settlingInterval)
        XCTAssertNil(SAGitHubReleaseSettlingPolicy.retryDelay(
            at: publishedAt.addingTimeInterval(SAGitHubRelease.settlingInterval),
            currentRelease: currentRelease,
            candidateReleases: [currentRelease, updateRelease]
        ))
        XCTAssertNil(SAGitHubReleaseSettlingPolicy.retryDelay(
            at: publishedAt,
            currentRelease: currentRelease,
            candidateReleases: [currentRelease]
        ))
    }

    func testSettlingRetryPreservesTheInitiatingCheckAuthorization() {
        var receivedValues: [(name: String, tag: String?, isUserInitiated: Bool)] = []
        let manualRetry = SAGitHubReleaseSettlingPolicy.retryOperation(
            installedBuildName: "5.5.0 (20111)",
            installedReleaseTag: "production/5.5.0-20111",
            isUserInitiated: true
        ) { name, tag, isUserInitiated in
            receivedValues.append((name, tag, isUserInitiated))
        }
        let automaticRetry = SAGitHubReleaseSettlingPolicy.retryOperation(
            installedBuildName: "5.5.0 (20111)",
            installedReleaseTag: nil,
            isUserInitiated: false
        ) { name, tag, isUserInitiated in
            receivedValues.append((name, tag, isUserInitiated))
        }

        manualRetry()
        automaticRetry()

        XCTAssertEqual(receivedValues.map { $0.name }, ["5.5.0 (20111)", "5.5.0 (20111)"])
        XCTAssertEqual(receivedValues.map { $0.tag }, ["production/5.5.0-20111", nil])
        XCTAssertEqual(receivedValues.map { $0.isUserInitiated }, [true, false])
    }

    func testUserInitiatedReleaseCheckTakesPriorityOverBackgroundChecks() throws {
        var tracker = SAGitHubReleaseCheckTracker()
        let backgroundCheck = try XCTUnwrap(tracker.begin(isUserInitiated: false))
        let userCheck = try XCTUnwrap(tracker.begin(isUserInitiated: true))

        XCTAssertFalse(tracker.isCurrent(backgroundCheck))
        XCTAssertTrue(tracker.isCurrent(userCheck))
        XCTAssertNil(tracker.begin(isUserInitiated: false))
        XCTAssertTrue(tracker.isCurrent(userCheck))

        tracker.finish(userCheck)
        let nextBackgroundCheck = try XCTUnwrap(tracker.begin(isUserInitiated: false))

        XCTAssertTrue(tracker.isCurrent(nextBackgroundCheck))
    }

    func testReleaseTagIdentityRequiresCanonicalGrammar() throws {
        XCTAssertEqual(SAGitHubReleaseTagIdentity("production/5.4.0-20109")?.version, "5.4.0")
        XCTAssertEqual(SAGitHubReleaseTagIdentity("beta/5.4.0-20110")?.build, 20_110)

        for value in [
            "beta/foo-20110",
            "beta/5.4-20110",
            "beta/5.4.0-rc1-20110",
            "beta/5.4.0-020110",
            "beta/5.4.0-0",
            "nightly/5.4.0-20110"
        ] {
            XCTAssertNil(SAGitHubReleaseTagIdentity(value), value)
        }

        let invalidRelease = try XCTUnwrap(SAGitHubRelease.decodeList(from: Data(
            #"""
            [{
              "tag_name": "beta/foo-20110",
              "name": "Out-of-contract beta",
              "html_url": "https://example.com/invalid",
              "draft": false,
              "prerelease": true,
              "published_at": "2026-08-13T00:00:00Z",
              "assets": [{
                "name": "Sequel-Ace-foo-beta1-alpha.zip",
                "size": 100,
                "browser_download_url": "https://example.com/invalid.zip"
              }]
            }]
            """#.utf8
        )).first)
        XCTAssertNil(invalidRelease.compatibleAppZip(for: .beta))
    }

    func testMissingReleaseStateDefaultsFailClosed() throws {
        let data = Data(
            #"""
            [
              {
                "tag_name": "production/5.5.0-20111",
                "name": "5.5.0 (20111)",
                "html_url": "https://example.com/missing-state",
                "created_at": "2026-08-14T00:00:00Z",
                "published_at": "2026-08-14T00:00:00Z",
                "assets": []
              },
              {
                "tag_name": "production/5.5.0-20112",
                "name": "5.5.0 (20112)",
                "html_url": "https://example.com/null-state",
                "draft": null,
                "prerelease": null,
                "created_at": "2026-08-15T00:00:00Z",
                "published_at": "2026-08-15T00:00:00Z",
                "assets": []
              }
            ]
            """#.utf8
        )

        for release in try SAGitHubRelease.decodeList(from: data) {
            XCTAssertTrue(release.draft)
            XCTAssertTrue(release.prerelease)
        }
    }

    func testPaginationContinuesPastThirtyReleasesUntilInstalledTagIsFound() throws {
        let fixture: [[String: Any]] = (1...31).map { index in
            let isInstalledRelease = index == 31
            return [
                "tag_name": isInstalledRelease ? "production/2.0.0-1000" : "production/5.0.\(index)-\(20000 + index)",
                "name": isInstalledRelease ? "2.0.0 (1000)" : "5.0.\(index) (\(20000 + index))",
                "html_url": "https://example.com/release-\(index)",
                "draft": false,
                "prerelease": false,
                "created_at": "2026-08-13T00:00:00Z",
                "published_at": "2026-08-13T00:00:00Z",
                "assets": []
            ]
        }
        let releases = try SAGitHubRelease.decodeList(from: JSONSerialization.data(withJSONObject: fixture))
        let firstPage = Array(releases.prefix(30))
        let linkHeader = "<https://api.github.com/repos/Sequel-Ace/Sequel-Ace/releases?per_page=100&page=2>; rel=\"next\", <https://api.github.com/repos/Sequel-Ace/Sequel-Ace/releases?per_page=100&page=2>; rel=\"last\""
        let firstPageURL = try XCTUnwrap(URL(
            string: "https://api.github.com/repos/Sequel-Ace/Sequel-Ace/releases?per_page=100&page=1"
        ))

        XCTAssertEqual(
            SAGitHubReleasePagination.nextPageURL(from: linkHeader,
                                                  pagesFetched: 1,
                                                  visitedPageURLs: [firstPageURL],
                                                  releases: firstPage,
                                                  installedBuildName: "2.0.0 (1000)",
                                                  installedReleaseTag: "production/2.0.0-1000")?.absoluteString,
            "https://api.github.com/repos/Sequel-Ace/Sequel-Ace/releases?per_page=100&page=2"
        )
        XCTAssertNil(SAGitHubReleasePagination.nextPageURL(from: linkHeader,
                                                           pagesFetched: 2,
                                                           visitedPageURLs: [],
                                                           releases: releases,
                                                           installedBuildName: "2.0.0 (9999)",
                                                           installedReleaseTag: "production/2.0.0-1000"))

        let cyclicLinkHeader = "<\(firstPageURL.absoluteString)>; rel=\"next\""
        XCTAssertNil(SAGitHubReleasePagination.nextPageURL(from: cyclicLinkHeader,
                                                           pagesFetched: 1,
                                                           visitedPageURLs: [firstPageURL],
                                                           releases: firstPage,
                                                           installedBuildName: "2.0.0 (1000)",
                                                           installedReleaseTag: "production/2.0.0-1000"))
        XCTAssertNil(SAGitHubReleasePagination.nextPageURL(from: linkHeader,
                                                           pagesFetched: SAGitHubReleasePagination.maximumPageCount,
                                                           visitedPageURLs: [],
                                                           releases: firstPage,
                                                           installedBuildName: "2.0.0 (1000)",
                                                           installedReleaseTag: "production/2.0.0-1000"))
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
