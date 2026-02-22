//
//  RDSIAMAuthenticationTests.swift
//  Sequel Ace
//
//  Unit tests for RDS IAM authentication token generation.
//

import XCTest
@testable import Sequel_Ace

final class RDSIAMAuthenticationTests: XCTestCase {

    // MARK: - Region Detection Tests

    func testRegionFromStandardRDSHostname() {
        let hostname = "mydb.123456789012.us-east-1.rds.amazonaws.com"
        let region = RDSIAMAuthentication.regionFromHostname(hostname)
        XCTAssertEqual(region, "us-east-1")
    }

    func testRegionFromAuroraHostname() {
        let hostname = "mydb-cluster.cluster-abc123.eu-west-2.rds.amazonaws.com"
        let region = RDSIAMAuthentication.regionFromHostname(hostname)
        XCTAssertEqual(region, "eu-west-2")
    }

    func testRegionFromProxyHostname() {
        let hostname = "mydb-proxy.proxy-abc123.ap-southeast-1.rds.amazonaws.com"
        let region = RDSIAMAuthentication.regionFromHostname(hostname)
        XCTAssertEqual(region, "ap-southeast-1")
    }

    func testRegionFromGovCloudHostname() {
        let hostname = "mydb.123456789012.us-gov-west-1.rds.amazonaws.com"
        let region = RDSIAMAuthentication.regionFromHostname(hostname)
        XCTAssertEqual(region, "us-gov-west-1")
    }

    func testRegionFromChinaHostname() {
        let hostname = "mydb.123456789012.cn-north-1.rds.amazonaws.com.cn"
        let region = RDSIAMAuthentication.regionFromHostname(hostname)
        XCTAssertEqual(region, "cn-north-1")
    }

    func testRegionFromNewerPartition() {
        // Test il (Israel) region
        let hostnameIL = "mydb.123456789012.il-central-1.rds.amazonaws.com"
        let regionIL = RDSIAMAuthentication.regionFromHostname(hostnameIL)
        XCTAssertEqual(regionIL, "il-central-1")

        // Test mx (Mexico) region - hypothetical
        let hostnameMX = "mydb.123456789012.mx-central-1.rds.amazonaws.com"
        let regionMX = RDSIAMAuthentication.regionFromHostname(hostnameMX)
        XCTAssertEqual(regionMX, "mx-central-1")
    }

    func testRegionFromNonRDSHostname() {
        let hostname = "localhost"
        let region = RDSIAMAuthentication.regionFromHostname(hostname)
        XCTAssertNil(region)
    }

    func testRegionFromEmptyHostname() {
        let region = RDSIAMAuthentication.regionFromHostname("")
        XCTAssertNil(region)
    }

    // MARK: - Region Validation Tests

    func testIsValidAWSRegion() {
        // Standard regions
        XCTAssertTrue(RDSIAMAuthentication.isValidAWSRegion("us-east-1"))
        XCTAssertTrue(RDSIAMAuthentication.isValidAWSRegion("us-west-2"))
        XCTAssertTrue(RDSIAMAuthentication.isValidAWSRegion("eu-west-1"))
        XCTAssertTrue(RDSIAMAuthentication.isValidAWSRegion("ap-southeast-1"))
        XCTAssertTrue(RDSIAMAuthentication.isValidAWSRegion("sa-east-1"))
        XCTAssertTrue(RDSIAMAuthentication.isValidAWSRegion("ca-central-1"))
        XCTAssertTrue(RDSIAMAuthentication.isValidAWSRegion("me-south-1"))
        XCTAssertTrue(RDSIAMAuthentication.isValidAWSRegion("af-south-1"))

        // GovCloud
        XCTAssertTrue(RDSIAMAuthentication.isValidAWSRegion("us-gov-west-1"))
        XCTAssertTrue(RDSIAMAuthentication.isValidAWSRegion("us-gov-east-1"))

        // China
        XCTAssertTrue(RDSIAMAuthentication.isValidAWSRegion("cn-north-1"))
        XCTAssertTrue(RDSIAMAuthentication.isValidAWSRegion("cn-northwest-1"))

        // Newer partitions
        XCTAssertTrue(RDSIAMAuthentication.isValidAWSRegion("il-central-1"))
        XCTAssertTrue(RDSIAMAuthentication.isValidAWSRegion("mx-central-1"))

        // Multi-digit suffixes
        XCTAssertTrue(RDSIAMAuthentication.isValidAWSRegion("ap-northeast-12"))
    }

    func testIsInvalidAWSRegion() {
        XCTAssertFalse(RDSIAMAuthentication.isValidAWSRegion("invalid"))
        XCTAssertFalse(RDSIAMAuthentication.isValidAWSRegion("us-east"))
        XCTAssertFalse(RDSIAMAuthentication.isValidAWSRegion("us-east-0"))
        XCTAssertFalse(RDSIAMAuthentication.isValidAWSRegion(""))
        XCTAssertFalse(RDSIAMAuthentication.isValidAWSRegion("123456789012"))
    }

    // MARK: - RDS Hostname Detection Tests

    func testIsRDSHostname() {
        XCTAssertTrue(RDSIAMAuthentication.isRDSHostname("mydb.123456789012.us-east-1.rds.amazonaws.com"))
        XCTAssertTrue(RDSIAMAuthentication.isRDSHostname("mydb.123456789012.cn-north-1.rds.amazonaws.com.cn"))
        XCTAssertTrue(RDSIAMAuthentication.isRDSHostname("something.rds.local"))
    }

    func testIsRDSHostnameCaseInsensitive() {
        XCTAssertTrue(RDSIAMAuthentication.isRDSHostname("MYDB.123456789012.US-EAST-1.RDS.AMAZONAWS.COM"))
    }

    func testIsNotRDSHostname() {
        XCTAssertFalse(RDSIAMAuthentication.isRDSHostname("localhost"))
        XCTAssertFalse(RDSIAMAuthentication.isRDSHostname("192.168.1.1"))
        XCTAssertFalse(RDSIAMAuthentication.isRDSHostname("mydb.amazonaws.com"))
        XCTAssertFalse(RDSIAMAuthentication.isRDSHostname(""))
    }

    // MARK: - Token Generation Tests

    func testGenerateAuthTokenWithValidCredentials() throws {
        let creds = AWSCredentials(
            accessKeyId: "AKIAIOSFODNN7EXAMPLE",
            secretAccessKey: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
        )

        let token = try RDSIAMAuthentication.generateAuthToken(
            forHost: "mydb.123456789012.us-east-1.rds.amazonaws.com",
            port: 3306,
            username: "admin",
            region: "us-east-1",
            credentials: creds
        )

        XCTAssertFalse(token.isEmpty)
        XCTAssertTrue(token.contains("X-Amz-Algorithm=AWS4-HMAC-SHA256"))
        XCTAssertTrue(token.contains("X-Amz-Credential=AKIAIOSFODNN7EXAMPLE"))
        XCTAssertTrue(token.contains("X-Amz-Signature="))
        XCTAssertTrue(token.contains("DBUser=admin"))
    }

    func testGenerateAuthTokenWithSessionToken() throws {
        let creds = AWSCredentials(
            accessKeyId: "AKIAIOSFODNN7EXAMPLE",
            secretAccessKey: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
            sessionToken: "FwoGZXIvYXdzEBYaDExampleSessionToken"
        )

        let token = try RDSIAMAuthentication.generateAuthToken(
            forHost: "mydb.123456789012.us-east-1.rds.amazonaws.com",
            port: 3306,
            username: "admin",
            region: "us-east-1",
            credentials: creds
        )

        XCTAssertTrue(token.contains("X-Amz-Security-Token="))
    }

    func testGenerateAuthTokenAutoDetectsRegion() throws {
        let creds = AWSCredentials(
            accessKeyId: "AKIAIOSFODNN7EXAMPLE",
            secretAccessKey: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
        )

        // Should auto-detect region from hostname
        let token = try RDSIAMAuthentication.generateAuthToken(
            forHost: "mydb.123456789012.eu-west-2.rds.amazonaws.com",
            port: 3306,
            username: "admin",
            region: nil,
            credentials: creds
        )

        XCTAssertFalse(token.isEmpty)
        XCTAssertTrue(token.contains("eu-west-2"))
    }

    func testGenerateAuthTokenUsesDefaultMySQLPortWhenPortIsZero() throws {
        let creds = AWSCredentials(
            accessKeyId: "AKIAIOSFODNN7EXAMPLE",
            secretAccessKey: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
        )

        let token = try RDSIAMAuthentication.generateAuthToken(
            forHost: "mydb.123456789012.us-east-1.rds.amazonaws.com",
            port: 0,
            username: "admin",
            region: "us-east-1",
            credentials: creds
        )

        XCTAssertTrue(token.hasPrefix("mydb.123456789012.us-east-1.rds.amazonaws.com:3306/?"))
    }

    func testGenerateAuthTokenEncodesUsernameForQueryString() throws {
        let creds = AWSCredentials(
            accessKeyId: "AKIAIOSFODNN7EXAMPLE",
            secretAccessKey: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
        )

        let token = try RDSIAMAuthentication.generateAuthToken(
            forHost: "mydb.123456789012.us-east-1.rds.amazonaws.com",
            port: 3306,
            username: "admin+ops@example.com",
            region: "us-east-1",
            credentials: creds
        )

        XCTAssertTrue(token.contains("DBUser=admin%2Bops%40example.com"))
    }

    func testGenerateAuthTokenThrowsForInvalidCredentials() {
        let invalidCreds = AWSCredentials(accessKeyId: "", secretAccessKey: "")

        XCTAssertThrowsError(try RDSIAMAuthentication.generateAuthToken(
            forHost: "mydb.us-east-1.rds.amazonaws.com",
            port: 3306,
            username: "admin",
            region: "us-east-1",
            credentials: invalidCreds
        )) { error in
            XCTAssertTrue(error is RDSIAMAuthenticationError)
        }
    }

    func testGenerateAuthTokenThrowsForEmptyHostname() {
        let creds = AWSCredentials(
            accessKeyId: "AKIAIOSFODNN7EXAMPLE",
            secretAccessKey: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
        )

        XCTAssertThrowsError(try RDSIAMAuthentication.generateAuthToken(
            forHost: "",
            port: 3306,
            username: "admin",
            region: "us-east-1",
            credentials: creds
        ))
    }

    func testGenerateAuthTokenThrowsForEmptyUsername() {
        let creds = AWSCredentials(
            accessKeyId: "AKIAIOSFODNN7EXAMPLE",
            secretAccessKey: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
        )

        XCTAssertThrowsError(try RDSIAMAuthentication.generateAuthToken(
            forHost: "mydb.us-east-1.rds.amazonaws.com",
            port: 3306,
            username: "",
            region: "us-east-1",
            credentials: creds
        ))
    }

    func testGenerateAuthTokenObjCMapsErrorsToNSError() {
        var error: NSError?
        let token = RDSIAMAuthentication.generateAuthTokenObjC(
            forHost: "",
            port: 3306,
            username: "admin",
            region: "us-east-1",
            credentials: AWSCredentials(
                accessKeyId: "AKIAIOSFODNN7EXAMPLE",
                secretAccessKey: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
            ),
            error: &error
        )

        XCTAssertNil(token)
        XCTAssertEqual(error?.domain, "RDSIAMAuthenticationErrorDomain")
        XCTAssertEqual(error?.code, RDSIAMAuthenticationError.invalidParameters.rawValue)
    }

    // MARK: - Token Lifetime Tests

    func testTokenLifetimeSeconds() {
        XCTAssertEqual(RDSIAMAuthentication.tokenLifetimeSeconds, 900) // 15 minutes
    }
}
