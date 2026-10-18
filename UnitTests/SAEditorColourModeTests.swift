//
//  SAEditorColourModeTests.swift
//  Unit Tests
//

import AppKit
import XCTest

final class SAEditorColourModeTests: XCTestCase {

    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "SAEditorColourModeTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    private func store(_ hex: UInt32, _ key: String) {
        let c = NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        defaults.set(SAArchiving.archivedData(forColor: c), forKey: key)
    }

    private func storeAll(_ hex: UInt32, name: String) {
        for key in SAEditorThemeLoader.colourKeys { store(hex, key) }
        defaults.set(name, forKey: SAEditorThemeLoader.themeNameKey)
    }

    private func liveRed(_ key: String = SAEditorThemeLoader.backgroundColourKey) -> Int {
        let c = SAArchiving.color(from: defaults.data(forKey: key))!.usingColorSpace(.sRGB)!
        return Int((c.redComponent * 255).rounded())
    }

    func testEnteringCustomiseWithoutSnapshotKeepsCurrentColoursAndSeedsSnapshot() {
        defaults.set(true, forKey: SAEditorAppearanceThemeSwitcher.matchesAppearanceKey)
        storeAll(0x151515, name: "Claude Dark")
        SAEditorColourMode.enterCustomise(in: defaults)
        XCTAssertFalse(SAEditorColourMode.isFollowingMacOS(defaults))
        XCTAssertEqual(liveRed(), 0x15)
        XCTAssertEqual(defaults.string(forKey: SAEditorThemeLoader.themeNameKey), "Claude Dark")
        let snapshot = defaults.dictionary(forKey: SAEditorColourMode.customColoursKey) as? [String: Data]
        XCTAssertEqual(snapshot?.count, SAEditorThemeLoader.colourKeys.count)
        XCTAssertEqual(defaults.string(forKey: SAEditorColourMode.customThemeNameKey), "Claude Dark")
    }

    func testLeavingCustomiseSavesTheLiveSetAndTurnsFollowOn() {
        defaults.set(false, forKey: SAEditorAppearanceThemeSwitcher.matchesAppearanceKey)
        storeAll(0x2E3440, name: "User-defined")
        SAEditorColourMode.leaveCustomise(in: defaults)
        XCTAssertTrue(SAEditorColourMode.isFollowingMacOS(defaults))
        XCTAssertEqual(defaults.string(forKey: SAEditorColourMode.customThemeNameKey), "User-defined")
        let snapshot = defaults.dictionary(forKey: SAEditorColourMode.customColoursKey) as? [String: Data]
        XCTAssertNotNil(snapshot?[SAEditorThemeLoader.backgroundColourKey])
    }

    func testRoundTripKeepsCustomColours() {
        defaults.set(false, forKey: SAEditorAppearanceThemeSwitcher.matchesAppearanceKey)
        storeAll(0x2E3440, name: "User-defined")
        SAEditorColourMode.leaveCustomise(in: defaults)
        storeAll(0xFCFCFB, name: "Claude Light")          // what Follow macOS loads
        SAEditorColourMode.enterCustomise(in: defaults)
        XCTAssertEqual(liveRed(), 0x2E)
        XCTAssertEqual(defaults.string(forKey: SAEditorThemeLoader.themeNameKey), "User-defined")
        SAEditorColourMode.leaveCustomise(in: defaults)
        storeAll(0x151515, name: "Claude Dark")
        SAEditorColourMode.enterCustomise(in: defaults)
        XCTAssertEqual(liveRed(), 0x2E)
    }

    func testIncompleteSnapshotIsIgnored() {
        defaults.set(true, forKey: SAEditorAppearanceThemeSwitcher.matchesAppearanceKey)
        storeAll(0x151515, name: "Claude Dark")
        defaults.set([SAEditorThemeLoader.backgroundColourKey: SAArchiving.archivedData(forColor: .red)!], forKey: SAEditorColourMode.customColoursKey)
        XCTAssertFalse(SAEditorColourMode.restoreSnapshot(in: defaults))
        SAEditorColourMode.enterCustomise(in: defaults)
        XCTAssertEqual(liveRed(), 0x15)
    }

    func testEnterAndLeaveAreNoOpsInTheirOwnMode() {
        defaults.set(false, forKey: SAEditorAppearanceThemeSwitcher.matchesAppearanceKey)
        storeAll(0x2E3440, name: "Nord")
        SAEditorColourMode.enterCustomise(in: defaults)          // already customising
        XCTAssertNil(defaults.object(forKey: SAEditorColourMode.customColoursKey))
        defaults.set(true, forKey: SAEditorAppearanceThemeSwitcher.matchesAppearanceKey)
        SAEditorColourMode.leaveCustomise(in: defaults)          // already following
        XCTAssertNil(defaults.object(forKey: SAEditorColourMode.customColoursKey))
    }

    func testSnapshotWithoutALiveThemeNameRestoresAsUserDefined() {
        defaults.set(false, forKey: SAEditorAppearanceThemeSwitcher.matchesAppearanceKey)
        storeAll(0x2E3440, name: "")
        defaults.removeObject(forKey: SAEditorThemeLoader.themeNameKey)
        SAEditorColourMode.leaveCustomise(in: defaults)
        XCTAssertEqual(defaults.string(forKey: SAEditorColourMode.customThemeNameKey), SAClaudeEditorDefaults.customSchemeName)
        storeAll(0xFCFCFB, name: "Claude Light")          // what Follow macOS loads
        SAEditorColourMode.enterCustomise(in: defaults)
        XCTAssertEqual(liveRed(), 0x2E)
        XCTAssertEqual(defaults.string(forKey: SAEditorThemeLoader.themeNameKey), "User-defined")
    }

    // MARK: - Match appearance / Choose / Custom

    private typealias Mode = SAEditorColourMode.Mode
    private var matches: String { SAEditorAppearanceThemeSwitcher.matchesAppearanceKey }
    private var chosen: String { SAEditorColourMode.chosenAppearanceKey }

    /// Existing users keep their mode: Follow on (or never set, registered on) is Match appearance, Follow off is
    /// Custom, and only a stored light/dark choice with Follow on is Choose.
    func testModeFromExistingKeys() {
        SAClaudeEditorDefaults.register(in: defaults)
        XCTAssertEqual(SAEditorColourMode.mode(in: defaults), .matchAppearance, "nothing stored: the registered default")
        defaults.set(true, forKey: matches)
        XCTAssertEqual(SAEditorColourMode.mode(in: defaults), .matchAppearance, "Follow = YES")
        defaults.set(false, forKey: matches)
        XCTAssertEqual(SAEditorColourMode.mode(in: defaults), .custom, "Follow = NO")
        defaults.set("dark", forKey: chosen)
        XCTAssertEqual(SAEditorColourMode.mode(in: defaults), .custom, "a stale choice never beats Custom")
        defaults.set(true, forKey: matches)
        XCTAssertEqual(SAEditorColourMode.mode(in: defaults), .choose(dark: true))
        defaults.set("light", forKey: chosen)
        XCTAssertEqual(SAEditorColourMode.mode(in: defaults), .choose(dark: false))
        defaults.set("sepia", forKey: chosen)
        XCTAssertEqual(SAEditorColourMode.mode(in: defaults), .matchAppearance, "an unknown value is ignored")
    }

    /// Which Claude theme applies for each (mode, app appearance) pair: true = Claude Dark, false = Claude Light.
    func testThemeForEachModeAndAppearance() {
        XCTAssertEqual(Mode.matchAppearance.appliesDark(appIsDark: false), false)
        XCTAssertEqual(Mode.matchAppearance.appliesDark(appIsDark: true), true)
        XCTAssertEqual(Mode.choose(dark: false).appliesDark(appIsDark: false), false)
        XCTAssertEqual(Mode.choose(dark: false).appliesDark(appIsDark: true), false, "light editor in dark mode")
        XCTAssertEqual(Mode.choose(dark: true).appliesDark(appIsDark: false), true, "dark editor in light mode")
        XCTAssertEqual(Mode.choose(dark: true).appliesDark(appIsDark: true), true)
        XCTAssertNil(Mode.custom.appliesDark(appIsDark: false))
        XCTAssertNil(Mode.custom.appliesDark(appIsDark: true))
    }

    /// The pill: 0 Match appearance, 1 Choose, 2 Custom; Choose starts on the theme showing now; a re-pick is no change.
    func testPillPicks() {
        XCTAssertEqual(Mode.matchAppearance.pillIndex, 0)
        XCTAssertEqual(Mode.choose(dark: true).pillIndex, 1)
        XCTAssertEqual(Mode.choose(dark: false).pillIndex, 1)
        XCTAssertEqual(Mode.custom.pillIndex, 2)

        XCTAssertEqual(Mode.picked(index: 1, from: .matchAppearance, appIsDark: true), .choose(dark: true))
        XCTAssertEqual(Mode.picked(index: 1, from: .matchAppearance, appIsDark: false), .choose(dark: false))
        XCTAssertEqual(Mode.picked(index: 1, from: .custom, appIsDark: true), .choose(dark: true))
        XCTAssertEqual(Mode.picked(index: 0, from: .choose(dark: false), appIsDark: true), .matchAppearance)
        XCTAssertEqual(Mode.picked(index: 2, from: .choose(dark: true), appIsDark: false), .custom)
        XCTAssertEqual(Mode.picked(index: 0, from: .custom, appIsDark: false), .matchAppearance)
        XCTAssertNil(Mode.picked(index: 0, from: .matchAppearance, appIsDark: true))
        XCTAssertNil(Mode.picked(index: 1, from: .choose(dark: false), appIsDark: true), "re-picking Choose keeps the tile")
        XCTAssertNil(Mode.picked(index: 2, from: .custom, appIsDark: true))
        XCTAssertNil(Mode.picked(index: 7, from: .custom, appIsDark: true))
    }

    /// Choose and Match appearance both let the switcher load a Claude theme; the choice is its own key.
    func testSetModeWritesTheKeys() {
        SAClaudeEditorDefaults.register(in: defaults)
        SAEditorColourMode.setMode(.choose(dark: false), in: defaults)
        XCTAssertTrue(defaults.bool(forKey: matches))
        XCTAssertEqual(defaults.string(forKey: chosen), "light")
        XCTAssertEqual(SAEditorColourMode.mode(in: defaults), .choose(dark: false))
        SAEditorColourMode.setMode(.choose(dark: true), in: defaults)
        XCTAssertEqual(SAEditorColourMode.mode(in: defaults), .choose(dark: true))
        SAEditorColourMode.setMode(.matchAppearance, in: defaults)
        XCTAssertNil(defaults.object(forKey: chosen))
        XCTAssertEqual(SAEditorColourMode.mode(in: defaults), .matchAppearance)
        SAEditorColourMode.setMode(.choose(dark: true), in: defaults)
        SAEditorColourMode.setMode(.custom, in: defaults)
        XCTAssertFalse(defaults.bool(forKey: matches))
        XCTAssertNil(defaults.object(forKey: chosen))
        XCTAssertEqual(SAEditorColourMode.mode(in: defaults), .custom)
    }

    /// Choose → Custom starts from the chosen theme's colours (no remembered set), as Custom does from Match appearance.
    func testChooseToCustomStartsFromTheChosenTheme() {
        SAClaudeEditorDefaults.register(in: defaults)
        SAEditorColourMode.setMode(.choose(dark: true), in: defaults)
        storeAll(0x151515, name: "Claude Dark")             // what the switcher loads for Choose ▸ Dark
        SAEditorColourMode.setMode(.custom, in: defaults)
        XCTAssertEqual(liveRed(), 0x15)
        XCTAssertEqual(defaults.string(forKey: SAEditorThemeLoader.themeNameKey), "Claude Dark")
    }

    /// Custom → Choose remembers the custom set, and coming back to Custom brings it back.
    func testCustomToChooseAndBackKeepsCustomColours() {
        defaults.set(false, forKey: matches)
        storeAll(0x2E3440, name: "User-defined")
        SAEditorColourMode.setMode(.choose(dark: false), in: defaults)
        XCTAssertEqual(SAEditorColourMode.mode(in: defaults), .choose(dark: false))
        storeAll(0xFCFCFB, name: "Claude Light")
        SAEditorColourMode.setMode(.custom, in: defaults)
        XCTAssertEqual(liveRed(), 0x2E)
        XCTAssertEqual(defaults.string(forKey: SAEditorThemeLoader.themeNameKey), "User-defined")
    }
}
