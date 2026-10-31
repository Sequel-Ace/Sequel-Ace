//
//  SAFontDisplayName.swift
//  Sequel Ace
//
//  Created by Sequel-Ace contributors on 2026.10.27.
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import AppKit

/// A user-facing "family + style" name for a font.
///
/// AppKit's `displayName` for system UI fonts is an internal name (for the
/// system monospaced font at regular weight it is ".SF NS Mono Light Regular":
/// a leading dot, and a weight that does not match the font). This maps those
/// fonts to the names users know, and leaves every other font's `displayName`
/// unchanged. AppKit only, so it is also compiled into the Unit Tests target.
@objc public final class SAFontDisplayName: NSObject {

    /// "SF Mono Regular" for the system monospaced font, "SF Pro Bold" for the
    /// system font, and `font.displayName` for anything else.
    @objc(nameForFont:)
    public static func name(for font: NSFont) -> String {
        let fontName = font.fontName
        let displayName = font.displayName ?? fontName

        if fontName.hasPrefix(".AppleSystemUIFontMonospaced") || displayName.hasPrefix(".SF NS Mono") {
            return "SF Mono " + styleName(for: font)
        }
        if fontName.hasPrefix(".AppleSystemUIFont") || displayName.hasPrefix(".SF NS") {
            return "SF Pro " + styleName(for: font)
        }
        return displayName
    }

    private static let weightNames: [(weight: NSFont.Weight, name: String)] = [
        (.ultraLight, "Ultralight"),
        (.thin, "Thin"),
        (.light, "Light"),
        (.regular, "Regular"),
        (.medium, "Medium"),
        (.semibold, "Semibold"),
        (.bold, "Bold"),
        (.heavy, "Heavy"),
        (.black, "Black")
    ]

    /// The style from the font's weight trait (not from its display name),
    /// snapped to the nearest named weight.
    private static func styleName(for font: NSFont) -> String {
        let traits = font.fontDescriptor.object(forKey: .traits) as? [NSFontDescriptor.TraitKey: Any]
        let weight = (traits?[.weight] as? NSNumber)?.doubleValue ?? 0
        let nearest = weightNames.min { abs($0.weight.rawValue - weight) < abs($1.weight.rawValue - weight) }
        return nearest?.name ?? "Regular"
    }
}
