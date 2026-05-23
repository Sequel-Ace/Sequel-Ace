//
//  SACellFilterColumnIdentifierTests.swift
//  Unit Tests
//
//  Created by Sequel-Ace contributors on 2026.05.23.
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import XCTest

final class SACellFilterColumnIdentifierTests: XCTestCase {

    func testPureIntegerIdentifiersResolveStorageIndex() {
        XCTAssertEqual(SACellFilterColumnIdentifier.storageIndex(from: "0")?.intValue, 0)
        XCTAssertEqual(SACellFilterColumnIdentifier.storageIndex(from: "12")?.intValue, 12)
        XCTAssertEqual(SACellFilterColumnIdentifier.storageIndex(from: NSNumber(value: 7))?.intValue, 7)
        XCTAssertEqual(SACellFilterColumnIdentifier.storageIndex(from: NSUserInterfaceItemIdentifier("4"))?.intValue, 4)
    }

    func testNonIntegerIdentifiersAreRejected() {
        XCTAssertNil(SACellFilterColumnIdentifier.storageIndex(from: nil))
        XCTAssertNil(SACellFilterColumnIdentifier.storageIndex(from: ""))
        XCTAssertNil(SACellFilterColumnIdentifier.storageIndex(from: "abc"))
        XCTAssertNil(SACellFilterColumnIdentifier.storageIndex(from: "12abc"))
        XCTAssertNil(SACellFilterColumnIdentifier.storageIndex(from: " 12"))
        XCTAssertNil(SACellFilterColumnIdentifier.storageIndex(from: "-1"))
    }
}
