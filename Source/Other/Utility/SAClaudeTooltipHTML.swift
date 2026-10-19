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
            return "<pre style=\"font-family:'\(sanitisedFontName(name))'; font-size: \(size ?? defaultFontSize)px\">\(escaped)</pre>"
        }
        if let size {
            return "<pre class=\"sa-prose\" style=\"font-size: \(size)px\">\(escaped)</pre>"
        }
        return "<pre class=\"sa-prose\">\(escaped)</pre>"
    }

    /// The whole page: SPTooltip's skeleton with the card's padding and colours — the theme card for
    /// text, the light paper for HTML a bundle wrote for a light page. `backgroundcolor` (a `#hex` or
    /// a colour word) and `transparent` passed by a caller still win.
    static func document(body: String, kind: Kind, options: [String: Any]?, theme: SAClaudeHintCardPalette,
                         paper: SAClaudeHintCardPalette) -> String {
        let palette = kind == .text ? theme : paper
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
            + "</style>"
            + "</head>"
            + "<body>\(body)</body>"
            + "</html>"
    }

    /// A font name safe inside `font-family:'…'`: quotes, `;`, braces, angle brackets, backslashes and
    /// control characters dropped.
    static func sanitisedFontName(_ name: String) -> String {
        let forbidden = CharacterSet(charactersIn: "'\";{}<>\\").union(.controlCharacters)
        return String(String.UnicodeScalarView(name.unicodeScalars.filter { !forbidden.contains($0) }))
    }

    // MARK: Private

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
