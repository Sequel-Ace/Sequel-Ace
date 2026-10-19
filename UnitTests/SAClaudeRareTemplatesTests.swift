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

    // MARK: - Socket help page

    private func socketPage() throws -> String { try file("Resources/local-connection.html") }

    func testSocketPageHasNoGoogleFontOrJekyllChrome() throws {
        let html = try socketPage()
        for legacy in ["fonts.googleapis", "<header", "<footer", "GitHub Pages", "#d5000d", "Chivo"] {
            XCTAssertFalse(html.contains(legacy), "still has \(legacy)")
        }
    }

    /// In the app the page reads the palette the paper base injects with it; opened elsewhere it falls back to light, or
    /// dark with the system; printed it is always light.
    func testSocketPageReadsPaletteWithFallback() throws {
        let html = try socketPage()
        for expected in ["var(--sa-surface,", "var(--sa-text,", "var(--sa-muted,", "var(--sa-hairline,", "var(--sa-accent,",
                         "var(--sa-code,", "prefers-color-scheme: dark", "@media print", "-apple-system"] {
            XCTAssertTrue(html.contains(expected), "lacks \(expected)")
        }
        assertRule("body", in: html, contains: ["var(--sa-surface,", "var(--sa-text,", "13px", "-apple-system"])
        assertRule("a", in: html, contains: ["var(--sa-accent,"])
        assertRule("pre", in: html, contains: ["var(--sa-code,", "border-radius: 8px", "SF Mono"])
        // The lead is a full sentence: half text, half muted keeps it ≥ 4.5:1 (the muted colour alone is not on paper).
        assertRule(".lead", in: html, contains: ["color-mix(in srgb, var(--sa-text, var(--fallback-text)) 50%, var(--sa-muted, var(--fallback-muted)))"])
    }

    func testSocketPageKeepsItsInstructions() throws {
        let html = try socketPage()
        for text in ["Connect to a Local MySQL Server",
                     "This document describes how to connect to a server running on the same computer as Sequel Ace.",
                     "Making sure your MySQL server is running", "Connecting via a socket connection",
                     "Connecting via a standard connection",
                     "[mysqld]\nsocket=/Users/YourUserName/Library/Containers/com.sequel-ace.sequel-ace/Data/mysql.sock",
                     "~/Library/Containers/com.sequel-ace.sequel-ace/Data", "my.cnf", "127.0.0.1", "3306", "port 8889",
                     "href=\"https://sequel-ace.com/get-started/mamp-xampp.html\"",
                     "href=\"https://dev.mysql.com/doc/refman/en/connecting.html\""] {
            XCTAssertTrue(html.contains(text), "lost \(text)")
        }
    }

    // MARK: - Print templates

    private static let dataPrintTemplate = "Resources/Templates/SPPrintTemplate.html"
    private static let tableInfoPrintTemplate = "Resources/Templates/SPTableInfoPrintTemplate.html"

    /// The template engine's `{{…}}` and `{% … %}` tokens in `text`.
    private func templateTokens(in text: String) -> Set<String> {
        let regex = try! NSRegularExpression(pattern: "\\{\\{[^}]*\\}\\}|\\{%[^%]*%\\}")
        return Set(regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { String(text[Range($0.range, in: text)!]) })
    }

    /// `rule(_:in:)` for a template: its `{{name}}` tokens read as `__name__`, so their braces don't end a rule.
    private func templateRule(_ selector: String, in text: String) -> String? {
        let regex = try! NSRegularExpression(pattern: "\\{\\{\\s*([^}]*?)\\s*\\}\\}")
        let plain = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "__$1__")
        return rule(selector, in: plain)
    }

    /// Paper is light: the templates have no dark variant and use the system font, not the legacy fills.
    func testPrintTemplatesAreAlwaysLight() throws {
        for path in [Self.dataPrintTemplate, Self.tableInfoPrintTemplate] {
            let html = try file(path)
            XCTAssertFalse(html.contains("prefers-color-scheme"), "\(path) has a dark variant")
            XCTAssertTrue(html.contains("-apple-system"), "\(path) lacks the system font")
            for legacy in ["#EDF3FE", "#E5E5E5", "Courier", "Lucida"] {
                XCTAssertFalse(html.contains(legacy), "\(path) still has \(legacy)")
            }
            XCTAssertTrue(templateRule("html", in: html)?.contains("color-scheme: light") ?? false, "\(path) is not pinned light")
        }
    }

    /// The vertical-gridlines preference (`{{gridlines}}`: `1px solid #CCCCCC` or `none`) still decides the cell sides,
    /// drawn in the hairline colour; `{{font}}` only ever carried "Lucida Grande", so the cells use the system font.
    func testDataPrintTemplateHonoursGridlines() throws {
        let html = try file(Self.dataPrintTemplate)
        let td = try XCTUnwrap(templateRule("td", in: html))
        for side in ["border-left: __gridlines__;", "border-right: __gridlines__;"] {
            XCTAssertTrue(td.contains(side), "td { \(td) } lacks \(side)")
        }
        let gridlines = try XCTUnwrap(td.range(of: "border-right: __gridlines__;"))
        for side in ["border-left-color: #E7E6E1;", "border-right-color: #E7E6E1;"] {
            let colour = try XCTUnwrap(td.range(of: side), "td { \(td) } lacks \(side)")
            XCTAssertLessThan(gridlines.lowerBound, colour.lowerBound, "\(side) must follow {{gridlines}} to replace its #CCCCCC")
        }
        XCTAssertFalse(html.contains("{{font}}"))
        XCTAssertTrue(templateRule("code", in: html)?.contains("ui-monospace") ?? false, "query code is not in the system monospace")
        // Hairline rows, a muted header row with no fill, no box around the table.
        XCTAssertTrue(td.contains("border-bottom: 1px solid #E7E6E1"), td)
        let th = try XCTUnwrap(templateRule("th", in: html))
        XCTAssertTrue(th.contains("color: #7B7974"), th)
        XCTAssertFalse(th.contains("background"), th)
        XCTAssertTrue(templateRule("table", in: html)?.contains("border: none") ?? false)
    }

    /// The table information page keeps the user's editor font, which the create syntax is shown in.
    func testTableInfoPrintTemplateKeepsEditorFontForSyntax() throws {
        let html = try file(Self.tableInfoPrintTemplate)
        XCTAssertEqual(html.components(separatedBy: "{{font}}").count - 1, 1)
        XCTAssertTrue(templateRule("pre", in: html)?.contains("font-family: __font__") ?? false)
    }

    /// The pages are still filled by SPDatabaseDocument.m with the same variables and tags.
    func testPrintTemplatesKeepTheirTokens() throws {
        let shared: Set<String> = [
            "{{c.table}}", "{{c.username}}", "{% if c.username %}", "{% /if %}", "{{c.hostname}}", "{% if c.port %}",
            "{{c.port}}", "{{c.database}}", "{% now | date_format: \"dd MMM yyyy 'at' HH:mm:ss\" %}", "{{c.version}}",
            "{{heading}}",
        ]
        // `{{font}}` is gone from the data template on purpose (see testDataPrintTemplateHonoursGridlines).
        let data = shared.union([
            "{% if c.query %}", "{{c.query}}", "{% for column in columns %}", "{{ column }}", "{% /for %}",
            "{% for row in rows %}", "{% cycle 'class=\"odd\" ' 'class=\"even\" ' %}", "{% for cell in row %}", "{{ cell }}",
            "{% if hasIndexes && indexes %}", "{% for indexColumn in indexColumns %}", "{{ indexColumn }}",
            "{% for index in indexes %}", "{% for cell in index %}", "{{gridlines}}",
        ])
        let tableInfo = shared.union([
            "{{font}}", "{{i.type}}", "{{i.encoding}}", "{{i.collation}}", "{{i.createdAt}}", "{{i.updatedAt}}",
            "{{i.rowNumber}}", "{{i.rowFormat}}", "{{i.rowAvgLength}}", "{{i.rowAutoIncrement}}", "{{i.dataSize}}",
            "{{i.maxDataSize}}", "{{i.indexSize}}", "{{i.sizeFree}}", "{% if i.comments.length > 0 %}", "{{i.comments}}",
            "{% if i.createSyntax > 0 %}", "{{i.createSyntax}}",
        ])
        XCTAssertEqual(templateTokens(in: try file(Self.dataPrintTemplate)), data)
        XCTAssertEqual(templateTokens(in: try file(Self.tableInfoPrintTemplate)), tableInfo)
    }
}
