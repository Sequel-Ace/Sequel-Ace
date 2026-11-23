//
//  SAEditorAppearanceThemeSwitcher.swift
//  Sequel Ace
//
//  Makes the query editor's color theme follow the app's light/dark
//  appearance: when "Match system appearance" is on, loads the chosen Light
//  or Dark theme into the editor color settings (which every editor already
//  observes). Pure Foundation/AppKit, shared with the Unit Tests target.
//

import AppKit

@objc final class SAEditorAppearanceThemeSwitcher: NSObject {

    // Registered by SAEditorDefaults.
    static let matchesAppearanceKey = "EditorThemeMatchesAppearance"
    static let lightThemeKey = "EditorLightThemeName"
    static let darkThemeKey = "EditorDarkThemeName"
    /// The bundled themes: the default Light/Dark picks, and what is loaded when a picked theme's file is missing.
    static let bundledLightThemeName = "Sequel Ace Light"
    static let bundledDarkThemeName = "Sequel Ace Dark"
    /// Posted after a theme was loaded because of the appearance or a setting change.
    static let themeDidChangeNotification = NSNotification.Name("SAEditorThemeDidChange")
    /// Posted after theme files were added, renamed or removed (`themeListDidChange()`), so pickers re-read the list.
    static let themeListDidChangeNotification = NSNotification.Name("SAEditorThemeListDidChange")
    private static let themeFileExtension = "spTheme" // keep in sync with SPColorThemeFileExtension in SPConstants.m

    @objc static let shared = SAEditorAppearanceThemeSwitcher(defaults: .standard)

    let defaults: UserDefaults
    /// The Themes folder; set by `start(themesDirectory:)` (tests set it directly).
    var themesDirectory: String?
    /// The app's own copies of the bundled themes (tests set it directly).
    var bundledThemesDirectory: String? = Bundle.main.sharedSupportPath.map { ($0 as NSString).appendingPathComponent("Default Themes") }
    private var appearanceObservation: NSKeyValueObservation?

    init(defaults: UserDefaults) {
        self.defaults = defaults
        super.init()
    }

    // MARK: - Decision

    /// The theme to load now, or nil when matching is off, no theme is chosen
    /// for this appearance, or it is already the current theme.
    static func themeToApply(isDark: Bool, matches: Bool, light: String?, dark: String?, current: String?) -> String? {
        guard matches, let name = isDark ? dark : light, !name.isEmpty else { return nil }
        if let current, name.caseInsensitiveCompare(current) == .orderedSame { return nil }
        return name
    }

    /// Whether `appearance` is a dark one (Dark Aqua, or its high-contrast variant).
    static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    // MARK: - Running

    /// Starts following the app's appearance and applies the matching theme now.
    @objc(startWithThemesDirectory:)
    func start(themesDirectory: String) {
        self.themesDirectory = themesDirectory
        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] app, _ in
            self?.apply(isDark: Self.isDark(app.effectiveAppearance))
        }
        applyForCurrentAppearance()
    }

    /// Applies the theme the current app appearance calls for (after a settings change).
    func applyForCurrentAppearance() {
        guard let app = NSApp else { return }
        apply(isDark: Self.isDark(app.effectiveAppearance))
    }

    /// Loads the theme for `isDark` if the settings call for one. When the picked theme's file is missing or
    /// unreadable, loads the bundled Sequel Ace Light/Dark instead, so the editor does not keep the other
    /// appearance's colors; the pick itself is kept (the section shows it as missing).
    /// - Returns: true when a theme was loaded.
    @discardableResult
    func apply(isDark: Bool) -> Bool {
        let current = defaults.string(forKey: SAEditorThemeLoader.themeNameKey)
        guard let name = Self.themeToApply(isDark: isDark,
                                           matches: defaults.bool(forKey: Self.matchesAppearanceKey),
                                           light: defaults.string(forKey: Self.lightThemeKey),
                                           dark: defaults.string(forKey: Self.darkThemeKey),
                                           current: current) else { return false }
        var loaded = name
        if name.caseInsensitiveCompare(SAEditorThemeLoader.defaultSchemeName) == .orderedSame {
            SAEditorThemeLoader.loadDefaultColors(into: defaults)
        } else if !loadTheme(named: name, from: themesDirectory) {
            let fallback = isDark ? Self.bundledDarkThemeName : Self.bundledLightThemeName
            if let current, current.caseInsensitiveCompare(fallback) == .orderedSame { return false }
            guard loadTheme(named: fallback, from: bundledThemesDirectory) else { return false }
            loaded = fallback
        }
        defaults.set(loaded, forKey: SAEditorThemeLoader.themeNameKey)
        NotificationCenter.default.post(name: Self.themeDidChangeNotification, object: self)
        return true
    }

    /// Loads `directory/name.spTheme`; true when it held colors.
    private func loadTheme(named name: String, from directory: String?) -> Bool {
        guard let directory else { return false }
        let path = (directory as NSString).appendingPathComponent(name + "." + Self.themeFileExtension)
        return SAEditorThemeLoader.loadTheme(atPath: path, into: defaults) > 0
    }

    // MARK: - Hooks from the preference pane

    /// A hand-edited color or a theme picked from the theme menu wins: matching turns off.
    @objc func userChoseThemeManually() {
        defaults.set(false, forKey: Self.matchesAppearanceKey)
    }

    /// Keeps the Light/Dark choices pointing at a theme renamed in Edit Theme List.
    @objc(themeRenamedFrom:to:)
    func themeRenamed(from oldName: String, to newName: String) {
        for key in [Self.lightThemeKey, Self.darkThemeKey] {
            if let chosen = defaults.string(forKey: key), chosen.caseInsensitiveCompare(oldName) == .orderedSame {
                defaults.set(newName, forKey: key)
            }
        }
    }

    /// Tells the theme pickers that theme files were added, renamed or removed (the pane's Save As, Duplicate,
    /// Rename, Remove and Export).
    @objc static func themeListDidChange() {
        NotificationCenter.default.post(name: themeListDidChangeNotification, object: nil)
    }

    // MARK: - Picker contents

    /// "Default" followed by every theme file in `directory`, sorted like Finder.
    static func availableThemeNames(in directory: String) -> [String] {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []
        let themes = files
            .filter { ($0 as NSString).pathExtension.caseInsensitiveCompare(themeFileExtension) == .orderedSame }
            .map { ($0 as NSString).deletingPathExtension }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        return [SAEditorThemeLoader.defaultSchemeName] + themes
    }

    /// The picker's entries: the available names, plus the selected name when it
    /// no longer exists (the section shows it as missing).
    static func pickerNames(available: [String], selected: String) -> [String] {
        let present = available.contains { $0.caseInsensitiveCompare(selected) == .orderedSame }
        return present || selected.isEmpty ? available : available + [selected]
    }

    /// The entry of `available` that matches `name` case-insensitively, or `name`
    /// itself when none does. Picker tags are matched exactly, so a stored name in a
    /// different case must be mapped to the listed spelling to show as selected.
    static func canonicalName(_ name: String, in available: [String]) -> String {
        available.first { $0.caseInsensitiveCompare(name) == .orderedSame } ?? name
    }
}
