//
//  SAClaudePaperBaseTests.swift
//  Unit Tests
//
//  The paper base under a bundle's HTML: where it goes in the page, that View Source / Save Page As get the page back
//  without it, and that every rule loses to the page's own CSS and legacy attributes.
//

import AppKit
import XCTest

final class SAClaudePaperBaseTests: XCTestCase {

    private func srgb(_ hex: UInt32) -> NSColor { SAClaudeStyle.srgb(hex) }

    private var darkTheme: SAClaudeHintCardPalette {
        let theme = SAClaudeThemeColours(background: srgb(0x1F1E1D), text: srgb(0xF0EFEC), keyword: srgb(0x6DA7EC),
                                         variable: srgb(0xA096EB), caret: srgb(0xD97757), quote: srgb(0x55BF50),
                                         backtick: srgb(0xF4ABAB), selection: srgb(0x383835))
        return .make(theme: theme, accent: srgb(0xD97757))
    }

    private var paper: SAClaudeHintCardPalette { .paper(accent: srgb(0x00C7FC)) }

    private var sheet: String { SAClaudePaperBase.stylesheet(paper: paper, theme: darkTheme) }

    private func inject(_ html: String) -> String { SAClaudePaperBase.inject(sheet, into: html) }

    // MARK: Fixtures

    private let headPage = "<!DOCTYPE html>\n<html>\n<head>\n<title>T</title>\n<style>body{background:#202020}</style>\n</head>\n<body><p>x</p></body>\n</html>"
    private let attributedHeadPage = "<HTML><HEAD lang=\"en\"><LINK rel=\"stylesheet\" href=\"a.css\"></HEAD><BODY>x</BODY></HTML>"
    private let htmlOnlyPage = "<html lang=\"en\">\n<body bgcolor=\"#000\" text=\"#fff\" link=\"#0f0\">x</body></html>"
    private let doctypeOnlyPage = "<!DOCTYPE html>\n<p>x</p>"
    private let fragment = "<b>x</b>"
    private let headerPage = "<html><body><header>h</header></body></html>"

    private var fixtures: [String] { [headPage, attributedHeadPage, htmlOnlyPage, doctypeOnlyPage, fragment, headerPage, ""] }

    // MARK: Injection

    func testInjectAfterHead() {
        let result = inject(headPage)
        XCTAssertTrue(result.hasPrefix("<!DOCTYPE html>\n<html>\n<head>" + sheet + "\n<title>"), result)
    }

    func testInjectHeadWithAttributesIsCaseInsensitive() {
        XCTAssertEqual(inject(attributedHeadPage), "<HTML><HEAD lang=\"en\">" + sheet + "<LINK rel=\"stylesheet\" href=\"a.css\"></HEAD><BODY>x</BODY></HTML>")
    }

    func testInjectAfterHtmlWithoutHead() {
        XCTAssertTrue(inject(htmlOnlyPage).hasPrefix("<html lang=\"en\">\n" + sheet + "<body bgcolor"), inject(htmlOnlyPage))
        // `<header>` is not a head.
        XCTAssertEqual(inject(headerPage), "<html>" + sheet + "<body><header>h</header></body></html>")
    }

    func testInjectAfterDoctypeOnly() {
        let result = inject(doctypeOnlyPage)
        XCTAssertTrue(result.hasPrefix("<!DOCTYPE html>"))
        XCTAssertEqual(result, "<!DOCTYPE html>\n" + sheet + "<p>x</p>")
    }

    func testInjectFragmentPrepends() {
        XCTAssertEqual(inject(fragment), sheet + "<b>x</b>")
    }

    func testInjectIsIdempotent() {
        for page in fixtures {
            XCTAssertEqual(inject(inject(page)), inject(page))
        }
    }

    /// The page's own `<style>` and `<link>` come after the base, so at equal (zero) specificity they would still win.
    func testInjectBeforePageStyles() throws {
        let result = inject(headPage)
        let base = try XCTUnwrap(result.range(of: SAClaudePaperBase.marker))
        let page = try XCTUnwrap(result.range(of: "<style>body"))
        XCTAssertLessThan(base.lowerBound, page.lowerBound)

        let linked = inject(attributedHeadPage)
        let linkBase = try XCTUnwrap(linked.range(of: SAClaudePaperBase.marker))
        let link = try XCTUnwrap(linked.range(of: "<LINK"))
        XCTAssertLessThan(linkBase.lowerBound, link.lowerBound)
    }

    // MARK: Strip

    func testStripRoundTrips() {
        for page in fixtures {
            XCTAssertEqual(SAClaudePaperBase.strip(inject(page)), page)
        }
    }

    /// What WebKit serialises back for View Source / Save Page As: the bare attribute gets an empty value.
    func testStripRemovesSerialisedBase() {
        let serialised = "<html><head>" + sheet.replacingOccurrences(of: "<style data-sa-base>", with: "<style data-sa-base=\"\">")
            + "<title>T</title></head><body>x</body></html>"
        XCTAssertEqual(SAClaudePaperBase.strip(serialised), "<html><head><title>T</title></head><body>x</body></html>")
    }

    func testStripLeavesPagesWithoutBaseAlone() {
        for page in fixtures {
            XCTAssertEqual(SAClaudePaperBase.strip(page), page)
        }
    }

    // MARK: The rules

    /// The CSS inside the base's `<style>` element.
    private func css(_ stylesheet: String) -> String {
        XCTAssertTrue(stylesheet.hasPrefix("<style \(SAClaudePaperBase.marker)>"))
        XCTAssertTrue(stylesheet.hasSuffix("</style>"))
        return String(stylesheet.dropFirst("<style \(SAClaudePaperBase.marker)>".count).dropLast("</style>".count))
    }

    /// Every rule's selector list and declarations, including the rules inside at-rules (an at-rule's prelude is never
    /// matched as a selector: it is followed by a rule, not by declarations).
    private func rules(_ css: String) -> [(selector: String, body: String)] {
        let regex = try! NSRegularExpression(pattern: "([^{}]+)\\{([^{}]*)\\}")
        return regex.matches(in: css, range: NSRange(css.startIndex..., in: css)).map { match in
            (String(css[Range(match.range(at: 1), in: css)!]).trimmingCharacters(in: .whitespaces),
             String(css[Range(match.range(at: 2), in: css)!]))
        }
    }

    /// True when `selector` is one `:where(…)` from its first to its last character.
    private func isWholeWhere(_ selector: String) -> Bool {
        guard selector.hasPrefix(":where("), selector.hasSuffix(")") else { return false }
        // The parenthesis that `:where(` opens must close at the very end.
        var depth = 0
        for (offset, character) in selector.enumerated().dropFirst(":where".count) {
            if character == "(" { depth += 1 }
            if character == ")" { depth -= 1 }
            if depth == 0 { return offset == selector.count - 1 }
        }
        return false
    }

    func testEveryBaseRuleHasZeroSpecificity() {
        let all = rules(css(sheet))
        XCTAssertEqual(all.count, 4, "\(all)")
        XCTAssertTrue(css(sheet).contains("@media print{:where(:root){"))
        for rule in all {
            for selector in rule.selector.split(separator: ",") {
                XCTAssertTrue(isWholeWhere(String(selector)), "\(selector) has specificity")
            }
        }
    }

    func testBaseLeavesLegacyAttributesAlone() throws {
        let text = css(sheet)
        XCTAssertFalse(text.contains("background"), "the paper is behind the web view, never a page background")
        let link = try XCTUnwrap(rules(text).first { $0.selector.contains("a:any-link") })
        XCTAssertTrue(link.selector.contains("body:not([link])"), link.selector)
        for rule in rules(text) {
            // The guard is the only place `body` may appear; no element a legacy page styles by attribute is named.
            let selector = rule.selector.replacingOccurrences(of: "body:not([link])", with: "")
            let names = selector.components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty }
            for legacy in ["font", "table", "td", "th", "tr", "body"] {
                XCTAssertFalse(names.contains(legacy), "\(rule.selector) names \(legacy)")
            }
        }
    }

    func testBaseCarriesPaperAndThemeVariables() throws {
        let all = rules(css(sheet))
        let html = try XCTUnwrap(all.first { $0.selector == ":where(html)" })
        XCTAssertTrue(html.body.contains("color:\(SAClaudeHintCardCSS.colour(paper.text))"), html.body)
        XCTAssertTrue(html.body.contains("font:13px/1.5 -apple-system"), html.body)
        XCTAssertTrue(html.body.contains("color-scheme:light"), html.body)

        let roots = all.filter { $0.selector == ":where(:root)" }
        XCTAssertEqual(roots.count, 2)
        XCTAssertTrue(roots[0].body.contains("--sa-surface:\(SAClaudeHintCardCSS.colour(darkTheme.surface))"), roots[0].body)
        XCTAssertEqual(roots[0].body, SAClaudeHintCardCSS.declarations(darkTheme))
        XCTAssertTrue(roots[1].body.contains("--sa-surface:#FAF9F5"), roots[1].body)
        XCTAssertEqual(roots[1].body, SAClaudeHintCardCSS.declarations(paper))

        let link = try XCTUnwrap(all.first { $0.selector.contains("a:any-link") })
        XCTAssertEqual(link.body, "color:\(SAClaudeHintCardCSS.colour(paper.accent))")
    }
}
