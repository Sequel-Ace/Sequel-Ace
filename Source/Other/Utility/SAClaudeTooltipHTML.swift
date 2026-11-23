//
//  SAClaudeTooltipHTML.swift
//  Sequel Ace
//
//  The page SPTooltip loads into its web view: a text value escaped into a `<pre>` (in the caller's
//  cell font, or as 12pt prose) and the document around it, styled as the Claude hint card.
//  Pure Foundation/AppKit so it is shared with the Unit Tests target.
//

import AppKit

enum SAClaudeTooltipHTML {

    /// What the tooltip shows: a text value (Sequel Ace's own) or HTML (a bundle's output).
    enum Kind { case text, html }

    /// SPTooltip's font size rules: `fontsize` as a number or a string, 10 without it, never below 5.
    static let defaultFontSize = 10
    static let minimumFontSize = 5

    /// `text` escaped into a `<pre>`: in the caller's font when `fontname` is passed (a grid cell's
    /// font), else as the card's prose (`.sa-prose`, sized only when `fontsize` is passed).
    static func textBody(_ text: String, options: [String: Any]?) -> String {
        let escaped = text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        let size = fontSize(options?["fontsize"])
        if let name = options?["fontname"] as? String {
            return "<pre style=\"font-family:\(fontFamily(name)); font-size: \(size ?? defaultFontSize)px\">\(escaped)</pre>"
        }
        if let size {
            return "<pre class=\"sa-prose\" style=\"font-size: \(size)px\">\(escaped)</pre>"
        }
        return "<pre class=\"sa-prose\">\(escaped)</pre>"
    }

    /// The whole page: SPTooltip's skeleton with the card's padding and colours — the theme card for
    /// text and for plain bundle HTML (no colours or fonts of its own, `SAClaudePlainPage`; its links in
    /// the theme's readable accent), the light paper for HTML a bundle styled for a light page or shown
    /// on a caller's `backgroundcolor` or `transparent`.
    /// `backgroundcolor` (a `#hex` or a colour word) and `transparent` passed by a caller still win.
    static func document(body: String, kind: Kind, options: [String: Any]?, theme: SAClaudeHintCardPalette,
                         paper: SAClaudeHintCardPalette) -> String {
        // A caller's own background (or transparency) is a style too: keep the paper's dark text on it.
        let callerBackground = options?["backgroundcolor"] != nil || options?["transparent"] != nil
        let plainHTML = kind == .html && !callerBackground && SAClaudePlainPage.isPlain(body)
        let palette = kind == .text || plainHTML ? theme : paper
        let background: String
        if options?["transparent"] != nil {
            background = "transparent"
        } else if let requested = options?["backgroundcolor"] as? String, isSafeColour(requested) {
            background = requested
        } else {
            background = SAClaudeHintCardCSS.colour(palette.surface)
        }
        let padding = "\(Int(SAClaudeHintCard.verticalPadding))px \(Int(SAClaudeHintCard.horizontalPadding))px"
        return "<html>"
            + "<head>"
            + "<style type='text/css' media='screen'>"
            + "body { background: \(background); color: \(SAClaudeHintCardCSS.colour(palette.text)); margin: 0; "
            + "padding: \(padding); overflow: hidden; display: table-cell; max-width: \(Int(SAClaudeHintCard.maxWidth))px; }"
            + "pre { white-space: pre-wrap; margin: 0; }"
            + ".sa-prose { font-family: -apple-system, system-ui, sans-serif; "
            + "font-size: \(Int(SAClaudeHintCard.proseFontSize))px; white-space: pre-wrap; }"
            + (plainHTML ? "a:any-link { color: \(SAClaudeHintCardCSS.colour(theme.accent)); }" : "")
            + "</style>"
            + "</head>"
            + "<body>\(body)</body>"
            + "</html>"
    }

    /// The CSS `font-family` list for a caller's font (a grid cell's `NSFont.fontName`). WebKit can't reach the
    /// system UI fonts by name (".AppleSystemUIFont", ".SFNS-Regular", ".AppleSystemUIFontMonospaced-Regular", …) and
    /// would draw them in its serif default: those become `-apple-system` (monospaced: `ui-monospace`). A named font
    /// (Menlo-Regular, SF Mono, Helvetica) stays the first choice, quoted. Every list ends on a generic family that
    /// matches the font's pitch, so a name WebKit can't resolve never falls back to serif.
    static func fontFamily(_ name: String) -> String {
        let fixedPitch = isMonospacedName(name) || NSFont(name: name, size: 12)?.isFixedPitch == true
        let fallback = fixedPitch ? monospacedFallback : proportionalFallback
        let safe = sanitisedFontName(name).trimmingCharacters(in: .whitespaces)
        if safe.isEmpty || isSystemUIFontName(safe) { return fallback }
        return "'\(safe)', \(fallback)"
    }

    /// The generic families after a proportional / a fixed-pitch font.
    static let proportionalFallback = "-apple-system, system-ui, sans-serif"
    static let monospacedFallback = "ui-monospace, monospace"

    /// A font name safe inside `font-family:'…'` in a double-quoted `style` attribute: quotes, `;`, braces, angle
    /// brackets, `&` (an entity would be decoded inside the attribute), backslashes and control characters dropped.
    static func sanitisedFontName(_ name: String) -> String {
        let forbidden = CharacterSet(charactersIn: "'\";{}<>&\\").union(.controlCharacters)
        return String(String.UnicodeScalarView(name.unicodeScalars.filter { !forbidden.contains($0) }))
    }

    /// The system UI font as AppKit names it (hidden, dot-prefixed fonts; the SF NS PostScript names) or as CSS does.
    static func isSystemUIFontName(_ name: String) -> Bool {
        let lower = name.lowercased()
        return name.hasPrefix(".") || name.hasPrefix("SFNS")
            || ["-apple-system", "system-ui", "blinkmacsystemfont", "ui-monospace", "ui-sans-serif"].contains(lower)
    }

    // MARK: Private

    /// A monospaced system UI font name (`NSFont.monospacedSystemFont`), which NSFont may not resolve by name.
    private static func isMonospacedName(_ name: String) -> Bool {
        let lower = name.lowercased()
        // SF Mono by name too: it isn't a registered system font everywhere (CI machines), and its fallback must still
        // be monospaced.
        return lower.contains("monospaced") || lower == "ui-monospace" || lower.hasPrefix(".sfnsmono") || lower.hasPrefix("sfnsmono")
            || lower.hasPrefix("sfmono") || lower.hasPrefix("sf mono")
    }

    private static func fontSize(_ value: Any?) -> Int? {
        let size: Int
        switch value {
        case let number as NSNumber: size = number.intValue
        case let string as String: size = Int((string as NSString).intValue)
        default: return nil
        }
        return max(size, minimumFontSize)
    }

    /// `#` and 3–8 hex digits, or a bare CSS colour word.
    private static func isSafeColour(_ value: String) -> Bool {
        value.range(of: "^#[0-9A-Fa-f]{3,8}$", options: .regularExpression) != nil
            || value.range(of: "^[A-Za-z]+$", options: .regularExpression) != nil
    }
}
