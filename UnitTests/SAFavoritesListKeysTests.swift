//
//  SAFavoritesListKeysTests.swift
//  Unit Tests
//
//  Pins the key decisions for the connection screen's favorites list:
//  Return/Enter handling and Escape while renaming a row.
//

import AppKit
import XCTest

/// Cell-based table with one editable text column and a single row.
private final class SAFavoritesKeysTestDataSource: NSObject, NSTableViewDataSource {
    var name = "Old"
    var setObjectValueCount = 0

    func numberOfRows(in tableView: NSTableView) -> Int { 1 }

    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        return name
    }

    func tableView(_ tableView: NSTableView, setObjectValue object: Any?, for tableColumn: NSTableColumn?, row: Int) {
        setObjectValueCount += 1
        name = object as? String ?? name
    }
}

/// Table delegate that records the field-editor commands AppKit routes to it and forwards them like
/// SAFavoritesListDataSource does.
private final class SAFavoritesKeysTestDelegate: NSObject, NSTableViewDelegate {
    var recordedSelectors: [String] = []

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        recordedSelectors.append(NSStringFromSelector(commandSelector))
        return SAFavoritesListKeys.handleEditingCommand(commandSelector, in: control)
    }
}

final class SAFavoritesListKeysTests: XCTestCase {

    private let returnKeyCodes: [UInt16] = [36, 76]

    // MARK: - Return / Enter

    func testReturnWithOneSelectedRowConnects() {
        for keyCode in returnKeyCodes {
            XCTAssertEqual(
                SAFavoritesListKeys.returnKeyAction(keyCode: keyCode, isARepeat: false, selectedRowCount: 1),
                .connect,
                "keyCode \(keyCode)"
            )
        }
    }

    func testAutoRepeatedReturnIsIgnored() {
        for keyCode in returnKeyCodes {
            XCTAssertEqual(
                SAFavoritesListKeys.returnKeyAction(keyCode: keyCode, isARepeat: true, selectedRowCount: 1),
                .ignore,
                "keyCode \(keyCode)"
            )
        }
    }

    func testReturnWithoutASingleSelectionPassesThrough() {
        for keyCode in returnKeyCodes {
            for rows in [0, 2] {
                for isARepeat in [false, true] {
                    XCTAssertEqual(
                        SAFavoritesListKeys.returnKeyAction(keyCode: keyCode, isARepeat: isARepeat, selectedRowCount: rows),
                        .passThrough,
                        "keyCode \(keyCode), rows \(rows), repeat \(isARepeat)"
                    )
                }
            }
        }
    }

    func testOtherKeysPassThrough() {
        for keyCode: UInt16 in [0, 48, 53, 35] {
            for isARepeat in [false, true] {
                XCTAssertEqual(
                    SAFavoritesListKeys.returnKeyAction(keyCode: keyCode, isARepeat: isARepeat, selectedRowCount: 1),
                    .passThrough,
                    "keyCode \(keyCode), repeat \(isARepeat)"
                )
            }
        }
    }

    // MARK: - Escape while renaming

    private func makeEditingTable() -> (NSWindow, NSTableView, SAFavoritesKeysTestDataSource) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
            styleMask: [],
            backing: .buffered,
            defer: false
        )
        let table = NSTableView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        column.width = 280
        column.isEditable = true
        column.dataCell = NSTextFieldCell(textCell: "")
        (column.dataCell as? NSTextFieldCell)?.isEditable = true
        table.addTableColumn(column)
        table.headerView = nil
        let dataSource = SAFavoritesKeysTestDataSource()
        table.dataSource = dataSource
        window.contentView?.addSubview(table)
        table.reloadData()
        return (window, table, dataSource)
    }

    func testEscapeWhileRenamingCancelsTheEdit() throws {
        let (window, table, dataSource) = makeEditingTable()
        withExtendedLifetime(dataSource) {
            XCTAssertTrue(window.makeFirstResponder(table))
            table.editColumn(0, row: 0, with: nil, select: true)
            XCTAssertEqual(table.editedRow, 0, "precondition: edit is open")
            let editor = table.currentEditor() as? NSTextView
            XCTAssertNotNil(editor, "precondition: field editor is active")
            editor?.insertText("New", replacementRange: editor?.selectedRange() ?? NSRange(location: 0, length: 0))
            XCTAssertEqual(editor?.string, "New", "precondition: text was typed")

            XCTAssertTrue(SAFavoritesListKeys.handleEditingCommand(#selector(NSResponder.cancelOperation(_:)), in: table))

            XCTAssertEqual(table.editedRow, -1)
            XCTAssertEqual(dataSource.setObjectValueCount, 0)
            XCTAssertEqual(dataSource.name, "Old")
            XCTAssertTrue(window.firstResponder === table, "Expected table, got \(String(describing: window.firstResponder))")
        }
    }

    func testEscapeReachesTheDelegateThroughTheFieldEditor() {
        let (window, table, dataSource) = makeEditingTable()
        let delegate = SAFavoritesKeysTestDelegate()
        table.delegate = delegate
        withExtendedLifetime((dataSource, delegate)) {
            XCTAssertTrue(window.makeFirstResponder(table))
            table.editColumn(0, row: 0, with: nil, select: true)
            XCTAssertEqual(table.editedRow, 0, "precondition: edit is open")
            let editor = table.currentEditor() as? NSTextView
            XCTAssertNotNil(editor, "precondition: field editor is active")
            editor?.insertText("New", replacementRange: editor?.selectedRange() ?? NSRange(location: 0, length: 0))
            XCTAssertEqual(editor?.string, "New", "precondition: text was typed")

            editor?.doCommand(by: #selector(NSResponder.cancelOperation(_:)))

            XCTAssertEqual(delegate.recordedSelectors, ["cancelOperation:"])
            XCTAssertEqual(table.editedRow, -1)
            XCTAssertEqual(dataSource.setObjectValueCount, 0)
            XCTAssertEqual(dataSource.name, "Old")
            XCTAssertTrue(window.firstResponder === table, "Expected table, got \(String(describing: window.firstResponder))")
        }
    }

    func testOtherEditingCommandsAreNotHandled() {
        let (window, table, dataSource) = makeEditingTable()
        withExtendedLifetime(dataSource) {
            XCTAssertTrue(window.makeFirstResponder(table))
            table.editColumn(0, row: 0, with: nil, select: true)
            XCTAssertEqual(table.editedRow, 0, "precondition: edit is open")

            XCTAssertFalse(SAFavoritesListKeys.handleEditingCommand(#selector(NSResponder.insertNewline(_:)), in: table))

            XCTAssertEqual(table.editedRow, 0, "edit is still open")
            table.abortEditing()
        }
    }
}
