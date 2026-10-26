//
//  SAClaudeFilterChrome.swift
//  Sequel Ace
//
//  The Content filter bar's Claude look as numbers and colours: control
//  sizes, the field and drop-zone fills, and where a pill's title and a
//  checkbox's square go. Shared with the unit tests.
//

import AppKit

enum SAClaudeFilterChrome {
    static let controlHeight: CGFloat = 24
    static let rowHeight: CGFloat = 32
    static let checkboxSize: CGFloat = 14
    static let checkboxRadius: CGFloat = 4
    static let selectorWidth: CGFloat = 14
    static let pillPadding: CGFloat = 9

    static func fieldFill(text: NSColor, background: NSColor) -> NSColor {
        SAClaudeEditorChrome.derivedColour(text: text, background: background, ratio: 0.035)
    }

    /// The Table Info cards' fill: the theme background lifted a little towards the text, quieter than a field.
    static let cardFillRatio: CGFloat = 0.025
    static func cardFill(text: NSColor, background: NSColor) -> NSColor {
        SAClaudeEditorChrome.derivedColour(text: text, background: background, ratio: cardFillRatio)
    }

    /// How far the idle drop-zone outline sits from the background towards the text; brighter than the
    /// palette hairline (0.08), which was invisible in dark mode.
    static let dropStrokeRatio: CGFloat = 0.30

    static func dropStroke(text: NSColor, background: NSColor) -> NSColor {
        SAClaudeEditorChrome.derivedColour(text: text, background: background, ratio: dropStrokeRatio)
    }

    static func dropHoverFill(background: NSColor) -> NSColor {
        SAClaudeEditorChrome.derivedColour(text: SAClaudeStatusChrome.clay, background: background, ratio: 0.12)
    }

    static func controlFrame(in cellFrame: NSRect) -> NSRect {
        NSRect(x: cellFrame.minX, y: (cellFrame.midY - controlHeight / 2).rounded(), width: cellFrame.width, height: controlHeight)
    }

    static func pillTitleRect(in pillFrame: NSRect) -> NSRect {
        let minX = pillFrame.minX + pillPadding
        let maxX = pillFrame.maxX - selectorWidth - 4
        return NSRect(x: minX, y: pillFrame.minY, width: max(0, maxX - minX), height: pillFrame.height)
    }

    static func checkboxRect(in cellFrame: NSRect) -> NSRect {
        NSRect(x: cellFrame.minX, y: (cellFrame.midY - checkboxSize / 2).rounded(), width: checkboxSize, height: checkboxSize)
    }
}

/// How a Claude checkbox or radio title is measured, in the attributes the cells draw it with. Shared with the unit tests.
enum SAClaudeToggleTitleMetrics {
    /// The font every Claude checkbox / radio title is drawn in, whatever the cell's own font (a caller may set a
    /// smaller one: the "Delete rows" alert's 11pt suppression checkbox).
    static let font = NSFont.systemFont(ofSize: 12)
    static var attributes: [NSAttributedString.Key: Any] { [.font: font] }
    /// From the box (or circle) to the title.
    static let gap: CGFloat = 6
    /// Spare width so a measured title never truncates by a rounding hair.
    static let slack: CGFloat = 2

    /// The title's lines (a title may hold explicit line breaks).
    static func lines(of title: String) -> [String] {
        title.components(separatedBy: .newlines)
    }

    /// The width of the widest line, measured line by line.
    static func widestLineWidth(_ title: String) -> CGFloat {
        lines(of: title).map { ceil(NSAttributedString(string: $0, attributes: attributes).size().width) }.max() ?? 0
    }

    /// The size a Claude checkbox or radio cell draws: its 14pt mark, then the gap, the widest title line and the slack
    /// (the cell's own font and AppKit's native mark size would under-measure it). The height is AppKit's, at least the
    /// mark's, and for a title of several lines at least those lines' height, so rows keep their vertical layout.
    static func cellSize(title: String, drawsTitle: Bool, nativeHeight: CGFloat) -> NSSize {
        var width = SAClaudeFilterChrome.checkboxSize
        var height = max(nativeHeight, SAClaudeFilterChrome.checkboxSize)
        if drawsTitle, !title.isEmpty {
            width += gap + widestLineWidth(title) + slack
            if lines(of: title).count > 1 { height = max(height, wrappedTitleHeight(title, cellWidth: width)) }
        }
        return NSSize(width: width, height: height)
    }

    /// The height of a title wrapped on word boundaries to fit a cell `cellWidth` wide (beside its 14pt mark and the
    /// gap). One line's height when the title fits on one line.
    static func wrappedTitleHeight(_ title: String, cellWidth: CGFloat) -> CGFloat {
        let width = max(1, cellWidth - SAClaudeFilterChrome.checkboxSize - gap - slack)
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byWordWrapping
        let bounds = NSAttributedString(string: title, attributes: [.font: font, .paragraphStyle: style])
            .boundingRect(with: NSSize(width: width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin])
        return ceil(bounds.height)
    }

    /// One line of a title.
    static var lineHeight: CGFloat { wrappedTitleHeight("Ag", cellWidth: 10_000) }
}
