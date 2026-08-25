//
//  SAAnalyticsConsentPolicy+Firebase.swift
//  Sequel Ace
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import FirebaseAnalytics
import FirebaseCore
import FirebaseCrashlytics
import Foundation

@MainActor
private enum SAFirebaseConsentState {
    static var appliedConsent: Bool?
}

extension SAAnalyticsConsentPolicy {
    /// Applies the persisted choice without configuring Firebase for opted-out users.
    @MainActor
    @objc(applyAnalyticsConsent)
    static func applyAnalyticsConsent() {
        let analyticsEnabled = UserDefaults.standard.bool(forKey: analyticsPreferenceKey)
        guard SAFirebaseConsentState.appliedConsent != analyticsEnabled else {
            return
        }

        SAFirebaseConsentState.appliedConsent = analyticsEnabled

        guard shouldConfigureFirebase(analyticsEnabled: analyticsEnabled) else {
            if FirebaseApp.app() != nil {
                Analytics.setAnalyticsCollectionEnabled(false)
                Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(false)
            }
            return
        }

        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
        Analytics.setAnalyticsCollectionEnabled(true)
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(true)
    }
}
