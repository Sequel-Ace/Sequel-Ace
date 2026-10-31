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

    func testEscapeWithSearchDismissesWithoutChangingRule() throws {
        let (controller, editor) = try makeController()
        defer { editor.unbind(NSBindingName("rows")) }
        let picker = try XCTUnwrap(editor.displayValues(forRow: 0)[1] as? SAFieldPickerButton)
        let model = picker.makePickerModel()
        var cancelled = false
        model.onCancel = { cancelled = true }
        model.query = "EMAIL"
        model.cancel()
        XCTAssertTrue(cancelled)
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

    private func makeController(selectedName: String = "customer_name") throws -> (NSObject, NSRuleEditor) {
        let controllerClass = try XCTUnwrap(NSClassFromString("SPRuleFilterController") as? NSObject.Type)
        let controller = controllerClass.init()
        let editor = NSRuleEditor(frame: NSRect(x: 0, y: 0, width: 600, height: 120))
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
