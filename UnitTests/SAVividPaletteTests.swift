//
//  SAVividPaletteTests.swift
//  Unit Tests
//

import XCTest
import AppKit

final class SAVividPaletteTests: XCTestCase {

    private let darkSurfaces: [UInt32] = [0x111111, 0x1A1A19, 0x1F1E1D, 0x262624]
    private let lightSurfaces: [UInt32] = [0xFFFFFF, 0xF6F6F4, 0xF4F3EF, 0xEBEAE5]

    private func rgba(_ c: NSColor) -> [CGFloat] {
        let s = c.usingColorSpace(.sRGB)!
        return [s.redComponent, s.greenComponent, s.blueComponent, s.alphaComponent]
    }

    private func hex(_ c: NSColor) -> UInt32 {
        let v = rgba(c).prefix(3).map { UInt32(($0 * 255).rounded()) }
        return v[0] << 16 | v[1] << 8 | v[2]
    }

    /// `c` laid over the opaque surface `0xRRGGBB`.
    private func composite(_ c: NSColor, over surface: UInt32) -> NSColor {
        let top = rgba(c)
        let base = rgba(SAClaudeStyle.srgb(surface))
        let mixed = (0..<3).map { top[$0] * top[3] + base[$0] * (1 - top[3]) }
        return NSColor(srgbRed: mixed[0], green: mixed[1], blue: mixed[2], alpha: 1)
    }

    private func contrast(_ a: NSColor, _ b: NSColor) -> CGFloat {
        let la = SAClaudeAccent.relativeLuminance(a)
        let lb = SAClaudeAccent.relativeLuminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    private func resolved(_ colour: NSColor, _ appearance: NSAppearance.Name) -> NSColor {
        var result = colour
        NSAppearance(named: appearance)!.performAsCurrentDrawingAppearance { result = colour.usingColorSpace(.sRGB)! }
        return result
    }

    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    func testStoredIndicesKeepTheirMeaning() {
        let expected: [(Int, SAVividColour, String)] = [
            (0, .rose, "favoriteRed"), (1, .orange, "favoriteOrange"), (2, .amber, "favoriteYellow"),
            (3, .emerald, "favoriteGreen"), (4, .sky, "favoriteBlue"), (5, .violet, "favoritePurple"),
            (6, .slate, "favoriteGraphite"), (7, .teal, "favoriteTeal"), (8, .blue, "favoriteIndigo"),
            (9, .pink, "favoritePink")
        ]
        XCTAssertEqual(expected.count, SAVividColour.allCases.count)
        for (index, colour, asset) in expected {
            XCTAssertEqual(SAVividColour(index: index), colour)
            XCTAssertEqual(colour.rawValue, index)
            XCTAssertEqual(colour.assetName, asset)
        }
    }

    func testOutOfRangeIndexHasNoColour() {
        for index in [-1, 10, 99, Int.min] {
            XCTAssertNil(SAVividColour(index: index), "\(index)")
        }
    }

    func testAssetNameRoundTrips() {
        for colour in SAVividColour.allCases {
            XCTAssertEqual(SAVividColour(assetName: colour.assetName), colour)
            XCTAssertEqual(SAVividColour(assetName: colour.assetName + "-tab"), colour)
        }
        XCTAssertNil(SAVividColour(assetName: "favoriteMauve"))
        XCTAssertNil(SAVividColour(assetName: ""))
    }

    func testValuesAreTheTable() {
        let table: [SAVividColour: (UInt32, UInt32, UInt32, UInt32)] = [
            .rose: (0xF43F5E, 0xFB7185, 0xE11D48, 0x9F1239),
            .orange: (0xF97316, 0xFB923C, 0xEA580C, 0x9A3412),
            .amber: (0xF5B21B, 0xFBBF24, 0xD97706, 0x92400E),
            .emerald: (0x22C55E, 0x4ADE80, 0x16A34A, 0x166534),
            .sky: (0x38BDF8, 0x38BDF8, 0x0284C7, 0x075985),
            .violet: (0x8B5CF6, 0xA78BFA, 0x7C3AED, 0x5B21B6),
            .slate: (0x94A3B8, 0xCBD5E1, 0x64748B, 0x334155),
            .teal: (0x14B8A6, 0x2DD4BF, 0x0D9488, 0x115E59),
            .blue: (0x4F6BFF, 0x8EA0FF, 0x3B55E6, 0x2A3DB8),
            .pink: (0xEC4899, 0xF472B6, 0xDB2777, 0x9D174D)
        ]
        for colour in SAVividColour.allCases {
            let row = table[colour]!
            XCTAssertEqual(hex(colour.fill(dark: true)), row.0, "\(colour) dark fill")
            XCTAssertEqual(hex(colour.ink(dark: true)), row.1, "\(colour) dark ink")
            XCTAssertEqual(hex(colour.fill(dark: false)), row.2, "\(colour) light fill")
            XCTAssertEqual(hex(colour.ink(dark: false)), row.3, "\(colour) light ink")
        }
    }

    func testRainbowOrderHasEveryColourOnce() {
        XCTAssertEqual(SAVividColour.rainbowOrder, [.rose, .orange, .amber, .emerald, .teal, .sky, .blue, .violet, .pink, .slate])
        XCTAssertEqual(Set(SAVividColour.rainbowOrder), Set(SAVividColour.allCases))
        XCTAssertEqual(SAVividColour.rainbowOrder.count, SAVividColour.allCases.count)
    }

    func testInkOnTintIsReadable() {
        for colour in SAVividColour.allCases {
            for s in darkSurfaces {
                let ratio = contrast(colour.ink(dark: true), composite(colour.tint(dark: true), over: s))
                XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(colour) dark ink on \(String(s, radix: 16))")
            }
            for s in lightSurfaces {
                let ratio = contrast(colour.ink(dark: false), composite(colour.tint(dark: false), over: s))
                XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(colour) light ink on \(String(s, radix: 16))")
            }
        }
    }

    func testFillsStandOutFromSurfaces() {
        for colour in SAVividColour.allCases {
            for s in darkSurfaces {
                XCTAssertGreaterThanOrEqual(contrast(colour.fill(dark: true), SAClaudeStyle.srgb(s)), 2.5, "\(colour) dark fill on \(String(s, radix: 16))")
            }
            for s in lightSurfaces {
                XCTAssertGreaterThanOrEqual(contrast(colour.fill(dark: false), SAClaudeStyle.srgb(s)), 2.5, "\(colour) light fill on \(String(s, radix: 16))")
            }
        }
    }

    func testDynamicColoursFollowTheAppearance() {
        XCTAssertEqual(SAVividColour.tintAlphaDark, 0.16)
        XCTAssertEqual(SAVividColour.tintAlphaLight, 0.12)
        for colour in SAVividColour.allCases {
            for (name, dark) in [(NSAppearance.Name.darkAqua, true), (NSAppearance.Name.aqua, false)] {
                XCTAssertEqual(rgba(resolved(colour.fillColour, name)), rgba(colour.fill(dark: dark)), "\(colour) fill \(name)")
                XCTAssertEqual(rgba(resolved(colour.inkColour, name)), rgba(colour.ink(dark: dark)), "\(colour) ink \(name)")
                XCTAssertEqual(rgba(resolved(colour.tintColour, name)), rgba(colour.tint(dark: dark)), "\(colour) tint \(name)")
            }
            XCTAssertEqual(rgba(resolved(colour.tintColour, .darkAqua))[3], 0.16, accuracy: 0.001)
            XCTAssertEqual(rgba(resolved(colour.tintColour, .aqua))[3], 0.12, accuracy: 0.001)
        }
    }

    func testAssetsMatchThePalette() throws {
        func components(_ entry: [String: Any]) throws -> [CGFloat] {
            let color = try XCTUnwrap(entry["color"] as? [String: Any])
            XCTAssertEqual(color["color-space"] as? String, "srgb")
            let c = try XCTUnwrap(color["components"] as? [String: String])
            return try ["red", "green", "blue", "alpha"].map { CGFloat(try XCTUnwrap(Double(try XCTUnwrap(c[$0])))) }
        }
        for colour in SAVividColour.allCases {
            for name in [colour.assetName, colour.assetName + "-tab"] {
                let url = repoRoot.appendingPathComponent("Resources/Colors.xcassets/\(name).colorset/Contents.json")
                let data = try Data(contentsOf: url)
                let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
                let entries = try XCTUnwrap(json["colors"] as? [[String: Any]], name)
                XCTAssertEqual(entries.count, 3, name)
                for entry in entries {
                    let appearance = (entry["appearances"] as? [[String: String]])?.first?["value"]
                    let expected = rgba(colour.fill(dark: appearance == "dark"))
                    let actual = try components(entry)
                    XCTAssertEqual(actual[3], 1, accuracy: 0.001, name)
                    for i in 0..<3 {
                        XCTAssertEqual(actual[i], expected[i], accuracy: 1.0 / 255, "\(name) \(appearance ?? "universal") component \(i)")
                    }
                }
                XCTAssertEqual(entries.filter { $0["appearances"] == nil }.count, 1, name)
            }
        }
    }

    func testColourNamesAreLocalized() throws {
        let url = repoRoot.appendingPathComponent("Resources/Localization/en.lproj/Localizable.strings")
        let strings = try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: String])
        let expected: [SAVividColour: String] = [
            .rose: "Rose", .orange: "Orange", .amber: "Amber", .emerald: "Emerald", .sky: "Sky",
            .violet: "Violet", .slate: "Slate", .teal: "Teal", .blue: "Blue", .pink: "Pink"
        ]
        for colour in SAVividColour.allCases {
            XCTAssertEqual(strings[colour.nameKey], expected[colour], "\(colour)")
        }
    }
}
