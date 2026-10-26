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

// MARK: - Footer

/// Push buttons along the bottom of a sheet or pane, right-aligned on the margin (as the User Manager's Apply and Cancel):
/// the rightmost first, each `gap` from the next as drawn. Frames carry the classic side margins inside them
/// (`buttonInset`), so the drawn buttons line up with the margin.
enum SAClaudeFooterLayout {
    static let margin: CGFloat = 18
    static let bottom: CGFloat = 12
    /// A regular push button's XIB height (its classic margins included).
    static let height: CGFloat = 32
    /// Between two buttons as drawn.
    static let gap: CGFloat = 12

    /// One frame per width, right to left from `maxX - margin`, at `y`.
    static func trailing(widths: [CGFloat], maxX: CGFloat, y: CGFloat, buttonInset: CGFloat, margin: CGFloat = margin) -> [NSRect] {
        var right = maxX - margin + buttonInset
        return widths.map { width in
            let frame = NSRect(x: right - width, y: y, width: width, height: height)
            right = frame.minX + 2 * buttonInset - gap
            return frame
        }
    }

    /// The leftmost x the drawn buttons reach (the left edge of the last frame, inside its margin).
    static func leadingEdge(of frames: [NSRect], buttonInset: CGFloat) -> CGFloat {
        (frames.map(\.minX).min() ?? 0) + buttonInset
    }
}

// MARK: - Sidebar bar

/// The bottom bar's glyph buttons under a source list, left to right from `x`, 2pt apart, centred on the bar: 28pt squares,
/// except a gear pull-down, which is as wide as its glyph and chevron need (`SAClaudeUtilityChrome.pullDownWidth`, as the
/// main window's 35pt gear) so its glyph is never cut by the chevron.
enum SAClaudeSidebarBarLayout {
    static let buttonSize: CGFloat = 28
    static let buttonGap: CGFloat = 2

    /// One frame per width, `buttonSize` tall; a width under `buttonSize` gets `buttonSize`.
    static func buttons(widths: [CGFloat], x: CGFloat, midY: CGFloat) -> [NSRect] {
        var left = x
        return widths.map { width in
            let frame = NSRect(x: left, y: (midY - buttonSize / 2).rounded(), width: max(buttonSize, ceil(width)), height: buttonSize)
            left = frame.maxX + buttonGap
            return frame
        }
    }

    /// `count` 28pt squares.
    static func buttons(count: Int, x: CGFloat, midY: CGFloat) -> [NSRect] {
        buttons(widths: Array(repeating: buttonSize, count: max(0, count)), x: x, midY: midY)
    }
}

// MARK: - Sidebar list

/// Where a Claude sidebar list puts its disclosure chevrons and where its content starts, so a list's header lines up
/// with its rows (spec 2026-10-18-claude-utility-windows-design.md, walkthrough fix 1).
enum SAClaudeSidebarListLayout {
    /// AppKit's disclosure triangle frame of a top-level row starts this far in from the list's edge (measured on macOS 26
    /// and 27 at the default intercell spacing, cell-based outline lists).
    static let nativeOutlineInset: CGFloat = 2
    /// The chevron glyph starts this far into its frame (measured).
    static let chevronInkInset: CGFloat = 1.5

    /// How far right a list's rows (chevrons and cells) move so the first chevrons (those at `chevronLevel`) start inside
    /// the selection pill, `pillInset` in from its left edge (the pill itself starts `pillInset` in from the list's edge);
    /// 0 when they already do.
    static func chevronShift(chevronLevel: Int, indentation: CGFloat, pillInset: CGFloat) -> CGFloat {
        let nativeInk = nativeOutlineInset + CGFloat(max(0, chevronLevel)) * indentation + chevronInkInset
        return max(0, ceil(2 * pillInset - nativeInk))
    }

    /// One indentation level of an `ImageAndTextCell` (INDENT_AMOUNT, keep in sync with ImageAndTextCell.h): the managers
    /// indent their favourites / filters one level under "Global" and the file header (17pt in the upstream look).
    static let indentationStep: CGFloat = 17

    /// Under caption headers (the managers' "Global" and file rows): how far the first column's cells move right so a cell's
    /// text at indentation level 0 starts `contentPadding` inside the selection pill — where the captions start. The rows
    /// under a caption keep the managers' one indentation level (`indentationStep`), so their text starts one level right
    /// of the caption text, as upstream lists them; 0 when the cells already start that far in.
    static func captionCellShift(cellMinX: CGFloat, pillInset: CGFloat, contentPadding: CGFloat, textInset: CGFloat) -> CGFloat {
        max(0, pillInset + contentPadding - textInset - cellMinX)
    }

    /// The row content's leading edge for a cell drawn in `frame`: the image after an `ImageAndTextCell`'s indentation
    /// (`indentationStep` per level, its image `imageInset` in), else the text (a borderless text cell's `textInset`).
    static func cellContentLeading(frame: NSRect, indentationLevel: Int, indentationStep: CGFloat, hasImage: Bool,
                                   imageInset: CGFloat, textInset: CGFloat) -> CGFloat {
        frame.minX + CGFloat(max(0, indentationLevel)) * indentationStep + (hasImage ? imageInset : textInset)
    }
}

// MARK: - Manager forms

/// The Query Favorites and Content Filter managers' forms (walkthrough fix 1): one label column, right-aligned, its longest
/// label's text on the left margin; every field starting at the same x after it; the query / clause editor across the form
/// from the labels' left edge to the right margin; the footer's items (help, Insert Placeholder, Cancel, Save) on one
/// centre line. Rects are in the right pane's non-flipped coordinates; label frames carry the text cell's inset.
enum SAClaudeManagerFormLayout {
    static let margin: CGFloat = SAClaudeFooterLayout.margin
    static let top: CGFloat = 12
    static let fieldHeight: CGFloat = 24
    static let labelHeight: CGFloat = 16
    /// Between a label's text and its field.
    static let labelGap: CGFloat = 8
    static let rowGap: CGFloat = 8
    /// Between the editor and the rows above and below it.
    static let editorGap: CGFloat = 10
    /// A borderless label draws its text this far inside its frame (`SAClaudeStyle.cellTextInset`).
    static let labelInset: CGFloat = 2
    /// The widest the label column gets (a longer localized label is truncated).
    static let labelMaxWidth: CGFloat = 140
    static let helpSize: CGFloat = SAClaudeSidebarBarLayout.buttonSize
    /// The help ghost icon's glyph starts this far into its frame: the frame sits this far left of the margin.
    static let helpInset: CGFloat = 6
    static let itemGap: CGFloat = 8
    static let checkboxHeight: CGFloat = 18

    struct Row: Equatable {
        var label: NSRect
        var field: NSRect
    }

    /// The label column: where the label frames start (the text on the margin), their width, where the fields start.
    struct Column: Equatable {
        var labelX: CGFloat
        var labelWidth: CGFloat
        var fieldX: CGFloat
    }

    static func column(labelWidths: [CGFloat], in bounds: NSRect) -> Column {
        let textWidth = min(labelMaxWidth, ceil(labelWidths.max() ?? 0))
        let labelX = bounds.minX + margin - labelInset
        let labelWidth = textWidth + 2 * labelInset
        return Column(labelX: labelX, labelWidth: labelWidth, fieldX: labelX + labelWidth - labelInset + labelGap)
    }

    /// A label + field row whose field starts at `fieldY` and runs to the right margin.
    static func row(_ column: Column, fieldY: CGFloat, in bounds: NSRect) -> Row {
        let field = NSRect(x: column.fieldX, y: fieldY, width: max(0, bounds.maxX - margin - column.fieldX), height: fieldHeight)
        let label = NSRect(x: column.labelX, y: (field.midY - labelHeight / 2).rounded(), width: column.labelWidth, height: labelHeight)
        return Row(label: label, field: field)
    }

    struct Footer: Equatable {
        var save: NSRect
        var cancel: NSRect
        /// The help button on the left margin (nil: none), then `accessory` (Insert Placeholder) after it.
        var help: NSRect?
        var accessory: NSRect?
        var midY: CGFloat
    }

    /// Save and Cancel on the right margin (frame widths with their classic side margins `buttonInset`), the help button
    /// and an accessory (`accessorySize`) from the left margin: all centred on the buttons' line.
    static func footer(in bounds: NSRect, saveWidth: CGFloat, cancelWidth: CGFloat, buttonInset: CGFloat, help: Bool,
                       accessorySize: NSSize?) -> Footer {
        let buttons = SAClaudeFooterLayout.trailing(widths: [saveWidth, cancelWidth], maxX: bounds.maxX,
                                                    y: bounds.minY + SAClaudeFooterLayout.bottom, buttonInset: buttonInset)
        let midY = buttons[0].midY
        var x = bounds.minX + margin
        var helpFrame: NSRect?
        if help {
            let frame = NSRect(x: x - helpInset, y: (midY - helpSize / 2).rounded(), width: helpSize, height: helpSize)
            helpFrame = frame
            x = frame.maxX + itemGap
        }
        let accessory = accessorySize.map { NSRect(x: x, y: (midY - $0.height / 2).rounded(), width: $0.width, height: $0.height) }
        return Footer(save: buttons[0], cancel: buttons[1], help: helpFrame, accessory: accessory, midY: midY)
    }

    /// The top of the area above the footer.
    static func footerTop(_ footer: Footer) -> CGFloat { footer.save.maxY }

    // MARK: Query Favorites

    struct FavoritesFrames: Equatable {
        var name: Row
        var editor: NSRect
        var trigger: Row
        var footer: Footer
    }

    /// Name on top, the query editor, Tab Trigger above the footer (help, Insert Placeholder, Cancel, Save).
    static func favorites(in bounds: NSRect, nameLabelWidth: CGFloat, triggerLabelWidth: CGFloat, saveWidth: CGFloat,
                          cancelWidth: CGFloat, buttonInset: CGFloat, placeholderSize: NSSize, help: Bool) -> FavoritesFrames {
        let column = column(labelWidths: [nameLabelWidth, triggerLabelWidth], in: bounds)
        let footer = footer(in: bounds, saveWidth: saveWidth, cancelWidth: cancelWidth, buttonInset: buttonInset, help: help,
                            accessorySize: placeholderSize)
        let name = row(column, fieldY: bounds.maxY - top - fieldHeight, in: bounds)
        let trigger = row(column, fieldY: footerTop(footer) + editorGap, in: bounds)
        let editorTop = name.field.minY - editorGap
        let editorBottom = trigger.field.maxY + editorGap
        let editor = NSRect(x: bounds.minX + margin, y: editorBottom, width: max(0, bounds.width - 2 * margin), height: max(0, editorTop - editorBottom))
        return FavoritesFrames(name: name, editor: editor, trigger: trigger, footer: footer)
    }

    // MARK: Content Filter

    struct FilterFrames: Equatable {
        var name: Row
        /// "Clause:" on the labels' left edge; "Number of arguments: n" right-aligned on the right margin, on its line.
        var clauseLabel: NSRect
        var argumentCount: NSRect
        var editor: NSRect
        var suppress: NSRect
        var placeholder: NSRect
        var conjunction: Row
        var resultLabel: NSRect
        var result: NSRect
        var footer: Footer
    }

    /// Name; the Clause line; the clause editor; the suppress checkbox; Insert Placeholder; the conjunction label + field
    /// (in the name's label column); the resulting clause (its label and `resultHeight` of text); Cancel and Save.
    static func contentFilter(in bounds: NSRect, nameLabelWidth: CGFloat, conjunctionLabelWidth: CGFloat, saveWidth: CGFloat,
                              cancelWidth: CGFloat, buttonInset: CGFloat, placeholderSize: NSSize, suppressWidth: CGFloat,
                              argumentCountWidth: CGFloat, resultHeight: CGFloat) -> FilterFrames {
        let column = column(labelWidths: [nameLabelWidth, conjunctionLabelWidth], in: bounds)
        let footer = footer(in: bounds, saveWidth: saveWidth, cancelWidth: cancelWidth, buttonInset: buttonInset, help: false, accessorySize: nil)
        let left = bounds.minX + margin, right = bounds.maxX - margin
        let fullLabelWidth = max(0, right - left + 2 * labelInset)

        // Top down: the name, the Clause line.
        let name = row(column, fieldY: bounds.maxY - top - fieldHeight, in: bounds)
        let clauseY = name.field.minY - rowGap - labelHeight
        // The count takes the width its text needs (never more than the line), "Clause:" the rest.
        let countWidth = min(fullLabelWidth, ceil(argumentCountWidth) + 2 * labelInset)
        let clauseLabel = NSRect(x: left - labelInset, y: clauseY, width: fullLabelWidth - countWidth, height: labelHeight)
        let argumentCount = NSRect(x: clauseLabel.maxX, y: clauseY, width: countWidth, height: labelHeight)

        // Bottom up: the resulting clause, the conjunction, Insert Placeholder, the checkbox.
        let result = NSRect(x: left - labelInset, y: footerTop(footer) + rowGap, width: fullLabelWidth, height: max(0, resultHeight))
        let resultLabel = NSRect(x: left - labelInset, y: result.maxY + 2, width: fullLabelWidth, height: labelHeight)
        let conjunction = row(column, fieldY: resultLabel.maxY + editorGap, in: bounds)
        let placeholder = NSRect(x: left, y: conjunction.field.maxY + rowGap, width: placeholderSize.width, height: placeholderSize.height)
        let suppress = NSRect(x: left, y: placeholder.maxY + rowGap, width: min(ceil(suppressWidth), max(0, right - left)), height: checkboxHeight)

        // The editor between them.
        let editorTop = clauseLabel.minY - 4
        let editorBottom = suppress.maxY + rowGap
        let editor = NSRect(x: left, y: editorBottom, width: max(0, right - left), height: max(0, editorTop - editorBottom))
        return FilterFrames(name: name, clauseLabel: clauseLabel, argumentCount: argumentCount, editor: editor, suppress: suppress,
                            placeholder: placeholder, conjunction: conjunction, resultLabel: resultLabel, result: result, footer: footer)
    }
}

// MARK: - Baselines

/// A form label on its control's text baseline (walkthrough fix 1, round 1): labels and fields centred on one line still
/// put their text on different baselines when they draw it differently (a label from its frame's top, a field centred in
/// a taller frame, a pill in another size).
enum SAClaudeFormBaseline {
    /// The y of a label frame `labelHeight` tall, in a non-flipped container, whose text baseline (`labelBaselineFromTop`
    /// below its top) sits at `baselineY`; rounded to the half point.
    static func labelY(baselineY: CGFloat, labelHeight: CGFloat, labelBaselineFromTop: CGFloat) -> CGFloat {
        ((baselineY + labelBaselineFromTop - labelHeight) * 2).rounded() / 2
    }
}
