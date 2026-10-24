//
//  SAClaudeTypeInfoText.swift
//  Sequel Ace
//
//  The text and placement of the Type Info hint card beside the Structure tab's Type dropdown: the type's
//  definition as a monospaced title, its range muted, its description as prose, and the card's frame
//  next to the open pop-up. Pure AppKit so it is shared with the Unit Tests target.
//

import AppKit

enum SAClaudeTypeInfoText {

    static let titleFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold)
    static let rangeFont = NSFont.systemFont(ofSize: 11)
    static let descriptionFont = NSFont.systemFont(ofSize: 12)
    /// Distance between the pop-up and the card, and the margin kept from the screen's right edge.
    static let gap: CGFloat = 10

    /// Space after the title and before the description (which used to follow a blank line).
    private static let titleSpacing: CGFloat = 2
    private static let descriptionSpacing: CGFloat = 8

    /// `definition`, then `range` (when there is one; every line of it muted), then `description`, one
    /// paragraph each.
    static func attributedString(definition: String, range: String?, description: String,
                                 palette: SAClaudeHintCardPalette) -> NSAttributedString {
        let result = NSMutableAttributedString()
        func paragraph(spacingAfter: CGFloat = 0, spacingBefore: CGFloat = 0) -> NSParagraphStyle {
            let style = NSMutableParagraphStyle()
            style.lineBreakMode = .byWordWrapping
            style.paragraphSpacing = spacingAfter
            style.paragraphSpacingBefore = spacingBefore
            return style
        }
        result.append(NSAttributedString(string: definition + "\n", attributes: [
            .font: titleFont, .foregroundColor: palette.text, .paragraphStyle: paragraph(spacingAfter: titleSpacing),
        ]))
        if let range, !range.isEmpty {
            result.append(NSAttributedString(string: range + "\n", attributes: [
                .font: rangeFont, .foregroundColor: palette.muted, .paragraphStyle: paragraph(),
            ]))
        }
        result.append(NSAttributedString(string: description, attributes: [
            .font: descriptionFont, .foregroundColor: palette.text,
            .paragraphStyle: paragraph(spacingBefore: descriptionSpacing),
        ]))
        return result
    }

    /// The card's frame: right of the pop-up, or left of it when the right side would come within `gap`
    /// of the screen's right edge; its top level with the pop-up's top.
    static func frame(popUpFrame: NSRect, screenFrame: NSRect, size: NSSize) -> NSRect {
        let x = popUpFrame.maxX + gap + size.width > screenFrame.maxX - gap
            ? popUpFrame.minX - gap - size.width
            : popUpFrame.maxX + gap
        return NSRect(x: x, y: popUpFrame.maxY - size.height, width: size.width, height: size.height)
    }
}
