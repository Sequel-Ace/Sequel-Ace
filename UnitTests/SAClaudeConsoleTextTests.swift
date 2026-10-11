//
//  SAClaudeConsoleTextTests.swift
//  Unit Tests
//

import AppKit
import XCTest

final class SAClaudeConsoleTextTests: XCTestCase {

    private let style = SAClaudeConsoleTextStyle(font: .systemFont(ofSize: 13), text: .white, muted: .gray, error: .orange,
                                                 keyword: .blue, string: .green, backtick: .red, number: .purple, comment: .brown)

    private func colour(_ s: NSAttributedString, at index: Int) -> NSColor? {
        s.attribute(.foregroundColor, at: index, effectiveRange: nil) as? NSColor
    }

    func testColumnIdentifiers() {
        XCTAssertEqual(SAClaudeConsoleColumn(identifier: "messageDate"), .time)
        XCTAssertEqual(SAClaudeConsoleColumn(identifier: "messageConnection"), .connection)
        XCTAssertEqual(SAClaudeConsoleColumn(identifier: "messageDatabase"), .database)
        XCTAssertEqual(SAClaudeConsoleColumn(identifier: "message"), .query)
    }

    func testQueryColumnIsColouredAndMetaIsMuted() {
        let q = SAClaudeConsoleText.attributed("SELECT 'a', 42 FROM `t`", column: .query, isError: false, style: style)
        XCTAssertEqual(q.string, "SELECT 'a', 42 FROM `t`")
        XCTAssertEqual(colour(q, at: 0), .blue)                          // SELECT
        XCTAssertEqual(colour(q, at: 7), .green)                         // 'a'
        XCTAssertEqual(colour(q, at: 12), .purple)                       // 42
        XCTAssertEqual(colour(q, at: 20), .red)                          // `t`
        XCTAssertEqual(colour(q, at: 6), .white)                         // plain text
        let meta = SAClaudeConsoleText.attributed("beato", column: .database, isError: false, style: style)
        XCTAssertEqual(colour(meta, at: 0), .gray)
    }

    func testErrorRowsAreErrorColouredInEveryColumn() {
        for column in [SAClaudeConsoleColumn.time, .connection, .database, .query] {
            let s = SAClaudeConsoleText.attributed("SELEC 2", column: column, isError: true, style: style)
            XCTAssertEqual(colour(s, at: 0), .orange)
            XCTAssertEqual(colour(s, at: 6), .orange)
        }
    }

    func testFontHasTabularDigits() {
        var tabular = style
        tabular.font = SAClaudeGridChrome.valueFont(.systemFont(ofSize: 13))
        let s = SAClaudeConsoleText.attributed("20:14:02", column: .time, isError: false, style: tabular)
        let font = s.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        let features = font?.fontDescriptor.object(forKey: .featureSettings) as? [[NSFontDescriptor.FeatureKey: Int]] ?? []
        XCTAssertTrue(features.contains { $0[.typeIdentifier] == kNumberSpacingType && $0[.selectorIdentifier] == kMonospacedNumbersSelector })
    }

    func testTruncatedQueryWithOpenQuoteStillColours() {
        let s = SAClaudeConsoleText.attributed("SELECT 'unterminated /* cut", column: .query, isError: false, style: style)
        XCTAssertEqual(s.string, "SELECT 'unterminated /* cut")
        XCTAssertEqual(colour(s, at: 0), .blue)
        XCTAssertEqual(colour(s, at: 10), .green)
    }

    private func themeDefaults(text: NSColor, background: NSColor, keyword: NSColor) -> (UserDefaults, String) {
        let suiteName = "SAClaudeConsoleTextTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(SAArchiving.archivedData(forColor: text), forKey: SAEditorThemeLoader.textColourKey)
        defaults.set(SAArchiving.archivedData(forColor: background), forKey: SAEditorThemeLoader.backgroundColourKey)
        defaults.set(SAArchiving.archivedData(forColor: keyword), forKey: SAEditorThemeLoader.keywordColourKey)
        return (defaults, suiteName)
    }

    func testStyleFromDefaultsDerivesFromTheStoredTheme() {
        let text = NSColor(srgbRed: 0.9, green: 0.88, blue: 0.85, alpha: 1)
        let background = NSColor(srgbRed: 0.12, green: 0.11, blue: 0.1, alpha: 1)
        let keyword = NSColor(srgbRed: 0.8, green: 0.5, blue: 0.3, alpha: 1)
        let (defaults, suiteName) = themeDefaults(text: text, background: background, keyword: keyword)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let storedText = SAArchiving.color(from: defaults.data(forKey: SAEditorThemeLoader.textColourKey))!
        let storedBackground = SAArchiving.color(from: defaults.data(forKey: SAEditorThemeLoader.backgroundColourKey))!
        let storedKeyword = SAArchiving.color(from: defaults.data(forKey: SAEditorThemeLoader.keywordColourKey))!
        let clay = NSColor(srgbRed: 0xD9 / 255.0, green: 0x77 / 255.0, blue: 0x57 / 255.0, alpha: 1)

        let style = SAClaudeConsoleTextStyle.from(defaults: defaults, font: .systemFont(ofSize: 13))

        XCTAssertEqual(style.keyword, storedKeyword)
        XCTAssertEqual(style.muted, SAClaudeEditorChrome.derivedColour(text: storedText, background: storedBackground, ratio: 0.55))
        XCTAssertEqual(style.error, SAClaudeEditorChrome.derivedColour(text: storedText, background: clay, ratio: 0.35))
        let features = style.font.fontDescriptor.object(forKey: .featureSettings) as? [[NSFontDescriptor.FeatureKey: Int]] ?? []
        XCTAssertTrue(features.contains { $0[.typeIdentifier] == kNumberSpacingType && $0[.selectorIdentifier] == kMonospacedNumbersSelector })
    }

    func testStylesCompareEqualOnlyWhenTheirInputsMatch() {
        let text = NSColor(srgbRed: 0.9, green: 0.88, blue: 0.85, alpha: 1)
        let background = NSColor(srgbRed: 0.12, green: 0.11, blue: 0.1, alpha: 1)
        let (a, suiteA) = themeDefaults(text: text, background: background, keyword: NSColor(srgbRed: 0.8, green: 0.5, blue: 0.3, alpha: 1))
        let (b, suiteB) = themeDefaults(text: text, background: background, keyword: NSColor(srgbRed: 0.3, green: 0.5, blue: 0.8, alpha: 1))
        defer { a.removePersistentDomain(forName: suiteA); b.removePersistentDomain(forName: suiteB) }
        let font = NSFont.systemFont(ofSize: 13)
        XCTAssertEqual(SAClaudeConsoleTextStyle.from(defaults: a, font: font), SAClaudeConsoleTextStyle.from(defaults: a, font: font))
        // A syntax-colour-only theme change must count as a different style (the console redraws on it).
        XCTAssertNotEqual(SAClaudeConsoleTextStyle.from(defaults: a, font: font), SAClaudeConsoleTextStyle.from(defaults: b, font: font))
        XCTAssertNotEqual(SAClaudeConsoleTextStyle.from(defaults: a, font: font), SAClaudeConsoleTextStyle.from(defaults: a, font: .systemFont(ofSize: 15)))
    }
}
