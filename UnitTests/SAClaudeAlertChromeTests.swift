import XCTest

final class SAClaudeAlertChromeTests: XCTestCase {
    private typealias C = SAClaudeAlertChrome

    private func srgb(_ colour: NSColor, file: StaticString = #filePath, line: UInt = #line) -> [CGFloat] {
        guard let c = colour.usingColorSpace(.sRGB) else {
            XCTFail("not convertible to sRGB", file: file, line: line)
            return [0, 0, 0, 0]
        }
        return [c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent]
    }

    private func assertColour(_ colour: NSColor, _ expected: [CGFloat], file: StaticString = #filePath, line: UInt = #line) {
        let actual = srgb(colour, file: file, line: line)
        for (a, e) in zip(actual, expected) { XCTAssertEqual(a, e, accuracy: 0.0001, file: file, line: line) }
    }

    func testSymbolNames() {
        XCTAssertEqual(C.symbolName(for: .error), "xmark.circle")
        XCTAssertEqual(C.symbolName(for: .destructive), "trash")
        XCTAssertEqual(C.symbolName(for: .warning), "exclamationmark.triangle")
        XCTAssertEqual(C.symbolName(for: .question), "questionmark.circle")
        XCTAssertEqual(C.symbolName(for: .info), "checkmark.circle")
        for kind in SAClaudeAlertKind.allCases {
            XCTAssertNotNil(NSImage(systemSymbolName: C.symbolName(for: kind), accessibilityDescription: nil), "\(kind)")
        }
    }

    func testTones() {
        let secondary = NSColor.systemPink
        XCTAssertEqual(C.tone(for: .error, secondaryText: secondary), C.redGlyph)
        XCTAssertEqual(C.tone(for: .destructive, secondaryText: secondary), C.redGlyph)
        XCTAssertEqual(C.tone(for: .warning, secondaryText: secondary), C.amber)
        XCTAssertEqual(C.tone(for: .info, secondaryText: secondary), C.green)
        XCTAssertEqual(C.tone(for: .question, secondaryText: secondary), secondary)
    }

    /// Red is #C03A2E, and its green channel differs from the primary fill (clay #C6613F) by more than 0.12, so a red
    /// "Delete" never reads as an ordinary OK.
    func testRedIsDistinctFromTheClayAccent() {
        assertColour(C.red, [0xC0 / 255.0, 0x3A / 255.0, 0x2E / 255.0, 1])
        let red = srgb(C.red)
        let clay = srgb(SAClaudeAccent.clayFill)
        XCTAssertGreaterThan(abs(red[1] - clay[1]), 0.12)
        XCTAssertNotEqual(C.red, SAClaudeStatusChrome.errorClay)
    }

    func testAmberAndGreen() {
        assertColour(C.amberDark, [0xD4 / 255.0, 0xA1 / 255.0, 0x3A / 255.0, 1])
        assertColour(C.amberLight, [0xB7 / 255.0, 0x80 / 255.0, 0x1A / 255.0, 1])
        NSAppearance(named: .darkAqua)!.performAsCurrentDrawingAppearance {
            assertColour(C.amber, [0xD4 / 255.0, 0xA1 / 255.0, 0x3A / 255.0, 1])
        }
        NSAppearance(named: .aqua)!.performAsCurrentDrawingAppearance {
            assertColour(C.amber, [0xB7 / 255.0, 0x80 / 255.0, 0x1A / 255.0, 1])
        }
        assertColour(C.greenDark, [0x4F / 255.0, 0xA0 / 255.0, 0x5A / 255.0, 1])
        assertColour(C.greenLight, [0x3E / 255.0, 0x8A / 255.0, 0x4A / 255.0, 1])
        assertColour(C.redGlyphDark, [0xE0 / 255.0, 0x57 / 255.0, 0x4A / 255.0, 1])
        NSAppearance(named: .darkAqua)!.performAsCurrentDrawingAppearance {
            assertColour(C.green, [0x4F / 255.0, 0xA0 / 255.0, 0x5A / 255.0, 1])
            assertColour(C.redGlyph, [0xE0 / 255.0, 0x57 / 255.0, 0x4A / 255.0, 1])
        }
        NSAppearance(named: .aqua)!.performAsCurrentDrawingAppearance {
            assertColour(C.green, [0x3E / 255.0, 0x8A / 255.0, 0x4A / 255.0, 1])
            assertColour(C.redGlyph, [0xC0 / 255.0, 0x3A / 255.0, 0x2E / 255.0, 1])
        }
    }

    /// Each kind's glyph reads against its own tile on the card surface (WCAG 3:1 for a graphic). The destructive
    /// button's fill stays `red` in both appearances. Surfaces: white (the light card), and the dark cards' range.
    /// The Warning glyph in light is the amber the round kept (`#B7801A`: 2.98:1 on white), so its floor is 2.9.
    func testGlyphContrastOnItsTile() {
        func contrast(_ a: NSColor, _ b: NSColor) -> CGFloat {
            let (x, y) = (SAClaudeAccent.relativeLuminance(a), SAClaudeAccent.relativeLuminance(b))
            return (max(x, y) + 0.05) / (min(x, y) + 0.05)
        }
        func surface(_ hex: Int) -> NSColor {
            NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
        let cases: [(name: String, appearance: NSAppearance.Name, surfaces: [Int])] = [
            ("light", .aqua, [0xFFFFFF]),
            ("dark", .darkAqua, [0x1A1A18, 0x262624, 0x30302E])
        ]
        // Question is the card's secondary text colour (not fixed here), so only the fixed tones are measured.
        for kind in SAClaudeAlertKind.allCases where kind != .question {
            for c in cases {
                for hex in c.surfaces {
                    NSAppearance(named: c.appearance)!.performAsCurrentDrawingAppearance {
                        let card = surface(hex)
                        let tone = C.tone(for: kind, secondaryText: .gray)
                        let tile = C.tileFill(tone: tone, surface: card)
                        let floor: CGFloat = (kind == .warning && c.name == "light") ? 2.9 : 3.0
                        let ratio = contrast(tone, tile)
                        XCTAssertGreaterThanOrEqual(ratio, floor, "\(kind) \(c.name) on #\(String(hex, radix: 16)): \(ratio)")
                    }
                }
            }
        }
        // Dark cards: the old red glyph (the button fill) would fail the bar, which is why the glyph has its own tone.
        NSAppearance(named: .darkAqua)!.performAsCurrentDrawingAppearance {
            let card = surface(0x30302E)
            XCTAssertLessThan(contrast(C.red, C.tileFill(tone: C.red, surface: card)), 3.0)
        }
        assertColour(C.red, [0xC0 / 255.0, 0x3A / 255.0, 0x2E / 255.0, 1])
    }

    func testTileFill() {
        let srgbSpace = NSColorSpace.sRGB
        func colour(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor { NSColor(colorSpace: srgbSpace, components: [r, g, b, 1], count: 4) }
        assertColour(C.tileFill(tone: colour(1, 0, 0), surface: colour(1, 1, 1)), [1, 0.87, 0.87, 1])
        assertColour(C.tileFill(tone: colour(0, 1, 0), surface: colour(0, 0, 0)), [0, 0.13, 0, 1])
        XCTAssertEqual(C.tileFillRatio, 0.13, accuracy: 0.00001)
    }

    func testFonts() {
        func weight(_ font: NSFont) -> CGFloat {
            let traits = font.fontDescriptor.object(forKey: .traits) as? [NSFontDescriptor.TraitKey: Any]
            return (traits?[.weight] as? NSNumber).map { CGFloat($0.doubleValue) } ?? .nan
        }
        XCTAssertEqual(C.titleFont.pointSize, 14)
        XCTAssertEqual(weight(C.titleFont), NSFont.Weight.medium.rawValue, accuracy: 0.01)
        XCTAssertEqual(C.messageFont.pointSize, 12)
        XCTAssertEqual(C.blockLabelFont.pointSize, 11)
        XCTAssertEqual(C.serverFont.pointSize, 11)
        XCTAssertTrue(C.serverFont.isFixedPitch)
        XCTAssertEqual(C.glyphPointSize, 18)
    }
}
