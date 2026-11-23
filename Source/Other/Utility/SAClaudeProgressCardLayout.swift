//
//  SAClaudeProgressCardLayout.swift
//  Sequel Ace
//
//  Pure geometry and text for the Claude progress card: Export's and Import's progress sheets re-laid out in code
//  (`SAClaudeProgressSheetStyler`) as a card - no app icon, the title over a muted detail line with the percentage at
//  its right end, the accent bar, and Cancel at the bottom right, all inside generous padding. Coordinates are
//  AppKit's (origin bottom-left, as the sheet's content view). Nothing here touches views. App and Unit Tests targets.
//

import Foundation

enum SAClaudeProgressCardLayout {
    static let padding: CGFloat = 20
    static let titleHeight: CGFloat = 17, titleDetailGap: CGFloat = 4, detailHeight: CGFloat = 14
    /// The percentage's column at the right end of the detail line (and the gap before it).
    static let percentWidth: CGFloat = 40, percentGap: CGFloat = 8
    /// From the detail line to the bar's frame, and from the bar's frame to the button row. The bar's frame is the
    /// XIB indicator's (20pt tall around a 6pt track), so the visible gaps are 7pt larger.
    static let detailBarGap: CGFloat = 6, barButtonGap: CGFloat = 10
    static let buttonHeight: CGFloat = 28, minimumButtonWidth: CGFloat = 80, buttonTitlePadding: CGFloat = 16

    struct Frames: Equatable {
        var size: CGSize
        var title: CGRect
        var detail: CGRect
        var percent: CGRect
        var bar: CGRect
        var cancel: CGRect
    }

    /// `barSize` is the indicator's own size (its width is the export's progress scale, so it is kept); the card's
    /// content column is that wide. `cancelTitleWidth` is the measured title of the Cancel button.
    static func frames(barSize: CGSize, cancelTitleWidth: CGFloat) -> Frames {
        let column = barSize.width
        let cancelWidth = max(minimumButtonWidth, ceil(cancelTitleWidth) + 2 * buttonTitlePadding)
        let height = padding + titleHeight + titleDetailGap + detailHeight + detailBarGap + barSize.height + barButtonGap + buttonHeight + padding
        let size = CGSize(width: column + 2 * padding, height: height)

        let cancel = CGRect(x: padding + column - cancelWidth, y: padding, width: cancelWidth, height: buttonHeight)
        let bar = CGRect(x: padding, y: cancel.maxY + barButtonGap, width: column, height: barSize.height)
        let detailY = bar.maxY + detailBarGap
        let percent = CGRect(x: padding + column - percentWidth, y: detailY, width: percentWidth, height: detailHeight)
        let detail = CGRect(x: padding, y: detailY, width: column - percentWidth - percentGap, height: detailHeight)
        let title = CGRect(x: padding, y: detail.maxY + titleDetailGap, width: column, height: titleHeight)
        return Frames(size: size, title: title, detail: detail, percent: percent, bar: bar, cancel: cancel)
    }

    /// The percentage shown at the end of the detail line: whole percent, rounded down (100% only when done); nil
    /// while the progress is indeterminate or the range is empty.
    static func percentText(value: Double, minimum: Double, maximum: Double, indeterminate: Bool,
                            locale: Locale = .current) -> String? {
        guard !indeterminate, maximum > minimum else { return nil }
        let fraction = min(1, max(0, (value - minimum) / (maximum - minimum)))
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 0
        formatter.roundingMode = .down
        formatter.locale = locale
        return formatter.string(from: NSNumber(value: fraction))
    }
}
