//
//  SATablesListCellViewTests.swift
//  Unit Tests
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import AppKit
import XCTest

final class SATablesListCellViewTests: XCTestCase {

    private var window: NSWindow!
    private var tableView: NSTableView!
    private var source: StubSource!

    override func setUp() {
        super.setUp()
        source = StubSource()
        tableView = NSTableView(frame: NSRect(x: 0, y: 0, width: 260, height: 400))
        tableView.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("tables")))
        tableView.tableColumns[0].width = 260
        tableView.style = .sourceList
        tableView.rowSizeStyle = .default
        tableView.dataSource = source
        tableView.delegate = source

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 260, height: 400))
        scrollView.documentView = tableView
        window = NSWindow(contentRect: scrollView.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = scrollView
        tableView.reloadData()
        tableView.layoutSubtreeIfNeeded()
    }

    override func tearDown() {
        window.close()
        window = nil
        tableView = nil
        source = nil
        super.tearDown()
    }

    func testItemAndGroupCellsUseDifferentIdentifiers() throws {
        XCTAssertNotEqual(SATablesListCellView.itemIdentifier, SATablesListCellView.groupIdentifier)

        // Flip which rows are headers between reloads so cells are recycled
        // across positions; each must still come back with its own kind.
        for groupRows in [Set([0, 3]), Set([1, 2]), Set([0, 3])] {
            source.groupRows = groupRows
            tableView.reloadData()
            tableView.layoutSubtreeIfNeeded()

            for row in 0..<source.names.count {
                let cell = try XCTUnwrap(tableView.view(atColumn: 0, row: row, makeIfNecessary: true) as? SATablesListCellView)
                let isGroup = groupRows.contains(row)
                XCTAssertEqual(cell.identifier, isGroup ? SATablesListCellView.groupIdentifier : SATablesListCellView.itemIdentifier, "row \(row)")
                XCTAssertEqual(cell.textField?.isEditable, !isGroup, "row \(row)")
                XCTAssertEqual(cell.textField?.stringValue, source.names[row], "row \(row)")
            }
        }

        let item = SATablesListCellView.make(in: tableView, isGroupRow: false, name: "a", tableTypeRawValue: 0, comment: nil)
        let group = SATablesListCellView.make(in: tableView, isGroupRow: true, name: "TABLES", tableTypeRawValue: -1, comment: nil)
        XCTAssertEqual(item.identifier, SATablesListCellView.itemIdentifier)
        XCTAssertEqual(group.identifier, SATablesListCellView.groupIdentifier)
        XCTAssertNotNil(item.imageView?.image)
        XCTAssertNil(group.commentField)
    }

    func testCommentFieldFollowsRowSizeStyle() throws {
        source.comments[1] = "customer records"
        tableView.reloadData()
        tableView.layoutSubtreeIfNeeded()
        let cell = try XCTUnwrap(tableView.view(atColumn: 0, row: 1, makeIfNecessary: true) as? SATablesListCellView)
        let comment = try XCTUnwrap(cell.commentField)

        var sizes: [CGFloat] = []
        for style in [NSTableView.RowSizeStyle.small, .large] {
            cell.rowSizeStyle = style
            // AppKit applies the name's font for the style when the cell is laid out.
            cell.layoutSubtreeIfNeeded()
            let nameSize = try XCTUnwrap(cell.textField?.font?.pointSize)
            XCTAssertEqual(comment.font?.pointSize, nameSize, "row size style \(style.rawValue)")
            sizes.append(nameSize)
        }
        // AppKit really did resize the name; otherwise the check above proves nothing.
        XCTAssertLessThan(sizes[0], sizes[1])
    }

    func testGroupTitleLinesUpWithTheRowIcons() throws {
        for style in [NSTableView.RowSizeStyle.small, .medium, .large] {
            tableView.rowSizeStyle = style
            tableView.reloadData()
            tableView.layoutSubtreeIfNeeded()

            let item = try XCTUnwrap(tableView.view(atColumn: 0, row: 1, makeIfNecessary: true) as? SATablesListCellView)
            let group = try XCTUnwrap(tableView.view(atColumn: 0, row: 0, makeIfNecessary: true) as? SATablesListCellView)
            item.layoutSubtreeIfNeeded()
            group.layoutSubtreeIfNeeded()

            let icon = try XCTUnwrap(item.imageView)
            let title = try XCTUnwrap(group.textField)
            let iconX = tableView.convert(icon.bounds, from: icon).minX
            let titleX = tableView.convert(title.bounds, from: title).minX
            XCTAssertEqual(titleX, iconX, accuracy: 1, "row size style \(style.rawValue)")
            XCTAssertGreaterThan(iconX, 4, "row size style \(style.rawValue)")
        }
    }

    func testGroupTitleStaysWhereAppKitPutsItWithoutItemRows() throws {
        source.names = ["TABLES", "PROCS & FUNCS"]
        source.groupRows = [0, 1]
        tableView.reloadData()
        tableView.layoutSubtreeIfNeeded()

        let group = try XCTUnwrap(tableView.view(atColumn: 0, row: 0, makeIfNecessary: true) as? SATablesListCellView)
        group.layoutSubtreeIfNeeded()
        XCTAssertEqual(try XCTUnwrap(group.textField).frame.minX, 0, accuracy: 0.5)
    }

    func testCommentHiddenWhenEmpty() throws {
        for (comment, hidden) in [(nil, true), ("", true), ("x", false)] as [(String?, Bool)] {
            let cell = SATablesListCellView.make(in: tableView, isGroupRow: false, name: "orders", tableTypeRawValue: 0, comment: comment)
            XCTAssertEqual(try XCTUnwrap(cell.commentField).isHidden, hidden, "comment \(String(describing: comment))")
        }
    }

    func testMultiLineCommentShowsOnOneLine() throws {
        let cell = SATablesListCellView.make(in: tableView, isGroupRow: false, name: "orders", tableTypeRawValue: 0, comment: "customer\nrecords\nby\tregion")
        XCTAssertEqual(try XCTUnwrap(cell.commentField).stringValue, "customer records by region")
    }

    func testCommentStartsAfterTheName() throws {
        source.comments[1] = "customer records"
        tableView.reloadData()
        tableView.layoutSubtreeIfNeeded()
        let cell = try XCTUnwrap(tableView.view(atColumn: 0, row: 1, makeIfNecessary: true) as? SATablesListCellView)
        cell.layoutSubtreeIfNeeded()
        let name = try XCTUnwrap(cell.textField)
        let comment = try XCTUnwrap(cell.commentField)

        XCTAssertFalse(comment.isHidden)
        XCTAssertGreaterThanOrEqual(name.frame.width, ceil(name.attributedStringValue.size().width))
        XCTAssertGreaterThan(comment.frame.minX, name.frame.maxX)
        XCTAssertLessThanOrEqual(comment.frame.maxX, cell.bounds.maxX)
    }

    func testEndEditingCommitsTrimmedTextThroughDataSource() throws {
        let cell = try beginEditing(row: 1)
        let editor = try XCTUnwrap(cell.textField?.currentEditor() as? NSTextView)
        editor.string = "  orders2 "

        XCTAssertTrue(window.makeFirstResponder(tableView))

        XCTAssertEqual(source.committed.count, 1)
        XCTAssertEqual(source.committed.first?.value, "orders2")
        XCTAssertEqual(source.committed.first?.row, 1)
        XCTAssertEqual(source.committed.first?.column, tableView.tableColumns.first)
    }

    func testReturnCommitsOnceAndFocusesTheTable() throws {
        let cell = try beginEditing(row: 1)
        let nameField = try XCTUnwrap(cell.textField)
        let editor = try XCTUnwrap(nameField.currentEditor() as? NSTextView)
        editor.string = "orders2"

        XCTAssertTrue(cell.control(nameField, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:))))

        XCTAssertEqual(source.committed.map(\.value), ["orders2"])
        XCTAssertEqual(source.committed.first?.row, 1)
        XCTAssertTrue(window.firstResponder === tableView)
    }

    func testTabCommitsOnceWithoutEditingAnotherRow() throws {
        for command in [#selector(NSResponder.insertTab(_:)), #selector(NSResponder.insertBacktab(_:))] {
            source.committed.removeAll()
            let cell = try beginEditing(row: 1)
            let nameField = try XCTUnwrap(cell.textField)
            let editor = try XCTUnwrap(nameField.currentEditor() as? NSTextView)
            editor.string = "orders2"

            XCTAssertTrue(cell.control(nameField, textView: editor, doCommandBy: command))

            XCTAssertEqual(source.committed.map(\.value), ["orders2"], NSStringFromSelector(command))
            XCTAssertTrue(window.firstResponder === tableView, NSStringFromSelector(command))
            for row in 0..<source.names.count {
                let rowCell = tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? SATablesListCellView
                XCTAssertNil(rowCell?.textField?.currentEditor(), "\(NSStringFromSelector(command)) row \(row)")
            }
        }
    }

    func testRenameOnlyForTheSingleSelectedRowTheDelegateAllows() {
        XCTAssertFalse(SATablesListCellView.canRename(row: 1, in: tableView), "nothing selected")

        tableView.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        XCTAssertTrue(SATablesListCellView.canRename(row: 1, in: tableView))
        XCTAssertFalse(SATablesListCellView.canRename(row: 2, in: tableView), "another row")
        XCTAssertFalse(SATablesListCellView.canRename(row: -1, in: tableView), "no row")

        source.allowsEditing = false
        XCTAssertFalse(SATablesListCellView.canRename(row: 1, in: tableView), "delegate refuses")
        source.allowsEditing = true

        tableView.allowsMultipleSelection = true
        tableView.selectRowIndexes(IndexSet([1, 2]), byExtendingSelection: false)
        XCTAssertFalse(SATablesListCellView.canRename(row: 1, in: tableView), "several rows selected")
    }

    func testEditColumnStartsRenamingTheRow() throws {
        // Return on a selected row and the Rename menu item both use editColumn.
        tableView.editColumn(0, row: 2, with: nil, select: true)

        let cell = try XCTUnwrap(tableView.view(atColumn: 0, row: 2, makeIfNecessary: false) as? SATablesListCellView)
        XCTAssertNotNil(cell.textField?.currentEditor())
    }

    func testEscapeRestoresNameWithoutCommit() throws {
        for command in [#selector(NSResponder.cancelOperation(_:)), #selector(NSResponder.complete(_:))] {
            let cell = try beginEditing(row: 1)
            let nameField = try XCTUnwrap(cell.textField)
            let editor = try XCTUnwrap(nameField.currentEditor() as? NSTextView)
            editor.string = "renamed"

            XCTAssertTrue(cell.control(nameField, textView: editor, doCommandBy: command))

            XCTAssertEqual(nameField.stringValue, source.names[1], NSStringFromSelector(command))
            XCTAssertNil(nameField.currentEditor(), NSStringFromSelector(command))
            XCTAssertTrue(window.firstResponder === tableView, NSStringFromSelector(command))
        }
        XCTAssertTrue(source.committed.isEmpty)
    }

    private func beginEditing(row: Int) throws -> SATablesListCellView {
        let cell = try XCTUnwrap(tableView.view(atColumn: 0, row: row, makeIfNecessary: true) as? SATablesListCellView)
        XCTAssertTrue(window.makeFirstResponder(cell.textField))
        XCTAssertNotNil(cell.textField?.currentEditor())
        return cell
    }
}

private final class StubSource: NSObject, NSTableViewDataSource, NSTableViewDelegate {

    var names = ["TABLES", "orders", "customers", "PROCS & FUNCS"]
    var groupRows: Set<Int> = [0, 3]
    var comments: [Int: String] = [:]
    var committed: [(value: String?, column: NSTableColumn?, row: Int)] = []
    var allowsEditing = true

    func numberOfRows(in tableView: NSTableView) -> Int {
        names.count
    }

    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
        groupRows.contains(row)
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        SATablesListCellView.make(
            in: tableView,
            isGroupRow: groupRows.contains(row),
            name: names[row],
            tableTypeRawValue: groupRows.contains(row) ? -1 : 0,
            comment: comments[row]
        )
    }

    func tableView(_ tableView: NSTableView, shouldEdit tableColumn: NSTableColumn?, row: Int) -> Bool {
        allowsEditing
    }

    func tableView(_ tableView: NSTableView, setObjectValue object: Any?, for tableColumn: NSTableColumn?, row: Int) {
        committed.append((object as? String, tableColumn, row))
    }
}
