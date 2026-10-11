//
//  SACompletionWindowLayout.swift
//  Sequel Ace
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import AppKit

@objc final class SACompletionWindowLayout: NSObject {

    /// The popup is a card whose scroll view sits this far inside the window on every side.
    @objc static let cardPadding: CGFloat = 5

    /// Returns a window size whose scroll view (inside the card padding) fits
    /// the table content whenever the maximum width allows it. If horizontal
    /// scrolling is unavoidable, its non-overlay scroller is added below the
    /// content instead of covering it. The maximum width caps the scroll view;
    /// the padding is added outside it.
    @objc(windowSizeForTableContentSize:maximumWidth:scrollerStyle:)
    static func windowSize(
        for tableContentSize: NSSize,
        maximumWidth: CGFloat,
        scrollerStyle: NSScroller.Style
    ) -> NSSize {
        let fittingSize = scrollViewFrameSize(
            for: tableContentSize,
            includesHorizontalScroller: false,
            scrollerStyle: scrollerStyle
        )
        let fittingWidth = ceil(fittingSize.width)
        let availableWidth = max(0, floor(maximumWidth))

        guard fittingWidth > availableWidth else {
            return padded(NSSize(width: fittingWidth, height: ceil(fittingSize.height)))
        }

        let scrollableSize = scrollViewFrameSize(
            for: tableContentSize,
            includesHorizontalScroller: true,
            scrollerStyle: scrollerStyle
        )
        return padded(NSSize(width: availableWidth, height: ceil(scrollableSize.height)))
    }

    private static func padded(_ scrollViewSize: NSSize) -> NSSize {
        NSSize(width: scrollViewSize.width + 2 * cardPadding, height: scrollViewSize.height + 2 * cardPadding)
    }

    private static func scrollViewFrameSize(
        for contentSize: NSSize,
        includesHorizontalScroller: Bool,
        scrollerStyle: NSScroller.Style
    ) -> NSSize {
        NSScrollView.frameSize(
            forContentSize: contentSize,
            horizontalScrollerClass: includesHorizontalScroller ? NSScroller.self : nil,
            verticalScrollerClass: NSScroller.self,
            borderType: .noBorder,
            controlSize: .small,
            scrollerStyle: scrollerStyle
        )
    }
}
