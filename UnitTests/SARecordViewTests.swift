import XCTest

private final class SARecordViewTestTable: NSTableView {
    override var acceptsFirstResponder: Bool { true }
}

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

    func testDisplayValueKeepsLineBreaksAndFullValue() {
        let field = SARecordField(id: 0, name: "content", value: "first\nsecond\tthird")

        XCTAssertEqual(SAClaudeRecordFields.displayValue(field), .text("first\nsecond\tthird"))
        XCTAssertEqual(field.value, "first\nsecond\tthird")
    }

    func testDisplayValueLimitsLongValuesButNotTheStoredValue() {
        let field = SARecordField(id: 0, name: "content", value: String(repeating: "x", count: 150_000))

        guard case .text(let shown) = SAClaudeRecordFields.displayValue(field) else {
            return XCTFail("expected text")
        }
        XCTAssertEqual(shown.count, 100_001)
        XCTAssertTrue(shown.hasSuffix("…"))
        XCTAssertEqual(field.value.count, 150_000)
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

    func testDeferredValueUsesSnapshotLoadedWhileBeginningEdit() {
        let model = SARecordViewModel()
        let unloaded = SARecordField(id: 0, name: "content", value: "(not loaded)")
        let loaded = SARecordField(id: 0, name: "content", value: "real value")
        model.update(fields: [unloaded], selectedRowCount: 1)
        model.beginEditing = { _ in
            model.update(fields: [loaded], selectedRowCount: 1)
            return true
        }

        model.requestEdit(unloaded)

        XCTAssertEqual(model.editDraft, "real value")
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

    func testDraftValidationAcceptsReplacementAndRejectsInvalidChange() {
        let model = SARecordViewModel()
        let field = SARecordField(id: 0, name: "name", value: "Ada")
        model.beginEditing = { _ in true }
        model.validateEditing = { _, value in
            value == "invalid" ? nil : String(value.prefix(3))
        }
        model.requestEdit(field)

        model.updateEditDraft("Grace")
        XCTAssertEqual(model.editDraft, "Gra")

        model.updateEditDraft("invalid")
        XCTAssertEqual(model.editDraft, "Gra")
    }

    func testTableFocusRequestSelectsFirstVisibleField() {
        let model = SARecordViewModel()
        model.update(fields: fields, selectedRowCount: 1)
        model.searchText = "display"

        model.requestFocus(.table)

        XCTAssertEqual(model.selectedFieldID, 1)
        XCTAssertEqual(model.focusTarget, .table)
        XCTAssertEqual(model.focusRequestID, 1)

        model.requestFocus(.filter)

        XCTAssertEqual(model.focusTarget, .filter)
        XCTAssertEqual(model.focusRequestID, 2)

        model.searchText = "missing"
        XCTAssertFalse(model.canFocusTable)
    }

    func testSearchMatchesValuesAndCountsMatchingFields() {
        let model = SARecordViewModel()
        model.update(fields: fields, selectedRowCount: 1)

        model.searchText = "ada"

        XCTAssertEqual(model.visibleFields.map(\.id), [1])
        XCTAssertEqual(model.searchResult.matchCount, 1)
        XCTAssertEqual(model.searchResult.matches[1]?.valueRanges, [NSRange(location: 0, length: 3)])

        model.searchText = ""
        XCTAssertEqual(model.visibleFields, fields)
        XCTAssertEqual(model.searchResult.matchCount, 0)
        XCTAssertTrue(model.searchResult.matches.isEmpty)
    }

    func testSearchKeepsEditedFieldVisibleWithoutCountingIt() {
        let model = SARecordViewModel()
        model.update(fields: fields, selectedRowCount: 1)
        model.beginEditing = { _ in true }
        model.requestEdit(fields[0])

        model.searchText = "lovelace"

        XCTAssertEqual(model.visibleFields.map(\.id), [0, 2])
        XCTAssertEqual(model.searchResult.matchCount, 1)
    }

    func testUpdateShowsNewValuesForSameFieldIDs() {
        let model = SARecordViewModel()
        model.update(fields: fields, selectedRowCount: 1, rowIndex: 0, rowCount: 2, title: "t")
        XCTAssertEqual(model.display(for: model.fields[1]), .text("Ada"))
        model.searchText = "ada"
        XCTAssertEqual(model.visibleFields.map(\.id), [1])

        var edited = fields
        edited[1].value = "Grace"
        model.update(fields: edited, selectedRowCount: 1, rowIndex: 0, rowCount: 2, title: "t")

        XCTAssertEqual(model.display(for: model.fields[1]), .text("Grace"))
        XCTAssertEqual(model.visibleFields.map(\.id), [])
    }

    func testNullFieldDisplaysAsChipNotItsText() {
        let model = SARecordViewModel()
        let null = SARecordField(id: 0, name: "deleted_at", value: "NULL", isNull: true)
        let literal = SARecordField(id: 1, name: "note", value: "NULL")
        let empty = SARecordField(id: 2, name: "nick", value: "")
        model.update(fields: [null, literal, empty], selectedRowCount: 1)

        XCTAssertEqual(model.display(for: null), .null)
        XCTAssertEqual(model.display(for: literal), .text("NULL"))
        XCTAssertEqual(model.display(for: empty), .text(""))
    }

    func testExpansionBelongsToTheRow() {
        let model = SARecordViewModel()
        model.update(fields: fields, selectedRowCount: 1, rowIndex: 0, rowCount: 3, title: "t")
        model.toggleExpanded(2)
        XCTAssertTrue(model.isExpanded(2))

        model.update(fields: fields, selectedRowCount: 1, rowIndex: 0, rowCount: 3, title: "t")
        XCTAssertTrue(model.isExpanded(2), "a refresh of the same row keeps it")

        model.update(fields: fields, selectedRowCount: 1, rowIndex: 1, rowCount: 3, title: "t")
        XCTAssertFalse(model.isExpanded(2), "another row drops it")

        model.toggleExpanded(2)
        model.toggleExpanded(2)
        XCTAssertFalse(model.isExpanded(2))
    }

    func testListKeyFollowsRowAndColumns() {
        let model = SARecordViewModel()
        model.update(fields: fields, selectedRowCount: 1, rowIndex: 0, rowCount: 3, title: "t")
        let first = model.listKey

        var edited = fields
        edited[1].value = "Grace"
        model.update(fields: edited, selectedRowCount: 1, rowIndex: 0, rowCount: 3, title: "t")
        XCTAssertEqual(model.listKey, first, "a refreshed value keeps the list")

        model.update(fields: fields, selectedRowCount: 1, rowIndex: 1, rowCount: 3, title: "t")
        XCTAssertNotEqual(model.listKey, first)

        model.update(fields: [SARecordField(id: 0, name: "other", value: "1")], selectedRowCount: 1, rowIndex: 0, rowCount: 3, title: "t")
        XCTAssertNotEqual(model.listKey, first, "another result's columns at the same position")
    }

    func testUpdateKeepsSelectionOnlyWhileTheFieldExists() {
        let model = SARecordViewModel()
        model.update(fields: fields, selectedRowCount: 1, rowIndex: 0, rowCount: 3, title: "t")
        model.selectedFieldID = 2

        model.update(fields: fields, selectedRowCount: 1, rowIndex: 1, rowCount: 3, title: "t")
        XCTAssertEqual(model.selectedFieldID, 2)

        model.update(fields: Array(fields.prefix(2)), selectedRowCount: 1, rowIndex: 1, rowCount: 3, title: "t")
        XCTAssertNil(model.selectedFieldID)
    }

    func testMoveSelectionWalksVisibleFieldsWithoutWrapping() {
        let model = SARecordViewModel()
        model.update(fields: fields, selectedRowCount: 1)

        model.moveSelection(by: 1)
        XCTAssertEqual(model.selectedFieldID, 0, "without a selection, the first visible field")
        model.moveSelection(by: 1)
        model.moveSelection(by: 1)
        model.moveSelection(by: 1)
        XCTAssertEqual(model.selectedFieldID, 2)
        model.moveSelection(by: -1)
        XCTAssertEqual(model.selectedFieldID, 1)

        model.searchText = "display"
        model.moveSelection(by: -1)
        XCTAssertEqual(model.selectedFieldID, 1, "field 0 is hidden by the search")
        model.moveSelection(by: 1)
        XCTAssertEqual(model.selectedFieldID, 2)

        model.searchText = "id"
        model.moveSelection(by: 1)
        XCTAssertEqual(model.selectedFieldID, 0, "a hidden selection restarts at the first visible field")

        model.searchText = "missing"
        model.moveSelection(by: 1)
        XCTAssertEqual(model.selectedFieldID, 0)
    }

    func testReturnEditsSelectedVisibleField() {
        let model = SARecordViewModel()
        model.update(fields: fields, selectedRowCount: 1)
        model.beginEditing = { _ in true }

        model.editSelectedField()
        XCTAssertNil(model.editingFieldID)

        model.selectedFieldID = 2
        model.editSelectedField()
        XCTAssertEqual(model.editingFieldID, 2)
        XCTAssertEqual(model.editDraft, "Lovelace")
    }

    func testTypingOnSelectedBlockStartsSearch() {
        let model = SARecordViewModel()
        model.update(fields: fields, selectedRowCount: 1)

        model.typeIntoSearch("d")
        XCTAssertEqual(model.searchText, "", "nothing selected")

        model.selectedFieldID = 0
        model.typeIntoSearch("d")
        model.typeIntoSearch("i")
        XCTAssertEqual(model.searchText, "di")
        XCTAssertEqual(model.focusTarget, .filter)
        XCTAssertEqual(model.focusRequestID, 2)
    }

    func testEscapeInSearchClearsThenReturnsToGrid() {
        let model = SARecordViewModel()
        var gridFocus = 0
        model.focusGridHandler = { gridFocus += 1 }
        model.update(fields: fields, selectedRowCount: 1)
        model.searchText = "ada"

        model.escapeInSearch()
        XCTAssertEqual(model.searchText, "")
        XCTAssertEqual(gridFocus, 0)

        model.escapeInSearch()
        XCTAssertEqual(gridFocus, 1)
    }

    func testFocusingFieldsAndClickingABlockFocusThePanel() {
        let model = SARecordViewModel()
        var panelFocus = 0
        model.focusPanelHandler = { panelFocus += 1 }
        model.update(fields: fields, selectedRowCount: 1)

        model.requestFocus(.table)
        XCTAssertEqual(panelFocus, 1)
        model.requestFocus(.filter)
        XCTAssertEqual(panelFocus, 1)

        model.selectField(2)
        XCTAssertEqual(model.selectedFieldID, 2)
        XCTAssertEqual(panelFocus, 2)
    }

    func testPanelKeysOnTheFieldBlocks() {
        let recordView = NSView()
        let outside = NSView()
        func action(_ event: NSEvent, responder: NSResponder? = nil, visible: Bool = true,
                    editing: Bool = false, selection: Bool = true) -> SARecordViewPanelKey? {
            SARecordViewToolbarSupport.panelKeyAction(event, firstResponder: responder ?? recordView, recordView: recordView,
                                                      isRecordViewVisible: visible, isEditing: editing, hasSelection: selection)
        }
        let up = keyEvent(keyCode: 126, characters: "\u{F700}", modifiers: [.numericPad, .function])
        let down = keyEvent(keyCode: 125, characters: "\u{F701}", modifiers: [.numericPad, .function])
        let optionDown = keyEvent(keyCode: 125, characters: "\u{F701}", modifiers: [.numericPad, .function, .option])
        let optionUp = keyEvent(keyCode: 126, characters: "\u{F700}", modifiers: [.numericPad, .function, .option])
        let returnKey = keyEvent(keyCode: 36, characters: "\r")
        let letter = keyEvent(keyCode: 0, characters: "a")
        let capital = keyEvent(keyCode: 0, characters: "A", modifiers: .shift)

        XCTAssertEqual(action(up), .moveSelection(-1))
        XCTAssertEqual(action(down), .moveSelection(1))
        XCTAssertEqual(action(down, selection: false), .moveSelection(1))
        XCTAssertEqual(action(optionDown), .stepRow(1))
        XCTAssertEqual(action(optionUp), .stepRow(-1))
        XCTAssertEqual(action(returnKey), .editSelection)
        XCTAssertNil(action(returnKey, selection: false))
        XCTAssertEqual(action(letter), .search("a"))
        XCTAssertEqual(action(capital), .search("A"))
        XCTAssertNil(action(letter, selection: false))
        XCTAssertNil(action(keyEvent(keyCode: 0, characters: "a", modifiers: .command)))
        XCTAssertNil(action(keyEvent(keyCode: 0, characters: "a", modifiers: .control)))
        XCTAssertNil(action(keyEvent(keyCode: 48, characters: "\t")))
        XCTAssertNil(action(keyEvent(keyCode: 53, characters: "\u{1b}")))
        XCTAssertNil(action(keyEvent(keyCode: 51, characters: "\u{7f}")))
        XCTAssertNil(action(keyEvent(keyCode: 115, characters: "\u{F729}", modifiers: .function)))
        XCTAssertNil(action(down, visible: false))
        XCTAssertNil(action(down, responder: outside))
    }

    func testBlockKeysStandDownWhileEditing() {
        let recordView = NSView()
        func action(_ event: NSEvent) -> SARecordViewPanelKey? {
            SARecordViewToolbarSupport.panelKeyAction(event, firstResponder: recordView, recordView: recordView,
                                                      isRecordViewVisible: true, isEditing: true, hasSelection: true)
        }
        XCTAssertNil(action(keyEvent(keyCode: 36, characters: "\r")))
        XCTAssertNil(action(keyEvent(keyCode: 0, characters: "a")))
        XCTAssertNil(action(keyEvent(keyCode: 125, characters: "\u{F701}", modifiers: [.numericPad, .function])))
        XCTAssertNil(action(keyEvent(keyCode: 125, characters: "\u{F701}", modifiers: [.numericPad, .function, .option])))
    }

    func testOpenEditKeepsItsDraftAgainstBlockActions() {
        let model = SARecordViewModel()
        model.update(fields: fields, selectedRowCount: 1)
        model.beginEditing = { _ in true }
        model.commitEditing = { _, _ in false }
        model.selectedFieldID = 1
        model.editSelectedField()
        model.editDraft = "unsaved"

        model.editSelectedField()
        XCTAssertEqual(model.editingFieldID, 1)
        XCTAssertEqual(model.editDraft, "unsaved", "Return on the block doesn't restart the edit")

        model.typeIntoSearch("x")
        XCTAssertEqual(model.searchText, "", "typing doesn't start a search while editing")

        model.moveSelection(by: 1)
        XCTAssertEqual(model.selectedFieldID, 1)

        model.requestEdit(fields[1])
        XCTAssertEqual(model.editDraft, "unsaved", "editing the same field again keeps the draft")

        model.requestEdit(fields[2])
        XCTAssertEqual(model.editingFieldID, 1, "another field waits while the open edit's commit is refused")
        XCTAssertEqual(model.editDraft, "unsaved")
    }

    func testEditingAnotherFieldCommitsTheOpenEditFirst() {
        let model = SARecordViewModel()
        var committed: [(Int, String)] = []
        model.update(fields: fields, selectedRowCount: 1)
        model.beginEditing = { _ in true }
        model.commitEditing = { id, value in
            committed.append((id, value))
            return true
        }
        model.requestEdit(fields[1])
        model.editDraft = "Grace"

        model.requestEdit(fields[2])

        XCTAssertEqual(committed.map(\.0), [1])
        XCTAssertEqual(committed.map(\.1), ["Grace"])
        XCTAssertEqual(model.editingFieldID, 2)
        XCTAssertEqual(model.editDraft, "Lovelace")
    }

    func testFocusFromGridSelectsKeptFieldOrFirstVisible() {
        let model = SARecordViewModel()
        model.update(fields: fields, selectedRowCount: 1, rowIndex: 0, rowCount: 3, title: "t")
        model.selectedFieldID = 2
        model.update(fields: fields, selectedRowCount: 1, rowIndex: 1, rowCount: 3, title: "t")

        model.requestFocus(.table)
        XCTAssertEqual(model.selectedFieldID, 2, "the field kept across the row change")

        model.update(fields: Array(fields.prefix(2)), selectedRowCount: 1, rowIndex: 2, rowCount: 3, title: "t")
        model.requestFocus(.table)
        XCTAssertEqual(model.selectedFieldID, 0, "none kept: the first visible field")
    }

    func testPanelKeysInTheSearchFieldAndEditor() {
        let recordView = NSView()
        let field = NSTextView()
        recordView.addSubview(field)
        func action(_ event: NSEvent, editing: Bool = false) -> SARecordViewPanelKey? {
            SARecordViewToolbarSupport.panelKeyAction(event, firstResponder: field, recordView: recordView,
                                                      isRecordViewVisible: true, isEditing: editing, hasSelection: true)
        }
        let escape = keyEvent(keyCode: 53, characters: "\u{1b}")
        let down = keyEvent(keyCode: 125, characters: "\u{F701}", modifiers: [.numericPad, .function])
        let up = keyEvent(keyCode: 126, characters: "\u{F700}", modifiers: [.numericPad, .function])
        let optionUp = keyEvent(keyCode: 126, characters: "\u{F700}", modifiers: [.numericPad, .function, .option])

        XCTAssertEqual(action(escape), .escapeSearch)
        XCTAssertEqual(action(down), .focusFields)
        XCTAssertEqual(action(optionUp), .stepRow(-1))
        XCTAssertNil(action(up))
        XCTAssertNil(action(keyEvent(keyCode: 0, characters: "a")))
        XCTAssertNil(action(keyEvent(keyCode: 36, characters: "\r")))

        XCTAssertNil(action(escape, editing: true), "the inline editor keeps Escape (cancel)")
        XCTAssertNil(action(down, editing: true))
        XCTAssertNil(action(optionUp, editing: true))
    }

    func testRecordViewValidationUsesSelectionAwareFormatterRules() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.set("NULL", forKey: "NullValue")
        let formatter = SAUuidFormatter(userDefaults: defaults)

        XCTAssertEqual(SARecordViewEditSupport.validate("01234567", with: formatter), "01234567")
        XCTAssertNil(SARecordViewEditSupport.validate(String(repeating: "0", count: 33), with: formatter))
    }

    func testControllerExposesObjectiveCEditingSelector() {
        let controller = SARecordViewController()

        XCTAssertTrue(
            controller.responds(to: NSSelectorFromString("setEditingHandlersWithBegin:validate:commit:"))
        )
    }

    func testUpdateStoresRowFacts() {
        let model = SARecordViewModel()

        model.update(fields: fields, selectedRowCount: 1, rowIndex: 3, rowCount: 10, title: "users")

        XCTAssertEqual(model.rowIndex, 3)
        XCTAssertEqual(model.rowCount, 10)
        XCTAssertEqual(model.title, "users")

        model.update(fields: fields, selectedRowCount: 1)
        XCTAssertEqual(model.rowIndex, -1)
        XCTAssertEqual(model.rowCount, 0)
        XCTAssertEqual(model.title, "")
    }

    func testStepRowCallsHandlerOnlyWhenAllowed() {
        let model = SARecordViewModel()
        var steps: [Int] = []
        model.rowStepHandler = { steps.append($0) }

        model.update(fields: fields, selectedRowCount: 1, rowIndex: 0, rowCount: 3, title: "t")
        model.stepRow(-1)
        XCTAssertEqual(steps, [])
        model.stepRow(1)
        XCTAssertEqual(steps, [1])

        model.update(fields: fields, selectedRowCount: 1, rowIndex: 2, rowCount: 3, title: "t")
        model.stepRow(1)
        XCTAssertEqual(steps, [1])
        model.stepRow(-1)
        XCTAssertEqual(steps, [1, -1])

        model.update(fields: [], selectedRowCount: 0, rowIndex: -1, rowCount: 0, title: "t")
        model.stepRow(1)
        model.stepRow(-1)
        XCTAssertEqual(steps, [1, -1])
    }

    func testStepRowCommitsEditFirst() {
        let model = SARecordViewModel()
        var events: [String] = []
        model.beginEditing = { _ in true }
        model.commitEditing = { id, value in
            events.append("commit \(id) \(value)")
            return true
        }
        model.rowStepHandler = { events.append("step \($0)") }
        model.update(fields: fields, selectedRowCount: 1, rowIndex: 1, rowCount: 3, title: "t")
        model.requestEdit(fields[1])
        model.editDraft = "Grace"

        model.stepRow(1)

        XCTAssertEqual(events, ["commit 1 Grace", "step 1"])
        XCTAssertNil(model.editingFieldID)
    }

    func testStepRowStaysPutWhenCommitFails() {
        let model = SARecordViewModel()
        var steps: [Int] = []
        model.beginEditing = { _ in true }
        model.commitEditing = { _, _ in false }
        model.rowStepHandler = { steps.append($0) }
        model.update(fields: fields, selectedRowCount: 1, rowIndex: 1, rowCount: 3, title: "t")
        model.requestEdit(fields[1])

        model.stepRow(1)

        XCTAssertEqual(steps, [])
        XCTAssertEqual(model.editingFieldID, 1)
    }

    func testControllerExposesObjectiveCRowFactSelectors() {
        let controller = SARecordViewController()

        XCTAssertTrue(controller.responds(to: NSSelectorFromString("updateWithFields:selectedRowCount:rowIndex:rowCount:title:")))
        XCTAssertTrue(controller.responds(to: NSSelectorFromString("updateWithFields:selectedRowCount:")))
        XCTAssertTrue(controller.responds(to: NSSelectorFromString("setRowStepHandler:")))
    }

    func testControllerExposesObjectiveCShowHandlerSelector() {
        let controller = SARecordViewController()

        XCTAssertTrue(controller.responds(to: NSSelectorFromString("setShowHandler:")))
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
            shortcutTableView: NSTableView(),
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

    func testControllerCallsShowHandlerOnlyWhenOpening() {
        let parent = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let grid = NSView(frame: parent.bounds)
        parent.addSubview(grid)
        let controller = SARecordViewController()
        var showCount = 0
        controller.setShowHandler { showCount += 1 }
        controller.installOverlay(
            in: parent,
            resizing: grid,
            shortcutTableView: NSTableView(),
            bottomInset: 0,
            topInset: 0,
            autosaveName: "SARecordViewTestsShowHandlerWidth"
        )

        controller.toggle()
        XCTAssertEqual(showCount, 1)
        controller.toggle()
        XCTAssertEqual(showCount, 1)
        controller.toggle()
        XCTAssertEqual(showCount, 2)
    }

    func testClosingRecordViewRestoresResultTableFocus() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [],
            backing: .buffered,
            defer: false
        )
        let parent = NSView(frame: window.contentView!.bounds)
        let grid = NSView(frame: parent.bounds)
        let table = SARecordViewTestTable(frame: grid.bounds)
        let recordFocus = NSTableView()
        window.contentView = parent
        parent.addSubview(grid)
        parent.addSubview(recordFocus)
        grid.addSubview(table)
        let controller = SARecordViewController()
        controller.installOverlay(
            in: parent,
            resizing: grid,
            shortcutTableView: table,
            bottomInset: 0,
            topInset: 0,
            autosaveName: "SARecordViewTestsFocusWidth"
        )
        controller.toggle()
        XCTAssertTrue(window.makeFirstResponder(recordFocus))

        controller.toggle()

        XCTAssertTrue(
            window.firstResponder === table,
            "Expected result table, got \(String(describing: window.firstResponder))"
        )
    }

    func testToolbarHostIdentifierUsesActiveResultTab() {
        XCTAssertEqual(SARecordViewToolbarSupport.hostIdentifier(forTabIndex: 1), "SwitchToTableContentToolbarItemIdentifier")
        XCTAssertEqual(SARecordViewToolbarSupport.hostIdentifier(forTabIndex: 2), "SwitchToRunQueryToolbarItemIdentifier")
        XCTAssertNil(SARecordViewToolbarSupport.hostIdentifier(forTabIndex: 0))
        XCTAssertNil(SARecordViewToolbarSupport.hostIdentifier(forTabIndex: 3))
        XCTAssertNil(SARecordViewToolbarSupport.hostIdentifier(forTabIndex: -1))
    }

    func testSpaceShortcutAllowsResultTableAndRecordViewNonTextFocus() {
        let table = NSTableView()
        let recordView = NSView()
        let recordRow = NSView()
        let filter = NSSearchField()
        recordView.addSubview(recordRow)
        recordView.addSubview(filter)
        func spaceEvent(isRepeat: Bool) -> NSEvent {
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: " ",
                charactersIgnoringModifiers: " ",
                isARepeat: isRepeat,
                keyCode: 49
            )!
        }
        let space = spaceEvent(isRepeat: false)

        XCTAssertTrue(SARecordViewToolbarSupport.shouldHandleSpace(space, firstResponder: table, tableView: table, recordView: recordView))
        XCTAssertTrue(SARecordViewToolbarSupport.shouldHandleSpace(space, firstResponder: recordView, tableView: table, recordView: recordView))
        XCTAssertTrue(SARecordViewToolbarSupport.shouldHandleSpace(space, firstResponder: recordRow, tableView: table, recordView: recordView))
        XCTAssertFalse(SARecordViewToolbarSupport.shouldHandleSpace(space, firstResponder: filter, tableView: table, recordView: recordView))
        XCTAssertFalse(SARecordViewToolbarSupport.shouldHandleSpace(space, firstResponder: NSTextView(), tableView: table, recordView: recordView))
        XCTAssertFalse(SARecordViewToolbarSupport.shouldHandleSpace(space, firstResponder: NSView(), tableView: table, recordView: recordView))
        XCTAssertFalse(SARecordViewToolbarSupport.shouldHandleSpace(spaceEvent(isRepeat: true), firstResponder: table, tableView: table, recordView: recordView))
        XCTAssertFalse(SARecordViewToolbarSupport.shouldHandleSpace(space, firstResponder: nil, tableView: table, recordView: recordView))
    }

    func testArrowKeysMoveFocusBetweenResultAndRecordViews() {
        let table = NSTableView()
        let recordView = NSView()
        let recordRow = NSView()
        let inlineEditor = NSTextField()
        let outsideView = NSView()
        recordView.addSubview(recordRow)
        recordView.addSubview(inlineEditor)
        let right = keyEvent(keyCode: 124, characters: "\u{F703}")
        let left = keyEvent(keyCode: 123, characters: "\u{F702}")

        XCTAssertEqual(
            SARecordViewToolbarSupport.focusAction(
                right,
                firstResponder: table,
                tableView: table,
                recordView: recordView,
                isRecordViewVisible: true,
                canFocusRecordView: true
            ),
            .recordView
        )
        XCTAssertNil(SARecordViewToolbarSupport.focusAction(
            right,
            firstResponder: table,
            tableView: table,
            recordView: recordView,
            isRecordViewVisible: false,
            canFocusRecordView: true
        ))
        XCTAssertEqual(
            SARecordViewToolbarSupport.focusAction(
                left,
                firstResponder: recordRow,
                tableView: table,
                recordView: recordView,
                isRecordViewVisible: true,
                canFocusRecordView: true
            ),
            .resultTable
        )
        XCTAssertNil(SARecordViewToolbarSupport.focusAction(
            left,
            firstResponder: inlineEditor,
            tableView: table,
            recordView: recordView,
            isRecordViewVisible: true,
            canFocusRecordView: true
        ))
        XCTAssertNil(SARecordViewToolbarSupport.focusAction(
            left,
            firstResponder: outsideView,
            tableView: table,
            recordView: recordView,
            isRecordViewVisible: true,
            canFocusRecordView: true
        ))
    }

    func testCommandFFocusesFilterOnlyFromRecordFieldList() {
        let table = NSTableView()
        let recordView = NSView()
        let recordRow = NSView()
        let inlineEditor = NSTextField()
        recordView.addSubview(recordRow)
        recordView.addSubview(inlineEditor)
        let commandF = keyEvent(keyCode: 3, characters: "f", modifiers: .command)

        XCTAssertEqual(
            SARecordViewToolbarSupport.focusAction(
                commandF,
                firstResponder: recordRow,
                tableView: table,
                recordView: recordView,
                isRecordViewVisible: true,
                canFocusRecordView: true
            ),
            .filter
        )
        XCTAssertNil(SARecordViewToolbarSupport.focusAction(
            commandF,
            firstResponder: inlineEditor,
            tableView: table,
            recordView: recordView,
            isRecordViewVisible: true,
            canFocusRecordView: true
        ))
        XCTAssertNil(SARecordViewToolbarSupport.focusAction(
            commandF,
            firstResponder: table,
            tableView: table,
            recordView: recordView,
            isRecordViewVisible: true,
            canFocusRecordView: true
        ))
        XCTAssertNil(SARecordViewToolbarSupport.focusAction(
            keyEvent(keyCode: 124, characters: "\u{F703}", modifiers: .shift),
            firstResponder: table,
            tableView: table,
            recordView: recordView,
            isRecordViewVisible: true,
            canFocusRecordView: true
        ))
        XCTAssertNil(SARecordViewToolbarSupport.focusAction(
            keyEvent(keyCode: 124, characters: "\u{F703}", isRepeat: true),
            firstResponder: table,
            tableView: table,
            recordView: recordView,
            isRecordViewVisible: true,
            canFocusRecordView: true
        ))
    }

    func testToolbarItemTargetsRecordViewAction() {
        let item = SARecordViewToolbarSupport.makeToolbarItem(target: NSObject())

        XCTAssertEqual(item.itemIdentifier.rawValue, "RecordViewToolbarItemIdentifier")
        XCTAssertEqual(item.label, "Record View")
        XCTAssertEqual(item.action.map(NSStringFromSelector), "toggleRecordView:")
        XCTAssertNil(item.view)
    }

    /// Verifies fields resolve to their own column after columns were moved,
    /// where the on-screen position now names a different column.
    func testColumnMappingFollowsMovedColumns() {
        let table = makeResultTable(columnCount: 3)
        table.moveColumn(0, toColumn: 2)

        XCTAssertEqual(table.tableColumns.map(\.identifier.rawValue), ["1", "2", "0"])
        XCTAssertEqual(SARecordViewColumnMapping.tableColumn(forFieldID: 0, in: table)?.identifier.rawValue, "0")
        XCTAssertEqual(SARecordViewColumnMapping.tableColumn(forFieldID: 2, in: table)?.identifier.rawValue, "2")
    }

    /// Verifies a column hidden by the column filter resolves to no column, so
    /// an edit of its stale field is rejected instead of hitting a neighbour.
    func testColumnMappingRejectsHiddenAndInvalidFields() {
        let table = makeResultTable(columnCount: 3)
        table.removeTableColumn(table.tableColumns[1])

        XCTAssertNil(SARecordViewColumnMapping.tableColumn(forFieldID: 1, in: table))
        XCTAssertEqual(SARecordViewColumnMapping.tableColumn(forFieldID: 2, in: table)?.identifier.rawValue, "2")
        XCTAssertNil(SARecordViewColumnMapping.tableColumn(forFieldID: -1, in: table))
        XCTAssertNil(SARecordViewColumnMapping.tableColumn(forFieldID: 3, in: table))
    }

    /// Builds a result table whose column identifiers are data column indexes
    /// formatted the way SPTableData and SPMySQL write them.
    private func makeResultTable(columnCount: Int) -> NSTableView {
        let table = NSTableView()
        for index in 0..<columnCount {
            let identifier = String(format: "%llu", UInt64(index))
            table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier)))
        }
        return table
    }

    private func keyEvent(keyCode: UInt16,
                          characters: String,
                          modifiers: NSEvent.ModifierFlags = [],
                          isRepeat: Bool = false) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: isRepeat,
            keyCode: keyCode
        )!
    }
}
