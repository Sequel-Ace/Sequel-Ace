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

    /// x positions and widths: search field from the left, buttons right-aligned in order; the search field shrinks
    /// (not below its minimum) so it never overlaps the buttons.
    static func layout(totalWidth: CGFloat, buttonWidths: [CGFloat]) -> (search: (x: CGFloat, width: CGFloat), buttons: [(x: CGFloat, width: CGFloat)]) {
        var buttons: [(x: CGFloat, width: CGFloat)] = []
        var right = totalWidth - sidePadding
        for width in buttonWidths.reversed() {
            buttons.insert((x: right - width, width: width), at: 0)
            right -= width + gap
        }
        // With no buttons the search field may run up to the right padding.
        let firstButtonX = buttons.first?.x ?? totalWidth - sidePadding + gap
        let available = firstButtonX - gap - sidePadding
        return (search: (x: sidePadding, width: max(searchMinWidth, min(searchWidth, available))), buttons: buttons)
    }
}
