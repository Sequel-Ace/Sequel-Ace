//
//  SAClaudeSidebarChrome.swift
//  Sequel Ace
//
//  Drawing and formatting helpers for the Claude-style left navigation:
//  section headers, info-panel rows, bottom-bar buttons. Pure AppKit, shared
//  with the Unit Tests target.
//

import AppKit

@objc final class SAClaudeSidebarChrome: NSObject {

    /// Draws a section header ("Tables and views") in a row, in the header
    /// style, aligned with the icons below it. Call inside a flipped view.
    @objc(drawHeader:inRowRect:)
    static func drawHeader(_ title: String, inRowRect rowRect: NSRect) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: SAClaudeStyle.headerFont,
            .foregroundColor: SAClaudeStyle.textMuted,
            .paragraphStyle: paragraph,
        ]
        let text = NSAttributedString(string: title, attributes: attributes)
        let frame = SAClaudeSidebarGeometry.headerTextFrame(in: rowRect, textHeight: ceil(text.size().height))
        guard frame.width > 0 else { return }
        text.draw(with: frame, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }
}

/// Formats a Table information row ("rows: ~18,402") as a muted label and a
/// right-aligned value. Pure so it can be unit-tested.
@objc final class SAClaudeInfoRow: NSObject {

    /// Splits at the first ": " and capitalises the label's first letter.
    ///
    /// - Returns: The label and value, or `nil` when there is no ": " or either side is empty.
    static func split(_ text: String) -> (label: String, value: String)? {
        guard let range = text.range(of: ": ") else { return nil }
        let label = String(text[..<range.lowerBound])
        let value = String(text[range.upperBound...])
        guard !label.isEmpty, !value.isEmpty else { return nil }
        return (label.prefix(1).uppercased() + label.dropFirst(), value)
    }

    /// The row as drawn: label muted on the left, value secondary on a right
    /// tab stop `infoRowTrailingPadding` in from `width`; text without ": " plain.
    @objc(attributedRowForText:width:)
    static func attributedRow(text: String, width: CGFloat) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        paragraph.tabStops = [NSTextTab(textAlignment: .right, location: max(0, width - SAClaudeStyle.infoRowTrailingPadding))]
        let font = SAClaudeStyle.infoFont
        guard let parts = split(text) else {
            return NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: SAClaudeStyle.textSecondary, .paragraphStyle: paragraph])
        }
        let row = NSMutableAttributedString(string: parts.label, attributes: [.font: font, .foregroundColor: SAClaudeStyle.textMuted, .paragraphStyle: paragraph])
        row.append(NSAttributedString(string: "\t" + parts.value, attributes: [.font: font, .foregroundColor: SAClaudeStyle.textSecondary, .paragraphStyle: paragraph]))
        return row
    }
}

extension SAClaudeSidebarChrome {

    /// Gives one of the sidebar's plain tables (Table information, Activities)
    /// the Claude background, no system selection and no source-list styling.
    @objc(styleSidebarTable:)
    static func styleSidebarTable(_ table: NSTableView) {
        table.style = .plain
        table.selectionHighlightStyle = .none
        table.usesAlternatingRowBackgroundColors = false
        table.gridStyleMask = []
        table.backgroundColor = SAClaudeStyle.sidebarBackground
        if let scrollView = table.enclosingScrollView {
            scrollView.drawsBackground = true
            scrollView.backgroundColor = SAClaudeStyle.sidebarBackground
        }
    }
}
