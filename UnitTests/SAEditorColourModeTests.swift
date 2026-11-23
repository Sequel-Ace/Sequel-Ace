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
}
