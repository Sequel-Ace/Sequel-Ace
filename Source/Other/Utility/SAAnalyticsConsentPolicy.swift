//
//  SAAnalyticsConsentPolicy.swift
//  Sequel Ace
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import AppKit

struct SAAnalyticsInstallationContext: Equatable {
    let distribution: String
    let releaseChannel: String
}

/// Keeps third-party analytics services dormant until the user opts in.
@objc final class SAAnalyticsConsentPolicy: NSObject {
    static let analyticsPreferenceKey = "SaveApplicationUsageAnalytics"
    static let privacyPolicyURL = URL(string: "https://moballo.com/privacy-policy/")!

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

    static func analyticsInstallationContext(
        isAppStoreInstall: Bool,
        isTestFlight: Bool,
        isBetaBuild: Bool
    ) -> SAAnalyticsInstallationContext {
        let distribution: String
        if isAppStoreInstall {
            distribution = isTestFlight ? "testflight" : "app_store"
        } else {
            distribution = "direct"
        }

        return SAAnalyticsInstallationContext(
            distribution: distribution,
            releaseChannel: isBetaBuild ? "beta" : "production"
        )
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
            "Allow Sequel Ace to send an app installation identifier, app version, macOS and device details, approximate region, usage analytics, and crash and diagnostic reports to Google Firebase?\n\nThe developers use this data to understand feature adoption and diagnose problems. It is not used for advertising or to track you across other companies' apps or websites. Collection starts only if you choose Share Analytics, and you can change your choice anytime in Preferences.",
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

        alert.addButton(withTitle: NSLocalizedString(
            "Privacy Policy…",
            comment: "analytics consent privacy policy button"
        ))

        while true {
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                return true
            case .alertThirdButtonReturn:
                NSWorkspace.shared.open(privacyPolicyURL)
            default:
                return false
            }
        }
    }
}
