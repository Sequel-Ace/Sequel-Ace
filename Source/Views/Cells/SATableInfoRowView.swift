//
//  SATableInfoRowView.swift
//  Sequel Ace
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import AppKit

/// A row of the Table information pane: a label and its value in two
/// columns, a line of text that has no label, or the pane's header.
///
/// A "Label: value" row shows the label in secondary text at the leading edge
/// and the value right-aligned at the trailing edge. The label keeps its width
/// and the value truncates in the space left, never closer than
/// `labelValueSpacing` to the label; a label wider than the row truncates too.
///
/// As in the tables list above, the views are laid out with frames, so that a
/// source-list table can position the text and set its font for the Sidebar
/// icon size in System Settings. AppKit only knows about the cell's
/// `textField` (the label); the value copies its font after AppKit applies it,
/// which happens when the cell is laid out or drawn.
///
/// Each kind of row has its own reuse identifier, so a cell styled as a header
/// by AppKit is never handed back for another row.
@objc(SATableInfoRowView) final class SATableInfoRowView: NSTableCellView {

    static let groupIdentifier = NSUserInterfaceItemIdentifier("SATableInfoGroupCell")
    static let textIdentifier = NSUserInterfaceItemIdentifier("SATableInfoTextCell")
    static let pairIdentifier = NSUserInterfaceItemIdentifier("SATableInfoPairCell")

    /// The least space between a label and its value.
    static let labelValueSpacing: CGFloat = 8

    /// Lines the text up with the object icons in the tables list.
    private static let leadingInset: CGFloat = 3

    private enum Kind {
        case group, text, pair

        var identifier: NSUserInterfaceItemIdentifier {
            switch self {
            case .group: return SATableInfoRowView.groupIdentifier
            case .text: return SATableInfoRowView.textIdentifier
            case .pair: return SATableInfoRowView.pairIdentifier
            }
        }
    }

    /// The value of a "Label: value" row. Nil in the other kinds of row.
    private(set) var valueField: NSTextField?

    /// Returns a cell showing `text` for a row of `tableView`, reusing one of
    /// the right kind when the table has one queued.
    @objc(makeInTableView:text:isGroupRow:)
    static func make(in tableView: NSTableView, text: String, isGroupRow: Bool) -> NSTableCellView {
        // Labels are capitalized for the app's language, not the region's: an
        // English label stays "Is updatable" in a Turkish region.
        let language = Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en")
        let row = isGroupRow ? nil : SATableInfoRow.split(text, locale: language)
        let kind: Kind = isGroupRow ? .group : (row == nil ? .text : .pair)
        let cell = tableView.makeView(withIdentifier: kind.identifier, owner: nil) as? SATableInfoRowView
            ?? SATableInfoRowView(kind: kind)
        cell.configure(text: text, row: row)
        return cell
    }

    private init(kind: Kind) {
        super.init(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        identifier = kind.identifier

        let field = Self.makeField()
        switch kind {
        case .group:
            field.frame = NSRect(x: 0, y: 4, width: 200, height: 16)
            field.autoresizingMask = [.width, .minYMargin, .maxYMargin]
        case .text:
            field.frame = NSRect(x: Self.leadingInset, y: 4, width: 200 - Self.leadingInset, height: 16)
            field.autoresizingMask = [.width, .minYMargin, .maxYMargin]
        case .pair:
            field.frame = NSRect(x: Self.leadingInset, y: 4, width: 0, height: 16)
            field.autoresizingMask = [.minYMargin, .maxYMargin]
            field.textColor = .secondaryLabelColor
        }
        addSubview(field)
        textField = field

        guard kind == .pair else { return }

        let value = Self.makeField()
        value.textColor = .labelColor
        value.alignment = .right
        addSubview(value)
        valueField = value
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported; use make(in:text:isGroupRow:)")
    }

    private static func makeField() -> NSTextField {
        let field = NSTextField(labelWithString: "")
        field.lineBreakMode = .byTruncatingTail
        field.maximumNumberOfLines = 1
        field.allowsExpansionToolTips = true
        return field
    }

    private func configure(text: String, row: SATableInfoRow?) {
        objectValue = text
        textField?.stringValue = row?.label ?? text
        valueField?.stringValue = row?.value ?? ""
        needsLayout = true
    }

    // MARK: - Layout

    override var rowSizeStyle: NSTableView.RowSizeStyle {
        didSet {
            needsLayout = true
        }
    }

    override func layout() {
        super.layout()
        layoutLabelAndValue()
    }

    override func viewWillDraw() {
        // AppKit sets the label's font and frame for the row size style here.
        super.viewWillDraw()
        layoutLabelAndValue()
    }

    private func layoutLabelAndValue() {
        guard let labelField = textField, let valueField, let labelCell = labelField.cell else { return }

        if let font = labelField.font, valueField.font != font {
            valueField.font = font
        }

        // The label takes the width it needs, up to the row's width less the
        // spacing; the value has the rest, right-aligned, and truncates first.
        var labelFrame = labelField.frame
        let available = max(0, bounds.maxX - labelFrame.minX)
        labelFrame.size.width = min(ceil(labelCell.cellSize.width), max(0, available - Self.labelValueSpacing))
        labelField.frame = labelFrame

        let valueX = labelFrame.maxX + Self.labelValueSpacing
        valueField.frame = NSRect(x: valueX, y: labelFrame.minY, width: max(0, bounds.maxX - valueX), height: labelFrame.height)
    }
}
