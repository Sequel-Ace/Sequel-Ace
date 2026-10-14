//
//  SAClaudeEditorChrome.swift
//  Sequel Ace
//
//  Pure values for the Claude-style query editor pane: colours derived from
//  the editor theme, the Run button's clay, bar geometry and the Run button
//  layout. Shared with the Unit Tests target.
//

import AppKit

@objc final class SAClaudeEditorChrome: NSObject {

    // MARK: - Theme-derived colours

    static let hairlineRatio: CGFloat = 0.08
    static let hoverRatio: CGFloat = 0.08
    static let buttonTextRatio: CGFloat = 0.78
    static let iconRatio: CGFloat = 0.55
    static let gutterRatio: CGFloat = 0.36

    struct Palette: Equatable {
        let background: NSColor
        let hairline: NSColor
        let hover: NSColor
        let buttonText: NSColor
        let icon: NSColor
        let gutterNumbers: NSColor
    }

    /// `background + (text − background) × ratio`, per channel, blended in the
    /// background's own RGB colour space (the theme loader stores calibrated
    /// RGB) and returned in it; sRGB when the background is not an RGB colour.
    static func derivedColour(text: NSColor, background: NSColor, ratio: CGFloat) -> NSColor {
        // `colorSpace` is only valid for component-based colours (not catalog/dynamic ones).
        let space: NSColorSpace = background.type == .componentBased && background.colorSpace.colorSpaceModel == .rgb
            ? background.colorSpace : .sRGB
        let t = text.usingColorSpace(space) ?? NSColor.white.usingColorSpace(space)!
        let b = background.usingColorSpace(space) ?? NSColor.black.usingColorSpace(space)!
        func mix(_ tv: CGFloat, _ bv: CGFloat) -> CGFloat { bv + (tv - bv) * ratio }
        var components: [CGFloat] = [mix(t.redComponent, b.redComponent), mix(t.greenComponent, b.greenComponent),
                                     mix(t.blueComponent, b.blueComponent), 1]
        return NSColor(colorSpace: space, components: &components, count: 4)
    }

    static func palette(text: NSColor, background: NSColor) -> Palette {
        Palette(background: background,
                hairline: derivedColour(text: text, background: background, ratio: hairlineRatio),
                hover: derivedColour(text: text, background: background, ratio: hoverRatio),
                buttonText: derivedColour(text: text, background: background, ratio: buttonTextRatio),
                icon: derivedColour(text: text, background: background, ratio: iconRatio),
                gutterNumbers: derivedColour(text: text, background: background, ratio: gutterRatio))
    }

    /// The palette for the editor's current theme colours.
    static func palette(from defaults: UserDefaults) -> Palette {
        let text = SAArchiving.color(from: defaults.data(forKey: SAEditorThemeLoader.textColourKey)) ?? .textColor
        let background = SAArchiving.color(from: defaults.data(forKey: SAEditorThemeLoader.backgroundColourKey)) ?? .textBackgroundColor
        return palette(text: text, background: background)
    }

    // MARK: - Run button

    /// The accent fill (clay `#C6613F` unless the user chose an accent colour).
    @objc static var runFill: NSColor { SAClaudeAccent.fill }
    /// The pressed fill: the fill mixed towards white (dark appearance) or black (light), by the app's effective appearance.
    @objc static var runFillPressed: NSColor {
        SAClaudeAccent.fillPressed(darkTheme: NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
    }

    // MARK: - Metrics

    @objc static let barHeight: CGFloat = 44
    @objc static let buttonHeight: CGFloat = 28
    @objc static let barSidePadding: CGFloat = 10
    @objc static let buttonGap: CGFloat = 2
    @objc static let editorTopInset: CGFloat = 10
    static let runSidePadding: CGFloat = 12
    static let runPlaySize: CGFloat = 9
    static let runPlayGap: CGFloat = 6
    static let runShortcutGap: CGFloat = 8

    // MARK: - Bar geometry (non-flipped container)

    /// Pins the bar, `height` tall and full width, to the top of its `container`
    /// (so it neither overhangs the split divider above nor leaves a gap below);
    /// the results area keeps its bottom, x and width and runs up to the bar.
    static func barFrames(container: NSRect, results: NSRect, height: CGFloat) -> (bar: NSRect, results: NSRect) {
        let bar = NSRect(x: container.minX, y: container.maxY - height, width: container.width, height: height)
        var newResults = results
        newResults.size.height = max(0, bar.minY - results.minY)
        return (bar, newResults)
    }

    static func centredY(height: CGFloat, in barHeight: CGFloat) -> CGFloat {
        ((barHeight - height) / 2).rounded(.down)
    }

    static func leadingXs(widths: [CGFloat], start: CGFloat, gap: CGFloat) -> [CGFloat] {
        var x = start
        return widths.map { w in defer { x += w + gap }; return x }
    }

    // MARK: - Shortcut hint

    /// For single printable key equivalents; special keys such as "\r" are not mapped to symbols.
    static func shortcutString(keyEquivalent: String, modifiers: NSEvent.ModifierFlags) -> String {
        guard !keyEquivalent.isEmpty else { return "" }
        var s = ""
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option) { s += "⌥" }
        if modifiers.contains(.shift) { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        return s + keyEquivalent.uppercased()
    }

    // MARK: - Run button layout

    struct RunLayout {
        let playRect: NSRect
        let titleOrigin: NSPoint
        let shortcutOrigin: NSPoint
        let dividerX: CGFloat
        let chevronRect: NSRect
    }

    /// Width that fits the play glyph, title, shortcut hint and chevron segment.
    static func runWidth(titleWidth: CGFloat, shortcutWidth: CGFloat, lineOffset: CGFloat) -> CGFloat {
        runSidePadding + runPlaySize + runPlayGap + titleWidth + runShortcutGap + shortcutWidth + runSidePadding + lineOffset
    }

    /// Positions inside the button; the divider is where SPComboPopupButton splits clicks.
    static func runLayout(bounds: NSRect, lineOffset: CGFloat, titleSize: NSSize, shortcutSize: NSSize) -> RunLayout {
        let dividerX = bounds.maxX - lineOffset
        let midY = bounds.midY
        let play = NSRect(x: bounds.minX + runSidePadding, y: midY - runPlaySize / 2, width: runPlaySize, height: runPlaySize)
        let titleX = play.maxX + runPlayGap
        let shortcutX = min(titleX + titleSize.width + runShortcutGap, dividerX - runSidePadding - shortcutSize.width)
        return RunLayout(playRect: play,
                         titleOrigin: NSPoint(x: titleX, y: midY - titleSize.height / 2),
                         shortcutOrigin: NSPoint(x: shortcutX, y: midY - shortcutSize.height / 2),
                         dividerX: dividerX,
                         chevronRect: NSRect(x: dividerX, y: bounds.minY, width: lineOffset, height: bounds.height))
    }
}
