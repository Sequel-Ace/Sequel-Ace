//
//  AWSCredentialsTests.swift
//  Sequel Ace
//
//  Unit tests for AWS credentials, STS validation, and IAM auth integration.
//

import XCTest

final class AWSCredentialsTests: XCTestCase {

    // MARK: - Manual Credentials

    func testManualCredentialsValidationAndFlags() {
        let credentials = AWSCredentials(
            accessKeyId: "AKIAIOSFODNN7EXAMPLE",
            secretAccessKey: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
            sessionToken: "session-token"
        )

        XCTAssertTrue(credentials.isValid)
        XCTAssertFalse(credentials.requiresMFA)
        XCTAssertFalse(credentials.requiresRoleAssumption)
        XCTAssertEqual(credentials.sessionToken, "session-token")
        XCTAssertNil(credentials.profileName)
    }

    func testManualCredentialsInvalidWhenAccessKeyMissing() {
        let credentials = AWSCredentials(accessKeyId: "", secretAccessKey: "secret")
        XCTAssertFalse(credentials.isValid)
    }

    func testManualCredentialsInvalidWhenSecretMissing() {
        let credentials = AWSCredentials(accessKeyId: "AKIAIOSFODNN7EXAMPLE", secretAccessKey: "")
        XCTAssertFalse(credentials.isValid)
    }

    // MARK: - File Paths

    func testCredentialsAndConfigFilePathsUseEnvironmentOverrides() throws {
        try AWSTestEnvironment.withTemporaryAWSFiles(credentials: "", config: "") { credentialsPath, configPath in
            XCTAssertEqual(AWSCredentials.credentialsFilePath, credentialsPath)
            XCTAssertEqual(AWSCredentials.configFilePath, configPath)
        }
    }

    // MARK: - Profile Loading

    func testProfileLoadsDefaultFromCredentialsFile() throws {
        let credentialsContents = """
        [default]
        aws_access_key_id = AKIADEFAULT0000000000
        aws_secret_access_key = defaultSecret
        aws_session_token = defaultToken
        """

        try AWSTestEnvironment.withTemporaryAWSFiles(credentials: credentialsContents, config: "") { _, _ in
            let credentials = try AWSCredentials(profile: nil)

            XCTAssertEqual(credentials.profileName, "default")
            XCTAssertEqual(credentials.accessKeyId, "AKIADEFAULT0000000000")
            XCTAssertEqual(credentials.secretAccessKey, "defaultSecret")
            XCTAssertEqual(credentials.sessionToken, "defaultToken")
            XCTAssertTrue(credentials.isValid)
        }
    }

    func testProfileLoadsRoleMetadataFromConfigAndKeysFromSourceProfile() throws {
        let credentialsContents = """
        [base]
        aws_access_key_id = AKIABASE000000000000
        aws_secret_access_key = baseSecret

        [default]
        aws_access_key_id = AKIADEFAULT0000000000
        aws_secret_access_key = defaultSecret
        """

        let configContents = """
        [profile app]
        role_arn = arn:aws:iam::123456789012:role/DatabaseAccess
        source_profile = base
        mfa_serial = arn:aws:iam::123456789012:mfa/dev-user
        region = us-west-2
        """

        try AWSTestEnvironment.withTemporaryAWSFiles(credentials: credentialsContents, config: configContents) { _, _ in
            let credentials = try AWSCredentials(profile: "app")

            XCTAssertEqual(credentials.accessKeyId, "AKIABASE000000000000")
            XCTAssertEqual(credentials.secretAccessKey, "baseSecret")
            XCTAssertEqual(credentials.roleArn, "arn:aws:iam::123456789012:role/DatabaseAccess")
            XCTAssertEqual(credentials.sourceProfile, "base")
            XCTAssertEqual(credentials.mfaSerial, "arn:aws:iam::123456789012:mfa/dev-user")
            XCTAssertEqual(credentials.region, "us-west-2")
            XCTAssertTrue(credentials.requiresMFA)
            XCTAssertTrue(credentials.requiresRoleAssumption)
        }
    }

    func testCredentialsFileValuesTakePrecedenceOverConfigFile() throws {
        let credentialsContents = """
        [app]
        aws_access_key_id = AKIAFROMCREDENTIALS01
        aws_secret_access_key = secret-from-credentials
        aws_session_token = token-from-credentials
        """

        let configContents = """
        [profile app]
        aws_access_key_id = AKIAFROMCONFIGFILE000
        aws_secret_access_key = secret-from-config
        aws_session_token = token-from-config
        region = eu-central-1
        """

        try AWSTestEnvironment.withTemporaryAWSFiles(credentials: credentialsContents, config: configContents) { _, _ in
            let credentials = try AWSCredentials(profile: "app")

            XCTAssertEqual(credentials.accessKeyId, "AKIAFROMCREDENTIALS01")
            XCTAssertEqual(credentials.secretAccessKey, "secret-from-credentials")
            XCTAssertEqual(credentials.sessionToken, "token-from-credentials")
            XCTAssertEqual(credentials.region, "eu-central-1")
        }
    }

    func testProfileThrowsProfileNotFoundForMissingProfile() throws {
        let credentialsContents = """
        [default]
        aws_access_key_id = AKIADEFAULT0000000000
        aws_secret_access_key = defaultSecret
        """

        try AWSTestEnvironment.withTemporaryAWSFiles(credentials: credentialsContents, config: "") { _, _ in
            assertThrowsError(AWSCredentialsError.profileNotFound, from: try AWSCredentials(profile: "missing"))
        }
    }

    func testProfileThrowsMissingCredentialsWhenProfileLacksKeys() throws {
        let credentialsContents = """
        [app]
        role_arn = arn:aws:iam::123456789012:role/DatabaseAccess
        """

        try AWSTestEnvironment.withTemporaryAWSFiles(credentials: credentialsContents, config: "") { _, _ in
            assertThrowsError(AWSCredentialsError.missingCredentials, from: try AWSCredentials(profile: "app"))
        }
    }

    func testProfileWithSourceProfileCycleThrows() throws {
        let credentialsContents = """
        [a]
        source_profile = b

        [b]
        source_profile = a
        """

        try AWSTestEnvironment.withTemporaryAWSFiles(credentials: credentialsContents, config: "") { _, _ in
            assertThrowsError(AWSCredentialsError.invalidCredentials, from: try AWSCredentials(profile: "a"))
        }
    }

    func testProfileThrowsWhenSourceProfileIsMissing() throws {
        let credentialsContents = """
        [app]
        role_arn = arn:aws:iam::123456789012:role/DatabaseAccess
        source_profile = missing
        """

        try AWSTestEnvironment.withTemporaryAWSFiles(credentials: credentialsContents, config: "") { _, _ in
            assertThrowsError(AWSCredentialsError.profileNotFound, from: try AWSCredentials(profile: "app"))
        }
    }

    // MARK: - Obj-C Compatibility

    func testCredentialsFactoryMethodSetsNSErrorOnFailure() throws {
        try AWSTestEnvironment.withTemporaryAWSFiles(credentials: "", config: "") { _, _ in
            var error: NSError?
            let credentials = AWSCredentials.credentials(withProfile: "missing", error: &error)

            XCTAssertNil(credentials)
            XCTAssertEqual(error?.domain, "AWSCredentialsErrorDomain")
            XCTAssertEqual(error?.code, AWSCredentialsError.profileNotFound.rawValue)
        }
    }

    func testProfileConfigurationReturnsParsedValues() throws {
        let credentialsContents = """
        [default]
        aws_access_key_id = AKIADEFAULT0000000000
        aws_secret_access_key = defaultSecret
        """

        let configContents = """
        [default]
        region = ap-southeast-2
        """

        try AWSTestEnvironment.withTemporaryAWSFiles(credentials: credentialsContents, config: configContents) { _, _ in
            let profileConfiguration = AWSCredentials.profileConfiguration(forProfile: "default")

            XCTAssertEqual(profileConfiguration?["aws_access_key_id"], "AKIADEFAULT0000000000")
            XCTAssertEqual(profileConfiguration?["aws_secret_access_key"], "defaultSecret")
            XCTAssertEqual(profileConfiguration?["region"], "ap-southeast-2")
        }
    }

    // MARK: - Description

    func testDescriptionDoesNotLeakSecretAccessKey() {
        let credentials = AWSCredentials(accessKeyId: "AKIA123456789", secretAccessKey: "my-secret")
        let description = credentials.description

        XCTAssertTrue(description.contains("AKIA"))
        XCTAssertFalse(description.contains("my-secret"))
    }
}

final class AWSSTSClientTests: XCTestCase {

    func testEndpointHostUsesStandardPartitionByDefault() {
        XCTAssertEqual(AWSSTSClient.endpointHost(for: "us-east-1"), "sts.us-east-1.amazonaws.com")
    }

    func testEndpointHostUsesChinaPartitionForCnRegions() {
        XCTAssertEqual(AWSSTSClient.endpointHost(for: "cn-north-1"), "sts.cn-north-1.amazonaws.com.cn")
    }

    func testEndpointHostUsesGovCloudPartition() {
        XCTAssertEqual(AWSSTSClient.endpointHost(for: "us-gov-west-1"), "sts.us-gov-west-1.amazonaws.com")
    }

    func testEndpointHostUsesIsoPartition() {
        XCTAssertEqual(AWSSTSClient.endpointHost(for: "us-iso-east-1"), "sts.us-iso-east-1.c2s.ic.gov")
    }

    func testEndpointHostUsesIsoBPartition() {
        XCTAssertEqual(AWSSTSClient.endpointHost(for: "us-isob-east-1"), "sts.us-isob-east-1.sc2s.sgov.gov")
    }

    func testEndpointHostFallsBackToStandardForUnknownRegions() {
        XCTAssertEqual(AWSSTSClient.endpointHost(for: "il-central-1"), "sts.il-central-1.amazonaws.com")
    }

    func testEndpointHostNormalizesCaseAndWhitespace() {
        XCTAssertEqual(AWSSTSClient.endpointHost(for: " CN-NORTH-1 "), "sts.cn-north-1.amazonaws.com.cn")
    }

    func testAssumeRoleAsyncThrowsForInvalidCredentials() async {
        let credentials = AWSCredentials(accessKeyId: "", secretAccessKey: "")

        do {
            _ = try await AWSSTSClient.assumeRole(
                roleArn: "arn:aws:iam::123456789012:role/DatabaseAccess",
                region: "us-east-1",
                credentials: credentials
            )
            XCTFail("Expected invalidCredentials")
        } catch let error as AWSSTSClientError {
            XCTAssertEqual(error, .invalidCredentials)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testAssumeRoleAsyncThrowsForMissingRoleArn() async {
        let credentials = AWSCredentials(
            accessKeyId: "AKIAIOSFODNN7EXAMPLE",
            secretAccessKey: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
        )

        do {
            _ = try await AWSSTSClient.assumeRole(
                roleArn: "",
                region: "us-east-1",
                credentials: credentials
            )
            XCTFail("Expected invalidParameters")
        } catch let error as AWSSTSClientError {
            XCTAssertEqual(error, .invalidParameters)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testAssumeRoleAsyncThrowsForMissingRegion() async {
        let credentials = AWSCredentials(
            accessKeyId: "AKIAIOSFODNN7EXAMPLE",
            secretAccessKey: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
        )

        do {
            _ = try await AWSSTSClient.assumeRole(
                roleArn: "arn:aws:iam::123456789012:role/DatabaseAccess",
                region: "",
                credentials: credentials
            )
            XCTFail("Expected invalidParameters")
        } catch let error as AWSSTSClientError {
            XCTAssertEqual(error, .invalidParameters)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testAssumeRoleAsyncThrowsForWhitespaceOnlyRegion() async {
        let credentials = AWSCredentials(
            accessKeyId: "AKIAIOSFODNN7EXAMPLE",
            secretAccessKey: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
        )

        do {
            _ = try await AWSSTSClient.assumeRole(
                roleArn: "arn:aws:iam::123456789012:role/DatabaseAccess",
                region: "   ",
                credentials: credentials
            )
            XCTFail("Expected invalidParameters")
        } catch let error as AWSSTSClientError {
            XCTAssertEqual(error, .invalidParameters)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testAssumeRoleAsyncThrowsWhenMFASerialProvidedWithoutToken() async {
        let credentials = AWSCredentials(
            accessKeyId: "AKIAIOSFODNN7EXAMPLE",
            secretAccessKey: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
        )

        do {
            _ = try await AWSSTSClient.assumeRole(
                roleArn: "arn:aws:iam::123456789012:role/DatabaseAccess",
                mfaSerialNumber: "arn:aws:iam::123456789012:mfa/dev-user",
                mfaTokenCode: nil,
                region: "us-east-1",
                credentials: credentials
            )
            XCTFail("Expected mfaRequired")
        } catch let error as AWSSTSClientError {
            XCTAssertEqual(error, .mfaRequired)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testAssumeRoleObjCReturnsNSErrorForInvalidCredentials() {
        let outcome: (AWSCredentials?, NSError?) = DispatchQueue.global(qos: .userInitiated).sync {
            var error: NSError?
            let result = AWSSTSClient.assumeRole(
                "arn:aws:iam::123456789012:role/DatabaseAccess",
                roleSessionName: nil,
                mfaSerialNumber: nil,
                mfaTokenCode: nil,
                durationSeconds: 3600,
                region: "us-east-1",
                credentials: AWSCredentials(accessKeyId: "", secretAccessKey: ""),
                error: &error
            )

            return (result, error)
        }

        let (result, returnedError) = outcome

        XCTAssertNil(result)
        XCTAssertEqual(returnedError?.domain, "AWSSTSClientErrorDomain")
        XCTAssertEqual(returnedError?.code, AWSSTSClientError.invalidCredentials.rawValue)
    }
}

final class AWSIAMAuthManagerTests: XCTestCase {

    private enum RegionCacheKeys {
        static let regions = "AWSIAMAvailableRegionsCache"
        static let timestamp = "AWSIAMAvailableRegionsCacheTimestamp"
    }

    override func setUp() {
        super.setUp()
        AWSIAMAuthManager.clearCachedCredentials(for: nil)
        clearRegionCatalogCache()
    }

    override func tearDown() {
        AWSIAMAuthManager.clearCachedCredentials(for: nil)
        clearRegionCatalogCache()
        super.tearDown()
    }

    func testGenerateAuthTokenUsesProfileCredentialsAndIgnoresManualCredentialFields() throws {
        let credentialsContents = """
        [default]
        aws_access_key_id = AKIADEFAULT0000000000
        aws_secret_access_key = defaultSecret
        """

        try AWSTestEnvironment.withTemporaryAWSFiles(credentials: credentialsContents, config: "") { _, _ in
            let token = try AWSIAMAuthManager.generateAuthToken(
                hostname: "mydb.123456789012.us-east-1.rds.amazonaws.com",
                port: 3306,
                username: "db_admin",
                region: nil,
                profile: nil,
                accessKey: "MANUALKEYSHOULDBEIGNORED",
                secretKey: "manual-secret-should-be-ignored",
                parentWindow: nil
            )

            XCTAssertTrue(token.contains("DBUser=db_admin"))
            XCTAssertTrue(token.contains("X-Amz-Credential=AKIADEFAULT0000000000"))
        }
    }

    func testPreferredSTSRegionUsesFallbackWhenBaseRegionIsEmpty() {
        XCTAssertEqual(
            AWSIAMAuthManager.preferredSTSRegion(baseRegion: "   ", fallbackRegion: "us-west-2"),
            "us-west-2"
        )
    }

    func testPreferredSTSRegionUsesBaseRegionWhenPresent() {
        XCTAssertEqual(
            AWSIAMAuthManager.preferredSTSRegion(baseRegion: "eu-central-1", fallbackRegion: "us-west-2"),
            "eu-central-1"
        )
    }

    func testGenerateAuthTokenFallsBackToUsEast1WhenRegionCannotBeDetected() throws {
        let credentialsContents = """
        [default]
        aws_access_key_id = AKIADEFAULT0000000000
        aws_secret_access_key = defaultSecret
        """

        try AWSTestEnvironment.withTemporaryAWSFiles(credentials: credentialsContents, config: "") { _, _ in
            let token = try AWSIAMAuthManager.generateAuthToken(
                hostname: "localhost",
                port: 3306,
                username: "admin",
                region: nil,
                profile: "default",
                accessKey: nil,
                secretKey: nil,
                parentWindow: nil
            )

            XCTAssertTrue(token.contains("us-east-1%2Frds-db%2Faws4_request"))
        }
    }

    func testGenerateAuthTokenThrowsCredentialsNotFoundForUnknownProfile() throws {
        let credentialsContents = """
        [default]
        aws_access_key_id = AKIADEFAULT0000000000
        aws_secret_access_key = defaultSecret
        """

        try AWSTestEnvironment.withTemporaryAWSFiles(credentials: credentialsContents, config: "") { _, _ in
            assertThrowsError(AWSIAMAuthError.credentialsNotFound, from: try AWSIAMAuthManager.generateAuthToken(
                hostname: "mydb.123456789012.us-east-1.rds.amazonaws.com",
                port: 3306,
                username: "admin",
                region: "us-east-1",
                profile: "missing-profile",
                accessKey: nil,
                secretKey: nil,
                parentWindow: nil
            ))
        }
    }

    func testGenerateAuthTokenMapsGenerationErrorsToTokenGenerationFailed() throws {
        let credentialsContents = """
        [default]
        aws_access_key_id = AKIADEFAULT0000000000
        aws_secret_access_key = defaultSecret
        """

        try AWSTestEnvironment.withTemporaryAWSFiles(credentials: credentialsContents, config: "") { _, _ in
            assertThrowsError(AWSIAMAuthError.tokenGenerationFailed, from: try AWSIAMAuthManager.generateAuthToken(
                hostname: "mydb.123456789012.us-east-1.rds.amazonaws.com",
                port: 3306,
                username: "",
                region: "us-east-1",
                profile: "default",
                accessKey: nil,
                secretKey: nil,
                parentWindow: nil
            ))
        }
    }

    func testRegionsFromIPRangesResponseFiltersAndSortsRegions() throws {
        let response = """
        {
          "syncToken": "1",
          "createDate": "2026-01-01-00-00-00",
          "prefixes": [
            { "ip_prefix": "3.5.140.0/22", "region": "ap-northeast-1", "service": "AMAZON" },
            { "ip_prefix": "3.5.141.0/24", "region": "GLOBAL", "service": "AMAZON" },
            { "ip_prefix": "3.5.142.0/24", "region": "us-east-1", "service": "AMAZON" }
          ],
          "ipv6_prefixes": [
            { "ipv6_prefix": "2406:da00::/28", "region": "cn-north-1", "service": "AMAZON" },
            { "ipv6_prefix": "2406:da10::/28", "region": "invalid", "service": "AMAZON" }
          ]
        }
        """

        let data = try XCTUnwrap(response.data(using: .utf8))
        let regions = try XCTUnwrap(AWSIAMAuthManager.regionsFromIPRangesResponse(data))

        XCTAssertEqual(regions, ["ap-northeast-1", "cn-north-1", "us-east-1"])
    }

    func testMergeWithFallbackRegionsIncludesFallbackEntries() {
        let merged = AWSIAMAuthManager.mergeWithFallbackRegions(["us-east-1"])

        XCTAssertTrue(merged.contains("us-east-1"))
        XCTAssertTrue(merged.contains("us-east-2"))
        XCTAssertTrue(merged.contains("eu-west-1"))
    }

    func testCachedOrFallbackRegionsUsesFallbackWhenNoCacheExists() {
        let regions = AWSIAMAuthManager.cachedOrFallbackRegions()

        XCTAssertEqual(regions, AWSIAMAuthManager.mergeWithFallbackRegions([]))
    }

    func testCachedOrFallbackRegionsMergesCachedRegionsWithFallback() {
        UserDefaults.standard.set(["US-EAST-1", "custom-region-1"], forKey: RegionCacheKeys.regions)

        let regions = AWSIAMAuthManager.cachedOrFallbackRegions()

        XCTAssertTrue(regions.contains("us-east-1"))
        XCTAssertTrue(regions.contains("custom-region-1"))
        XCTAssertEqual(regions.filter { $0 == "us-east-1" }.count, 1)
    }

    func testRegionsFromIPRangesResponseReturnsNilForMalformedJSON() {
        let data = Data("not valid json".utf8)

        XCTAssertNil(AWSIAMAuthManager.regionsFromIPRangesResponse(data))
    }

    func testRegionsFromIPRangesResponseNormalizesAndDeduplicatesCaseVariants() throws {
        let response = """
        {
          "prefixes": [
            { "region": "US-EAST-1", "service": "AMAZON" },
            { "region": "us-east-1", "service": "AMAZON" }
          ],
          "ipv6_prefixes": [
            { "region": "Us-East-1", "service": "AMAZON" },
            { "region": "EU-WEST-1", "service": "AMAZON" }
          ]
        }
        """

        let data = try XCTUnwrap(response.data(using: .utf8))
        let regions = try XCTUnwrap(AWSIAMAuthManager.regionsFromIPRangesResponse(data))

        XCTAssertEqual(regions, ["eu-west-1", "us-east-1"])
    }

    func testRegionsFromIPRangesResponseReturnsEmptyArrayWhenNoValidRegions() throws {
        let response = """
        {
          "prefixes": [
            { "region": "GLOBAL", "service": "AMAZON" },
            { "region": "invalid", "service": "AMAZON" }
          ],
          "ipv6_prefixes": []
        }
        """

        let data = try XCTUnwrap(response.data(using: .utf8))
        let regions = try XCTUnwrap(AWSIAMAuthManager.regionsFromIPRangesResponse(data))

        XCTAssertTrue(regions.isEmpty)
    }

    private func clearRegionCatalogCache() {
        UserDefaults.standard.removeObject(forKey: RegionCacheKeys.regions)
        UserDefaults.standard.removeObject(forKey: RegionCacheKeys.timestamp)
    }
}

private enum AWSTestEnvironment {

    private static let lock = NSLock()

    static func withTemporaryAWSFiles(
        credentials: String,
        config: String,
        _ body: (_ credentialsPath: String, _ configPath: String) throws -> Void
    ) throws {
        lock.lock()
        defer { lock.unlock() }

        let fileManager = FileManager.default
        let rootPath = fileManager.temporaryDirectory
            .appendingPathComponent("SequelAce-AWSTests-\(UUID().uuidString)", isDirectory: true)

        let credentialsURL = rootPath.appendingPathComponent("credentials", isDirectory: false)
        let configURL = rootPath.appendingPathComponent("config", isDirectory: false)

        try fileManager.createDirectory(at: rootPath, withIntermediateDirectories: true)
        try credentials.write(to: credentialsURL, atomically: true, encoding: .utf8)
        try config.write(to: configURL, atomically: true, encoding: .utf8)

        let oldCredentialsPath = currentEnvironmentValue(for: "AWS_SHARED_CREDENTIALS_FILE")
        let oldConfigPath = currentEnvironmentValue(for: "AWS_CONFIG_FILE")

        setenv("AWS_SHARED_CREDENTIALS_FILE", credentialsURL.path, 1)
        setenv("AWS_CONFIG_FILE", configURL.path, 1)

        defer {
            if let oldCredentialsPath {
                setenv("AWS_SHARED_CREDENTIALS_FILE", oldCredentialsPath, 1)
            } else {
                unsetenv("AWS_SHARED_CREDENTIALS_FILE")
            }

            if let oldConfigPath {
                setenv("AWS_CONFIG_FILE", oldConfigPath, 1)
            } else {
                unsetenv("AWS_CONFIG_FILE")
            }

            try? fileManager.removeItem(at: rootPath)
            AWSIAMAuthManager.clearCachedCredentials(for: nil)
        }

        try body(credentialsURL.path, configURL.path)
    }

    private static func currentEnvironmentValue(for key: String) -> String? {
        guard let value = getenv(key) else {
            return nil
        }

        return String(cString: value)
    }
}

private func assertThrowsError<T: Error & Equatable>(
    _ expectedError: T,
    from expression: @autoclosure () throws -> Any,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    do {
        _ = try expression()
        XCTFail("Expected error \(expectedError), but no error was thrown", file: file, line: line)
    } catch let error as T {
        XCTAssertEqual(error, expectedError, file: file, line: line)
    } catch {
        XCTFail("Expected \(T.self), got \(error)", file: file, line: line)
    }
}
