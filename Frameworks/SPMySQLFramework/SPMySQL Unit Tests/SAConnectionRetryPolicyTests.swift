//
//  SAConnectionRetryPolicyTests.swift
//  SPMySQLFramework
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//
//  More info at <https://github.com/Sequel-Ace/Sequel-Ace>
//

import XCTest
@testable import SPMySQL

final class SAConnectionRetryPolicyTests: XCTestCase {
    func testAHostThatWasNeverReachedIsNotTriedAgain() {
        XCTAssertFalse(SAConnectionRetryPolicy.shouldRetryWithoutTLS(afterErrorID: 2002)) // CR_CONNECTION_ERROR
        XCTAssertFalse(SAConnectionRetryPolicy.shouldRetryWithoutTLS(afterErrorID: 2003)) // CR_CONN_HOST_ERROR
        XCTAssertFalse(SAConnectionRetryPolicy.shouldRetryWithoutTLS(afterErrorID: 2005)) // CR_UNKNOWN_HOST
    }

    func testAServerThatAnsweredIsTriedWithoutTLS() {
        XCTAssertTrue(SAConnectionRetryPolicy.shouldRetryWithoutTLS(afterErrorID: 2026)) // CR_SSL_CONNECTION_ERROR
        XCTAssertTrue(SAConnectionRetryPolicy.shouldRetryWithoutTLS(afterErrorID: 2013)) // CR_SERVER_LOST, closed during the handshake
        XCTAssertTrue(SAConnectionRetryPolicy.shouldRetryWithoutTLS(afterErrorID: 1045)) // ER_ACCESS_DENIED_ERROR
        XCTAssertTrue(SAConnectionRetryPolicy.shouldRetryWithoutTLS(afterErrorID: 0))
    }
}
