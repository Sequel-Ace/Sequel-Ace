//
//  AWSCredentialsTests.swift
//  Sequel Ace
//
//  Unit tests for AWS credentials, STS validation, and IAM auth integration.
//

import AppKit
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

    // MARK: - SSO and Login Profiles

    func testProfileLoadsSSOSessionFormatAndResolvesSessionSection() throws {
        let configContents = """
        [sso-session my-org]
        sso_start_url = https://my-org.awsapps.com/start
        sso_region = eu-west-1
        sso_registration_scopes = sso:account:access

        [profile dev]
        sso_session = my-org
        sso_account_id = 123456789012
        sso_role_name = DeveloperAccess
        region = eu-west-1
        """

        try AWSTestEnvironment.withTemporaryAWSFiles(credentials: "", config: configContents) { _, _ in
            let credentials = try AWSCredentials(profile: "dev")

            XCTAssertTrue(credentials.isSSOProfile)
            XCTAssertFalse(credentials.isLoginProfile)
            XCTAssertFalse(credentials.isValid)
            XCTAssertEqual(credentials.ssoSession, "my-org")
            XCTAssertEqual(credentials.ssoStartURL, "https://my-org.awsapps.com/start")
            XCTAssertEqual(credentials.ssoRegion, "eu-west-1")
            XCTAssertEqual(credentials.ssoAccountID, "123456789012")
            XCTAssertEqual(credentials.ssoRoleName, "DeveloperAccess")
        }
    }

    func testProfileLoadsLegacySSOFormat() throws {
        let configContents = """
        [profile legacy]
        sso_start_url = https://my-org.awsapps.com/start
        sso_region = us-east-1
        sso_account_id = 123456789012
        sso_role_name = ReadOnly
        """

        try AWSTestEnvironment.withTemporaryAWSFiles(credentials: "", config: configContents) { _, _ in
            let credentials = try AWSCredentials(profile: "legacy")

            XCTAssertTrue(credentials.isSSOProfile)
            XCTAssertNil(credentials.ssoSession)
            XCTAssertEqual(credentials.ssoStartURL, "https://my-org.awsapps.com/start")
            XCTAssertEqual(credentials.ssoRegion, "us-east-1")
        }
    }

    func testProfileLoadsLoginSession() throws {
        let configContents = """
        [default]
        login_session = arn:aws:iam::123456789012:user/dev
        region = eu-west-1
        """

        try AWSTestEnvironment.withTemporaryAWSFiles(credentials: "", config: configContents) { _, _ in
            let credentials = try AWSCredentials(profile: nil)

            XCTAssertTrue(credentials.isLoginProfile)
            XCTAssertFalse(credentials.isSSOProfile)
            XCTAssertFalse(credentials.isValid)
            XCTAssertEqual(credentials.loginSession, "arn:aws:iam::123456789012:user/dev")
            XCTAssertEqual(credentials.region, "eu-west-1")
        }
    }

    func testProfileNamesExcludeSSOSessionSectionsAndStripProfilePrefix() {
        let configContents = """
        [default]
        [sso-session my-org]
        sso_start_url = https://my-org.awsapps.com/start
        [profile dev]
        sso_session = my-org
        """

        let names = AWSCredentials.profileNames(inFileContents: configContents, isConfigFile: true)

        XCTAssertEqual(names, ["default", "dev"])
        XCTAssertFalse(names.contains("sso-session my-org"))
    }

    func testProfileNamesInCredentialsFileKeepRawSectionNames() {
        let credentialsContents = """
        [default]
        [work]
        """

        let names = AWSCredentials.profileNames(inFileContents: credentialsContents, isConfigFile: false)

        XCTAssertEqual(names, ["default", "work"])
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

    func testCancelledAttemptDoesNotPresentMFADialog() {
        let check = {
            XCTAssertTrue(Thread.isMainThread)
            var checkedLiveness = false
            let token = AWSMFATokenDialog.promptForMFAToken(
                profile: "offline-mfa", mfaSerial: "offline-mfa-device", parentWindow: nil,
                shouldContinue: {
                    XCTAssertTrue(Thread.isMainThread)
                    checkedLiveness = true
                    return false
                }
            )
            XCTAssertTrue(checkedLiveness)
            XCTAssertNil(token)
        }
        if Thread.isMainThread { check() } else { DispatchQueue.main.sync(execute: check) }
    }

    func testBackgroundTokenGenerationReturnsBeforeMainQueueCallback() throws {
        let runOnMain: () throws -> Void = {
            let credentialsContents = """
            [default]
            aws_access_key_id = AKIADEFAULT0000000000
            aws_secret_access_key = offline-test-secret
            """

            try AWSTestEnvironment.withTemporaryAWSFiles(credentials: credentialsContents, config: "") { _, _ in
                var returnedFromMethod = false
                var callbackCalled = false
                var token: String?
                var callbackError: NSError?

                AWSIAMAuthManager.generateAuthTokenInBackground(
                    hostname: "mydb.123456789012.us-east-1.rds.amazonaws.com",
                    port: 3306,
                    username: "db_admin",
                    region: nil,
                    profile: nil,
                    parentWindow: nil
                ) { result, error in
                    XCTAssertTrue(Thread.isMainThread)
                    XCTAssertTrue(returnedFromMethod, "The API must return before invoking its callback")
                    token = result
                    callbackError = error
                    callbackCalled = true
                }

                returnedFromMethod = true
                XCTAssertFalse(callbackCalled, "Completion should be queued after the method returns")

                let deadline = Date().addingTimeInterval(5)
                while !callbackCalled && Date() < deadline {
                    _ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
                }

                XCTAssertTrue(callbackCalled, "Expected the main-queue completion")
                XCTAssertNil(callbackError)
                XCTAssertTrue(token?.contains("DBUser=db_admin") == true)
                XCTAssertTrue(token?.contains("X-Amz-Credential=AKIADEFAULT0000000000") == true)
            }
        }

        if Thread.isMainThread {
            try runOnMain()
        } else {
            try DispatchQueue.main.sync(execute: runOnMain)
        }
    }

    func testGenerateAuthTokenUsesDefaultProfileWhenProvidedProfileIsWhitespace() throws {
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
                region: "us-east-1",
                profile: "   ",
                accessKey: nil,
                secretKey: nil,
                parentWindow: nil
            )

            XCTAssertTrue(token.contains("X-Amz-Credential=AKIADEFAULT0000000000"))
        }
    }

    func testGenerateAuthTokenNormalizesProvidedRegionWhitespaceAndCase() throws {
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
                region: " US-EAST-1 ",
                profile: "default",
                accessKey: nil,
                secretKey: nil,
                parentWindow: nil
            )

            XCTAssertTrue(token.contains("us-east-1%2Frds-db%2Faws4_request"))
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

    func testGenerateAuthTokenResolvesConsoleSignInProfile() throws {
        let loginSession = "arn:aws:iam::123456789012:user/dev"
        let configContents = """
        [default]
        login_session = \(loginSession)
        region = eu-west-1
        """

        try AWSTestEnvironment.withTemporaryAWSFiles(credentials: "", config: configContents) { _, _ in
            let cacheDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("SequelAce-LoginCache-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: cacheDir) }

            let fileName = AWSLoginCredentialsProvider.cacheFileName(forLoginSession: loginSession)
            let json = """
            {
              "accessToken": {
                "accessKeyId": "ASIAEXAMPLE0000000000",
                "secretAccessKey": "exampleSecretKey",
                "sessionToken": "exampleSessionToken",
                "expiresAt": "2999-01-01T00:00:00Z"
              }
            }
            """
            try json.write(to: cacheDir.appendingPathComponent(fileName), atomically: true, encoding: .utf8)

            setenv("AWS_LOGIN_CACHE_DIRECTORY", cacheDir.path, 1)
            defer {
                unsetenv("AWS_LOGIN_CACHE_DIRECTORY")
                AWSIAMAuthManager.clearCachedCredentials(for: nil)
            }

            let token = try AWSIAMAuthManager.generateAuthToken(
                hostname: "mydb.123456789012.eu-west-1.rds.amazonaws.com",
                port: 3306,
                username: "db_admin",
                region: nil,
                profile: nil,
                accessKey: nil,
                secretKey: nil,
                parentWindow: nil
            )

            XCTAssertTrue(token.contains("DBUser=db_admin"))
            XCTAssertTrue(token.contains("X-Amz-Credential=ASIAEXAMPLE0000000000"))
            XCTAssertTrue(token.contains("X-Amz-Security-Token="))
        }
    }

    func testGenerateAuthTokenPrefersStaticKeysOverConsoleSignIn() throws {
        let loginSession = "arn:aws:iam::123456789012:user/dev"
        let credentialsContents = """
        [default]
        aws_access_key_id = AKIASTATIC00000000000
        aws_secret_access_key = staticSecret
        """
        let configContents = """
        [default]
        login_session = \(loginSession)
        region = eu-west-1
        """

        try AWSTestEnvironment.withTemporaryAWSFiles(credentials: credentialsContents, config: configContents) { _, _ in
            let cacheDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("SequelAce-LoginCache-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: cacheDir) }

            let fileName = AWSLoginCredentialsProvider.cacheFileName(forLoginSession: loginSession)
            let json = """
            {
              "accessToken": {
                "accessKeyId": "ASIALOGIN000000000000",
                "secretAccessKey": "loginSecret",
                "sessionToken": "loginSessionToken",
                "expiresAt": "2999-01-01T00:00:00Z"
              }
            }
            """
            try json.write(to: cacheDir.appendingPathComponent(fileName), atomically: true, encoding: .utf8)

            setenv("AWS_LOGIN_CACHE_DIRECTORY", cacheDir.path, 1)
            defer {
                unsetenv("AWS_LOGIN_CACHE_DIRECTORY")
                AWSIAMAuthManager.clearCachedCredentials(for: nil)
            }

            let token = try AWSIAMAuthManager.generateAuthToken(
                hostname: "mydb.123456789012.eu-west-1.rds.amazonaws.com",
                port: 3306,
                username: "db_admin",
                region: nil,
                profile: nil,
                accessKey: nil,
                secretKey: nil,
                parentWindow: nil
            )

            XCTAssertTrue(token.contains("X-Amz-Credential=AKIASTATIC00000000000"))
            XCTAssertFalse(token.contains("ASIALOGIN000000000000"))
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

    func testRegionComboBoxDefersFirstPopupUntilPreparationCompletes() throws {
        let comboBox = SAAWSRegionComboBox(frame: NSRect(x: 0, y: 0, width: 200, height: 26))
        let delegate = SAAWSRegionComboBoxPreparationDelegateStub()
        comboBox.preparationDelegate = delegate
        let popupButtonEvent = try XCTUnwrap(comboBoxMouseDownEvent(x: 192))

        XCTAssertTrue(comboBox.shouldPreparePopup(for: popupButtonEvent))

        comboBox.mouseDown(with: popupButtonEvent)

        XCTAssertEqual(delegate.preparationCount, 1)
        XCTAssertFalse(comboBox.hasPreparedPopup)
        XCTAssertTrue(comboBox.shouldOpenPopupAfterPreparation)

        delegate.completePreparation()

        XCTAssertTrue(comboBox.hasPreparedPopup)
        XCTAssertFalse(comboBox.shouldOpenPopupAfterPreparation)
        XCTAssertFalse(comboBox.shouldPreparePopup(for: popupButtonEvent))
    }

    func testRegionComboBoxCancelsDeferredPopupAfterInterveningInput() throws {
        let comboBox = SAAWSRegionComboBox(frame: NSRect(x: 0, y: 0, width: 200, height: 26))
        let delegate = SAAWSRegionComboBoxPreparationDelegateStub()
        comboBox.preparationDelegate = delegate
        let popupButtonEvent = try XCTUnwrap(comboBoxMouseDownEvent(x: 192))

        comboBox.mouseDown(with: popupButtonEvent)
        comboBox.cancelPendingPopupOpening()

        XCTAssertFalse(comboBox.shouldOpenPopupAfterPreparation)

        delegate.completePreparation()

        XCTAssertTrue(comboBox.hasPreparedPopup)
        XCTAssertFalse(comboBox.shouldOpenPopupAfterPreparation)
    }

    func testRegionComboBoxDefersPopupPreparationWithoutMouseInput() {
        let comboBox = SAAWSRegionComboBox(frame: NSRect(x: 0, y: 0, width: 200, height: 26))
        let delegate = SAAWSRegionComboBoxPreparationDelegateStub()
        comboBox.preparationDelegate = delegate

        XCTAssertTrue(comboBox.preparePopupIfNeeded())
        XCTAssertEqual(delegate.preparationCount, 1)
        XCTAssertFalse(comboBox.hasPreparedPopup)

        delegate.completePreparation()

        XCTAssertTrue(comboBox.hasPreparedPopup)
        XCTAssertFalse(comboBox.preparePopupIfNeeded())
    }

    func testRegionComboBoxCellRoutesAccessibilityMenuThroughPreparation() {
        let comboBox = SAAWSRegionComboBox(frame: NSRect(x: 0, y: 0, width: 200, height: 26))
        let cell = SAAWSRegionComboBoxCell()
        let delegate = SAAWSRegionComboBoxPreparationDelegateStub()
        comboBox.cell = cell
        comboBox.preparationDelegate = delegate

        XCTAssertTrue(cell.accessibilityPerformShowMenu())
        XCTAssertEqual(delegate.preparationCount, 1)
        XCTAssertFalse(comboBox.hasPreparedPopup)

        delegate.completePreparation()

        XCTAssertTrue(comboBox.hasPreparedPopup)
    }

    func testRegionComboBoxDoesNotRefreshWhenEditingItsText() throws {
        let comboBox = SAAWSRegionComboBox(frame: NSRect(x: 0, y: 0, width: 200, height: 26))
        let textFieldEvent = try XCTUnwrap(comboBoxMouseDownEvent(x: 8))

        XCTAssertFalse(comboBox.shouldPreparePopup(for: textFieldEvent))
    }

    private func comboBoxMouseDownEvent(x: CGFloat) -> NSEvent? {
        NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: NSPoint(x: x, y: 13),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        )
    }

    private func clearRegionCatalogCache() {
        UserDefaults.standard.removeObject(forKey: RegionCacheKeys.regions)
        UserDefaults.standard.removeObject(forKey: RegionCacheKeys.timestamp)
    }
}

private final class SAAWSRegionComboBoxPreparationDelegateStub: NSObject, SAAWSRegionComboBoxPreparationDelegate {
    private(set) var preparationCount = 0
    private var completion: (() -> Void)?

    func prepareAWSRegionComboBox(_ comboBox: SAAWSRegionComboBox, completion: @escaping () -> Void) {
        preparationCount += 1
        self.completion = completion
    }

    func completePreparation() {
        completion?()
        completion = nil
    }
}

final class AWSLoginCredentialsProviderTests: XCTestCase {

    func testCacheFileNameIsSHA256OfLoginSession() {
        let loginSession = "arn:aws:iam::184343387869:user/holger"

        XCTAssertEqual(
            AWSLoginCredentialsProvider.cacheFileName(forLoginSession: loginSession),
            "ae55f86d5ac80ede8793dc541f44e1bbf3998886b34d98b02c0e541fc2ba452e.json"
        )
    }

    func testParseCachedCredentialsReturnsTemporaryCredentials() throws {
        let json = """
        {
          "accessToken": {
            "accessKeyId": "ASIAEXAMPLE0000000000",
            "secretAccessKey": "exampleSecretKey",
            "sessionToken": "exampleSessionToken",
            "expiresAt": "2999-01-01T00:00:00Z"
          }
        }
        """

        let credentials = try AWSLoginCredentialsProvider.parseCachedCredentials(
            fromJSON: Data(json.utf8),
            now: Date()
        )

        XCTAssertEqual(credentials.accessKeyId, "ASIAEXAMPLE0000000000")
        XCTAssertEqual(credentials.secretAccessKey, "exampleSecretKey")
        XCTAssertEqual(credentials.sessionToken, "exampleSessionToken")
        XCTAssertTrue(credentials.isValid)
    }

    func testParseCachedCredentialsThrowsWhenExpired() {
        let json = """
        {
          "accessToken": {
            "accessKeyId": "ASIAEXAMPLE0000000000",
            "secretAccessKey": "exampleSecretKey",
            "expiresAt": "2000-01-01T00:00:00Z"
          }
        }
        """

        assertThrowsError(
            AWSLoginAuthError.sessionExpired,
            from: try AWSLoginCredentialsProvider.parseCachedCredentials(fromJSON: Data(json.utf8), now: Date())
        )
    }

    func testParseCachedCredentialsThrowsWhenAccessKeyMissing() {
        let json = """
        {
          "accessToken": {
            "secretAccessKey": "exampleSecretKey",
            "expiresAt": "2999-01-01T00:00:00Z"
          }
        }
        """

        assertThrowsError(
            AWSLoginAuthError.invalidCacheContents,
            from: try AWSLoginCredentialsProvider.parseCachedCredentials(fromJSON: Data(json.utf8), now: Date())
        )
    }

    func testParseCachedCredentialsThrowsForMalformedJSON() {
        assertThrowsError(
            AWSLoginAuthError.invalidCacheContents,
            from: try AWSLoginCredentialsProvider.parseCachedCredentials(fromJSON: Data("not valid json".utf8), now: Date())
        )
    }

    func testResolveCredentialsReadsCacheFileForProfile() throws {
        let loginSession = "arn:aws:iam::123456789012:user/dev"
        let configContents = """
        [default]
        login_session = \(loginSession)
        region = eu-west-1
        """

        try AWSTestEnvironment.withTemporaryAWSFiles(credentials: "", config: configContents) { _, _ in
            let profile = try AWSCredentials(profile: nil)

            let cacheDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("SequelAce-LoginCache-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: cacheDir) }

            let fileName = AWSLoginCredentialsProvider.cacheFileName(forLoginSession: loginSession)
            let json = """
            {
              "accessToken": {
                "accessKeyId": "ASIAEXAMPLE0000000000",
                "secretAccessKey": "exampleSecretKey",
                "sessionToken": "exampleSessionToken",
                "expiresAt": "2999-01-01T00:00:00Z"
              }
            }
            """
            try json.write(to: cacheDir.appendingPathComponent(fileName), atomically: true, encoding: .utf8)

            setenv("AWS_LOGIN_CACHE_DIRECTORY", cacheDir.path, 1)
            defer { unsetenv("AWS_LOGIN_CACHE_DIRECTORY") }

            let resolved = try AWSLoginCredentialsProvider.resolveCredentials(for: profile)

            XCTAssertEqual(resolved.accessKeyId, "ASIAEXAMPLE0000000000")
            XCTAssertEqual(resolved.sessionToken, "exampleSessionToken")
        }
    }
}

final class AWSSSOClientTests: XCTestCase {

    func testCacheFileNameIsSHA1OfKey() {
        XCTAssertEqual(
            AWSSSOClient.cacheFileName(forKey: "my-org"),
            "063b06ca21ff862fb6d05839b8f962c8f1afdec6.json"
        )
        XCTAssertEqual(
            AWSSSOClient.cacheFileName(forKey: "https://my-org.awsapps.com/start"),
            "acff06c7037450e5a3fddcacb0a34e921da42d68.json"
        )
    }

    func testTokenCacheKeyPrefersSessionOverStartURL() throws {
        let configContents = """
        [sso-session my-org]
        sso_start_url = https://my-org.awsapps.com/start
        sso_region = eu-west-1

        [profile dev]
        sso_session = my-org
        sso_account_id = 123456789012
        sso_role_name = DeveloperAccess
        """

        try AWSTestEnvironment.withTemporaryAWSFiles(credentials: "", config: configContents) { _, _ in
            let credentials = try AWSCredentials(profile: "dev")
            XCTAssertEqual(AWSSSOClient.tokenCacheKey(for: credentials), "my-org")
        }
    }

    func testTokenCacheKeyFallsBackToStartURLForLegacyProfile() throws {
        let configContents = """
        [profile legacy]
        sso_start_url = https://my-org.awsapps.com/start
        sso_region = us-east-1
        sso_account_id = 123456789012
        sso_role_name = ReadOnly
        """

        try AWSTestEnvironment.withTemporaryAWSFiles(credentials: "", config: configContents) { _, _ in
            let credentials = try AWSCredentials(profile: "legacy")
            XCTAssertEqual(AWSSSOClient.tokenCacheKey(for: credentials), "https://my-org.awsapps.com/start")
        }
    }

    func testParseAccessTokenReturnsTokenAndRegion() throws {
        let json = """
        {
          "startUrl": "https://my-org.awsapps.com/start",
          "region": "eu-west-1",
          "accessToken": "example-access-token",
          "expiresAt": "2999-01-01T00:00:00Z"
        }
        """

        let token = try AWSSSOClient.parseAccessToken(fromJSON: Data(json.utf8), now: Date())

        XCTAssertEqual(token.accessToken, "example-access-token")
        XCTAssertEqual(token.region, "eu-west-1")
    }

    func testParseAccessTokenThrowsWhenExpired() {
        let json = """
        { "accessToken": "example", "expiresAt": "2000-01-01T00:00:00Z" }
        """

        assertThrowsError(
            AWSSSOClientError.tokenExpired,
            from: try AWSSSOClient.parseAccessToken(fromJSON: Data(json.utf8), now: Date())
        )
    }

    func testParseAccessTokenThrowsWhenTokenMissing() {
        let json = """
        { "region": "eu-west-1", "expiresAt": "2999-01-01T00:00:00Z" }
        """

        assertThrowsError(
            AWSSSOClientError.invalidResponse,
            from: try AWSSSOClient.parseAccessToken(fromJSON: Data(json.utf8), now: Date())
        )
    }

    func testPortalHostUsesStandardPartition() {
        XCTAssertEqual(AWSSSOClient.portalHost(forRegion: "eu-west-1"), "portal.sso.eu-west-1.amazonaws.com")
    }

    func testPortalHostUsesChinaPartition() {
        XCTAssertEqual(AWSSSOClient.portalHost(forRegion: "cn-north-1"), "portal.sso.cn-north-1.amazonaws.com.cn")
    }

    func testParseRoleCredentialsReturnsTemporaryCredentials() throws {
        let json = """
        {
          "roleCredentials": {
            "accessKeyId": "ASIAEXAMPLE0000000000",
            "secretAccessKey": "exampleSecretKey",
            "sessionToken": "exampleSessionToken",
            "expiration": 4102444800000
          }
        }
        """

        let credentials = try AWSSSOClient.parseRoleCredentials(fromJSON: Data(json.utf8))

        XCTAssertEqual(credentials.accessKeyId, "ASIAEXAMPLE0000000000")
        XCTAssertEqual(credentials.secretAccessKey, "exampleSecretKey")
        XCTAssertEqual(credentials.sessionToken, "exampleSessionToken")
        XCTAssertEqual(credentials.expiration, Date(timeIntervalSince1970: 4102444800))
    }

    func testParseRoleCredentialsThrowsWhenMissing() {
        let json = "{ \"roleCredentials\": { \"secretAccessKey\": \"x\" } }"

        assertThrowsError(
            AWSSSOClientError.invalidResponse,
            from: try AWSSSOClient.parseRoleCredentials(fromJSON: Data(json.utf8))
        )
    }

    func testFetchRoleCredentialsSendsEncodedGETAndBearerHeader() async throws {
        let session = makeOfflineSession()
        defer { session.invalidateAndCancel() }
        let credentials = try await AWSSSOClient.fetchRoleCredentials(
            accountID: "123456789012 +&/?",
            roleName: "Developer +&/Access",
            accessToken: "offline-test-bearer",
            region: "eu-west-1",
            session: session
        )

        XCTAssertEqual(credentials.accessKeyId, "ASIAOFFLINE000000000")
        XCTAssertEqual(credentials.secretAccessKey, "offline-secret")
        XCTAssertEqual(credentials.sessionToken, "offline-session-token")
        XCTAssertEqual(credentials.expiration, Date(timeIntervalSince1970: 4_102_444_800))
    }

    func testFetchRoleCredentialsMapsPortalErrorsAndTransportFailures() async {
        let cases: [(String, AWSSSOClientError)] = [
            ("expired", .tokenExpired),
            ("denied", .accessDenied),
            ("malformed", .invalidResponse),
            ("timeout", .requestTimeout),
            ("network-failure", .networkFailure)
        ]

        for (roleName, expectedError) in cases {
            let session = makeOfflineSession()
            do {
                _ = try await AWSSSOClient.fetchRoleCredentials(
                    accountID: "123456789012",
                    roleName: roleName,
                    accessToken: "offline-test-bearer",
                    region: "eu-west-1",
                    session: session
                )
                XCTFail("Expected \(expectedError) for \(roleName)")
            } catch let error as AWSSSOClientError {
                XCTAssertEqual(error, expectedError, "Unexpected error for \(roleName)")
            } catch {
                XCTFail("Unexpected error for \(roleName): \(error)")
            }
            session.invalidateAndCancel()
        }
    }

    func testResolveCredentialsUsesSessionAndLegacyCacheKeysAndSSORegion() async throws {
        let config = """
        [sso-session modern-org]
        sso_start_url = https://modern.awsapps.com/start
        sso_region = eu-west-1

        [profile modern]
        sso_session = modern-org
        sso_account_id = 123456789012
        sso_role_name = DeveloperAccess
        region = us-east-1

        [profile legacy]
        sso_start_url = https://legacy.awsapps.com/start
        sso_region = eu-west-1
        sso_account_id = 123456789012
        sso_role_name = ReadOnly
        region = us-east-1
        """

        var modernProfile: AWSCredentials?
        var legacyProfile: AWSCredentials?
        try AWSTestEnvironment.withTemporaryAWSFiles(credentials: "", config: config) { _, _ in
            modernProfile = try AWSCredentials(profile: "modern")
            legacyProfile = try AWSCredentials(profile: "legacy")
        }

        let modern = try XCTUnwrap(modernProfile)
        let legacy = try XCTUnwrap(legacyProfile)
        let cacheDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SequelAce-SSOOfflineCache-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: cacheDirectory) }

        for cacheKey in ["modern-org", "https://legacy.awsapps.com/start"] {
            let token = """
            { "accessToken": "offline-test-bearer", "expiresAt": "2999-01-01T00:00:00Z" }
            """
            try token.write(
                to: cacheDirectory.appendingPathComponent(AWSSSOClient.cacheFileName(forKey: cacheKey)),
                atomically: true,
                encoding: .utf8
            )
        }

        for profile in [modern, legacy] {
            let session = makeOfflineSession()
            defer { session.invalidateAndCancel() }
            let resolved = try await AWSSSOClient.resolveCredentials(
                for: profile,
                cacheDirectory: cacheDirectory.path,
                session: session
            )
            XCTAssertEqual(resolved.accessKeyId, "ASIAOFFLINE000000000")
            XCTAssertEqual(resolved.sessionToken, "offline-session-token")
        }
    }

    private func makeOfflineSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SAOfflineSSOURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

/// A fail-closed URLProtocol fixture. Its response is selected from request data,
/// so each URLSession has isolated behavior and no process-wide mutable fixture state.
private final class SAOfflineSSOURLProtocol: URLProtocol {

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              request.httpMethod == "GET",
              url.scheme == "https",
              url.host == "portal.sso.eu-west-1.amazonaws.com",
              components.path == "/federation/credentials",
              request.httpBody == nil,
              request.value(forHTTPHeaderField: "x-amz-sso_bearer_token") == "offline-test-bearer",
              !url.absoluteString.contains("offline-test-bearer") else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        guard query["account_id"] != nil, query["role_name"] != nil else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        let roleName = query["role_name"] ?? ""
        let rawQuery = components.percentEncodedQuery ?? ""
        switch roleName {
        case "timeout":
            client?.urlProtocol(self, didFailWithError: URLError(.timedOut))
        case "network-failure":
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
        case "expired":
            respond(statusCode: 401, body: Data(), url: url)
        case "denied":
            respond(statusCode: 403, body: Data(), url: url)
        case "malformed":
            respond(statusCode: 200, body: Data("not-json".utf8), url: url)
        default:
            let validEncodedQuery: Bool
            if roleName == "Developer +&/Access" {
                validEncodedQuery = query["account_id"] == "123456789012 +&/?"
                    && rawQuery.contains("%2B") && rawQuery.contains("%26")
            } else {
                validEncodedQuery = query["account_id"] == "123456789012"
                    && ["DeveloperAccess", "ReadOnly"].contains(roleName)
            }
            guard validEncodedQuery else {
                respond(statusCode: 400, body: Data(), url: url)
                return
            }
            let body = Data("""
            { "roleCredentials": {
              "accessKeyId": "ASIAOFFLINE000000000",
              "secretAccessKey": "offline-secret",
              "sessionToken": "offline-session-token",
              "expiration": 4102444800000
            } }
            """.utf8)
            respond(statusCode: 200, body: body, url: url)
        }
    }

    override func stopLoading() {}

    private func respond(statusCode: Int, body: Data, url: URL) {
        guard let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
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

final class AWSLoginCredentialsRenewalTests: XCTestCase {

    private let loginSession = "arn:aws:iam::123456789012:user/dev"
    private var cacheDirectory: URL!
    private var cacheFile: URL!
    private var originalTransport: ((URLRequest) throws -> (Data, Int))!
    private var requests: [URLRequest] = []

    override func setUpWithError() throws {
        cacheDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SequelAce-LoginRenewal-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        cacheFile = cacheDirectory.appendingPathComponent(AWSLoginCredentialsProvider.cacheFileName(forLoginSession: loginSession))

        setenv("AWS_LOGIN_CACHE_DIRECTORY", cacheDirectory.path, 1)
        originalTransport = AWSLoginCredentialsProvider.refreshTransport
        requests = []
    }

    override func tearDownWithError() throws {
        AWSLoginCredentialsProvider.refreshTransport = originalTransport
        unsetenv("AWS_LOGIN_CACHE_DIRECTORY")
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: cacheDirectory.path)
        try? FileManager.default.removeItem(at: cacheDirectory)
    }

    func testFreshCredentialsAreUsedWithoutRenewal() throws {
        try writeCache(SAAWSLoginTestFixtures.cacheContents(expiresAt: Date().addingTimeInterval(600)))
        respond(status: 200, body: SAAWSLoginTestFixtures.successResponse)

        try withLoginProfile { profile in
            let credentials = try AWSLoginCredentialsProvider.resolveCredentials(for: profile)
            XCTAssertEqual(credentials.accessKeyId, "ASIAOLD0000000000000")
        }
        XCTAssertTrue(requests.isEmpty)
    }

    func testExpiringCredentialsAreRenewedInTheIssuingRegionAndWrittenBack() throws {
        let original = SAAWSLoginTestFixtures.cacheContents(expiresAt: Date().addingTimeInterval(120))
        try writeCache(original)
        respond(status: 200, body: SAAWSLoginTestFixtures.successResponse)

        try withLoginProfile(region: "eu-west-1") { profile in
            let credentials = try AWSLoginCredentialsProvider.resolveCredentials(for: profile)
            XCTAssertEqual(credentials.accessKeyId, "ASIANEW0000000000000")
            XCTAssertEqual(credentials.sessionToken, "newSessionToken")
        }

        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(request.url?.absoluteString, "https://eu-north-1.signin.aws.amazon.com/v1/token")
        XCTAssertNotNil(request.value(forHTTPHeaderField: "DPoP"))
        let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: String])
        XCTAssertEqual(body["refreshToken"], "oldRefreshToken")

        let cached = try readCache()
        let accessToken = try XCTUnwrap(cached["accessToken"] as? [String: String])
        XCTAssertEqual(accessToken["accessKeyId"], "ASIANEW0000000000000")
        XCTAssertEqual(accessToken["accountId"], "123456789012")
        XCTAssertEqual(cached["refreshToken"] as? String, "newRefreshToken")
        XCTAssertEqual(cached["idToken"] as? String, original["idToken"] as? String)
        XCTAssertEqual(cached["dpopKey"] as? String, SAAWSLoginTestFixtures.sec1Key)
        XCTAssertEqual(cached["futureField"] as? String, "kept")

        let permissions = try FileManager.default.attributesOfItem(atPath: cacheFile.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: cacheDirectory.path), [cacheFile.lastPathComponent])
    }

    func testRenewalUsesTheProfileRegionWithoutAnIdentityToken() throws {
        try writeCache(SAAWSLoginTestFixtures.cacheContents(expiresAt: Date().addingTimeInterval(120), issuer: nil))
        respond(status: 200, body: SAAWSLoginTestFixtures.successResponse)

        try withLoginProfile(region: "eu-west-1") { profile in
            _ = try AWSLoginCredentialsProvider.resolveCredentials(for: profile)
        }

        XCTAssertEqual(requests.first?.url?.absoluteString, "https://eu-west-1.signin.aws.amazon.com/v1/token")
    }

    func testRenewalWithoutAnyRegionFailsOnceExpired() throws {
        try writeCache(SAAWSLoginTestFixtures.cacheContents(expiresAt: Date().addingTimeInterval(-60), issuer: nil))
        respond(status: 200, body: SAAWSLoginTestFixtures.successResponse)

        try withLoginProfile(region: nil) { profile in
            assertThrowsError(SAAWSLoginRefreshError.regionUnavailable,
                              from: try AWSLoginCredentialsProvider.resolveCredentials(for: profile))
        }
        XCTAssertTrue(requests.isEmpty)
    }

    func testEndedSessionReportsSessionExpiredAndKeepsTheCache() throws {
        try writeCache(SAAWSLoginTestFixtures.cacheContents(expiresAt: Date().addingTimeInterval(-60)))
        respond(status: 401, body: Data(#"{"error":"TOKEN_EXPIRED","message":"The refresh token has expired."}"#.utf8))

        try withLoginProfile { profile in
            assertThrowsError(AWSLoginAuthError.sessionExpired,
                              from: try AWSLoginCredentialsProvider.resolveCredentials(for: profile))
        }
        XCTAssertEqual(try readCache()["refreshToken"] as? String, "oldRefreshToken")
    }

    func testFailedRenewalFallsBackToCredentialsThatAreStillValid() throws {
        try writeCache(SAAWSLoginTestFixtures.cacheContents(expiresAt: Date().addingTimeInterval(180)))
        AWSLoginCredentialsProvider.refreshTransport = { [unowned self] request in
            self.requests.append(request)
            throw SAAWSLoginRefreshError.requestFailed("offline")
        }

        try withLoginProfile { profile in
            let credentials = try AWSLoginCredentialsProvider.resolveCredentials(for: profile)
            XCTAssertEqual(credentials.accessKeyId, "ASIAOLD0000000000000")
        }
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(try readCache()["refreshToken"] as? String, "oldRefreshToken")
    }

    func testReadOnlyCacheDirectoryIsNeverRenewed() throws {
        try writeCache(SAAWSLoginTestFixtures.cacheContents(expiresAt: Date().addingTimeInterval(-60)))
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: cacheDirectory.path)
        respond(status: 200, body: SAAWSLoginTestFixtures.successResponse)

        try withLoginProfile { profile in
            assertThrowsError(SAAWSLoginRefreshError.writeAccessRequired,
                              from: try AWSLoginCredentialsProvider.resolveCredentials(for: profile))
        }
        XCTAssertTrue(requests.isEmpty)
    }

    func testReadOnlyCacheDirectoryKeepsUsingCredentialsThatAreStillValid() throws {
        try writeCache(SAAWSLoginTestFixtures.cacheContents(expiresAt: Date().addingTimeInterval(180)))
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: cacheDirectory.path)
        respond(status: 200, body: SAAWSLoginTestFixtures.successResponse)

        try withLoginProfile { profile in
            let credentials = try AWSLoginCredentialsProvider.resolveCredentials(for: profile)
            XCTAssertEqual(credentials.accessKeyId, "ASIAOLD0000000000000")
        }
        XCTAssertTrue(requests.isEmpty)
    }

    func testRenewalByAnotherProcessIsNotOverwrittenAndItsCredentialsAreUsed() throws {
        try writeCache(SAAWSLoginTestFixtures.cacheContents(expiresAt: Date().addingTimeInterval(120)))
        renewElsewhereDuringRequest(expiresIn: 900)

        try withLoginProfile { profile in
            let credentials = try AWSLoginCredentialsProvider.resolveCredentials(for: profile)
            XCTAssertEqual(credentials.accessKeyId, "ASIACLI0000000000000")
            XCTAssertEqual(credentials.sessionToken, "cliSessionToken")
        }
        XCTAssertEqual(try readCache()["refreshToken"] as? String, "cliRefreshToken")
    }

    func testRenewalByAnotherProcessThatIsAboutToExpireUsesTheRenewedCredentials() throws {
        try writeCache(SAAWSLoginTestFixtures.cacheContents(expiresAt: Date().addingTimeInterval(120)))
        renewElsewhereDuringRequest(expiresIn: 60)

        try withLoginProfile { profile in
            let credentials = try AWSLoginCredentialsProvider.resolveCredentials(for: profile)
            XCTAssertEqual(credentials.accessKeyId, "ASIANEW0000000000000")
        }
        XCTAssertEqual(try readCache()["refreshToken"] as? String, "cliRefreshToken")
    }

    func testFailedRenewalUsesCredentialsAnotherProcessRenewedMeanwhile() throws {
        try writeCache(SAAWSLoginTestFixtures.cacheContents(expiresAt: Date().addingTimeInterval(-60)))
        renewElsewhereDuringRequest(expiresIn: 900, status: 400,
                                    body: Data(#"{"error":"INVALID_REQUEST","message":"The provided authorization grant is invalid"}"#.utf8))

        try withLoginProfile { profile in
            let credentials = try AWSLoginCredentialsProvider.resolveCredentials(for: profile)
            XCTAssertEqual(credentials.accessKeyId, "ASIACLI0000000000000")
        }
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(try readCache()["refreshToken"] as? String, "cliRefreshToken")
    }

    func testRenewedSessionThatCannotBeSavedIsReported() throws {
        try writeCache(SAAWSLoginTestFixtures.cacheContents(expiresAt: Date().addingTimeInterval(-60)))
        AWSLoginCredentialsProvider.refreshTransport = { [unowned self] request in
            self.requests.append(request)
            try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: self.cacheDirectory.path)
            return (SAAWSLoginTestFixtures.successResponse, 200)
        }

        try withLoginProfile { profile in
            XCTAssertThrowsError(try AWSLoginCredentialsProvider.resolveCredentials(for: profile)) { error in
                guard case .cacheWriteFailed = error as? SAAWSLoginRefreshError else {
                    return XCTFail("Expected cacheWriteFailed, got \(error)")
                }
            }
        }
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(try readCache()["refreshToken"] as? String, "oldRefreshToken")
    }

    func testCacheWithoutRefreshTokenReportsSessionExpiredOnceExpired() throws {
        var contents = SAAWSLoginTestFixtures.cacheContents(expiresAt: Date().addingTimeInterval(-60))
        contents.removeValue(forKey: "refreshToken")
        try writeCache(contents)
        respond(status: 200, body: SAAWSLoginTestFixtures.successResponse)

        try withLoginProfile { profile in
            assertThrowsError(AWSLoginAuthError.sessionExpired,
                              from: try AWSLoginCredentialsProvider.resolveCredentials(for: profile))
        }
        XCTAssertTrue(requests.isEmpty)
    }

    func testNeedsWriteAccessGrantOnlyForReadOnlyConsoleSignInCaches() throws {
        try withLoginProfile { profile in
            XCTAssertFalse(AWSLoginCredentialsProvider.needsWriteAccessGrant(for: profile))

            try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: cacheDirectory.path)
            XCTAssertTrue(AWSLoginCredentialsProvider.needsWriteAccessGrant(for: profile))
        }

        let staticKeys = """
        [default]
        aws_access_key_id = AKIASTATIC00000000000
        aws_secret_access_key = staticSecret
        """
        let config = """
        [default]
        login_session = \(loginSession)
        """
        try AWSTestEnvironment.withTemporaryAWSFiles(credentials: staticKeys, config: config) { _, _ in
            XCTAssertFalse(AWSLoginCredentialsProvider.needsWriteAccessGrant(for: try AWSCredentials(profile: nil)))
        }
    }

    func testBackgroundTokenGenerationKeepsTheMainQueueResponsiveDuringASlowRenewal() throws {
        try writeCache(SAAWSLoginTestFixtures.cacheContents(expiresAt: Date().addingTimeInterval(-60)))
        let requestStarted = expectation(description: "renewal request started")
        let releaseRequest = DispatchSemaphore(value: 0)
        var requestRanOnMainThread = true
        AWSLoginCredentialsProvider.refreshTransport = { request in
            requestRanOnMainThread = Thread.isMainThread
            requestStarted.fulfill()
            _ = releaseRequest.wait(timeout: .now() + 10)
            return (SAAWSLoginTestFixtures.successResponse, 200)
        }

        try withLoginProfile { _ in
            let mainQueueRan = expectation(description: "main queue ran during the renewal")
            let tokenDelivered = expectation(description: "token delivered")
            var completionRanOnMainThread = false
            var token: String?

            AWSIAMAuthManager.generateAuthTokenInBackground(
                hostname: "mydb.123456789012.eu-west-1.rds.amazonaws.com",
                port: 3306,
                username: "db_admin",
                region: nil,
                profile: nil,
                parentWindow: nil
            ) { generatedToken, _ in
                completionRanOnMainThread = Thread.isMainThread
                token = generatedToken
                tokenDelivered.fulfill()
            }

            wait(for: [requestStarted], timeout: 5)
            DispatchQueue.main.async { mainQueueRan.fulfill() }
            wait(for: [mainQueueRan], timeout: 2)

            releaseRequest.signal()
            wait(for: [tokenDelivered], timeout: 5)

            XCTAssertFalse(requestRanOnMainThread)
            XCTAssertTrue(completionRanOnMainThread)
            XCTAssertEqual(token?.contains("X-Amz-Credential=ASIANEW0000000000000"), true)
        }
    }

    func testBackgroundTokenGenerationReportsAnEndedSessionWithTheProfileCommand() throws {
        try writeCache(SAAWSLoginTestFixtures.cacheContents(expiresAt: Date().addingTimeInterval(-60)))
        respond(status: 401, body: Data(#"{"error":"TOKEN_EXPIRED","message":"The refresh token has expired."}"#.utf8))

        try withLoginProfile(named: "team dev") { _ in
            let completed = expectation(description: "completion called")
            var completionRanOnMainThread = false
            var reportedError: NSError?

            AWSIAMAuthManager.generateAuthTokenInBackground(
                hostname: "mydb.123456789012.eu-west-1.rds.amazonaws.com",
                port: 3306,
                username: "db_admin",
                region: nil,
                profile: "team dev",
                parentWindow: nil,
                shouldContinue: { true }
            ) { token, error in
                XCTAssertNil(token)
                completionRanOnMainThread = Thread.isMainThread
                reportedError = error
                completed.fulfill()
            }

            wait(for: [completed], timeout: 5)

            XCTAssertTrue(completionRanOnMainThread)
            let error = try XCTUnwrap(reportedError)
            XCTAssertEqual(error as Error as? AWSLoginAuthError, .sessionExpired)
            XCTAssertTrue(error.localizedDescription.contains("`aws login --profile 'team dev'`"), error.localizedDescription)
        }
    }

    func testBackgroundTokenGenerationReportsAFailingEndpoint() throws {
        try writeCache(SAAWSLoginTestFixtures.cacheContents(expiresAt: Date().addingTimeInterval(-60)))
        respond(status: 503, body: Data(#"{"error":"server_error","message":"Unavailable"}"#.utf8))

        try withLoginProfile { _ in
            let completed = expectation(description: "completion called")
            var reportedError: NSError?

            AWSIAMAuthManager.generateAuthTokenInBackground(
                hostname: "mydb.123456789012.eu-west-1.rds.amazonaws.com",
                port: 3306,
                username: "db_admin",
                region: nil,
                profile: nil,
                parentWindow: nil
            ) { _, error in
                reportedError = error
                completed.fulfill()
            }

            wait(for: [completed], timeout: 5)
            XCTAssertEqual(reportedError?.localizedDescription,
                           SAAWSLoginRefreshError.requestFailed("Unavailable").localizedDescription)
        }
    }

    // MARK: - Helpers

    private func withLoginProfile(named name: String = "default", region: String? = "eu-west-1", _ body: (AWSCredentials) throws -> Void) throws {
        var config = """
        \(name == "default" ? "[default]" : "[profile \(name)]")
        login_session = \(loginSession)
        """
        if let region {
            config += "\nregion = \(region)"
        }

        try AWSTestEnvironment.withTemporaryAWSFiles(credentials: "", config: config) { _, _ in
            AWSIAMAuthManager.clearCachedCredentials(for: nil)
            try body(try AWSCredentials(profile: name))
        }
    }

    private func renewElsewhereDuringRequest(expiresIn: TimeInterval, status: Int = 200, body: Data = SAAWSLoginTestFixtures.successResponse) {
        AWSLoginCredentialsProvider.refreshTransport = { [unowned self] request in
            self.requests.append(request)
            var renewedElsewhere = SAAWSLoginTestFixtures.cacheContents(expiresAt: Date().addingTimeInterval(expiresIn))
            renewedElsewhere["accessToken"] = [
                "accessKeyId": "ASIACLI0000000000000",
                "secretAccessKey": "cliSecret",
                "sessionToken": "cliSessionToken",
                "accountId": "123456789012",
                "expiresAt": SAAWSLoginSession.formatTimestamp(Date().addingTimeInterval(expiresIn))
            ]
            renewedElsewhere["refreshToken"] = "cliRefreshToken"
            try self.writeCache(renewedElsewhere)
            return (body, status)
        }
    }

    private func respond(status: Int, body: Data) {
        AWSLoginCredentialsProvider.refreshTransport = { [unowned self] request in
            self.requests.append(request)
            return (body, status)
        }
    }

    private func writeCache(_ contents: [String: Any]) throws {
        try JSONSerialization.data(withJSONObject: contents).write(to: cacheFile)
    }

    private func readCache() throws -> [String: Any] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: cacheFile)) as? [String: Any])
    }
}
