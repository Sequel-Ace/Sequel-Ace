//
//  SAClaudeHintCardTests.swift
//  Unit Tests
//

import AppKit
import XCTest

final class SAClaudeHintCardTests: XCTestCase {

    private func srgb(_ hex: UInt32) -> NSColor { SAClaudeStyle.srgb(hex) }

    private func theme(bg: UInt32, text: UInt32) -> SAClaudeThemeColours {
        SAClaudeThemeColours(background: srgb(bg), text: srgb(text), keyword: srgb(0x6DA7EC), variable: srgb(0xA096EB),
                             caret: srgb(0xD97757), quote: srgb(0x55BF50), backtick: srgb(0xF4ABAB), selection: srgb(0x383835))
    }

    private var light: SAClaudeThemeColours { theme(bg: 0xFFFFFF, text: 0x000000) }
    private var dark: SAClaudeThemeColours { theme(bg: 0x1F1E1D, text: 0xF0EFEC) }
    private let clay = SAClaudeStyle.srgb(0xD97757)

    /// WCAG contrast ratio, computed independently of the production helper.
    private func contrast(_ a: NSColor, _ b: NSColor) -> CGFloat {
        func luminance(_ colour: NSColor) -> CGFloat {
            let c = colour.usingColorSpace(.sRGB)!
            func lin(_ v: CGFloat) -> CGFloat { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
            return 0.2126 * lin(c.redComponent) + 0.7152 * lin(c.greenComponent) + 0.0722 * lin(c.blueComponent)
        }
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    // MARK: Colour strings

    func testColourHexIsSRGBUppercase() {
        XCTAssertEqual(SAClaudeHintCardCSS.colour(srgb(0xFAF9F5)), "#FAF9F5")
        let calibrated = NSColor(calibratedRed: 0.5, green: 0.25, blue: 0.75, alpha: 1)
        let s = calibrated.usingColorSpace(.sRGB)!
        let expected = String(format: "#%02X%02X%02X", Int((s.redComponent * 255).rounded()),
                              Int((s.greenComponent * 255).rounded()), Int((s.blueComponent * 255).rounded()))
        XCTAssertEqual(SAClaudeHintCardCSS.colour(calibrated), expected)
        XCTAssertEqual(SAClaudeHintCardCSS.colour(NSColor(calibratedWhite: 1, alpha: 1)), "#FFFFFF")
    }

    func testColourWithAlphaIsRGBA() {
        XCTAssertEqual(SAClaudeHintCardCSS.colour(clay.withAlphaComponent(0.28)), "rgba(217,119,87,0.28)")
        XCTAssertEqual(SAClaudeHintCardCSS.colour(clay.withAlphaComponent(0.5)), "rgba(217,119,87,0.5)")
    }

    // MARK: Palettes

    func testPaletteFromLightTheme() {
        let t = light
        let p = SAClaudeHintCardPalette.make(theme: t, accent: clay)
        XCTAssertEqual(p.surface, SAClaudeStatusChrome.popupSurface(theme: t))
        XCTAssertFalse(p.isDark)
        XCTAssertEqual(p.destructive, SAClaudeAlertChrome.red)
        XCTAssertEqual(p.muted, SAClaudeStatusChrome.muted(theme: t))
        XCTAssertEqual(p.hairline, SAClaudeStatusChrome.hairline(theme: t))
        XCTAssertEqual(p.text, t.text)
    }

    func testPaletteFromDarkTheme() {
        let p = SAClaudeHintCardPalette.make(theme: dark, accent: clay)
        XCTAssertTrue(p.isDark)
        XCTAssertEqual(p.destructive, SAClaudeAlertChrome.redGlyphDark)
        XCTAssertEqual(p.accent, clay)
        XCTAssertEqual(p.selection, clay.withAlphaComponent(0.28))
        XCTAssertEqual(p.codeFill, SAClaudeEditorChrome.derivedColour(text: p.text, background: p.surface, ratio: 0.05))
    }

    func testTextContrastOnSurfaceIsReadable() {
        let palettes = [SAClaudeHintCardPalette.make(theme: light, accent: clay),
                        SAClaudeHintCardPalette.make(theme: dark, accent: clay),
                        SAClaudeHintCardPalette.paper(accent: clay)]
        for p in palettes {
            XCTAssertGreaterThanOrEqual(contrast(p.text, p.surface), 4.5)
            XCTAssertGreaterThanOrEqual(contrast(p.muted, p.surface), 3)
        }
    }

    func testPaperIsAlwaysLight() {
        let accent = srgb(0x1A4D8F)
        let p = SAClaudeHintCardPalette.paper(accent: accent)
        XCTAssertEqual(SAClaudeHintCardCSS.colour(p.surface), "#FAF9F5")
        XCTAssertEqual(SAClaudeHintCardCSS.colour(p.text), "#0B0B0B")
        XCTAssertEqual(SAClaudeHintCardCSS.colour(p.muted), "#7B7974")
        XCTAssertEqual(SAClaudeHintCardCSS.colour(p.hairline), "#E7E6E1")
        XCTAssertEqual(p.destructive, SAClaudeAlertChrome.red)
        XCTAssertFalse(p.isDark)
        XCTAssertEqual(p.accent, accent)
        XCTAssertEqual(SAClaudeHintCardCSS.colour(SAClaudeHintCardPalette.paper(accent: .systemTeal).surface), "#FAF9F5")
    }

    func testPaperAccentIsReadable() {
        let paperSurface = srgb(0xFAF9F5)
        let cyan = NSColor(srgbRed: 0, green: 199 / 255.0, blue: 252 / 255.0, alpha: 1)
        for accent in [cyan, clay] {
            let p = SAClaudeHintCardPalette.paper(accent: accent)
            XCTAssertGreaterThanOrEqual(contrast(p.accent, paperSurface), 4.5, "\(accent)")
            // The hue survives the darkening.
            var h0: CGFloat = 0, h1: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            accent.usingColorSpace(.sRGB)!.getHue(&h0, saturation: &s, brightness: &b, alpha: &a)
            p.accent.usingColorSpace(.sRGB)!.getHue(&h1, saturation: &s, brightness: &b, alpha: &a)
            XCTAssertEqual(h0, h1, accuracy: 0.02)
        }
        let already = srgb(0x1A4D8F)
        XCTAssertEqual(SAClaudeHintCardPalette.paper(accent: already).accent, already)
        XCTAssertEqual(SAClaudeHintCardPalette.paper(accent: cyan).selection.alphaComponent, 0.28, accuracy: 0.001)
    }

    // MARK: CSS

    func testDeclarationsListEveryVariable() {
        let p = SAClaudeHintCardPalette.make(theme: dark, accent: clay)
        let css = SAClaudeHintCardCSS.declarations(p)
        for name in SAClaudeHintCardCSS.variableNames {
            XCTAssertEqual(css.components(separatedBy: "\(name):").count - 1, 1, name)
        }
        XCTAssertTrue(css.hasSuffix("color-scheme:dark"))
        XCTAssertTrue(SAClaudeHintCardCSS.declarations(.make(theme: light, accent: clay)).hasSuffix("color-scheme:light"))
        XCTAssertEqual(SAClaudeHintCardCSS.rootRule(p), ":root{\(css)}")
    }

    func testJSONIsParseable() throws {
        let p = SAClaudeHintCardPalette.make(theme: dark, accent: clay)
        let object = try JSONSerialization.jsonObject(with: Data(SAClaudeHintCardCSS.json(p).utf8)) as? [String: String]
        XCTAssertEqual(object?.count, 8)
        XCTAssertEqual(Set(object?.keys.map { $0 } ?? []), Set(SAClaudeHintCardCSS.variableNames))
        XCTAssertEqual(object?["--sa-accent"], "#D97757")
    }

    func testPageStyleEndsWithPrintPaper() {
        let themed = SAClaudeHintCardPalette.make(theme: dark, accent: clay)
        let paper = SAClaudeHintCardPalette.paper(accent: clay)
        let css = SAClaudeHintCardCSS.pageStyle(theme: themed, paper: paper)
        XCTAssertTrue(css.hasPrefix(":root{"))
        XCTAssertTrue(css.contains("@media print{:root{--sa-surface:#FAF9F5"))
        XCTAssertTrue(css.hasSuffix("}}"))
        XCTAssertEqual(css, SAClaudeHintCardCSS.rootRule(themed) + SAClaudeHintCardCSS.printRule(paper: paper))
    }

    // MARK: Metrics

    func testImageFit() {
        XCTAssertEqual(SAClaudeHintCard.imageFit(NSSize(width: 400, height: 100)), NSSize(width: 200, height: 50))
        XCTAssertEqual(SAClaudeHintCard.imageFit(NSSize(width: 100, height: 400)), NSSize(width: 50, height: 200))
        XCTAssertEqual(SAClaudeHintCard.imageFit(NSSize(width: 150, height: 120)), NSSize(width: 150, height: 120))
        XCTAssertEqual(SAClaudeHintCard.imageFit(.zero), .zero)
        // Whole points: fractions truncate, as SPTooltip's NSIntegers did.
        XCTAssertEqual(SAClaudeHintCard.imageFit(NSSize(width: 400.9, height: 100.9)), NSSize(width: 200, height: 50))
        XCTAssertEqual(SAClaudeHintCard.imageFit(NSSize(width: 150.9, height: 120.9)), NSSize(width: 150, height: 120))
        // A square image over the limit takes the height branch.
        XCTAssertEqual(SAClaudeHintCard.imageFit(NSSize(width: 300, height: 300)), NSSize(width: 200, height: 200))
    }

    func testImageCardSizeAddsPadding() {
        XCTAssertEqual(SAClaudeHintCard.imageCardSize(NSSize(width: 400, height: 100)), NSSize(width: 220, height: 66))
    }
}
