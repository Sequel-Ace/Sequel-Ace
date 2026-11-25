//
//  SAEditorThemeAppearanceSettings.swift
//  Sequel Ace
//
//  The state of Preferences ▸ Query Editor ▸ Theme Appearance ("Match system
//  appearance" and the Light/Dark theme picks), read from and written to the
//  user defaults. Shared with the Unit Tests target.
//

import Foundation
import Combine

final class SAEditorThemeAppearanceSettings: ObservableObject {
    private let defaults: UserDefaults
    private let themesDirectory: String
    private let confirmDiscardUnsaved: () -> Bool
    private let onThemeApplied: () -> Void
    private let applyTheme: () -> Void
    private var keyObserver: KeyObserver?
    private var observers: [NSObjectProtocol] = []

    @Published private(set) var themeNames: [String] = []
    @Published private(set) var matches = false
    @Published private(set) var lightTheme = ""
    @Published private(set) var darkTheme = ""

    /// - Parameters:
    ///   - confirmDiscardUnsaved: asks before matching replaces unsaved colors (the pane's "Unsaved Theme" prompt);
    ///     false keeps matching off.
    ///   - onThemeApplied: called after the switcher loaded a theme, so the pane can redraw its colors.
    ///   - applyTheme: loads the theme the settings now call for (the shared switcher; tests pass their own).
    init(defaults: UserDefaults = .standard, themesDirectory: String,
         confirmDiscardUnsaved: @escaping () -> Bool, onThemeApplied: @escaping () -> Void,
         applyTheme: @escaping () -> Void = { SAEditorAppearanceThemeSwitcher.shared.applyForCurrentAppearance() }) {
        self.defaults = defaults
        self.themesDirectory = themesDirectory
        self.confirmDiscardUnsaved = confirmDiscardUnsaved
        self.onThemeApplied = onThemeApplied
        self.applyTheme = applyTheme
        reloadThemeNames()
        // Only the three keys shown here: other defaults writes (every color edit, every window frame) cost nothing.
        keyObserver = KeyObserver(defaults: defaults, keys: [SAEditorAppearanceThemeSwitcher.matchesAppearanceKey,
                                                             SAEditorAppearanceThemeSwitcher.lightThemeKey,
                                                             SAEditorAppearanceThemeSwitcher.darkThemeKey]) { [weak self] in
            self?.readSettings()
        }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: SAEditorAppearanceThemeSwitcher.themeDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.onThemeApplied()
        })
        observers.append(center.addObserver(forName: SAEditorAppearanceThemeSwitcher.themeListDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.reloadThemeNames()
        })
    }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    /// Re-reads the Themes folder, then the settings. Called when the section appears and after theme files change.
    func reloadThemeNames() {
        let names = SAEditorAppearanceThemeSwitcher.availableThemeNames(in: themesDirectory)
        if names != themeNames { themeNames = names }
        readSettings()
    }

    /// Re-reads the three settings (no file access).
    func readSettings() {
        let newMatches = defaults.bool(forKey: SAEditorAppearanceThemeSwitcher.matchesAppearanceKey)
        if newMatches != matches { matches = newMatches }
        let newLight = defaults.string(forKey: SAEditorAppearanceThemeSwitcher.lightThemeKey) ?? ""
        if newLight != lightTheme { lightTheme = newLight }
        let newDark = defaults.string(forKey: SAEditorAppearanceThemeSwitcher.darkThemeKey) ?? ""
        if newDark != darkTheme { darkTheme = newDark }
    }

    // Read-write accessors the view binds to through `$settings.…` (no closure-built Bindings).
    var matchesSetting: Bool {
        get { matches }
        set {
            if newValue, !confirmDiscardUnsaved() {
                // Nothing in the model changed, so SwiftUI would not re-render and the
                // checkbox would keep its flipped state. Republish after the toggle has
                // finished writing so the body re-reads `matches` (false) and pushes it back.
                DispatchQueue.main.async { [weak self] in self?.objectWillChange.send() }
                return
            }
            defaults.set(newValue, forKey: SAEditorAppearanceThemeSwitcher.matchesAppearanceKey)
            if newValue { applyTheme() }
            readSettings()
        }
    }

    var lightSetting: String {
        get { SAEditorAppearanceThemeSwitcher.canonicalName(lightTheme, in: themeNames) }
        set { choose(newValue, forKey: SAEditorAppearanceThemeSwitcher.lightThemeKey) }
    }

    var darkSetting: String {
        get { SAEditorAppearanceThemeSwitcher.canonicalName(darkTheme, in: themeNames) }
        set { choose(newValue, forKey: SAEditorAppearanceThemeSwitcher.darkThemeKey) }
    }

    private func choose(_ name: String, forKey key: String) {
        defaults.set(name, forKey: key)
        applyTheme()
        readSettings()
    }

    func entries(selected: String) -> [String] {
        SAEditorAppearanceThemeSwitcher.pickerNames(available: themeNames, selected: selected)
    }

    func displayName(_ name: String) -> String {
        themeNames.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame })
            ? name
            : String(format: NSLocalizedString("%@ (missing)", comment: "Preferences > Query Editor > Theme Appearance: a chosen theme whose file no longer exists"), name)
    }

    /// Key-value observes a few user defaults keys and calls `onChange` on the main queue when one changes.
    private final class KeyObserver: NSObject {
        private let defaults: UserDefaults
        private let keys: [String]
        private let onChange: () -> Void

        init(defaults: UserDefaults, keys: [String], onChange: @escaping () -> Void) {
            self.defaults = defaults
            self.keys = keys
            self.onChange = onChange
            super.init()
            for key in keys { defaults.addObserver(self, forKeyPath: key, options: [], context: nil) }
        }

        deinit { for key in keys { defaults.removeObserver(self, forKeyPath: key) } }

        override func observeValue(forKeyPath keyPath: String?, of object: Any?,
                                   change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
            guard let keyPath, keys.contains(keyPath), (object as? UserDefaults) === defaults else {
                super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
                return
            }
            if Thread.isMainThread { onChange() } else { DispatchQueue.main.async(execute: onChange) }
        }
    }
}
