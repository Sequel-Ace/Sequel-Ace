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
        XCTAssertTrue(body.contains("font-family:'Menlo-Regular'; font-size: 11px"), body)
        XCTAssertFalse(body.contains("sa-prose"), body)
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

    func testHTMLDocumentSitsOnPaper() {
        let html = SAClaudeTooltipHTML.document(body: "<p>bundle</p>", kind: .html, options: nil, theme: darkTheme, paper: paper)
        let rule = bodyRule(html)
        XCTAssertTrue(rule.contains("background: #FAF9F5"), rule)
        XCTAssertTrue(rule.contains("color: #0B0B0B"), rule)
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
