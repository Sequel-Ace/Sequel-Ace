//
//  SAEditorAppearanceThemeSwitcherTests.swift
//  Unit Tests
//

import AppKit
import XCTest

final class SAEditorAppearanceThemeSwitcherTests: XCTestCase {

    private let suite = "SAEditorAppearanceThemeSwitcherTests"
    private var defaults: UserDefaults!
    private var dir: URL!
    private var bundledDir: URL!
    private var switcher: SAEditorAppearanceThemeSwitcher!
    private var registered: SARegistrationDomainSnapshot!

    override func setUpWithError() throws {
        registered = SARegistrationDomainSnapshot()
        UserDefaults().removePersistentDomain(forName: suite)
        defaults = UserDefaults(suiteName: suite)
        SAEditorDefaults.register(in: defaults)
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try writeTheme("Light One", background: "#FCFCFB")
        try writeTheme("Dark One", background: "#151515")
        // Stand-ins for the app's bundled Sequel Ace Light / Sequel Ace Dark.
        bundledDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: bundledDir, withIntermediateDirectories: true)
        try writeTheme("Sequel Ace Light", background: "#F0F0F0", in: bundledDir)
        try writeTheme("Sequel Ace Dark", background: "#0A0A0A", in: bundledDir)
        switcher = SAEditorAppearanceThemeSwitcher(defaults: defaults)
        switcher.themesDirectory = dir.path
        switcher.bundledThemesDirectory = bundledDir.path
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.removeItem(at: bundledDir)
        UserDefaults().removePersistentDomain(forName: suite)
        registered.restore()
    }

    private func writeTheme(_ name: String, background: String, in directory: URL? = nil) throws {
        let plist: [String: Any] = ["settings": [["settings": ["background": background, "foreground": "#808080"]]]]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: (directory ?? dir).appendingPathComponent(name + ".spTheme"))
    }

    private func backgroundRed() -> Int {
        let c = SAArchiving.color(from: defaults.data(forKey: SAEditorThemeLoader.backgroundColorKey))?.usingColorSpace(.genericRGB)
        return Int(((c?.redComponent ?? -1) * 255).rounded())
    }

    /// Verifies the decision table.
    func testThemeToApply() {
        typealias S = SAEditorAppearanceThemeSwitcher
        XCTAssertEqual(S.themeToApply(isDark: true, matches: true, light: "L", dark: "D", current: "L"), "D")
        XCTAssertEqual(S.themeToApply(isDark: false, matches: true, light: "L", dark: "D", current: "D"), "L")
        XCTAssertNil(S.themeToApply(isDark: true, matches: false, light: "L", dark: "D", current: "L"), "matching off")
        XCTAssertNil(S.themeToApply(isDark: true, matches: true, light: "L", dark: "D", current: "d"), "already current (case-insensitive)")
        XCTAssertNil(S.themeToApply(isDark: true, matches: true, light: "L", dark: nil, current: "L"))
        XCTAssertNil(S.themeToApply(isDark: true, matches: true, light: "L", dark: "", current: "L"))
        XCTAssertEqual(S.themeToApply(isDark: true, matches: true, light: "L", dark: "D", current: nil), "D")
    }

    /// Verifies dark/light apply loads the chosen file, records its name and posts once.
    func testApplyLoadsTheChosenThemeAndNotifies() {
        defaults.set(true, forKey: SAEditorAppearanceThemeSwitcher.matchesAppearanceKey)
        defaults.set("Light One", forKey: SAEditorAppearanceThemeSwitcher.lightThemeKey)
        defaults.set("Dark One", forKey: SAEditorAppearanceThemeSwitcher.darkThemeKey)
        let posted = expectation(forNotification: SAEditorAppearanceThemeSwitcher.themeDidChangeNotification, object: switcher)
        XCTAssertTrue(switcher.apply(isDark: true))
        wait(for: [posted], timeout: 1)
        XCTAssertEqual(backgroundRed(), 21)
        XCTAssertEqual(defaults.string(forKey: SAEditorThemeLoader.themeNameKey), "Dark One")
        XCTAssertFalse(switcher.apply(isDark: true), "already current: no reload")
        XCTAssertTrue(switcher.apply(isDark: false))
        XCTAssertEqual(backgroundRed(), 252)
    }

    /// Verifies "Default" resets to the registered colors instead of reading a file.
    func testDefaultSchemeUsesRegisteredColors() {
        defaults.register(defaults: [SAEditorThemeLoader.backgroundColorKey:
                                        SAArchiving.archivedData(forColor: NSColor(calibratedWhite: 1, alpha: 1))!])
        defaults.set(true, forKey: SAEditorAppearanceThemeSwitcher.matchesAppearanceKey)
        defaults.set("Default", forKey: SAEditorAppearanceThemeSwitcher.lightThemeKey)
        XCTAssertTrue(switcher.apply(isDark: false))
        XCTAssertEqual(backgroundRed(), 255)
        XCTAssertEqual(defaults.string(forKey: SAEditorThemeLoader.themeNameKey), "Default")
    }

    /// Verifies a missing picked theme loads the bundled theme for that appearance and records its name; the pick
    /// is kept, and a second apply does not reload the fallback.
    func testMissingPickedThemeFallsBackToTheBundledTheme() {
        defaults.set("Before", forKey: SAEditorThemeLoader.themeNameKey)
        defaults.set(true, forKey: SAEditorAppearanceThemeSwitcher.matchesAppearanceKey)
        defaults.set("Gone Dark", forKey: SAEditorAppearanceThemeSwitcher.darkThemeKey)
        defaults.set("Gone Light", forKey: SAEditorAppearanceThemeSwitcher.lightThemeKey)
        let posted = expectation(forNotification: SAEditorAppearanceThemeSwitcher.themeDidChangeNotification, object: switcher)
        XCTAssertTrue(switcher.apply(isDark: true))
        wait(for: [posted], timeout: 1)
        XCTAssertEqual(backgroundRed(), 10)
        XCTAssertEqual(defaults.string(forKey: SAEditorThemeLoader.themeNameKey), "Sequel Ace Dark")
        XCTAssertEqual(defaults.string(forKey: SAEditorAppearanceThemeSwitcher.darkThemeKey), "Gone Dark", "the pick is kept")
        XCTAssertFalse(switcher.apply(isDark: true), "already on the fallback: no reload")

        XCTAssertTrue(switcher.apply(isDark: false))
        XCTAssertEqual(backgroundRed(), 240)
        XCTAssertEqual(defaults.string(forKey: SAEditorThemeLoader.themeNameKey), "Sequel Ace Light")
    }

    /// Verifies an unreadable picked theme file falls back like a missing one.
    func testUnreadablePickedThemeFallsBackToTheBundledTheme() throws {
        try Data("not a plist".utf8).write(to: dir.appendingPathComponent("Broken.spTheme"))
        defaults.set(true, forKey: SAEditorAppearanceThemeSwitcher.matchesAppearanceKey)
        defaults.set("Broken", forKey: SAEditorAppearanceThemeSwitcher.darkThemeKey)
        XCTAssertTrue(switcher.apply(isDark: true))
        XCTAssertEqual(defaults.string(forKey: SAEditorThemeLoader.themeNameKey), "Sequel Ace Dark")
    }

    /// Verifies that when the bundled theme can't be read either, colors and the theme name are left alone.
    func testMissingPickAndBundledThemeLeaveColorsAlone() {
        switcher.bundledThemesDirectory = "/nonexistent-\(UUID().uuidString)"
        defaults.set(SAArchiving.archivedData(forColor: NSColor(calibratedRed: 0.2, green: 0.2, blue: 0.2, alpha: 1)), forKey: SAEditorThemeLoader.backgroundColorKey)
        defaults.set("Before", forKey: SAEditorThemeLoader.themeNameKey)
        defaults.set(true, forKey: SAEditorAppearanceThemeSwitcher.matchesAppearanceKey)
        defaults.set("Gone", forKey: SAEditorAppearanceThemeSwitcher.darkThemeKey)
        XCTAssertFalse(switcher.apply(isDark: true))
        XCTAssertEqual(backgroundRed(), 51)
        XCTAssertEqual(defaults.string(forKey: SAEditorThemeLoader.themeNameKey), "Before")
    }

    /// Verifies the bundled theme names are the registered default picks and the app's theme files.
    func testBundledThemeNames() {
        XCTAssertEqual(SAEditorAppearanceThemeSwitcher.bundledLightThemeName, "Sequel Ace Light")
        XCTAssertEqual(SAEditorAppearanceThemeSwitcher.bundledDarkThemeName, "Sequel Ace Dark")
        let themes = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("SharedSupport/Default Themes")
        for name in [SAEditorAppearanceThemeSwitcher.bundledLightThemeName, SAEditorAppearanceThemeSwitcher.bundledDarkThemeName] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: themes.appendingPathComponent(name + ".spTheme").path), name)
        }
    }

    /// Verifies themeListDidChange posts the theme-list notification.
    func testThemeListDidChangePosts() {
        let posted = expectation(forNotification: SAEditorAppearanceThemeSwitcher.themeListDidChangeNotification, object: nil)
        SAEditorAppearanceThemeSwitcher.themeListDidChange()
        wait(for: [posted], timeout: 1)
    }

    /// Verifies a manual color edit or theme pick turns matching off.
    func testManualChoiceTurnsMatchingOff() {
        defaults.set(true, forKey: SAEditorAppearanceThemeSwitcher.matchesAppearanceKey)
        switcher.userChoseThemeManually()
        XCTAssertFalse(defaults.bool(forKey: SAEditorAppearanceThemeSwitcher.matchesAppearanceKey))
    }

    /// Verifies renaming a theme keeps the Light/Dark choices pointing at it.
    func testRenameFollowsTheChoice() {
        defaults.set("Light One", forKey: SAEditorAppearanceThemeSwitcher.lightThemeKey)
        defaults.set("Other", forKey: SAEditorAppearanceThemeSwitcher.darkThemeKey)
        switcher.themeRenamed(from: "light one", to: "Morning")
        XCTAssertEqual(defaults.string(forKey: SAEditorAppearanceThemeSwitcher.lightThemeKey), "Morning")
        XCTAssertEqual(defaults.string(forKey: SAEditorAppearanceThemeSwitcher.darkThemeKey), "Other")
    }

    /// Verifies the picker list: "Default" first, then theme files sorted, other files ignored.
    func testAvailableThemeNames() throws {
        try Data().write(to: dir.appendingPathComponent("notes.txt"))
        XCTAssertEqual(SAEditorAppearanceThemeSwitcher.availableThemeNames(in: dir.path), ["Default", "Dark One", "Light One"])
        XCTAssertEqual(SAEditorAppearanceThemeSwitcher.availableThemeNames(in: "/nonexistent-\(UUID().uuidString)"), ["Default"])
    }

    /// Verifies light/dark resolution from an appearance.
    func testIsDark() {
        XCTAssertTrue(SAEditorAppearanceThemeSwitcher.isDark(NSAppearance(named: .darkAqua)!))
        XCTAssertFalse(SAEditorAppearanceThemeSwitcher.isDark(NSAppearance(named: .aqua)!))
    }

    /// Verifies a chosen theme that no longer exists stays selectable (shown as missing).
    func testPickerNamesKeepAMissingChoice() {
        let available = ["Default", "Dark One"]
        XCTAssertEqual(SAEditorAppearanceThemeSwitcher.pickerNames(available: available, selected: "Dark One"), available)
        XCTAssertEqual(SAEditorAppearanceThemeSwitcher.pickerNames(available: available, selected: "dark one"), available)
        XCTAssertEqual(SAEditorAppearanceThemeSwitcher.pickerNames(available: available, selected: "Gone"), available + ["Gone"])
    }

    /// Verifies a stored name in another case maps to the listed spelling; unknown names pass through.
    func testCanonicalName() {
        let available = ["Default", "Dark One"]
        XCTAssertEqual(SAEditorAppearanceThemeSwitcher.canonicalName("dark one", in: available), "Dark One")
        XCTAssertEqual(SAEditorAppearanceThemeSwitcher.canonicalName("Dark One", in: available), "Dark One")
        XCTAssertEqual(SAEditorAppearanceThemeSwitcher.canonicalName("Gone", in: available), "Gone")
        XCTAssertEqual(SAEditorAppearanceThemeSwitcher.canonicalName("", in: available), "")
    }
}
