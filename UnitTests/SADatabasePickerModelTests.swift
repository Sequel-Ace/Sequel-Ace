//
//  SADatabasePickerModelTests.swift
//  Unit Tests
//
//  Tests for SADatabasePickerModel — reading the choose-database popup's
//  menu, filtering, highlight movement and the choose/cancel callbacks of
//  the searchable database picker.
//

import XCTest
import AppKit

final class SADatabasePickerModelTests: XCTestCase {

    private func configuredPopup(databases: [String], current: String?) -> NSPopUpButton {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        _ = SADatabaseListManager.configurePopup(popup,
                                                 databases: databases,
                                                 currentDatabase: current,
                                                 addDatabaseSelector: #selector(NSResponder.selectAll(_:)),
                                                 refreshDatabasesSelector: #selector(NSResponder.selectAll(_:)))
        return popup
    }

    private func entries(_ names: [String]) -> [SADatabasePickerEntry] {
        names.map { SADatabasePickerEntry(name: $0, section: 0) }
    }

    // MARK: - Reading the popup menu

    func testConfigurePopupTagsOnlyCommandItems() {
        let popup = configuredPopup(databases: ["mysql", "app"], current: nil)
        let tagged = popup.itemArray.filter { $0.tag == SADatabaseListManager.commandMenuItemTag }.map(\.title)
        XCTAssertEqual(tagged, [
            NSLocalizedString("Add Database...", comment: "menu item to add db"),
            NSLocalizedString("Refresh Databases", comment: "menu item to refresh databases"),
        ])
    }

    func testMenuSplitsCommandsAndSectionedDatabases() {
        let popup = configuredPopup(databases: ["mysql", "app", "sys", "analytics"], current: "app")
        let model = SADatabasePickerModel(menu: popup.menu, currentDatabase: "app")

        XCTAssertEqual(model.commands.count, 2)
        XCTAssertEqual(model.entries, [
            SADatabasePickerEntry(name: "mysql", section: 0),
            SADatabasePickerEntry(name: "sys", section: 0),
            SADatabasePickerEntry(name: "app", section: 1),
            SADatabasePickerEntry(name: "analytics", section: 1),
        ])
    }

    func testMenuWithOnlyUserDatabasesHasOneSection() {
        let popup = configuredPopup(databases: ["b", "a"], current: nil)
        let model = SADatabasePickerModel(menu: popup.menu, currentDatabase: nil)
        XCTAssertEqual(model.entries.map(\.section), [0, 0])
        XCTAssertEqual(model.entries.map(\.name), ["b", "a"])
    }

    func testMenuIncludesDatabasesAppendedAfterConfiguration() {
        // SADatabaseListManager.performSelection appends a database the
        // stale list didn't know about with a plain addItem(withTitle:).
        let popup = configuredPopup(databases: ["app"], current: nil)
        popup.addItem(withTitle: "late")
        let model = SADatabasePickerModel(menu: popup.menu, currentDatabase: nil)
        XCTAssertEqual(model.entries.map(\.name), ["app", "late"])
    }

    func testNilMenuIsEmpty() {
        let model = SADatabasePickerModel(menu: nil, currentDatabase: nil)
        XCTAssertTrue(model.entries.isEmpty)
        XCTAssertTrue(model.commands.isEmpty)
        XCTAssertNil(model.highlightedName)
    }

    // MARK: - Filtering

    func testFilterIsCaseDiacriticAndWidthInsensitiveSubstring() {
        let all = entries(["Sales_2024", "café_orders", "ＦＵＬＬ", "inventory"])
        XCTAssertEqual(SADatabasePickerModel.filter(all, query: "sales").map(\.name), ["Sales_2024"])
        XCTAssertEqual(SADatabasePickerModel.filter(all, query: "CAFE").map(\.name), ["café_orders"])
        XCTAssertEqual(SADatabasePickerModel.filter(all, query: "full").map(\.name), ["ＦＵＬＬ"])
        XCTAssertEqual(SADatabasePickerModel.filter(all, query: "or").map(\.name), ["café_orders", "inventory"])
    }

    func testBlankQueryKeepsEverythingInOrder() {
        let all = entries(["z", "a", "m"])
        XCTAssertEqual(SADatabasePickerModel.filter(all, query: "   "), all)
    }

    func testQueryUpdatesVisibleEntriesAndHighlight() {
        let model = SADatabasePickerModel(entries: entries(["shop", "shop_archive", "blog"]),
                                          commands: [],
                                          currentDatabase: "blog")
        XCTAssertEqual(model.highlightedName, "blog")

        model.query = "shop"
        XCTAssertEqual(model.visibleEntries.map(\.name), ["shop", "shop_archive"])
        XCTAssertEqual(model.highlightedName, "shop")

        model.query = "nothing"
        XCTAssertTrue(model.visibleEntries.isEmpty)
        XCTAssertNil(model.highlightedName)

        model.query = ""
        XCTAssertEqual(model.visibleEntries.count, 3)
        XCTAssertEqual(model.highlightedName, "blog")
    }

    func testExactMatchWinsHighlightOverEarlierSubstringMatch() {
        let model = SADatabasePickerModel(entries: entries(["app_logs", "app"]),
                                          commands: [],
                                          currentDatabase: nil)
        model.query = "APP"
        XCTAssertEqual(model.highlightedName, "app")
    }

    // MARK: - Keyboard

    func testMoveHighlightClampsToVisibleList() {
        let model = SADatabasePickerModel(entries: entries(["a", "b", "c"]), commands: [], currentDatabase: nil)
        XCTAssertEqual(model.highlightedName, "a")
        model.moveHighlight(by: -1)
        XCTAssertEqual(model.highlightedName, "a")
        model.moveHighlight(by: 1)
        model.moveHighlight(by: 1)
        model.moveHighlight(by: 1)
        XCTAssertEqual(model.highlightedName, "c")
    }

    func testChooseHighlightedReportsDatabase() {
        let model = SADatabasePickerModel(entries: entries(["a", "b"]), commands: [], currentDatabase: nil)
        var chosen: [String] = []
        model.onChooseDatabase = { chosen.append($0) }

        model.query = "b"
        model.chooseHighlighted()
        XCTAssertEqual(chosen, ["b"])

        model.query = "nothing"
        model.chooseHighlighted()
        XCTAssertEqual(chosen, ["b"])
    }

    func testCancelClearsQueryBeforeDismissing() {
        let model = SADatabasePickerModel(entries: entries(["a"]), commands: [], currentDatabase: nil)
        var cancelled = 0
        model.onCancel = { cancelled += 1 }

        model.query = "x"
        model.cancel()
        XCTAssertEqual(model.query, "")
        XCTAssertEqual(cancelled, 0)

        model.cancel()
        XCTAssertEqual(cancelled, 1)
    }
}
