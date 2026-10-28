//
//  SATableInfoRowViewTests.swift
//  Unit Tests
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import AppKit
import XCTest

final class SATableInfoRowViewTests: XCTestCase {

    private var window: NSWindow!
    private var tableView: NSTableView!
    private var source: StubSource!
    private var delegate: SATableInfoTableDelegate!
    private var headerActivations = 0

    override func setUp() {
        super.setUp()
        source = StubSource()
        headerActivations = 0
        tableView = NSTableView(frame: NSRect(x: 0, y: 0, width: 240, height: 300))
        tableView.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("info")))
        tableView.tableColumns[0].width = 240
        tableView.dataSource = source
        delegate = SATableInfoTableDelegate(text: { [unowned self] row in
            row < self.source.rows.count ? self.source.rows[row] : nil
        }, isGroupRow: { $0 == 0 }, shouldSelect: { $0 == 0 }, headerActivated: { [unowned self] in
            self.headerActivations += 1
        })
        delegate.attach(to: tableView)

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 240, height: 300))
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
        delegate = nil
        source = nil
        super.tearDown()
    }

    func testAttachMakesAViewBasedSourceList() throws {
        XCTAssertTrue(tableView.delegate === delegate)
        XCTAssertEqual(tableView.style, .sourceList)
        XCTAssertEqual(tableView.rowSizeStyle, .default)
        XCTAssertTrue(tableView.target === delegate)
        XCTAssertNotNil(tableView.doubleAction)

        XCTAssertNotNil(tableView.view(atColumn: 0, row: 1, makeIfNecessary: true) as? SATableInfoRowView)
        XCTAssertTrue(tableView.delegate?.tableView?(tableView, isGroupRow: 0) ?? false)
        XCTAssertFalse(tableView.delegate?.tableView?(tableView, isGroupRow: 1) ?? true)
        XCTAssertTrue(tableView.delegate?.tableView?(tableView, shouldSelectRow: 0) ?? false)
        XCTAssertFalse(tableView.delegate?.tableView?(tableView, shouldSelectRow: 1) ?? true)
    }

    func testDoubleClickOutsideTheHeaderDoesNothing() {
        // No row was clicked.
        delegate.tableViewDoubleClicked(tableView)
        XCTAssertEqual(headerActivations, 0)
    }

    func testDoubleClickOnTheHeaderActivatesIt() throws {
        let clickedTable = ClickedRowTableView()
        delegate.attach(to: clickedTable)
        let target = try XCTUnwrap(clickedTable.target as? NSObject)
        let doubleAction = try XCTUnwrap(clickedTable.doubleAction)

        // Row 1 is a "Label: value" row.
        clickedTable.stubbedClickedRow = 1
        target.perform(doubleAction, with: clickedTable)
        XCTAssertEqual(headerActivations, 0)

        // Row 0 is the header.
        clickedTable.stubbedClickedRow = 0
        target.perform(doubleAction, with: clickedTable)
        XCTAssertEqual(headerActivations, 1)
    }

    func testEachKindOfRowHasItsOwnIdentifier() throws {
        let identifiers = [SATableInfoRowView.groupIdentifier, SATableInfoRowView.textIdentifier, SATableInfoRowView.pairIdentifier]
        XCTAssertEqual(Set(identifiers).count, 3)

        for (row, identifier) in [(0, SATableInfoRowView.groupIdentifier), (1, SATableInfoRowView.pairIdentifier), (2, SATableInfoRowView.textIdentifier)] {
            let cell = try XCTUnwrap(tableView.view(atColumn: 0, row: row, makeIfNecessary: true) as? SATableInfoRowView)
            XCTAssertEqual(cell.identifier, identifier, "row \(row)")
        }

        let group = SATableInfoRowView.make(in: tableView, text: "TABLE INFORMATION", isGroupRow: true)
        XCTAssertEqual(group.textField?.stringValue, "TABLE INFORMATION")
        XCTAssertNil((group as? SATableInfoRowView)?.valueField)
    }

    func testLabelAndValueGoInTheirOwnFields() throws {
        let cell = try XCTUnwrap(SATableInfoRowView.make(in: tableView, text: "rows: ~200", isGroupRow: false) as? SATableInfoRowView)
        let value = try XCTUnwrap(cell.valueField)

        XCTAssertEqual(cell.textField?.stringValue, "Rows")
        XCTAssertEqual(value.stringValue, "~200")
        XCTAssertEqual(cell.textField?.textColor, .secondaryLabelColor)
        XCTAssertEqual(value.textColor, .labelColor)
        XCTAssertEqual(value.alignment, .right)
        XCTAssertEqual(value.lineBreakMode, .byTruncatingTail)
        XCTAssertTrue(value.allowsExpansionToolTips)
    }

    func testTextWithoutALabelUsesOneFullWidthField() throws {
        let cell = SATableInfoRowView.make(in: tableView, text: "multiple selection", isGroupRow: false)
        cell.frame = NSRect(x: 0, y: 0, width: 160, height: 24)
        cell.layoutSubtreeIfNeeded()

        let visibleFields = cell.subviews.compactMap { $0 as? NSTextField }.filter { !$0.isHidden && $0.frame.width > 0 }
        XCTAssertEqual(visibleFields.count, 1)
        XCTAssertTrue(visibleFields.first === cell.textField)
        XCTAssertEqual(cell.textField?.stringValue, "multiple selection")
        XCTAssertEqual(try XCTUnwrap(cell.textField).frame.maxX, cell.bounds.maxX, accuracy: 0.5)
    }

    func testLongValueNeverRunsIntoItsLabel() throws {
        let value = "utf8mb4 (utf8mb4_0900_ai_ci) on a server"
        XCTAssertEqual(value.count, 40)
        source.rows = ["TABLE INFORMATION", "encoding: \(value)"]

        for width in [120, 160, 240] as [CGFloat] {
            tableView.tableColumns[0].width = width
            tableView.frame.size.width = width
            tableView.reloadData()
            tableView.layoutSubtreeIfNeeded()

            let cell = try XCTUnwrap(tableView.view(atColumn: 0, row: 1, makeIfNecessary: true) as? SATableInfoRowView)
            cell.layoutSubtreeIfNeeded()
            let label = try XCTUnwrap(cell.textField)
            let valueField = try XCTUnwrap(cell.valueField)

            XCTAssertEqual(label.stringValue, "Encoding", "width \(width)")
            XCTAssertFalse(label.frame.intersects(valueField.frame), "width \(width)")
            XCTAssertGreaterThanOrEqual(valueField.frame.minX - label.frame.maxX, SATableInfoRowView.labelValueSpacing, "width \(width)")
            XCTAssertLessThanOrEqual(valueField.frame.maxX, cell.bounds.maxX, "width \(width)")
            // The label keeps its full width; the value gives way.
            XCTAssertGreaterThanOrEqual(label.frame.width, ceil(label.attributedStringValue.size().width), "width \(width)")
            XCTAssertGreaterThan(valueField.frame.width, 0, "width \(width)")
            XCTAssertEqual(valueField.font, label.font, "width \(width)")
        }
    }

    func testGroupTitleLinesUpWithTheLabels() throws {
        source.rows = ["TABLE INFORMATION", "rows: 200"]
        for style in [NSTableView.RowSizeStyle.small, .medium, .large] {
            tableView.rowSizeStyle = style
            tableView.reloadData()
            tableView.layoutSubtreeIfNeeded()

            let group = try XCTUnwrap(tableView.view(atColumn: 0, row: 0, makeIfNecessary: true) as? SATableInfoRowView)
            let pair = try XCTUnwrap(tableView.view(atColumn: 0, row: 1, makeIfNecessary: true) as? SATableInfoRowView)
            group.layoutSubtreeIfNeeded()
            pair.layoutSubtreeIfNeeded()

            let title = try XCTUnwrap(group.textField)
            let label = try XCTUnwrap(pair.textField)
            let titleX = tableView.convert(title.bounds, from: title).minX
            let labelX = tableView.convert(label.bounds, from: label).minX
            XCTAssertEqual(titleX, labelX, accuracy: 1, "row size style \(style.rawValue)")
            XCTAssertGreaterThan(labelX, 4, "row size style \(style.rawValue)")
        }
    }

    func testGroupTitleStaysWhereAppKitPutsItWithoutItemRows() throws {
        source.rows = ["TABLE INFORMATION"]
        tableView.reloadData()
        tableView.layoutSubtreeIfNeeded()

        let group = try XCTUnwrap(tableView.view(atColumn: 0, row: 0, makeIfNecessary: true) as? SATableInfoRowView)
        group.layoutSubtreeIfNeeded()
        XCTAssertEqual(try XCTUnwrap(group.textField).frame.minX, 0, accuracy: 0.5)
    }

    func testValueFollowsTheLabelsRowSizeStyle() throws {
        source.rows = ["TABLE INFORMATION", "rows: 200"]
        tableView.reloadData()
        tableView.layoutSubtreeIfNeeded()
        let cell = try XCTUnwrap(tableView.view(atColumn: 0, row: 1, makeIfNecessary: true) as? SATableInfoRowView)
        let value = try XCTUnwrap(cell.valueField)

        var sizes: [CGFloat] = []
        for style in [NSTableView.RowSizeStyle.small, .large] {
            cell.rowSizeStyle = style
            cell.layoutSubtreeIfNeeded()
            let labelSize = try XCTUnwrap(cell.textField?.font?.pointSize)
            XCTAssertEqual(value.font?.pointSize, labelSize, "row size style \(style.rawValue)")
            sizes.append(labelSize)
        }
        XCTAssertLessThan(sizes[0], sizes[1])
    }
}

/// A table that reports a chosen row as clicked, as a double-click would.
private final class ClickedRowTableView: NSTableView {
    var stubbedClickedRow = -1

    override var clickedRow: Int {
        stubbedClickedRow
    }
}

private final class StubSource: NSObject, NSTableViewDataSource {
    var rows = ["TABLE INFORMATION", "rows: 200", "multiple selection"]

    func numberOfRows(in tableView: NSTableView) -> Int {
        rows.count
    }

    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        rows[row]
    }
}
