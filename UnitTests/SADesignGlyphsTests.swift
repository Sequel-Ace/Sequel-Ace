//
//  SADesignGlyphsTests.swift
//  Unit Tests
//

import AppKit
import XCTest

final class SADesignGlyphsTests: XCTestCase {

    private let allGlyphs: [SADesignGlyph] = [.database, .table,
                                                .structure, .relations, .triggers, .info, .query, .recordView, .users, .console,
                                                .clearConsole, .chevronLeft, .chevronRight]

    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    /// Draws an image at 2x into a bitmap under an appearance.
    private func render(_ image: NSImage, _ name: NSAppearance.Name) -> NSBitmapImageRep {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(image.size.width * 2), pixelsHigh: Int(image.size.height * 2),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = image.size
        NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            image.draw(in: NSRect(origin: .zero, size: image.size))
            NSGraphicsContext.restoreGraphicsState()
        }
        return rep
    }

    /// The color of the most opaque pixel, in sRGB, or nil for an empty image.
    private func strokeColor(_ rep: NSBitmapImageRep) -> NSColor? {
        var best: NSColor?
        var bestAlpha: CGFloat = 0
        for x in 0..<rep.pixelsWide {
            for y in 0..<rep.pixelsHigh {
                if let c = rep.colorAt(x: x, y: y), c.alphaComponent > bestAlpha {
                    bestAlpha = c.alphaComponent
                    best = c
                }
            }
        }
        return bestAlpha > 0.9 ? best?.usingColorSpace(.sRGB) : nil
    }

    private func assertClose(_ c: NSColor?, _ hex: UInt32, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        guard let c else { return XCTFail("empty image: \(message)", file: file, line: line) }
        let e = SADesignStyle.srgb(hex)
        XCTAssertEqual(c.redComponent, e.redComponent, accuracy: 0.03, message, file: file, line: line)
        XCTAssertEqual(c.greenComponent, e.greenComponent, accuracy: 0.03, message, file: file, line: line)
        XCTAssertEqual(c.blueComponent, e.blueComponent, accuracy: 0.03, message, file: file, line: line)
    }

    /// Verifies every glyph is 16pt, draws something, and is named for VoiceOver.
    func testEveryGlyphRendersAndIsNamed() {
        for glyph in allGlyphs {
            let image = SADesignGlyphs.image(glyph, tint: SADesignStyle.textMuted)
            XCTAssertEqual(image.size, NSSize(width: 16, height: 16))
            XCTAssertNotNil(strokeColor(render(image, .darkAqua)), "glyph \(glyph.rawValue) draws nothing")
            XCTAssertFalse(image.accessibilityDescription?.isEmpty ?? true)
        }
    }

    /// Verifies one image instance re-tints when the appearance changes (no stale cache).
    func testSameImageInstanceRetintsPerAppearance() {
        let image = SADesignGlyphs.image(.table, tint: SADesignStyle.textPrimary)
        assertClose(strokeColor(render(image, .darkAqua)), 0xF0EFEC, "first dark draw")
        assertClose(strokeColor(render(image, .aqua)), 0x0B0B0B, "then light")
        assertClose(strokeColor(render(image, .darkAqua)), 0xF0EFEC, "back to dark")
    }

    /// Verifies each glyph's VoiceOver name is an English key of Localizable.strings, so it can be translated.
    func testGlyphNamesAreLocalized() throws {
        let url = repoRoot.appendingPathComponent("Resources/Localization/en.lproj/Localizable.strings")
        let strings = try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: String])
        let expected: [SADesignGlyph: String] = [
            .database: "Database", .table: "Table", .structure: "Structure", .relations: "Relations", .triggers: "Triggers",
            .info: "Table Info", .query: "Query", .recordView: "Record View", .users: "Users", .console: "Console",
            .clearConsole: "Clear Console", .chevronLeft: "Back", .chevronRight: "Forward",
        ]
        XCTAssertEqual(expected.count, allGlyphs.count)
        for glyph in allGlyphs {
            let name = SADesignGlyphs.accessibilityName(for: glyph)
            XCTAssertEqual(name, expected[glyph], "glyph \(glyph.rawValue)")
            XCTAssertEqual(strings[name], name, "\(name) in en.lproj")
        }
    }
}
