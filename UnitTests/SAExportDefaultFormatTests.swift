//
//  SAExportDefaultFormatTests.swift
//  Sequel Ace
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import Foundation
import XCTest

final class SAExportDefaultFormatTests: XCTestCase {

    private func format(_ preference: SAExportDefaultFormat, resultDisplayed: Bool) -> SAExportDefaultFormat {
        SAExportDefaultFormatResolver.format(forPreference: preference.rawValue, isResultDisplayed: resultDisplayed)
    }

    // MARK: - Automatic keeps the original behaviour

    func testAutomaticOpensOnCSVWhenAResultIsDisplayed() {
        XCTAssertEqual(format(.automatic, resultDisplayed: true), .csv)
    }

    func testAutomaticKeepsTheLastFormatWhenNoResultIsDisplayed() {
        XCTAssertEqual(format(.automatic, resultDisplayed: false), .automatic)
    }

    func testUnknownPreferenceCountsAsAutomatic() {
        XCTAssertEqual(SAExportDefaultFormatResolver.format(forPreference: 99, isResultDisplayed: true), .csv)
        XCTAssertEqual(SAExportDefaultFormatResolver.format(forPreference: -1, isResultDisplayed: false), .automatic)
    }

    // MARK: - A chosen format always wins (#1622)

    func testChosenFormatWinsWhateverIsDisplayed() {
        for chosen in [SAExportDefaultFormat.sql, .csv, .xml, .dot] {
            XCTAssertEqual(format(chosen, resultDisplayed: true), chosen)
            XCTAssertEqual(format(chosen, resultDisplayed: false), chosen)
        }
    }

    // MARK: - Export source

    func testCSVAndXMLCanExportTheDisplayedResult() {
        XCTAssertTrue(SAExportDefaultFormatResolver.canExportDisplayedResult(.csv))
        XCTAssertTrue(SAExportDefaultFormatResolver.canExportDisplayedResult(.xml))
    }

    func testSQLAndDotAreTableOnly() {
        XCTAssertFalse(SAExportDefaultFormatResolver.canExportDisplayedResult(.sql))
        XCTAssertFalse(SAExportDefaultFormatResolver.canExportDisplayedResult(.dot))
    }

    // MARK: - Persisted values and Preferences.xib tags

    func testRawValuesAreStable() {
        XCTAssertEqual(SAExportDefaultFormat.automatic.rawValue, 0)
        XCTAssertEqual(SAExportDefaultFormat.sql.rawValue, 1)
        XCTAssertEqual(SAExportDefaultFormat.csv.rawValue, 2)
        XCTAssertEqual(SAExportDefaultFormat.xml.rawValue, 3)
        XCTAssertEqual(SAExportDefaultFormat.dot.rawValue, 4)
    }
}
