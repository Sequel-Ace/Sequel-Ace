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
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
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

    func testOnAccentIsWhiteForClayAndNearBlackForALightAccent() {
        assertSame(SAClaudeAccent.onAccent(in: defaults), srgb(0xFFFFFF))
        SAClaudeAccent.store(srgb(0xFFE066), in: defaults)
        assertSame(SAClaudeAccent.onAccent(in: defaults), srgb(0x1A1A1A))
    }

    func testErrorClayIsFixedWhateverTheAccent() {
        SAClaudeAccent.store(srgb(0x2A78D6), in: .standard)
        defer { SAClaudeAccent.store(nil, in: .standard) }
        assertSame(SAClaudeStatusChrome.errorClay, srgb(0xD97757))
        assertSame(SAClaudeStatusChrome.clay, srgb(0x2A78D6))
    }
}
