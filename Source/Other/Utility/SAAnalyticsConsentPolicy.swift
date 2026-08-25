//
//  SAAnalyticsConsentPolicy.swift
//  Sequel Ace
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import Foundation

/// Keeps third-party analytics services dormant until the user opts in.
@objc final class SAAnalyticsConsentPolicy: NSObject {
    @objc(shouldConfigureFirebaseWithAnalyticsEnabled:)
    static func shouldConfigureFirebase(analyticsEnabled: Bool) -> Bool {
        analyticsEnabled
    }
}
