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
                Analytics.setConsent([
                    .adPersonalization: .denied,
                    .adStorage: .denied,
                    .adUserData: .denied,
                    .analyticsStorage: .denied,
                ])
                Analytics.setUserProperty(nil, forName: "distribution")
                Analytics.setUserProperty(nil, forName: "release_channel")

                let crashlytics = Crashlytics.crashlytics()
                crashlytics.setCrashlyticsCollectionEnabled(false)
                crashlytics.deleteUnsentReports()
            }
            return
        }

        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }

        // This app uses Firebase only for first-party product analytics and
        // diagnostics. Advertising consent remains denied even after opt-in.
        Analytics.setConsent([
            .adPersonalization: .denied,
            .adStorage: .denied,
            .adUserData: .denied,
            .analyticsStorage: .granted,
        ])
        Analytics.setAnalyticsCollectionEnabled(true)

        let receiptURL = Bundle.main.appStoreReceiptURL
        let context = analyticsInstallationContext(
            isAppStoreInstall: Bundle.main.isMASVersion,
            isTestFlight: receiptURL?.lastPathComponent == "sandboxReceipt",
            isBetaBuild: Bundle.main.isSnapshotBuild
        )
        Analytics.setUserProperty(context.distribution, forName: "distribution")
        Analytics.setUserProperty(context.releaseChannel, forName: "release_channel")

        let crashlytics = Crashlytics.crashlytics()
        crashlytics.setCustomValue(context.distribution, forKey: "distribution")
        crashlytics.setCustomValue(context.releaseChannel, forKey: "release_channel")
        crashlytics.setCrashlyticsCollectionEnabled(true)
    }
}
