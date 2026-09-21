//
//  SAConnectionLostSheetCopyTests.swift
//  Unit Tests
//
//  Copyright (c) 2026 Sequel-Ace. All rights reserved.
//

import XCTest

final class SAConnectionLostSheetCopyTests: XCTestCase {

    // MARK: - Default Copy

    func testDefaultCopyWithoutError() {
        let copy = SAConnectionLostSheetCopy.make(awsIAMTokenError: nil, isAWSIAMConnection: true)

        XCTAssertEqual(copy.title, SAConnectionLostSheetCopy.defaultTitle)
        XCTAssertEqual(copy.message, SAConnectionLostSheetCopy.defaultMessage)
    }

    func testDefaultCopyForNonAWSIAMConnection() {
        let copy = SAConnectionLostSheetCopy.make(awsIAMTokenError: AWSLoginAuthError.sessionExpired as NSError,
                                                  isAWSIAMConnection: false)

        XCTAssertEqual(copy.title, SAConnectionLostSheetCopy.defaultTitle)
        XCTAssertEqual(copy.message, SAConnectionLostSheetCopy.defaultMessage)
    }

    // MARK: - Lapsed Session Copy

    func testLapsedConsoleSignInSessionNamesAwsLogin() {
        let copy = SAConnectionLostSheetCopy.make(awsIAMTokenError: AWSLoginAuthError.sessionExpired as NSError,
                                                  isAWSIAMConnection: true)

        XCTAssertEqual(copy.title, SAConnectionLostSheetCopy.awsSignInTitle)
        XCTAssertTrue(copy.message.contains("run `aws login`"), copy.message)
        XCTAssertTrue(copy.message.contains("click Reconnect"), copy.message)
        XCTAssertFalse(copy.message.contains("%@"), copy.message)
    }

    func testMissingConsoleSignInSessionNamesAwsLogin() {
        let copy = SAConnectionLostSheetCopy.make(awsIAMTokenError: AWSLoginAuthError.cacheNotFound as NSError,
                                                  isAWSIAMConnection: true)

        XCTAssertTrue(copy.message.contains("run `aws login`"), copy.message)
    }

    func testExpiredSSOTokenNamesAwsSsoLogin() {
        let copy = SAConnectionLostSheetCopy.make(awsIAMTokenError: AWSSSOClientError.tokenExpired as NSError,
                                                  isAWSIAMConnection: true)

        XCTAssertEqual(copy.title, SAConnectionLostSheetCopy.awsSignInTitle)
        XCTAssertTrue(copy.message.contains("run `aws sso login`"), copy.message)
        XCTAssertFalse(copy.message.contains("%@"), copy.message)
    }

    func testMissingSSOTokenNamesAwsSsoLogin() {
        let copy = SAConnectionLostSheetCopy.make(awsIAMTokenError: AWSSSOClientError.tokenNotFound as NSError,
                                                  isAWSIAMConnection: true)

        XCTAssertTrue(copy.message.contains("run `aws sso login`"), copy.message)
    }

    // MARK: - Other Failures

    func testUnrelatedErrorEmbedsItsDescription() {
        let error = NSError(domain: "AWSIAMAuthErrorDomain",
                            code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "MFA authentication was cancelled"])

        let copy = SAConnectionLostSheetCopy.make(awsIAMTokenError: error, isAWSIAMConnection: true)

        XCTAssertEqual(copy.title, SAConnectionLostSheetCopy.awsSignInTitle)
        XCTAssertTrue(copy.message.contains("MFA authentication was cancelled"), copy.message)
        XCTAssertTrue(copy.message.contains("Fix the AWS credentials"), copy.message)
        XCTAssertFalse(copy.message.contains("%@"), copy.message)
    }

    func testBlankDescriptionUsesFallback() {
        let error = NSError(domain: "AWSIAMAuthErrorDomain",
                            code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "   "])

        let copy = SAConnectionLostSheetCopy.make(awsIAMTokenError: error, isAWSIAMConnection: true)

        XCTAssertTrue(copy.message.contains(SAConnectionLostSheetCopy.unknownErrorDescription), copy.message)
    }

    func testProfileMisconfigurationIsNotReportedAsALapsedSession() {
        let copy = SAConnectionLostSheetCopy.make(awsIAMTokenError: AWSLoginAuthError.invalidProfile as NSError,
                                                  isAWSIAMConnection: true)

        XCTAssertFalse(copy.message.contains("In Terminal, run"), copy.message)
        XCTAssertTrue(copy.message.contains("Fix the AWS credentials"), copy.message)
    }

    // MARK: - Command Mapping

    func testLapsedSessionIsRecognisedFromABridgedNSErrorDomain() {
        let bridged = AWSLoginAuthError.sessionExpired as NSError
        let rebuilt = NSError(domain: bridged.domain,
                              code: bridged.code,
                              userInfo: [NSLocalizedDescriptionKey: "expired"])

        let copy = SAConnectionLostSheetCopy.make(awsIAMTokenError: rebuilt, isAWSIAMConnection: true)

        XCTAssertTrue(copy.message.contains("run `aws login`"), copy.message)
    }

    func testSignInCommandMapping() {
        XCTAssertEqual(SAConnectionLostSheetCopy.awsSignInCommand(for: AWSLoginAuthError.sessionExpired), "aws login")
        XCTAssertEqual(SAConnectionLostSheetCopy.awsSignInCommand(for: AWSSSOClientError.tokenExpired), "aws sso login")
        XCTAssertNil(SAConnectionLostSheetCopy.awsSignInCommand(for: AWSSSOClientError.accessDenied))
        XCTAssertNil(SAConnectionLostSheetCopy.awsSignInCommand(for: AWSLoginAuthError.invalidCacheContents))
    }

    // MARK: - Buttons

    func testButtonTitles() {
        XCTAssertEqual(SAConnectionLostSheetCopy.reconnectButtonTitle, "Reconnect")
        XCTAssertEqual(SAConnectionLostSheetCopy.closeConnectionButtonTitle, "Close connection")
    }
}
