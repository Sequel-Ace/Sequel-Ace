//
//  SAClaudeTableInfoLayoutTests.swift
//  Unit Tests
//

import AppKit
import XCTest

final class SAClaudeTableInfoLayoutTests: XCTestCase {
    private typealias L = SAClaudeTableInfoLayout

    func testFramesAtXIBSize() {
        let f = L.frames(in: NSRect(x: 0, y: 0, width: 706, height: 546), generalRows: 3, storageRows: 4, copyButtonWidth: 64)
        XCTAssertEqual(f.generalTitle, NSRect(x: 16, y: 516, width: 674, height: 16))
        XCTAssertEqual(f.generalCard, NSRect(x: 16, y: 406, width: 674, height: 104))
        XCTAssertEqual(f.storageTitle, NSRect(x: 16, y: 374, width: 674, height: 16))
        XCTAssertEqual(f.storageCard, NSRect(x: 16, y: 232, width: 674, height: 136))
        XCTAssertEqual(f.syntaxTitle, NSRect(x: 16, y: 192, width: 602, height: 24))
        XCTAssertEqual(f.copyButton, NSRect(x: 626, y: 192, width: 64, height: 24))
        XCTAssertEqual(f.splitView, NSRect(x: 16, y: 12, width: 674, height: 174))
    }

    func testNarrowWidthKeepsEverythingInside() {
        let f = L.frames(in: NSRect(x: 0, y: 0, width: 600, height: 546), generalRows: 3, storageRows: 4, copyButtonWidth: 64)
        XCTAssertEqual(f.generalCard.width, 568)
        XCTAssertEqual(f.copyButton.maxX, 584)
        XCTAssertLessThanOrEqual(f.syntaxTitle.maxX, f.copyButton.minX - 8)
        let rows = L.rows(in: f.storageCard, count: 4, half: .right, labelWidth: 100)
        XCTAssertLessThanOrEqual(rows[0].value.maxX, f.storageCard.maxX - L.cardInsetX)
        XCTAssertGreaterThan(rows[0].value.width, 0)
    }

    func testWideWindowStretchesCardsAndSplit() {
        let f = L.frames(in: NSRect(x: 0, y: 0, width: 1200, height: 800), generalRows: 3, storageRows: 4, copyButtonWidth: 64)
        XCTAssertEqual(f.storageCard.width, 1168)
        XCTAssertEqual(f.splitView.height, 800 - 14 - 16 - 6 - 104 - 16 - 16 - 6 - 136 - 16 - 24 - 6 - 12)
    }

    func testShortHeightKeepsMinimumSplit() {
        let f = L.frames(in: NSRect(x: 0, y: 0, width: 706, height: 400), generalRows: 3, storageRows: 4, copyButtonWidth: 64)
        XCTAssertEqual(f.splitView.height, L.minimumSplitHeight)
        XCTAssertEqual(f.splitView.maxY, f.syntaxTitle.minY - L.titleToCard)
    }

    func testRowsSplitTheCardIntoHalves() {
        let card = NSRect(x: 16, y: 406, width: 674, height: 104)
        let left = L.rows(in: card, count: 3, half: .left, labelWidth: 80)
        XCTAssertEqual(left[0], .init(label: NSRect(x: 28, y: 474, width: 80, height: 32), value: NSRect(x: 116, y: 474, width: 229, height: 32)))
        XCTAssertEqual(left[2].label.minY, 410)
        let right = L.rows(in: card, count: 2, half: .right, labelWidth: 90)
        XCTAssertEqual(right[0].label.minX, 361)
        XCTAssertEqual(right[0].value.maxX, 678)
    }

    func testLabelPairing() {
        let labels = [NSRect(x: 23, y: 402, width: 150, height: 14), NSRect(x: 286, y: 402, width: 172, height: 14), NSRect(x: 23, y: 380, width: 150, height: 14)]
        XCTAssertEqual(L.labelIndex(for: NSRect(x: 175, y: 402, width: 99, height: 14), among: labels), 0)
        XCTAssertEqual(L.labelIndex(for: NSRect(x: 462, y: 402, width: 210, height: 14), among: labels), 1)
        XCTAssertEqual(L.labelIndex(for: NSRect(x: 175, y: 380, width: 99, height: 14), among: labels), 2)
        XCTAssertNil(L.labelIndex(for: NSRect(x: 175, y: 300, width: 99, height: 14), among: labels))
        // popup 22pt tall at y 498 pairs with a 14pt label at y 503 (midY 509 vs 510)
        XCTAssertEqual(L.labelIndex(for: NSRect(x: 115, y: 498, width: 161, height: 22), among: [NSRect(x: 22, y: 503, width: 91, height: 14)]), 0)
    }

    func testCentredAndCopyEnabled() {
        XCTAssertEqual(L.centred(height: 24, in: NSRect(x: 0, y: 474, width: 10, height: 32)), 478)
        XCTAssertFalse(L.copyEnabled(syntax: ""))
        XCTAssertFalse(L.copyEnabled(syntax: "  \n"))
        XCTAssertTrue(L.copyEnabled(syntax: "CREATE TABLE `t` (`id` int)"))
    }

    func testCardFillIsBetweenBackgroundAndFieldFill() {
        let bg = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1), text = NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        let card = SAClaudeFilterChrome.cardFill(text: text, background: bg).usingColorSpace(.sRGB)!
        XCTAssertEqual(card.redComponent, 0.025, accuracy: 0.005)
        XCTAssertLessThan(card.redComponent, SAClaudeFilterChrome.fieldFill(text: text, background: bg).usingColorSpace(.sRGB)!.redComponent)
    }
}
