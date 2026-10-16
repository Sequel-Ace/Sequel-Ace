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
        XCTAssertEqual(C.tone(for: .error, secondaryText: secondary), C.red)
        XCTAssertEqual(C.tone(for: .destructive, secondaryText: secondary), C.red)
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
        assertColour(C.amber, [0xD4 / 255.0, 0xA1 / 255.0, 0x3A / 255.0, 1])
        assertColour(C.green, [0x4F / 255.0, 0xA0 / 255.0, 0x5A / 255.0, 1])
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
