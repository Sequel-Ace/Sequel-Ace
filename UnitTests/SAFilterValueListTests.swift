import AppKit
import XCTest

final class SAFilterValueListTests: XCTestCase {
    func testQuotedListPreservesEmptyItemsAndNumericLookingText() {
        XCTAssertEqual(SAFilterValueList.quotedSQL(from: "abc, 001, O'Brien, ,"),
                       "'abc', '001', 'O''Brien', '', ''")
    }

    func testModeAndEncodingSensitiveTextUsesCharacterLiterals() {
        XCTAssertEqual(SAFilterValueList.quotedSQL(from: "a,\u{0301}b"), "'a', _utf8mb4 X'CC8162'")
        XCTAssertEqual(SAFilterValueList.quotedSQL(from: "a\\b, a\u{0}b, 한, 😀"),
                       "_utf8mb4 X'615C62', _utf8mb4 X'610062', _utf8mb4 X'ED959C', _utf8mb4 X'F09F9880'")
    }

    func testEmptyInputProducesAnEmptyStringLiteral() {
        XCTAssertEqual(SAFilterValueList.quotedSQL(from: ""), "''")
        XCTAssertEqual(SAFilterValueList.quotedSQL(from: ", ,"), "'', '', ''")
    }

    private func makeEditor(group: String) throws -> (NSObject, NSRuleEditor) {
        let controllerType = try XCTUnwrap(NSClassFromString("SPRuleFilterController") as? NSObject.Type)
        let controller = controllerType.init()
        let editor = NSRuleEditor(frame: NSRect(x: 0, y: 0, width: 700, height: 120))
        editor.delegate = controller as? NSRuleEditorDelegate
        controller.setValue(editor, forKey: "filterRuleEditor")
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

        let (controller, editor) = try makeEditor(group: "string")
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

            let checkbox = try XCTUnwrap(list.subviews.compactMap { $0 as? NSButton }.first)
            checkbox.performClick(nil)
            XCTAssertEqual(list.checked, !checked)
            XCTAssertEqual(defaults.bool(forKey: key), !checked)
            checkbox.performClick(nil)
            XCTAssertEqual(defaults.bool(forKey: key), checked)

            try chooseOperator("=")
            XCTAssertNil(editor.displayValues(forRow: 0).last as? SAFilterListInput)
            try chooseOperator("IN")
            XCTAssertEqual((editor.displayValues(forRow: 0).last as? SAFilterListInput)?.checked, checked)
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

    func testPreviewAndApplyFormatTheSameListWithoutCheckingTheConnection() throws {
        let (controller, editor) = try makeEditor(group: "string")
        defer { editor.unbind(NSBindingName("rows")) }
        let box = try XCTUnwrap(controller.value(forKey: "dropBox") as? SPRuleFilterDropBox)
        let leaf: [String: Any] = ["filterClass": "expressionNode", "column": "code", "filterComparison": "IN",
                                   "filterValues": ["abc"], "quoteEachValue": true]
        controller.perform(NSSelectorFromString("restoreSerializedFilters:"), with: leaf)
        let field = try XCTUnwrap((editor.displayValues(forRow: 0).last as? SAFilterListInput)?.field)
        let edit = Notification(name: NSControl.textDidChangeNotification, object: field)
        for (input, list) in [(#"O'Brien, a\b"#, #"'O''Brien', _utf8mb4 X'615C62'"#),
                              ("😀", "_utf8mb4 X'F09F9880'"), (",,", "'', '', ''")] {
            field.stringValue = input
            controller.perform(NSSelectorFromString("controlTextDidChange:"), with: edit)
            let clause = "`code` IN (\(list))"
            XCTAssertEqual(try whereClause(of: controller), clause)
            XCTAssertEqual(box.toolTip?.components(separatedBy: "\n").first, "WHERE " + clause)
        }
    }

    func testRestoredRulesUseTheirOwnQuoteSettingAndColumnType() throws {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: "SAQuoteEachFilterValue")
        defer { defaults.set(previous, forKey: "SAQuoteEachFilterValue") }
        defaults.set(true, forKey: "SAQuoteEachFilterValue")

        for (group, op, saved, expectedBox) in [
            ("string", "IN", nil as Bool?, false as Bool?),
            ("textdata", "NOT IN __ OR NULL", true, true),
            ("enum", "NOT IN __ OR NULL", true, true),
            ("binary", "IN", true, nil),
            ("string", "=", true, nil),
            ("integer", "IN", true, nil),
            ("blobdata", "IN", true, nil),
        ] {
            let (controller, editor) = try makeEditor(group: group)
            defer { editor.unbind(NSBindingName("rows")) }
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
                               ? #"(`code` NOT IN ('abc', 'O''Brien') OR `code` IS NULL)"#
                               : "`code` IN ('abc,def,ghi')")
            }
        }
    }
}
