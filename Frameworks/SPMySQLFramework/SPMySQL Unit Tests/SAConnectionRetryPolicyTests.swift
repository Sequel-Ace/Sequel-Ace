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
    /// A host that was never reached is not tried again.
    func testAHostThatWasNeverReachedIsNotTriedAgain() {
        XCTAssertFalse(SAConnectionRetryPolicy.shouldRetryWithoutTLS(afterErrorID: 2002)) // CR_CONNECTION_ERROR
        XCTAssertFalse(SAConnectionRetryPolicy.shouldRetryWithoutTLS(afterErrorID: 2003)) // CR_CONN_HOST_ERROR
        XCTAssertFalse(SAConnectionRetryPolicy.shouldRetryWithoutTLS(afterErrorID: 2005)) // CR_UNKNOWN_HOST
    }

    /// A failed TLS negotiation is tried without TLS.
    func testAFailedTLSNegotiationIsTriedWithoutTLS() {
        XCTAssertTrue(SAConnectionRetryPolicy.shouldRetryWithoutTLS(afterErrorID: 2026)) // CR_SSL_CONNECTION_ERROR
    }

    /// A connection lost after the negotiation may already have carried the credentials over TLS,
    /// so it is not repeated without TLS.
    func testAConnectionLostAfterTheNegotiationIsNotTriedWithoutTLS() {
        XCTAssertFalse(SAConnectionRetryPolicy.shouldRetryWithoutTLS(afterErrorID: 2013)) // CR_SERVER_LOST
        XCTAssertFalse(SAConnectionRetryPolicy.shouldRetryWithoutTLS(afterErrorID: 2055)) // CR_SERVER_LOST_EXTENDED
        XCTAssertFalse(SAConnectionRetryPolicy.shouldRetryWithoutTLS(afterErrorID: 2006)) // CR_SERVER_GONE_ERROR
    }

    /// Rejected credentials and any other or unknown error are not sent again without TLS.
    func testRejectedCredentialsAndOtherErrorsAreNotTriedWithoutTLS() {
        XCTAssertFalse(SAConnectionRetryPolicy.shouldRetryWithoutTLS(afterErrorID: 1045)) // ER_ACCESS_DENIED_ERROR
        XCTAssertFalse(SAConnectionRetryPolicy.shouldRetryWithoutTLS(afterErrorID: 1044)) // ER_DBACCESS_DENIED_ERROR
        XCTAssertFalse(SAConnectionRetryPolicy.shouldRetryWithoutTLS(afterErrorID: 1130)) // ER_HOST_NOT_PRIVILEGED
        XCTAssertFalse(SAConnectionRetryPolicy.shouldRetryWithoutTLS(afterErrorID: 2059)) // CR_AUTH_PLUGIN_CANNOT_LOAD
        XCTAssertFalse(SAConnectionRetryPolicy.shouldRetryWithoutTLS(afterErrorID: 2061)) // CR_AUTH_PLUGIN_ERR
        XCTAssertFalse(SAConnectionRetryPolicy.shouldRetryWithoutTLS(afterErrorID: 0))
    }
}
