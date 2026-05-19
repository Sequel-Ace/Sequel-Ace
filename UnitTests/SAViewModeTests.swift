//
//  SAViewModeTests.swift
//  Unit Tests
//
//  Tests for SAViewMode and SAViewModeHelper — the data-driven enum that
//  replaces the scattered SPViewMode C enum and the six repetitive
//  view-switching methods on SPDatabaseDocument.
//
//  These tests are the safety net for Phase A3 of the modernization
//  follow-up plan ("validate before and after"). They lock down:
//    - tab indexes (used to drive NSTabView selection)
//    - toolbar identifier strings (must match SPMainToolbar* constants)
//    - legacy SPViewMode preferences integers (round-trip with stored prefs)
//    - the action selector names (must match the ObjC viewX methods)
//    - exhaustive case coverage
//

import XCTest
import AppKit

final class SAViewModeTests: XCTestCase {

    // MARK: - Tab indexes

    /// Tab indexes drive `[tableTabView selectTabViewItemAtIndex:]` in
    /// `-[SPDatabaseDocument switchToViewMode:]`. They must stay 0..5
    /// in order — changing them would silently switch the user to the
    /// wrong tab.
    func testTabIndexes() {
        XCTAssertEqual(SAViewMode.structure.tabIndex, 0)
        XCTAssertEqual(SAViewMode.content.tabIndex,   1)
        XCTAssertEqual(SAViewMode.query.tabIndex,     2)
        XCTAssertEqual(SAViewMode.status.tabIndex,    3)
        XCTAssertEqual(SAViewMode.relations.tabIndex, 4)
        XCTAssertEqual(SAViewMode.triggers.tabIndex,  5)
    }

    func testTabIndexesAreContiguousAndUnique() {
        let indexes = SAViewMode.allCases.map(\.tabIndex)
        XCTAssertEqual(indexes.sorted(), Array(0..<SAViewMode.allCases.count))
        XCTAssertEqual(Set(indexes).count, SAViewMode.allCases.count)
    }

    // MARK: - Toolbar identifiers

    /// The toolbar identifier of each view mode must exactly match the
    /// corresponding `SPMainToolbar*` constant defined in SPConstants.m
    /// — these are used to look up the selected toolbar item, and the
    /// matching toolbar item targets the same view mode.
    ///
    /// The strings are pinned as literals here because the Unit Tests
    /// target has no ObjC bridging header, so the C extern symbols
    /// aren't visible from Swift. This doubles as a regression guard:
    /// if anyone renames the constant in SPConstants.m, persisted
    /// toolbar selections from existing installs break, and this test
    /// fires.
    func testToolbarIdentifiersMatchConstants() {
        XCTAssertEqual(SAViewMode.structure.toolbarIdentifier.rawValue, "SwitchToTableStructureToolbarItemIdentifier")
        XCTAssertEqual(SAViewMode.content.toolbarIdentifier.rawValue,   "SwitchToTableContentToolbarItemIdentifier")
        XCTAssertEqual(SAViewMode.query.toolbarIdentifier.rawValue,     "SwitchToRunQueryToolbarItemIdentifier")
        XCTAssertEqual(SAViewMode.status.toolbarIdentifier.rawValue,    "SwitchToTableInfoToolbarItemIdentifier")
        XCTAssertEqual(SAViewMode.relations.toolbarIdentifier.rawValue, "SwitchToTableRelationsToolbarItemIdentifier")
        XCTAssertEqual(SAViewMode.triggers.toolbarIdentifier.rawValue,  "SwitchToTableTriggersToolbarItemIdentifier")
    }

    func testToolbarIdentifiersAreUnique() {
        let identifiers = SAViewMode.allCases.map(\.toolbarIdentifier)
        XCTAssertEqual(Set(identifiers).count, SAViewMode.allCases.count)
    }

    // MARK: - Preferences round-trip

    /// The legacy SPViewMode preferences values are:
    ///   1 = Structure, 2 = Content, 3 = Relations, 4 = TableInfo,
    ///   5 = QueryEditor, 6 = Triggers
    /// (declared in SPConstants.h). Note the order is NOT 1..6 by
    /// enum case order — `query` is 5 and `status` is 4. This test
    /// pins those exact integers because they're already stored in
    /// user defaults on existing installs and must not drift.
    func testPreferencesValues() {
        XCTAssertEqual(SAViewMode.structure.preferencesValue, 1)
        XCTAssertEqual(SAViewMode.content.preferencesValue,   2)
        XCTAssertEqual(SAViewMode.relations.preferencesValue, 3)
        XCTAssertEqual(SAViewMode.status.preferencesValue,    4)
        XCTAssertEqual(SAViewMode.query.preferencesValue,     5)
        XCTAssertEqual(SAViewMode.triggers.preferencesValue,  6)
    }

    func testPreferencesRoundTrip() {
        for mode in SAViewMode.allCases {
            let restored = SAViewMode.fromPreferences(mode.preferencesValue)
            XCTAssertEqual(restored, mode, "round-trip failed for \(mode)")
        }
    }

    /// Unknown / corrupted preference values must fall back to a known
    /// good mode rather than crashing or returning a bogus case.
    func testFromPreferencesFallsBackForUnknownValue() {
        XCTAssertEqual(SAViewMode.fromPreferences(0),    .structure)
        XCTAssertEqual(SAViewMode.fromPreferences(-1),   .structure)
        XCTAssertEqual(SAViewMode.fromPreferences(7),    .structure)
        XCTAssertEqual(SAViewMode.fromPreferences(9999), .structure)
    }

    // MARK: - Action selector names

    /// These selector names are wired up by `makeToolbarItem` and
    /// must match the ObjC entry points on SPDatabaseDocument
    /// (-viewStructure, -viewContent, ...).
    func testActionSelectorNames() {
        XCTAssertEqual(SAViewMode.structure.actionSelectorName, "viewStructure")
        XCTAssertEqual(SAViewMode.content.actionSelectorName,   "viewContent")
        XCTAssertEqual(SAViewMode.query.actionSelectorName,     "viewQuery")
        XCTAssertEqual(SAViewMode.status.actionSelectorName,    "viewStatus")
        XCTAssertEqual(SAViewMode.relations.actionSelectorName, "viewRelations")
        XCTAssertEqual(SAViewMode.triggers.actionSelectorName,  "viewTriggers")
    }

    // MARK: - Toolbar item factory

    func testMakeToolbarItemConfiguration() {
        let target = NSObject()

        for mode in SAViewMode.allCases {
            let item = mode.makeToolbarItem(target: target)

            XCTAssertEqual(item.itemIdentifier, mode.toolbarIdentifier,
                           "wrong identifier for \(mode)")
            XCTAssertEqual(item.label, mode.toolbarLabel,
                           "wrong label for \(mode)")
            XCTAssertEqual(item.paletteLabel, mode.toolbarLabel,
                           "palette label should match label for \(mode)")
            XCTAssertEqual(item.toolTip, mode.toolbarTooltip,
                           "wrong tooltip for \(mode)")
            XCTAssertNotNil(item.image, "missing image for \(mode)")
            XCTAssertTrue(item.target === target, "wrong target for \(mode)")
            XCTAssertEqual(item.action, NSSelectorFromString(mode.actionSelectorName),
                           "wrong action for \(mode)")
        }
    }

    func testToolbarLabelsAreNonEmpty() {
        for mode in SAViewMode.allCases {
            XCTAssertFalse(mode.toolbarLabel.isEmpty, "empty label for \(mode)")
            XCTAssertFalse(mode.toolbarTooltip.isEmpty, "empty tooltip for \(mode)")
        }
    }

    // MARK: - SAViewModeHelper ObjC bridges

    func testHelperTabIndex() {
        for mode in SAViewMode.allCases {
            XCTAssertEqual(SAViewModeHelper.tabIndex(for: mode), mode.tabIndex)
        }
    }

    func testHelperToolbarIdentifier() {
        for mode in SAViewMode.allCases {
            XCTAssertEqual(SAViewModeHelper.toolbarIdentifier(for: mode),
                           mode.toolbarIdentifier.rawValue)
        }
    }

    func testHelperPreferencesValue() {
        for mode in SAViewMode.allCases {
            XCTAssertEqual(SAViewModeHelper.preferencesValue(for: mode),
                           mode.preferencesValue)
        }
    }

    func testHelperToolbarIdentifierForPreferencesValue() {
        // Round-trip through the legacy-prefs entry point used by the
        // toolbar code when reading a previously stored mode.
        for mode in SAViewMode.allCases {
            XCTAssertEqual(
                SAViewModeHelper.toolbarIdentifier(forPreferencesValue: mode.preferencesValue),
                mode.toolbarIdentifier.rawValue
            )
        }
    }

    func testHelperAllToolbarIdentifiers() {
        let identifiers = SAViewModeHelper.allToolbarIdentifiers
        XCTAssertEqual(identifiers.count, SAViewMode.allCases.count)
        XCTAssertEqual(Set(identifiers), Set(SAViewMode.allCases.map { $0.toolbarIdentifier.rawValue }))
    }

    // MARK: - Exhaustive case coverage

    /// If a new SAViewMode case is added, this test fails until each
    /// other test is updated. Keeps the suite honest about
    /// "all cases covered".
    func testCaseCountIsExpected() {
        XCTAssertEqual(SAViewMode.allCases.count, 6,
                       "SAViewMode case count changed — update all SAViewModeTests to cover the new case")
    }
}
