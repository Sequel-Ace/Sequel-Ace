//
//  SAAnalyticsConsentPolicy.swift
//  Sequel Ace
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import AppKit

/// Keeps third-party analytics services dormant until the user opts in.
@objc final class SAAnalyticsConsentPolicy: NSObject {
    static let analyticsPreferenceKey = "SaveApplicationUsageAnalytics"

    @objc(shouldConfigureFirebaseWithAnalyticsEnabled:)
    static func shouldConfigureFirebase(analyticsEnabled: Bool) -> Bool {
        analyticsEnabled
    }

    /// Prompts only when the registered default is the sole source of the preference.
    /// Existing explicit opt-in and opt-out choices are both preserved.
    @objc(requestConsentIfNeeded)
    static func requestConsentIfNeeded() {
        let defaults = UserDefaults.standard
        guard !hasRecordedAnalyticsChoice(
            in: defaults,
            applicationIdentifier: Bundle.main.bundleIdentifier
        ) else {
            return
        }

        let analyticsEnabled = requestAnalyticsConsent()
        defaults.set(analyticsEnabled, forKey: analyticsPreferenceKey)
    }

    static func hasRecordedAnalyticsChoice(
        in defaults: UserDefaults,
        applicationIdentifier: String?
    ) -> Bool {
        if defaults.objectIsForced(forKey: analyticsPreferenceKey) {
            return true
        }

        guard let applicationIdentifier else {
            return false
        }

        return defaults.persistentDomain(forName: applicationIdentifier)?[analyticsPreferenceKey] != nil
    }

    private static func requestAnalyticsConsent() -> Bool {
        assert(Thread.isMainThread)

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = NSLocalizedString(
            "Help Improve Sequel Ace",
            comment: "analytics consent dialog title"
        )
        alert.informativeText = NSLocalizedString(
            "Allow Sequel Ace to send device and app information, usage analytics, and crash reports to Google Firebase?\n\nThis helps the developers understand how Sequel Ace is used and diagnose problems. Collection starts only if you choose Share Analytics, and you can change your choice anytime in Preferences.",
            comment: "analytics consent dialog message"
        )

        // The positive action is the default button to encourage opt-in, while
        // collection remains off until the user explicitly chooses it.
        let shareButton = alert.addButton(withTitle: NSLocalizedString(
            "Share Analytics",
            comment: "analytics consent allow button"
        ))
        shareButton.keyEquivalent = "\r"

        let declineButton = alert.addButton(withTitle: NSLocalizedString(
            "Don't Share",
            comment: "analytics consent deny button"
        ))
        declineButton.keyEquivalent = "\u{1b}"

        return alert.runModal() == .alertFirstButtonReturn
    }
}
