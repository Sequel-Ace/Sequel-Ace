//
//  SAClaudeBitEditorForm.swift
//  Sequel Ace
//
//  The Claude BIT editor (SPFieldEditorController's bitSheet; the controller file is never edited) as a shared-form
//  recipe: the column as title and the table and type as context, Hexadecimal / Integer / Octal rows, the operator
//  buttons as a row of small secondary buttons, the 64 bits as an 8 × 8 grid of chips (bit 63 top-left → bit 0
//  bottom-right, each row led by its bit-position label), NULL at the footer's left and Cancel + OK at its right.
//  App target only.
//

import AppKit

extension SAClaudeFormRecipes {

    static func bitEditor(_ m: SAClaudeFormMatch) -> SAClaudeFormRecipe? {
        let o = m.owner
        guard let contentView = m.window.contentView,
              let fieldName: NSTextField = outlet(o, "bitSheetFieldName"),
              let hex: NSTextField = outlet(o, "bitSheetHexTextField"),
              let integer: NSTextField = outlet(o, "bitSheetIntegerTextField"),
              let octal: NSTextField = outlet(o, "bitSheetOctalTextField"),
              let ok: NSButton = outlet(o, "bitSheetOkButton"),
              let cancel: NSButton = outlet(o, "bitSheetCloseButton"),
              let null: NSButton = outlet(o, "bitSheetNULLButton"),
              let hexRow = row(hex, .field), let integerRow = row(integer, .field), let octalRow = row(octal, .field)
        else { return nil }
        let bits: [NSButton] = (0..<64).compactMap { outlet(o, "bitSheetBitButton\($0)") }
        let bitLabels: [NSTextField] = stride(from: 56, through: 0, by: -8).compactMap { outlet(o, "bitSheetBitLabel\($0)") }
        let operators = SAClaudeFormFind.buttons(in: contentView, action: "bitSheetOperatorButtonWasClicked:").sorted { $0.tag < $1.tag }
        let dummies = SAClaudeFormFind.buttons(in: contentView, action: "selectText:") + SAClaudeFormFind.buttons(in: contentView, action: "bitSheetSelectBit0:")
        guard bits.count == 64, bitLabels.count == 8, operators.count == 7,
              ((bits as [NSView]) + (bitLabels as [NSView]) + (operators as [NSView]) + [null]).allSatisfy({ $0.superview === contentView }) else { return nil }

        let items: [SAClaudeFormItem] = [
            hexRow, integerRow, octalRow,
            .custom(views: operators, height: SAClaudeFormLayout.operatorButtonSize.height, wide: false, place: { rect, _ in
                for (button, frame) in zip(operators, SAClaudeFormLayout.operatorFrames(count: operators.count, in: rect)) {
                    SAClaudeFormSheet.place(button, frame)
                }
            }),
            .custom(views: (bits as [NSView]) + (bitLabels as [NSView]), height: SAClaudeFormLayout.bitGridHeight, wide: true, place: { rect, controlX in
                // The chips start at the control column (inside the right margin when the labels are very wide).
                let chipsLeft = min(controlX, rect.maxX - SAClaudeFormLayout.bitChipsWidth)
                let grid = SAClaudeFormLayout.bitGrid(chipsLeft: chipsLeft, top: rect.maxY)
                for (bit, chip) in bits.enumerated() { SAClaudeFormSheet.place(chip, grid.chips[bit]) }
                for (row, label) in bitLabels.enumerated() { SAClaudeFormSheet.place(label, grid.rowLabels[row]) }
            }),
        ]
        // Every view is already a direct child of the content view: nothing to re-parent, so no `install`.
        return SAClaudeSimpleFormRecipe(didAttach: { _ in
            for field in [hex, integer, octal] {
                field.controlSize = .regular
                field.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            }
            for label in bitLabels {
                label.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
                label.alignment = .right
            }
            for chip in bits + [null] { SAClaudeBitChipCell.install(on: chip) }
            null.isBordered = false
            null.setFrameSize(NSSize(width: ceil(null.cell?.cellSize.width ?? 48), height: SAClaudeFormLayout.bitChipSize.height))
            SAClaudeFormChrome.force(ok, primary: true)
            SAClaudeFormChrome.force(cancel, primary: false)
            for button in operators { SAClaudeFormChrome.force(button, primary: false) }
            return nil
        }, content: { [weak editor = o, weak doc = m.document] in
            let header = SAClaudeFormContext.fieldEditorHeader(label: fieldName.stringValue, editor: editor, document: doc)
            return SAClaudeFormContent(title: header.title, context: header.context, items: items,
                                       footerLeading: [null], footerTrailing: [cancel, ok], hidden: [fieldName], offscreen: dummies,
                                       minimumControlWidth: SAClaudeFormLayout.bitControlColumnWidth)
        })
    }
}

/// A BIT editor chip: a rounded rectangle, the accent fill when on, a hairline outline when off, its title (NULL)
/// centred. Installed in place of the bit checkboxes' and the NULL toggle's cells (`object_setClass`, no stored
/// properties), so their state, target, action and tags stay the controller's; draws its colours at draw time.
@objc(SAClaudeBitChipCell) final class SAClaudeBitChipCell: NSButtonCell {

    private static let radius: CGFloat = 5
    private static let titleFont = NSFont.systemFont(ofSize: 10, weight: .medium)
    private static let titlePadding: CGFloat = 16

    /// Swaps `button`'s cell (a plain NSButtonCell, or the skin's Claude checkbox or sheet button cell) for the chip;
    /// the skin's later walks leave it (it only installs over exact AppKit cells, and skips borderless buttons).
    static func install(on button: NSButton) {
        guard let cell = button.cell as? NSButtonCell else { return }
        if !(cell is SAClaudeBitChipCell) {
            let current: AnyClass = Swift.type(of: cell)
            let swappable = current == NSButtonCell.self || current == SAClaudeCheckboxCell.self
                || current == SAClaudeSheetPrimaryButtonCell.self || current == SAClaudeSheetSecondaryButtonCell.self
            guard swappable, SAClaudeClassSwap.mayChangeClass(of: cell) else { return }
            object_setClass(cell, SAClaudeBitChipCell.self)
        }
        SAClaudeFilterCells.installCellDrawing(on: button)
        button.needsDisplay = true
    }

    override func cellSize(forBounds rect: NSRect) -> NSSize {
        let titleWidth = title.isEmpty ? 0 : ceil(NSAttributedString(string: title, attributes: [.font: Self.titleFont]).size().width) + Self.titlePadding
        return NSSize(width: max(SAClaudeFormLayout.bitChipSize.width, titleWidth), height: SAClaudeFormLayout.bitChipSize.height)
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        let palette = SAClaudeFilterBarStyler.currentPalette
        let path = FilterCellDrawing.roundedPath(cellFrame.insetBy(dx: 0.5, dy: 0.5), radius: Self.radius)
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        if !isEnabled { NSGraphicsContext.current?.cgContext.setAlpha(FilterCellDrawing.disabledAlpha) }
        let on = state == .on
        if on {
            (isHighlighted ? SAClaudeEditorChrome.runFillPressed : SAClaudeEditorChrome.runFill).setFill()
            path.fill()
        } else {
            if isHighlighted {
                palette.hover.setFill()
                path.fill()
            }
            path.lineWidth = 1
            palette.hairline.setStroke()
            path.stroke()
        }
        if !title.isEmpty {
            FilterCellDrawing.drawTitle(title, in: cellFrame, colour: on ? SAClaudeAccent.onAccent : SAClaudeFilterBarStyler.currentThemeText,
                                        font: Self.titleFont, alignment: .center)
        }
    }
}
