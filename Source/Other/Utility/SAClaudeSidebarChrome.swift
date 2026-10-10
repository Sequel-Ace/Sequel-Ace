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
