//
//  SACellFilterColumnIdentifierTests.swift
//  Unit Tests
//
//  Created by Sequel-Ace contributors on 2026.05.23.
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import XCTest

final class SACellFilterColumnIdentifierTests: XCTestCase {

    /// Verifies integer-like identifiers resolve to storage column indexes.
    func testPureIntegerIdentifiersResolveStorageIndex() {
        XCTAssertEqual(SACellFilterColumnIdentifier.storageIndex(from: "0")?.intValue, 0)
        XCTAssertEqual(SACellFilterColumnIdentifier.storageIndex(from: "12")?.intValue, 12)
        XCTAssertEqual(SACellFilterColumnIdentifier.storageIndex(from: NSNumber(value: 7))?.intValue, 7)
        XCTAssertEqual(SACellFilterColumnIdentifier.storageIndex(from: NSUserInterfaceItemIdentifier("4"))?.intValue, 4)
    }

    /// Verifies nil, empty, mixed, whitespace, and negative identifiers are rejected.
    func testNonIntegerIdentifiersAreRejected() {
        XCTAssertNil(SACellFilterColumnIdentifier.storageIndex(from: nil))
        XCTAssertNil(SACellFilterColumnIdentifier.storageIndex(from: ""))
        XCTAssertNil(SACellFilterColumnIdentifier.storageIndex(from: "abc"))
        XCTAssertNil(SACellFilterColumnIdentifier.storageIndex(from: "12abc"))
        XCTAssertNil(SACellFilterColumnIdentifier.storageIndex(from: " 12"))
        XCTAssertNil(SACellFilterColumnIdentifier.storageIndex(from: "-1"))
    }

    /// Verifies a visible position resolves to the storage index of the column
    /// shown there once columns were moved - e.g. a column dragged to the end
    /// must not be checked with the definition of the column formerly there.
    func testVisibleColumnResolvesStorageIndexAfterColumnsMoved() {
        let table = NSTableView()
        for index in 0..<4 {
            table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier(String(index))))
        }

        table.moveColumn(1, toColumn: 3)

        XCTAssertEqual(SACellFilterColumnIdentifier.storageIndex(forVisibleColumn: 3, in: table), 1)
        XCTAssertEqual(SACellFilterColumnIdentifier.storageIndex(forVisibleColumn: 1, in: table), 2)
        XCTAssertEqual(SACellFilterColumnIdentifier.storageIndex(forVisibleColumn: 0, in: table), 0)
    }

    /// Verifies out-of-range positions and non-index identifiers resolve to -1.
    func testVisibleColumnOutOfRangeOrInvalidIdentifierResolvesToMinusOne() {
        let table = NSTableView()
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("abc")))

        XCTAssertEqual(SACellFilterColumnIdentifier.storageIndex(forVisibleColumn: 0, in: table), -1)
        XCTAssertEqual(SACellFilterColumnIdentifier.storageIndex(forVisibleColumn: -1, in: table), -1)
        XCTAssertEqual(SACellFilterColumnIdentifier.storageIndex(forVisibleColumn: 1, in: table), -1)
    }
}
