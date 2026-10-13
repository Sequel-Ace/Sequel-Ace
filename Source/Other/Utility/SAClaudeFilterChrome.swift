//
//  SAClaudeFilterChrome.swift
//  Sequel Ace
//
//  The Content filter bar's Claude look as numbers and colours: control
//  sizes, the field and drop-zone fills, and where a pill's title and a
//  checkbox's square go. Shared with the unit tests.
//

import AppKit

enum SAClaudeFilterChrome {
    static let controlHeight: CGFloat = 24
    static let rowHeight: CGFloat = 32
    static let checkboxSize: CGFloat = 14
    static let checkboxRadius: CGFloat = 4
    static let selectorWidth: CGFloat = 14
    static let pillPadding: CGFloat = 9

    static func fieldFill(text: NSColor, background: NSColor) -> NSColor {
        SAClaudeEditorChrome.derivedColour(text: text, background: background, ratio: 0.035)
    }

    /// The Table Info cards' fill: the theme background lifted a little towards the text, quieter than a field.
    static let cardFillRatio: CGFloat = 0.025
    static func cardFill(text: NSColor, background: NSColor) -> NSColor {
        SAClaudeEditorChrome.derivedColour(text: text, background: background, ratio: cardFillRatio)
    }

    /// How far the idle drop-zone outline sits from the background towards the text; brighter than the
    /// palette hairline (0.08), which was invisible in dark mode.
    static let dropStrokeRatio: CGFloat = 0.30

    static func dropStroke(text: NSColor, background: NSColor) -> NSColor {
        SAClaudeEditorChrome.derivedColour(text: text, background: background, ratio: dropStrokeRatio)
    }

    static func dropHoverFill(background: NSColor) -> NSColor {
        SAClaudeEditorChrome.derivedColour(text: SAClaudeStatusChrome.clay, background: background, ratio: 0.12)
    }

    static func controlFrame(in cellFrame: NSRect) -> NSRect {
        NSRect(x: cellFrame.minX, y: (cellFrame.midY - controlHeight / 2).rounded(), width: cellFrame.width, height: controlHeight)
    }

    static func pillTitleRect(in pillFrame: NSRect) -> NSRect {
        let minX = pillFrame.minX + pillPadding
        let maxX = pillFrame.maxX - selectorWidth - 4
        return NSRect(x: minX, y: pillFrame.minY, width: max(0, maxX - minX), height: pillFrame.height)
    }

    static func checkboxRect(in cellFrame: NSRect) -> NSRect {
        NSRect(x: cellFrame.minX, y: (cellFrame.midY - checkboxSize / 2).rounded(), width: checkboxSize, height: checkboxSize)
    }
}
