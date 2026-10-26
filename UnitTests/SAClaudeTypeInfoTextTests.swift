//
//  SAClaudeTypeInfoTextTests.swift
//  Unit Tests
//

import AppKit
import XCTest

final class SAClaudeTypeInfoTextTests: XCTestCase {

    private func srgb(_ hex: UInt32) -> NSColor { SAClaudeStyle.srgb(hex) }

    private var palette: SAClaudeHintCardPalette {
        let theme = SAClaudeThemeColours(background: srgb(0x1F1E1D), text: srgb(0xF0EFEC), keyword: srgb(0x6DA7EC),
                                         variable: srgb(0xA096EB), caret: srgb(0xD97757), quote: srgb(0x55BF50),
                                         backtick: srgb(0xF4ABAB), selection: srgb(0x383835))
        return SAClaudeHintCardPalette.make(theme: theme, accent: srgb(0xD97757))
    }

    private let varcharDescription = "A character string with variable length."

    private func text(_ definition: String, _ range: String?, _ description: String) -> NSAttributedString {
        SAClaudeTypeInfoText.attributedString(definition: definition, range: range, description: description, palette: palette)
    }

    private func nsRange(of part: String, in string: NSAttributedString) -> NSRange {
        let range = (string.string as NSString).range(of: part)
        XCTAssertNotEqual(range.location, NSNotFound, "\(part) not in \(string.string)")
        return range
    }

    /// Every character of `part` carries `font` and `colour`.
    private func assertStyle(_ part: String, in string: NSAttributedString, font: NSFont, colour: NSColor,
                             file: StaticString = #filePath, line: UInt = #line) {
        let range = nsRange(of: part, in: string)
        string.enumerateAttributes(in: range) { attributes, sub, _ in
            XCTAssertEqual(attributes[.font] as? NSFont, font, "font at \(sub)", file: file, line: line)
            XCTAssertEqual(attributes[.foregroundColor] as? NSColor, colour, "colour at \(sub)", file: file, line: line)
        }
    }

    // MARK: String

    func testStringJoinsDefinitionRangeAndDescription() {
        let string = text("VARCHAR(M)", "M: 0 to 65,535 characters", varcharDescription)
        XCTAssertEqual(string.string, "VARCHAR(M)\nM: 0 to 65,535 characters\n\(varcharDescription)")
    }

    func testEmptyRangeIsOmitted() {
        let description = "A character string that can store up to 255 bytes."
        XCTAssertEqual(text("TINYTEXT", nil, description).string, "TINYTEXT\n\(description)")
        XCTAssertEqual(text("TINYTEXT", "", description).string, "TINYTEXT\n\(description)")
    }

    // MARK: Fonts and colours

    func testFontsAndColours() {
        let string = text("VARCHAR(M)", "M: 0 to 65,535 characters", varcharDescription)

        let title = SAClaudeTypeInfoText.titleFont
        XCTAssertEqual(title.pointSize, 13)
        XCTAssertTrue(title.fontDescriptor.symbolicTraits.contains(.monoSpace), "\(title)")
        XCTAssertEqual(title, NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold))
        assertStyle("VARCHAR(M)", in: string, font: title, colour: palette.text)

        XCTAssertEqual(SAClaudeTypeInfoText.rangeFont.pointSize, 11)
        assertStyle("M: 0 to 65,535 characters", in: string, font: SAClaudeTypeInfoText.rangeFont, colour: palette.muted)

        XCTAssertEqual(SAClaudeTypeInfoText.descriptionFont.pointSize, 12)
        assertStyle(varcharDescription, in: string, font: SAClaudeTypeInfoText.descriptionFont, colour: palette.text)
    }

    func testMultiLineRangeIsMuted() {
        let range = "Signed: -128 to 127\nUnsigned: 0 to 255"
        let string = text("TINYINT[(M)] [UNSIGNED] [ZEROFILL]", range, "The smallest integer type.")
        XCTAssertEqual(string.string, "TINYINT[(M)] [UNSIGNED] [ZEROFILL]\n\(range)\nThe smallest integer type.")
        assertStyle("Signed: -128 to 127", in: string, font: SAClaudeTypeInfoText.rangeFont, colour: palette.muted)
        assertStyle("Unsigned: 0 to 255", in: string, font: SAClaudeTypeInfoText.rangeFont, colour: palette.muted)
    }

    // MARK: Frame

    private let popUp = NSRect(x: 100, y: 300, width: 200, height: 250)
    private let size = NSSize(width: 410, height: 120)

    func testFrameRightOfPopUp() {
        let screen = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = SAClaudeTypeInfoText.frame(popUpFrame: popUp, screenFrame: screen, size: size)
        XCTAssertEqual(frame.minX, popUp.maxX + SAClaudeTypeInfoText.gap)
        XCTAssertEqual(frame.size, size)
    }

    func testFrameFlipsLeftAtScreenEdge() {
        // 300 + 10 + 410 = 720 > 650 - 10, so the card goes to the left of the pop-up.
        let screen = NSRect(x: 0, y: 0, width: 650, height: 900)
        let frame = SAClaudeTypeInfoText.frame(popUpFrame: popUp, screenFrame: screen, size: size)
        XCTAssertEqual(frame.minX, popUp.minX - SAClaudeTypeInfoText.gap - size.width)
        XCTAssertEqual(frame.size, size)
        // Exactly fitting (maxX of the card == screen.maxX - 10) stays on the right, as today.
        let fits = NSRect(x: 0, y: 0, width: 730, height: 900)
        XCTAssertEqual(SAClaudeTypeInfoText.frame(popUpFrame: popUp, screenFrame: fits, size: size).minX, 310)
    }

    func testFrameTopAlignedWithPopUp() {
        for width: CGFloat in [1440, 650] {
            let screen = NSRect(x: 0, y: 0, width: width, height: 900)
            let frame = SAClaudeTypeInfoText.frame(popUpFrame: popUp, screenFrame: screen, size: size)
            XCTAssertEqual(frame.maxY, popUp.maxY, "screen \(width)")
            XCTAssertEqual(frame.minY, 430, "screen \(width)")
        }
    }
}
