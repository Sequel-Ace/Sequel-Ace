//
//  SACompletionWindowLayoutTests.swift
//  Unit Tests
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import AppKit
import XCTest

final class SACompletionWindowLayoutTests: XCTestCase {

    private let tableContentSize = NSSize(width: 530, height: 255)

    func testLegacyScrollersFitAllColumnsWithoutReducingRowHeight() {
        let result = SACompletionWindowLayout.windowSize(
            for: tableContentSize,
            maximumWidth: 1_000,
            scrollerStyle: .legacy
        )

        let visibleContentSize = contentSize(for: scrollViewSize(result), includesHorizontalScroller: false, style: .legacy)
        XCTAssertEqual(visibleContentSize, tableContentSize)
    }

    func testOverlayScrollersFitAllColumnsWithoutExtraWindowSpace() {
        let result = SACompletionWindowLayout.windowSize(
            for: tableContentSize,
            maximumWidth: 1_000,
            scrollerStyle: .overlay
        )

        XCTAssertEqual(scrollViewSize(result), tableContentSize)
    }

    func testLegacyHorizontalScrollerIsPlacedBelowRowsWhenWidthIsCapped() {
        let result = SACompletionWindowLayout.windowSize(
            for: tableContentSize,
            maximumWidth: 450,
            scrollerStyle: .legacy
        )

        let visibleContentSize = contentSize(for: scrollViewSize(result), includesHorizontalScroller: true, style: .legacy)
        XCTAssertEqual(scrollViewSize(result).width, 450)
        XCTAssertEqual(visibleContentSize.height, tableContentSize.height)
    }

    func testOverlayHorizontalScrollerDoesNotIncreaseWindowHeightWhenWidthIsCapped() {
        let result = SACompletionWindowLayout.windowSize(
            for: tableContentSize,
            maximumWidth: 450,
            scrollerStyle: .overlay
        )

        XCTAssertEqual(scrollViewSize(result), NSSize(width: 450, height: tableContentSize.height))
    }

    func testWindowAddsTheCardPaddingOnEverySide() {
        let result = SACompletionWindowLayout.windowSize(
            for: tableContentSize,
            maximumWidth: 1_000,
            scrollerStyle: .overlay
        )

        XCTAssertEqual(SACompletionWindowLayout.cardPadding, 5)
        XCTAssertEqual(result, NSSize(width: tableContentSize.width + 10, height: tableContentSize.height + 10))
    }

    func testRowsStay26ptForUsualEditorFonts() {
        XCTAssertEqual(SACompletionWindowLayout.rowHeight(forFontLineHeight: 14), 26)
        XCTAssertEqual(SACompletionWindowLayout.rowHeight(forFontLineHeight: 20), 26)
    }

    func testRowsGrowWithALargeEditorFont() {
        XCTAssertEqual(SACompletionWindowLayout.rowHeight(forFontLineHeight: 21), 27)
        XCTAssertEqual(SACompletionWindowLayout.rowHeight(forFontLineHeight: 28), 34)
        // A fractional line height is rounded up before the 3pt above and below are added.
        XCTAssertEqual(SACompletionWindowLayout.rowHeight(forFontLineHeight: 27.2), 34)
    }

    func testNameTextOffsetAddsTheCardPaddingAndTheCellsTextInset() {
        // Multi-column list: the name cell starts at 20pt icon + 6pt spacing + half the name column's 6pt spacing.
        XCTAssertEqual(SACompletionWindowLayout.nameTextOffset(cellDrawingMinX: 29), 36)
        // One-column and dictionary lists: the icon column is 0pt wide.
        XCTAssertEqual(SACompletionWindowLayout.nameTextOffset(cellDrawingMinX: 9), 16)
    }

    func testPopupOpensAboveTheCaretOnlyWhenItRunsPastTheEditorAndThereIsMoreRoomAbove() {
        // Editor visible from y 100 to 600; caret lines are 16pt tall.
        func opensAbove(_ popupHeight: CGFloat, lineBottom: CGFloat) -> Bool {
            SACompletionWindowLayout.opensAbove(popupHeight: popupHeight, lineBottom: lineBottom, lineHeight: 16,
                                                visibleMinY: 100, visibleMaxY: 600)
        }
        // Near the top: fits below.
        XCTAssertFalse(opensAbove(280, lineBottom: 560))
        // Last line of the editor: 20pt below, 464pt above.
        XCTAssertTrue(opensAbove(280, lineBottom: 120))
        // Exactly fits below.
        XCTAssertFalse(opensAbove(280, lineBottom: 380))
        // Fits neither way: the bigger side wins.
        XCTAssertFalse(opensAbove(600, lineBottom: 400))
        XCTAssertTrue(opensAbove(600, lineBottom: 250))
    }

    /// The scroll view's frame inside the card padding.
    private func scrollViewSize(_ windowSize: NSSize) -> NSSize {
        let padding = SACompletionWindowLayout.cardPadding
        return NSSize(width: windowSize.width - 2 * padding, height: windowSize.height - 2 * padding)
    }

    private func contentSize(
        for frameSize: NSSize,
        includesHorizontalScroller: Bool,
        style: NSScroller.Style
    ) -> NSSize {
        NSScrollView.contentSize(
            forFrameSize: frameSize,
            horizontalScrollerClass: includesHorizontalScroller ? NSScroller.self : nil,
            verticalScrollerClass: NSScroller.self,
            borderType: .noBorder,
            controlSize: .small,
            scrollerStyle: style
        )
    }
}
