//
//  SAClaudeWindowTabBarLayout.swift
//  Sequel Ace
//
//  Frames and reorder steps for the Claude window tab bar (chips, scroll area, "+" button).
//  Pure geometry and reorder maths. Shared with the Unit Tests target.
//

import AppKit

enum SAClaudeWindowTabBarLayout {
    static let height: CGFloat = 36
    static let chipHeight: CGFloat = 28
    static let maxChipWidth: CGFloat = 220
    static let minChipWidth: CGFloat = 100
    static let gap: CGFloat = 6
    static let sideInset: CGFloat = 8
    static let plusSize: CGFloat = 24
    static let plusGap: CGFloat = 8

    struct Frames: Equatable {
        var scrollArea: NSRect        // in bar coordinates
        var chips: [NSRect]           // in the scroll content's coordinates (origin at the scroll area's left)
        var contentWidth: CGFloat
        var scrolls: Bool
        var plus: NSRect              // in bar coordinates
    }

    /// Remove `id`, then insert it at `index`.
    struct Step: Equatable { var id: Int; var index: Int }

    /// Chips sized to their content: each preferred width clamped to [min, max], packed from the left of the
    /// scrolling area. When they don't fit, every chip shrinks by the same ratio, though not below the minimum;
    /// if they still don't fit at that size the strip scrolls. "+" follows the last chip, or stays at the right
    /// edge (where the scrolling area always leaves room for it) while the strip scrolls.
    static func frames(preferredWidths: [CGFloat], barWidth: CGFloat) -> Frames {
        var plus = NSRect(x: barWidth - sideInset - plusSize, y: ((height - plusSize) / 2).rounded(.down), width: plusSize, height: plusSize)
        let scrollArea = NSRect(x: sideInset, y: 0, width: max(0, barWidth - 2 * sideInset - plusSize - plusGap), height: height)
        guard !preferredWidths.isEmpty else { return Frames(scrollArea: scrollArea, chips: [], contentWidth: 0, scrolls: false, plus: plus) }
        let gaps = gap * CGFloat(preferredWidths.count - 1)
        let available = scrollArea.width
        var widths = preferredWidths.map { min(maxChipWidth, max(minChipWidth, $0)) }
        let total = widths.reduce(0, +)
        var scrolls = false
        if total + gaps > available {
            let ratio = max(0, available - gaps) / total
            widths = widths.map { max(minChipWidth, ($0 * ratio).rounded(.down)) }
            scrolls = widths.reduce(0, +) + gaps > available
        }
        let contentWidth = widths.reduce(0, +) + gaps
        if !scrolls { plus.origin.x = scrollArea.minX + contentWidth + gap }
        let y = ((height - chipHeight) / 2).rounded(.down)
        var x: CGFloat = 0
        let chips = widths.map { width -> NSRect in
            defer { x += width + gap }
            return NSRect(x: x, y: y, width: width, height: chipHeight)
        }
        return Frames(scrollArea: scrollArea, chips: chips, contentWidth: contentWidth, scrolls: scrolls, plus: plus)
    }

    /// The insertion index (0...chips.count) for a drag at content x: the number of chips whose midX is left of x.
    static func insertionIndex(x: CGFloat, chips: [NSRect]) -> Int {
        chips.filter { $0.midX < x }.count
    }

    /// The order after moving `id` to the gap before index `insertion` (an index in the current order, clamped to
    /// 0...order.count); unchanged when the move is a no-op.
    static func target(order: [Int], moving id: Int, toInsertion insertion: Int) -> [Int] {
        let insertion = min(max(0, insertion), order.count)
        guard let from = order.firstIndex(of: id), insertion != from, insertion != from + 1 else { return order }
        var result = order
        result.remove(at: from)
        result.insert(id, at: insertion > from ? insertion - 1 : insertion)
        return result
    }

    /// Steps that turn `order` into `target` without ever moving `selected`.
    static func reorderSteps(order: [Int], target: [Int], selected: Int) -> [Step] {
        guard order != target else { return [] }
        func applied(_ step: Step, to list: [Int]) -> [Int] {
            var working = list
            working.removeAll { $0 == step.id }
            working.insert(step.id, at: step.index)
            return working
        }
        // One step when a single non-selected window moved. Scanning from the end makes the tie between two equally valid
        // single steps (a swap of neighbours) resolve to the later tab being moved up, as a drag from the right does.
        for id in order.reversed() where id != selected {
            guard let index = target.firstIndex(of: id) else { continue }
            let step = Step(id: id, index: index)
            if applied(step, to: order) == target { return [step] }
        }
        // Otherwise: every non-selected window to the end in target order, then the ones before the selected one back to the front.
        var steps: [Step] = []
        var working = order
        for id in target where id != selected {
            let step = Step(id: id, index: order.count - 1)
            working = applied(step, to: working)
            steps.append(step)
        }
        let selectedTarget = target.firstIndex(of: selected) ?? 0
        for k in 0..<selectedTarget {
            let step = Step(id: target[k], index: k)
            working = applied(step, to: working)
            steps.append(step)
        }
        return steps
    }
}
