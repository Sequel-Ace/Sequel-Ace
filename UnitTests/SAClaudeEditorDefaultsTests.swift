//
//  SAClaudeEditorDefaultsTests.swift
//  Unit Tests
//

import AppKit
import XCTest

final class SAClaudeEditorDefaultsTests: XCTestCase {

    private let suite = "SAClaudeEditorDefaultsTests"
    private var defaults: UserDefaults!
    private var registered: SARegistrationDomainSnapshot!

    override func setUp() {
        registered = SARegistrationDomainSnapshot()
        UserDefaults().removePersistentDomain(forName: suite)
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: suite)
        registered.restore()
    }

    /// Verifies Layer 2's defaults override Layer 1's neutral ones.
    func testClaudeDefaultsOverrideTheNeutralOnes() {
        SAEditorAppearanceThemeSwitcher.register(in: defaults)
        SAClaudeEditorDefaults.register(in: defaults)
        XCTAssertTrue(defaults.bool(forKey: SAEditorAppearanceThemeSwitcher.matchesAppearanceKey))
        XCTAssertEqual(defaults.string(forKey: SAEditorAppearanceThemeSwitcher.lightThemeKey), "Claude Light")
        XCTAssertEqual(defaults.string(forKey: SAEditorAppearanceThemeSwitcher.darkThemeKey), "Claude Dark")
    }

    /// Verifies when the font migration applies.
    func testShouldMigrateFont() {
        let menlo14 = SAArchiving.archivedData(forFont: NSFont(name: "Menlo-Regular", size: 14)!)
        let menlo12 = SAArchiving.archivedData(forFont: NSFont(name: "Menlo-Regular", size: 12)!)
        XCTAssertTrue(SAClaudeEditorDefaults.shouldMigrateFont(alreadyMigrated: false, userFontData: nil))
        XCTAssertTrue(SAClaudeEditorDefaults.shouldMigrateFont(alreadyMigrated: false, userFontData: menlo14))
        XCTAssertFalse(SAClaudeEditorDefaults.shouldMigrateFont(alreadyMigrated: false, userFontData: menlo12), "a custom font stays")
        XCTAssertFalse(SAClaudeEditorDefaults.shouldMigrateFont(alreadyMigrated: true, userFontData: nil), "only once")
    }

    /// Verifies the migration writes SF Mono 13 once and records it.
    func testMigrateFontWritesSFMonoOnce() {
        SAClaudeEditorDefaults.migrateFont(in: defaults, userFontData: nil)
        let font = SAArchiving.font(from: defaults.data(forKey: SAClaudeEditorDefaults.fontKey))
        XCTAssertEqual(font, SAClaudeEditorDefaults.claudeFont)
        XCTAssertEqual(font?.pointSize, 13)
        XCTAssertTrue(defaults.bool(forKey: SAClaudeEditorDefaults.fontMigratedKey))

        let menlo14 = SAArchiving.archivedData(forFont: NSFont(name: "Menlo-Regular", size: 14)!)
        defaults.set(menlo14, forKey: SAClaudeEditorDefaults.fontKey)
        SAClaudeEditorDefaults.migrateFont(in: defaults, userFontData: menlo14)
        XCTAssertEqual(SAArchiving.font(from: defaults.data(forKey: SAClaudeEditorDefaults.fontKey))?.fontName, "Menlo-Regular", "a later deliberate Menlo 14 is kept")
    }

    /// Verifies the editor font's Reset gives the Claude default, SF Mono 13 (monospaced), not the proportional system
    /// font it used to install.
    func testResetEditorFontGivesSFMono13() {
        let helvetica = SAArchiving.archivedData(forFont: NSFont(name: "Helvetica", size: 18)!)
        defaults.set(helvetica, forKey: SAClaudeEditorDefaults.fontKey)
        SAClaudeEditorDefaults.resetEditorFont(in: defaults)
        let font = SAArchiving.font(from: defaults.data(forKey: SAClaudeEditorDefaults.fontKey))
        XCTAssertEqual(font, NSFont.monospacedSystemFont(ofSize: 13, weight: .regular))
        XCTAssertEqual(font?.pointSize, 13)
        XCTAssertTrue(font?.isFixedPitch ?? false, "monospaced")
        XCTAssertNotEqual(font, NSFont.systemFont(ofSize: 13), "not the proportional system font")
    }

    // MARK: - Theme-matching upgrade guard

    private var matches: String { SAEditorAppearanceThemeSwitcher.matchesAppearanceKey }

    /// Registers the Claude defaults, then runs the upgrade guard against the suite's own persistent domain.
    private func runUpgrade() {
        SAClaudeEditorDefaults.register(in: defaults)
        SAClaudeEditorDefaults.upgradeThemeMatching(in: defaults, userDomain: defaults.persistentDomain(forName: suite))
    }

    /// Verifies an existing user on the pane's "User-defined" scheme keeps their hand-edited colours.
    func testUpgradeTurnsMatchingOffForUserDefinedScheme() {
        defaults.set("User-defined", forKey: SAEditorThemeLoader.themeNameKey)
        runUpgrade()
        XCTAssertFalse(defaults.bool(forKey: matches))
        XCTAssertTrue(defaults.bool(forKey: SAClaudeEditorDefaults.themeUpgradeCheckedKey))
    }

    /// Verifies a user with no theme name but their own colour keys keeps them.
    func testUpgradeTurnsMatchingOffForUnnamedCustomColours() {
        defaults.set(SAArchiving.archivedData(forColor: .red), forKey: SAEditorThemeLoader.keywordColourKey)
        runUpgrade()
        XCTAssertFalse(defaults.bool(forKey: matches))
    }

    /// Verifies a user on a named theme is left to the registered default (matching on).
    func testUpgradeLeavesNamedThemeAlone() {
        defaults.set("Nord", forKey: SAEditorThemeLoader.themeNameKey)
        defaults.set(SAArchiving.archivedData(forColor: .red), forKey: SAEditorThemeLoader.keywordColourKey)
        runUpgrade()
        XCTAssertTrue(defaults.bool(forKey: matches))
        XCTAssertNil(defaults.persistentDomain(forName: suite)?[matches])
    }

    /// Verifies a fresh user gets the registered default (matching on).
    func testUpgradeLeavesFreshUserAlone() {
        runUpgrade()
        XCTAssertTrue(defaults.bool(forKey: matches))
        XCTAssertNil(defaults.persistentDomain(forName: suite)?[matches])
        XCTAssertTrue(defaults.bool(forKey: SAClaudeEditorDefaults.themeUpgradeCheckedKey))
    }

    /// Verifies an explicit choice already in the user's domain is never overridden.
    func testUpgradeLeavesExplicitChoiceAlone() {
        defaults.set("User-defined", forKey: SAEditorThemeLoader.themeNameKey)
        defaults.set(true, forKey: matches)
        runUpgrade()
        XCTAssertTrue(defaults.bool(forKey: matches))
    }

    /// Verifies the guard runs only once.
    func testUpgradeRunsOnlyOnce() {
        runUpgrade()
        defaults.set("User-defined", forKey: SAEditorThemeLoader.themeNameKey)
        runUpgrade()
        XCTAssertTrue(defaults.bool(forKey: matches))
        XCTAssertNil(defaults.persistentDomain(forName: suite)?[matches])
    }

    /// Verifies the bundled Claude themes parse and DISPLAY as Claude's sRGB colours: the files store
    /// compensated hexes because the .spTheme parser creates calibrated (Generic RGB) colours.
    func testBundledClaudeThemesParse() throws {
        let themes = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("SharedSupport/Default Themes")
        // Target sRGB background and SQL keyword colour per theme.
        let expected: [(name: String, background: [Int], keyword: [Int])] = [
            ("Claude Dark", [0x15, 0x15, 0x15], [0x6D, 0xA7, 0xEC]),
            ("Claude Light", [0xFC, 0xFC, 0xFB], [0x18, 0x4F, 0x95]),
        ]
        func srgb(_ key: String) -> [Int]? {
            guard let c = SAArchiving.color(from: defaults.data(forKey: key))?.usingColorSpace(.sRGB) else { return nil }
            return [c.redComponent, c.greenComponent, c.blueComponent].map { Int(($0 * 255).rounded()) }
        }
        for item in expected {
            XCTAssertEqual(SAEditorThemeLoader.loadTheme(atPath: themes.appendingPathComponent(item.name + ".spTheme").path, into: defaults), 11, item.name)
            for (key, target) in [(SAEditorThemeLoader.backgroundColourKey, item.background), (SAEditorThemeLoader.keywordColourKey, item.keyword)] {
                guard let shown = srgb(key) else { XCTFail("\(item.name) \(key) missing"); continue }
                for (got, want) in zip(shown, target) { XCTAssertLessThanOrEqual(abs(got - want), 1, "\(item.name) \(key)") }
            }
        }
    }

    /// Verifies the console-only appearance override is cleared so the console follows the editor.
    func testConsoleOverrideIsResetSoTheConsoleMatchesTheEditor() {
        defaults.set(true, forKey: SAClaudeEditorDefaults.consoleOverrideKey)
        SAClaudeEditorDefaults.resetConsoleOverride(in: defaults)
        XCTAssertNil(defaults.persistentDomain(forName: suite)?[SAClaudeEditorDefaults.consoleOverrideKey])
        XCTAssertFalse(defaults.bool(forKey: SAClaudeEditorDefaults.consoleOverrideKey))
    }

    /// Verifies Follow macOS always reads the bundled pair: stored light/dark theme names are cleared.
    func testFollowPairIsResetToTheClaudeThemes() {
        SAClaudeEditorDefaults.register(in: defaults)
        defaults.set("Nord", forKey: SAEditorAppearanceThemeSwitcher.lightThemeKey)
        defaults.set("Dracula", forKey: SAEditorAppearanceThemeSwitcher.darkThemeKey)
        SAClaudeEditorDefaults.resetFollowPair(in: defaults)
        XCTAssertNil(defaults.persistentDomain(forName: suite)?[SAEditorAppearanceThemeSwitcher.lightThemeKey])
        XCTAssertNil(defaults.persistentDomain(forName: suite)?[SAEditorAppearanceThemeSwitcher.darkThemeKey])
        XCTAssertEqual(defaults.string(forKey: SAEditorAppearanceThemeSwitcher.lightThemeKey), "Claude Light")
        XCTAssertEqual(defaults.string(forKey: SAEditorAppearanceThemeSwitcher.darkThemeKey), "Claude Dark")
    }

    /// Choose survives a relaunch: the launch-time resets leave the chosen appearance alone.
    func testChooseSurvivesTheLaunchResets() {
        SAEditorAppearanceThemeSwitcher.register(in: defaults)
        SAClaudeEditorDefaults.register(in: defaults)
        SAEditorColourMode.setMode(.choose(dark: false), in: defaults)
        SAClaudeEditorDefaults.upgradeThemeMatching(in: defaults, userDomain: defaults.persistentDomain(forName: suite))
        SAClaudeEditorDefaults.resetConsoleOverride(in: defaults)
        SAClaudeEditorDefaults.resetFollowPair(in: defaults)
        XCTAssertEqual(SAEditorColourMode.mode(in: defaults), .choose(dark: false))
    }
}
