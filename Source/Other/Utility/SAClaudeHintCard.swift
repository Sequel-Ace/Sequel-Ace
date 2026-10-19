//
//  SAClaudeHintCard.swift
//  Sequel Ace
//
//  The Claude hint card shared by the rare windows (tooltips, Type Info, the SQL help viewer, the
//  About window, the bundle HTML window): its palette, metrics and the CSS variables a web page
//  reads the palette through. Pure Foundation/AppKit so it is shared with the Unit Tests target.
//

import AppKit

// MARK: - Palette

/// The colours of one hint card.
struct SAClaudeHintCardPalette: Equatable {
    var surface, text, muted, hairline, accent, destructive, codeFill, selection: NSColor
    var isDark: Bool

    /// Opacity of the accent behind a text selection.
    static let selectionAlpha: CGFloat = 0.28

    /// The card for an editor theme: the theme's popup surface with its text, `accent` for links.
    static func make(theme: SAClaudeThemeColours, accent: NSColor) -> SAClaudeHintCardPalette {
        let isDark = SAClaudeGridChrome.isDark(theme.background)
        return build(surface: SAClaudeStatusChrome.popupSurface(theme: theme),
                     text: theme.text,
                     muted: SAClaudeStatusChrome.muted(theme: theme),
                     hairline: SAClaudeStatusChrome.hairline(theme: theme),
                     accent: accent,
                     destructive: isDark ? SAClaudeAlertChrome.redGlyphDark : SAClaudeAlertChrome.red,
                     isDark: isDark)
    }

    /// The light card a printed page and a bundle's own page sit on, whatever the theme: Sequel Ace's
    /// light Claude colours. A link in `accent` must read on the paper, so an accent below the
    /// body-text contrast of 4.5:1 is darkened, keeping its hue, until it reaches it.
    static func paper(accent: NSColor) -> SAClaudeHintCardPalette {
        build(surface: SAClaudeStyle.srgb(paperSurfaceHex),
              text: SAClaudeStyle.srgb(0x0B0B0B),
              muted: SAClaudeStyle.srgb(0x7B7974),
              hairline: SAClaudeStyle.srgb(0xE7E6E1),
              accent: readable(accent, on: SAClaudeStyle.srgb(paperSurfaceHex)),
              destructive: SAClaudeAlertChrome.red,
              isDark: false)
    }

    static let paperSurfaceHex: UInt32 = 0xFAF9F5
    /// WCAG AA for body text.
    static let readableContrast: CGFloat = 4.5

    private static func build(surface: NSColor, text: NSColor, muted: NSColor, hairline: NSColor, accent: NSColor,
                              destructive: NSColor, isDark: Bool) -> SAClaudeHintCardPalette {
        SAClaudeHintCardPalette(surface: surface, text: text, muted: muted, hairline: hairline, accent: accent,
                                destructive: destructive,
                                codeFill: SAClaudeEditorChrome.derivedColour(text: text, background: surface, ratio: 0.05),
                                selection: accent.withAlphaComponent(selectionAlpha),
                                isDark: isDark)
    }

    // MARK: Contrast

    /// WCAG contrast ratio of two colours, 1...21.
    static func contrast(_ a: NSColor, _ b: NSColor) -> CGFloat {
        let la = SAClaudeAccent.relativeLuminance(a), lb = SAClaudeAccent.relativeLuminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// `colour` itself when it reads on `background` (contrast ≥ 4.5), else the same hue and saturation
    /// with the HSB brightness stepped down until it does.
    static func readable(_ colour: NSColor, on background: NSColor) -> NSColor {
        guard contrast(colour, background) < readableContrast, let rgb = colour.usingColorSpace(.sRGB) else { return colour }
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        rgb.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        var result = rgb
        while brightness > 0, contrast(result, background) < readableContrast {
            brightness = max(0, brightness - 0.01)
            result = NSColor(hue: hue, saturation: saturation, brightness: brightness, alpha: alpha)
                .usingColorSpace(.sRGB) ?? result
        }
        return result
    }
}

// MARK: - Metrics

enum SAClaudeHintCard {
    static let cornerRadius: CGFloat = 8
    static let borderWidth: CGFloat = 1
    static let verticalPadding: CGFloat = 8
    static let horizontalPadding: CGFloat = 10
    static let maxWidth: CGFloat = 800
    static let proseFontSize: CGFloat = 12
    static let imageLimit: CGFloat = 200

    /// An image's size in a tooltip: the longer side clamped to `imageLimit`, the other scaled with it,
    /// in whole points (SPTooltip's downsizing, which worked in `NSInteger`s).
    static func imageFit(_ size: NSSize) -> NSSize {
        var w = Int(size.width), h = Int(size.height)
        if w > h {
            if size.width > imageLimit {
                w = Int(imageLimit)
                h = Int(imageLimit / size.width * size.height)
            }
        } else if size.height > imageLimit {
            h = Int(imageLimit)
            w = Int(imageLimit / size.height * size.width)
        }
        return NSSize(width: w, height: h)
    }

    /// The card around an image tooltip: the fitted image plus the card's padding.
    static func imageCardSize(_ imageSize: NSSize) -> NSSize {
        let fit = imageFit(imageSize)
        return NSSize(width: fit.width + 2 * horizontalPadding, height: fit.height + 2 * verticalPadding)
    }
}

// MARK: - CSS

/// The palette as CSS custom properties, which every hint-card web page styles itself with.
enum SAClaudeHintCardCSS {
    static let variableNames = ["--sa-surface", "--sa-text", "--sa-muted", "--sa-hairline",
                                "--sa-accent", "--sa-destructive", "--sa-code", "--sa-selection"]

    /// sRGB `#RRGGBB` (uppercase), or `rgba(r,g,b,a)` when the colour is translucent.
    static func colour(_ c: NSColor) -> String {
        guard let rgb = c.usingColorSpace(.sRGB) else { return "#000000" }
        func byte(_ v: CGFloat) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        let r = byte(rgb.redComponent), g = byte(rgb.greenComponent), b = byte(rgb.blueComponent)
        let a = rgb.alphaComponent
        if a < 1 {
            var alpha = String(format: "%.2f", Double(a))
            while alpha.hasSuffix("0") { alpha.removeLast() }
            if alpha.hasSuffix(".") { alpha.removeLast() }
            return "rgba(\(r),\(g),\(b),\(alpha))"
        }
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    private static func values(_ p: SAClaudeHintCardPalette) -> [String] {
        [colour(p.surface), colour(p.text), colour(p.muted), colour(p.hairline),
         colour(p.accent), colour(p.destructive), colour(p.codeFill), colour(p.selection)]
    }

    /// `--sa-surface:#…;…;color-scheme:dark` (every variable once, then the scheme).
    static func declarations(_ p: SAClaudeHintCardPalette) -> String {
        let pairs = zip(variableNames, values(p)).map { "\($0):\($1)" }
        return (pairs + ["color-scheme:\(p.isDark ? "dark" : "light")"]).joined(separator: ";")
    }

    static func rootRule(_ p: SAClaudeHintCardPalette) -> String { ":root{\(declarations(p))}" }

    /// `{"--sa-…":"…"}` with sorted keys, for scripts that restyle a live page.
    static func json(_ p: SAClaudeHintCardPalette) -> String {
        let object = Dictionary(uniqueKeysWithValues: zip(variableNames, values(p)))
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8) else { return "{}" }
        return string
    }

    /// Printing always uses the light paper, whatever the theme.
    static func printRule(paper: SAClaudeHintCardPalette) -> String { "@media print{:root{\(declarations(paper))}}" }

    static func pageStyle(theme: SAClaudeHintCardPalette, paper: SAClaudeHintCardPalette) -> String {
        rootRule(theme) + printRule(paper: paper)
    }
}
