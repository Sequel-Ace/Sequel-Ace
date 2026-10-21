//
//  SAClaudeTooltipHTMLTests.swift
//  Unit Tests
//

import AppKit
import XCTest

final class SAClaudeTooltipHTMLTests: XCTestCase {

    private func srgb(_ hex: UInt32) -> NSColor { SAClaudeStyle.srgb(hex) }

    private var darkTheme: SAClaudeHintCardPalette {
        let theme = SAClaudeThemeColours(background: srgb(0x1F1E1D), text: srgb(0xF0EFEC), keyword: srgb(0x6DA7EC),
                                         variable: srgb(0xA096EB), caret: srgb(0xD97757), quote: srgb(0x55BF50),
                                         backtick: srgb(0xF4ABAB), selection: srgb(0x383835))
        return SAClaudeHintCardPalette.make(theme: theme, accent: srgb(0xD97757))
    }

    private var paper: SAClaudeHintCardPalette { SAClaudeHintCardPalette.paper(accent: srgb(0xD97757)) }

    /// The declarations of the document's `body { … }` rule.
    private func bodyRule(_ html: String) -> String {
        guard let start = html.range(of: "body {"),
              let end = html.range(of: "}", range: start.upperBound..<html.endIndex) else {
            XCTFail("no body rule in \(html)")
            return ""
        }
        return String(html[start.upperBound..<end.lowerBound])
    }

    // MARK: Text body

    func testTextBodyEscapesMarkup() {
        let body = SAClaudeTooltipHTML.textBody("<b>&</b>", options: nil)
        XCTAssertTrue(body.contains("&lt;b&gt;&amp;&lt;/b&gt;"), body)
        XCTAssertFalse(body.contains("<b>"), body)
    }

    func testTextBodyKeepsCallerFont() {
        let body = SAClaudeTooltipHTML.textBody("x", options: ["fontname": "Menlo-Regular", "fontsize": NSNumber(value: 11)])
        XCTAssertTrue(body.contains("font-family:'Menlo-Regular', ui-monospace, monospace; font-size: 11px"), body)
        XCTAssertFalse(body.contains("sa-prose"), body)
    }

    /// The grid's default results font is the system font (".AppleSystemUIFont"): WebKit can't load it by name and drew
    /// the value in its serif default (walkthrough fix 1).
    func testSystemUIFontNamesBecomeAppleSystem() {
        let sans = "-apple-system, system-ui, sans-serif"
        for name in [".AppleSystemUIFont", ".AppleSystemUIFontBold", ".SFNS-Regular", "SFNSText-Regular", "-apple-system", "system-ui",
                     NSFont.systemFont(ofSize: 13).fontName, NSFont.boldSystemFont(ofSize: 13).fontName] {
            XCTAssertEqual(SAClaudeTooltipHTML.fontFamily(name), sans, name)
        }
        let body = SAClaudeTooltipHTML.textBody("gautam@beatoapp.com", options: ["fontname": ".AppleSystemUIFont", "fontsize": NSNumber(value: 14)])
        XCTAssertTrue(body.contains("font-family:-apple-system, system-ui, sans-serif; font-size: 14px"), body)
        XCTAssertFalse(body.contains("AppleSystemUIFont"), body)
    }

    func testMonospacedSystemFontBecomesUIMonospace() {
        for name in [".AppleSystemUIFontMonospaced-Regular", ".AppleSystemUIFontMonospaced-Bold", ".SFNSMono-Regular",
                     NSFont.monospacedSystemFont(ofSize: 11, weight: .regular).fontName] {
            XCTAssertEqual(SAClaudeTooltipHTML.fontFamily(name), "ui-monospace, monospace", name)
        }
    }

    func testNamedFontStaysFirstWithAGenericFallback() {
        XCTAssertEqual(SAClaudeTooltipHTML.fontFamily("Menlo-Regular"), "'Menlo-Regular', ui-monospace, monospace")
        XCTAssertEqual(SAClaudeTooltipHTML.fontFamily("SFMono-Regular"), "'SFMono-Regular', ui-monospace, monospace")
        XCTAssertEqual(SAClaudeTooltipHTML.fontFamily("Helvetica"), "'Helvetica', -apple-system, system-ui, sans-serif")
        XCTAssertEqual(SAClaudeTooltipHTML.fontFamily("No Such Font"), "'No Such Font', -apple-system, system-ui, sans-serif")
    }

    func testEveryFamilyListEndsOnAGenericFamilyNeverSerif() {
        for name in ["Menlo-Regular", "Helvetica", "Times-Roman", ".AppleSystemUIFont", ".AppleSystemUIFontMonospaced-Regular", "",
                     "  ", "No Such Font", "Evil'; } body{x"] {
            let family = SAClaudeTooltipHTML.fontFamily(name)
            XCTAssertTrue(family.hasSuffix(", sans-serif") || family.hasSuffix(", monospace"), "\(name) → \(family)")
            let generics = family.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            XCTAssertFalse(generics.contains("serif"), "\(name) → \(family)")
        }
    }

    func testTextBodyFontSizeAsStringAndFloor() {
        let body = SAClaudeTooltipHTML.textBody("x", options: ["fontname": "Menlo-Regular", "fontsize": "3"])
        XCTAssertTrue(body.contains("font-size: 5px"), body)
        let defaultSize = SAClaudeTooltipHTML.textBody("x", options: ["fontname": "Menlo-Regular"])
        XCTAssertTrue(defaultSize.contains("font-size: 10px"), defaultSize)
    }

    func testTextBodyWithoutOptionsIsProse() {
        let body = SAClaudeTooltipHTML.textBody("Field is not editable.", options: nil)
        XCTAssertTrue(body.contains("class=\"sa-prose\""), body)
        XCTAssertFalse(body.contains("Lucida"), body)
        XCTAssertFalse(body.contains("style="), body)
        let sized = SAClaudeTooltipHTML.textBody("x", options: ["fontsize": "14"])
        XCTAssertTrue(sized.contains("class=\"sa-prose\" style=\"font-size: 14px\""), sized)
    }

    func testFontNameIsSanitised() {
        let name = SAClaudeTooltipHTML.sanitisedFontName("Evil'; } body{x")
        for forbidden in ["'", "\"", ";", "{", "}", "<", ">"] {
            XCTAssertFalse(name.contains(forbidden), "\(forbidden) in \(name)")
        }
        XCTAssertEqual(SAClaudeTooltipHTML.sanitisedFontName("Menlo-Regular"), "Menlo-Regular")
        XCTAssertEqual(SAClaudeTooltipHTML.sanitisedFontName("SF Mono"), "SF Mono")
        let body = SAClaudeTooltipHTML.textBody("x", options: ["fontname": "Evil'; } body{x"])
        XCTAssertFalse(body.contains("body{"), body)
        XCTAssertEqual(SAClaudeTooltipHTML.sanitisedFontName("A&quot;B&#39;C"), "AquotB#39C")
    }

    /// Whatever the font name, the `<pre>`'s style attribute holds exactly the two declarations it writes.
    func testHostileFontNameStaysInsideItsDeclaration() {
        for name in ["Evil'; } body{x", "A&quot;; color:red", "x\"><script>alert(1)</script>", "a\\'b", "Tab\tName\n"] {
            let body = SAClaudeTooltipHTML.textBody("v", options: ["fontname": name, "fontsize": NSNumber(value: 12)])
            guard let start = body.range(of: "style=\""), let end = body.range(of: "\">", range: start.upperBound..<body.endIndex) else {
                XCTFail("no style attribute in \(body)")
                continue
            }
            let style = body[start.upperBound..<end.lowerBound]
            for forbidden in ["\"", "{", "}", "<", ">", "&", "\\", "\t", "\n"] {
                XCTAssertFalse(style.contains(forbidden), "\(forbidden) in \(style)")
            }
            XCTAssertEqual(style.filter { $0 == ";" }.count, 1, String(style))
            XCTAssertEqual(style.filter { $0 == "'" }.count, 2, String(style))
            XCTAssertTrue(style.hasSuffix("; font-size: 12px"), String(style))
            XCTAssertTrue(body.hasSuffix(">v</pre>"), body)
        }
    }

    // MARK: Document

    func testTextDocumentUsesThemeCard() {
        let dark = darkTheme
        let html = SAClaudeTooltipHTML.document(body: "<pre>x</pre>", kind: .text, options: nil, theme: dark, paper: paper)
        let rule = bodyRule(html)
        XCTAssertTrue(rule.contains("background: \(SAClaudeHintCardCSS.colour(dark.surface))"), rule)
        XCTAssertTrue(rule.contains("color: \(SAClaudeHintCardCSS.colour(dark.text))"), rule)
        XCTAssertTrue(rule.contains("padding: 8px 10px"), rule)
        XCTAssertTrue(rule.contains("max-width: 800px"), rule)
        XCTAssertTrue(rule.contains("display: table-cell"), rule)
        XCTAssertTrue(rule.contains("overflow: hidden"), rule)
        XCTAssertTrue(rule.contains("margin: 0"), rule)
        XCTAssertFalse(html.contains("#F0F0F0"), html)
        XCTAssertTrue(html.contains("pre { white-space: pre-wrap; margin: 0; }"), html)
        XCTAssertTrue(html.contains(".sa-prose"), html)
        XCTAssertTrue(html.contains("-apple-system"), html)
        XCTAssertTrue(html.contains("<body><pre>x</pre></body>"), html)
    }

    /// Bundle HTML that styles itself keeps the light paper, exactly as before (walkthrough 16).
    func testStyledHTMLDocumentSitsOnPaper() {
        for body in ["<p><font color=blue>bundle</font></p>", "<style>p{color:#333}</style><p>bundle</p>",
                     "<p style=\"color:#333\">bundle</p>", "<table bgcolor=#ECECEC><tr><td>x</td></tr></table>"] {
            let html = SAClaudeTooltipHTML.document(body: body, kind: .html, options: nil, theme: darkTheme, paper: paper)
            let rule = bodyRule(html)
            XCTAssertTrue(rule.contains("background: #FAF9F5"), rule)
            XCTAssertTrue(rule.contains("color: #0B0B0B"), rule)
            XCTAssertFalse(html.contains("a:any-link"), html)
        }
    }

    /// Plain bundle HTML (no colours or fonts of its own) follows the theme like a text tooltip, links in the theme's
    /// readable accent (walkthrough 16).
    func testPlainHTMLDocumentFollowsTheTheme() {
        let dark = darkTheme
        let html = SAClaudeTooltipHTML.document(body: "<p>bundle <a href=\"x\">link</a></p>", kind: .html, options: nil,
                                                theme: dark, paper: paper)
        let rule = bodyRule(html)
        XCTAssertTrue(rule.contains("background: \(SAClaudeHintCardCSS.colour(dark.surface))"), rule)
        XCTAssertTrue(rule.contains("color: \(SAClaudeHintCardCSS.colour(dark.text))"), rule)
        XCTAssertFalse(html.contains("#FAF9F5"), html)
        XCTAssertTrue(html.contains("a:any-link { color: \(SAClaudeHintCardCSS.colour(dark.accent)); }"), html)
        XCTAssertGreaterThanOrEqual(SAClaudeHintCardPalette.contrast(dark.accent, dark.surface), 4.5)
        // A caller's background still wins.
        let explicit = SAClaudeTooltipHTML.document(body: "<p>x</p>", kind: .html, options: ["backgroundcolor": "#EEEEEE"],
                                                    theme: dark, paper: paper)
        XCTAssertTrue(bodyRule(explicit).contains("background: #EEEEEE"), explicit)
        // Text tooltips are unchanged: no link rule.
        let text = SAClaudeTooltipHTML.document(body: "<pre>x</pre>", kind: .text, options: nil, theme: dark, paper: paper)
        XCTAssertFalse(text.contains("a:any-link"), text)
    }

    func testExplicitBackgroundOptionWins() {
        let explicit = SAClaudeTooltipHTML.document(body: "x", kind: .text, options: ["backgroundcolor": "#EEEEEE"],
                                                    theme: darkTheme, paper: paper)
        XCTAssertTrue(bodyRule(explicit).contains("background: #EEEEEE"), explicit)
        let transparent = SAClaudeTooltipHTML.document(body: "x", kind: .html,
                                                       options: ["transparent": "1", "backgroundcolor": "#EEEEEE"],
                                                       theme: darkTheme, paper: paper)
        XCTAssertTrue(bodyRule(transparent).contains("background: transparent"), transparent)
        let word = SAClaudeTooltipHTML.document(body: "x", kind: .text, options: ["backgroundcolor": "white"],
                                                theme: darkTheme, paper: paper)
        XCTAssertTrue(bodyRule(word).contains("background: white"), word)
    }

    func testInvalidBackgroundOptionIgnored() {
        let dark = darkTheme
        for bad in ["red; } body {", "#12", "#123456789", "#GGGGGG", "url(x)"] {
            let html = SAClaudeTooltipHTML.document(body: "x", kind: .text, options: ["backgroundcolor": bad],
                                                    theme: dark, paper: paper)
            XCTAssertTrue(bodyRule(html).contains("background: \(SAClaudeHintCardCSS.colour(dark.surface))"), bad)
            XCTAssertFalse(html.contains(bad), bad)
        }
    }
}
