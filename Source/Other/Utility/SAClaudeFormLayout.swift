//
//  SAClaudeFormLayout.swift
//  Sequel Ace
//
//  Frames for the shared Claude form of the table and database sheets: the title and context line, right-aligned
//  labels beside a column of controls, titled sections, full-width blocks, the footer (primary right, Cancel to its
//  left, extra actions left) and the sheet's size; plus the text helpers the forms share. Pure geometry, shared with
//  Unit Tests. Coordinates are AppKit's (origin bottom-left).
//  Spec: docs/superpowers/specs/2026-10-15-claude-table-sheets-design.md.
//

import AppKit

enum SAClaudeFormLayout {
    // Sheet.
    static let sideMargin: CGFloat = 20
    static let topMargin: CGFloat = 18
    static let bottomMargin: CGFloat = 16
    static let minimumWidth: CGFloat = 360
    static let maximumWidth: CGFloat = 560
    /// The narrowest control column the sheet widens for; beyond 560pt the labels truncate instead.
    static let minimumControlWidth: CGFloat = 200
    // Header.
    static let titleHeight: CGFloat = 18
    static let contextGap: CGFloat = 2
    static let contextHeight: CGFloat = 15
    static let headerGap: CGFloat = 16
    // Rows.
    static let rowHeight: CGFloat = 28
    static let rowGap: CGFloat = 10
    static let minimumLabelColumn: CGFloat = 64
    static let labelGap: CGFloat = 10
    static let labelHeight: CGFloat = 16
    static let fieldHeight: CGFloat = 24
    static let checkboxHeight: CGFloat = 18
    // Sections.
    static let sectionTitleHeight: CGFloat = 14
    static let sectionGapAbove: CGFloat = 14
    static let sectionGapBelow: CGFloat = 8
    // Full-width blocks.
    static let blockRadius: CGFloat = 10
    static let blockInset: CGFloat = 4
    static let blockStripHeight: CGFloat = 24
    // Footer.
    static let footerGap: CGFloat = 20
    static let footerHeight: CGFloat = 28
    static let footerItemGap: CGFloat = 8

    /// How tall a row's control is (it is centred on its row, which is at least 28pt).
    enum ControlKind: Equatable {
        case field, popUp, checkbox
        case custom(height: CGFloat)

        var height: CGFloat {
            switch self {
            case .field: return SAClaudeFormLayout.fieldHeight
            case .popUp: return SAClaudeFormLayout.rowHeight
            case .checkbox: return SAClaudeFormLayout.checkboxHeight
            case .custom(let height): return height
            }
        }
    }

    enum Item: Equatable {
        /// A labelled row; `labelWidth` is the label's measured text width.
        case row(labelWidth: CGFloat, control: ControlKind)
        /// A control in the control column without a label (checkbox rows, the BIT operators).
        case control(ControlKind)
        /// A control spanning the label and control columns (a search field, a note, the BIT grid).
        case wide(ControlKind)
        /// A section title (or the index sheet's Advanced disclosure).
        case section
        /// A full-width block: a rounded surface around a scroll view; `grows` takes the sheet's extra height;
        /// `stripHeight` > 0 reserves a strip at its bottom (the index sheet's +/−).
        case block(minHeight: CGFloat, grows: Bool, stripHeight: CGFloat)
    }

    struct FooterItem: Equatable {
        var width: CGFloat
        var height: CGFloat
        /// The classic bezel's side margin inside a XIB push button's frame (0 for anything else).
        var inset: CGFloat = 0
    }

    struct Spec: Equatable {
        var items: [Item]
        var hasContext: Bool
        var footerLeading: [FooterItem] = []
        /// Left to right; the last is the primary (Return) button.
        var footerTrailing: [FooterItem] = []
        /// The sheet's content size now.
        var currentSize: NSSize
        /// The recipe's width, when it gives one.
        var fixedWidth: CGFloat? = nil
        var resizable = false
    }

    struct ItemFrame: Equatable {
        var label: NSRect? = nil
        /// The control (row, wide, section title) or the block's scroll view.
        var control: NSRect
        /// A block's rounded surface.
        var surface: NSRect? = nil
        /// A block's bottom strip.
        var strip: NSRect? = nil
    }

    struct Frames: Equatable {
        var size: NSSize
        /// The width the form needs and its natural height: the min size of a resizable sheet.
        var minimumSize: NSSize
        /// A resizable sheet with a growing block: its height may exceed the natural one.
        var heightIsFlexible: Bool
        var labelColumnWidth: CGFloat
        /// The labels are wider than the column (the sheet is at 560pt): they truncate with a tooltip.
        var truncatesLabels: Bool
        var title: NSRect
        var context: NSRect?
        var items: [ItemFrame]
        var footerLeading: [NSRect]
        var footerTrailing: [NSRect]
    }

    static func labelColumnWidth(_ widths: [CGFloat]) -> CGFloat {
        max(minimumLabelColumn, ceil(widths.max() ?? 0))
    }

    static func height(of item: Item) -> CGFloat {
        switch item {
        case .row(_, let control), .control(let control), .wide(let control): return max(rowHeight, control.height)
        case .section: return sectionTitleHeight
        case .block(let minHeight, _, _): return minHeight
        }
    }

    /// The space above `item` when it follows `previous` (none above the first).
    static func gap(before item: Item, after previous: Item?) -> CGFloat {
        guard let previous else { return 0 }
        if case .section = item { return sectionGapAbove }
        if case .section = previous { return sectionGapBelow }
        return rowGap
    }

    /// The sheet width the footer needs (margins included).
    static func footerWidth(leading: [FooterItem], trailing: [FooterItem]) -> CGFloat {
        func run(_ items: [FooterItem]) -> CGFloat {
            items.isEmpty ? 0 : items.reduce(0) { $0 + $1.width - 2 * $1.inset } + CGFloat(items.count - 1) * footerItemGap
        }
        let between: CGFloat = leading.isEmpty || trailing.isEmpty ? 0 : 2 * footerItemGap
        return 2 * sideMargin + run(leading) + between + run(trailing)
    }

    /// Footer frames in a sheet `width` wide: leading items from the left margin, trailing ones ending on the right
    /// margin (drawn edges, `inset` inside each frame), each centred on the 28pt footer row.
    static func footerFrames(width: CGFloat, leading: [FooterItem], trailing: [FooterItem]) -> (leading: [NSRect], trailing: [NSRect]) {
        func y(_ item: FooterItem) -> CGFloat { bottomMargin + ((footerHeight - item.height) / 2).rounded(.down) }
        var left: [NSRect] = []
        var x = sideMargin
        for item in leading {
            let frame = NSRect(x: x - item.inset, y: y(item), width: item.width, height: item.height)
            left.append(frame)
            x = frame.maxX - item.inset + footerItemGap
        }
        var right: [NSRect] = []
        x = width - sideMargin
        for item in trailing.reversed() {
            let frame = NSRect(x: x + item.inset - item.width, y: y(item), width: item.width, height: item.height)
            right.insert(frame, at: 0)
            x = frame.minX + item.inset - footerItemGap
        }
        return (left, right)
    }

    static func frames(_ s: Spec) -> Frames {
        // Width: the label column, the control column's minimum and the footer; at most 560pt, then labels truncate.
        let labelWidths = s.items.compactMap { item -> CGFloat? in
            if case .row(let width, _) = item { return width } else { return nil }
        }
        var labelColumn = labelColumnWidth(labelWidths)
        let formNeed = labelWidths.isEmpty
            ? 2 * sideMargin + minimumControlWidth
            : 2 * sideMargin + labelColumn + labelGap + minimumControlWidth
        let footerNeed = footerWidth(leading: s.footerLeading, trailing: s.footerTrailing)
        let minWidth = min(max(minimumWidth, formNeed, footerNeed), maximumWidth)
        let width = max(minWidth, s.fixedWidth ?? s.currentSize.width)
        // Labels truncate only when the sheet cannot widen further (it is at 560pt or more) and they still don't fit.
        let availableLabelColumn = max(minimumLabelColumn, width - 2 * sideMargin - labelGap - minimumControlWidth)
        let truncates = width >= maximumWidth && labelColumn > availableLabelColumn
        if truncates { labelColumn = availableLabelColumn }

        // Height: the content's, or (resizable with a growing block) at least the current one.
        var natural = topMargin + titleHeight + (s.hasContext ? contextGap + contextHeight : 0)
        if !s.items.isEmpty { natural += headerGap }
        var previous: Item?
        for item in s.items {
            natural += gap(before: item, after: previous) + height(of: item)
            previous = item
        }
        natural += footerGap + footerHeight + bottomMargin
        let growers = s.items.indices.filter { index in
            if case .block(_, true, _) = s.items[index] { return true } else { return false }
        }
        let flexible = s.resizable && !growers.isEmpty
        let sheetHeight = flexible ? max(natural, s.currentSize.height) : natural
        let extra = sheetHeight - natural
        let share = growers.isEmpty ? 0 : (extra / CGFloat(growers.count)).rounded(.down)

        // Header, top down.
        let contentWidth = width - 2 * sideMargin
        var cursor = sheetHeight - topMargin
        let title = NSRect(x: sideMargin, y: cursor - titleHeight, width: contentWidth, height: titleHeight)
        cursor = title.minY
        var context: NSRect?
        if s.hasContext {
            cursor -= contextGap
            context = NSRect(x: sideMargin, y: cursor - contextHeight, width: contentWidth, height: contextHeight)
            cursor -= contextHeight
        }
        if !s.items.isEmpty { cursor -= headerGap }

        // Items, top down.
        let controlX = sideMargin + labelColumn + labelGap
        let controlWidth = max(0, width - sideMargin - controlX)
        var frames: [ItemFrame] = []
        previous = nil
        for (index, item) in s.items.enumerated() {
            cursor -= gap(before: item, after: previous)
            previous = item
            var h = height(of: item)
            if growers.contains(index) { h += index == growers.last ? extra - share * CGFloat(growers.count - 1) : share }
            let slot = NSRect(x: sideMargin, y: cursor - h, width: contentWidth, height: h)
            cursor = slot.minY
            func centred(_ kind: ControlKind, x: CGFloat, width: CGFloat) -> NSRect {
                NSRect(x: x, y: slot.minY + ((slot.height - kind.height) / 2).rounded(.down), width: width, height: kind.height)
            }
            switch item {
            case .row(_, let kind):
                let control = centred(kind, x: controlX, width: controlWidth)
                let label = NSRect(x: sideMargin, y: (control.midY - labelHeight / 2).rounded(.down), width: labelColumn, height: labelHeight)
                frames.append(ItemFrame(label: label, control: control))
            case .control(let kind):
                frames.append(ItemFrame(control: centred(kind, x: controlX, width: controlWidth)))
            case .wide(let kind):
                frames.append(ItemFrame(control: centred(kind, x: sideMargin, width: contentWidth)))
            case .section:
                frames.append(ItemFrame(control: slot))
            case .block(_, _, let stripHeight):
                let strip = stripHeight > 0 ? NSRect(x: slot.minX, y: slot.minY, width: slot.width, height: stripHeight) : nil
                let bottom = strip.map { $0.maxY + 1 } ?? slot.minY + blockInset
                let inner = NSRect(x: slot.minX + blockInset, y: bottom, width: max(0, slot.width - 2 * blockInset),
                                   height: max(0, slot.maxY - blockInset - bottom))
                frames.append(ItemFrame(control: inner, surface: slot, strip: strip))
            }
        }

        let footer = footerFrames(width: width, leading: s.footerLeading, trailing: s.footerTrailing)
        return Frames(size: NSSize(width: width, height: sheetHeight), minimumSize: NSSize(width: minWidth, height: natural),
                      heightIsFlexible: flexible, labelColumnWidth: labelColumn, truncatesLabels: truncates,
                      title: title, context: context, items: frames,
                      footerLeading: footer.leading, footerTrailing: footer.trailing)
    }
}

/// Text the forms show, derived from the XIB's own strings.
enum SAClaudeFormText {

    /// A XIB row label as the form shows it: one trailing colon dropped ("Database Name:" → "Database Name"),
    /// unless that would leave nothing.
    static func rowLabel(_ text: String) -> String {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let last = trimmed.last, last == ":" || last == "：" {
            let without = String(trimmed.dropLast()).trimmingCharacters(in: .whitespaces)
            if !without.isEmpty { trimmed = without }
        }
        return trimmed
    }

    /// The non-empty parts joined with " · " (a context line from several facts); nil when there are none.
    static func joined(_ parts: [String?]) -> String? {
        let kept = parts.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return kept.isEmpty ? nil : kept.joined(separator: " · ")
    }
}
