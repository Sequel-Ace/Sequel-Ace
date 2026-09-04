//
//  SATableListCellRendererTests.swift
//  Unit Tests
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import AppKit
import XCTest

final class SATableListCellRendererTests: XCTestCase {

    func testCommentStartsAfterTheCompleteName() throws {
        let name = makeName("customers")
        let comment = RecordingCommentCell(textCell: "Customer records and contact details")
        var nameFrame = NSRect.zero

        render(name: name, comment: comment, width: 420) { nameFrame = $0 }

        XCTAssertGreaterThanOrEqual(nameFrame.width, name.attributedStringValue.size().width)
        XCTAssertGreaterThan(try XCTUnwrap(comment.drawnFrame).minX, nameFrame.maxX)
        XCTAssertLessThanOrEqual(try XCTUnwrap(comment.drawnFrame).maxX, 420)
    }

    func testLongNameTakesPriorityOverCommentInNarrowSidebar() {
        let name = makeName("a_long_table_name_that_fills_the_entire_sidebar")
        let comment = RecordingCommentCell(textCell: "Must not cover the name")
        var didDrawName = false

        render(name: name, comment: comment, width: 90) { _ in didDrawName = true }

        XCTAssertTrue(didDrawName)
        XCTAssertNil(comment.drawnFrame)
    }

    func testDrawingDoesNotPermanentlyTruncateNameWhenSidebarIsResized() {
        let name = makeName("monthly_customer_order_history")
        name.lineBreakMode = .byClipping
        let original = name.attributedStringValue

        for width: CGFloat in [70, 500] {
            render(name: name, comment: nil, width: width) { _ in
                XCTAssertEqual(name.lineBreakMode, .byTruncatingTail)
                XCTAssertEqual(name.stringValue, original.string)
            }
            XCTAssertEqual(name.attributedStringValue, original)
            XCTAssertEqual(name.lineBreakMode, .byClipping)
        }
    }

    func testEmptyCommentIsNotDrawn() {
        let comment = RecordingCommentCell(textCell: "")
        render(name: makeName("customers"), comment: comment)
        XCTAssertNil(comment.drawnFrame)
    }

    func testClearingAReusedCommentCellRemovesItsPreviousText() {
        let comment = RecordingCommentCell(textCell: "Previous table's comment")
        render(name: makeName("customers"), comment: comment)
        XCTAssertNotNil(comment.drawnFrame)

        comment.stringValue = ""
        comment.drawnFrame = nil
        render(name: makeName("orders"), comment: comment)
        XCTAssertNil(comment.drawnFrame)
    }

    func testCommentTracksTheNameFontAfterPreferenceChanges() {
        let name = makeName("orders")
        let comment = RecordingCommentCell(textCell: "Order details")

        for size: CGFloat in [11, 18, 28] {
            name.font = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
            render(name: name, comment: comment, width: 600)
            XCTAssertEqual(comment.font, name.font)
            XCTAssertEqual(comment.attributedStringValue.attribute(.font, at: 0, effectiveRange: nil) as? NSFont, name.font)
        }
    }

    func testCommentIsASingleLeftAlignedTruncatedLine() {
        let comment = RecordingCommentCell(textCell: "First line\nSecond line\r\nThird\tcolumn")
        render(name: makeName("orders"), comment: comment)

        XCTAssertFalse(comment.stringValue.contains("\n"))
        XCTAssertFalse(comment.stringValue.contains("\r"))
        XCTAssertFalse(comment.stringValue.contains("\t"))
        XCTAssertTrue(comment.usesSingleLineMode)
        XCTAssertEqual(comment.alignment, .left)
        XCTAssertEqual(comment.lineBreakMode, .byTruncatingTail)
        let paragraph = comment.attributedStringValue.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertEqual(paragraph?.lineBreakMode, .byTruncatingTail)
    }

    func testSelectedCommentUsesReadableTextColor() {
        let name = EmphasizedNameCell(textCell: "orders")
        let comment = RecordingCommentCell(textCell: "Order details")
        render(name: name, comment: comment)

        XCTAssertEqual(comment.attributedStringValue.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, .selectedControlTextColor)
    }

    func testUnselectedCommentUsesSecondaryTextColor() {
        let comment = RecordingCommentCell(textCell: "Order details")
        render(name: makeName("orders"), comment: comment)

        XCTAssertEqual(comment.attributedStringValue.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, .secondaryLabelColor)
    }

    func testLayoutHandlesTinyWidthsAndNonzeroOrigins() {
        for width: CGFloat in [0, 1, 4, 5, 10, 100, 500] {
            let frame = NSRect(x: 27, y: 40, width: width, height: 24)
            let layout = SATableListCellRenderer.layout(in: frame, nameWidth: 83.5)
            for textFrame in [layout.nameFrame, layout.commentFrame] {
                XCTAssertGreaterThanOrEqual(textFrame.width, 0)
                XCTAssertGreaterThanOrEqual(textFrame.minX, frame.minX)
                XCTAssertLessThanOrEqual(textFrame.maxX, frame.maxX)
                XCTAssertEqual(textFrame.minY, frame.minY)
                XCTAssertEqual(textFrame.height, frame.height)
            }
            XCTAssertLessThanOrEqual(layout.nameFrame.maxX, layout.commentFrame.minX)
        }
    }

    func testUnicodeAndProportionalFontsKeepTextRegionsSeparate() throws {
        for title in ["WWWWWWW", "iiiiiii", "客户订单", "cafe\u{301}_orders"] {
            for size: CGFloat in [11, 18, 28] {
                let name = makeName(title)
                name.font = NSFont.systemFont(ofSize: size)
                let comment = RecordingCommentCell(textCell: "Additional details")
                var nameFrame = NSRect.zero
                render(name: name, comment: comment, width: 600) { nameFrame = $0 }
                XCTAssertGreaterThan(try XCTUnwrap(comment.drawnFrame).minX, nameFrame.maxX)
                XCTAssertGreaterThanOrEqual(nameFrame.width, name.attributedStringValue.size().width)
            }
        }
    }

    func testZeroWidthDoesNotDrawEitherTextCell() {
        let comment = RecordingCommentCell(textCell: "Order details")
        render(name: makeName("orders"), comment: comment, width: 0) { _ in
            XCTFail("A zero-width cell must not draw its name")
        }
        XCTAssertNil(comment.drawnFrame)
    }

    private func makeName(_ text: String) -> NSTextFieldCell {
        let cell = NSTextFieldCell(textCell: text)
        cell.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        return cell
    }

    private func render(
        name: NSTextFieldCell,
        comment: NSCell?,
        width: CGFloat = 420,
        drawName: (NSRect) -> Void = { _ in }
    ) {
        let image = NSImage(size: NSSize(width: 640, height: 60))
        image.lockFocus()
        defer { image.unlockFocus() }
        SATableListCellRenderer.draw(
            nameCell: name,
            commentCell: comment,
            frame: NSRect(x: 0, y: 0, width: width, height: 50),
            in: NSView(),
            drawName: drawName
        )
    }
}

private final class RecordingCommentCell: NSTextFieldCell {
    var drawnFrame: NSRect?

    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        drawnFrame = cellFrame
    }
}

private final class EmphasizedNameCell: NSTextFieldCell {
    override var interiorBackgroundStyle: NSView.BackgroundStyle { .emphasized }
}
