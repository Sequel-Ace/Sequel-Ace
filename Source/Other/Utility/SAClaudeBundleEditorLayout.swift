//
//  SAClaudeBundleEditorLayout.swift
//  Sequel Ace
//
//  The Bundle Editor's pure geometry (spec 2026-10-18-claude-utility-windows-design.md, section D): the bundle's
//  settings as a two-column form from the pane's top margin (label + control rows, rows level across the columns:
//  Bundle Scope | Trigger, Menu Label | Menu Category, Shortcut | Tooltip, Input | Or / And, Output | the bundle summary
//  and Bundle Info, which take the right column's spare row), the command below it and the footer (Disable Bundle, help,
//  Cancel, Save). Rects are in the pane's non-flipped coordinates. Applied by SAClaudeBundleEditorStyler.swift. Shared
//  with the Unit Tests target.
//

import AppKit

enum SAClaudeBundleEditorLayout {
    static let margin: CGFloat = SAClaudeFooterLayout.margin
    /// The form's first row starts this far below the pane's top (the User Manager's tabs' top margin).
    static let top: CGFloat = 16
    /// Bundle Info's frame height: a regular push button's XIB height (its classic margins included).
    static let infoHeight: CGFloat = 32
    static let rowHeight: CGFloat = 24
    static let rowGap: CGFloat = 8
    static let labelGap: CGFloat = 8
    static let columnGap: CGFloat = 24
    /// The widest a label column gets (a longer localized label is truncated).
    static let labelMaxWidth: CGFloat = 150
    static let formCommandGap: CGFloat = 16
    static let commandLabelHeight: CGFloat = 16
    static let commandLabelGap: CGFloat = 6
    static let commandFooterGap: CGFloat = 12
    static let helpSize: CGFloat = 28
    static let checkboxHeight: CGFloat = 18
    /// Between the summary and Bundle Info, the checkbox and help, help and Cancel.
    static let itemGap: CGFloat = 12

    struct Row: Equatable {
        var label: NSRect
        var control: NSRect
    }

    struct Frames: Equatable {
        var summary: NSRect
        var info: NSRect
        var left: [Row]
        var right: [Row]
        var commandLabel: NSRect
        var command: NSRect
        var disable: NSRect
        var help: NSRect
        var cancel: NSRect
        var save: NSRect
    }

    /// What the styler measured: each column's widest label, the rows in each column, a label's height, the push
    /// buttons' frame widths (their classic margins `buttonInset` included) and the checkbox's width.
    struct Measures: Equatable {
        var leftLabelWidth: CGFloat
        var rightLabelWidth: CGFloat
        var leftRows: Int
        var rightRows: Int
        var labelHeight: CGFloat = 16
        var infoWidth: CGFloat
        var cancelWidth: CGFloat
        var saveWidth: CGFloat
        var disableWidth: CGFloat
        var buttonInset: CGFloat
    }

    /// Each column's width: half the room between the margins, less the gap between them.
    static func columnWidth(paneWidth: CGFloat) -> CGFloat {
        max(0, ((paneWidth - 2 * margin - columnGap) / 2).rounded(.down))
    }

    /// The width a column's labels get: the widest label, capped (`labelMaxWidth`, and never more than half the column).
    static func labelWidth(_ measured: CGFloat, columnWidth: CGFloat) -> CGFloat {
        max(0, min(ceil(measured), labelMaxWidth, (columnWidth / 2).rounded(.down)))
    }

    /// `count` rows of a column at `x`, `width` wide, from `top` down; labels right next to their controls.
    static func rows(count: Int, x: CGFloat, width: CGFloat, top: CGFloat, labelWidth: CGFloat, labelHeight: CGFloat) -> [Row] {
        (0..<max(0, count)).map { index in
            let y = top - rowHeight - CGFloat(index) * (rowHeight + rowGap)
            let controlX = x + labelWidth + labelGap
            let control = NSRect(x: controlX, y: y, width: max(0, x + width - controlX), height: rowHeight)
            let label = NSRect(x: x, y: (control.midY - labelHeight / 2).rounded(), width: labelWidth, height: labelHeight)
            return Row(label: label, control: control)
        }
    }

    static func frames(in bounds: NSRect, _ m: Measures) -> Frames {
        let innerMinX = bounds.minX + margin
        let innerMaxX = bounds.maxX - margin

        // The form from the top margin: two columns of rows, level across the columns.
        let column = columnWidth(paneWidth: bounds.width)
        let formTop = bounds.maxY - top
        let rightX = innerMinX + column + columnGap
        let left = rows(count: m.leftRows, x: innerMinX, width: column, top: formTop,
                        labelWidth: labelWidth(m.leftLabelWidth, columnWidth: column), labelHeight: m.labelHeight)
        let rightAndSpare = rows(count: m.rightRows + 1, x: rightX, width: column, top: formTop,
                                 labelWidth: labelWidth(m.rightLabelWidth, columnWidth: column), labelHeight: m.labelHeight)
        let right = Array(rightAndSpare.prefix(m.rightRows))

        // Bundle Info in the right column's spare row (level with the left column's row there), its right edge on the
        // form's; the summary right-aligned before it, across the rest of the right column.
        let band = rightAndSpare[m.rightRows].control
        let info = SAClaudeFooterLayout.trailing(widths: [m.infoWidth], maxX: bounds.maxX, y: (band.midY - infoHeight / 2).rounded(),
                                                 buttonInset: m.buttonInset)[0]
        let summaryMaxX = info.minX + m.buttonInset - itemGap
        let summary = NSRect(x: rightX, y: (band.midY - m.labelHeight / 2).rounded(), width: max(0, summaryMaxX - rightX), height: m.labelHeight)
        let formBottom = (left + right).map(\.control.minY).min().map { min($0, band.minY) } ?? band.minY

        // Footer: Save and Cancel on the right margin, help just left of them, Disable Bundle on the left margin.
        let footerY = bounds.minY + SAClaudeFooterLayout.bottom
        let buttons = SAClaudeFooterLayout.trailing(widths: [m.saveWidth, m.cancelWidth], maxX: bounds.maxX, y: footerY, buttonInset: m.buttonInset)
        let footerMidY = footerY + SAClaudeFooterLayout.height / 2
        let helpX = SAClaudeFooterLayout.leadingEdge(of: buttons, buttonInset: m.buttonInset) - itemGap - helpSize
        let help = NSRect(x: helpX, y: (footerMidY - helpSize / 2).rounded(), width: helpSize, height: helpSize)
        let disable = NSRect(x: innerMinX, y: (footerMidY - checkboxHeight / 2).rounded(),
                             width: max(0, min(ceil(m.disableWidth), help.minX - itemGap - innerMinX)), height: checkboxHeight)

        // The command: its label under the form, the editor down to the footer.
        let commandLabel = NSRect(x: innerMinX, y: formBottom - formCommandGap - commandLabelHeight,
                                  width: max(0, innerMaxX - innerMinX), height: commandLabelHeight)
        let commandTop = commandLabel.minY - commandLabelGap
        let commandBottom = footerY + SAClaudeFooterLayout.height + commandFooterGap
        let command = NSRect(x: innerMinX, y: commandBottom, width: max(0, innerMaxX - innerMinX), height: max(0, commandTop - commandBottom))

        return Frames(summary: summary, info: info, left: left, right: right, commandLabel: commandLabel, command: command,
                      disable: disable, help: help, cancel: buttons[1], save: buttons[0])
    }
}
