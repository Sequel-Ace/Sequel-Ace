//
//  SAClaudeStyle.swift
//  Sequel Ace
//
//  Colours, fonts and metrics for the Claude-style left navigation (and the
//  later editor / output restyles). Values are the Claude desktop app's own
//  design tokens; see docs/superpowers/specs/2026-10-10-claude-sidebar-design.md.
//  Pure AppKit so it is shared with the Unit Tests target.
//

import AppKit

@objc final class SAClaudeStyle: NSObject {

    // MARK: - Colours

    /// An sRGB colour from 0xRRGGBB.
    static func srgb(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1)
    }

    /// A colour that resolves to `dark` under a dark appearance and `light` otherwise.
    private static func dynamic(_ name: String, dark: UInt32, light: UInt32) -> NSColor {
        let darkColor = srgb(dark)
        let lightColor = srgb(light)
        return NSColor(name: NSColor.Name("SAClaude." + name)) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? darkColor : lightColor
        }
    }

    @objc static let sidebarBackground = dynamic("sidebarBackground", dark: 0x111111, light: 0xF6F6F4)
    @objc static let selection = dynamic("selection", dark: 0x343434, light: 0xE4E3DD)
    @objc static let hoverFill = dynamic("hoverFill", dark: 0x1E1E1D, light: 0xEAE9E4)
    @objc static let divider = dynamic("divider", dark: 0x202020, light: 0xE7E6E1)
    @objc static let textPrimary = dynamic("textPrimary", dark: 0xF0EFEC, light: 0x0B0B0B)
    @objc static let textSecondary = dynamic("textSecondary", dark: 0xC3C2B7, light: 0x52514E)
    @objc static let textMuted = dynamic("textMuted", dark: 0x898781, light: 0x7B7974)
    /// The database glyph tint: the accent on a dark appearance, the accent's fill on a light one.
    @objc static var tintDatabase: NSColor {
        NSColor(name: NSColor.Name("SAClaude.tintDatabase")) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? SAClaudeAccent.accent : SAClaudeAccent.fill
        }
    }
    /// The object type tints: the ink of the type's vivid colour (`SAClaudeKindColours`), so a glyph reads on its chip.
    @objc static let tintTable = SAVividColour.sky.inkColour
    @objc static let tintView = SAVividColour.violet.inkColour
    @objc static let tintProcedure = SAVividColour.amber.inkColour
    @objc static let tintFunction = SAVividColour.emerald.inkColour
    /// The main window's title bar and toolbar.
    @objc static let toolbarBackground = dynamic("toolbarBackground", dark: 0x1A1A19, light: 0xF4F3EF)
    /// The window tab bar's chips: every tab, and the selected (raised) one.
    @objc static let tabFill = dynamic("tabFill", dark: 0x222221, light: 0xEBEAE5)
    @objc static let tabBorder = dynamic("tabBorder", dark: 0x34332F, light: 0xD9D8D2)
    @objc static let tabSelectedFill = dynamic("tabSelectedFill", dark: 0x2F2E2B, light: 0xFFFFFF)
    @objc static let tabSelectedBorder = dynamic("tabSelectedBorder", dark: 0x4A4944, light: 0xCFCEC8)

    // MARK: - Fonts (SF Pro)

    @objc static var rowFont: NSFont { .systemFont(ofSize: 14) }
    @objc static var headerFont: NSFont { .systemFont(ofSize: 13) }
    @objc static var infoFont: NSFont { .systemFont(ofSize: 12) }

    // MARK: - Metrics

    @objc static let rowHeight: CGFloat = 32
    @objc static let pillRadius: CGFloat = 8
    @objc static let pillInset: CGFloat = 8
    @objc static let rowContentPadding: CGFloat = 10
    @objc static let iconSize: CGFloat = 16
    @objc static let iconStrokeWidth: CGFloat = 1.5
    @objc static let iconTextGap: CGFloat = 10
    @objc static let barButtonRadius: CGFloat = 7
    @objc static let headerBottomPadding: CGFloat = 6
    /// Space kept clear at the right of a row: the pill inset plus its padding.
    @objc static let sidebarTrailingPadding: CGFloat = 18
    /// `ImageAndTextCell` draws its image this far in from the cell's left edge.
    @objc static let cellImageInset: CGFloat = 3
    /// A borderless `NSTextFieldCell` draws its text this far in from its frame.
    @objc static let cellTextInset: CGFloat = 2
    /// Space an info row's value keeps clear at the right, like the list's rows.
    @objc static let infoRowTrailingPadding: CGFloat = sidebarTrailingPadding
    /// Paragraph indent of an info row or pane header, so its text (after the
    /// text cell's own inset) starts `pillInset + rowContentPadding` in, like the names.
    @objc static var infoRowLeadingIndent: CGFloat { pillInset + rowContentPadding - cellTextInset }

    /// Where the 16pt glyph starts inside the padded sidebar icon canvas, so the
    /// icon lands `pillInset + rowContentPadding` from the list's left edge.
    @objc static var sidebarIconLeading: CGFloat { pillInset + rowContentPadding - cellImageInset }

    /// Width of the padded sidebar icon canvas, so the name starts
    /// `iconTextGap` after the icon.
    @objc static var sidebarIconCanvasWidth: CGFloat { sidebarIconLeading + iconSize + iconTextGap - cellTextInset }

    /// Height of one line of row text plus the text cell's insets.
    @objc static var rowTextHeight: CGFloat { SAClaudeLineHeight.ceiledHeight(for: rowFont) + cellTextInset }
}

/// Frames for the sidebar's cells and headers. Pure so it can be unit-tested.
enum SAClaudeSidebarGeometry {

    /// The frame a name cell is drawn and edited in: centred vertically on one
    /// line of text, stopping `sidebarTrailingPadding` short of the row's right edge.
    static func cellFrame(in rowCellFrame: NSRect, textHeight: CGFloat) -> NSRect {
        let height = min(rowCellFrame.height, textHeight)
        return NSRect(x: rowCellFrame.minX,
                      y: rowCellFrame.minY + floor((rowCellFrame.height - height) / 2),
                      width: max(0, rowCellFrame.width - SAClaudeStyle.sidebarTrailingPadding),
                      height: height)
    }

    /// The frame of a section header's text: aligned with the icons, sitting
    /// `headerBottomPadding` above the row's bottom (the list is flipped).
    static func headerTextFrame(in rowRect: NSRect, textHeight: CGFloat) -> NSRect {
        let x = rowRect.minX + SAClaudeStyle.pillInset + SAClaudeStyle.rowContentPadding
        return NSRect(x: x,
                      y: rowRect.maxY - SAClaudeStyle.headerBottomPadding - textHeight,
                      width: max(0, rowRect.maxX - SAClaudeStyle.sidebarTrailingPadding - x),
                      height: textHeight)
    }
}

/// Where the rounded selection pills go. Pure so it can be unit-tested.
enum SAClaudeSelectionLayout {

    /// One rect per run of adjacent selected rows, inset on both sides.
    ///
    /// - Parameters:
    ///   - selectedRows: Selected row indexes, in any order.
    ///   - rowRect: The rect of a row in the list's coordinates.
    ///   - inset: How far each pill stays in from the left and right edges.
    /// - Returns: The pill rects, top to bottom.
    static func pillRects(selectedRows: [Int], rowRect: (Int) -> NSRect, inset: CGFloat) -> [NSRect] {
        var runs: [[Int]] = []
        for row in selectedRows.sorted() {
            if let last = runs.last?.last, last + 1 == row {
                runs[runs.count - 1].append(row)
            } else {
                runs.append([row])
            }
        }
        return runs.map { run in
            let union = rowRect(run.first!).union(rowRect(run.last!))
            return NSRect(x: union.minX + inset, y: union.minY,
                          width: max(0, union.width - 2 * inset), height: union.height)
        }
    }
}
