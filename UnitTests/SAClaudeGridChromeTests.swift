//
//  SAClaudeGridChromeTests.swift
//  Unit Tests
//

import AppKit
import XCTest

final class SAClaudeGridChromeTests: XCTestCase {

    private func srgb(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }

    func testPaletteDerivesFromTheTheme() {
        let t = srgb(0xF0EFEC), b = srgb(0x151515), sel = srgb(0x383835), key = srgb(0x6DA7EC), caret = srgb(0xD97757)
        let p = SAClaudeGridChrome.palette(text: t, background: b, selection: sel, keyword: key, caret: caret)
        XCTAssertEqual(p.background, b)
        XCTAssertEqual(p.text, t)
        XCTAssertEqual(p.rowLine, SAClaudeEditorChrome.derivedColour(text: t, background: b, ratio: 0.12))
        XCTAssertEqual(p.headerLine, SAClaudeEditorChrome.derivedColour(text: t, background: b, ratio: 0.12))
        XCTAssertEqual(p.zebra, SAClaudeEditorChrome.derivedColour(text: t, background: b, ratio: 0.035))
        XCTAssertEqual(p.headerBackground, SAClaudeEditorChrome.derivedColour(text: t, background: b, ratio: 0.05))
        XCTAssertEqual(p.headerLabel, SAClaudeEditorChrome.derivedColour(text: t, background: b, ratio: 0.55))
        XCTAssertEqual(p.typeTag, SAClaudeEditorChrome.derivedColour(text: t, background: b, ratio: 0.36))
        XCTAssertEqual(p.hover, SAClaudeEditorChrome.derivedColour(text: t, background: b, ratio: 0.08))
        XCTAssertEqual(p.null, SAClaudeEditorChrome.derivedColour(text: t, background: b, ratio: 0.36))
        XCTAssertEqual(p.selection, sel)
        XCTAssertEqual(p.displayOverride, key)
        XCTAssertEqual(p.caret, caret)
    }

    func testZebraShadesOddRows() {
        XCTAssertFalse(SAClaudeGridChrome.isZebra(row: 0))
        XCTAssertTrue(SAClaudeGridChrome.isZebra(row: 1))
        XCTAssertFalse(SAClaudeGridChrome.isZebra(row: 2))
        XCTAssertTrue(SAClaudeGridChrome.isZebra(row: 3))
    }

    func testColumnSeparatorSkipsTheLastColumnEdge() {
        XCTAssertTrue(SAClaudeGridChrome.drawsColumnSeparator(columnMaxX: 100, boundsMaxX: 300))
        XCTAssertFalse(SAClaudeGridChrome.drawsColumnSeparator(columnMaxX: 300, boundsMaxX: 300))
        XCTAssertFalse(SAClaudeGridChrome.drawsColumnSeparator(columnMaxX: 299.5, boundsMaxX: 300))
        XCTAssertFalse(SAClaudeGridChrome.drawsColumnSeparator(columnMaxX: 301, boundsMaxX: 300))
    }

    func testColumnLinesEndAtTheLastRow() {
        XCTAssertNil(SAClaudeGridChrome.columnLineExtent(rowCount: 0, lastRowMaxY: 0))
        XCTAssertNil(SAClaudeGridChrome.columnLineExtent(rowCount: 0, lastRowMaxY: 120))
        XCTAssertEqual(SAClaudeGridChrome.columnLineExtent(rowCount: 3, lastRowMaxY: 90), 90)
    }

    func testScrollerAppearanceFollowsBackgroundLuminance() {
        XCTAssertTrue(SAClaudeGridChrome.isDark(srgb(0x151515)))
        XCTAssertTrue(SAClaudeGridChrome.isDark(srgb(0x2E3440)))
        XCTAssertFalse(SAClaudeGridChrome.isDark(srgb(0xFCFCFB)))
        XCTAssertEqual(SAClaudeGridChrome.scrollerAppearance(for: srgb(0x151515))?.name, .darkAqua)
        XCTAssertEqual(SAClaudeGridChrome.scrollerAppearance(for: srgb(0xFCFCFB))?.name, .aqua)
    }

    func testValueFontUsesTabularDigits() {
        let font = SAClaudeGridChrome.valueFont(.systemFont(ofSize: 13))
        let features = font.fontDescriptor.object(forKey: .featureSettings) as? [[NSFontDescriptor.FeatureKey: Int]] ?? []
        XCTAssertTrue(features.contains { $0[.typeIdentifier] == kNumberSpacingType && $0[.selectorIdentifier] == kMonospacedNumbersSelector })
        XCTAssertEqual(font.pointSize, 13)
    }

    func testNullFontIsItalic() {
        let font = SAClaudeGridChrome.nullFont(.systemFont(ofSize: 13))
        XCTAssertTrue(font.fontDescriptor.symbolicTraits.contains(.italic))
    }

    func testValueFontRemovesItalicAgain() {
        let italic = SAClaudeGridChrome.nullFont(.systemFont(ofSize: 13))
        XCTAssertFalse(SAClaudeGridChrome.valueFont(italic).fontDescriptor.symbolicTraits.contains(.italic))
    }

    func testHeaderPartsSplitNameAndType() {
        let title = NSMutableAttributedString(string: "id", attributes: [.font: NSFont.systemFont(ofSize: 11)])
        title.append(NSAttributedString(string: " "))
        title.append(NSAttributedString(string: "INT", attributes: [.font: NSFont.systemFont(ofSize: 8), .foregroundColor: NSColor.gray]))
        let parts = SAClaudeGridChrome.headerParts(title)
        XCTAssertEqual(parts.name, "id")
        XCTAssertEqual(parts.type, "INT")
    }

    func testHeaderPartsKeepSpacesInTheName() {
        let title = NSMutableAttributedString(string: "first name", attributes: [.font: NSFont.systemFont(ofSize: 11)])
        title.append(NSAttributedString(string: " "))
        title.append(NSAttributedString(string: "VARCHAR", attributes: [.font: NSFont.systemFont(ofSize: 8), .foregroundColor: NSColor.gray]))
        let parts = SAClaudeGridChrome.headerParts(title)
        XCTAssertEqual(parts.name, "first name")
        XCTAssertEqual(parts.type, "VARCHAR")
    }

    func testHeaderPartsWithoutTypeKeepTheWholeTitle() {
        let parts = SAClaudeGridChrome.headerParts(NSAttributedString(string: "first name", attributes: [.font: NSFont.systemFont(ofSize: 11)]))
        XCTAssertEqual(parts.name, "first name")
        XCTAssertNil(parts.type)
    }
}
