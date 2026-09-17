//
//  SACleartextAuthPolicyTests.swift
//  SPMySQLFramework
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//
//  More info at <https://github.com/Sequel-Ace/Sequel-Ace>
//

import Foundation
import XCTest
@testable import SPMySQL

final class SACleartextAuthPolicyTests: XCTestCase {

    // MARK: - Requiring TLS

    func testCleartextPluginRequiresTLSEvenWhenSSLWasNotRequested() {
        XCTAssertTrue(SACleartextAuthPolicy.requiresTLS(cleartextPluginEnabled: true, sslRequested: false))
    }

    func testRequestedSSLRequiresTLS() {
        XCTAssertTrue(SACleartextAuthPolicy.requiresTLS(cleartextPluginEnabled: false, sslRequested: true))
    }

    func testCleartextPluginWithRequestedSSLRequiresTLS() {
        XCTAssertTrue(SACleartextAuthPolicy.requiresTLS(cleartextPluginEnabled: true, sslRequested: true))
    }

    func testPlainConnectionOnlyPrefersTLS() {
        XCTAssertFalse(SACleartextAuthPolicy.requiresTLS(cleartextPluginEnabled: false, sslRequested: false))
    }

    // MARK: - Retrying Without TLS

    func testRetryWithoutTLSIsWithheldFromACleartextPassword() {
        XCTAssertFalse(SACleartextAuthPolicy.allowsRetryWithoutTLS(cleartextPluginEnabled: true, sslRequested: false))
    }

    func testRetryWithoutTLSIsWithheldWhenSSLWasRequested() {
        XCTAssertFalse(SACleartextAuthPolicy.allowsRetryWithoutTLS(cleartextPluginEnabled: false, sslRequested: true))
    }

    func testRetryWithoutTLSIsWithheldWhenBothApply() {
        XCTAssertFalse(SACleartextAuthPolicy.allowsRetryWithoutTLS(cleartextPluginEnabled: true, sslRequested: true))
    }

    func testRetryWithoutTLSRemainsAvailableForAPlainConnection() {
        XCTAssertTrue(SACleartextAuthPolicy.allowsRetryWithoutTLS(cleartextPluginEnabled: false, sslRequested: false))
    }

    // MARK: - Relationship Between The Two Decisions

    func testAnAttemptThatRequiresTLSNeverRetriesWithoutIt() {
        for cleartextPluginEnabled in [true, false] {
            for sslRequested in [true, false] {
                let requiresTLS = SACleartextAuthPolicy.requiresTLS(cleartextPluginEnabled: cleartextPluginEnabled,
                                                                    sslRequested: sslRequested)
                let allowsRetry = SACleartextAuthPolicy.allowsRetryWithoutTLS(cleartextPluginEnabled: cleartextPluginEnabled,
                                                                              sslRequested: sslRequested)

                XCTAssertNotEqual(requiresTLS, allowsRetry,
                                  "cleartext=\(cleartextPluginEnabled) ssl=\(sslRequested)")
            }
        }
    }
}
