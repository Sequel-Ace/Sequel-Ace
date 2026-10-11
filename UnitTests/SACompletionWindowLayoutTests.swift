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
