//
//  SAClaudeStatusChromeTests.swift
//  Unit Tests
//

import AppKit
import XCTest

final class SAClaudeStatusChromeTests: XCTestCase {

    private func srgb(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
    private func theme(bg: UInt32, text: UInt32) -> SAClaudeThemeColours {
        SAClaudeThemeColours(background: srgb(bg), text: srgb(text), keyword: srgb(0x6DA7EC), variable: srgb(0xA096EB),
                             caret: srgb(0xD97757), quote: srgb(0x55BF50), backtick: srgb(0xF4ABAB), selection: srgb(0x383835))
    }

    func testImageNamesMapToKinds() {
        XCTAssertEqual(SAClaudeCompletionKind(imageName: "table-small-square"), .table)
        XCTAssertEqual(SAClaudeCompletionKind(imageName: "table-view-small-square"), .view)
        XCTAssertEqual(SAClaudeCompletionKind(imageName: "database-small"), .database)
        XCTAssertEqual(SAClaudeCompletionKind(imageName: "field-small-square"), .field)
        XCTAssertEqual(SAClaudeCompletionKind(imageName: "func-small"), .function)
        XCTAssertEqual(SAClaudeCompletionKind(imageName: "proc-small"), .procedure)
        XCTAssertEqual(SAClaudeCompletionKind(imageName: "dummy-small"), .keyword)
        XCTAssertEqual(SAClaudeCompletionKind.field.glyph, .field)
        XCTAssertEqual(SAClaudeCompletionKind.keyword.glyph, .keyword)
    }

    func testUnknownImageNameHasNoKind() {
        XCTAssertNil(SAClaudeCompletionKind(imageName: "sync_arrows_01"))
        XCTAssertNil(SAClaudeCompletionKind(imageName: "snippet-small"))
    }

    func testCompletionTintsComeFromTheTheme() {
        let t = theme(bg: 0x151515, text: 0xF0EFEC)
        XCTAssertEqual(SAClaudeStatusChrome.completionTint(.table, theme: t), t.keyword)
        XCTAssertEqual(SAClaudeStatusChrome.completionTint(.view, theme: t), t.variable)
        XCTAssertEqual(SAClaudeStatusChrome.completionTint(.database, theme: t), t.caret)
        XCTAssertEqual(SAClaudeStatusChrome.completionTint(.function, theme: t), t.quote)
        XCTAssertEqual(SAClaudeStatusChrome.completionTint(.procedure, theme: t), t.backtick)
        XCTAssertEqual(SAClaudeStatusChrome.completionTint(.field, theme: t), SAClaudeStatusChrome.muted(theme: t))
        XCTAssertEqual(SAClaudeStatusChrome.completionTint(.keyword, theme: t), SAClaudeStatusChrome.muted(theme: t))
    }

    func testPopupSurfaceFollowsBackgroundBrightness() {
        let dark = theme(bg: 0x151515, text: 0xF0EFEC)
        XCTAssertEqual(SAClaudeStatusChrome.popupSurface(theme: dark),
                       SAClaudeEditorChrome.derivedColour(text: dark.text, background: dark.background, ratio: 0.035))
        let light = theme(bg: 0xFCFCFB, text: 0x0B0B0B)
        let surface = SAClaudeStatusChrome.popupSurface(theme: light).usingColorSpace(.sRGB)!
        XCTAssertEqual(surface.redComponent, 1, accuracy: 0.001)
        XCTAssertEqual(surface.blueComponent, 1, accuracy: 0.001)
    }

    func testInfoColoursDifferForErrorAndOk() {
        let t = theme(bg: 0x151515, text: 0xF0EFEC)
        XCTAssertEqual(SAClaudeStatusChrome.statusDot(isError: true, theme: t), SAClaudeStatusChrome.clay)
        XCTAssertEqual(SAClaudeStatusChrome.statusDot(isError: false, theme: t), t.quote)
        XCTAssertEqual(SAClaudeStatusChrome.messageText(isError: true, theme: t),
                       SAClaudeEditorChrome.derivedColour(text: t.text, background: SAClaudeStatusChrome.clay, ratio: 0.35))
        XCTAssertEqual(SAClaudeStatusChrome.messageText(isError: false, theme: t),
                       SAClaudeEditorChrome.derivedColour(text: t.text, background: t.background, ratio: 0.55))
        XCTAssertEqual(SAClaudeStatusChrome.errorFill(theme: t),
                       SAClaudeEditorChrome.derivedColour(text: SAClaudeStatusChrome.clay, background: t.background, ratio: 0.06))
    }
}
