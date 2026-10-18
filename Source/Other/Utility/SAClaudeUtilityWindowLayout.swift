//
//  SAClaudeUtilityWindowLayout.swift
//  Sequel Ace
//
//  The pure geometry the utility windows' Claude look shares (spec 2026-10-18-claude-utility-windows-design.md, C and
//  D): a grid of checkboxes inside a titled card (and the reading order of a XIB's checkboxes), a card's padding, label +
//  field rows inside a card. Rects are in non-flipped coordinates (the first row at the top). Nothing here touches a
//  view; the stylers apply the frames. Each window's own geometry lives with it (SAClaudeUserManagerLayout.swift).
//  Shared with the Unit Tests target.
//

import AppKit

// MARK: - Checkbox grid

/// Checkboxes in columns inside a card, filled column by column (the first column top to bottom, then the next), so
/// reading down each column keeps the controls' own order.
enum SAClaudeCheckboxGrid {
    static let rowHeight: CGFloat = 18
    static let rowPitch: CGFloat = 20
    static let columnGap: CGFloat = 10
    static let maxColumns = 2

    /// The width of each of `columns` columns across `width`.
    static func columnWidth(columns: Int, width: CGFloat) -> CGFloat {
        let count = CGFloat(max(1, columns))
        return max(0, ((width - columnGap * (count - 1)) / count).rounded(.down))
    }

    /// The most columns (up to `maxColumns`, never more than there are items) in which every item fits whole; 1 when
    /// even two would cut a title.
    static func columnCount(itemWidths: [CGFloat], width: CGFloat, maxColumns: Int = maxColumns) -> Int {
        guard let widest = itemWidths.max() else { return 1 }
        var columns = min(maxColumns, itemWidths.count)
        while columns > 1 {
            if widest <= columnWidth(columns: columns, width: width) { return columns }
            columns -= 1
        }
        return 1
    }

    static func rows(count: Int, columns: Int) -> Int {
        guard count > 0 else { return 0 }
        let columns = max(1, columns)
        return (count + columns - 1) / columns
    }

    /// The height the grid takes: its rows at `rowPitch`, the last one `rowHeight` tall.
    static func height(count: Int, columns: Int) -> CGFloat {
        let rows = rows(count: count, columns: columns)
        return rows == 0 ? 0 : CGFloat(rows - 1) * rowPitch + rowHeight
    }

    /// How far apart (in x) two checkboxes may sit and still count as one column of a XIB.
    static let columnTolerance: CGFloat = 4

    /// The reading order of checkboxes laid out in columns (a XIB's): column by column from the left, each top to bottom.
    /// Frames whose left edges lie within `columnTolerance` of a column's first one belong to that column, so a column
    /// nudged by a point or two stays one column. Returns indexes into `frames`.
    static func readingOrder(of frames: [NSRect], tolerance: CGFloat = columnTolerance) -> [Int] {
        var columns: [(x: CGFloat, members: [Int])] = []
        for index in frames.indices.sorted(by: { frames[$0].minX < frames[$1].minX }) {
            if let last = columns.indices.last, frames[index].minX - columns[last].x <= tolerance {
                columns[last].members.append(index)
            } else {
                columns.append((frames[index].minX, [index]))
            }
        }
        return columns.flatMap { column in column.members.sorted { frames[$0].midY > frames[$1].midY } }
    }

    /// One frame per item, in item order, in `rect` from its top: column-major, each as wide as its column.
    static func frames(count: Int, columns: Int, in rect: NSRect) -> [NSRect] {
        let rows = rows(count: count, columns: columns)
        guard rows > 0 else { return [] }
        let columns = max(1, columns)
        let width = columnWidth(columns: columns, width: rect.width)
        return (0..<count).map { index in
            let column = index / rows
            let row = index % rows
            return NSRect(x: rect.minX + CGFloat(column) * (width + columnGap),
                          y: rect.maxY - CGFloat(row) * rowPitch - rowHeight,
                          width: width, height: rowHeight)
        }
    }
}

// MARK: - Cards

/// A titled card (an NSBox drawn by `SAClaudeSheetTitledBox`) and the padding inside it.
enum SAClaudeCardLayout {
    static let horizontalPadding: CGFloat = 12
    static let verticalPadding: CGFloat = 12
    /// Between cards stacked in a column, and between card columns.
    static let spacing: CGFloat = 12

    /// What the box adds around its content frame: the title above, the hairline around (measured from the box).
    struct Chrome: Equatable {
        var top: CGFloat
        var bottom: CGFloat
        var left: CGFloat
        var right: CGFloat

        static let zero = Chrome(top: 0, bottom: 0, left: 0, right: 0)
        var height: CGFloat { top + bottom }
        var width: CGFloat { left + right }
    }

    /// The content frame of a card whose whole box (title included) fills `outer`.
    static func contentFrame(outer: NSRect, chrome: Chrome) -> NSRect {
        NSRect(x: outer.minX + chrome.left, y: outer.minY + chrome.bottom,
               width: max(0, outer.width - chrome.width), height: max(0, outer.height - chrome.height))
    }

    /// The grid area inside a card's content.
    static func inset(_ content: NSRect) -> NSRect {
        content.insetBy(dx: horizontalPadding, dy: verticalPadding)
    }
}

/// Label + field rows inside a card: right-aligned labels in one column, fields filling the rest.
enum SAClaudeFormCardLayout {
    static let fieldHeight: CGFloat = 24
    static let rowGap: CGFloat = 10
    static let labelGap: CGFloat = 10

    struct Row: Equatable {
        var label: NSRect
        var field: NSRect
    }

    static func contentHeight(rows: Int) -> CGFloat {
        guard rows > 0 else { return 2 * SAClaudeCardLayout.verticalPadding }
        return 2 * SAClaudeCardLayout.verticalPadding + CGFloat(rows) * fieldHeight + CGFloat(rows - 1) * rowGap
    }

    /// Rows in a card content `width` wide (content-local, from the top); each label `labelHeight` tall, centred on its field.
    static func rows(count: Int, labelWidth: CGFloat, labelHeight: CGFloat, width: CGFloat) -> [Row] {
        let height = contentHeight(rows: count)
        let x = SAClaudeCardLayout.horizontalPadding
        let fieldX = x + labelWidth + labelGap
        let fieldWidth = max(0, width - SAClaudeCardLayout.horizontalPadding - fieldX)
        return (0..<count).map { index in
            let fieldY = height - SAClaudeCardLayout.verticalPadding - fieldHeight - CGFloat(index) * (fieldHeight + rowGap)
            let field = NSRect(x: fieldX, y: fieldY, width: fieldWidth, height: fieldHeight)
            let label = NSRect(x: x, y: (field.midY - labelHeight / 2).rounded(), width: labelWidth, height: labelHeight)
            return Row(label: label, field: field)
        }
    }
}
