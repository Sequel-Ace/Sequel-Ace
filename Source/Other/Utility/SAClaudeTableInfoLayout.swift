//
//  SAClaudeTableInfoLayout.swift
//  Sequel Ace
//
//  Frames for the Claude Table Info tab: section titles, the General and Storage cards, the Create syntax
//  title row with its Copy button, and the split view below. Pure geometry, shared with Unit Tests.
//

import AppKit

enum SAClaudeTableInfoLayout {
    static let sideMargin: CGFloat = 16
    static let topMargin: CGFloat = 14
    static let titleHeight: CGFloat = 16
    static let titleToCard: CGFloat = 6
    static let sectionGap: CGFloat = 16
    static let cardInsetX: CGFloat = 12
    static let cardInsetY: CGFloat = 4
    static let rowHeight: CGFloat = 32
    static let halfGap: CGFloat = 16
    static let labelGap: CGFloat = 8
    static let copyRowHeight: CGFloat = 24
    static let bottomMargin: CGFloat = 12
    static let minimumSplitHeight: CGFloat = 120
    static let pillMaxWidth: CGFloat = 220
    static let cardRadius: CGFloat = 9

    struct Frames: Equatable {
        var generalTitle, generalCard, storageTitle, storageCard, syntaxTitle, copyButton, splitView: NSRect
    }

    enum Half { case left, right }

    struct Row: Equatable {
        var label: NSRect
        var value: NSRect
    }

    static func frames(in bounds: NSRect, generalRows: Int, storageRows: Int, copyButtonWidth: CGFloat) -> Frames {
        let x = bounds.minX + sideMargin
        let width = max(bounds.width - 2 * sideMargin, 0)
        var top = bounds.maxY - topMargin

        func title() -> NSRect {
            defer { top -= titleHeight + titleToCard }
            return NSRect(x: x, y: top - titleHeight, width: width, height: titleHeight)
        }
        func card(rows: Int) -> NSRect {
            let height = CGFloat(rows) * rowHeight + 2 * cardInsetY
            defer { top -= height + sectionGap }
            return NSRect(x: x, y: top - height, width: width, height: height)
        }

        let generalTitle = title()
        let generalCard = card(rows: generalRows)
        let storageTitle = title()
        let storageCard = card(rows: storageRows)

        let rowY = top - copyRowHeight
        let copyButton = NSRect(x: x + width - copyButtonWidth, y: rowY, width: copyButtonWidth, height: copyRowHeight)
        let syntaxTitle = NSRect(x: x, y: rowY, width: max(copyButton.minX - 8 - x, 0), height: copyRowHeight)
        top = rowY - titleToCard

        let available = top - (bounds.minY + bottomMargin)
        let splitHeight = max(available, minimumSplitHeight)
        let splitView = NSRect(x: x, y: top - splitHeight, width: width, height: splitHeight)

        return Frames(generalTitle: generalTitle, generalCard: generalCard, storageTitle: storageTitle,
                      storageCard: storageCard, syntaxTitle: syntaxTitle, copyButton: copyButton, splitView: splitView)
    }

    /// The rows of one half of a card, top row first.
    static func rows(in card: NSRect, count: Int, half: Half, labelWidth: CGFloat) -> [Row] {
        let innerWidth = card.width - 2 * cardInsetX
        let halfWidth = max((innerWidth - halfGap) / 2, 0)
        let halfX = card.minX + cardInsetX + (half == .left ? 0 : halfWidth + halfGap)
        let valueWidth = max(halfWidth - labelWidth - labelGap, 0)
        return (0..<count).map { index in
            let y = card.maxY - cardInsetY - CGFloat(index + 1) * rowHeight
            return Row(label: NSRect(x: halfX, y: y, width: labelWidth, height: rowHeight),
                       value: NSRect(x: halfX + labelWidth + labelGap, y: y, width: valueWidth, height: rowHeight))
        }
    }

    /// The XIB label for a control: on the same line (mid-lines within 6pt) and ending left of it; the nearest wins.
    static func labelIndex(for control: NSRect, among labels: [NSRect]) -> Int? {
        var best: (index: Int, maxX: CGFloat)?
        for (index, label) in labels.enumerated() where abs(label.midY - control.midY) <= 6 && label.maxX <= control.minX + 2 {
            if best == nil || label.maxX > best!.maxX { best = (index, label.maxX) }
        }
        return best?.index
    }

    static func centred(height: CGFloat, in row: NSRect) -> CGFloat {
        (row.midY - height / 2).rounded(.down)
    }

    static func copyEnabled(syntax: String) -> Bool {
        !syntax.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
