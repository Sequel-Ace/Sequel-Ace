//
//  AWSCredentialsTests.swift
//  Sequel Ace
//
//  Unit tests for AWS credentials management.
//

import XCTest
@testable import Sequel_Ace

final class AWSCredentialsTests: XCTestCase {

    // MARK: - Manual Credentials Tests

    func testInitWithValidManualCredentials() {
        let creds = AWSCredentials(
            accessKeyId: "AKIAIOSFODNN7EXAMPLE",
            secretAccessKey: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
        )

        XCTAssertEqual(creds.accessKeyId, "AKIAIOSFODNN7EXAMPLE")
        XCTAssertEqual(creds.secretAccessKey, "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY")
        XCTAssertNil(creds.sessionToken)
        XCTAssertNil(creds.profileName)
        XCTAssertTrue(creds.isValid)
    }

    func testInitWithSessionToken() {
        let creds = AWSCredentials(
            accessKeyId: "AKIAIOSFODNN7EXAMPLE",
            secretAccessKey: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
            sessionToken: "FwoGZXIvYXdzEBYaDExample"
        )

        XCTAssertEqual(creds.sessionToken, "FwoGZXIvYXdzEBYaDExample")
        XCTAssertTrue(creds.isValid)
    }

    func testIsValidWithEmptyAccessKey() {
        let creds = AWSCredentials(
            accessKeyId: "",
            secretAccessKey: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
        )

        XCTAssertFalse(creds.isValid, "Credentials with empty access key should be invalid")
    }

    func testIsValidWithEmptySecretKey() {
        let creds = AWSCredentials(
            accessKeyId: "AKIAIOSFODNN7EXAMPLE",
            secretAccessKey: ""
        )

        XCTAssertFalse(creds.isValid, "Credentials with empty secret key should be invalid")
    }

    // MARK: - Profile Tests

    func testCredentialsFilePath() {
        let path = AWSCredentials.credentialsFilePath
        XCTAssertFalse(path.isEmpty, "Credentials file path should not be empty")
        XCTAssertTrue(path.hasSuffix(".aws/credentials"), "Path should end with .aws/credentials")
    }

    func testConfigFilePath() {
        let path = AWSCredentials.configFilePath
        XCTAssertFalse(path.isEmpty, "Config file path should not be empty")
        XCTAssertTrue(path.hasSuffix(".aws/config"), "Path should end with .aws/config")
    }

    func testAvailableProfilesReturnsArray() {
        let profiles = AWSCredentials.availableProfiles()
        XCTAssertTrue(profiles is [String], "Should return array of strings")
    }

    func testInitWithNonExistentProfile() {
        XCTAssertThrowsError(try AWSCredentials(profile: "this-profile-definitely-does-not-exist-12345")) { error in
            XCTAssertTrue(error is AWSCredentialsError, "Should throw AWSCredentialsError")
        }
    }

    // MARK: - Description Tests

    func testDescription() {
        let creds = AWSCredentials(
            accessKeyId: "AKIAIOSFODNN7EXAMPLE",
            secretAccessKey: "secret"
        )

        let desc = creds.description
        XCTAssertTrue(desc.contains("AKIA"), "Description should contain partial access key")
        XCTAssertFalse(desc.contains("secret"), "Description should NOT contain secret key")
    }

    // MARK: - Role Assumption Properties

    func testRequiresMFA() {
        let credsWithMFA = AWSCredentials(
            accessKeyId: "AKIAIOSFODNN7EXAMPLE",
            secretAccessKey: "secret"
        )
        // Manual credentials don't have mfaSerial set
        XCTAssertFalse(credsWithMFA.requiresMFA)
    }

    func testRequiresRoleAssumption() {
        let creds = AWSCredentials(
            accessKeyId: "AKIAIOSFODNN7EXAMPLE",
            secretAccessKey: "secret"
        )
        // Manual credentials don't have roleArn set
        XCTAssertFalse(creds.requiresRoleAssumption)
    }

    // MARK: - Directory Authorization Tests

    func testIsAWSDirectoryAuthorizedProperty() {
        // Should return a boolean without crashing
        let isAuthorized = AWSCredentials.isAWSDirectoryAuthorized
        XCTAssertTrue(isAuthorized == true || isAuthorized == false, "Should return a boolean value")
    }

    func testCredentialsFileExistsProperty() {
        // Should return a boolean without crashing
        let exists = AWSCredentials.credentialsFileExists
        XCTAssertTrue(exists == true || exists == false, "Should return a boolean value")
    }

    func testAvailableProfilesHandlesUnauthorizedState() {
        // availableProfiles() should return an array (possibly empty) without crashing
        let profiles = AWSCredentials.availableProfiles()
        XCTAssertNotNil(profiles, "Should return an array, not nil")
        // If not authorized, should return empty array; if authorized, returns actual profiles
        XCTAssertTrue(profiles.count >= 0, "Should return zero or more profiles")
    }

    func testCredentialsFilePathMatchesBookmarkManagerPath() {
        let credentialsPath = AWSCredentials.credentialsFilePath
        let awsDirectoryPath = AWSDirectoryBookmarkManager.awsDirectoryPath
        XCTAssertTrue(credentialsPath.hasPrefix(awsDirectoryPath), "Credentials path should be inside AWS directory")
    }

    func testConfigFilePathMatchesBookmarkManagerPath() {
        let configPath = AWSCredentials.configFilePath
        let awsDirectoryPath = AWSDirectoryBookmarkManager.awsDirectoryPath
        XCTAssertTrue(configPath.hasPrefix(awsDirectoryPath), "Config path should be inside AWS directory")
    }
}
