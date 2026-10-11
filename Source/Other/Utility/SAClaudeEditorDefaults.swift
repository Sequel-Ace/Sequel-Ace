//
//  SAClaudeEditorDefaults.swift
//  Sequel Ace
//
//  The Claude look's editor defaults: follow the system appearance with the
//  bundled Claude Light / Claude Dark themes, and SF Mono 13 as the editor
//  font. Shared with the Unit Tests target.
//

import AppKit

@objc final class SAClaudeEditorDefaults: NSObject {

    /// Keep in sync with SPCustomQueryEditorFont in SPConstants.m.
    static let fontKey = "CustomQueryEditorFont"
    static let fontMigratedKey = "SAClaudeEditorFontMigrated"
    static let themeUpgradeCheckedKey = "SAClaudeEditorThemeUpgradeChecked"

    static var claudeFont: NSFont { .monospacedSystemFont(ofSize: 13, weight: .regular) }

    /// Registers the Claude defaults over Layer 1's neutral ones, then runs the
    /// one-time font migration and theme-matching upgrade guard against the
    /// user's own (persistent) settings.
    @objc static func registerAndMigrate() {
        register(in: .standard)
        let userDomain = Bundle.main.bundleIdentifier.flatMap { UserDefaults.standard.persistentDomain(forName: $0) }
        migrateFont(in: .standard, userFontData: userDomain?[fontKey] as? Data)
        upgradeThemeMatching(in: .standard, userDomain: userDomain)
        resetConsoleOverride(in: .standard)
        resetFollowPair(in: .standard)
    }

    /// Keep in sync with SAScriptConsoleAppearance.useCustomKey. The Claude look has no
    /// console-only colours: the console always uses the editor's.
    static let consoleOverrideKey = "ScriptConsoleUseCustomAppearance"

    static func resetConsoleOverride(in defaults: UserDefaults) {
        defaults.removeObject(forKey: consoleOverrideKey)
    }

    /// The Claude look has no light/dark theme pickers: Follow macOS always uses the
    /// registered Claude Light / Claude Dark, so clear any stored (or renamed) pair.
    static func resetFollowPair(in defaults: UserDefaults) {
        defaults.removeObject(forKey: SAEditorAppearanceThemeSwitcher.lightThemeKey)
        defaults.removeObject(forKey: SAEditorAppearanceThemeSwitcher.darkThemeKey)
    }

    static func register(in defaults: UserDefaults) {
        defaults.register(defaults: [
            SAEditorAppearanceThemeSwitcher.matchesAppearanceKey: true,
            SAEditorAppearanceThemeSwitcher.lightThemeKey: "Claude Light",
            SAEditorAppearanceThemeSwitcher.darkThemeKey: "Claude Dark",
        ])
    }

    /// Migrate when not done before and the font is unset or the old default, Menlo 14.
    static func shouldMigrateFont(alreadyMigrated: Bool, userFontData: Data?) -> Bool {
        guard !alreadyMigrated else { return false }
        guard let data = userFontData, let font = SAArchiving.font(from: data) else { return true }
        return font.fontName == "Menlo-Regular" && font.pointSize == 14
    }

    /// Writes SF Mono 13 when `shouldMigrateFont` says so; always records that it ran.
    static func migrateFont(in defaults: UserDefaults, userFontData: Data?) {
        if shouldMigrateFont(alreadyMigrated: defaults.bool(forKey: fontMigratedKey), userFontData: userFontData),
           let data = SAArchiving.archivedData(forFont: claudeFont) {
            defaults.set(data, forKey: fontKey)
        }
        defaults.set(true, forKey: fontMigratedKey)
    }

    /// Theme name the Query Editor pane gives hand-edited colours.
    /// Keep in sync with SPCustomColorSchemeName in SPEditorPreferencePane.m.
    static let customSchemeName = "User-defined"

    /// One-time guard for existing users: turning matching on by default would load
    /// Claude Light/Dark over colours they edited by hand and never saved as a theme.
    /// Reads the user's own (persistent) domain; always records that it ran.
    static func upgradeThemeMatching(in defaults: UserDefaults, userDomain: [String: Any]?) {
        guard !defaults.bool(forKey: themeUpgradeCheckedKey) else { return }
        defaults.set(true, forKey: themeUpgradeCheckedKey)
        let domain = userDomain ?? [:]
        guard domain[SAEditorAppearanceThemeSwitcher.matchesAppearanceKey] == nil else { return }
        let name = (domain[SAEditorThemeLoader.themeNameKey] as? String) ?? ""
        let handEdited = name.caseInsensitiveCompare(customSchemeName) == .orderedSame
            || (name.isEmpty && SAEditorThemeLoader.colourKeys.contains { domain[$0] != nil })
        if handEdited { defaults.set(false, forKey: SAEditorAppearanceThemeSwitcher.matchesAppearanceKey) }
    }
}
