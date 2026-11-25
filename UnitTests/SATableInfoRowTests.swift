//
//  SATableInfoRowTests.swift
//  Unit Tests
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import XCTest

final class SATableInfoRowTests: XCTestCase {

    private let english = Locale(identifier: "en_US")

    private func row(_ label: String, _ value: String) -> SATableInfoRow {
        SATableInfoRow(label: label, value: value)
    }

    func testSplitsAtTheColon() {
        XCTAssertEqual(SATableInfoRow.split("rows: 200", locale: english), row("Rows", "200"))
        XCTAssertEqual(SATableInfoRow.split("rows: ~1,024", locale: english), row("Rows", "~1,024"))
    }

    func testValueKeepsLaterColons() {
        XCTAssertEqual(SATableInfoRow.split("created: 21/10/26, 8:51 AM", locale: english), row("Created", "21/10/26, 8:51 AM"))
        XCTAssertEqual(SATableInfoRow.split("definer: root@%:3306", locale: english), row("Definer", "root@%:3306"))
    }

    func testValueWithTwoArguments() {
        XCTAssertEqual(SATableInfoRow.split("encoding: utf8mb4 (utf8mb4_0900_ai_ci)", locale: english),
                       row("Encoding", "utf8mb4 (utf8mb4_0900_ai_ci)"))
    }

    func testFrenchSeparatorHasASpaceBefore() {
        let french = Locale(identifier: "fr_FR")
        XCTAssertEqual(SATableInfoRow.split("lignes : 200", locale: french), row("Lignes", "200"))
        // French typography often uses a no-break space before the colon.
        XCTAssertEqual(SATableInfoRow.split("lignes\u{00A0}: 200", locale: french), row("Lignes", "200"))
    }

    func testChineseFullWidthColon() {
        XCTAssertEqual(SATableInfoRow.split("行数：200", locale: Locale(identifier: "zh_Hans")), row("行数", "200"))
    }

    func testTextWithoutASeparatorIsNotSplit() {
        XCTAssertNil(SATableInfoRow.split("multiple selection", locale: english))
        XCTAssertNil(SATableInfoRow.split("TABLE INFORMATION", locale: english))
        XCTAssertNil(SATableInfoRow.split("", locale: english))
    }

    func testEmptySideIsNotSplit() {
        XCTAssertNil(SATableInfoRow.split(": x", locale: english))
        XCTAssertNil(SATableInfoRow.split("x: ", locale: english))
        XCTAssertNil(SATableInfoRow.split(":", locale: english))
        XCTAssertNil(SATableInfoRow.split("  ：  ", locale: english))
    }

    func testLabelIsCapitalizedForTheLocale() {
        XCTAssertEqual(SATableInfoRow.split("isim: x", locale: Locale(identifier: "tr_TR"))?.label, "İsim")
        XCTAssertEqual(SATableInfoRow.split("isim: x", locale: english)?.label, "Isim")
        // Only the first letter changes.
        XCTAssertEqual(SATableInfoRow.split("auto_increment: 7", locale: english)?.label, "Auto_increment")
        XCTAssertEqual(SATableInfoRow.split("is updatable: YES", locale: english)?.label, "Is updatable")
    }
}
