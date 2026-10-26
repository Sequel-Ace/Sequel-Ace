//
//  SAEditorDefaultsTests.swift
//  Unit Tests
//

import AppKit
import XCTest

final class SAEditorDefaultsTests: XCTestCase {

    private let suite = "SAEditorDefaultsTests"
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

    /// Verifies the registered defaults: matching on, Sequel Ace Light / Sequel Ace Dark.
    func testRegisteredDefaults() {
        SAEditorDefaults.register(in: defaults)
        XCTAssertTrue(defaults.bool(forKey: SAEditorAppearanceThemeSwitcher.matchesAppearanceKey))
        XCTAssertEqual(defaults.string(forKey: SAEditorAppearanceThemeSwitcher.lightThemeKey), "Sequel Ace Light")
        XCTAssertEqual(defaults.string(forKey: SAEditorAppearanceThemeSwitcher.darkThemeKey), "Sequel Ace Dark")
    }

    /// Verifies the persisted names of the one-time flags.
    func testOneTimeFlagNames() {
        XCTAssertEqual(SAEditorDefaults.fontUpdatedKey, "EditorFontUpdatedToSystemMonospace")
        XCTAssertEqual(SAEditorDefaults.themeMatchingUpgradeCheckedKey, "EditorThemeMatchingUpgradeChecked")
    }

    /// Verifies when the font update applies.
    func testShouldUpdateFont() {
        let menlo14 = SAArchiving.archivedData(forFont: NSFont(name: "Menlo-Regular", size: 14)!)
        let menlo12 = SAArchiving.archivedData(forFont: NSFont(name: "Menlo-Regular", size: 12)!)
        XCTAssertTrue(SAEditorDefaults.shouldUpdateFont(alreadyUpdated: false, userFontData: nil))
        XCTAssertTrue(SAEditorDefaults.shouldUpdateFont(alreadyUpdated: false, userFontData: menlo14))
        XCTAssertFalse(SAEditorDefaults.shouldUpdateFont(alreadyUpdated: false, userFontData: menlo12), "a custom font stays")
        XCTAssertFalse(SAEditorDefaults.shouldUpdateFont(alreadyUpdated: true, userFontData: nil), "only once")
    }

    /// Verifies the update writes SF Mono 13 once and records it.
    func testUpdateFontWritesSFMonoOnce() {
        SAEditorDefaults.updateFont(in: defaults, userFontData: nil)
        let font = SAArchiving.font(from: defaults.data(forKey: SAEditorDefaults.fontKey))
        XCTAssertEqual(font, SAEditorDefaults.defaultFont)
        XCTAssertEqual(font?.pointSize, 13)
        XCTAssertTrue(defaults.bool(forKey: SAEditorDefaults.fontUpdatedKey))

        let menlo14 = SAArchiving.archivedData(forFont: NSFont(name: "Menlo-Regular", size: 14)!)
        defaults.set(menlo14, forKey: SAEditorDefaults.fontKey)
        SAEditorDefaults.updateFont(in: defaults, userFontData: menlo14)
        XCTAssertEqual(SAArchiving.font(from: defaults.data(forKey: SAEditorDefaults.fontKey))?.fontName, "Menlo-Regular", "a later deliberate Menlo 14 is kept")
    }

    /// Verifies the editor font's Reset gives the default, SF Mono 13 (monospaced), not the proportional system
    /// font it used to install.
    func testResetEditorFontGivesSFMono13() {
        let helvetica = SAArchiving.archivedData(forFont: NSFont(name: "Helvetica", size: 18)!)
        defaults.set(helvetica, forKey: SAEditorDefaults.fontKey)
        SAEditorDefaults.resetEditorFont(in: defaults)
        let font = SAArchiving.font(from: defaults.data(forKey: SAEditorDefaults.fontKey))
        XCTAssertEqual(font, NSFont.monospacedSystemFont(ofSize: 13, weight: .regular))
        XCTAssertEqual(font?.pointSize, 13)
        XCTAssertTrue(font?.isFixedPitch ?? false, "monospaced")
        XCTAssertNotEqual(font, NSFont.systemFont(ofSize: 13), "not the proportional system font")
    }

    // MARK: - Theme-matching upgrade guard

    private var matches: String { SAEditorAppearanceThemeSwitcher.matchesAppearanceKey }

    /// Registers the defaults, then runs the upgrade guard against the suite's own persistent domain.
    private func runUpgrade() {
        SAEditorDefaults.register(in: defaults)
        SAEditorDefaults.upgradeThemeMatching(in: defaults, userDomain: defaults.persistentDomain(forName: suite))
    }

    /// The registered (stock) colors, as the app's plist registers them.
    private func registerStockColors() {
        defaults.register(defaults: [SAEditorThemeLoader.keywordColorKey: SAArchiving.archivedData(forColor: .blue)!])
    }

    /// Verifies an existing user on the pane's "User-defined" scheme keeps their hand-edited colors.
    func testUpgradeTurnsMatchingOffForUserDefinedScheme() {
        defaults.set("User-defined", forKey: SAEditorThemeLoader.themeNameKey)
        runUpgrade()
        XCTAssertFalse(defaults.bool(forKey: matches))
        XCTAssertTrue(defaults.bool(forKey: SAEditorDefaults.themeMatchingUpgradeCheckedKey))
    }

    /// Verifies a user with no theme name but their own color keys keeps them.
    func testUpgradeTurnsMatchingOffForUnnamedCustomColors() {
        registerStockColors()
        defaults.set(SAArchiving.archivedData(forColor: .red), forKey: SAEditorThemeLoader.keywordColorKey)
        runUpgrade()
        XCTAssertFalse(defaults.bool(forKey: matches))
    }

    /// Verifies a user with no theme name whose stored colors are the stock ones counts as on the default colors.
    func testUpgradeLeavesUnnamedStockColorsToTheDefault() {
        registerStockColors()
        defaults.set(SAArchiving.archivedData(forColor: .blue), forKey: SAEditorThemeLoader.keywordColorKey)
        runUpgrade()
        XCTAssertTrue(defaults.bool(forKey: matches))
        XCTAssertNil(defaults.persistentDomain(forName: suite)?[matches])
    }

    /// Verifies a user on a named theme keeps it: matching off, theme name untouched.
    func testUpgradeTurnsMatchingOffForANamedTheme() {
        for name in ["Nord", "Sequel Ace Dark", "Dark Ace"] {
            defaults.removePersistentDomain(forName: suite)
            defaults.set(name, forKey: SAEditorThemeLoader.themeNameKey)
            runUpgrade()
            XCTAssertFalse(defaults.bool(forKey: matches), name)
            XCTAssertEqual(defaults.persistentDomain(forName: suite)?[matches] as? Bool, false, name)
            XCTAssertEqual(defaults.string(forKey: SAEditorThemeLoader.themeNameKey), name)
        }
    }

    /// Verifies a user on the "Default" scheme gets the registered default (matching on).
    func testUpgradeLeavesTheDefaultSchemeToTheDefault() {
        for name in ["Default", "default"] {
            defaults.removePersistentDomain(forName: suite)
            defaults.set(name, forKey: SAEditorThemeLoader.themeNameKey)
            runUpgrade()
            XCTAssertTrue(defaults.bool(forKey: matches), name)
            XCTAssertNil(defaults.persistentDomain(forName: suite)?[matches], name)
        }
    }

    /// Verifies a fresh user gets the registered default (matching on).
    func testUpgradeLeavesFreshUserAlone() {
        runUpgrade()
        XCTAssertTrue(defaults.bool(forKey: matches))
        XCTAssertNil(defaults.persistentDomain(forName: suite)?[matches])
        XCTAssertTrue(defaults.bool(forKey: SAEditorDefaults.themeMatchingUpgradeCheckedKey))
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
        defaults.set("Nord", forKey: SAEditorThemeLoader.themeNameKey)
        runUpgrade()
        XCTAssertTrue(defaults.bool(forKey: matches))
        XCTAssertNil(defaults.persistentDomain(forName: suite)?[matches])
    }

    // MARK: - The launch step

    /// Verifies the launch step runs both updates on a fresh install, reading the user's domain once.
    func testOneTimeUpdatesRunOnAFreshInstall() {
        SAEditorDefaults.register(in: defaults)
        var reads = 0
        SAEditorDefaults.runOneTimeUpdates(in: defaults) { reads += 1; return self.defaults.persistentDomain(forName: self.suite) }
        XCTAssertEqual(reads, 1)
        XCTAssertEqual(SAArchiving.font(from: defaults.data(forKey: SAEditorDefaults.fontKey)), SAEditorDefaults.defaultFont)
        XCTAssertTrue(defaults.bool(forKey: SAEditorDefaults.fontUpdatedKey))
        XCTAssertTrue(defaults.bool(forKey: SAEditorDefaults.themeMatchingUpgradeCheckedKey))
        XCTAssertTrue(defaults.bool(forKey: matches))
    }

    /// Verifies that once both flags are set the launch step returns without reading the user's domain, and
    /// changes nothing: a named theme set later does not turn matching off.
    func testOneTimeUpdatesSkipTheDomainOnceBothHaveRun() {
        SAEditorDefaults.register(in: defaults)
        defaults.set(true, forKey: SAEditorDefaults.fontUpdatedKey)
        defaults.set(true, forKey: SAEditorDefaults.themeMatchingUpgradeCheckedKey)
        defaults.set("Sequel Ace Dark", forKey: SAEditorThemeLoader.themeNameKey)
        let before = defaults.persistentDomain(forName: suite) as NSDictionary?
        var reads = 0
        SAEditorDefaults.runOneTimeUpdates(in: defaults) { reads += 1; return self.defaults.persistentDomain(forName: self.suite) }
        XCTAssertEqual(reads, 0)
        XCTAssertEqual(defaults.persistentDomain(forName: suite) as NSDictionary?, before)
        XCTAssertTrue(defaults.bool(forKey: matches))
    }

    /// Verifies one flag missing is enough to run the step; the other update still runs only once.
    func testOneTimeUpdatesRunWhenOneFlagIsMissing() {
        SAEditorDefaults.register(in: defaults)
        defaults.set(true, forKey: SAEditorDefaults.fontUpdatedKey)
        let menlo14 = SAArchiving.archivedData(forFont: NSFont(name: "Menlo-Regular", size: 14)!)
        defaults.set(menlo14, forKey: SAEditorDefaults.fontKey)
        defaults.set("Nord", forKey: SAEditorThemeLoader.themeNameKey)
        var reads = 0
        SAEditorDefaults.runOneTimeUpdates(in: defaults) { reads += 1; return self.defaults.persistentDomain(forName: self.suite) }
        XCTAssertEqual(reads, 1)
        XCTAssertEqual(SAArchiving.font(from: defaults.data(forKey: SAEditorDefaults.fontKey))?.fontName, "Menlo-Regular", "font already updated")
        XCTAssertFalse(defaults.bool(forKey: matches), "named theme kept")
    }

    /// Verifies the Light/Dark picks and matching survive a relaunch: a fresh UserDefaults on the same suite runs
    /// the same launch steps, and the stored values stay in both the resolved and the persistent values.
    func testLightAndDarkPicksSurviveARelaunch() {
        SAEditorDefaults.register(in: defaults)
        SAEditorDefaults.runOneTimeUpdates(in: defaults) { self.defaults.persistentDomain(forName: self.suite) }
        defaults.set("Nord", forKey: SAEditorAppearanceThemeSwitcher.lightThemeKey)
        defaults.set("Monokai", forKey: SAEditorAppearanceThemeSwitcher.darkThemeKey)

        let relaunched = UserDefaults(suiteName: suite)!
        SAEditorDefaults.register(in: relaunched)
        SAEditorDefaults.runOneTimeUpdates(in: relaunched) { relaunched.persistentDomain(forName: self.suite) }
        XCTAssertEqual(relaunched.string(forKey: SAEditorAppearanceThemeSwitcher.lightThemeKey), "Nord")
        XCTAssertEqual(relaunched.string(forKey: SAEditorAppearanceThemeSwitcher.darkThemeKey), "Monokai")
        XCTAssertTrue(relaunched.bool(forKey: matches))
        let domain = relaunched.persistentDomain(forName: suite) ?? [:]
        XCTAssertEqual(domain[SAEditorAppearanceThemeSwitcher.lightThemeKey] as? String, "Nord")
        XCTAssertEqual(domain[SAEditorAppearanceThemeSwitcher.darkThemeKey] as? String, "Monokai")
    }

    /// Verifies the bundled themes parse and display as the intended sRGB colors: the files store
    /// compensated hexes because the .spTheme parser creates calibrated (Generic RGB) colors.
    func testBundledThemesParse() throws {
        let themes = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("SharedSupport/Default Themes")
        // Target sRGB background and SQL keyword color per theme.
        let expected: [(name: String, background: [Int], keyword: [Int])] = [
            ("Sequel Ace Dark", [0x15, 0x15, 0x15], [0x6D, 0xA7, 0xEC]),
            ("Sequel Ace Light", [0xFC, 0xFC, 0xFB], [0x18, 0x4F, 0x95]),
        ]
        func srgb(_ key: String) -> [Int]? {
            guard let c = SAArchiving.color(from: defaults.data(forKey: key))?.usingColorSpace(.sRGB) else { return nil }
            return [c.redComponent, c.greenComponent, c.blueComponent].map { Int(($0 * 255).rounded()) }
        }
        for item in expected {
            XCTAssertEqual(SAEditorThemeLoader.loadTheme(atPath: themes.appendingPathComponent(item.name + ".spTheme").path, into: defaults), 11, item.name)
            for (key, target) in [(SAEditorThemeLoader.backgroundColorKey, item.background), (SAEditorThemeLoader.keywordColorKey, item.keyword)] {
                guard let shown = srgb(key) else { XCTFail("\(item.name) \(key) missing"); continue }
                for (got, want) in zip(shown, target) { XCTAssertLessThanOrEqual(abs(got - want), 1, "\(item.name) \(key)") }
            }
        }
    }
}
