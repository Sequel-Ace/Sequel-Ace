//
//  SAClaudeRareTemplatesTests.swift
//  Unit Tests
//
//  The bundled HTML pages of the rare windows (the SQL help template, …) read the Claude palette through CSS variables.
//  These tests read the files from the repository and check their CSS rules.
//

import XCTest

final class SAClaudeRareTemplatesTests: XCTestCase {

    // MARK: - Helpers

    /// The repository root: this file lives in `UnitTests/`.
    static let repositoryRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    /// The text of a file in the repository, by its path from the root.
    func file(_ relativePath: String) throws -> String {
        try String(contentsOf: Self.repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    /// The contents of every `<style>` element in `html`, in document order.
    func styleBlocks(in html: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: "<style[^>]*>(.*?)</style>", options: [.dotMatchesLineSeparators, .caseInsensitive])
        let range = NSRange(html.startIndex..., in: html)
        return regex.matches(in: html, range: range).compactMap { Range($0.range(at: 1), in: html).map { String(html[$0]) } }
    }

    /// The declarations of the first CSS rule whose selector list names `selector` exactly (`a, .internallink` names `a`),
    /// trimmed; nil when there is none. `text` is an HTML page (only its `<style>` elements are read) or plain CSS. Rules
    /// inside an at-rule (`@media print { … }`) count too, in document order; comments are ignored.
    func rule(_ selector: String, in text: String) -> String? {
        let blocks = styleBlocks(in: text)
        var css = blocks.isEmpty ? text : blocks.joined(separator: "\n")
        css = css.replacingOccurrences(of: "/\\*.*?\\*/", with: "", options: .regularExpression)
        let regex = try! NSRegularExpression(pattern: "([^{}]+)\\{([^{}]*)\\}")
        for match in regex.matches(in: css, range: NSRange(css.startIndex..., in: css)) {
            guard let selectors = Range(match.range(at: 1), in: css), let body = Range(match.range(at: 2), in: css) else { continue }
            let names = css[selectors].split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            if names.contains(selector) { return css[body].trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        return nil
    }

    func assertRule(_ selector: String, in text: String, contains expected: [String], file: StaticString = #filePath, line: UInt = #line) {
        guard let body = rule(selector, in: text) else {
            XCTFail("no rule for \(selector)", file: file, line: line)
            return
        }
        for value in expected {
            XCTAssertTrue(body.contains(value), "\(selector) { \(body) } lacks \(value)", file: file, line: line)
        }
    }

    // MARK: - SQL help template

    private func helpTemplate() throws -> String { try file("Resources/Templates/SPMySQLHelpTemplate.html") }

    func testRuleHelperReadsSelectorListsAndAtRules() {
        let css = "<style>/* c */ a, .x { color: red; }\n@media print { b { color: blue } }</style>"
        XCTAssertEqual(rule(".x", in: css), "color: red;")
        XCTAssertEqual(rule("a", in: css), "color: red;")
        XCTAssertEqual(rule("b", in: css), "color: blue")
        XCTAssertNil(rule("c", in: css))
        XCTAssertEqual(rule("p", in: "p{margin:0}"), "margin:0")
    }

    func testHelpTemplateHasPaletteSlot() throws {
        let html = try helpTemplate()
        XCTAssertTrue(styleBlocks(in: html).contains { $0.contains("{{palette}}") }, "{{palette}} is not inside a <style>")
        for variable in ["{{title}}", "{{body}}", "{{bodyClass}}"] {
            XCTAssertTrue(html.contains(variable), "lost \(variable)")
        }
    }

    func testHelpTemplateUsesPaletteVariables() throws {
        let html = try helpTemplate()
        assertRule("body", in: html, contains: ["var(--sa-surface)", "var(--sa-text)", "13px", "-apple-system"])
        assertRule("a", in: html, contains: ["var(--sa-accent)"])
        assertRule(".internallink", in: html, contains: ["var(--sa-accent)"])
        assertRule(".error", in: html, contains: ["var(--sa-destructive)"])
        assertRule(".nothing", in: html, contains: ["var(--sa-muted)"])
        assertRule("::selection", in: html, contains: ["var(--sa-selection)"])
    }

    /// MySQL's syntax text keeps its alignment (monospaced) but wraps, with no box behind it.
    func testHelpDescriptionStaysMonospacedAndWraps() throws {
        let html = try helpTemplate()
        assertRule(".description", in: html, contains: ["SF Mono", "12px", "pre-wrap"])
        XCTAssertFalse(rule(".description", in: html)?.contains("background") ?? true)
    }

    /// Examples sit on the rounded code surface and scroll sideways instead of widening the page.
    func testHelpExampleIsCodeSurface() throws {
        assertRule(".example", in: try helpTemplate(), contains: ["var(--sa-code)", "border-radius: 8px", "overflow-x: auto", "white-space: pre;"])
    }

    func testHelpTemplateDropsLegacyFonts() throws {
        let html = try helpTemplate()
        for legacy in ["Helvetica", "Monaco", "Courier", "9pt", "rgb(42, 38, 38)"] {
            XCTAssertFalse(html.contains(legacy), "still has \(legacy)")
        }
    }

    /// The live theme hook takes the palette's variables and sets each one.
    func testHelpThemeHookAcceptsPalette() throws {
        let html = try helpTemplate()
        XCTAssertTrue(html.contains("window.onThemeChange = function(theme, palette)"))
        XCTAssertTrue(html.contains("style.setProperty(key, palette[key])"))
    }
}
