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
        let all = [
            SADragPasteboard.tableRowType,
            SADragPasteboard.sslCipherType,
            SADragPasteboard.dragRowType,
            SADragPasteboard.navigatorSchemaPathsType,
            SADragPasteboard.navigatorTableDataType,
        ]

        XCTAssertEqual(Set(all).count, all.count, "pasteboard types must not collide")
    }

    /// The drag-out types are subject to the same UTI rule, and two of them are
    /// renames of legacy names ("SPNavigatorPasteboardDragType",
    /// "SPNavigatorTableDataPasteboardDragType") that would have been rejected.
    func testDragOutPasteboardTypesAreAcceptedByNSPasteboardItem() {
        for type in [SADragPasteboard.dragRowType,
                     SADragPasteboard.navigatorSchemaPathsType,
                     SADragPasteboard.navigatorTableDataType] {
            let item = SADragPasteboard.item(string: "payload", forType: type)

            XCTAssertEqual(item.types, [NSPasteboard.PasteboardType(type)], type)
            XCTAssertEqual(item.string(forType: NSPasteboard.PasteboardType(type)), "payload", type)
        }
    }

    // MARK: - Whole-drag payloads

    private func makePasteboard(_ name: String = #function) -> NSPasteboard {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("com.sequel-ace.tests.\(name)"))
        pasteboard.clearContents()
        return pasteboard
    }

    /// Writes `rows` marker items the way -pasteboardWriterForRow: does.
    @discardableResult
    private func writeMarkers(_ rows: Range<Int>, to pasteboard: NSPasteboard) -> Bool {
        pasteboard.writeObjects(rows.map { SADragPasteboard.dragRowItem(row: $0) })
    }

    func testDragRowItemCarriesOnlyTheMarkerType() {
        let item = SADragPasteboard.dragRowItem(row: 7)

        XCTAssertEqual(item.types, [NSPasteboard.PasteboardType(SADragPasteboard.dragRowType)])
        XCTAssertEqual(item.string(forType: NSPasteboard.PasteboardType(SADragPasteboard.dragRowType)), "7")
    }

    func testMarkerItemsPreserveRowOrder() {
        let pasteboard = makePasteboard()
        writeMarkers(0..<4, to: pasteboard)

        XCTAssertEqual(SADragPasteboard.strings(from: pasteboard, forType: SADragPasteboard.dragRowType),
                       ["0", "1", "2", "3"])
    }

    func testAttachedDragStringIsReadableUnderBothTextTypes() {
        let pasteboard = makePasteboard()
        writeMarkers(0..<3, to: pasteboard)

        XCTAssertTrue(SADragPasteboard.attach(dragString: "a\tb\nc\td", to: pasteboard))

        XCTAssertEqual(pasteboard.string(forType: .string), "a\tb\nc\td")
        XCTAssertEqual(pasteboard.string(forType: .tabularText), "a\tb\nc\td")
    }

    /// The reason the per-row items must stay marker-only.
    ///
    /// `NSPasteboard` concatenates `.string` across every item, joined with a
    /// newline — unlike `.tabularText` and custom types, which resolve to the
    /// first item alone. Had the per-row writer put each row's own text on its
    /// item, a receiver would read the whole-drag blob with every row's fragment
    /// appended after it.
    func testMarkerOnlyItemsDoNotAppendFragmentsToTheDragString() {
        let pasteboard = makePasteboard()
        writeMarkers(0..<3, to: pasteboard)
        SADragPasteboard.attach(dragString: "row0\nrow1\nrow2", to: pasteboard)

        XCTAssertEqual(pasteboard.string(forType: .string), "row0\nrow1\nrow2")

        // Demonstrate the failure mode being avoided.
        let contaminated = makePasteboard("contaminated")
        contaminated.clearContents()
        let items = (0..<3).map { row -> NSPasteboardItem in
            let item = NSPasteboardItem()
            item.setString("fragment\(row)", forType: .string)
            return item
        }
        contaminated.writeObjects(items)
        SADragPasteboard.attach(dragString: "WHOLE", to: contaminated)

        XCTAssertEqual(contaminated.string(forType: .string), "WHOLE\nfragment1\nfragment2")
    }

    func testAttachedPropertyListSurvivesRoundTrip() {
        let pasteboard = makePasteboard()
        writeMarkers(0..<2, to: pasteboard)
        let type = SPCellValuePasteboard.pasteboardRowTypeRaw

        XCTAssertTrue(SADragPasteboard.attach(propertyList: ["columnName": "id", "value": "7"],
                                              forType: type, to: pasteboard))

        let read = pasteboard.propertyList(forType: NSPasteboard.PasteboardType(type)) as? [String: String]
        XCTAssertEqual(read, ["columnName": "id", "value": "7"])
    }

    func testAttachedDataSurvivesRoundTrip() throws {
        let pasteboard = makePasteboard()
        writeMarkers(0..<2, to: pasteboard)
        let archive = try NSKeyedArchiver.archivedData(withRootObject: ["db\u{FFF8}tbl"],
                                                       requiringSecureCoding: true)

        XCTAssertTrue(SADragPasteboard.attach(data: archive,
                                              forType: SADragPasteboard.navigatorSchemaPathsType,
                                              to: pasteboard))

        let read = pasteboard.data(forType: NSPasteboard.PasteboardType(SADragPasteboard.navigatorSchemaPathsType))
        XCTAssertEqual(read, archive)
    }

    func testAttachedStringSurvivesRoundTrip() {
        let pasteboard = makePasteboard()
        writeMarkers(0..<1, to: pasteboard)
        let query = "CREATE TABLE IF NOT EXISTS `t` SELECT * FROM `db`.`t`"

        XCTAssertTrue(SADragPasteboard.attach(string: query,
                                              forType: SADragPasteboard.navigatorTableDataType,
                                              to: pasteboard))

        XCTAssertEqual(pasteboard.string(forType: NSPasteboard.PasteboardType(SADragPasteboard.navigatorTableDataType)),
                       query)
    }

    /// A writer that refused every row leaves nothing to hang the payload on.
    func testAttachingToAnEmptyPasteboardReportsFailure() {
        let pasteboard = makePasteboard()
        pasteboard.clearContents()

        XCTAssertFalse(SADragPasteboard.attach(dragString: "payload", to: pasteboard))
        XCTAssertFalse(SADragPasteboard.attach(string: "x", forType: SADragPasteboard.navigatorTableDataType, to: pasteboard))
        XCTAssertFalse(SADragPasteboard.attach(data: Data([1, 2]), forType: SADragPasteboard.navigatorSchemaPathsType, to: pasteboard))
        XCTAssertFalse(SADragPasteboard.attach(propertyList: ["a": "b"], forType: SPCellValuePasteboard.pasteboardRowTypeRaw, to: pasteboard))
    }

    /// Every payload for one drag lands on the same (first) item, so attaching
    /// several does not displace the earlier ones.
    func testMultiplePayloadsCoexistOnTheSameDrag() {
        let pasteboard = makePasteboard()
        writeMarkers(0..<3, to: pasteboard)

        SADragPasteboard.attach(dragString: "a\tb", to: pasteboard)
        SADragPasteboard.attach(propertyList: ["columnName": "id"],
                                forType: SPCellValuePasteboard.pasteboardRowTypeRaw, to: pasteboard)

        XCTAssertEqual(pasteboard.string(forType: .string), "a\tb")
        XCTAssertEqual(pasteboard.string(forType: .tabularText), "a\tb")
        XCTAssertNotNil(pasteboard.propertyList(forType: NSPasteboard.PasteboardType(SPCellValuePasteboard.pasteboardRowTypeRaw)))
        XCTAssertEqual(SADragPasteboard.strings(from: pasteboard, forType: SADragPasteboard.dragRowType).count, 3)
    }

    // MARK: - Payload field resolution

    func testSchemaPathStripsTheLeadingConnectionID() {
        let path = SADragPasteboard.schemaPath(fromKey: "conn123\u{FFF8}mydb\u{FFF8}mytable",
                                               delimiter: "\u{FFF8}")

        XCTAssertEqual(path, "mydb\u{FFF8}mytable")
    }

    /// The regex this replaced was non-greedy, so only the first segment goes.
    func testSchemaPathStripsOnlyTheFirstSegment() {
        XCTAssertEqual(SADragPasteboard.schemaPath(fromKey: "a/b/c", delimiter: "/"), "b/c")
    }

    func testSchemaPathLeavesAKeyWithoutADelimiterAlone() {
        XCTAssertEqual(SADragPasteboard.schemaPath(fromKey: "justaname", delimiter: "\u{FFF8}"),
                       "justaname")
    }

    func testSchemaPathHandlesATrailingDelimiter() {
        XCTAssertEqual(SADragPasteboard.schemaPath(fromKey: "conn\u{FFF8}", delimiter: "\u{FFF8}"), "")
    }

    func testSchemaPathWithAnEmptyDelimiterIsANoOp() {
        XCTAssertEqual(SADragPasteboard.schemaPath(fromKey: "conn\u{FFF8}db", delimiter: ""),
                       "conn\u{FFF8}db")
    }

    /// Splitting on the first occurrence also fixes a latent regex quirk: `.`
    /// does not match newlines in ICU, so `^.*?<delim>` left such a key
    /// unstripped.
    func testSchemaPathStripsEvenWhenTheKeyContainsANewline() {
        XCTAssertEqual(SADragPasteboard.schemaPath(fromKey: "co\nnn\u{FFF8}db", delimiter: "\u{FFF8}"),
                       "db")
    }

    func testClickedColumnResolvesThroughItsStorageIndex() {
        // Visible column 1 carries storage index 2.
        let name = SADragPasteboard.columnName(forClickedColumn: 1,
                                               identifiers: ["0", "2"],
                                               columnNames: ["id", "name", "email"])

        XCTAssertEqual(name, "email")
    }

    func testClickedColumnOutOfRangeResolvesToNothing() {
        XCTAssertNil(SADragPasteboard.columnName(forClickedColumn: 5,
                                                 identifiers: ["0"],
                                                 columnNames: ["id"]))
        XCTAssertNil(SADragPasteboard.columnName(forClickedColumn: -1,
                                                 identifiers: ["0"],
                                                 columnNames: ["id"]))
    }

    /// A stale storage index — the row reloaded under the drag — must resolve
    /// to nothing rather than to the wrong column.
    func testStorageIndexPastTheColumnListResolvesToNothing() {
        XCTAssertNil(SADragPasteboard.columnName(forClickedColumn: 0,
                                                 identifiers: ["9"],
                                                 columnNames: ["id"]))
    }

    /// `-valueForKey:` substitutes NSNull where a value is missing; that must
    /// read as "no column", not crash.
    func testNullEntriesResolveToNothing() {
        XCTAssertNil(SADragPasteboard.columnName(forClickedColumn: 0,
                                                 identifiers: [NSNull()],
                                                 columnNames: ["id"]))
        XCTAssertNil(SADragPasteboard.columnName(forClickedColumn: 0,
                                                 identifiers: ["0"],
                                                 columnNames: [NSNull()]))
    }

    /// ObjC `-integerValue` leniency: a non-numeric identifier yields 0.
    func testNonNumericIdentifierFallsBackToTheFirstColumn() {
        XCTAssertEqual(SADragPasteboard.columnName(forClickedColumn: 0,
                                                   identifiers: ["notanumber"],
                                                   columnNames: ["id", "name"]),
                       "id")
    }

    // MARK: - Rule-filter cell payload

    // Gates which drags advertise a droppable cell for the Content-tab filter.
    // Publishing an unresolved cell would synthesize a `col = \'\'` rule on drop.

    func testCellPayloadCarriesColumnValueAndKind() {
        let payload = SPCellValuePasteboard.rowPayload(columnName: "id", value: "7", isNull: false)

        XCTAssertEqual(payload?[SPCellValuePasteboard.rowColumnNameKey], "id")
        XCTAssertEqual(payload?[SPCellValuePasteboard.rowValueKey], "7")
        XCTAssertEqual(payload?[SPCellValuePasteboard.rowValueKindKey], SPCellValuePasteboard.rowValueKindString)
    }

    /// A NULL cell qualifies without a display value, so a drop can map it to
    /// `IS NULL` rather than the literal string.
    func testNullCellPayloadIsPublishedWithoutAValue() {
        let payload = SPCellValuePasteboard.rowPayload(columnName: "name", value: nil, isNull: true)

        XCTAssertEqual(payload?[SPCellValuePasteboard.rowValueKey], "")
        XCTAssertEqual(payload?[SPCellValuePasteboard.rowValueKindKey], SPCellValuePasteboard.rowValueKindNull)
    }

    func testCellPayloadIsRefusedWithoutAColumnName() {
        XCTAssertNil(SPCellValuePasteboard.rowPayload(columnName: nil, value: "7", isNull: false))
        XCTAssertNil(SPCellValuePasteboard.rowPayload(columnName: "", value: "7", isNull: false))
    }

    /// A nil display value on a non-NULL cell means the lookup failed.
    func testCellPayloadIsRefusedForAnUnresolvedNonNullCell() {
        XCTAssertNil(SPCellValuePasteboard.rowPayload(columnName: "id", value: nil, isNull: false))
    }

    func testEmptyCellValueStillQualifies() {
        // An empty string is a real value — only nil means "did not resolve".
        let payload = SPCellValuePasteboard.rowPayload(columnName: "id", value: "", isNull: false)

        XCTAssertEqual(payload?[SPCellValuePasteboard.rowValueKey], "")
        XCTAssertEqual(payload?[SPCellValuePasteboard.rowValueKindKey], SPCellValuePasteboard.rowValueKindString)
    }

    /// The payload must survive the pasteboard as a plist, which means every
    /// value has to be a property-list type.
    func testCellPayloadIsPropertyListEncodable() throws {
        let pasteboard = makePasteboard()
        writeMarkers(0..<1, to: pasteboard)
        let payload = try XCTUnwrap(SPCellValuePasteboard.rowPayload(columnName: "id", value: "7", isNull: false))

        XCTAssertTrue(SADragPasteboard.attach(propertyList: payload,
                                              forType: SPCellValuePasteboard.pasteboardRowTypeRaw,
                                              to: pasteboard))
        let read = pasteboard.propertyList(forType: NSPasteboard.PasteboardType(SPCellValuePasteboard.pasteboardRowTypeRaw)) as? [String: String]

        XCTAssertEqual(read, payload)
    }
}
