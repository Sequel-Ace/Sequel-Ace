//
//  SACompletionWindowLayout.swift
//  Sequel Ace
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import AppKit

@objc final class SACompletionWindowLayout: NSObject {

    /// Returns a scroll-view frame that fits the table content whenever the
    /// maximum width allows it. If horizontal scrolling is unavoidable, its
    /// non-overlay scroller is added below the content instead of covering it.
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
            return NSSize(width: fittingWidth, height: ceil(fittingSize.height))
        }

        let scrollableSize = scrollViewFrameSize(
            for: tableContentSize,
            includesHorizontalScroller: true,
            scrollerStyle: scrollerStyle
        )
        return NSSize(width: availableWidth, height: ceil(scrollableSize.height))
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
