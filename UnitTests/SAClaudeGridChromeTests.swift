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
        XCTAssertEqual(p.rowLine, SAClaudeEditorChrome.derivedColour(text: t, background: b, ratio: 0.04))
        XCTAssertEqual(p.headerLine, SAClaudeEditorChrome.derivedColour(text: t, background: b, ratio: 0.08))
        XCTAssertEqual(p.headerLabel, SAClaudeEditorChrome.derivedColour(text: t, background: b, ratio: 0.55))
        XCTAssertEqual(p.typeTag, SAClaudeEditorChrome.derivedColour(text: t, background: b, ratio: 0.36))
        XCTAssertEqual(p.hover, SAClaudeEditorChrome.derivedColour(text: t, background: b, ratio: 0.08))
        XCTAssertEqual(p.null, SAClaudeEditorChrome.derivedColour(text: t, background: b, ratio: 0.36))
        XCTAssertEqual(p.selection, sel)
        XCTAssertEqual(p.displayOverride, key)
        XCTAssertEqual(p.caret, caret)
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
