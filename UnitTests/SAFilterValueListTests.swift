import AppKit
import SPMySQL
import XCTest

final class SAFilterValueListTests: XCTestCase {
    func testQuotedListPassesEachTrimmedItemToConnectionQuoter() {
        var received: [String] = []
        let result = SAFilterValueList.quotedSQL(from: "abc, 001, O'Brien, ,") { value in
            received.append(value)
            return "'\(value.replacingOccurrences(of: "'", with: "''"))'"
        }
        XCTAssertEqual(received, ["abc", "001", "O'Brien", "", ""])
        XCTAssertEqual(result, "'abc', '001', 'O''Brien', '', ''")
    }

    func testOneUnquotableValueRefusesTheWholeList() {
        XCTAssertNil(SAFilterValueList.quotedSQL(from: "a,b") { $0 == "a" ? "'a'" : nil })
    }
}

private final class SAListFilterTestConnection: SPMySQLConnection {
    var connectionChecks = 0
    var checkedOnMainThread = false

    override func checkIfNecessary() -> Bool {
        connectionChecks += 1
        checkedOnMainThread = checkedOnMainThread || Thread.isMainThread
        return true
    }
}

private final class SAListFilterTestDocument: NSObject {
    let connection = SAListFilterTestConnection()

    override init() {
        super.init()
        connection.setValue(SPMySQLConnected.rawValue, forKey: "state")
    }

    deinit { connection.setValue(SPMySQLDisconnected.rawValue, forKey: "state") }

    @objc var fileURL: URL? { nil }
    @objc func getConnection() -> SPMySQLConnection { connection }
}

extension SAFilterValueListTests {
    private func makeEditor(group: String, document: SAListFilterTestDocument) throws -> (NSObject, NSRuleEditor) {
        let controllerType = try XCTUnwrap(NSClassFromString("SPRuleFilterController") as? NSObject.Type)
        let controller = controllerType.init()
        let editor = NSRuleEditor(frame: NSRect(x: 0, y: 0, width: 700, height: 120))
        editor.delegate = controller as? NSRuleEditorDelegate
        controller.setValue(editor, forKey: "filterRuleEditor")
        controller.setValue(document, forKey: "tableDocumentInstance")
        let columns = ["code", "label"].map { ["name": $0, "typegrouping": group] }
        controller.perform(NSSelectorFromString("setColumns:"), with: columns)
        controller.perform(NSSelectorFromString("awakeFromNib"))
        return (controller, editor)
    }

    func testEditingAListKeepsItsQuoteChoiceUntilLeavingTheListOperators() throws {
        let defaults = UserDefaults.standard
        let key = "SAQuoteEachFilterValue"
        let previous = defaults.object(forKey: key)
        defer { defaults.set(previous, forKey: key) }

        let document = SAListFilterTestDocument()
        let (controller, editor) = try makeEditor(group: "string", document: document)
        defer { editor.unbind(NSBindingName("rows")) }
        func chooseOperator(_ title: String) throws {
            let current = try XCTUnwrap(editor.displayValues(forRow: 0)[2] as? NSMenuItem)
            let menu = try XCTUnwrap(current.menu)
            let item = try XCTUnwrap(menu.item(withTitle: title))
            menu.performActionForItem(at: menu.index(of: item))
            XCTAssertEqual((editor.displayValues(forRow: 0)[2] as? NSMenuItem)?.title, title)
        }

        for checked in [false, true] {
            defaults.set(!checked, forKey: key)
            let input = checked ? "abc,def,ghi" : "'abc,def,ghi'"
            let leaf: [String: Any] = ["filterClass": "expressionNode", "column": "code", "filterComparison": "IN",
                                       "filterValues": [input], "quoteEachValue": checked]
            controller.perform(NSSelectorFromString("restoreSerializedFilters:"), with: leaf)
            let picker = try XCTUnwrap(editor.displayValues(forRow: 0)[1] as? SAFieldPickerButton)
            picker.selectItem(withTitle: "label")
            XCTAssertTrue(picker.sendAction(picker.action, to: picker.target))
            XCTAssertEqual((editor.displayValues(forRow: 0)[1] as? SAFieldPickerButton)?.titleOfSelectedItem, "label")
            XCTAssertEqual((editor.displayValues(forRow: 0).last as? SAFilterListInput)?.checked, checked)
            try chooseOperator("NOT IN __ OR NULL")
            let list = try XCTUnwrap(editor.displayValues(forRow: 0).last as? SAFilterListInput)
            XCTAssertEqual(list.checked, checked)
            XCTAssertEqual(list.field.stringValue, input)

            try chooseOperator("=")
            XCTAssertNil(editor.displayValues(forRow: 0).last as? SAFilterListInput)
            try chooseOperator("IN")
            XCTAssertEqual((editor.displayValues(forRow: 0).last as? SAFilterListInput)?.checked, !checked)
        }
    }

    private func whereClause(of controller: NSObject) throws -> String? {
        let selector = NSSelectorFromString("sqlWhereExpressionWithBinary:error:")
        typealias Render = @convention(c) (NSObject, Selector, Bool, NSErrorPointer) -> NSString?
        let render = unsafeBitCast(controller.method(for: selector), to: Render.self)
        var error: NSError?
        let sql = render(controller, selector, false, &error) as String?
        if let error { throw error }
        return sql
    }

    func testTypingQuotesOfflineAndApplyChecksTheConnectionAgain() throws {
        let document = SAListFilterTestDocument()
        let (controller, editor) = try makeEditor(group: "string", document: document)
        defer { editor.unbind(NSBindingName("rows")) }
        let box = try XCTUnwrap(controller.value(forKey: "dropBox") as? SPRuleFilterDropBox)
        let leaf: [String: Any] = ["filterClass": "expressionNode", "column": "code", "filterComparison": "IN",
                                   "filterValues": ["abc"], "quoteEachValue": true]
        controller.perform(NSSelectorFromString("restoreSerializedFilters:"), with: leaf)
        let field = try XCTUnwrap((editor.displayValues(forRow: 0).last as? SAFilterListInput)?.field)
        field.stringValue = #"O'Brien, a\b"#
        let edit = Notification(name: NSControl.textDidChangeNotification, object: field)
        controller.perform(NSSelectorFromString("controlTextDidChange:"), with: edit)
        let clause = #"`code` IN ('O\'Brien', 'a\\b')"#
        XCTAssertEqual(box.toolTip?.components(separatedBy: "\n").first, "WHERE " + clause)

        document.connection.setValue(SASessionReplacementMark.whenNothingIsOpen.rawValue, forKey: "sessionReplacement")
        controller.perform(NSSelectorFromString("controlTextDidChange:"), with: edit)
        XCTAssertFalse(box.isShowingPreview)
        document.connection.setValue(SASessionReplacementMark.notMarked.rawValue, forKey: "sessionReplacement")

        // Losing the session clears the last preview without trying to reconnect.
        document.connection.setValue(SPMySQLConnectionLostInBackground.rawValue, forKey: "state")
        controller.perform(NSSelectorFromString("controlTextDidChange:"), with: edit)
        XCTAssertFalse(box.isShowingPreview)
        XCTAssertEqual(document.connection.connectionChecks, 0)

        document.connection.setValue(SPMySQLConnected.rawValue, forKey: "state")
        let selector = NSSelectorFromString("filterRequestWithBinary:")
        typealias Capture = @convention(c) (NSObject, Selector, Bool) -> SATableFilterRequest
        let capture = unsafeBitCast(controller.method(for: selector), to: Capture.self)
        let request = capture(controller, selector, false)
        XCTAssertTrue(request.requiresConnection)
        XCTAssertEqual(document.connection.connectionChecks, 0)
        field.stringValue = "edited after Apply"

        let rendered = expectation(description: "Filter rendered on the load thread")
        DispatchQueue.global().async {
            var error: NSError?
            XCTAssertEqual(request.sql(error: &error), clause)
            XCTAssertNil(error)
            rendered.fulfill()
        }
        wait(for: [rendered], timeout: 5)
        XCTAssertGreaterThan(document.connection.connectionChecks, 0)
        XCTAssertFalse(document.connection.checkedOnMainThread)
    }

    func testRestoredRulesUseTheirOwnQuoteSettingAndColumnType() throws {
        let document = SAListFilterTestDocument()
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: "SAQuoteEachFilterValue")
        defer { defaults.set(previous, forKey: "SAQuoteEachFilterValue") }
        defaults.set(true, forKey: "SAQuoteEachFilterValue")

        for (group, op, saved, expectedBox) in [
            ("string", "IN", nil as Bool?, false as Bool?),
            ("textdata", "NOT IN __ OR NULL", true, true),
            ("string", "=", true, nil),
            ("integer", "IN", true, nil),
            ("blobdata", "IN", true, nil),
        ] {
            let (controller, editor) = try makeEditor(group: group, document: document)
            let input = saved == nil ? "'abc,def,ghi'" : "abc, O'Brien"
            var leaf: [String: Any] = ["filterClass": "expressionNode", "column": "code", "filterComparison": op, "filterValues": [input]]
            leaf["quoteEachValue"] = saved
            controller.perform(NSSelectorFromString("restoreSerializedFilters:"), with: leaf)
            let box = editor.displayValues(forRow: 0).last as? SAFilterListInput
            XCTAssertEqual(box?.checked, expectedBox, "\(group) \(op)")
            let stored = controller.perform(NSSelectorFromString("serializedFilter"))?.takeUnretainedValue() as? [String: Any]
            XCTAssertEqual(stored?["quoteEachValue"] as? Bool, expectedBox == true ? true : nil)
            if let expectedBox {
                let sql = try whereClause(of: controller)
                XCTAssertEqual(sql, expectedBox
                               ? #"(`code` NOT IN ('abc', 'O\'Brien') OR `code` IS NULL)"#
                               : "`code` IN ('abc,def,ghi')")
            }
        }
    }
}
