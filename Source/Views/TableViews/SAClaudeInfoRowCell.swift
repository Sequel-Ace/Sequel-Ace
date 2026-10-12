//
//  SAClaudeInfoRowCell.swift
//  Sequel Ace
//
//  Draws a sidebar Table information row as two pieces — the label on the
//  left and the value right-aligned — instead of one tab-stopped string.
//  Rows without a value (the header, "Multiple selection") draw as before.
//  App target only.
//

import AppKit

@objc(SAClaudeInfoRowCell) final class SAClaudeInfoRowCell: NSTextFieldCell {

    private static var labelFont: NSFont { .systemFont(ofSize: 13) }
    private static var valueFont: NSFont { .monospacedDigitSystemFont(ofSize: 13, weight: .regular) }

    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        guard let parts = SAClaudeInfoRowLayout.parts(of: stringValue) else {
            super.drawInterior(withFrame: cellFrame, in: controlView)
            return
        }
        let labelAttributes: [NSAttributedString.Key: Any] = [.font: Self.labelFont, .foregroundColor: SAClaudeStyle.textMuted]
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingMiddle
        paragraph.alignment = .right
        let valueAttributes: [NSAttributedString.Key: Any] = [.font: Self.valueFont, .foregroundColor: SAClaudeStyle.textSecondary, .paragraphStyle: paragraph]
        let label = parts.label as NSString
        let value = parts.value as NSString
        let labelSize = label.size(withAttributes: labelAttributes)
        let valueSize = value.size(withAttributes: valueAttributes)
        let frames = SAClaudeInfoRowLayout.frames(in: cellFrame, labelWidth: ceil(labelSize.width), valueWidth: ceil(valueSize.width),
                                                  leading: SAClaudeStyle.infoRowLeadingIndent, trailing: SAClaudeStyle.infoRowTrailingPadding)
        let y = (cellFrame.midY - labelSize.height / 2).rounded()
        label.draw(in: NSRect(x: frames.label.minX, y: y, width: frames.label.width, height: labelSize.height), withAttributes: labelAttributes)
        value.draw(in: NSRect(x: frames.value.minX, y: y, width: frames.value.width, height: valueSize.height), withAttributes: valueAttributes)
    }
}

extension SAClaudeSidebarChrome {
    /// The Table information list: the sidebar table style, 24pt rows, and the two-piece row cell.
    @objc(styleInfoTable:)
    static func styleInfoTable(_ table: NSTableView) {
        styleSidebarTable(table)
        table.rowHeight = 24
        if let column = table.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("info")) {
            let cell = SAClaudeInfoRowCell(textCell: "")
            cell.lineBreakMode = .byTruncatingTail
            // Editable/selectable like the XIB cell: SPTableInfo's shouldEditTableColumn: drives the header-click pane toggle (and always returns NO).
            cell.isEditable = true
            cell.isSelectable = true
            column.dataCell = cell
        }
    }
}
