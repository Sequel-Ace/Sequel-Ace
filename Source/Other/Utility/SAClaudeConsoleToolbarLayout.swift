//
//  SAClaudeConsoleToolbarLayout.swift
//  Sequel Ace
//
//  Pure geometry for the Query Console's top toolbar in the Claude look: the
//  search field on the left, ghost buttons right-aligned. Shared with the Unit
//  Tests target.
//

import CoreGraphics

/// Frames for the Query Console toolbar (flipped-agnostic x/width only).
struct SAClaudeConsoleToolbarLayout {
    static let height: CGFloat = 40, sidePadding: CGFloat = 10, gap: CGFloat = 4
    static let searchWidth: CGFloat = 220, searchMinWidth: CGFloat = 120, searchHeight: CGFloat = 26

    /// x positions and widths: search field from the left, buttons right-aligned in order, and the middle item (the
    /// logging note) between them. The search field shrinks (not below its minimum) so it never overlaps the buttons;
    /// with a `middleWidth` (the note's fitted width, 0 when it is empty) it also yields room for the note.
    static func layout(totalWidth: CGFloat, buttonWidths: [CGFloat], middleWidth: CGFloat = 0)
        -> (search: (x: CGFloat, width: CGFloat), middle: (x: CGFloat, width: CGFloat), buttons: [(x: CGFloat, width: CGFloat)]) {
        var buttons: [(x: CGFloat, width: CGFloat)] = []
        var right = totalWidth - sidePadding
        for width in buttonWidths.reversed() {
            buttons.insert((x: right - width, width: width), at: 0)
            right -= width + gap
        }
        // With no buttons the search field (or the middle item) may run up to the right padding.
        let firstButtonX = buttons.first?.x ?? totalWidth - sidePadding + gap
        var available = firstButtonX - gap - sidePadding
        if middleWidth > 0 { available -= middleWidth + gap }
        let search = (x: sidePadding, width: max(searchMinWidth, min(searchWidth, available)))
        let middleX = search.x + search.width + gap
        return (search: search, middle: (x: middleX, width: max(0, firstButtonX - gap - middleX)), buttons: buttons)
    }
}
