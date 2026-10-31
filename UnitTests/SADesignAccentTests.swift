//
//  SADesignAccentTests.swift
//  Unit Tests
//

import AppKit
import XCTest

final class SADesignAccentTests: XCTestCase {

    private func srgb(_ hex: UInt32) -> NSColor { SADesignStyle.srgb(hex) }

    private func components(_ c: NSColor) -> [CGFloat] {
        let s = c.usingColorSpace(.sRGB)!
        return [s.redComponent, s.greenComponent, s.blueComponent]
    }

    private func assertSame(_ a: NSColor, _ b: NSColor, file: StaticString = #filePath, line: UInt = #line) {
        for (x, y) in zip(components(a), components(b)) { XCTAssertEqual(x, y, accuracy: 0.001, file: file, line: line) }
    }

    private func resolved(_ color: NSColor, _ appearance: NSAppearance.Name) -> NSColor {
        var result = color
        NSAppearance(named: appearance)!.performAsCurrentDrawingAppearance { result = color.usingColorSpace(.sRGB)! }
        return result
    }

    // MARK: - The accent

    /// The accent is the macOS accent color, in the appearance it is read in, and stays dynamic.
    func testAccentIsTheSystemAccent() {
        for appearance: NSAppearance.Name in [.aqua, .darkAqua] {
            assertSame(resolved(SADesignAccent.accent, appearance), resolved(.controlAccentColor, appearance))
        }
        XCTAssertNotEqual(SADesignAccent.accent.type, .componentBased, "dynamic: it follows System Settings")
    }

    func testRelativeLuminance() {
        XCTAssertEqual(SADesignAccent.relativeLuminance(srgb(0xFFFFFF)), 1, accuracy: 0.001)
        XCTAssertEqual(SADesignAccent.relativeLuminance(srgb(0x000000)), 0, accuracy: 0.001)
        // WCAG: #C6613F linearizes to 0.209.
        XCTAssertEqual(SADesignAccent.relativeLuminance(srgb(0xC6613F)), 0.209, accuracy: 0.005)
    }

    // MARK: - Observing

    func testObserveRunsTheHandlerOnMainWhileTheOwnerLives() {
        final class Owner {}
        let owner = Owner()
        var calls = 0
        let called = expectation(description: "handler")
        called.assertForOverFulfill = false
        SADesignAccent.observe(owner) { _ in
            XCTAssertTrue(Thread.isMainThread)
            calls += 1
            called.fulfill()
        }
        DispatchQueue.global().async { NotificationCenter.default.post(name: NSColor.systemColorsDidChangeNotification, object: nil) }
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
                SADesignAccent.observe(owner) { _ in _ = strongCanary }
                XCTAssertNotNil(canary)
            }
        }
        // No notification was posted since: only removing the observer can have released the handler.
        XCTAssertNil(canary)
    }

    // MARK: - The macOS accent changing

    /// Changing the accent color in System Settings (AppKit posts `systemColorsDidChangeNotification`) is a change of
    /// the accent: the stylers that observe the accent are told.
    func testASystemAccentChangeNotifiesTheAccentObservers() {
        final class Owner {}
        let owner = Owner()
        SADesignAccent.observe(owner) { _ in }   // starts the system observer
        let told = XCTNSNotificationExpectation(name: SADesignAccent.didChangeNotification)
        NotificationCenter.default.post(name: NSColor.systemColorsDidChangeNotification, object: nil)
        wait(for: [told], timeout: 1)
        withExtendedLifetime(owner) {}
    }

    // MARK: - Readable accent text and glyphs for every macOS accent

    /// The macOS accent choices, as the system colors they resolve to (blue is also "multicolor"); graphite is
    /// the system gray.
    private let systemAccents: [(name: String, color: NSColor)] = [
        ("blue", .systemBlue), ("purple", .systemPurple), ("pink", .systemPink), ("red", .systemRed),
        ("orange", .systemOrange), ("yellow", .systemYellow), ("green", .systemGreen), ("graphite", .systemGray),
    ]

    private func contrast(_ a: NSColor, _ b: NSColor) -> CGFloat { SADesignAccent.contrast(a, b) }

    private enum Use { case text, glyph }

    private func readable(_ use: Use, on backgrounds: [NSColor], dark: Bool, accent: NSColor) -> NSColor {
        switch (use, backgrounds.count) {
        case (.text, 1): return SADesignAccent.readableText(on: backgrounds[0], dark: dark, accent: accent)
        case (.text, 2): return SADesignAccent.readableText(on: backgrounds[0], backgrounds[1], dark: dark, accent: accent)
        case (.text, _): return SADesignAccent.readableText(on: backgrounds[0], backgrounds[1], backgrounds[2], dark: dark, accent: accent)
        case (.glyph, 1): return SADesignAccent.readableGlyph(on: backgrounds[0], dark: dark, accent: accent)
        case (.glyph, 2): return SADesignAccent.readableGlyph(on: backgrounds[0], backgrounds[1], dark: dark, accent: accent)
        case (.glyph, _): return SADesignAccent.readableGlyph(on: backgrounds[0], backgrounds[1], backgrounds[2], dark: dark, accent: accent)
        }
    }

    /// Asserts, for every macOS accent in light and dark, that accent text keeps 4.5:1 and an accent glyph 3:1 on every
    /// one of the surfaces `backgrounds(dark)` returns.
    private func assertReadable(_ what: String, file: StaticString = #filePath, line: UInt = #line,
                                backgrounds: (_ dark: Bool, _ accent: NSColor) -> [NSColor]) {
        for dark in [false, true] {
            for (name, accent) in systemAccents {
                let surfaces = backgrounds(dark, accent)
                for (use, minimum) in [(Use.text, 4.5), (Use.glyph, 3.0)] {
                    let color = readable(use, on: surfaces, dark: dark, accent: accent)
                    XCTAssertEqual(color.alphaComponent, 1, file: file, line: line)
                    for surface in surfaces {
                        XCTAssertGreaterThanOrEqual(contrast(color, SADesignAccent.resolved(surface, dark: dark)), CGFloat(minimum),
                                                    "\(name) \(use) on \(what), \(dark ? "dark" : "light")", file: file, line: line)
                    }
                }
            }
        }
    }

    func testThresholdsAreWCAGTextAndNonText() {
        XCTAssertEqual(SADesignAccent.readableContrast, 4.5)
        XCTAssertEqual(SADesignAccent.glyphContrast, 3)
    }

    /// The selected toolbar view's glyph on its chip: the accent at the chip's tint alpha over the toolbar background.
    func testReadableOnTheToolbarChipForEverySystemAccent() {
        assertReadable("the toolbar chip") { dark, accent in
            let tint = accent.withAlphaComponent(dark ? SAVividColor.tintAlphaDark : SAVividColor.tintAlphaLight)
            return [SADesignAccent.composite(tint, over: SADesignStyle.toolbarBackground, dark: dark)]
        }
    }

    /// The database pill's glyph, on the pill and on its hover fill.
    func testReadableOnTheDatabasePillForEverySystemAccent() {
        assertReadable("the database pill") { _, _ in [SADesignStyle.hoverFill, SADesignStyle.selection] }
    }

    /// A menu card's tick, on the card and on a hovered or highlighted row.
    func testReadableOnTheMenuCardForEverySystemAccent() {
        assertReadable("the menu card") { _, _ in [SADesignStyle.cardSurface, SADesignStyle.hoverFill, SADesignStyle.selection] }
    }

    /// A glyph keeps more of the accent than text: one that reads at 3:1 is kept, though it is below 4.5:1.
    func testReadableGlyphKeepsAnAccentThatTextWouldDarken() {
        let white = srgb(0xFFFFFF)
        let blue = srgb(0x3B82F6)   // 3.68:1 on white
        assertSame(SADesignAccent.readableGlyph(on: white, dark: false, accent: blue), blue)
        XCTAssertGreaterThanOrEqual(contrast(SADesignAccent.readableText(on: white, dark: false, accent: blue), white), 4.5)
        XCTAssertLessThan(contrast(blue, white), 4.5)
    }

    /// An accent that already reads is kept as it is; one that doesn't keeps its hue.
    func testReadableTextKeepsAReadableAccentAndTheHueOfOneThatIsNot() {
        let white = srgb(0xFFFFFF)
        let deepBlue = srgb(0x1D4ED8)
        assertSame(SADesignAccent.readableText(on: white, dark: false, accent: deepBlue), deepBlue)
        let yellow = SADesignAccent.resolved(.systemYellow, dark: false)
        let darkened = SADesignAccent.readableText(on: white, dark: false, accent: yellow)
        XCTAssertGreaterThanOrEqual(contrast(darkened, white), 4.5)
        XCTAssertEqual(darkened.usingColorSpace(.sRGB)!.hueComponent, yellow.usingColorSpace(.sRGB)!.hueComponent, accuracy: 0.03)
    }

    /// The current accent is the default: `readableText` starts from the macOS accent, resolved in the appearance.
    func testReadableTextStartsFromTheCurrentAccent() {
        let surface = srgb(0x1A1A19)
        assertSame(SADesignAccent.readableText(on: surface, dark: true),
                   SADesignAccent.readable(SADesignAccent.resolved(.controlAccentColor, dark: true), on: surface))
    }

    /// Compositing gives the opaque color a translucent fill shows.
    func testCompositeMixesByAlpha() {
        let half = NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 0.5)
        let result = SADesignAccent.composite(half, over: srgb(0x000000), dark: false)
        assertSame(result, NSColor(srgbRed: 0.5, green: 0, blue: 0, alpha: 1))
        XCTAssertEqual(result.alphaComponent, 1)
    }
}
