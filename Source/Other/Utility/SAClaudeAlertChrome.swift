//
//  SAClaudeAlertChrome.swift
//  Sequel Ace
//
//  The fixed values of the Claude alert card: one glyph and tone per alert kind, the card's fonts and the tinted
//  tile fill. Shared with the Unit Tests target (AppKit, `SAClaudeAlertKind` and `SAClaudeEditorChrome` only).
//

import AppKit

/// The colours the alert card draws with, resolved from the editor theme by whoever builds the card.
struct SAClaudeAlertCardColours: Equatable {
    var surface: NSColor
    var text: NSColor
    var secondaryText: NSColor
    var hairline: NSColor
    var blockFill: NSColor
}

enum SAClaudeAlertChrome {
    /// A true red `#C03A2E`, distinct from the clay accent (`#C6613F`) and from the error clay (`#D97757`), so a red
    /// "Delete" never reads as an ordinary OK. Used for the destructive button's fill (white text on it is 5.4:1) and the
    /// Error / Destructive glyph on a light card; a dark card draws the glyph in the lighter `redGlyphDark`.
    static let red = NSColor(srgbRed: 0xC0 / 255.0, green: 0x3A / 255.0, blue: 0x2E / 255.0, alpha: 1)
    /// The Warning tone follows the appearance it is drawn in: `#D4A13A` on a dark card, the deeper `#B7801A` on a
    /// light one (the lighter amber is too faint on a light surface).
    static let amberDark = NSColor(srgbRed: 0xD4 / 255.0, green: 0xA1 / 255.0, blue: 0x3A / 255.0, alpha: 1)
    static let amberLight = NSColor(srgbRed: 0xB7 / 255.0, green: 0x80 / 255.0, blue: 0x1A / 255.0, alpha: 1)
    static let amber = NSColor(name: "SAClaudeAlertAmber") { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? amberDark : amberLight
    }
    /// The Error / Destructive glyph tone: `red` on a light card, a lighter `#E0574A` on a dark one (`red` is only
    /// 2.3-2.6:1 on a dark card's tile; this is 3.1:1 or more).
    static let redGlyphDark = NSColor(srgbRed: 0xE0 / 255.0, green: 0x57 / 255.0, blue: 0x4A / 255.0, alpha: 1)
    static let redGlyph = NSColor(name: "SAClaudeAlertRedGlyph") { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? redGlyphDark : red
    }
    /// A secondary destructive button (a delete-type destructive button other than the default one): a 1pt dashed outline and the
    /// title in this red, `red` on a light card and `redGlyphDark` on a dark one; pressed, filled with it at 10%.
    static var destructiveOutline: NSColor { redGlyph }
    static let destructiveOutlineDash: [CGFloat] = [4, 3]
    static let destructiveOutlineWidth: CGFloat = 1
    /// Pulled in from the button's edge (the 1pt stroke spans 0.5-1.5pt in): optical, a bright dashed line reads larger than a dim solid one.
    static let destructiveOutlineInset: CGFloat = 1
    static let destructiveOutlinePressedAlpha: CGFloat = 0.10
    /// The Info glyph tone: `#4FA05A` on a dark card, the deeper `#3E8A4A` on a light one (the lighter green is 2.5-2.7:1
    /// on a light tile).
    static let greenDark = NSColor(srgbRed: 0x4F / 255.0, green: 0xA0 / 255.0, blue: 0x5A / 255.0, alpha: 1)
    static let greenLight = NSColor(srgbRed: 0x3E / 255.0, green: 0x8A / 255.0, blue: 0x4A / 255.0, alpha: 1)
    static let green = NSColor(name: "SAClaudeAlertGreen") { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? greenDark : greenLight
    }

    /// The tile is the surface mixed this far towards the tone.
    static let tileFillRatio: CGFloat = 0.13

    static let titleFont = NSFont.systemFont(ofSize: 14, weight: .medium)
    static let messageFont = NSFont.systemFont(ofSize: 12)
    static let blockLabelFont = NSFont.systemFont(ofSize: 11)
    static let serverFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)

    static let glyphPointSize: CGFloat = 18

    static func symbolName(for kind: SAClaudeAlertKind) -> String {
        switch kind {
        case .error: return "xmark.circle"
        case .destructive: return "trash"
        case .warning: return "exclamationmark.triangle"
        case .question: return "questionmark.circle"
        case .info: return "checkmark.circle"
        }
    }

    /// Question is neutral: the card's secondary text colour.
    static func tone(for kind: SAClaudeAlertKind, secondaryText: NSColor) -> NSColor {
        switch kind {
        case .error, .destructive: return redGlyph
        case .warning: return amber
        case .question: return secondaryText
        case .info: return green
        }
    }

    /// `surface + (tone − surface) × tileFillRatio`.
    static func tileFill(tone: NSColor, surface: NSColor) -> NSColor {
        SAClaudeEditorChrome.derivedColour(text: tone, background: surface, ratio: tileFillRatio)
    }
}
