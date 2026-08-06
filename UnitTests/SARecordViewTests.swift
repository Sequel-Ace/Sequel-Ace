import XCTest

final class SARecordViewTests: XCTestCase {

    private let fields = [
        SARecordField(id: 0, name: "id", value: "42"),
        SARecordField(id: 1, name: "display_name", value: "Ada"),
        SARecordField(id: 2, name: "display_name", value: "Lovelace")
    ]

    func testKeepsFieldsOnlyForSingleSelection() {
        let model = SARecordViewModel()

        model.update(fields: fields, selectedRowCount: 0)
        XCTAssertEqual(model.selectedRowCount, 0)
        XCTAssertEqual(model.fields, [])

        model.update(fields: fields, selectedRowCount: 2)
        XCTAssertEqual(model.selectedRowCount, 2)
        XCTAssertEqual(model.fields, [])

        model.update(fields: fields, selectedRowCount: 1)
        XCTAssertEqual(model.selectedRowCount, 1)
        XCTAssertEqual(model.fields, fields)
    }

    func testFiltersFieldNamesCaseInsensitively() {
        let model = SARecordViewModel()
        model.update(fields: fields, selectedRowCount: 1)

        model.searchText = " NAME "

        XCTAssertEqual(model.visibleFields.map(\.id), [1, 2])
    }

    func testPreservesOrderAndDuplicateNames() {
        let model = SARecordViewModel()
        model.update(fields: fields, selectedRowCount: 1)

        XCTAssertEqual(model.visibleFields, fields)
        XCTAssertEqual(model.visibleFields.map(\.value), ["42", "Ada", "Lovelace"])
    }

    func testClearRemovesSelectionAndFilter() {
        let model = SARecordViewModel()
        model.update(fields: fields, selectedRowCount: 1)
        model.searchText = "id"
        model.selectedFieldID = 0

        model.clear()

        XCTAssertEqual(model.selectedRowCount, 0)
        XCTAssertEqual(model.fields, [])
        XCTAssertEqual(model.searchText, "")
        XCTAssertNil(model.selectedFieldID)
    }

    func testPreviewFlattensWhitespaceWithoutChangingValue() {
        let field = SARecordField(id: 0, name: "content", value: "first\nsecond\tthird")

        XCTAssertEqual(field.previewValue, "first second third")
        XCTAssertEqual(field.value, "first\nsecond\tthird")
    }

    func testPreviewLimitsLongValues() {
        let field = SARecordField(id: 0, name: "content", value: String(repeating: "x", count: 5_000))

        XCTAssertEqual(field.previewValue.count, 4_097)
        XCTAssertTrue(field.previewValue.hasSuffix("…"))
    }

    func testBeginsAndCommitsInlineEdit() {
        let model = SARecordViewModel()
        let field = SARecordField(id: 2, name: "name", value: "Ada")
        var committed: (Int, String)?
        model.beginEditing = { $0 == 2 }
        model.commitEditing = { id, value in
            committed = (id, value)
            return true
        }

        model.requestEdit(field)
        XCTAssertEqual(model.editingFieldID, 2)
        XCTAssertEqual(model.focusedFieldID, 2)
        XCTAssertEqual(model.editDraft, "Ada")

        model.editDraft = "Grace"
        model.commitEdit()

        XCTAssertEqual(committed?.0, 2)
        XCTAssertEqual(committed?.1, "Grace")
        XCTAssertNil(model.editingFieldID)
    }

    func testLosingInlineEditorFocusCommitsEdit() {
        let model = SARecordViewModel()
        let field = SARecordField(id: 2, name: "name", value: "Ada")
        var committed: (Int, String)?
        model.beginEditing = { _ in true }
        model.commitEditing = { id, value in
            committed = (id, value)
            return true
        }
        model.requestEdit(field)
        model.editDraft = "Grace"

        model.editorFocusChanged(nil)

        XCTAssertEqual(committed?.0, 2)
        XCTAssertEqual(committed?.1, "Grace")
        XCTAssertNil(model.editingFieldID)
    }

    func testRejectedEditNeverCreatesDraft() {
        let model = SARecordViewModel()
        model.beginEditing = { _ in false }

        model.requestEdit(SARecordField(id: 0, name: "generated", value: "42"))

        XCTAssertNil(model.editingFieldID)
        XCTAssertEqual(model.editDraft, "")
    }

    func testCancelAndSnapshotRefreshDiscardDraft() {
        let model = SARecordViewModel()
        let field = SARecordField(id: 0, name: "name", value: "Ada")
        model.beginEditing = { _ in true }
        model.requestEdit(field)
        model.editDraft = "unsaved"

        model.update(fields: [field], selectedRowCount: 1)

        XCTAssertNil(model.editingFieldID)
        XCTAssertNil(model.focusedFieldID)
        XCTAssertEqual(model.editDraft, "")
    }

    func testFailedCommitKeepsDraftOpen() {
        let model = SARecordViewModel()
        let field = SARecordField(id: 0, name: "name", value: "Ada")
        model.beginEditing = { _ in true }
        model.commitEditing = { _, _ in false }
        model.requestEdit(field)
        model.editDraft = "invalid"

        model.commitEdit()

        XCTAssertEqual(model.editingFieldID, 0)
        XCTAssertEqual(model.editDraft, "invalid")
    }

    func testControllerExposesObjectiveCEditingSelector() {
        let controller = SARecordViewController()

        XCTAssertTrue(
            controller.responds(to: NSSelectorFromString("setEditingHandlersWithBegin:commit:"))
        )
    }

    func testControllerUsesExplicitFieldIDsWithPositionalFallback() {
        let fields = SARecordViewController.fields(from: [
            ["id": 4, "name": "explicit", "value": "a"],
            ["name": "fallback", "value": "b"]
        ])

        XCTAssertEqual(fields.map(\.id), [4, 1])
    }

    func testControllerTogglesVisibilityWithoutLocalButton() {
        let parent = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let grid = NSView(frame: parent.bounds)
        parent.addSubview(grid)
        let controller = SARecordViewController()

        controller.installOverlay(
            in: parent,
            resizing: grid,
            bottomInset: 0,
            topInset: 0,
            autosaveName: "SARecordViewTestsWidth"
        )

        XCTAssertFalse(controller.isVisible)
        controller.toggle()
        XCTAssertTrue(controller.isVisible)
        controller.toggle()
        XCTAssertFalse(controller.isVisible)
    }

    func testToolbarIsEnabledOnlyForContentAndQuery() {
        XCTAssertTrue(SARecordViewToolbarSupport.isEnabled(for: "SwitchToTableContentToolbarItemIdentifier"))
        XCTAssertTrue(SARecordViewToolbarSupport.isEnabled(for: "SwitchToRunQueryToolbarItemIdentifier"))
        XCTAssertFalse(SARecordViewToolbarSupport.isEnabled(for: "SwitchToTableStructureToolbarItemIdentifier"))
        XCTAssertFalse(SARecordViewToolbarSupport.isEnabled(for: nil))
    }

    func testToolbarHostIdentifierUsesActiveResultTab() {
        XCTAssertEqual(SARecordViewToolbarSupport.hostIdentifier(forTabIndex: 1), "SwitchToTableContentToolbarItemIdentifier")
        XCTAssertEqual(SARecordViewToolbarSupport.hostIdentifier(forTabIndex: 2), "SwitchToRunQueryToolbarItemIdentifier")
        XCTAssertNil(SARecordViewToolbarSupport.hostIdentifier(forTabIndex: 0))
        XCTAssertNil(SARecordViewToolbarSupport.hostIdentifier(forTabIndex: 3))
        XCTAssertNil(SARecordViewToolbarSupport.hostIdentifier(forTabIndex: -1))
    }

    func testToolbarInsertionFollowsQueryItem() {
        XCTAssertEqual(
            SARecordViewToolbarSupport.insertionIndex(in: [
                "SwitchToTableContentToolbarItemIdentifier",
                "SwitchToRunQueryToolbarItemIdentifier",
                "HistoryNavigationToolbarItemIdentifier"
            ]),
            2
        )
        XCTAssertEqual(SARecordViewToolbarSupport.insertionIndex(in: ["first", "second"]), 2)
    }

    func testToolbarMigrationOnlyInsertsOnceWhenMissing() {
        XCTAssertTrue(SARecordViewToolbarSupport.shouldAutoInsert(hasMigrated: false, containsItem: false))
        XCTAssertFalse(SARecordViewToolbarSupport.shouldAutoInsert(hasMigrated: false, containsItem: true))
        XCTAssertFalse(SARecordViewToolbarSupport.shouldAutoInsert(hasMigrated: true, containsItem: false))
    }

    func testToolbarItemTargetsRecordViewAction() {
        let item = SARecordViewToolbarSupport.makeToolbarItem(target: NSObject())

        XCTAssertEqual(item.itemIdentifier.rawValue, "RecordViewToolbarItemIdentifier")
        XCTAssertEqual(item.label, "Record View")
        XCTAssertEqual(item.action.map(NSStringFromSelector), "toggleRecordView:")
        XCTAssertNil(item.view)
    }

    func testRecordViewMenuTitleReflectsVisibility() {
        XCTAssertEqual(SARecordViewToolbarSupport.menuTitle(isVisible: false), "Show Record View")
        XCTAssertEqual(SARecordViewToolbarSupport.menuTitle(isVisible: true), "Hide Record View")
    }
}
