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
    private var switcher: SAEditorAppearanceThemeSwitcher!

    override func setUpWithError() throws {
        UserDefaults().removePersistentDomain(forName: suite)
        defaults = UserDefaults(suiteName: suite)
        SAEditorAppearanceThemeSwitcher.register(in: defaults)
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try writeTheme("Light One", background: "#FCFCFB")
        try writeTheme("Dark One", background: "#151515")
        switcher = SAEditorAppearanceThemeSwitcher(defaults: defaults)
        switcher.themesDirectory = dir.path
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
        UserDefaults().removePersistentDomain(forName: suite)
    }

    private func writeTheme(_ name: String, background: String) throws {
        let plist: [String: Any] = ["settings": [["settings": ["background": background, "foreground": "#808080"]]]]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: dir.appendingPathComponent(name + ".spTheme"))
    }

    private func backgroundRed() -> Int {
        let c = SAArchiving.color(from: defaults.data(forKey: SAEditorThemeLoader.backgroundColourKey))?.usingColorSpace(.genericRGB)
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

    /// Verifies Layer 1's neutral registered defaults.
    func testNeutralDefaults() {
        XCTAssertFalse(defaults.bool(forKey: SAEditorAppearanceThemeSwitcher.matchesAppearanceKey))
        XCTAssertEqual(defaults.string(forKey: SAEditorAppearanceThemeSwitcher.lightThemeKey), "Default")
        XCTAssertEqual(defaults.string(forKey: SAEditorAppearanceThemeSwitcher.darkThemeKey), "Dark Ace")
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

    /// Verifies "Default" resets to the registered colours instead of reading a file.
    func testDefaultSchemeUsesRegisteredColours() {
        defaults.register(defaults: [SAEditorThemeLoader.backgroundColourKey:
                                        SAArchiving.archivedData(forColor: NSColor(calibratedWhite: 1, alpha: 1))!])
        defaults.set(true, forKey: SAEditorAppearanceThemeSwitcher.matchesAppearanceKey)
        defaults.set("Default", forKey: SAEditorAppearanceThemeSwitcher.lightThemeKey)
        XCTAssertTrue(switcher.apply(isDark: false))
        XCTAssertEqual(backgroundRed(), 255)
        XCTAssertEqual(defaults.string(forKey: SAEditorThemeLoader.themeNameKey), "Default")
    }

    /// Verifies a missing theme file leaves colours and the theme name untouched.
    func testMissingThemeFileLeavesColoursAlone() {
        defaults.set(SAArchiving.archivedData(forColor: NSColor(calibratedRed: 0.2, green: 0.2, blue: 0.2, alpha: 1)), forKey: SAEditorThemeLoader.backgroundColourKey)
        defaults.set("Before", forKey: SAEditorThemeLoader.themeNameKey)
        defaults.set(true, forKey: SAEditorAppearanceThemeSwitcher.matchesAppearanceKey)
        defaults.set("Gone", forKey: SAEditorAppearanceThemeSwitcher.darkThemeKey)
        XCTAssertFalse(switcher.apply(isDark: true))
        XCTAssertEqual(backgroundRed(), 51)
        XCTAssertEqual(defaults.string(forKey: SAEditorThemeLoader.themeNameKey), "Before")
    }

    /// Verifies a manual colour edit or theme pick turns matching off.
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
}
