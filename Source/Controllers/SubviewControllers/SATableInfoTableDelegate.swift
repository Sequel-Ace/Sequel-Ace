//
//  SATableInfoTableDelegate.swift
//  Sequel Ace
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import AppKit

/// The delegate of the Table information pane's table, which makes it a
/// view-based source list of `SATableInfoRowView`s.
///
/// The pane's controller stays the table's data source, and the delegate of
/// the Activities table beside it, which is cell-based; it hands this delegate
/// what it needs as closures.
@objc(SATableInfoTableDelegate) final class SATableInfoTableDelegate: NSObject, NSTableViewDelegate {

    private let text: (Int) -> String?
    private let isGroupRow: (Int) -> Bool
    private let shouldSelect: (Int) -> Bool
    private let headerActivated: () -> Void

    /// - Parameters:
    ///   - text: The text of a row.
    ///   - isGroupRow: Whether a row is drawn as the pane's header.
    ///   - shouldSelect: Whether a row may be selected.
    ///   - headerActivated: Called when the header row is double-clicked.
    @objc init(text: @escaping (Int) -> String?,
               isGroupRow: @escaping (Int) -> Bool,
               shouldSelect: @escaping (Int) -> Bool,
               headerActivated: @escaping () -> Void) {
        self.text = text
        self.isGroupRow = isGroupRow
        self.shouldSelect = shouldSelect
        self.headerActivated = headerActivated
        super.init()
    }

    /// Becomes `tableView`'s delegate, makes it a source list whose rows follow
    /// the Sidebar icon size, and listens for double-clicks on its header.
    /// The caller keeps this object alive: a table holds neither its delegate
    /// nor its target strongly.
    @objc(attachToTableView:)
    func attach(to tableView: NSTableView) {
        tableView.delegate = self
        tableView.style = .sourceList
        tableView.rowSizeStyle = .default
        // Rows touch, as in the tables list above; the nib's 2 pt vertical
        // spacing would add a gap between them.
        tableView.intercellSpacing = NSSize(width: tableView.intercellSpacing.width, height: 0)
        tableView.target = self
        tableView.doubleAction = #selector(tableViewDoubleClicked(_:))
    }

    @objc func tableViewDoubleClicked(_ sender: NSTableView) {
        guard sender.clickedRow >= 0, isGroupRow(sender.clickedRow) else { return }
        headerActivated()
    }

    // MARK: - NSTableViewDelegate

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        SATableInfoRowView.make(in: tableView, text: text(row) ?? "", isGroupRow: isGroupRow(row))
    }

    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
        isGroupRow(row)
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        shouldSelect(row)
    }
}
