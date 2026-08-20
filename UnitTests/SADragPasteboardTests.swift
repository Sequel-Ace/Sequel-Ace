//
//  SADragPasteboardTests.swift
//  Unit Tests
//
//  Created as part of the deprecated drag-API migration.
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import AppKit
import XCTest

final class SADragPasteboardTests: XCTestCase {

    // Must be UTI-conformant, like the shipped types — see the pinning test below.
    private let type = "com.sequel-ace.tests.drag"

    // MARK: - Writing and reading

    func testItemCarriesTheStringUnderTheGivenType() {
        let item = SADragPasteboard.item(string: "DHE-RSA-AES256-SHA", forType: type)

        XCTAssertEqual(item.string(forType: NSPasteboard.PasteboardType(type)), "DHE-RSA-AES256-SHA")
    }

    func testItemForRowCarriesTheRowIndexAsAString() {
        XCTAssertEqual(
            SADragPasteboard.item(row: 7, forType: type).string(forType: NSPasteboard.PasteboardType(type)),
            "7"
        )
    }

    /// The drop side reads the items back in row order, replacing the single
    /// archived collection the deprecated write API produced.
    func testStringsAreReadBackInItemOrder() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("SADragPasteboardTests.order"))
        pasteboard.clearContents()
        pasteboard.writeObjects([
            SADragPasteboard.item(string: "first", forType: type),
            SADragPasteboard.item(string: "second", forType: type),
            SADragPasteboard.item(string: "third", forType: type),
        ])

        XCTAssertEqual(SADragPasteboard.strings(from: pasteboard, forType: type), ["first", "second", "third"])
    }

    func testItemsWithoutTheTypeAreSkipped() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("SADragPasteboardTests.mixed"))
        pasteboard.clearContents()

        let other = NSPasteboardItem()
        other.setString("ignored", forType: .string)
        pasteboard.writeObjects([SADragPasteboard.item(string: "kept", forType: type), other])

        XCTAssertEqual(SADragPasteboard.strings(from: pasteboard, forType: type), ["kept"])
    }

    func testAnEmptyPasteboardYieldsNoStrings() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("SADragPasteboardTests.empty"))
        pasteboard.clearContents()

        XCTAssertEqual(SADragPasteboard.strings(from: pasteboard, forType: type), [])
    }

    // MARK: - Multi-row refusal (SPTableStructure field reorder)

    func testDraggingAnUnselectedRowIsAllowedEvenWithAMultiRowSelection() {
        // AppKit drags just that row, so there is nothing to refuse.
        XCTAssertFalse(SADragPasteboard.refusesMultiRowDrag(row: 9, selectedRows: IndexSet([2, 3])))
    }

    func testDraggingOneOfSeveralSelectedRowsIsRefused() {
        let selection = IndexSet([2, 3])

        XCTAssertTrue(SADragPasteboard.refusesMultiRowDrag(row: 2, selectedRows: selection))
        XCTAssertTrue(SADragPasteboard.refusesMultiRowDrag(row: 3, selectedRows: selection))
    }

    func testDraggingTheOnlySelectedRowIsAllowed() {
        XCTAssertFalse(SADragPasteboard.refusesMultiRowDrag(row: 2, selectedRows: IndexSet([2])))
        XCTAssertFalse(SADragPasteboard.refusesMultiRowDrag(row: 2, selectedRows: IndexSet()))
    }

    // MARK: - Excluded-row refusal (SSL cipher list marker)

    func testTheExcludedRowItselfIsRefused() {
        XCTAssertTrue(SADragPasteboard.refusesDrag(row: 4, selectedRows: IndexSet([4]), excludedRow: 4))
        // …even when it isn't selected.
        XCTAssertTrue(SADragPasteboard.refusesDrag(row: 4, selectedRows: IndexSet(), excludedRow: 4))
    }

    func testASelectionContainingTheExcludedRowIsRefusedEntirely() {
        let selection = IndexSet([1, 4, 6])

        XCTAssertTrue(SADragPasteboard.refusesDrag(row: 1, selectedRows: selection, excludedRow: 4))
        XCTAssertTrue(SADragPasteboard.refusesDrag(row: 6, selectedRows: selection, excludedRow: 4))
    }

    func testASelectionWithoutTheExcludedRowIsAllowed() {
        let selection = IndexSet([1, 6])

        XCTAssertFalse(SADragPasteboard.refusesDrag(row: 1, selectedRows: selection, excludedRow: 4))
        XCTAssertFalse(SADragPasteboard.refusesDrag(row: 6, selectedRows: selection, excludedRow: 4))
    }

    func testDraggingAnUnselectedRowIgnoresTheExcludedRowInTheSelection() {
        // Only the dragged row travels, so a selected marker elsewhere is irrelevant.
        XCTAssertFalse(SADragPasteboard.refusesDrag(row: 9, selectedRows: IndexSet([4]), excludedRow: 4))
    }

    /// `indexOfObject:` returns NSNotFound when the list has no marker at all.
    func testAMissingExcludedRowRefusesNothing() {
        XCTAssertFalse(SADragPasteboard.refusesDrag(row: 3, selectedRows: IndexSet([3]), excludedRow: NSNotFound))
    }

    // MARK: - Type names

    /// The shipped types must be valid UTIs. NSPasteboardItem refuses anything
    /// else — it logs "not a valid UTI string", stores nothing, and the drag then
    /// carries an empty item while every API involved still reports success. The
    /// legacy names these drags used before the migration ("SequelProPasteboard",
    /// "SSLCipherPboardType") failed exactly that way.
    func testShippedPasteboardTypesAreAcceptedByNSPasteboardItem() {
        for type in [SADragPasteboard.tableRowType, SADragPasteboard.sslCipherType] {
            let item = SADragPasteboard.item(string: "payload", forType: type)

            XCTAssertEqual(item.types, [NSPasteboard.PasteboardType(type)], type)
            XCTAssertEqual(item.string(forType: NSPasteboard.PasteboardType(type)), "payload", type)
        }
    }

    func testShippedPasteboardTypesAreDistinct() {
        XCTAssertNotEqual(SADragPasteboard.tableRowType, SADragPasteboard.sslCipherType)
    }
}
