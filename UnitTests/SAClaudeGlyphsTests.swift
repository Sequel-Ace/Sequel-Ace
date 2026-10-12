//
//  SAClaudeGlyphsTests.swift
//  Unit Tests
//

import AppKit
import XCTest

final class SAClaudeGlyphsTests: XCTestCase {

    private let allGlyphs: [SAClaudeGlyph] = [.database, .table, .view, .procedure, .function, .add, .actions, .refresh, .infoPanel,
                                                .copy, .save, .clear, .field, .keyword,
                                                .structure, .relations, .triggers, .info, .query, .recordView, .users, .console,
                                                .clearConsole, .chevronLeft, .chevronRight]

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

    /// The colour of the most opaque pixel, in sRGB, or nil for an empty image.
    private func strokeColour(_ rep: NSBitmapImageRep) -> NSColor? {
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
        let e = SAClaudeStyle.srgb(hex)
        XCTAssertEqual(c.redComponent, e.redComponent, accuracy: 0.03, message, file: file, line: line)
        XCTAssertEqual(c.greenComponent, e.greenComponent, accuracy: 0.03, message, file: file, line: line)
        XCTAssertEqual(c.blueComponent, e.blueComponent, accuracy: 0.03, message, file: file, line: line)
    }

    /// Verifies every glyph is 16pt, draws something, and is named for VoiceOver.
    func testEveryGlyphRendersAndIsNamed() {
        for glyph in allGlyphs {
            let image = SAClaudeGlyphs.image(glyph, tint: SAClaudeGlyphs.tint(for: glyph))
            XCTAssertEqual(image.size, NSSize(width: 16, height: 16))
            XCTAssertNotNil(strokeColour(render(image, .darkAqua)), "glyph \(glyph.rawValue) draws nothing")
            XCTAssertFalse(image.accessibilityDescription?.isEmpty ?? true)
        }
    }

    /// Verifies the object icons carry their type tints in both appearances.
    func testTypeTints() {
        let expected: [(SAClaudeGlyph, UInt32, UInt32)] = [
            (.database, 0xD97757, 0xC6613F), (.table, 0x6DA7EC, 0x2A78D6), (.view, 0xA096EB, 0x7161E0),
            (.procedure, 0xEC835A, 0xC25124), (.function, 0x55BF50, 0x008300),
        ]
        for (glyph, dark, light) in expected {
            let image = SAClaudeGlyphs.image(glyph, tint: SAClaudeGlyphs.tint(for: glyph))
            assertClose(strokeColour(render(image, .darkAqua)), dark, "glyph \(glyph.rawValue) dark")
            assertClose(strokeColour(render(image, .aqua)), light, "glyph \(glyph.rawValue) light")
        }
    }

    /// Verifies one image instance re-tints when the appearance changes (no stale cache).
    func testSameImageInstanceRetintsPerAppearance() {
        let image = SAClaudeGlyphs.image(.table, tint: SAClaudeStyle.tintTable)
        assertClose(strokeColour(render(image, .darkAqua)), 0x6DA7EC, "first dark draw")
        assertClose(strokeColour(render(image, .aqua)), 0x2A78D6, "then light")
        assertClose(strokeColour(render(image, .darkAqua)), 0x6DA7EC, "back to dark")
    }

    /// Verifies the sidebar images use the padded canvas, map the table types, and skip headers.
    func testSidebarImagesByTableType() {
        XCTAssertNil(SAClaudeGlyphs.sidebarImage(forTableType: -1))
        let names = [0: "Table", 1: "View", 2: "Procedure", 3: "Function", 4: "Table", 5: "Table"]
        for (type, name) in names {
            let image = SAClaudeGlyphs.sidebarImage(forTableType: type)
            XCTAssertEqual(image?.size, NSSize(width: SAClaudeStyle.sidebarIconCanvasWidth, height: 16))
            XCTAssertEqual(image?.accessibilityDescription, name)
        }
    }

    /// Verifies the glyph inside the padded canvas starts at sidebarIconLeading.
    func testSidebarImageLeavesLeadingSpaceClear() {
        let rep = render(SAClaudeGlyphs.sidebarImage(forTableType: 0)!, .darkAqua)
        let leadingPixels = Int(SAClaudeStyle.sidebarIconLeading * 2)
        for x in 0..<(leadingPixels - 1) {
            for y in 0..<rep.pixelsHigh {
                XCTAssertLessThan(rep.colorAt(x: x, y: y)?.alphaComponent ?? 0, 0.01, "ink at x=\(x)")
            }
        }
    }

    /// Verifies the editor bar's glyphs render and are named.
    func testEditorBarGlyphs() {
        for glyph in [SAClaudeGlyph.more, .favorite, .history] {
            let image = SAClaudeGlyphs.image(glyph, tint: .gray)
            XCTAssertNotNil(strokeColour(render(image, .darkAqua)), "glyph \(glyph.rawValue) draws nothing")
            XCTAssertFalse(image.accessibilityDescription?.isEmpty ?? true)
        }
        XCTAssertEqual(SAClaudeGlyph.infoPanel.rawValue, 8, "existing raw values unchanged")
        XCTAssertEqual(SAClaudeGlyph.clear.rawValue, 14, "existing raw values unchanged")
        XCTAssertEqual(SAClaudeGlyph.field.rawValue, 15)
        XCTAssertEqual(SAClaudeGlyph.keyword.rawValue, 16)
    }

    /// Verifies the toolbar colour follows the appearance: 0x1A1A19 dark, 0xF4F3EF light.
    func testToolbarBackgroundFollowsTheAppearance() {
        var dark: NSColor?, light: NSColor?
        NSAppearance(named: .darkAqua)!.performAsCurrentDrawingAppearance { dark = SAClaudeStyle.toolbarBackground.usingColorSpace(.sRGB) }
        NSAppearance(named: .aqua)!.performAsCurrentDrawingAppearance { light = SAClaudeStyle.toolbarBackground.usingColorSpace(.sRGB) }
        XCTAssertEqual(dark?.redComponent ?? 0, 0x1A / 255, accuracy: 0.01)
        XCTAssertEqual(light?.redComponent ?? 0, 0xF4 / 255, accuracy: 0.01)
    }
}
