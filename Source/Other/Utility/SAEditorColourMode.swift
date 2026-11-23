//
//  SAEditorColourMode.swift
//  Sequel Ace
//
//  Settings → Query Editor's two colour modes. Follow macOS (the appearance
//  switcher loads Claude Light/Dark) or Customise (the user's own set, fixed in
//  light and dark mode). The custom set is remembered as a snapshot while
//  following macOS. Shared with the Unit Tests target.
//

import AppKit

@objc final class SAEditorColourMode: NSObject {

    static let customColoursKey = "EditorCustomColours"
    static let customThemeNameKey = "EditorCustomThemeName"

    static func isFollowingMacOS(_ defaults: UserDefaults) -> Bool {
        defaults.bool(forKey: SAEditorAppearanceThemeSwitcher.matchesAppearanceKey)
    }

    /// Stores the live 11 colours and theme name as the custom snapshot.
    static func saveSnapshot(in defaults: UserDefaults) {
        var colours: [String: Data] = [:]
        for key in SAEditorThemeLoader.colourKeys {
            if let data = defaults.data(forKey: key) { colours[key] = data }
        }
        defaults.set(colours, forKey: customColoursKey)
        // Hand-edited colours from older versions may have no theme name; "User-defined" is
        // what the switcher treats as custom, so restoring never leaves a Claude name on them.
        let liveName = defaults.string(forKey: SAEditorThemeLoader.themeNameKey) ?? ""
        defaults.set(liveName.isEmpty ? SAClaudeEditorDefaults.customSchemeName : liveName, forKey: customThemeNameKey)
    }

    /// Writes the snapshot back into the live keys when it holds all 11 colours.
    @discardableResult
    static func restoreSnapshot(in defaults: UserDefaults) -> Bool {
        guard let colours = defaults.dictionary(forKey: customColoursKey) as? [String: Data],
              SAEditorThemeLoader.colourKeys.allSatisfy({ colours[$0] != nil }) else { return false }
        for key in SAEditorThemeLoader.colourKeys { defaults.set(colours[key], forKey: key) }
        if let name = defaults.string(forKey: customThemeNameKey), !name.isEmpty {
            defaults.set(name, forKey: SAEditorThemeLoader.themeNameKey)
        }
        return true
    }

    /// Follow macOS → Customise: bring back the remembered set, or keep what is showing.
    static func enterCustomise(in defaults: UserDefaults) {
        guard isFollowingMacOS(defaults) else { return }
        defaults.set(false, forKey: SAEditorAppearanceThemeSwitcher.matchesAppearanceKey)
        if !restoreSnapshot(in: defaults) { saveSnapshot(in: defaults) }
    }

    /// Customise → Follow macOS: remember the custom set first (the caller then applies Claude).
    static func leaveCustomise(in defaults: UserDefaults) {
        guard !isFollowingMacOS(defaults) else { return }
        saveSnapshot(in: defaults)
        defaults.set(true, forKey: SAEditorAppearanceThemeSwitcher.matchesAppearanceKey)
    }

    /// The settings control's entry point (standard defaults, live switcher).
    @objc static func setFollowsMacOS(_ follow: Bool) {
        if follow {
            leaveCustomise(in: .standard)
            SAEditorAppearanceThemeSwitcher.shared.applyForCurrentAppearance()
        } else {
            enterCustomise(in: .standard)
        }
    }
}
