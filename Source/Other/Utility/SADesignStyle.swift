//
//  SADesignStyle.swift
//  Sequel Ace
//
//  Colors and metrics of the design system's surfaces: the main window's
//  toolbar, its controls and the menu cards they open.
//  Pure AppKit so it is shared with the Unit Tests target.
//

import AppKit

@objc final class SADesignStyle: NSObject {

    // MARK: - Colors

    /// An sRGB color from 0xRRGGBB.
    static func srgb(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1)
    }

    /// A color that resolves to `dark` under a dark appearance and `light` otherwise.
    private static func dynamic(_ name: String, dark: UInt32, light: UInt32) -> NSColor {
        let darkColor = srgb(dark)
        let lightColor = srgb(light)
        return NSColor(name: NSColor.Name("SADesign." + name)) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? darkColor : lightColor
        }
    }

    @objc static let selection = dynamic("selection", dark: 0x343434, light: 0xE4E3DD)
    @objc static let hoverFill = dynamic("hoverFill", dark: 0x1E1E1D, light: 0xEAE9E4)
    @objc static let divider = dynamic("divider", dark: 0x202020, light: 0xE7E6E1)
    @objc static let textPrimary = dynamic("textPrimary", dark: 0xF0EFEC, light: 0x0B0B0B)
    @objc static let textMuted = dynamic("textMuted", dark: 0x898781, light: 0x7B7974)
    /// The main window's title bar and toolbar.
    @objc static let toolbarBackground = dynamic("toolbarBackground", dark: 0x1A1A19, light: 0xF4F3EF)
    /// The menu cards' raised surface and their hairline (outline and separators).
    @objc static let cardSurface = dynamic("cardSurface", dark: 0x2F2E2B, light: 0xFFFFFF)
    @objc static let cardHairline = dynamic("cardHairline", dark: 0x34332F, light: 0xD9D8D2)

    // MARK: - Metrics

    /// The stroke width of the 16pt outline glyphs (`SADesignGlyphs`).
    @objc static let iconStrokeWidth: CGFloat = 1.5
}
