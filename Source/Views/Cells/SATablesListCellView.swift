//
//  SATablesListCellView.swift
//  Sequel Ace
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import AppKit

/// A row of the tables list: an object's icon, its name and, optionally, its
/// comment; or the title of a group row.
///
/// The views are laid out with frames, like AppKit's own sidebar cell views,
/// so that a source-list table can position and size the icon and name for
/// the Sidebar icon size in System Settings. Fonts, symbol configurations and
/// tints are left to AppKit; only the comment, which AppKit doesn't know
/// about, copies the name's font. AppKit applies the font and frames for a
/// row size style when the cell is next laid out or drawn (in
/// `viewWillDraw`), so the comment is matched to the name right after that.
///
/// Item and group rows use separate reuse identifiers, so a cell styled as a
/// header by AppKit is never handed back for an item row.
///
/// Renaming happens in place: the cell is its name field's delegate and hands
/// the trimmed name to the table's data source through
/// `tableView(_:setObjectValue:for:row:)`, which validates and performs it.
@objc(SATablesListCellView) final class SATablesListCellView: NSTableCellView, NSTextFieldDelegate {

    @objc static let itemIdentifier = NSUserInterfaceItemIdentifier("SATablesListItemCell")
    @objc static let groupIdentifier = NSUserInterfaceItemIdentifier("SATablesListGroupCell")

    private static let commentSpacing: CGFloat = 8

    /// The object's comment, after the name. Nil in group rows.
    private(set) var commentField: NSTextField?

    private var isCancellingRename = false

    /// Returns a cell for a row of `tableView`, reusing one of the right kind
    /// when the table has one queued.
    @objc(makeInTableView:isGroupRow:name:tableTypeRawValue:comment:)
    static func make(in tableView: NSTableView, isGroupRow: Bool, name: String, tableTypeRawValue: Int, comment: String?) -> SATablesListCellView {
        let identifier = isGroupRow ? groupIdentifier : itemIdentifier
        let cell = tableView.makeView(withIdentifier: identifier, owner: nil) as? SATablesListCellView
            ?? SATablesListCellView(identifier: identifier, isGroupRow: isGroupRow)
        cell.configure(name: name, tableTypeRawValue: tableTypeRawValue, comment: comment)
        return cell
    }

    private init(identifier: NSUserInterfaceItemIdentifier, isGroupRow: Bool) {
        super.init(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        self.identifier = identifier

        let nameField: NSTextField = isGroupRow ? NSTextField(labelWithString: "") : SATablesListNameField(labelWithString: "")
        nameField.frame = NSRect(x: isGroupRow ? 0 : 24, y: 4, width: isGroupRow ? 200 : 176, height: 16)
        nameField.autoresizingMask = [.width, .minYMargin, .maxYMargin]
        nameField.lineBreakMode = .byTruncatingTail
        nameField.maximumNumberOfLines = 1
        nameField.allowsExpansionToolTips = true
        addSubview(nameField)
        textField = nameField

        guard !isGroupRow else { return }

        let iconView = NSImageView(frame: NSRect(x: 3, y: 4, width: 16, height: 16))
        iconView.autoresizingMask = [.minYMargin, .maxYMargin]
        addSubview(iconView)
        imageView = iconView

        nameField.isEditable = true
        nameField.delegate = self

        let comment = NSTextField(labelWithString: "")
        comment.textColor = .secondaryLabelColor
        comment.lineBreakMode = .byTruncatingTail
        comment.maximumNumberOfLines = 1
        comment.allowsExpansionToolTips = true
        comment.isHidden = true
        addSubview(comment)
        commentField = comment
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported; use make(in:isGroupRow:name:tableTypeRawValue:comment:)")
    }

    private func configure(name: String, tableTypeRawValue: Int, comment: String?) {
        objectValue = name
        textField?.stringValue = name
        imageView?.image = SASidebarObjectGlyph.image(forTableTypeRawValue: tableTypeRawValue)

        if let commentField {
            commentField.stringValue = Self.singleLine(comment ?? "")
            commentField.isHidden = (comment ?? "").isEmpty
            matchCommentFontToName()
        }
        needsLayout = true
    }

    /// A comment on one line, as the tables list has always shown it: line
    /// breaks and tabs become spaces.
    static func singleLine(_ comment: String) -> String {
        comment.components(separatedBy: .newlines).joined(separator: " ")
            .replacingOccurrences(of: "\t", with: " ")
    }

    // MARK: - Layout

    override var rowSizeStyle: NSTableView.RowSizeStyle {
        didSet {
            needsLayout = true
        }
    }

    override func layout() {
        super.layout()
        layoutComment()
    }

    override func viewWillDraw() {
        // AppKit sets the name's font and frame for the row size style here.
        super.viewWillDraw()
        layoutComment()
    }

    private func matchCommentFontToName() {
        guard let commentField, let font = textField?.font, commentField.font != font else { return }
        commentField.font = font
    }

    private func layoutComment() {
        guard let nameField = textField, let commentField else { return }
        matchCommentFontToName()

        // The name keeps the whole width while it is renamed or has no comment
        // beside it; otherwise it takes what it needs and the comment the rest.
        var nameFrame = nameField.frame
        let available = max(0, bounds.maxX - nameFrame.minX)
        guard !commentField.isHidden, nameField.currentEditor() == nil, let nameCell = nameField.cell else {
            nameFrame.size.width = available
            nameField.frame = nameFrame
            commentField.frame.size.width = 0
            return
        }

        nameFrame.size.width = min(available, ceil(nameCell.cellSize.width))
        nameField.frame = nameFrame

        let commentX = nameFrame.maxX + Self.commentSpacing
        commentField.frame = NSRect(x: commentX, y: nameFrame.minY, width: max(0, bounds.maxX - commentX), height: nameFrame.height)
    }

    // MARK: - Renaming

    /// Whether `row`'s name may be edited: only as the single selected row,
    /// as the Rename command requires, and only when the table's delegate
    /// allows it (it refuses while the document is working).
    static func canRename(row: Int, in tableView: NSTableView) -> Bool {
        guard row >= 0, tableView.numberOfSelectedRows == 1, tableView.isRowSelected(row) else {
            return false
        }
        return tableView.delegate?.tableView?(tableView, shouldEdit: tableView.tableColumns.first, row: row) ?? true
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard !isCancellingRename, let nameField = textField, let tableView = enclosingTableView else { return }

        let row = tableView.row(for: self)
        let newName = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        // Keep showing the current name; the data source reloads the list
        // after a rename and leaves it alone when it declines one (an empty or
        // duplicate name, or a cancelled confirmation).
        nameField.stringValue = objectValue as? String ?? ""
        needsLayout = true

        guard row >= 0 else { return }
        tableView.dataSource?.tableView?(tableView, setObjectValue: newName, for: tableView.tableColumns.first, row: row)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)),
             #selector(NSResponder.insertTab(_:)),
             #selector(NSResponder.insertBacktab(_:)):
            // Moving focus back to the list ends editing, which commits. Tab
            // must not carry on into the next row's name: the data source
            // renames the selected table, whichever row is being edited.
            focusTableView()
            return true
        case #selector(NSResponder.cancelOperation(_:)), #selector(NSResponder.complete(_:)):
            cancelRename()
            return true
        default:
            return false
        }
    }

    private func cancelRename() {
        guard let nameField = textField else { return }
        isCancellingRename = true
        defer { isCancellingRename = false }

        nameField.abortEditing()
        nameField.stringValue = objectValue as? String ?? ""
        (nameField as? SATablesListNameField)?.restoreDisplayAfterEditing()
        focusTableView()
    }

    private func focusTableView() {
        guard let tableView = enclosingTableView else { return }
        window?.makeFirstResponder(tableView)
    }

    private var enclosingTableView: NSTableView? {
        var view = superview
        while let candidate = view {
            if let tableView = candidate as? NSTableView {
                return tableView
            }
            view = candidate.superview
        }
        return nil
    }
}

/// The editable name of an item row. It truncates while displayed and
/// scrolls horizontally while edited, so a long name never wraps out of view.
private final class SATablesListNameField: NSTextField {

    override func becomeFirstResponder() -> Bool {
        cell?.isScrollable = true
        let didBecomeFirstResponder = super.becomeFirstResponder()
        if !didBecomeFirstResponder {
            restoreDisplayAfterEditing()
        }
        superview?.needsLayout = true
        return didBecomeFirstResponder
    }

    override func textDidEndEditing(_ notification: Notification) {
        super.textDidEndEditing(notification)
        restoreDisplayAfterEditing()
    }

    func restoreDisplayAfterEditing() {
        cell?.isScrollable = false
        lineBreakMode = .byTruncatingTail
        superview?.needsLayout = true
    }
}
