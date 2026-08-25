//
//  SAAnalyticsConsentPolicyTests.swift
//  Unit Tests
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import XCTest

final class SAAnalyticsConsentPolicyTests: XCTestCase {
    func testFirebaseConfigurationRequiresAnalyticsConsent() {
        XCTAssertFalse(SAAnalyticsConsentPolicy.shouldConfigureFirebase(analyticsEnabled: false))
        XCTAssertTrue(SAAnalyticsConsentPolicy.shouldConfigureFirebase(analyticsEnabled: true))
    }
}
