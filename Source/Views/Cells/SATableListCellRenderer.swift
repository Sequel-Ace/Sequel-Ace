//
//  SATableListCellRenderer.swift
//  Sequel Ace
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import AppKit

@objc final class SATableListCellRenderer: NSObject {

    struct Layout {
        let nameFrame: NSRect
        let commentFrame: NSRect
    }

    /// The table name has priority. A comment can use only the space after the
    /// name and its text-cell insets, never the same rectangle as the name.
    static func layout(in frame: NSRect, nameWidth: CGFloat) -> Layout {
        let availableWidth = max(0, frame.width - 5)
        let nameFrame = NSRect(
            x: frame.origin.x,
            y: frame.origin.y,
            width: min(availableWidth, ceil(max(0, nameWidth)) + 4),
            height: max(0, frame.height)
        )
        let rightEdge = frame.origin.x + availableWidth
        let commentX = min(rightEdge, nameFrame.maxX + 8)
        return Layout(
            nameFrame: nameFrame,
            commentFrame: NSRect(
                x: commentX,
                y: frame.origin.y,
                width: max(0, rightEdge - commentX),
                height: nameFrame.height
            )
        )
    }

    @objc(drawNameCell:commentCell:frame:inView:drawName:)
    static func draw(
        nameCell: NSTextFieldCell,
        commentCell: NSCell?,
        frame: NSRect,
        in view: NSView,
        drawName: (NSRect) -> Void
    ) {
        let originalValue = nameCell.attributedStringValue
        let originalLineBreakMode = nameCell.lineBreakMode
        defer {
            nameCell.lineBreakMode = originalLineBreakMode
            nameCell.attributedStringValue = originalValue
        }

        let layout = layout(in: frame, nameWidth: originalValue.size().width)
        nameCell.lineBreakMode = .byTruncatingTail
        if layout.nameFrame.width > 0 {
            drawName(layout.nameFrame)
        }

        guard let commentCell, !commentCell.stringValue.isEmpty,
              layout.commentFrame.width > 0 else { return }

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        paragraph.alignment = .left
        let comment = commentCell.stringValue
            .components(separatedBy: .newlines).joined(separator: " ")
            .replacingOccurrences(of: "\t", with: " ")
        let color: NSColor = nameCell.interiorBackgroundStyle == .emphasized
            ? .selectedControlTextColor : .secondaryLabelColor
        commentCell.font = nameCell.font
        commentCell.alignment = .left
        commentCell.lineBreakMode = .byTruncatingTail
        commentCell.usesSingleLineMode = true
        commentCell.attributedStringValue = NSAttributedString(string: comment, attributes: [
            .font: nameCell.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize),
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ])

        // AppKit may draw glyph overhang outside a text cell's nominal bounds.
        NSGraphicsContext.saveGraphicsState()
        layout.commentFrame.clip()
        commentCell.drawInterior(withFrame: layout.commentFrame, in: view)
        NSGraphicsContext.restoreGraphicsState()
    }
}
