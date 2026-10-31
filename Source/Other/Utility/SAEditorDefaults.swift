//
//  SAEditorDefaults.swift
//  Sequel Ace
//
//  The query editor's defaults: follow the system appearance with the bundled
//  Sequel Ace Light / Sequel Ace Dark themes, and SF Mono 13 as the editor
//  font; plus the one-time updates that bring existing users' settings onto
//  them. Shared with the Unit Tests target.
//

import AppKit

@objc final class SAEditorDefaults: NSObject {

    /// Keep in sync with SPCustomQueryEditorFont in SPConstants.m.
    static let fontKey = "CustomQueryEditorFont"
    /// Set once the one-time font update has run.
    static let fontUpdatedKey = "EditorFontUpdatedToSystemMonospace"
    /// Set once the one-time theme-matching upgrade has run.
    static let themeMatchingUpgradeCheckedKey = "EditorThemeMatchingUpgradeChecked"

    static var defaultFont: NSFont { .monospacedSystemFont(ofSize: 13, weight: .regular) }

    /// The editor font's Reset (SPEditorPreferencePane -resetSystemFont:): back to the default editor font,
    /// SF Mono 13, rather than the proportional system font.
    @objc(resetEditorFontIn:)
    static func resetEditorFont(in defaults: UserDefaults) {
        guard let data = SAArchiving.archivedData(forFont: defaultFont) else { return }
        defaults.set(data, forKey: fontKey)
    }

    // MARK: - Registration

    /// Registers the theme-matching defaults. Called at launch right after the app's plist defaults, before
    /// anything reads these keys.
    @objc static func registerDefaults() { register(in: .standard) }

    static func register(in defaults: UserDefaults) {
        defaults.register(defaults: [
            SAEditorAppearanceThemeSwitcher.matchesAppearanceKey: true,
            SAEditorAppearanceThemeSwitcher.lightThemeKey: SAEditorAppearanceThemeSwitcher.bundledLightThemeName,
            SAEditorAppearanceThemeSwitcher.darkThemeKey: SAEditorAppearanceThemeSwitcher.bundledDarkThemeName,
        ])
    }

    // MARK: - One-time updates

    /// Runs the one-time font update and theme-matching upgrade against the user's own (persistent) settings.
    /// Called at launch after the preference revision upgrades (SPApplyRevisionChanges), which can reset the font.
    @objc static func runOneTimeUpdates() {
        runOneTimeUpdates(in: .standard) {
            Bundle.main.bundleIdentifier.flatMap { UserDefaults.standard.persistentDomain(forName: $0) }
        }
    }

    /// The launch step against `defaults`. Once both updates have run it returns without calling `userDomain`,
    /// so a normal launch never reads the persistent domain. Nothing here touches the Light/Dark theme picks.
    static func runOneTimeUpdates(in defaults: UserDefaults, userDomain: () -> [String: Any]?) {
        guard !defaults.bool(forKey: fontUpdatedKey) || !defaults.bool(forKey: themeMatchingUpgradeCheckedKey) else { return }
        let domain = userDomain()
        updateFont(in: defaults, userFontData: domain?[fontKey] as? Data)
        upgradeThemeMatching(in: defaults, userDomain: domain)
    }

    /// Update when not done before and the font is unset or the old default, Menlo 14.
    static func shouldUpdateFont(alreadyUpdated: Bool, userFontData: Data?) -> Bool {
        guard !alreadyUpdated else { return false }
        guard let data = userFontData, let font = SAArchiving.font(from: data) else { return true }
        return font.fontName == "Menlo-Regular" && font.pointSize == 14
    }

    /// Writes SF Mono 13 when `shouldUpdateFont` says so; always records that it ran.
    static func updateFont(in defaults: UserDefaults, userFontData: Data?) {
        if shouldUpdateFont(alreadyUpdated: defaults.bool(forKey: fontUpdatedKey), userFontData: userFontData),
           let data = SAArchiving.archivedData(forFont: defaultFont) {
            defaults.set(data, forKey: fontKey)
        }
        defaults.set(true, forKey: fontUpdatedKey)
    }

    /// Whether an existing user's own settings call for matching on. Only users on the default colors keep the
    /// registered default (on): no theme name, or "Default". A named theme or "User-defined" is kept, with
    /// matching off. With no theme name, colors of their own (hand-edited before themes had names) also keep
    /// matching off; colors equal to the registered ones still count as the default colors.
    static func shouldMatchAppearance(userDomain domain: [String: Any], registered: [String: Any]) -> Bool {
        let name = (domain[SAEditorThemeLoader.themeNameKey] as? String) ?? ""
        if !name.isEmpty { return name.caseInsensitiveCompare(SAEditorThemeLoader.defaultSchemeName) == .orderedSame }
        return SAEditorThemeLoader.colorKeys.allSatisfy { key in
            guard let stored = domain[key] else { return true }
            return (stored as? Data) == (registered[key] as? Data)
        }
    }

    /// One-time guard for existing users: matching on by default would load Sequel Ace Light/Dark over the theme
    /// or colors they chose. Turns matching off for them unless `shouldMatchAppearance` says otherwise. Never
    /// overrides a matching value already in their domain. Reads the user's own (persistent) domain; always
    /// records that it ran.
    static func upgradeThemeMatching(in defaults: UserDefaults, userDomain: [String: Any]?) {
        guard !defaults.bool(forKey: themeMatchingUpgradeCheckedKey) else { return }
        defaults.set(true, forKey: themeMatchingUpgradeCheckedKey)
        let domain = userDomain ?? [:]
        guard domain[SAEditorAppearanceThemeSwitcher.matchesAppearanceKey] == nil else { return }
        let registered = defaults.volatileDomain(forName: UserDefaults.registrationDomain)
        if !shouldMatchAppearance(userDomain: domain, registered: registered) {
            defaults.set(false, forKey: SAEditorAppearanceThemeSwitcher.matchesAppearanceKey)
        }
    }
}
