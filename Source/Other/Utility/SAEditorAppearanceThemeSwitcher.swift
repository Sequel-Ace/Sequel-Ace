//
//  SAEditorAppearanceThemeSwitcher.swift
//  Sequel Ace
//
//  Makes the query editor's colour theme follow the app's light/dark
//  appearance: when "Match system appearance" is on, loads the chosen Light
//  or Dark theme into the editor colour settings (which every editor already
//  observes). Pure Foundation/AppKit, shared with the Unit Tests target.
//

import AppKit

@objc final class SAEditorAppearanceThemeSwitcher: NSObject {

    @objc static let matchesAppearanceKey = "EditorThemeMatchesAppearance"
    @objc static let lightThemeKey = "EditorLightThemeName"
    @objc static let darkThemeKey = "EditorDarkThemeName"
    /// Posted after a theme was loaded because of the appearance or a setting change.
    @objc static let themeDidChangeNotification = NSNotification.Name("SAEditorThemeDidChange")
    private static let themeFileExtension = "spTheme" // keep in sync with SPColorThemeFileExtension in SPConstants.m

    @objc static let shared = SAEditorAppearanceThemeSwitcher(defaults: .standard)

    let defaults: UserDefaults
    /// The Themes folder; set by `start(themesDirectory:)` (tests set it directly).
    var themesDirectory: String?
    private var appearanceObservation: NSKeyValueObservation?

    init(defaults: UserDefaults) {
        self.defaults = defaults
        super.init()
    }

    // MARK: - Defaults

    /// Registers Layer 1's neutral defaults: matching off, "Default" / "Dark Ace".
    @objc static func registerDefaults() { register(in: .standard) }

    static func register(in defaults: UserDefaults) {
        defaults.register(defaults: [matchesAppearanceKey: false, lightThemeKey: "Default", darkThemeKey: "Dark Ace"])
    }

    // MARK: - Decision

    /// The theme to load now, or nil when matching is off, no theme is chosen
    /// for this appearance, or it is already the current theme.
    static func themeToApply(isDark: Bool, matches: Bool, light: String?, dark: String?, current: String?) -> String? {
        guard matches, let name = isDark ? dark : light, !name.isEmpty else { return nil }
        if let current, name.caseInsensitiveCompare(current) == .orderedSame { return nil }
        return name
    }

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
    @objc func applyForCurrentAppearance() {
        guard let app = NSApp else { return }
        apply(isDark: Self.isDark(app.effectiveAppearance))
    }

    /// Loads the theme for `isDark` if the settings call for one.
    /// - Returns: true when a theme was loaded.
    @discardableResult
    func apply(isDark: Bool) -> Bool {
        guard let name = Self.themeToApply(isDark: isDark,
                                           matches: defaults.bool(forKey: Self.matchesAppearanceKey),
                                           light: defaults.string(forKey: Self.lightThemeKey),
                                           dark: defaults.string(forKey: Self.darkThemeKey),
                                           current: defaults.string(forKey: SAEditorThemeLoader.themeNameKey)) else { return false }
        if name.caseInsensitiveCompare(SAEditorThemeLoader.defaultSchemeName) == .orderedSame {
            SAEditorThemeLoader.loadDefaultColours(into: defaults)
        } else {
            guard let directory = themesDirectory else { return false }
            let path = (directory as NSString).appendingPathComponent(name + "." + Self.themeFileExtension)
            guard SAEditorThemeLoader.loadTheme(atPath: path, into: defaults) > 0 else { return false }
        }
        defaults.set(name, forKey: SAEditorThemeLoader.themeNameKey)
        NotificationCenter.default.post(name: Self.themeDidChangeNotification, object: self)
        return true
    }

    // MARK: - Hooks from the preference pane

    /// A hand-edited colour or a theme picked from the theme menu wins: matching turns off.
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
}
