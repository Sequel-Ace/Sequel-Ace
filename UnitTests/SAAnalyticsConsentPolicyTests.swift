//
//  SAAnalyticsConsentPolicyTests.swift
//  Unit Tests
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import XCTest

final class SAAnalyticsConsentPolicyTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "SAAnalyticsConsentPolicyTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testFirebaseConfigurationRequiresAnalyticsConsent() {
        XCTAssertFalse(SAAnalyticsConsentPolicy.shouldConfigureFirebase(analyticsEnabled: false))
        XCTAssertTrue(SAAnalyticsConsentPolicy.shouldConfigureFirebase(analyticsEnabled: true))
    }

    func testRegisteredDefaultDoesNotCountAsRecordedConsentChoice() {
        defaults.register(defaults: ["SaveApplicationUsageAnalytics": false])

        XCTAssertFalse(SAAnalyticsConsentPolicy.hasRecordedAnalyticsChoice(
            in: defaults,
            applicationIdentifier: suiteName
        ))
    }

    func testExplicitOptInCountsAsRecordedConsentChoice() {
        defaults.set(true, forKey: "SaveApplicationUsageAnalytics")

        XCTAssertTrue(SAAnalyticsConsentPolicy.hasRecordedAnalyticsChoice(
            in: defaults,
            applicationIdentifier: suiteName
        ))
    }

    func testExplicitOptOutCountsAsRecordedConsentChoice() {
        defaults.set(false, forKey: "SaveApplicationUsageAnalytics")

        XCTAssertTrue(SAAnalyticsConsentPolicy.hasRecordedAnalyticsChoice(
            in: defaults,
            applicationIdentifier: suiteName
        ))
    }
}
