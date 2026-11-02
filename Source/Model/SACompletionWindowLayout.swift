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

    /// The list's row height for the usual editor font sizes.
    static let minimumRowHeight: CGFloat = 26

    /// An NSTextFieldCell draws its text this far right of its drawing rect (the line fragment padding).
    static let cellTextInset: CGFloat = 2

    /// The row height for the editor font's line height: 26pt, or the line plus 3pt above and
    /// below once a large font would no longer fit.
    static func rowHeight(forFontLineHeight lineHeight: CGFloat) -> CGFloat {
        max(minimumRowHeight, ceil(lineHeight) + 6)
    }

    /// How far right of the window's left edge a completion's name text starts, given the x of
    /// the name cell's drawing rect within the table.
    static func nameTextOffset(cellDrawingMinX: CGFloat) -> CGFloat {
        cardPadding + cellDrawingMinX + cellTextInset
    }

    /// Whether the popup opens above the caret's line instead of below it: it doesn't fit between
    /// the line and the bottom of the editor's visible area, and there is more room above the line.
    /// Screen coordinates (y up); `lineBottom` is the bottom of the caret's line.
    static func opensAbove(popupHeight: CGFloat, lineBottom: CGFloat, lineHeight: CGFloat,
                           visibleMinY: CGFloat, visibleMaxY: CGFloat) -> Bool {
        let roomBelow = lineBottom - visibleMinY
        let roomAbove = visibleMaxY - (lineBottom + lineHeight)
        return popupHeight > roomBelow && roomAbove > roomBelow
    }

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
