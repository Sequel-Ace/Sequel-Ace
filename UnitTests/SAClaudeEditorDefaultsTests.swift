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

    /// Verifies the bundled Claude themes parse to their backgrounds.
    func testBundledClaudeThemesParse() throws {
        let themes = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("SharedSupport/Default Themes")
        for (name, red) in [("Claude Dark", 0x15), ("Claude Light", 0xFC)] {
            XCTAssertEqual(SAEditorThemeLoader.loadTheme(atPath: themes.appendingPathComponent(name + ".spTheme").path, into: defaults), 11, name)
            let bg = SAArchiving.color(from: defaults.data(forKey: SAEditorThemeLoader.backgroundColourKey))?.usingColorSpace(.genericRGB)
            XCTAssertEqual(Int(((bg?.redComponent ?? -1) * 255).rounded()), red, name)
        }
    }
}
