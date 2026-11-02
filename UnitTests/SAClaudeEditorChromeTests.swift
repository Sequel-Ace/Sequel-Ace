//
//  SAClaudeEditorChromeTests.swift
//  Unit Tests
//

import AppKit
import XCTest

final class SAClaudeEditorChromeTests: XCTestCase {

    private func hex(_ c: NSColor) -> UInt32 {
        let s = c.usingColorSpace(.sRGB)!
        return UInt32((s.redComponent * 255).rounded()) << 16 | UInt32((s.greenComponent * 255).rounded()) << 8 | UInt32((s.blueComponent * 255).rounded())
    }

    private let claudeDark = (text: SAClaudeStyle.srgb(0xF0EFEC), background: SAClaudeStyle.srgb(0x151515))
    private let claudeLight = (text: SAClaudeStyle.srgb(0x0B0B0B), background: SAClaudeStyle.srgb(0xFCFCFB))

    private func assertNear(_ c: NSColor, _ expected: UInt32, file: StaticString = #filePath, line: UInt = #line) {
        let got = hex(c)
        for shift in [16, 8, 0] {
            XCTAssertLessThanOrEqual(abs(Int((got >> UInt32(shift)) & 0xFF) - Int((expected >> UInt32(shift)) & 0xFF)), 1,
                                     String(format: "got %06X expected %06X", got, expected), file: file, line: line)
        }
    }

    /// Verifies the spec's palette values for the Claude themes (±1 per channel).
    func testClaudePalettes() {
        let dark = SAClaudeEditorChrome.palette(text: claudeDark.text, background: claudeDark.background)
        assertNear(dark.background, 0x151515); assertNear(dark.hairline, 0x272626); assertNear(dark.hover, 0x272626)
        assertNear(dark.buttonText, 0xC0BFBD); assertNear(dark.icon, 0x8D8D8B); assertNear(dark.gutterNumbers, 0x646362)
        let light = SAClaudeEditorChrome.palette(text: claudeLight.text, background: claudeLight.background)
        assertNear(light.background, 0xFCFCFB); assertNear(light.hairline, 0xE9E9E8); assertNear(light.hover, 0xE9E9E8)
        assertNear(light.buttonText, 0x404040); assertNear(light.icon, 0x777777); assertNear(light.gutterNumbers, 0xA5A5A5)
    }

    /// Reads `c` back in generic RGB as a 24-bit hex value.
    private func genericHex(_ c: NSColor) -> UInt32 {
        let g = c.usingColorSpace(.genericRGB)!
        return UInt32((g.redComponent * 255).rounded()) << 16 | UInt32((g.greenComponent * 255).rounded()) << 8 | UInt32((g.blueComponent * 255).rounded())
    }

    private func assertNearGeneric(_ c: NSColor, _ expected: UInt32, _ name: String, file: StaticString = #filePath, line: UInt = #line) {
        let got = genericHex(c)
        for shift in [16, 8, 0] {
            XCTAssertLessThanOrEqual(abs(Int((got >> UInt32(shift)) & 0xFF) - Int((expected >> UInt32(shift)) & 0xFF)), 1,
                                     String(format: "%@: got %06X expected %06X", name, got, expected), file: file, line: line)
        }
    }

    /// The colours as the app stores and reloads them: calibrated (generic) RGB through SAArchiving.
    private func storedTheme(text: String, background: String) throws -> (text: NSColor, background: NSColor) {
        func roundTrip(_ hex: String) throws -> NSColor {
            let colour = try XCTUnwrap(SAEditorThemeLoader.colour(fromHex: hex))
            return try XCTUnwrap(SAArchiving.color(from: SAArchiving.archivedData(forColor: colour)))
        }
        return (try roundTrip(text), try roundTrip(background))
    }

    /// Verifies theme-loaded (generic RGB) Claude colours give the spec values, not an sRGB drift.
    func testClaudePalettesFromStoredThemeColours() throws {
        let dark = try storedTheme(text: "#F0EFEC", background: "#151515")
        let d = SAClaudeEditorChrome.palette(text: dark.text, background: dark.background)
        assertNearGeneric(d.background, 0x151515, "dark background")
        assertNearGeneric(d.hairline, 0x272626, "dark hairline"); assertNearGeneric(d.hover, 0x272626, "dark hover")
        assertNearGeneric(d.buttonText, 0xC0BFBD, "dark buttonText"); assertNearGeneric(d.icon, 0x8D8D8B, "dark icon")
        assertNearGeneric(d.gutterNumbers, 0x646362, "dark gutter")
        let light = try storedTheme(text: "#0B0B0B", background: "#FCFCFB")
        let l = SAClaudeEditorChrome.palette(text: light.text, background: light.background)
        assertNearGeneric(l.background, 0xFCFCFB, "light background")
        assertNearGeneric(l.hairline, 0xE9E9E8, "light hairline"); assertNearGeneric(l.hover, 0xE9E9E8, "light hover")
        assertNearGeneric(l.buttonText, 0x404040, "light buttonText"); assertNearGeneric(l.icon, 0x777777, "light icon")
        assertNearGeneric(l.gutterNumbers, 0xA5A5A5, "light gutter")
    }

    private func luminance(_ c: NSColor) -> CGFloat {
        let s = c.usingColorSpace(.sRGB)!
        func lin(_ v: CGFloat) -> CGFloat { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(s.redComponent) + 0.7152 * lin(s.greenComponent) + 0.0722 * lin(s.blueComponent)
    }

    /// Verifies a non-Claude theme still gets readable button text (≥ 4.5:1).
    func testNonClaudeThemeKeepsReadableButtonText() {
        for (text, bg) in [(0xE7EAF1, 0x222631), (0x363C38, 0xECEFEB), (0xFFFFFF, 0x000000)] as [(UInt32, UInt32)] {
            let p = SAClaudeEditorChrome.palette(text: SAClaudeStyle.srgb(text), background: SAClaudeStyle.srgb(bg))
            let (a, b) = (luminance(p.buttonText), luminance(p.background))
            XCTAssertGreaterThanOrEqual((max(a, b) + 0.05) / (min(a, b) + 0.05), 4.5, String(format: "%06X on %06X", text, bg))
        }
    }

    /// Verifies the palette falls back when the colour settings are missing.
    func testPaletteFromEmptyDefaultsFallsBack() {
        let suite = "SAClaudeEditorChromeTests"
        UserDefaults().removePersistentDomain(forName: suite)
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let p = SAClaudeEditorChrome.palette(from: UserDefaults(suiteName: suite)!)
        XCTAssertNotNil(p.background.usingColorSpace(.sRGB))
    }

    /// Verifies the bar is pinned to the top of its pane at 44pt and full width, and the
    /// results area below runs right up to it (no overhang above, no gap below).
    func testBarFrames() {
        // DBView.xib: pane 7211 is 695x235; the bar sits at y=213 h=25 (3pt above the pane), results top at 204.
        let frames = SAClaudeEditorChrome.barFrames(container: NSRect(x: 0, y: 0, width: 695, height: 235),
                                                     results: NSRect(x: -1, y: -1, width: 697, height: 205),
                                                     height: 44)
        XCTAssertEqual(frames.bar, NSRect(x: 0, y: 191, width: 695, height: 44))
        XCTAssertEqual(frames.results, NSRect(x: -1, y: -1, width: 697, height: 192))
        XCTAssertEqual(frames.results.maxY, frames.bar.minY)
        let tiny = SAClaudeEditorChrome.barFrames(container: NSRect(x: 0, y: 0, width: 100, height: 30),
                                                   results: NSRect(x: 0, y: 0, width: 100, height: 5), height: 44)
        XCTAssertEqual(tiny.results.height, 0)
    }

    /// Verifies vertical centring and left-to-right placement.
    func testCentringAndPlacement() {
        XCTAssertEqual(SAClaudeEditorChrome.centredY(height: 28, in: 44), 8)
        XCTAssertEqual(SAClaudeEditorChrome.leadingXs(widths: [28, 90, 80], start: 10, gap: 2), [10, 40, 132])
    }

    /// Verifies shortcut hints like the menu shows them.
    func testShortcutString() {
        XCTAssertEqual(SAClaudeEditorChrome.shortcutString(keyEquivalent: "r", modifiers: .command), "⌘R")
        XCTAssertEqual(SAClaudeEditorChrome.shortcutString(keyEquivalent: "r", modifiers: [.command, .option]), "⌥⌘R")
        XCTAssertEqual(SAClaudeEditorChrome.shortcutString(keyEquivalent: "r", modifiers: [.command, .option, .shift, .control]), "⌃⌥⇧⌘R")
        XCTAssertEqual(SAClaudeEditorChrome.shortcutString(keyEquivalent: "", modifiers: .command), "")
    }

    /// Verifies the drawn divider sits exactly at SPComboPopupButton's click split.
    func testRunLayoutPutsTheDividerAtTheClickSplit() {
        let bounds = NSRect(x: 0, y: 0, width: 150, height: 28)
        let layout = SAClaudeEditorChrome.runLayout(bounds: bounds, lineOffset: 15, titleSize: NSSize(width: 70, height: 16), shortcutSize: NSSize(width: 20, height: 15))
        XCTAssertEqual(layout.dividerX, 135)
        XCTAssertEqual(layout.chevronRect.minX, 135)
        XCTAssertEqual(layout.chevronRect.maxX, 150)
        XCTAssertLessThanOrEqual(layout.shortcutOrigin.x + 20, layout.dividerX)
        XCTAssertEqual(layout.shortcutOrigin.x, 103)
        XCTAssertEqual(SAClaudeEditorChrome.runWidth(titleWidth: 70, shortcutWidth: 20, lineOffset: 15), 12 + 9 + 6 + 70 + 8 + 20 + 12 + 15)
    }
}
