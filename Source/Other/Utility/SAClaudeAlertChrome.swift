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
    /// "Delete" never reads as an ordinary OK. Used for the Error / Destructive tile and the destructive button.
    static let red = NSColor(srgbRed: 0xC0 / 255.0, green: 0x3A / 255.0, blue: 0x2E / 255.0, alpha: 1)
    static let amber = NSColor(srgbRed: 0xD4 / 255.0, green: 0xA1 / 255.0, blue: 0x3A / 255.0, alpha: 1)
    static let green = NSColor(srgbRed: 0x4F / 255.0, green: 0xA0 / 255.0, blue: 0x5A / 255.0, alpha: 1)

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
        case .error, .destructive: return red
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
