//
//  SAEditorColourMode.swift
//  Sequel Ace
//
//  Settings ▸ Appearance ▸ Colours' three modes. Match appearance (the
//  appearance switcher loads Claude Light/Dark with the app's appearance),
//  Choose (it loads the one picked, whatever the appearance) or Custom (the
//  user's own set, fixed in light and dark mode). The custom set is remembered
//  as a snapshot while a Claude theme is in charge. Shared with the Unit Tests
//  target.
//

import AppKit

@objc final class SAEditorColourMode: NSObject {

    static let customColoursKey = "EditorCustomColours"
    static let customThemeNameKey = "EditorCustomThemeName"
    /// Choose's pick, "light" or "dark"; absent (or anything else) while matching the appearance. Only read while
    /// `matchesAppearanceKey` is on, so a Follow=YES/NO user from before Choose keeps Match appearance/Custom.
    static let chosenAppearanceKey = "EditorChosenAppearance"
    private static let chosenLight = "light", chosenDark = "dark"

    enum Mode: Equatable {
        /// Claude Light in light mode, Claude Dark in dark mode.
        case matchAppearance
        /// Claude Dark (`dark`) or Claude Light, whatever the app's appearance.
        case choose(dark: Bool)
        /// The user's own 11 colours.
        case custom

        /// The Colours pill: 0 Match appearance, 1 Choose, 2 Custom.
        var pillIndex: Int {
            switch self {
            case .matchAppearance: return 0
            case .choose: return 1
            case .custom: return 2
            }
        }

        /// Whether Claude Dark (true) or Claude Light (false) applies with the app in `appIsDark`; nil in Custom.
        func appliesDark(appIsDark: Bool) -> Bool? {
            switch self {
            case .matchAppearance: return appIsDark
            case .choose(let dark): return dark
            case .custom: return nil
            }
        }

        /// The mode a pill pick moves to, or nil when it is the current one (the pop-up reports re-picks too).
        /// Choose starts on the theme the app's appearance shows now, so picking it changes nothing until a tile is clicked.
        static func picked(index: Int, from current: Mode, appIsDark: Bool) -> Mode? {
            guard index != current.pillIndex else { return nil }
            switch index {
            case 0: return .matchAppearance
            case 1: return .choose(dark: appIsDark)
            case 2: return .custom
            default: return nil
            }
        }
    }

    /// Match appearance or Choose: a Claude theme is in charge (the switcher loads it), not the custom set.
    static func isFollowingMacOS(_ defaults: UserDefaults) -> Bool {
        defaults.bool(forKey: SAEditorAppearanceThemeSwitcher.matchesAppearanceKey)
    }

    static func mode(in defaults: UserDefaults) -> Mode {
        guard isFollowingMacOS(defaults) else { return .custom }
        switch defaults.string(forKey: chosenAppearanceKey) {
        case chosenLight: return .choose(dark: false)
        case chosenDark: return .choose(dark: true)
        default: return .matchAppearance
        }
    }

    /// Writes `mode`'s keys, remembering or restoring the custom set when leaving or entering Custom (the caller then
    /// has the switcher apply the Claude theme for Match appearance or Choose).
    static func setMode(_ mode: Mode, in defaults: UserDefaults) {
        switch mode {
        case .custom:
            enterCustomise(in: defaults)
            defaults.removeObject(forKey: chosenAppearanceKey)
        case .matchAppearance:
            defaults.removeObject(forKey: chosenAppearanceKey)
            leaveCustomise(in: defaults)
        case .choose(let dark):
            // Written first: while Custom it is not read, and from Match appearance it is the only change.
            defaults.set(dark ? chosenDark : chosenLight, forKey: chosenAppearanceKey)
            leaveCustomise(in: defaults)
        }
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

    /// Match appearance or Choose → Custom: bring back the remembered set, or keep what is showing.
    static func enterCustomise(in defaults: UserDefaults) {
        guard isFollowingMacOS(defaults) else { return }
        defaults.set(false, forKey: SAEditorAppearanceThemeSwitcher.matchesAppearanceKey)
        if !restoreSnapshot(in: defaults) { saveSnapshot(in: defaults) }
    }

    /// Custom → Match appearance or Choose: remember the custom set first (the caller then applies Claude).
    static func leaveCustomise(in defaults: UserDefaults) {
        guard !isFollowingMacOS(defaults) else { return }
        saveSnapshot(in: defaults)
        defaults.set(true, forKey: SAEditorAppearanceThemeSwitcher.matchesAppearanceKey)
    }

    /// The settings control's entry point (standard defaults, live switcher).
    static func apply(_ mode: Mode) {
        setMode(mode, in: .standard)
        if mode != .custom { SAEditorAppearanceThemeSwitcher.shared.applyForCurrentAppearance() }
    }
}
