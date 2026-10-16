import XCTest

private typealias L = SAClaudeAlertLayout

final class SAClaudeAlertLayoutTests: XCTestCase {
    private func spec(_ buttons: [CGFloat], suppression: NSSize? = nil, accessory: L.Accessory? = nil, max: CGFloat = 600) -> L.Spec {
        L.Spec(buttonWidths: buttons, suppressionSize: suppression, accessory: accessory, maximumHeight: max)
    }

    /// Delete database: two buttons, two-line explanation.
    func testConfirmationCard() {
        let f = L.frames(L.Spec(buttonWidths: [72, 72], maximumHeight: 600), text: L.TextHeights(title: 17, message: 30))
        XCTAssertEqual(f.size, NSSize(width: 420, height: 142))
        XCTAssertEqual(f.tile, NSRect(x: 20, y: 20, width: 32, height: 32))
        XCTAssertEqual(f.textViewport, NSRect(x: 64, y: 20, width: 336, height: 58))
        XCTAssertEqual(f.textDocumentHeight, 58)
        XCTAssertFalse(f.scrolls)
        XCTAssertEqual(f.title, NSRect(x: 0, y: 7, width: 336, height: 17))
        XCTAssertEqual(f.message, NSRect(x: 0, y: 28, width: 336, height: 30))
        XCTAssertNil(f.block)
        XCTAssertNil(f.accessory)
        XCTAssertNil(f.suppression)
        XCTAssertEqual(f.buttons, [NSRect(x: 328, y: 94, width: 72, height: 28), NSRect(x: 248, y: 94, width: 72, height: 28)])
    }

    func testErrorWithServerBlock() {
        let f = L.frames(spec([72]), text: L.TextHeights(title: 17, message: 15, block: 62))
        XCTAssertEqual(f.message, NSRect(x: 0, y: 28, width: 336, height: 15))
        XCTAssertEqual(f.block, NSRect(x: 0, y: 53, width: 336, height: 62))
        XCTAssertEqual(f.textDocumentHeight, 115)
        XCTAssertEqual(f.buttons, [NSRect(x: 328, y: 151, width: 72, height: 28)])
        XCTAssertEqual(f.size, NSSize(width: 420, height: 199))
    }

    func testWholeMessageInBlock() {
        let f = L.frames(spec([72]), text: L.TextHeights(title: 17, block: 62))
        XCTAssertNil(f.message)
        XCTAssertEqual(f.block, NSRect(x: 0, y: 34, width: 336, height: 62))
        XCTAssertEqual(f.size, NSSize(width: 420, height: 180))
    }

    func testShortTextKeepsTileHeight() {
        let f = L.frames(spec([72]), text: L.TextHeights(title: 17))
        XCTAssertEqual(f.textViewport, NSRect(x: 64, y: 20, width: 336, height: 24))
        XCTAssertEqual(f.buttons[0].minY, 68)
        XCTAssertEqual(f.size, NSSize(width: 420, height: 116))
    }

    func testThreeButtonsRightAlignedInOrder() {
        let f = L.frames(spec([80, 90, 72]), text: L.TextHeights(title: 17, message: 30))
        XCTAssertEqual(f.buttons, [NSRect(x: 320, y: 94, width: 80, height: 28),
                                   NSRect(x: 222, y: 94, width: 90, height: 28),
                                   NSRect(x: 142, y: 94, width: 72, height: 28)])
    }

    func testWideButtonsWidenCard() {
        let s = spec([200, 180, 100])
        let f = L.frames(s, text: L.TextHeights(title: 17, message: 30))
        XCTAssertEqual(L.width(s), 536)
        let y = f.buttons[0].minY
        XCTAssertEqual(f.buttons, [NSRect(x: 316, y: y, width: 200, height: 28),
                                   NSRect(x: 128, y: y, width: 180, height: 28),
                                   NSRect(x: 20, y: y, width: 100, height: 28)])
        XCTAssertEqual(f.textViewport.width, 452)
    }

    func testSuppressionSharesFooterRowAndWidens() {
        let text = L.TextHeights(title: 17, message: 30)
        var f = L.frames(spec([72, 72], suppression: NSSize(width: 260, height: 18)), text: text)
        XCTAssertEqual(f.size, NSSize(width: 468, height: 142))
        XCTAssertEqual(f.suppression, NSRect(x: 20, y: 99, width: 260, height: 18))
        XCTAssertEqual(f.buttons, [NSRect(x: 376, y: 94, width: 72, height: 28), NSRect(x: 296, y: 94, width: 72, height: 28)])
        f = L.frames(spec([72, 72], suppression: NSSize(width: 120, height: 18)), text: text)
        XCTAssertEqual(f.size.width, 420)
        XCTAssertEqual(f.suppression, NSRect(x: 20, y: 99, width: 120, height: 18))
    }

    func testLongSuppressionGetsOwnRow() {
        let f = L.frames(spec([150, 190, 72], suppression: NSSize(width: 230, height: 28)), text: L.TextHeights(title: 17, message: 30))
        XCTAssertEqual(f.size, NSSize(width: 468, height: 178))
        XCTAssertEqual(f.suppression, NSRect(x: 20, y: 94, width: 230, height: 28))
        XCTAssertEqual(f.buttons, [NSRect(x: 298, y: 130, width: 150, height: 28),
                                   NSRect(x: 100, y: 130, width: 190, height: 28),
                                   NSRect(x: 20, y: 130, width: 72, height: 28)])
    }

    /// A suppression checkbox wider than the card on its own row is cut to the margins (its title truncates).
    func testOwnRowSuppressionStaysWithinTheMargins() {
        let f = L.frames(spec([150, 190, 72], suppression: NSSize(width: 500, height: 16)), text: L.TextHeights(title: 17, message: 30))
        XCTAssertEqual(f.size.width, 468)
        XCTAssertEqual(f.suppression, NSRect(x: 20, y: 94, width: 428, height: 16))
        XCTAssertEqual(f.buttons.first, NSRect(x: 298, y: 118, width: 150, height: 28))
    }

    /// Walkthrough: "Reset AUTO_INCREMENT after delete (only for Delete ALL ROWS IN TABLE)" beside three long buttons. The
    /// checkbox takes its own row spanning the content width and is as tall as its wrapped title: nothing truncates.
    func testLongSuppressionTitleWrapsOnItsOwnRowAtTheContentWidth() throws {
        let s = spec([150, 190, 72], suppression: NSSize(width: 520, height: 16))
        let content = L.width(s) - 2 * L.margin
        // The card measured the title wrapped at `content`: three lines of 16.
        let f = L.frames(s, text: L.TextHeights(title: 17, message: 30, suppression: 48))
        let box = try XCTUnwrap(f.suppression)
        XCTAssertEqual(box.height, 48)
        XCTAssertLessThanOrEqual(box.width, content)
        XCTAssertEqual(box.minX, L.margin)
        XCTAssertLessThanOrEqual(box.maxX, f.size.width - L.margin)
        // The buttons sit below it, the card is tall enough for both rows.
        XCTAssertEqual(f.buttons.first?.minY, box.maxY + L.footerRowGap)
        XCTAssertEqual(f.size.height, box.minY + 48 + L.footerRowGap + L.buttonHeight + L.margin)
        // A checkbox that fits beside the buttons is untouched by its measured height.
        let beside = L.frames(spec([72, 72], suppression: NSSize(width: 260, height: 18)), text: L.TextHeights(title: 17, message: 30, suppression: 54))
        XCTAssertEqual(beside.suppression?.height, 18)
        XCTAssertEqual(beside.size.height, 142)
    }

    /// AWS MFA: a fixed-size accessory in the text column.
    func testFixedAccessoryInTextColumn() {
        let text = L.TextHeights(title: 17, message: 60)
        let s = spec([96, 72], accessory: L.Accessory(size: NSSize(width: 200, height: 24), flexibleWidth: false))
        let f = L.frames(s, text: text)
        XCTAssertEqual(f.accessory, NSRect(x: 64, y: 120, width: 200, height: 24))
        XCTAssertEqual(f.buttons, [NSRect(x: 304, y: 160, width: 96, height: 28), NSRect(x: 224, y: 160, width: 72, height: 28)])
        XCTAssertEqual(f.size, NSSize(width: 420, height: 208))
        let wide = spec([96, 72], accessory: L.Accessory(size: NSSize(width: 520, height: 100), flexibleWidth: false))
        XCTAssertEqual(L.width(wide), 604)
    }

    /// CHECK TABLE: a flexible accessory spans the card between the margins.
    func testFlexibleAccessorySpansCard() {
        let text = L.TextHeights(title: 17, message: 15)
        let f = L.frames(spec([72], accessory: L.Accessory(size: NSSize(width: 600, height: 200), flexibleWidth: true)), text: text)
        XCTAssertEqual(f.size, NSSize(width: 640, height: 339))
        XCTAssertEqual(f.accessory, NSRect(x: 20, y: 75, width: 600, height: 200))
        XCTAssertEqual(f.buttons, [NSRect(x: 548, y: 291, width: 72, height: 28)])
        let narrow = L.frames(spec([72], accessory: L.Accessory(size: NSSize(width: 300, height: 120), flexibleWidth: true)), text: text)
        XCTAssertEqual(narrow.size.width, 420)
        XCTAssertEqual(narrow.accessory?.width, 380)
    }

    func testLongTextScrollsWithinMaxHeight() {
        let f = L.frames(spec([72], max: 600), text: L.TextHeights(title: 17, message: 872))
        XCTAssertEqual(f.size, NSSize(width: 420, height: 600))
        XCTAssertEqual(f.textViewport, NSRect(x: 64, y: 20, width: 336, height: 516))
        XCTAssertEqual(f.textDocumentHeight, 900)
        XCTAssertTrue(f.scrolls)
        XCTAssertEqual(f.message, NSRect(x: 0, y: 28, width: 336, height: 872))
        XCTAssertEqual(f.buttons, [NSRect(x: 328, y: 552, width: 72, height: 28)])
    }

    func testTallAccessoryKeepsMinimumViewport() {
        let s = spec([72], accessory: L.Accessory(size: NSSize(width: 200, height: 400), flexibleWidth: false), max: 300)
        let f = L.frames(s, text: L.TextHeights(title: 17, message: 72))
        XCTAssertEqual(f.textViewport.height, 60)
        XCTAssertTrue(f.scrolls)
        XCTAssertEqual(f.size.height, 556)
        XCTAssertEqual(f.accessory, NSRect(x: 64, y: 92, width: 200, height: 400))
    }

    func testButtonWidth() {
        XCTAssertEqual(L.buttonWidth(titleWidth: 30), 72)
        XCTAssertEqual(L.buttonWidth(titleWidth: 50.2), 83)
    }

    func testBlockMetrics() {
        XCTAssertEqual(L.blockHeight(labelHeight: 14, textHeight: 28), 62)
        XCTAssertEqual(L.blockFrames(blockWidth: 336, labelHeight: 14, textHeight: 28),
                       L.BlockFrames(label: NSRect(x: 10, y: 8, width: 316, height: 14), text: NSRect(x: 10, y: 26, width: 316, height: 28)))
    }

    /// Layout is a pure function of its inputs: computing it again (an apply after an apply) changes nothing.
    func testFramesAreDeterministic() {
        let s = spec([72], accessory: L.Accessory(size: NSSize(width: 600, height: 200), flexibleWidth: true))
        let text = L.TextHeights(title: 17, message: 15)
        XCTAssertEqual(L.frames(s, text: text), L.frames(s, text: text))
    }
}
