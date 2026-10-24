//
//  SAClaudeProcessListTones.swift
//  Sequel Ace
//
//  The Process List's status colours: the vivid palette by group (`SAClaudeKindColours`: Rose needs attention, Amber
//  running, Slate idle), the ink for dots, stripes and text and the tint for a selected chip, each picked by the
//  theme's lightness. The alert colours stay for the Kill buttons and alerts. Pure AppKit, shared with the Unit Tests
//  target; the SwiftUI palette overloads live with the panels (SAClaudeProcessListPanels.swift).
//

import AppKit

enum SAClaudeProcessListTones {
    /// The alert card's red: the Kill buttons.
    static func red(dark: Bool) -> NSColor { dark ? SAClaudeAlertChrome.redGlyphDark : SAClaudeAlertChrome.red }

    /// A group's dots, row stripe and attention text: its colour's ink.
    static func colour(for group: SAClaudeProcessGroup, dark: Bool) -> NSColor {
        SAClaudeKindColours.colour(for: group).ink(dark: dark)
    }

    /// A selected status chip's fill: its group's tint.
    static func tint(for group: SAClaudeProcessGroup, dark: Bool) -> NSColor {
        SAClaudeKindColours.colour(for: group).tint(dark: dark)
    }

    /// A needs-attention row's state and time text: the Rose ink, lifted just enough to read at 4.5:1 (as
    /// `SAClaudeHintCardPalette.readable` does) on the list's `selection`, so it stays readable on a selected row.
    /// Claude Dark's selection takes the dark ink to 4.4:1, so it lightens a little; Claude Light's keeps the ink.
    static func attentionText(dark: Bool, selection: NSColor) -> NSColor {
        SAClaudeHintCardPalette.readable(colour(for: .needsAttention, dark: dark), on: selection)
    }

    /// A status chip's count: the group's ink while it counts something; nil (the muted text colour) at 0, so an
    /// empty group never looks like a problem.
    static func countColour(for group: SAClaudeProcessGroup, count: Int, dark: Bool) -> NSColor? {
        count > 0 ? colour(for: group, dark: dark) : nil
    }
}
