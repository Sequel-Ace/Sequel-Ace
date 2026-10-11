//
//  SAClaudeEditorDefaultsTests.swift
//  Unit Tests
//

import AppKit
import XCTest

final class SAClaudeEditorDefaultsTests: XCTestCase {

    private let suite = "SAClaudeEditorDefaultsTests"
    private var defaults: UserDefaults!

    override func setUp() {
        UserDefaults().removePersistentDomain(forName: suite)
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() { UserDefaults().removePersistentDomain(forName: suite) }

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
