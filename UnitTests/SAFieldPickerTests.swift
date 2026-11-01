import AppKit
import XCTest

final class SAFieldPickerTests: XCTestCase {
    func testWideTablePickerKeepsItsControlWidthBoundedAndSearchesEveryField() {
        let names = (0..<64).map { "customer_\($0)_" + String(repeating: "x", count: 100) }
        let picker = SAFieldPickerButton(names: names, nodes: names, selectedName: names[0])
        XCTAssertLessThanOrEqual(picker.frame.width, 220)
        XCTAssertGreaterThan(picker.frame.height, 0)
        let model = picker.makePickerModel()
        model.query = "_63_"
        XCTAssertEqual(model.visibleEntries.map(\.name), [names[63]])
        model.chooseHighlighted()
        XCTAssertEqual(picker.titleOfSelectedItem, names[63])
    }

    func testContentFilterColumnUsesSearchableControl() throws {
        let (controller, editor) = try makeController()
        defer { editor.unbind(NSBindingName("rows")) }
        let picker = try XCTUnwrap(editor.displayValues(forRow: 0)[1] as? SAFieldPickerButton)
        XCTAssertEqual(picker.itemTitles, ["customer_name", "customer_email", "billing_email"])
        XCTAssertNotNil(controller)
    }

    func testRuleEditorEmbedsTheSearchableControlInsteadOfBuildingAnotherMenu() throws {
        let (controller, editor) = try makeController()
        defer { editor.unbind(NSBindingName("rows")) }
        let picker = try XCTUnwrap(editor.displayValues(forRow: 0)[1] as? SAFieldPickerButton)
        editor.layoutSubtreeIfNeeded()
        XCTAssertTrue(picker.isDescendant(of: editor), "The rule editor must install the searchable control, not wrap column alternatives in its own native menu")
        XCTAssertNotNil(controller)
    }

    func testOpeningPickerFocusesItsSearchField() throws {
        let (controller, editor) = try makeController()
        defer { editor.unbind(NSBindingName("rows")) }
        let window = NSWindow(contentRect: editor.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = editor
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        let picker = try XCTUnwrap(editor.displayValues(forRow: 0)[1] as? SAFieldPickerButton)
        picker.performClick(nil)
        let focused = expectation(description: "Popover has completed presentation")
        DispatchQueue.main.async { focused.fulfill() }
        wait(for: [focused], timeout: 2)
        let popover = try XCTUnwrap(picker.pickerPopover)
        let popoverWindow = try XCTUnwrap(popover.contentViewController?.view.window)
        let fieldEditor = try XCTUnwrap(popoverWindow.firstResponder as? NSTextView)
        let searchField = try XCTUnwrap(fieldEditor.delegate as? NSSearchField)
        XCTAssertEqual(searchField.placeholderString, "Search Fields")
        fieldEditor.insertText("EMAIL", replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertEqual(searchField.stringValue, "EMAIL")
        XCTAssertEqual(searchField.delegate?.control?(searchField, textView: fieldEditor,
                                                      doCommandBy: #selector(NSResponder.moveDown(_:))), true)
        XCTAssertEqual(searchField.delegate?.control?(searchField, textView: fieldEditor,
                                                      doCommandBy: #selector(NSResponder.insertNewline(_:))), true)
        XCTAssertEqual(try serializedFilter(controller)["column"] as? String, "billing_email")
    }

    func testSearchSelectsSubstringAndPreservesOperatorAndValue() throws {
        let (controller, editor) = try makeController()
        defer { editor.unbind(NSBindingName("rows")) }
        let picker = try XCTUnwrap(editor.displayValues(forRow: 0)[1] as? SAFieldPickerButton)
        let model = picker.makePickerModel()
        model.query = "EMAIL"
        XCTAssertEqual(model.visibleEntries.map(\.name), ["customer_email", "billing_email"])
        model.moveHighlight(by: 1)
        model.chooseHighlighted()

        let saved = try serializedFilter(controller)
        XCTAssertEqual(saved["column"] as? String, "billing_email")
        XCTAssertEqual(saved["filterComparison"] as? String, "contains")
        XCTAssertEqual(saved["filterValues"] as? [String], ["example"])
        XCTAssertEqual((editor.displayValues(forRow: 0)[1] as? SAFieldPickerButton)?.titleOfSelectedItem, "billing_email")
    }

    func testFirstFieldIsSearchableAndSelectable() throws {
        let (controller, editor) = try makeController(selectedName: "billing_email")
        defer { editor.unbind(NSBindingName("rows")) }
        let picker = try XCTUnwrap(editor.displayValues(forRow: 0)[1] as? SAFieldPickerButton)
        let model = picker.makePickerModel()
        model.query = "NAME"
        model.chooseHighlighted()
        XCTAssertEqual(try serializedFilter(controller)["column"] as? String, "customer_name")
    }

    func testReloadCriteriaPreservesSelectedLaterField() throws {
        let (controller, editor) = try makeController()
        defer { editor.unbind(NSBindingName("rows")) }
        let originalPicker = try XCTUnwrap(editor.displayValues(forRow: 0)[1] as? SAFieldPickerButton)
        let model = originalPicker.makePickerModel()
        model.query = "billing"
        model.chooseHighlighted()
        let before = try serializedFilter(controller) as NSDictionary

        editor.reloadCriteria()

        XCTAssertEqual(try serializedFilter(controller) as NSDictionary, before)
        let picker = try XCTUnwrap(editor.displayValues(forRow: 0)[1] as? SAFieldPickerButton)
        XCTAssertEqual(picker.titleOfSelectedItem, "billing_email")
        XCTAssertTrue(picker.isDescendant(of: editor))
    }

    func testReloadCriteriaPreservesDifferentFieldsInNestedAndDisabledRows() throws {
        let (controller, editor) = try makeController()
        defer { editor.unbind(NSBindingName("rows")) }
        editor.nestingMode = .compound
        var disabledRule = savedRule(selectedName: "customer_email")
        disabledRule["enabled"] = false
        let filters: [String: Any] = [
            "filterClass": "groupNode", "isConjunction": false,
            "children": [
                disabledRule,
                ["filterClass": "groupNode", "isConjunction": true,
                 "children": [savedRule(selectedName: "billing_email"), savedRule(selectedName: "customer_name")]]
            ]
        ]
        controller.perform(NSSelectorFromString("restoreSerializedFilters:"), with: filters)
        let before = try serializedFilter(controller) as NSDictionary

        controller.perform(NSSelectorFromString("_contentFiltersHaveBeenUpdated:"), with: nil)

        XCTAssertEqual(try serializedFilter(controller) as NSDictionary, before)
        let pickers = (0..<editor.numberOfRows).compactMap { row -> SAFieldPickerButton? in
            guard editor.rowType(forRow: row) == .simple else { return nil }
            return editor.displayValues(forRow: row)[1] as? SAFieldPickerButton
        }
        XCTAssertEqual(pickers.map(\.titleOfSelectedItem), ["customer_email", "billing_email", "customer_name"])
        XCTAssertTrue(pickers.allSatisfy { $0.isDescendant(of: editor) })
    }

    func testUpdatingContentFiltersPreservesSelectedLaterField() throws {
        let (controller, editor) = try makeController(selectedName: "billing_email")
        defer { editor.unbind(NSBindingName("rows")) }
        let before = try serializedFilter(controller) as NSDictionary

        controller.perform(NSSelectorFromString("_contentFiltersHaveBeenUpdated:"), with: nil)

        XCTAssertEqual(try serializedFilter(controller) as NSDictionary, before)
        let picker = try XCTUnwrap(editor.displayValues(forRow: 0)[1] as? SAFieldPickerButton)
        XCTAssertEqual(picker.titleOfSelectedItem, "billing_email")
        XCTAssertTrue(picker.isDescendant(of: editor))
    }

    func testSelectedFieldLookupReadsRowsLinearly() throws {
        let editor = SACountingFieldRuleEditor(frame: NSRect(x: 0, y: 0, width: 600, height: 120))
        let (controller, _) = try makeController(editor: editor)
        defer { editor.unbind(NSBindingName("rows")) }
        editor.nestingMode = .compound
        let rules = (0..<24).map { savedRule(selectedName: $0.isMultiple(of: 2) ? "customer_email" : "billing_email") }
        controller.perform(NSSelectorFromString("restoreSerializedFilters:"), with: [
            "filterClass": "groupNode", "isConjunction": true, "children": rules
        ])
        let criteria = (0..<editor.numberOfRows).filter { editor.rowType(forRow: $0) == .simple }
            .map { editor.criteria(forRow: $0) }
        editor.criteriaReadCount = 0

        for row in criteria {
            let selected = editor.delegate?.ruleEditor(editor, child: 0, forCriterion: row[0], with: .simple)
            XCTAssertTrue((selected as AnyObject?) === (row[1] as AnyObject))
        }

        XCTAssertEqual(criteria.count, 24)
        XCTAssertLessThanOrEqual(editor.criteriaReadCount, editor.numberOfRows * 3,
                                "Selection lookup should build one row index, not scan every row for each field")
    }

    func testIndexedLookupUsesCurrentSelectionAndReplacementRows() throws {
        let (controller, editor) = try makeController()
        defer { editor.unbind(NSBindingName("rows")) }
        editor.reloadCriteria()
        let picker = try XCTUnwrap(editor.displayValues(forRow: 0)[1] as? SAFieldPickerButton)
        let model = picker.makePickerModel()
        model.query = "billing"
        model.chooseHighlighted()

        editor.reloadCriteria()
        XCTAssertEqual(try serializedFilter(controller)["column"] as? String, "billing_email")

        // A new enable criterion at the same row index must replace the cached identity.
        controller.perform(NSSelectorFromString("restoreSerializedFilters:"), with: savedRule(selectedName: "customer_email"))
        editor.reloadCriteria()
        XCTAssertEqual(try serializedFilter(controller)["column"] as? String, "customer_email")
    }

    func testIndexedLookupSurvivesRowRemoval() throws {
        let (controller, editor) = try makeController()
        defer { editor.unbind(NSBindingName("rows")) }
        editor.nestingMode = .compound
        controller.perform(NSSelectorFromString("restoreSerializedFilters:"), with: [
            "filterClass": "groupNode", "isConjunction": true,
            "children": [savedRule(selectedName: "customer_name"), savedRule(selectedName: "billing_email"),
                         savedRule(selectedName: "customer_email")]
        ])
        editor.reloadCriteria()
        let firstRow = try XCTUnwrap((0..<editor.numberOfRows).first { editor.rowType(forRow: $0) == .simple })
        editor.removeRows(at: IndexSet(integer: firstRow), includeSubrows: true)
        let before = try serializedFilter(controller) as NSDictionary

        editor.reloadCriteria()

        XCTAssertEqual(try serializedFilter(controller) as NSDictionary, before)
        let fields = (0..<editor.numberOfRows).compactMap {
            (editor.displayValues(forRow: $0)[1] as? SAFieldPickerButton)?.titleOfSelectedItem
        }
        XCTAssertEqual(fields, ["billing_email", "customer_email"])
    }

    func testDisablingControllerPreventsPendingPickerSelection() throws {
        let (controller, editor) = try makeController()
        defer { editor.unbind(NSBindingName("rows")) }
        let picker = try XCTUnwrap(editor.displayValues(forRow: 0)[1] as? SAFieldPickerButton)
        let model = picker.makePickerModel()
        model.query = "billing"
        controller.setValue(false, forKey: "enabled")
        XCTAssertFalse(editor.isEnabled)

        model.chooseHighlighted()

        XCTAssertEqual(try serializedFilter(controller)["column"] as? String, "customer_name")
        XCTAssertFalse(picker.accessibilityPerformPress())
    }

    func testSpaceKeyOpensSearchablePopover() throws {
        let (controller, editor) = try makeController()
        defer { editor.unbind(NSBindingName("rows")) }
        let window = NSWindow(contentRect: editor.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = editor
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        let picker = try XCTUnwrap(editor.displayValues(forRow: 0)[1] as? SAFieldPickerButton)
        window.makeFirstResponder(picker)
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                                 timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                                 characters: " ", charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49))
        // Bound the test if AppKit falls back to the native menu's tracking loop.
        let cancelNativeMenu = Timer(timeInterval: 0.25, repeats: false) { _ in picker.menu?.cancelTracking() }
        RunLoop.main.add(cancelNativeMenu, forMode: .common)
        defer { cancelNativeMenu.invalidate(); picker.pickerPopover?.close() }

        picker.keyDown(with: event)

        XCTAssertEqual(picker.pickerPopover?.isShown, true)
        XCTAssertEqual(try serializedFilter(controller)["column"] as? String, "customer_name")
    }

    func testEscapeWithSearchDismissesWithoutChangingRule() throws {
        let (controller, editor) = try makeController()
        defer { editor.unbind(NSBindingName("rows")) }
        let window = NSWindow(contentRect: editor.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = editor
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        let picker = try XCTUnwrap(editor.displayValues(forRow: 0)[1] as? SAFieldPickerButton)
        picker.performClick(nil)
        let presented = expectation(description: "Popover has completed presentation")
        DispatchQueue.main.async { presented.fulfill() }
        wait(for: [presented], timeout: 2)
        let popover = try XCTUnwrap(picker.pickerPopover)
        let popoverWindow = try XCTUnwrap(popover.contentViewController?.view.window)
        let fieldEditor = try XCTUnwrap(popoverWindow.firstResponder as? NSTextView)
        let searchField = try XCTUnwrap(fieldEditor.delegate as? NSSearchField)
        fieldEditor.insertText("EMAIL", replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertEqual(searchField.delegate?.control?(searchField, textView: fieldEditor,
                                                      doCommandBy: #selector(NSResponder.cancelOperation(_:))), true)
        XCTAssertFalse(popover.isShown)
        XCTAssertNil(picker.pickerPopover)
        XCTAssertEqual(try serializedFilter(controller)["column"] as? String, "customer_name")
    }

    func testNoMatchDoesNotChangeRule() throws {
        let (controller, editor) = try makeController()
        defer { editor.unbind(NSBindingName("rows")) }
        let picker = try XCTUnwrap(editor.displayValues(forRow: 0)[1] as? SAFieldPickerButton)
        let model = picker.makePickerModel()
        model.query = "missing"
        model.chooseHighlighted()
        XCTAssertTrue(model.visibleEntries.isEmpty)
        XCTAssertEqual(try serializedFilter(controller)["column"] as? String, "customer_name")
    }

    func testDisabledControlCannotCommitPendingSelection() throws {
        let (controller, editor) = try makeController()
        defer { editor.unbind(NSBindingName("rows")) }
        let picker = try XCTUnwrap(editor.displayValues(forRow: 0)[1] as? SAFieldPickerButton)
        let model = picker.makePickerModel()
        model.query = "EMAIL"
        picker.isEnabled = false
        model.chooseHighlighted()
        XCTAssertEqual(try serializedFilter(controller)["column"] as? String, "customer_name")
    }

    func testChoosingFromRemovedRowDoesNotChangeReplacementRule() throws {
        let (controller, editor) = try makeController()
        defer { editor.unbind(NSBindingName("rows")) }
        let picker = try XCTUnwrap(editor.displayValues(forRow: 0)[1] as? SAFieldPickerButton)
        let model = picker.makePickerModel()
        model.query = "EMAIL"
        controller.perform(NSSelectorFromString("restoreSerializedFilters:"), with: savedRule(selectedName: "billing_email"))
        model.chooseHighlighted()
        XCTAssertEqual(try serializedFilter(controller)["column"] as? String, "billing_email")
    }

    private func savedRule(selectedName: String) -> [String: Any] {
        ["filterClass": "expressionNode", "column": selectedName, "filterType": "string",
         "filterComparison": "contains", "filterValues": ["example"], "enabled": true]
    }

    private func serializedFilter(_ controller: NSObject) throws -> [String: Any] {
        try XCTUnwrap(controller.perform(NSSelectorFromString("serializedFilter"))?.takeUnretainedValue() as? [String: Any])
    }

    private func makeController(selectedName: String = "customer_name",
                                editor: NSRuleEditor = NSRuleEditor(frame: NSRect(x: 0, y: 0, width: 600, height: 120))) throws -> (NSObject, NSRuleEditor) {
        let controllerClass = try XCTUnwrap(NSClassFromString("SPRuleFilterController") as? NSObject.Type)
        let controller = controllerClass.init()
        editor.delegate = controller as? NSRuleEditorDelegate
        controller.setValue(editor, forKey: "filterRuleEditor")
        let model = try XCTUnwrap(controller.value(forKey: "_modelContainer"))
        editor.bind(NSBindingName("rows"), to: model, withKeyPath: "model", options: nil)
        controller.perform(NSSelectorFromString("setColumns:"), with: [
            ["name": "customer_name", "typegrouping": "string"],
            ["name": "customer_email", "typegrouping": "string"],
            ["name": "billing_email", "typegrouping": "string"]
        ])
        controller.setValue(true, forKey: "enabled")
        controller.perform(NSSelectorFromString("restoreSerializedFilters:"), with: savedRule(selectedName: selectedName))
        XCTAssertEqual(editor.numberOfRows, 1)
        return (controller, editor)
    }
}

private final class SACountingFieldRuleEditor: NSRuleEditor {
    var criteriaReadCount = 0

    override func criteria(forRow row: Int) -> [Any] {
        criteriaReadCount += 1
        return super.criteria(forRow: row)
    }
}
