//
//  SPTableContentColumnFilterTests.swift
//  Unit Tests
//
//  Created for Sequel-Ace column filter feature.
//  Copyright © 2020-2022 Sequel-Ace. All rights reserved.
//

import XCTest

/// Tests for the column filter functionality in SPTableContent.
/// Tests the comma-separated filter term parsing and column name matching logic.
final class SPTableContentColumnFilterTests: XCTestCase {

    // MARK: - Filter Term Parsing Tests

    /// Test parsing comma-separated terms with whitespace handling
    func testParseFilterTerms() {
        // Single term
        XCTAssertEqual(parseFilterTerms("id"), ["id"])

        // Multiple comma-separated terms
        XCTAssertEqual(parseFilterTerms("id, name, created"), ["id", "name", "created"])

        // Whitespace is trimmed
        XCTAssertEqual(parseFilterTerms("  id  ,  name  "), ["id", "name"])

        // Empty terms are ignored
        XCTAssertEqual(parseFilterTerms("id,,name,,,created"), ["id", "name", "created"])

        // Empty/whitespace-only returns empty array
        XCTAssertEqual(parseFilterTerms(""), [])
        XCTAssertEqual(parseFilterTerms("   "), [])
    }

    // MARK: - Column Matching Tests

    /// Test column name matching with single and multiple terms
    func testColumnMatching() {
        // Single term matching (substring, case-insensitive)
        XCTAssertTrue(columnMatches("user_id", terms: ["user"]))
        XCTAssertTrue(columnMatches("USER_ID", terms: ["user"]))
        XCTAssertFalse(columnMatches("created_at", terms: ["user"]))

        // Multiple terms use OR logic - matches if ANY term matches
        let terms = ["id", "name"]
        XCTAssertTrue(columnMatches("user_id", terms: terms))
        XCTAssertTrue(columnMatches("first_name", terms: terms))
        XCTAssertFalse(columnMatches("created_at", terms: terms))
    }

    // MARK: - Regression Guardrails

    /// Ensure the app defaults include the autofill heuristic workaround used for Tahoe lag regressions.
    func testAutoFillHeuristicControllerDisabledByDefault() {
        guard let defaults = preferenceDefaultsDictionary() else {
            XCTFail("Could not find PreferenceDefaults.plist in any loaded bundle")
            return
        }

        let value = defaults["NSAutoFillHeuristicControllerEnabled"] as? Bool
        XCTAssertEqual(value, false)
    }

    /// Existing users should retain the drop zone unless they explicitly hide it.
    func testFilterDropZoneShownByDefault() {
        guard let defaults = preferenceDefaultsDictionary() else {
            XCTFail("Could not find PreferenceDefaults.plist in any loaded bundle")
            return
        }

        let value = defaults[SARuleFilterDropZoneLayoutPolicy.defaultsKey] as? Bool
        XCTAssertEqual(value, true)
    }

    // MARK: - Helper Functions (mirrors SPTableContent logic)

    /// Parse comma-separated filter string into array of lowercase trimmed terms
    private func parseFilterTerms(_ filterString: String) -> [String] {
        let lowercased = filterString.lowercased().trimmingCharacters(in: .whitespaces)
        if lowercased.isEmpty {
            return []
        }

        let rawTerms = lowercased.components(separatedBy: ",")
        var trimmedTerms: [String] = []

        for term in rawTerms {
            let trimmed = term.trimmingCharacters(in: .whitespaces)
            if trimmed.isNotEmpty {
                trimmedTerms.append(trimmed)
            }
        }

        return trimmedTerms
    }

    /// Check if column name matches any of the filter terms
    private func columnMatches(_ columnName: String, terms: [String]) -> Bool {
        let lowercaseName = columnName.lowercased()
        for term in terms where lowercaseName.contains(term) {
            return true
        }
        return false
    }

    private func preferenceDefaultsDictionary() -> [String: Any]? {
        let candidateBundles = [Bundle.main, Bundle(for: Self.self)] + Bundle.allBundles + Bundle.allFrameworks
        for bundle in candidateBundles {
            guard let path = bundle.path(forResource: "PreferenceDefaults", ofType: "plist") else {
                continue
            }

            if let defaults = NSDictionary(contentsOfFile: path) as? [String: Any] {
                return defaults
            }
        }

        return nil
    }
}

final class SARuleFilterPreviewFormatterTests: XCTestCase {

    /// Verifies a usable clause is prefixed with WHERE.
    func testClauseGetsWherePrefix() {
        XCTAssertEqual(SARuleFilterPreviewFormatter.previewText(clause: "(`a` = '1') OR (`b` = '2')"), "WHERE (`a` = '1') OR (`b` = '2')")
    }

    /// Verifies empty input collapses to nil so the drop prompt returns.
    func testEmptyClauseYieldsNil() {
        XCTAssertNil(SARuleFilterPreviewFormatter.previewText(clause: nil))
        XCTAssertNil(SARuleFilterPreviewFormatter.previewText(clause: ""))
        XCTAssertNil(SARuleFilterPreviewFormatter.previewText(clause: "  \n "))
    }

    /// Verifies surrounding whitespace from the generator is trimmed.
    func testClauseIsTrimmed() {
        XCTAssertEqual(SARuleFilterPreviewFormatter.previewText(clause: " `a` = '1' "), "WHERE `a` = '1'")
    }
}

/// A click on the WHERE preview used to add a filter row, which nobody expected
/// from a line that reads as text; it now opens the filter menu instead.
final class SARuleFilterDropBoxClickTests: XCTestCase {

    /// Records what the drop box asks of its controller.
    private final class SARuleFilterDropHandlerStub: NSObject, SPFilterRuleEditorDropHandler {
        var addedRows = 0
        var addedGroups = 0

        /// Accepts a dropped value without doing anything.
        func appendFilter(forColumn columnName: String, value: String?, isNull: Bool) -> Bool { true }
        /// Accepts a replacing drop without doing anything.
        func replaceFilter(at row: Int, forColumn columnName: String, value: String?, isNull: Bool) -> Bool { true }
        /// Counts added rows.
        func addEmptyFilterRow() { addedRows += 1 }
        /// Counts added groups.
        func addEmptyFilterGroup() { addedGroups += 1 }
    }

    /// Verifies that the prompt still adds a row or, with ⌥, a group, while the preview
    /// opens the menu whatever the modifier.
    func testClickAddsOnlyWhileThePromptShows() {
        XCTAssertEqual(SARuleFilterDropBoxClickPolicy.action(showingPreview: false, optionPressed: false), .addFilterRow)
        XCTAssertEqual(SARuleFilterDropBoxClickPolicy.action(showingPreview: false, optionPressed: true), .addFilterGroup)
        XCTAssertEqual(SARuleFilterDropBoxClickPolicy.action(showingPreview: true, optionPressed: false), .showFilterMenu)
        XCTAssertEqual(SARuleFilterDropBoxClickPolicy.action(showingPreview: true, optionPressed: true), .showFilterMenu)
    }

    /// Verifies the menu a click on the preview opens: adding a filter or a group, and
    /// copying the clause - the last only while there is a clause to copy.
    func testPreviewMenuOffersAddingAndCopying() throws {
        let box = SPRuleFilterDropBox(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        let handler = SARuleFilterDropHandlerStub()
        box.dropHandler = handler

        XCTAssertFalse(box.isShowingPreview)
        XCTAssertEqual(box.filterMenu()?.items.filter { !$0.isSeparatorItem }.map(\.title), ["Add Filter", "Add AND/OR Group"])

        box.setPreviewClause("`a` = '1'")
        XCTAssertTrue(box.isShowingPreview)
        let menu = try XCTUnwrap(box.filterMenu())
        XCTAssertEqual(menu.items.filter { !$0.isSeparatorItem }.map(\.title), ["Add Filter", "Add AND/OR Group", "Copy WHERE Clause"])
        XCTAssertTrue(box.toolTip?.contains("filter menu") ?? false)

        // The menu's items still reach the controller.
        let addFilter = menu.items[0]
        _ = (addFilter.target as AnyObject?)?.perform(addFilter.action, with: addFilter)
        XCTAssertEqual(handler.addedRows, 1)

        box.setPreviewClause(nil)
        XCTAssertFalse(box.isShowingPreview)
        XCTAssertFalse(box.filterMenu()?.items.contains { $0.title == "Copy WHERE Clause" } ?? true)
    }
}

/// The row seeded when another table is selected starts unchecked: it is an empty
/// template, and a checked one made the WHERE preview show `column = ''` while the
/// table was unfiltered. Its first edit checks it, and it keeps waiting across
/// reloads. The controller is Objective-C without a bridging header in this target,
/// so it is driven through selectors and KVC.
final class SARuleFilterPendingStarterTests: XCTestCase {

    /// Verifies the seeded row starts unchecked and is no filter.
    func testSeededStarterRowStartsUncheckedAndIsNoFilter() throws {
        let (controller, editor) = try makeBoundController()
        call(controller, "addStarterFilterExpression")

        XCTAssertEqual(editor.numberOfRows, 1)
        XCTAssertEqual(checkbox(in: editor)?.state, .off)
        XCTAssertEqual(whereClause(of: controller), "")
    }

    /// Verifies typing a value into the seeded row checks it, so Apply filters by it.
    func testTypingIntoTheStarterRowChecksIt() throws {
        let (controller, editor) = try makeBoundController()
        call(controller, "addStarterFilterExpression")

        type("5", into: editor, of: controller)

        XCTAssertEqual(checkbox(in: editor)?.state, .on)
        XCTAssertTrue(whereClause(of: controller).contains("5"), whereClause(of: controller))
    }

    /// Verifies a click on the seeded row's checkbox is the user's choice and later typing leaves it alone.
    func testAClickOnTheStarterCheckboxIsRespected() throws {
        let (controller, editor) = try makeBoundController()
        call(controller, "addStarterFilterExpression")
        let box = try XCTUnwrap(checkbox(in: editor))

        box.state = .on
        controller.perform(NSSelectorFromString("_checkboxClicked:"), with: box)
        box.state = .off
        controller.perform(NSSelectorFromString("_checkboxClicked:"), with: box)
        type("5", into: editor, of: controller)

        XCTAssertEqual(box.state, .off)
        XCTAssertEqual(whereClause(of: controller), "")
    }

    /// Verifies the drop zone's "add a filter" click checks the seeded row instead of adding a second one.
    func testAddingAFilterUsesTheSeededRow() throws {
        let (controller, editor) = try makeBoundController()
        controller.setValue(true, forKey: "enabled")
        call(controller, "addStarterFilterExpression")

        call(controller, "addEmptyFilterRow")
        XCTAssertEqual(editor.numberOfRows, 1)
        XCTAssertEqual(checkbox(in: editor)?.state, .on)

        call(controller, "addEmptyFilterRow")
        XCTAssertEqual(editor.numberOfRows, 2, "with no row waiting, the click adds one as before")
    }

    /// Verifies that the row a new AND/OR group is seeded with waits like the first row does,
    /// instead of putting `column = ''` into the WHERE preview the moment the group appears.
    func testANewGroupsSeededRowWaitsRatherThanFiltering() throws {
        let (controller, editor) = try makeBoundController()
        controller.setValue(true, forKey: "enabled")
        call(controller, "addStarterFilterExpression")
        type("5", into: editor, of: controller)
        let before = whereClause(of: controller)
        XCTAssertFalse(before.isEmpty, "the first row is a filter once it has a value")

        call(controller, "addEmptyFilterGroup")

        XCTAssertEqual(whereClause(of: controller), before,
                       "the group's seeded row adds nothing until it is filled in")
    }

    /// Verifies that a row the user switched on and then unchecked again is a filter set aside:
    /// "add a filter" leaves it alone and adds a row.
    ///
    /// Its value being the empty string makes no difference, and from the editor's state alone
    /// there is no telling the two apart - an empty value field looks the same whether the user
    /// meant `column = ''` or never typed anything. Reusing it switched a filter the user had put
    /// away back on and put the cursor in it, so the next keystroke replaced it.
    func testAddingAFilterLeavesARowUncheckedAgainAlone() throws {
        let (controller, editor) = try makeBoundController()
        controller.setValue(true, forKey: "enabled")
        call(controller, "addStarterFilterExpression")

        call(controller, "addEmptyFilterRow")
        let box = try XCTUnwrap(checkbox(in: editor))
        XCTAssertEqual(box.state, .on, "the seeded row is the one this click checks")
        box.state = .off
        controller.perform(NSSelectorFromString("_checkboxClicked:"), with: box)

        call(controller, "addEmptyFilterRow")
        XCTAssertEqual(editor.numberOfRows, 2, "the filter set aside is left where it is")
        XCTAssertEqual(box.state, .off, "and stays off")
    }

    /// Verifies that an unchecked row with a value, and one whose operator takes no value, are filters set
    /// aside: "add a filter" leaves them alone and adds a row.
    func testAddingAFilterLeavesSetAsideFiltersAlone() throws {
        let (controller, editor) = try makeBoundController()
        controller.setValue(true, forKey: "enabled")
        call(controller, "addStarterFilterExpression")
        type("5", into: editor, of: controller)
        let box = try XCTUnwrap(checkbox(in: editor))
        box.state = .off
        controller.perform(NSSelectorFromString("_checkboxClicked:"), with: box)

        call(controller, "addEmptyFilterRow")
        XCTAssertEqual(editor.numberOfRows, 2)
        XCTAssertEqual(checkbox(in: editor)?.state, .off, "the set-aside `id = 5` stays unchecked")

        let isNullRow: [String: Any] = ["filterClass": "expressionNode", "column": "id", "filterComparison": "IS NULL", "filterValues": [String](), "enabled": false]
        controller.perform(NSSelectorFromString("restoreSerializedFilters:"), with: isNullRow)
        XCTAssertEqual(editor.numberOfRows, 1)
        call(controller, "addEmptyFilterRow")
        XCTAssertEqual(editor.numberOfRows, 2)
        XCTAssertEqual(checkbox(in: editor)?.state, .off, "the set-aside IS NULL stays unchecked")
    }

    /// Verifies a dropped value replaces the seeded row and comes out checked; a drop that cannot
    /// become a rule leaves the row waiting.
    ///
    /// The replaced row gets a checkbox of its own: the rule editor builds the display values for
    /// a restored row from scratch. What the drop paths end is the tracking, not the button.
    func testDroppedValuesAndTheSeededRow() throws {
        for isConjunction in [true, false] {
            let (controller, editor) = try makeBoundController()
            controller.setValue(true, forKey: "enabled")
            controller.setValue(isConjunction, forKey: "rootIsConjunction")
            call(controller, "addStarterFilterExpression")

            XCTAssertFalse(appendFilter(to: controller, column: "no_such_column", value: "7"))
            XCTAssertEqual(checkbox(in: editor)?.state, .off)
            XCTAssertEqual(whereClause(of: controller), "")

            XCTAssertTrue(appendFilter(to: controller, column: "id", value: "7"))
            XCTAssertEqual(editor.numberOfRows, 1, "only the dropped rule under AND and OR")
            XCTAssertEqual(checkbox(in: editor)?.state, .on)
            let saved = try XCTUnwrap(serializedFilter(of: controller))
            let rules = leaves(of: saved)
            XCTAssertEqual(rules.count, 1)
            XCTAssertEqual(rules.first?["filterValues"] as? [String], ["7"])
            XCTAssertEqual(rules.first?["enabled"] as? Bool, true)
            XCTAssertNil(rules.first?["pendingStarter"])
            XCTAssertTrue(whereClause(of: controller).contains("7"))
            XCTAssertEqual(controller.value(forKey: "rootIsConjunction") as? Bool, isConjunction)
        }
    }

    /// A clicked empty-string predicate belongs to the user, even if they then
    /// disable it. Appending a dropped value must keep it in the bound editor.
    func testAppendingDroppedValuesPreservesUserEmptyPredicates() throws {
        for isConjunction in [true, false] {
            for isEnabled in [true, false] {
                let (controller, editor) = try makeBoundController(columns: [
                    ["name": "name", "typegrouping": "string"],
                    ["name": "id", "typegrouping": "integer"]
                ])
                controller.setValue(true, forKey: "enabled")
                controller.setValue(isConjunction, forKey: "rootIsConjunction")
                call(controller, "addStarterFilterExpression")
                let box = try XCTUnwrap(checkbox(in: editor))
                box.state = .on
                controller.perform(NSSelectorFromString("_checkboxClicked:"), with: box)
                if !isEnabled {
                    box.state = .off
                    controller.perform(NSSelectorFromString("_checkboxClicked:"), with: box)
                }

                XCTAssertTrue(appendFilter(to: controller, column: "id", value: "7"))
                XCTAssertEqual(editor.numberOfRows, 2)
                let saved = try XCTUnwrap(serializedFilter(of: controller))
                let rules = leaves(of: saved)
                XCTAssertEqual(rules.count, 2)
                let emptyRule = try XCTUnwrap(rules.first { $0["column"] as? String == "name" })
                XCTAssertEqual(emptyRule["filterValues"] as? [String], [""])
                XCTAssertEqual(emptyRule["enabled"] as? Bool, isEnabled)
                XCTAssertNil(emptyRule["pendingStarter"])
                XCTAssertEqual(controller.value(forKey: "rootIsConjunction") as? Bool, isConjunction)
            }
        }
    }

    /// Verifies the seeded row still waits for its first edit after the filter is saved and restored, as
    /// on a reload or a return to the table, and after the criteria are reloaded, as after "Edit Filters…".
    func testTheSeededRowKeepsWaitingAcrossRestoreAndCriteriaReload() throws {
        let (controller, editor) = try makeBoundController()
        call(controller, "addStarterFilterExpression")
        let saved = try XCTUnwrap(serializedFilter(of: controller))

        controller.perform(NSSelectorFromString("restoreSerializedFilters:"), with: saved)
        editor.reloadCriteria()
        XCTAssertEqual(editor.numberOfRows, 1)
        XCTAssertEqual(checkbox(in: editor)?.state, .off)
        XCTAssertEqual(whereClause(of: controller), "")

        type("5", into: editor, of: controller)
        XCTAssertEqual(checkbox(in: editor)?.state, .on)
        XCTAssertTrue(whereClause(of: controller).contains("5"))
    }


    /// Verifies a restored row that has since been enabled is not unchecked again when the editor
    /// rebuilds its checkbox - which it does on a criteria reload, as after a custom filter is
    /// removed in "Edit Filters…".
    ///
    /// The mark a restored row carries exists so that tracking resumes when the checkbox is built
    /// anew before the row has been edited. It therefore has to go the moment the row stops
    /// waiting, or a later rebuild would take the row back to unchecked with the user's value
    /// still in it. The test before this one reloads before the first edit; this one reloads after.
    func testARestoredRowEnabledBeforeACriteriaReloadStaysEnabled() throws {
        let (controller, editor) = try makeBoundController()
        call(controller, "addStarterFilterExpression")
        let saved = try XCTUnwrap(serializedFilter(of: controller))

        controller.perform(NSSelectorFromString("restoreSerializedFilters:"), with: saved)
        editor.reloadCriteria()
        XCTAssertEqual(checkbox(in: editor)?.state, .off, "it is still waiting")

        // the user types, which enables the row
        type("5", into: editor, of: controller)
        XCTAssertEqual(checkbox(in: editor)?.state, .on)
        XCTAssertTrue(whereClause(of: controller).contains("5"))

        // removing a custom filter invalidates the criteria and rebuilds every display value
        editor.reloadCriteria()

        XCTAssertEqual(editor.numberOfRows, 1)
        XCTAssertEqual(checkbox(in: editor)?.state, .on, "the row the user enabled stays enabled")
        XCTAssertTrue(whereClause(of: controller).contains("5"), "and keeps producing its clause")
    }

    /// Verifies the same for a row whose checkbox the user clicked rather than typing into it.
    func testARestoredRowCheckedByHandStaysCheckedAcrossACriteriaReload() throws {
        let (controller, editor) = try makeBoundController()
        call(controller, "addStarterFilterExpression")
        let saved = try XCTUnwrap(serializedFilter(of: controller))

        controller.perform(NSSelectorFromString("restoreSerializedFilters:"), with: saved)
        editor.reloadCriteria()
        let box = try XCTUnwrap(checkbox(in: editor))
        XCTAssertEqual(box.state, .off)

        // the user checks it themselves
        box.state = .on
        controller.perform(NSSelectorFromString("_checkboxClicked:"), with: box)

        editor.reloadCriteria()

        XCTAssertEqual(checkbox(in: editor)?.state, .on, "the user's own choice survives the rebuild")
    }

    /// Verifies the persisted marker is a plain plist key that older readers ignore, and that an unchecked
    /// empty row saved by an older version - without the marker - restores as a plain unchecked row that
    /// typing does not check.
    func testPendingMarkerWireFormatAndLegacyRows() throws {
        let (controller, editor) = try makeBoundController()
        call(controller, "addStarterFilterExpression")
        let saved = try XCTUnwrap(serializedFilter(of: controller))

        let data = try PropertyListSerialization.data(fromPropertyList: saved, format: .xml, options: 0)
        let decoded = try XCTUnwrap(try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any])
        let leaf = try XCTUnwrap(leaves(of: decoded).first)
        XCTAssertEqual(leaf["pendingStarter"] as? Bool, true)
        XCTAssertEqual(leaf["enabled"] as? Bool, false, "older readers see an unchecked row")
        XCTAssertEqual(leaf["column"] as? String, "id")

        // What an older version wrote for an unchecked empty row.
        let legacyRow: [String: Any] = [
            "filterClass": "expressionNode",
            "column": "id",
            "filterComparison": "=",
            "filterValues": [""],
            "enabled": false,
        ]
        controller.perform(NSSelectorFromString("restoreSerializedFilters:"), with: legacyRow)
        XCTAssertEqual(checkbox(in: editor)?.state, .off)
        type("5", into: editor, of: controller)
        XCTAssertEqual(checkbox(in: editor)?.state, .off, "a legacy unchecked row is the user's, not a waiting starter")
        XCTAssertEqual(whereClause(of: controller), "")
    }

    /// Verifies that a filter restored straight over the waiting seeded row - a cell's "filter by this
    /// value", or a same-table foreign-key jump - comes out checked and is applied. The rule editor keeps
    /// the replaced row's checkbox for the new row.
    func testAFilterRestoredOverTheSeededRowIsChecked() throws {
        let (controller, editor) = try makeBoundController()
        call(controller, "addStarterFilterExpression")

        let cellFilter: [String: Any] = ["filterClass": "expressionNode", "column": "id", "filterComparison": "=", "filterValues": ["7"], "enabled": true]
        controller.perform(NSSelectorFromString("restoreSerializedFilters:"), with: cellFilter)

        XCTAssertEqual(editor.numberOfRows, 1)
        XCTAssertEqual(checkbox(in: editor)?.state, .on)
        XCTAssertTrue(whereClause(of: controller).contains("7"), whereClause(of: controller))
    }

    /// Verifies the cell context menu's "filter by this value" path: the current filter, holding the
    /// waiting seeded row, is merged with the cell's filter and restored, and the result is applied.
    func testACellFilterMergedOverTheSeededRowIsChecked() throws {
        let (controller, editor) = try makeBoundController()
        call(controller, "addStarterFilterExpression")

        let cellFilter: [String: Any] = ["filterClass": "expressionNode", "column": "id", "filterComparison": "=", "filterValues": ["7"]]
        let merged = SACellFilterMerge.mergedFilter(currentFilter: serializedFilter(of: controller), newFilter: cellFilter)
        controller.perform(NSSelectorFromString("restoreSerializedFilters:"), with: merged)

        XCTAssertEqual(editor.numberOfRows, 1)
        XCTAssertEqual(checkbox(in: editor)?.state, .on)
        XCTAssertTrue(whereClause(of: controller).contains("7"), whereClause(of: controller))
    }

    /// Verifies that two groups added one after the other each bring a row that waits on its own,
    /// so filling in the one added first filters by it.
    ///
    /// A single tracked row meant the later group's row took the earlier one's place: editing the
    /// earlier row no longer checked it, so its condition was missing from the WHERE clause.
    func testEachNewGroupsSeededRowWaitsOnItsOwn() throws {
        let (controller, editor) = try makeBoundController()
        controller.setValue(true, forKey: "enabled")
        call(controller, "addStarterFilterExpression")
        type("5", into: editor, of: controller)

        call(controller, "addEmptyFilterGroup")
        call(controller, "addEmptyFilterGroup")

        let waiting = waitingRows(in: editor)
        XCTAssertEqual(waiting.count, 2, "each group brought a row waiting for its first edit")
        let earlier = try XCTUnwrap(waiting.first)

        type("7", intoRow: earlier, in: editor, of: controller)

        let box = try XCTUnwrap(editor.displayValues(forRow: earlier).first as? NSButton)
        XCTAssertEqual(box.state, .on, "its first edit checks it")
        XCTAssertTrue(whereClause(of: controller).contains("7"), whereClause(of: controller))
    }

    /// Verifies a saved filter holding more than one waiting row restores every one of them
    /// waiting, so filling in the one that is not the last still filters by it.
    ///
    /// This is the path back to a table the user left with groups still unfilled. With a single
    /// tracked row, the saved filter named only one of them and the rest came back as plain
    /// unchecked rows.
    func testASavedFilterRestoresEveryWaitingRow() throws {
        let (controller, editor) = try makeBoundController()
        controller.setValue(true, forKey: "enabled")
        call(controller, "addStarterFilterExpression")
        type("5", into: editor, of: controller)
        call(controller, "addEmptyFilterGroup")
        call(controller, "addEmptyFilterGroup")

        let saved = try XCTUnwrap(serializedFilter(of: controller))
        let marked = leaves(of: saved).filter { ($0["pendingStarter"] as? NSNumber)?.boolValue == true }
        XCTAssertEqual(marked.count, 2, "the saved filter records both rows as waiting")

        restore(saved, in: controller)

        let waiting = waitingRows(in: editor)
        XCTAssertEqual(waiting.count, 2, "and both come back waiting")
        let earlier = try XCTUnwrap(waiting.first)

        type("7", intoRow: earlier, in: editor, of: controller)

        let box = try XCTUnwrap(editor.displayValues(forRow: earlier).first as? NSButton)
        XCTAssertEqual(box.state, .on, "the restored row's first edit checks it")
        XCTAssertTrue(whereClause(of: controller).contains("7"), whereClause(of: controller))
    }

    /// Verifies a drop the editor cannot address leaves every waiting row alone.
    ///
    /// The drop handler is handed an ordinal among the top-level rows, which counts none of a
    /// nested group's subrows; the tracker addresses rule editor rows, which count all of them.
    /// With two groups, dropping onto the second one is refused - a group is no rule - and the
    /// refused ordinal is the first group's waiting row. Asking the tracker about it switched
    /// that row on with nothing in it, so `column = \'\'` became a filter while the drop itself
    /// did nothing.
    func testARefusedDropLeavesAWaitingRowAlone() throws {
        let (controller, editor) = try makeBoundController()
        controller.setValue(true, forKey: "enabled")
        call(controller, "addEmptyFilterGroup")
        call(controller, "addEmptyFilterGroup")

        // group, its waiting row, second group, its waiting row.
        XCTAssertEqual(waitingRows(in: editor), [1, 3])
        XCTAssertEqual(editor.rowType(forRow: 2), .compound, "ordinal 1 among the top-level rows")
        XCTAssertEqual(whereClause(of: controller), "", "nothing filters yet")

        XCTAssertFalse(replaceFilter(in: controller, atRow: 1, column: "id", value: "7"),
                       "a group is no rule, so the drop is refused")

        let box = try XCTUnwrap(editor.displayValues(forRow: 1).first as? NSButton)
        XCTAssertEqual(box.state, .off, "the first group's waiting row was not switched on")
        XCTAssertEqual(whereClause(of: controller), "", "and nothing became a filter")
    }

    /// Verifies switching a group on stops its waiting row waiting, so the row stays switched on.
    ///
    /// The group pushes its state down onto its rows directly. A row left tracked was unchecked
    /// again the next time its checkbox was built, so returning to the table brought the group
    /// back with the row switched off.
    func testSwitchingAGroupOnStopsItsRowWaiting() throws {
        let (controller, editor) = try makeBoundController()
        controller.setValue(true, forKey: "enabled")
        call(controller, "addStarterFilterExpression")
        type("5", into: editor, of: controller)
        call(controller, "addEmptyFilterGroup")

        let groupRow = try XCTUnwrap((0..<editor.numberOfRows).first { editor.rowType(forRow: $0) == .compound })
        let childRow = try XCTUnwrap(waitingRows(in: editor).first)
        XCTAssertEqual(editor.parentRow(forRow: childRow), groupRow, "the waiting row is the group's")

        let groupBox = try XCTUnwrap(editor.displayValues(forRow: groupRow).first as? NSButton)
        groupBox.state = .on
        controller.perform(NSSelectorFromString("_checkboxClicked:"), with: groupBox)

        let childBox = try XCTUnwrap(editor.displayValues(forRow: childRow).first as? NSButton)
        XCTAssertEqual(childBox.state, .on, "the group switched its row on")

        let saved = try XCTUnwrap(serializedFilter(of: controller))
        XCTAssertTrue(leaves(of: saved).allSatisfy { ($0["pendingStarter"] as? NSNumber)?.boolValue != true },
                      "no row is recorded as still waiting")

        restore(saved, in: controller)
        XCTAssertTrue(waitingRows(in: editor).isEmpty, "and none comes back unchecked and empty")
    }

    // MARK: - Helpers

    /// An `SPRuleFilterController` for one integer column `id`, whose rule editor is set up and bound to the
    /// controller's model the way DBView.xib and `-awakeFromNib` do it.
    private func makeBoundController(columns: [[String: String]] = [["name": "id", "typegrouping": "integer"]]) throws -> (NSObject, NSRuleEditor) {
        let controllerClass = try XCTUnwrap(NSClassFromString("SPRuleFilterController") as? NSObject.Type)
        let controller = controllerClass.init()
        let editor = NSRuleEditor(frame: NSRect(x: 0, y: 0, width: 600, height: 120))
        editor.nestingMode = .compound
        editor.canRemoveAllRows = true
        editor.delegate = controller as? NSRuleEditorDelegate
        controller.setValue(editor, forKey: "filterRuleEditor")
        controller.perform(NSSelectorFromString("setColumns:"), with: columns)
        call(controller, "awakeFromNib")
        return (controller, editor)
    }

    /// Sends a selector without arguments.
    private func call(_ controller: NSObject, _ selector: String) {
        controller.perform(NSSelectorFromString(selector))
    }

    /// The enable checkbox of the first row.
    private func checkbox(in editor: NSRuleEditor) -> NSButton? {
        return editor.displayValues(forRow: 0).first as? NSButton
    }

    /// Types `value` into the first row's argument field, as the user would.
    private func type(_ value: String, into editor: NSRuleEditor, of controller: NSObject) {
        guard let field = editor.displayValues(forRow: 0).compactMap({ $0 as? NSTextField }).first else {
            XCTFail("the row has no argument field")
            return
        }
        field.stringValue = value
        controller.perform(NSSelectorFromString("controlTextDidChange:"),
                           with: Notification(name: NSControl.textDidChangeNotification, object: field))
    }

    /// The WHERE clause the enabled rules produce; empty when none is enabled.
    private func whereClause(of controller: NSObject) -> String {
        let selector = NSSelectorFromString("sqlWhereExpressionWithBinary:error:")
        typealias SAWhereFunction = @convention(c) (NSObject, Selector, Bool, AutoreleasingUnsafeMutablePointer<NSError?>?) -> NSString?
        let function = unsafeBitCast(controller.method(for: selector), to: SAWhereFunction.self)
        return (function(controller, selector, false, nil) as String?) ?? ""
    }

    /// Calls `-appendFilterForColumn:value:isNull:`, the drop of a cell onto the drop zone.
    private func appendFilter(to controller: NSObject, column: String, value: String) -> Bool {
        let selector = NSSelectorFromString("appendFilterForColumn:value:isNull:")
        typealias SAAppendFunction = @convention(c) (NSObject, Selector, NSString, NSString?, Bool) -> Bool
        let function = unsafeBitCast(controller.method(for: selector), to: SAAppendFunction.self)
        return function(controller, selector, column as NSString, value as NSString, false)
    }

    /// Types `value` into `row`'s argument field, as the user would.
    private func type(_ value: String, intoRow row: Int, in editor: NSRuleEditor, of controller: NSObject) {
        guard let field = editor.displayValues(forRow: row).compactMap({ $0 as? NSTextField }).first else {
            XCTFail("row \(row) has no argument field")
            return
        }
        field.stringValue = value
        controller.perform(NSSelectorFromString("controlTextDidChange:"),
                           with: Notification(name: NSControl.textDidChangeNotification, object: field))
    }

    /// The indexes of the simple rows that are unchecked and hold no value - the rows a seeded
    /// starter leaves behind, in editor order.
    private func waitingRows(in editor: NSRuleEditor) -> [Int] {
        return (0..<editor.numberOfRows).filter { row in
            guard editor.rowType(forRow: row) == .simple else { return false }
            let values = editor.displayValues(forRow: row)
            guard let box = values.first as? NSButton, box.state == .off else { return false }
            let fields = values.compactMap { $0 as? NSTextField }
            return !fields.isEmpty && fields.allSatisfy { $0.stringValue.isEmpty }
        }
    }

    /// Calls `-replaceFilterAtRow:forColumn:value:isNull:`, the drop of a cell onto a row. The
    /// row is an ordinal among the top-level rows, as the rule editor hands it over.
    private func replaceFilter(in controller: NSObject, atRow row: Int, column: String, value: String) -> Bool {
        let selector = NSSelectorFromString("replaceFilterAtRow:forColumn:value:isNull:")
        typealias SAReplaceFunction = @convention(c) (NSObject, Selector, Int, NSString, NSString?, Bool) -> Bool
        let function = unsafeBitCast(controller.method(for: selector), to: SAReplaceFunction.self)
        return function(controller, selector, row, column as NSString, value as NSString, false)
    }

    /// Calls `-serializedFilter`.
    private func serializedFilter(of controller: NSObject) -> [String: Any]? {
        return controller.perform(NSSelectorFromString("serializedFilter"))?.takeUnretainedValue() as? [String: Any]
    }

    /// Calls `-restoreSerializedFilters:`, as returning to a table does.
    private func restore(_ filter: [String: Any], in controller: NSObject) {
        controller.perform(NSSelectorFromString("restoreSerializedFilters:"), with: filter)
    }

    /// The expression leaves of a serialized filter tree.
    private func leaves(of filter: [String: Any]) -> [[String: Any]] {
        if filter["filterClass"] as? String == "expressionNode" {
            return [filter]
        }
        return (filter["children"] as? [[String: Any]] ?? []).flatMap { leaves(of: $0) }
    }
}

final class SARuleFilterBottomBarLayoutTests: XCTestCase {

    /// Verifies rows sit above a fully reserved bottom bar (drop zone shown).
    func testRowsSitAboveTheDropZoneBar() {
        let m = SARuleFilterDropZoneLayoutPolicy.metrics(editorVisible: true, editorHasRows: true, requestedHeight: 87, dropZoneHeight: 40, showDropZonePreference: true)
        XCTAssertTrue(m.dropZoneVisible)
        XCTAssertEqual(m.dropZoneReservedHeight, 40)
        XCTAssertEqual(m.ruleEditorOriginY, 41)
        XCTAssertEqual(m.containerRequestedHeight, 40 + 88)
    }

    /// Verifies the button bar stays reserved when the drop zone is hidden, so full-width rows never overlap it.
    func testButtonBarReservedWithHiddenDropZone() {
        let m = SARuleFilterDropZoneLayoutPolicy.metrics(editorVisible: true, editorHasRows: true, requestedHeight: 58, dropZoneHeight: 40, showDropZonePreference: false)
        XCTAssertFalse(m.dropZoneVisible)
        XCTAssertEqual(m.dropZoneReservedHeight, 31)
        XCTAssertEqual(m.ruleEditorOriginY, 32)
        XCTAssertEqual(m.containerRequestedHeight, 31 + 59)
    }

    /// Verifies an empty editor shows just the bar (with or without drop zone).
    func testEmptyEditorShowsOnlyTheBar() {
        let withZone = SARuleFilterDropZoneLayoutPolicy.metrics(editorVisible: true, editorHasRows: false, requestedHeight: 0, dropZoneHeight: 40, showDropZonePreference: true)
        XCTAssertEqual(withZone.containerRequestedHeight, 40)
        let withoutZone = SARuleFilterDropZoneLayoutPolicy.metrics(editorVisible: true, editorHasRows: false, requestedHeight: 0, dropZoneHeight: 40, showDropZonePreference: false)
        XCTAssertEqual(withoutZone.containerRequestedHeight, 31)
    }

    /// Verifies a hidden editor reserves nothing.
    func testHiddenEditorReservesNothing() {
        let m = SARuleFilterDropZoneLayoutPolicy.metrics(editorVisible: false, editorHasRows: true, requestedHeight: 87, dropZoneHeight: 40, showDropZonePreference: true)
        XCTAssertFalse(m.dropZoneVisible)
        XCTAssertEqual(m.dropZoneReservedHeight, 0)
        XCTAssertEqual(m.containerRequestedHeight, 0)
    }
}

final class SARuleFilterResizePolicyTests: XCTestCase {

    /// Verifies an unchanged row count schedules no resize at all.
    func testUnchangedRowCountDoesNothing() {
        XCTAssertEqual(SARuleFilterResizePolicy.action(rowCount: 3, previousRowCount: 3), .none)
        XCTAssertEqual(SARuleFilterResizePolicy.action(rowCount: 0, previousRowCount: 0), .none)
    }

    /// Verifies growing resizes immediately so the container makes room while the row animates in.
    func testGrowingResizesImmediately() {
        XCTAssertEqual(SARuleFilterResizePolicy.action(rowCount: 1, previousRowCount: 0), .immediate)
        XCTAssertEqual(SARuleFilterResizePolicy.action(rowCount: 5, previousRowCount: 2), .immediate)
    }

    /// Verifies shrinking waits for the rule editor's removal animation.
    func testShrinkingDefersResize() {
        XCTAssertEqual(SARuleFilterResizePolicy.action(rowCount: 2, previousRowCount: 3), .deferred)
        XCTAssertEqual(SARuleFilterResizePolicy.action(rowCount: 0, previousRowCount: 1), .deferred)
        XCTAssertGreaterThan(SARuleFilterResizePolicy.deferredResizeDelay, 0)
    }
}

final class PinnedTableMigrationPlannerTests: XCTestCase {

    func testPinnedTableMigrationTokenGeneration() {
        let token = PinnedTableMigrationPlanner.migrationToken(legacyHostName: "", connectionIdentifier: "user@localhost:3306", databaseName: "db_name")
        XCTAssertEqual(token, "|user@localhost:3306|db_name")
    }

    func testPinnedTableMigrationTokenRejectsInvalidInputs() {
        XCTAssertNil(PinnedTableMigrationPlanner.migrationToken(legacyHostName: "legacy", connectionIdentifier: "", databaseName: "db_name"))
        XCTAssertNil(PinnedTableMigrationPlanner.migrationToken(legacyHostName: "legacy", connectionIdentifier: "user@localhost:3306", databaseName: ""))
        XCTAssertNil(PinnedTableMigrationPlanner.migrationToken(legacyHostName: "same_key", connectionIdentifier: "same_key", databaseName: "db_name"))
    }

    func testPinnedTableMigrationTableMerge() {
        let tablesToMigrate = PinnedTableMigrationPlanner.tablesToMigrate(
            legacyPinnedTables: ["users", "orders", "users", "", "products", "orders"],
            existingPinnedTables: ["orders", "existing"]
        )

        XCTAssertEqual(tablesToMigrate, ["users", "products"])
    }
}

final class SPOptimizedFieldTypeEstimatorTests: XCTestCase {

    func testNormalizedFieldType() {
        XCTAssertEqual(
            SPOptimizedFieldTypeEstimator.normalizedFieldType(fromDefinition: ["type": " varchar(255) "] as NSDictionary),
            "VARCHAR"
        )
        XCTAssertEqual(
            SPOptimizedFieldTypeEstimator.normalizedFieldType(fromDefinition: ["type": " mediumint unsigned "] as NSDictionary),
            "MEDIUMINT UNSIGNED"
        )
        XCTAssertEqual(
            SPOptimizedFieldTypeEstimator.normalizedFieldType(fromDefinition: ["type": NSNull()] as NSDictionary),
            ""
        )
        XCTAssertEqual(
            SPOptimizedFieldTypeEstimator.normalizedFieldType(fromDefinition: [:] as NSDictionary),
            ""
        )
    }

    func testFieldTypeClassification() {
        let intType = SPOptimizedFieldTypeEstimator.normalizedFieldType(fromDefinition: ["type": "int(11)"] as NSDictionary)
        let binaryType = SPOptimizedFieldTypeEstimator.normalizedFieldType(fromDefinition: ["type": "varbinary(64)"] as NSDictionary)
        let stringType = SPOptimizedFieldTypeEstimator.normalizedFieldType(fromDefinition: ["type": "varchar(64)"] as NSDictionary)
        let unknownType = SPOptimizedFieldTypeEstimator.normalizedFieldType(fromDefinition: ["type": "json"] as NSDictionary)

        XCTAssertTrue(SPOptimizedFieldTypeEstimator.isIntegerFieldType(intType))
        XCTAssertTrue(SPOptimizedFieldTypeEstimator.isBinaryFieldType(binaryType))
        XCTAssertTrue(SPOptimizedFieldTypeEstimator.isStringFieldType(stringType))
        XCTAssertFalse(SPOptimizedFieldTypeEstimator.isIntegerFieldType(unknownType))
        XCTAssertFalse(SPOptimizedFieldTypeEstimator.isBinaryFieldType(nil))
        XCTAssertFalse(SPOptimizedFieldTypeEstimator.isStringFieldType(nil))
    }

    func testDecimalNumberParsingFromStats() {
        XCTAssertEqual(
            SPOptimizedFieldTypeEstimator.decimalNumber(fromStatValue: " 42.5 "),
            NSDecimalNumber(string: "42.5")
        )
        XCTAssertEqual(
            SPOptimizedFieldTypeEstimator.decimalNumber(fromStatValue: 12),
            NSDecimalNumber(string: "12")
        )
        XCTAssertNil(SPOptimizedFieldTypeEstimator.decimalNumber(fromStatValue: nil))
        XCTAssertNil(SPOptimizedFieldTypeEstimator.decimalNumber(fromStatValue: NSNull()))
        XCTAssertNil(SPOptimizedFieldTypeEstimator.decimalNumber(fromStatValue: ""))
        XCTAssertNil(SPOptimizedFieldTypeEstimator.decimalNumber(fromStatValue: "not a number"))
    }

    func testUnsignedIntegerParsingFromStats() {
        XCTAssertEqual(SPOptimizedFieldTypeEstimator.unsignedIntegerValue(fromStatValue: " 17 "), 17)
        XCTAssertEqual(SPOptimizedFieldTypeEstimator.unsignedIntegerValue(fromStatValue: 9), 9)
        XCTAssertEqual(SPOptimizedFieldTypeEstimator.unsignedIntegerValue(fromStatValue: "-3"), 0)
        XCTAssertEqual(SPOptimizedFieldTypeEstimator.unsignedIntegerValue(fromStatValue: nil), 0)
        XCTAssertEqual(SPOptimizedFieldTypeEstimator.unsignedIntegerValue(fromStatValue: NSNull()), 0)
        XCTAssertEqual(SPOptimizedFieldTypeEstimator.unsignedIntegerValue(fromStatValue: "abc"), 0)
    }

    func testMaxBytesPerCharacterResolution() {
        let utf8mb4Bytes = SPOptimizedFieldTypeEstimator.maxBytesPerCharacter(
            forFieldDefinition: ["encodingName": "utf8mb4"] as NSDictionary,
            tableEncoding: nil,
            availableEncodings: [["CHARACTER_SET_NAME": "utf8mb4", "MAXLEN": 4] as NSDictionary]
        )
        XCTAssertEqual(utf8mb4Bytes, 4)

        let latinBytes = SPOptimizedFieldTypeEstimator.maxBytesPerCharacter(
            forFieldDefinition: [:] as NSDictionary,
            tableEncoding: "latin1",
            availableEncodings: [["Charset": "LATIN1", "Maxlen": 1] as NSDictionary]
        )
        XCTAssertEqual(latinBytes, 1)

        let utf8HeuristicBytes = SPOptimizedFieldTypeEstimator.maxBytesPerCharacter(
            forFieldDefinition: ["encoding": "utf8_general_ci"] as NSDictionary,
            tableEncoding: nil,
            availableEncodings: []
        )
        XCTAssertEqual(utf8HeuristicBytes, 3)

        let utf16HeuristicBytes = SPOptimizedFieldTypeEstimator.maxBytesPerCharacter(
            forFieldDefinition: ["encoding": "utf16le"] as NSDictionary,
            tableEncoding: nil,
            availableEncodings: []
        )
        XCTAssertEqual(utf16HeuristicBytes, 4)

        let ucs2HeuristicBytes = SPOptimizedFieldTypeEstimator.maxBytesPerCharacter(
            forFieldDefinition: ["encoding": "ucs2"] as NSDictionary,
            tableEncoding: nil,
            availableEncodings: []
        )
        XCTAssertEqual(ucs2HeuristicBytes, 2)

        let unknownEncodingBytes = SPOptimizedFieldTypeEstimator.maxBytesPerCharacter(
            forFieldDefinition: ["encoding": "latin1"] as NSDictionary,
            tableEncoding: nil,
            availableEncodings: [["CHARACTER_SET_NAME": "latin1", "MAXLEN": 0] as NSDictionary]
        )
        XCTAssertEqual(unknownEncodingBytes, 1)

        let defaultBytes = SPOptimizedFieldTypeEstimator.maxBytesPerCharacter(
            forFieldDefinition: [:] as NSDictionary,
            tableEncoding: nil,
            availableEncodings: []
        )
        XCTAssertEqual(defaultBytes, 1)
    }

    func testEstimatedIntegerTypeBoundaries() {
        XCTAssertEqual(
            SPOptimizedFieldTypeEstimator.estimatedIntegerType(
                forMinimum: NSDecimalNumber(string: "0"),
                maximum: NSDecimalNumber(string: "255")
            ),
            "TINYINT UNSIGNED"
        )

        XCTAssertEqual(
            SPOptimizedFieldTypeEstimator.estimatedIntegerType(
                forMinimum: NSDecimalNumber(string: "-128"),
                maximum: NSDecimalNumber(string: "127")
            ),
            "TINYINT"
        )

        XCTAssertEqual(
            SPOptimizedFieldTypeEstimator.estimatedIntegerType(
                forMinimum: NSDecimalNumber(string: "-129"),
                maximum: NSDecimalNumber(string: "127")
            ),
            "SMALLINT"
        )

        XCTAssertEqual(
            SPOptimizedFieldTypeEstimator.estimatedIntegerType(
                forMinimum: NSDecimalNumber(string: "0"),
                maximum: NSDecimalNumber(string: "18446744073709551615")
            ),
            "BIGINT UNSIGNED"
        )

        XCTAssertEqual(
            SPOptimizedFieldTypeEstimator.estimatedIntegerType(
                forMinimum: NSDecimalNumber(string: "0"),
                maximum: NSDecimalNumber(string: "18446744073709551616")
            ),
            "BIGINT UNSIGNED"
        )
    }
}

/// The BIT literal the table views write for a cell value, from
/// `SPFieldTypeClassifier.bitLiteral(for:)`; the views pass an empty value as "0".
final class SABitLiteralTests: XCTestCase {

    /// Verifies text of only 0 and 1 becomes a literal.
    func testBinaryDigitsBecomeALiteral() {
        XCTAssertEqual(SPFieldTypeClassifier.bitLiteral(for: "1"), "b'1'")
        XCTAssertEqual(SPFieldTypeClassifier.bitLiteral(for: "0"), "b'0'")
        XCTAssertEqual(SPFieldTypeClassifier.bitLiteral(for: "0101"), "b'0101'")
    }

    /// Verifies any other text is refused, above all one that would end the literal.
    func testAnyOtherTextIsRefused() {
        for text in ["", "2", "01a", "1' OR 1=1 -- ", "1'", " 1", "1 ", "NULL", "b'1'", "\u{0661}", "1\u{0301}"] {
            XCTAssertNil(SPFieldTypeClassifier.bitLiteral(for: text), text)
        }
    }
}
