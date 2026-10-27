//
//  SADesignStyleTests.swift
//  Unit Tests
//

import AppKit
import XCTest

final class SADesignStyleTests: XCTestCase {

    /// Resolves a color under an appearance to 0xRRGGBB in sRGB.
    private func hex(_ color: NSColor, _ name: NSAppearance.Name) -> UInt32 {
        var value: UInt32 = 0
        NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
            let c = color.usingColorSpace(.sRGB)!
            value = UInt32((c.redComponent * 255).rounded()) << 16
                | UInt32((c.greenComponent * 255).rounded()) << 8
                | UInt32((c.blueComponent * 255).rounded())
        }
        return value
    }

    /// Verifies every color resolves to its exact value in dark and light.
    func testColorsResolveToTheirValues() {
        let expected: [(NSColor, UInt32, UInt32, String)] = [
            (SADesignStyle.selection, 0x343434, 0xE4E3DD, "selection"),
            (SADesignStyle.hoverFill, 0x1E1E1D, 0xEAE9E4, "hoverFill"),
            (SADesignStyle.divider, 0x202020, 0xE7E6E1, "divider"),
            (SADesignStyle.textPrimary, 0xF0EFEC, 0x0B0B0B, "textPrimary"),
            (SADesignStyle.textMuted, 0x898781, 0x7B7974, "textMuted"),
            (SADesignStyle.toolbarBackground, 0x1A1A19, 0xF4F3EF, "toolbarBackground"),
            (SADesignStyle.cardSurface, 0x2F2E2B, 0xFFFFFF, "cardSurface"),
            (SADesignStyle.cardHairline, 0x34332F, 0xD9D8D2, "cardHairline"),
        ]
        for (color, dark, light, name) in expected {
            XCTAssertEqual(hex(color, .darkAqua), dark, "\(name) dark")
            XCTAssertEqual(hex(color, .aqua), light, "\(name) light")
        }
    }

    /// Verifies `srgb` reads 0xRRGGBB as opaque sRGB components.
    func testSRGBReadsTheHexChannels() {
        let color = SADesignStyle.srgb(0x3366CC)
        XCTAssertEqual(color.colorSpace, .sRGB)
        XCTAssertEqual(color.redComponent, 0x33 / 255, accuracy: 0.0001)
        XCTAssertEqual(color.greenComponent, 0x66 / 255, accuracy: 0.0001)
        XCTAssertEqual(color.blueComponent, 0xCC / 255, accuracy: 0.0001)
        XCTAssertEqual(color.alphaComponent, 1)
    }
}
