//
//  SAClaudeServerVariablesModel.swift
//  Sequel Ace
//
//  The logic behind the Server Variables sheet in the Claude look (spec 2026-10-18-claude-utility-windows-design.md,
//  section B): the search hits the grid and the full-value strip highlight (the same matching as the controller's
//  filter), what the strip shows and copies for the selection, the rows that keep a selection by variable name when
//  the filter or a refresh reloads the table, and the sheet's frames. Pure; shared with the Unit Tests target.
//

import Foundation

/// One row of `SHOW VARIABLES`.
struct SAClaudeServerVariable: Equatable {
    let name: String
    let value: String
}

// MARK: - Search

enum SAClaudeServerVariablesSearch {

    /// The filter as `SPServerVariablesController` applies it: lowercased, whitespace and newlines trimmed.
    static func needle(_ filter: String) -> String {
        filter.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Every non-overlapping, case-insensitive hit of the filter in `text` (UTF-16 ranges); none for an empty filter.
    /// The controller keeps a row when its name or value contains the filter this way, so a kept row always shows a hit.
    static func ranges(of filter: String, in text: String) -> [NSRange] {
        let needle = needle(filter)
        guard !needle.isEmpty else { return [] }
        let string = text as NSString
        var found: [NSRange] = []
        var searchRange = NSRange(location: 0, length: string.length)
        while searchRange.length > 0 {
            let hit = string.range(of: needle, options: .caseInsensitive, range: searchRange)
            guard hit.location != NSNotFound, hit.length > 0 else { break }
            found.append(hit)
            let next = NSMaxRange(hit)
            searchRange = NSRange(location: next, length: string.length - next)
        }
        return found
    }

    /// A value as one grid line: line breaks and tabs become spaces, one UTF-16 unit for one, so search ranges of the
    /// value still fit the line.
    static func singleLine(_ text: String) -> String {
        guard text.rangeOfCharacter(from: lineBreaks) != nil else { return text }
        let units = text.utf16.map { lineBreakUnits.contains($0) ? 0x20 : $0 }
        return String(utf16CodeUnits: units, count: units.count)
    }

    /// How many UTF-16 units of context an excerpt keeps before its first hit.
    static let excerptLead = 16

    /// `line` from `excerptLead` units before the first hit, led by "…", with `ranges` moved to match: for a grid cell
    /// whose first hit lies past what its column shows (a long value such as `optimizer_switch`). The cut starts on a
    /// whole character; a line whose first hit is already near the start is returned as it is.
    static func excerpt(_ line: String, ranges: [NSRange]) -> (text: String, ranges: [NSRange]) {
        guard let first = ranges.min(by: { $0.location < $1.location }), first.location > excerptLead else { return (line, ranges) }
        let string = line as NSString
        let start = string.rangeOfComposedCharacterSequence(at: first.location - excerptLead).location
        let shift = 1 - start
        let moved = ranges.compactMap { range -> NSRange? in
            let lower = max(range.location, start)
            let upper = NSMaxRange(range)
            guard upper > lower else { return nil }
            return NSRange(location: lower + shift, length: upper - lower)
        }
        return ("…" + string.substring(from: start), moved)
    }

    private static let lineBreaks = CharacterSet(charactersIn: "\n\r\t\u{2028}\u{2029}")
    private static let lineBreakUnits: Set<UInt16> = [0x0A, 0x0D, 0x09, 0x2028, 0x2029]
}

// MARK: - Detail strip

/// What the strip under the list shows for the selected rows (in list order).
struct SAClaudeServerVariablesDetail: Equatable {
    let variables: [SAClaudeServerVariable]
    /// The selected variable's name, or nil when several are selected (the view titles them by count).
    let name: String?
    /// The full value, or one `name = value` line per variable when several are selected.
    let text: String
    /// What Copy puts on the pasteboard: the value itself, or the controller's Copy format (`name = value\n` each).
    let copyText: String
    let nameRanges: [NSRange]
    let textRanges: [NSRange]

    var count: Int { variables.count }
    /// A single variable whose value is the empty string (many server variables are).
    var isEmptyValue: Bool { name != nil && text.isEmpty }

    /// Nil when nothing is selected.
    static func make(selected: [SAClaudeServerVariable], filter: String) -> SAClaudeServerVariablesDetail? {
        guard let first = selected.first else { return nil }
        if selected.count == 1 {
            return SAClaudeServerVariablesDetail(variables: selected, name: first.name, text: first.value, copyText: first.value,
                                                 nameRanges: SAClaudeServerVariablesSearch.ranges(of: filter, in: first.name),
                                                 textRanges: SAClaudeServerVariablesSearch.ranges(of: filter, in: first.value))
        }
        let lines = selected.map { "\($0.name) = \($0.value)" }
        let text = lines.joined(separator: "\n")
        return SAClaudeServerVariablesDetail(variables: selected, name: nil, text: text, copyText: lines.map { $0 + "\n" }.joined(),
                                             nameRanges: [], textRanges: SAClaudeServerVariablesSearch.ranges(of: filter, in: text))
    }
}

// MARK: - Selection

enum SAClaudeServerVariablesSelection {

    /// The rows of `visible` (names in list order) whose variable is one of `names`. The controller reloads the table
    /// after every filter keystroke and refresh without touching the selection, which would otherwise stay on the same
    /// row indexes — other variables.
    static func rows(selecting names: [String], in visible: [String]) -> IndexSet {
        guard !names.isEmpty else { return IndexSet() }
        let wanted = Set(names)
        var rows = IndexSet()
        for (row, name) in visible.enumerated() where wanted.contains(name) { rows.insert(row) }
        return rows
    }
}

// MARK: - Layout

/// The sheet's frames in its content view (not flipped): the header row (title, "N of M", search), the list edge to
/// edge between two hairlines, the full-value strip, and the footer (Save As… left, Close right).
enum SAClaudeServerVariablesLayout {
    static let margin: CGFloat = 16
    static let headerHeight: CGFloat = 52
    static let searchHeight: CGFloat = SAClaudeFormLayout.fieldHeight
    static let searchMinWidth: CGFloat = 180
    static let searchMaxWidth: CGFloat = 260
    static let countWidth: CGFloat = 96
    static let titleHeight: CGFloat = 18
    static let countHeight: CGFloat = 15
    static let gap: CGFloat = 8
    static let footerHeight: CGFloat = SAClaudeFormLayout.footerHeight
    /// Between the strip and the footer.
    static let footerGap: CGFloat = 4
    static let detailMinHeight: CGFloat = 150
    static let detailMaxHeight: CGFloat = 240
    static let detailShare: CGFloat = 0.3

    /// The smallest content size: the strip at its minimum and a list of five or so rows.
    static let minimumSize = NSSize(width: 520, height: 440)
    /// The size the sheet opens at the first time when its saved size is below the minimum (the XIB's is 433×341).
    static let preferredSize = NSSize(width: 680, height: 560)

    struct Frames: Equatable {
        var title: NSRect
        var count: NSRect
        var search: NSRect
        var topLine: NSRect
        var table: NSRect
        var bottomLine: NSRect
        var detail: NSRect
        var save: NSRect
        var close: NSRect
    }

    /// The strip takes 30% of the height, between 150 and 240pt.
    static func detailHeight(forHeight height: CGFloat) -> CGFloat {
        min(detailMaxHeight, max(detailMinHeight, (height * detailShare).rounded()))
    }

    /// `saveWidth` / `closeWidth` are the push buttons' frame widths, `buttonInset` the classic side margin inside them
    /// (the drawn buttons line up with the margin).
    static func frames(in bounds: NSRect, saveWidth: CGFloat, closeWidth: CGFloat, buttonInset: CGFloat) -> Frames {
        let width = bounds.width
        let height = bounds.height
        let headerMidY = bounds.maxY - headerHeight / 2

        let searchWidth = min(searchMaxWidth, max(searchMinWidth, (width * 0.36).rounded()))
        let search = NSRect(x: bounds.maxX - margin - searchWidth, y: (headerMidY - searchHeight / 2).rounded(), width: searchWidth, height: searchHeight)
        let count = NSRect(x: search.minX - gap - countWidth, y: (headerMidY - countHeight / 2).rounded(), width: countWidth, height: countHeight)
        let title = NSRect(x: bounds.minX + margin, y: (headerMidY - titleHeight / 2).rounded(),
                           width: max(0, count.minX - gap - (bounds.minX + margin)), height: titleHeight)
        let topLine = NSRect(x: bounds.minX, y: bounds.maxY - headerHeight - 1, width: width, height: 1)

        let footerY = bounds.minY + margin
        let save = NSRect(x: bounds.minX + margin - buttonInset, y: footerY, width: saveWidth, height: footerHeight)
        let close = NSRect(x: bounds.maxX - margin + buttonInset - closeWidth, y: footerY, width: closeWidth, height: footerHeight)

        let detailY = footerY + footerHeight + footerGap
        let detail = NSRect(x: bounds.minX, y: detailY, width: width, height: detailHeight(forHeight: height))
        let bottomLine = NSRect(x: bounds.minX, y: detail.maxY, width: width, height: 1)
        let table = NSRect(x: bounds.minX, y: bottomLine.maxY, width: width, height: max(0, topLine.minY - bottomLine.maxY))
        return Frames(title: title, count: count, search: search, topLine: topLine, table: table, bottomLine: bottomLine,
                      detail: detail, save: save, close: close)
    }
}
