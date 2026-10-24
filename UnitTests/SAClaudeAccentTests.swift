//
//  SAClaudeAccentTests.swift
//  Unit Tests
//

import AppKit
import XCTest

final class SAClaudeAccentTests: XCTestCase {

    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "SAClaudeAccentTests." + UUID().uuidString
        defaults = UserDefaults(suiteName: suiteName)
        clearStandardAccent()
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        clearStandardAccent()
        super.tearDown()
    }

    /// The accessors that draw read `.standard`; no test may leave an accent there.
    private func clearStandardAccent() {
        UserDefaults.standard.removeObject(forKey: SAClaudeAccent.defaultsKey)
        SAClaudeAccent.invalidateCache()
    }

    private func srgb(_ hex: UInt32) -> NSColor { SAClaudeStyle.srgb(hex) }

    private func components(_ c: NSColor) -> [CGFloat] {
        let s = c.usingColorSpace(.sRGB)!
        return [s.redComponent, s.greenComponent, s.blueComponent]
    }

    private func assertSame(_ a: NSColor, _ b: NSColor, file: StaticString = #filePath, line: UInt = #line) {
        for (x, y) in zip(components(a), components(b)) { XCTAssertEqual(x, y, accuracy: 0.001, file: file, line: line) }
    }

    func testAbsentStoredColourFallsBackToClay() {
        XCTAssertNil(SAClaudeAccent.stored(in: defaults))
        assertSame(SAClaudeAccent.accent(in: defaults), SAClaudeAccent.clayAccent)
        assertSame(SAClaudeAccent.fill(in: defaults), SAClaudeAccent.clayFill)
        assertSame(SAClaudeAccent.clayAccent, srgb(0xD97757))
        assertSame(SAClaudeAccent.clayFill, srgb(0xC6613F))
    }

    func testStoredColourIsAccentAndFill() {
        let blue = srgb(0x2A78D6)
        SAClaudeAccent.store(blue, in: defaults)
        assertSame(SAClaudeAccent.stored(in: defaults)!, blue)
        assertSame(SAClaudeAccent.accent(in: defaults), blue)
        assertSame(SAClaudeAccent.fill(in: defaults), blue)
    }

    func testStoringADeviceColourReadsBackAsSRGB() {
        let displayP3 = NSColor(colorSpace: .displayP3, components: [0.2, 0.5, 0.8, 1], count: 4)
        SAClaudeAccent.store(displayP3, in: defaults)
        let stored = SAClaudeAccent.stored(in: defaults)!
        XCTAssertEqual(stored.colorSpace, .sRGB)
        assertSame(stored, displayP3)
    }

    func testStoringNilResets() {
        SAClaudeAccent.store(srgb(0x2A78D6), in: defaults)
        SAClaudeAccent.store(nil, in: defaults)
        XCTAssertNil(SAClaudeAccent.stored(in: defaults))
        XCTAssertNil(defaults.object(forKey: SAClaudeAccent.defaultsKey))
        assertSame(SAClaudeAccent.accent(in: defaults), SAClaudeAccent.clayAccent)
        assertSame(SAClaudeAccent.fill(in: defaults), SAClaudeAccent.clayFill)
    }

    func testStorePostsDidChangeNotification() {
        let wrote = XCTNSNotificationExpectation(name: SAClaudeAccent.didChangeNotification)
        SAClaudeAccent.store(srgb(0x2A78D6), in: defaults)
        wait(for: [wrote], timeout: 1)
        let reset = XCTNSNotificationExpectation(name: SAClaudeAccent.didChangeNotification)
        SAClaudeAccent.store(nil, in: defaults)
        wait(for: [reset], timeout: 1)
    }

    func testFillPressedMixesTowardsWhiteInDarkAndBlackInLight() {
        SAClaudeAccent.store(srgb(0x000000), in: defaults)
        XCTAssertEqual(components(SAClaudeAccent.fillPressed(darkTheme: true, in: defaults))[0], 0.12, accuracy: 0.005)
        SAClaudeAccent.store(srgb(0xFFFFFF), in: defaults)
        XCTAssertEqual(components(SAClaudeAccent.fillPressed(darkTheme: false, in: defaults))[0], 0.88, accuracy: 0.005)
    }

    func testRelativeLuminance() {
        XCTAssertEqual(SAClaudeAccent.relativeLuminance(srgb(0xFFFFFF)), 1, accuracy: 0.001)
        XCTAssertEqual(SAClaudeAccent.relativeLuminance(srgb(0x000000)), 0, accuracy: 0.001)
        // WCAG: #C6613F linearises to 0.209 (the brief's 0.25 is not what the formula gives).
        XCTAssertEqual(SAClaudeAccent.relativeLuminance(srgb(0xC6613F)), 0.209, accuracy: 0.005)
    }

    func testOnAccentIsWhiteForClayAndNearBlackForLightAndMidAccents() {
        assertSame(SAClaudeAccent.onAccent(in: defaults), srgb(0xFFFFFF))
        let expectations: [(UInt32, UInt32)] = [(0xFFE066, 0x1A1A1A), (0xF5A623, 0x1A1A1A), (0x1F4E9C, 0xFFFFFF), (0xD97757, 0x1A1A1A)]
        for (fill, title) in expectations {
            SAClaudeAccent.store(srgb(fill), in: defaults)
            assertSame(SAClaudeAccent.onAccent(in: defaults), srgb(title))
        }
    }

    func testOnAccentHasTheBetterContrastExceptWhiteKeepsClay() {
        func contrast(_ a: NSColor, _ b: NSColor) -> CGFloat {
            let (x, y) = (SAClaudeAccent.relativeLuminance(a), SAClaudeAccent.relativeLuminance(b))
            return (max(x, y) + 0.05) / (min(x, y) + 0.05)
        }
        // Whatever the fill, the chosen title is within the preference margin of the better one.
        for hex: UInt32 in [0x000000, 0x1F4E9C, 0x2A78D6, 0x7161E0, 0x008300, 0xC6613F, 0xD97757, 0xF5A623, 0xFFE066, 0xFFFFFF] {
            let fill = srgb(hex)
            let chosen = SAClaudeAccent.onAccent(fill: fill)
            let best = max(contrast(fill, srgb(0xFFFFFF)), contrast(fill, SAClaudeAccent.nearBlack))
            XCTAssertGreaterThanOrEqual(contrast(fill, chosen) * 1.25, best, String(format: "#%06X", hex))
        }
    }

    func testStandardAccessorsReadStoredColourThroughTheCache() {
        assertSame(SAClaudeAccent.accent, SAClaudeAccent.clayAccent)
        SAClaudeAccent.store(srgb(0x2A78D6), in: .standard)
        assertSame(SAClaudeAccent.accent, srgb(0x2A78D6))
        assertSame(SAClaudeAccent.fill, srgb(0x2A78D6))
        SAClaudeAccent.store(nil, in: .standard)
        assertSame(SAClaudeAccent.accent, SAClaudeAccent.clayAccent)
        assertSame(SAClaudeAccent.fill, SAClaudeAccent.clayFill)
    }

    func testCacheFollowsAnOutsideWriteOfTheKey() {
        assertSame(SAClaudeAccent.accent, SAClaudeAccent.clayAccent)   // fills the cache with "absent"
        let data = SAArchiving.archivedData(forColor: srgb(0x7161E0))
        UserDefaults.standard.set(data, forKey: SAClaudeAccent.defaultsKey)   // not through `store`
        assertSame(SAClaudeAccent.accent, srgb(0x7161E0))
        UserDefaults.standard.removeObject(forKey: SAClaudeAccent.defaultsKey)
        assertSame(SAClaudeAccent.accent, SAClaudeAccent.clayAccent)
    }

    func testFillPressedOnDefaultClayFill() {
        let clay = SAClaudeAccent.clayFill
        let dark = SAClaudeAccent.fillPressed(darkTheme: true)
        let light = SAClaudeAccent.fillPressed(darkTheme: false)
        let c = components(clay)
        for (index, value) in components(dark).enumerated() { XCTAssertEqual(value, c[index] + (1 - c[index]) * 0.12, accuracy: 0.005) }
        for (index, value) in components(light).enumerated() { XCTAssertEqual(value, c[index] * 0.88, accuracy: 0.005) }
        assertSame(SAClaudeAccent.fillPressed(darkTheme: true, in: defaults), dark)
    }

    private func resolved(_ colour: NSColor, _ appearance: NSAppearance.Name) -> NSColor {
        var result = colour
        NSAppearance(named: appearance)!.performAsCurrentDrawingAppearance { result = colour.usingColorSpace(.sRGB)! }
        return result
    }

    func testTintDatabaseIsTheAccentInDarkAndTheFillInLight() {
        assertSame(resolved(SAClaudeStyle.tintDatabase, .darkAqua), SAClaudeAccent.clayAccent)
        assertSame(resolved(SAClaudeStyle.tintDatabase, .aqua), SAClaudeAccent.clayFill)
        // A stored accent is both the accent and the fill: the same colour in either appearance.
        SAClaudeAccent.store(srgb(0x2A78D6), in: .standard)
        assertSame(resolved(SAClaudeStyle.tintDatabase, .darkAqua), srgb(0x2A78D6))
        assertSame(resolved(SAClaudeStyle.tintDatabase, .aqua), srgb(0x2A78D6))
    }

    func testObserveRunsTheHandlerOnMainWhileTheOwnerLives() {
        final class Owner {}
        let owner = Owner()
        var calls = 0
        let called = expectation(description: "handler")
        called.assertForOverFulfill = false
        SAClaudeAccent.observe(owner) { _ in
            XCTAssertTrue(Thread.isMainThread)
            calls += 1
            called.fulfill()
        }
        DispatchQueue.global().async { SAClaudeAccent.store(nil, in: self.defaults) }
        wait(for: [called], timeout: 2)
        XCTAssertGreaterThan(calls, 0)
        withExtendedLifetime(owner) {}
    }

    func testObserveRemovesItsObserverAsSoonAsTheOwnerDeallocates() {
        final class Owner {}
        final class Canary {}
        weak var canary: Canary?
        autoreleasepool {
            let owner = Owner()
            let strongCanary = Canary()
            canary = strongCanary
            withExtendedLifetime(owner) {
                // The observer block holds the handler, which holds the canary: it lives while the observer does.
                SAClaudeAccent.observe(owner) { _ in _ = strongCanary }
                XCTAssertNotNil(canary)
            }
        }
        // No notification was posted since: only removing the observer can have released the handler.
        XCTAssertNil(canary)
    }

    // MARK: - Settings row

    private func makeSettings() -> SAClaudeEditorColoursSettings {
        SAClaudeEditorColoursSettings(defaults: defaults, themesDirectory: NSTemporaryDirectory(), confirmDiscardUnsaved: { true },
                                      saveAs: {}, importTheme: {}, exportTheme: {}, editThemeList: {})
    }

    func testSettingsStartAtClayWithResetDisabled() {
        let settings = makeSettings()
        assertSame(settings.accent, SAClaudeAccent.clayAccent)
        XCTAssertFalse(settings.accentIsStored)
    }

    func testSetAccentStoresAnOpaqueSRGBColourInTheInjectedDefaults() {
        let settings = makeSettings()
        settings.setAccent(srgb(0x2A78D6).withAlphaComponent(0.4))
        XCTAssertTrue(settings.accentIsStored)
        assertSame(settings.accent, srgb(0x2A78D6))
        let stored = SAClaudeAccent.stored(in: defaults)
        XCTAssertEqual(stored?.alphaComponent ?? 0, 1, accuracy: 0.001)
        assertSame(stored!, srgb(0x2A78D6))
        XCTAssertNil(SAClaudeAccent.stored(in: .standard), "the injected defaults were used, not .standard")
    }

    func testResetAccentClearsTheStoredColour() {
        let settings = makeSettings()
        settings.setAccent(srgb(0x7161E0))
        settings.resetAccent()
        XCTAssertFalse(settings.accentIsStored)
        assertSame(settings.accent, SAClaudeAccent.clayAccent)
        XCTAssertNil(defaults.object(forKey: SAClaudeAccent.defaultsKey))
    }

    func testSettingsPickUpAnAccentStoredElsewhere() {
        let settings = makeSettings()
        SAClaudeAccent.store(srgb(0x008300), in: defaults)
        settings.refresh()
        XCTAssertTrue(settings.accentIsStored)
        assertSame(settings.accent, srgb(0x008300))
    }

    func testErrorClayIsFixedWhateverTheAccent() {
        SAClaudeAccent.store(srgb(0x2A78D6), in: .standard)
        defer { SAClaudeAccent.store(nil, in: .standard) }
        assertSame(SAClaudeStatusChrome.errorClay, srgb(0xD97757))
        assertSame(SAClaudeStatusChrome.clay, srgb(0x2A78D6))
    }
}
