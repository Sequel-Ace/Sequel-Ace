//
//  SAVividPalette.swift
//  Sequel Ace
//
//  The ten-colour favourite palette of the Claude look. The raw value of
//  `SAVividColour` is the stored favourite colour index (0...6 keep their old
//  meaning: red...graphite), so saved favourites never change. Each colour has
//  a fill (dots, lines, rings) and an ink (text and glyphs on its tint), in a
//  dark and a light variant. Shared with the Unit Tests target.
//

import AppKit

enum SAVividColour: Int, CaseIterable {
    case rose = 0, orange, amber, emerald, sky, violet, slate, teal, blue, pink

    /// The colours in rainbow order, as the connection colour picker lists them.
    static let rainbowOrder: [SAVividColour] = [.rose, .orange, .amber, .emerald, .teal, .sky, .blue, .violet, .pink, .slate]

    /// Alpha of the tint (the fill laid over a surface) in each appearance.
    static let tintAlphaDark: CGFloat = 0.16
    static let tintAlphaLight: CGFloat = 0.12

    /// The colour stored as `index`, or nil outside 0...9.
    init?(index: Int) {
        self.init(rawValue: index)
    }

    /// The colour of a colour-asset name; the `-tab` twin names the same colour.
    init?(assetName: String) {
        let base = assetName.hasSuffix("-tab") ? String(assetName.dropLast(4)) : assetName
        guard let colour = SAVividColour.allCases.first(where: { $0.assetName == base }) else { return nil }
        self = colour
    }

    /// The storage name of the colour asset (it predates the vivid names and stays).
    var assetName: String {
        switch self {
        case .rose: return "favoriteRed"
        case .orange: return "favoriteOrange"
        case .amber: return "favoriteYellow"
        case .emerald: return "favoriteGreen"
        case .sky: return "favoriteBlue"
        case .violet: return "favoritePurple"
        case .slate: return "favoriteGraphite"
        case .teal: return "favoriteTeal"
        case .blue: return "favoriteIndigo"
        case .pink: return "favoritePink"
        }
    }

    private var caseName: String {
        switch self {
        case .rose: return "rose"
        case .orange: return "orange"
        case .amber: return "amber"
        case .emerald: return "emerald"
        case .sky: return "sky"
        case .violet: return "violet"
        case .slate: return "slate"
        case .teal: return "teal"
        case .blue: return "blue"
        case .pink: return "pink"
        }
    }

    /// The localization key of the colour's name.
    var nameKey: String { "ClaudeFavouriteColour." + caseName }

    var localizedName: String {
        let fallback: String
        switch self {
        case .rose: fallback = "Rose"
        case .orange: fallback = "Orange"
        case .amber: fallback = "Amber"
        case .emerald: fallback = "Emerald"
        case .sky: fallback = "Sky"
        case .violet: fallback = "Violet"
        case .slate: fallback = "Slate"
        case .teal: fallback = "Teal"
        case .blue: fallback = "Blue"
        case .pink: fallback = "Pink"
        }
        return NSLocalizedString(nameKey, value: fallback, comment: "Favourite colour name, shown in the connection colour picker")
    }

    // MARK: - Values

    /// sRGB `0xRRGGBB` of (dark fill, dark ink, light fill, light ink).
    private var values: (darkFill: UInt32, darkInk: UInt32, lightFill: UInt32, lightInk: UInt32) {
        switch self {
        case .rose: return (0xF43F5E, 0xFB7185, 0xE11D48, 0x9F1239)
        case .orange: return (0xF97316, 0xFB923C, 0xEA580C, 0x9A3412)
        case .amber: return (0xF5B21B, 0xFBBF24, 0xD97706, 0x92400E)
        case .emerald: return (0x22C55E, 0x4ADE80, 0x16A34A, 0x166534)
        case .sky: return (0x38BDF8, 0x38BDF8, 0x0284C7, 0x075985)
        case .violet: return (0x8B5CF6, 0xA78BFA, 0x7C3AED, 0x5B21B6)
        case .slate: return (0x94A3B8, 0xCBD5E1, 0x64748B, 0x334155)
        case .teal: return (0x14B8A6, 0x2DD4BF, 0x0D9488, 0x115E59)
        case .blue: return (0x4F6BFF, 0x8EA0FF, 0x3B55E6, 0x2A3DB8)
        case .pink: return (0xEC4899, 0xF472B6, 0xDB2777, 0x9D174D)
        }
    }

    /// The colour of dots, lines and rings.
    func fill(dark: Bool) -> NSColor {
        SAClaudeStyle.srgb(dark ? values.darkFill : values.lightFill)
    }

    /// The colour of text and glyphs sitting on the tint.
    func ink(dark: Bool) -> NSColor {
        SAClaudeStyle.srgb(dark ? values.darkInk : values.lightInk)
    }

    /// The fill at the tint alpha, to lay over a surface.
    func tint(dark: Bool) -> NSColor {
        fill(dark: dark).withAlphaComponent(dark ? SAVividColour.tintAlphaDark : SAVividColour.tintAlphaLight)
    }

    // MARK: - Dynamic colours

    private static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    /// `fill` that follows the appearance it is drawn in.
    var fillColour: NSColor {
        NSColor(name: NSColor.Name("SAVivid.fill." + caseName)) { self.fill(dark: SAVividColour.isDark($0)) }
    }

    /// `ink` that follows the appearance it is drawn in.
    var inkColour: NSColor {
        NSColor(name: NSColor.Name("SAVivid.ink." + caseName)) { self.ink(dark: SAVividColour.isDark($0)) }
    }

    /// `tint` that follows the appearance it is drawn in.
    var tintColour: NSColor {
        NSColor(name: NSColor.Name("SAVivid.tint." + caseName)) { self.tint(dark: SAVividColour.isDark($0)) }
    }
}

/// The palette as the favourite colour list: one colour per stored index, in index order.
@objc(SAFavoritePalette) final class SAFavoritePalette: NSObject {
    /// The asset colours, resolved once. An asset that fails to load falls back to the palette's own
    /// dynamic fill, so an entry is never dropped and a stored index can never shift to another colour.
    @objc static let assetColours: [NSColor] = SAVividColour.allCases.map {
        NSColor(named: NSColor.Name($0.assetName)) ?? $0.fillColour
    }
}
