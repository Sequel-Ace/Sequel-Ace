//
//  SAAWSLoginRefreshTests.swift
//  Unit Tests
//
//  Tests for renewing console sign-in (aws login) credentials.
//

import CryptoKit
import XCTest

/// Fixtures shared by the console sign-in renewal tests.
enum SAAWSLoginTestFixtures {

    /// A throwaway P-256 key in SEC1 PEM form, as `aws login` writes it.
    static let sec1Key = """
    -----BEGIN EC PRIVATE KEY-----
    MHcCAQEEIAuLlh4XqGasSdNNys96ooMaFIWbhexrcXe89nmxVbw6oAoGCCqGSM49
    AwEHoUQDQgAE9MAbwEDwdchpRpBDcXhA/9M48frY1wCSqOtPfWmEAzfoYGbE7loA
    W0fo90oW4qtVuWLtbOhIqlSYIn1nnTZtaA==
    -----END EC PRIVATE KEY-----

    """

    /// The same key in PKCS#8 PEM form.
    static let pkcs8Key = """
    -----BEGIN PRIVATE KEY-----
    MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQgC4uWHheoZqxJ003K
    z3qigxoUhZuF7Gtxd7z2ebFVvDqhRANCAAT0wBvAQPB1yGlGkENxeED/0zjx+tjX
    AJKo6099aYQDN+hgZsTuWgBbR+j3Shbiq1W5Yu1s6EiqVJgifWedNm1o
    -----END PRIVATE KEY-----

    """

    /// The key's public coordinates, as computed by OpenSSL.
    static let publicX = "9MAbwEDwdchpRpBDcXhA_9M48frY1wCSqOtPfWmEAzc"
    static let publicY = "6GBmxO5aAFtH6PdKFuKrVbli7WzoSKpUmCJ9Z502bWg"

    /// An unsigned JWT whose payload carries `issuer` as its `iss` claim.
    static func identityToken(issuer: String) -> String {
        let header = SAAWSDPoPProof.base64URLEncoded(Data(#"{"alg":"ES384","typ":"JWT"}"#.utf8))
        let payload = SAAWSDPoPProof.base64URLEncoded(Data(#"{"aud":"arn:aws:signin:::devtools/same-device","iss":"\#(issuer)"}"#.utf8))
        return "\(header).\(payload).c2lnbmF0dXJl"
    }

    /// A cache file dictionary in the shape `aws login` writes.
    static func cacheContents(expiresAt: Date, issuer: String? = "https://eu-north-1.signin.aws.amazon.com/signin") -> [String: Any] {
        var contents: [String: Any] = [
            "accessToken": [
                "accessKeyId": "ASIAOLD0000000000000",
                "secretAccessKey": "oldSecret",
                "sessionToken": "oldSessionToken",
                "accountId": "123456789012",
                "expiresAt": SAAWSLoginSession.formatTimestamp(expiresAt)
            ],
            "tokenType": "urn:aws:params:oauth:token-type:access_token_sigv4",
            "clientId": "arn:aws:signin:::devtools/same-device",
            "refreshToken": "oldRefreshToken",
            "dpopKey": sec1Key,
            "futureField": "kept"
        ]
        if let issuer {
            contents["idToken"] = identityToken(issuer: issuer)
        }
        return contents
    }

    /// A successful refresh response body.
    static let successResponse = Data("""
    {
      "accessToken": {
        "accessKeyId": "ASIANEW0000000000000",
        "secretAccessKey": "newSecret",
        "sessionToken": "newSessionToken"
      },
      "tokenType": "aws_sigv4",
      "expiresIn": 900,
      "refreshToken": "newRefreshToken"
    }
    """.utf8)
}

final class SAAWSSignInEndpointTests: XCTestCase {

    func testTokenURLForCommercialRegion() {
        XCTAssertEqual(SAAWSSignInEndpoint.tokenURL(forRegion: "eu-north-1")?.absoluteString,
                       "https://eu-north-1.signin.aws.amazon.com/v1/token")
        XCTAssertEqual(SAAWSSignInEndpoint.tokenURL(forRegion: "us-east-1")?.absoluteString,
                       "https://us-east-1.signin.aws.amazon.com/v1/token")
    }

    func testTokenURLForOtherPartitions() {
        let expected = [
            "cn-north-1": "https://cn-north-1.signin.amazonaws.cn/v1/token",
            "us-gov-west-1": "https://us-gov-west-1.signin.amazonaws-us-gov.com/v1/token",
            "eusc-de-east-1": "https://eusc-de-east-1.signin.amazonaws-eusc.eu/v1/token",
            "us-iso-east-1": "https://us-iso-east-1.signin.c2shome.ic.gov/v1/token",
            "us-isob-east-1": "https://us-isob-east-1.signin.sc2shome.sgov.gov/v1/token",
            "us-isof-south-1": "https://us-isof-south-1.signin.csphome.hci.ic.gov/v1/token",
            "eu-isoe-west-1": "https://eu-isoe-west-1.signin.csphome.adc-e.uk/v1/token"
        ]

        for (region, url) in expected {
            XCTAssertEqual(SAAWSSignInEndpoint.tokenURL(forRegion: region)?.absoluteString, url, region)
        }
    }

    func testTokenURLRejectsInvalidRegions() {
        for region in ["", "eu", "EU-NORTH-1", "evil.example.com/x", "eu-north-1.attacker", "eu north 1"] {
            XCTAssertNil(SAAWSSignInEndpoint.tokenURL(forRegion: region), region)
        }
    }

    func testRegionFromIssuer() {
        XCTAssertEqual(SAAWSSignInEndpoint.region(fromIssuer: "https://eu-north-1.signin.aws.amazon.com/signin"), "eu-north-1")
        XCTAssertEqual(SAAWSSignInEndpoint.region(fromIssuer: "https://cn-north-1.signin.amazonaws.cn/signin"), "cn-north-1")
        XCTAssertNil(SAAWSSignInEndpoint.region(fromIssuer: "https://signin.aws.amazon.com/signin"))
        XCTAssertNil(SAAWSSignInEndpoint.region(fromIssuer: "https://eu-north-1.example.com/signin"))
        XCTAssertNil(SAAWSSignInEndpoint.region(fromIssuer: "not a url"))
    }
}

final class SAAWSDPoPProofTests: XCTestCase {

    private let url = URL(string: "https://eu-north-1.signin.aws.amazon.com/v1/token")!

    func testProofHeaderAndClaims() throws {
        let issuedAt = Date(timeIntervalSince1970: 1_790_000_000)
        let id = UUID(uuidString: "5A1B8B3E-2F1D-4C6B-9E0A-0123456789AB")!

        let proof = try SAAWSDPoPProof.make(privateKeyPEM: SAAWSLoginTestFixtures.sec1Key, url: url, issuedAt: issuedAt, id: id)
        let (header, claims, _) = try decode(proof)

        XCTAssertEqual(header["typ"] as? String, "dpop+jwt")
        XCTAssertEqual(header["alg"] as? String, "ES256")
        let jwk = try XCTUnwrap(header["jwk"] as? [String: String])
        XCTAssertEqual(jwk, ["kty": "EC", "crv": "P-256", "x": SAAWSLoginTestFixtures.publicX, "y": SAAWSLoginTestFixtures.publicY])

        XCTAssertEqual(claims["htm"] as? String, "POST")
        XCTAssertEqual(claims["htu"] as? String, url.absoluteString)
        XCTAssertEqual(claims["iat"] as? Int, 1_790_000_000)
        XCTAssertEqual(claims["jti"] as? String, "5a1b8b3e-2f1d-4c6b-9e0a-0123456789ab")
        XCTAssertEqual(Set(claims.keys), ["htm", "htu", "iat", "jti"])
    }

    func testProofSignatureVerifiesWithTheEmbeddedPublicKey() throws {
        let proof = try SAAWSDPoPProof.make(privateKeyPEM: SAAWSLoginTestFixtures.sec1Key, url: url, issuedAt: Date())
        let (header, _, signature) = try decode(proof)

        let jwk = try XCTUnwrap(header["jwk"] as? [String: String])
        let x = try XCTUnwrap(SAAWSDPoPProof.base64URLDecoded(jwk["x"] ?? ""))
        let y = try XCTUnwrap(SAAWSDPoPProof.base64URLDecoded(jwk["y"] ?? ""))
        let publicKey = try P256.Signing.PublicKey(rawRepresentation: x + y)

        XCTAssertEqual(signature.count, 64)
        let signingInput = proof.split(separator: ".").prefix(2).joined(separator: ".")
        XCTAssertTrue(publicKey.isValidSignature(try P256.Signing.ECDSASignature(rawRepresentation: signature),
                                                 for: Data(signingInput.utf8)))
    }

    func testProofAcceptsPKCS8Key() throws {
        let proof = try SAAWSDPoPProof.make(privateKeyPEM: SAAWSLoginTestFixtures.pkcs8Key, url: url, issuedAt: Date())
        let jwk = try XCTUnwrap(try decode(proof).header["jwk"] as? [String: String])

        XCTAssertEqual(jwk["x"], SAAWSLoginTestFixtures.publicX)
        XCTAssertEqual(jwk["y"], SAAWSLoginTestFixtures.publicY)
    }

    func testProofRejectsUnreadableKey() {
        XCTAssertThrowsError(try SAAWSDPoPProof.make(privateKeyPEM: "not a key", url: url, issuedAt: Date())) { error in
            XCTAssertEqual(error as? SAAWSLoginRefreshError, .invalidSigningKey)
        }
    }

    private func decode(_ proof: String) throws -> (header: [String: Any], claims: [String: Any], signature: Data) {
        let segments = proof.split(separator: ".").map(String.init)
        XCTAssertEqual(segments.count, 3)

        let header = try XCTUnwrap(try JSONSerialization.jsonObject(with: XCTUnwrap(SAAWSDPoPProof.base64URLDecoded(segments[0]))) as? [String: Any])
        let claims = try XCTUnwrap(try JSONSerialization.jsonObject(with: XCTUnwrap(SAAWSDPoPProof.base64URLDecoded(segments[1]))) as? [String: Any])
        let signature = try XCTUnwrap(SAAWSDPoPProof.base64URLDecoded(segments[2]))
        return (header, claims, signature)
    }
}

final class SAAWSLoginSessionTests: XCTestCase {

    private func session(_ contents: [String: Any]) throws -> SAAWSLoginSession {
        try SAAWSLoginSession(jsonData: JSONSerialization.data(withJSONObject: contents))
    }

    func testIssuingRegionComesFromIdToken() throws {
        let contents = SAAWSLoginTestFixtures.cacheContents(expiresAt: Date())
        XCTAssertEqual(try session(contents).issuingRegion, "eu-north-1")
    }

    func testIssuingRegionAcceptsIdentityTokenField() throws {
        var contents = SAAWSLoginTestFixtures.cacheContents(expiresAt: Date(), issuer: nil)
        contents["identityToken"] = SAAWSLoginTestFixtures.identityToken(issuer: "https://us-west-2.signin.aws.amazon.com/signin")

        XCTAssertEqual(try session(contents).issuingRegion, "us-west-2")
    }

    func testIssuingRegionIsNilWithoutIdentityToken() throws {
        let contents = SAAWSLoginTestFixtures.cacheContents(expiresAt: Date(), issuer: nil)
        XCTAssertNil(try session(contents).issuingRegion)
    }

    func testNeedsRefreshWithinTheRefreshWindow() throws {
        let now = Date()

        XCTAssertFalse(try session(SAAWSLoginTestFixtures.cacheContents(expiresAt: now.addingTimeInterval(301))).needsRefresh(at: now))
        XCTAssertTrue(try session(SAAWSLoginTestFixtures.cacheContents(expiresAt: now.addingTimeInterval(299))).needsRefresh(at: now))
        XCTAssertTrue(try session(SAAWSLoginTestFixtures.cacheContents(expiresAt: now.addingTimeInterval(-60))).needsRefresh(at: now))
    }

    func testRefreshMaterialIsRead() throws {
        let cached = try session(SAAWSLoginTestFixtures.cacheContents(expiresAt: Date()))

        XCTAssertEqual(cached.refreshToken, "oldRefreshToken")
        XCTAssertEqual(cached.clientId, "arn:aws:signin:::devtools/same-device")
        XCTAssertEqual(cached.dpopKey, SAAWSLoginTestFixtures.sec1Key)
    }

    func testApplyingResponseReplacesCredentialsAndKeepsEverythingElse() throws {
        let issuedAt = Date(timeIntervalSince1970: 1_790_000_000)
        let original = SAAWSLoginTestFixtures.cacheContents(expiresAt: issuedAt)
        let response = try SAAWSLoginTokenResponse.parse(data: SAAWSLoginTestFixtures.successResponse, statusCode: 200)

        let renewed = try session(original).applying(response, issuedAt: issuedAt)
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: renewed.jsonData()) as? [String: Any])
        let accessToken = try XCTUnwrap(root["accessToken"] as? [String: String])

        XCTAssertEqual(accessToken, [
            "accessKeyId": "ASIANEW0000000000000",
            "secretAccessKey": "newSecret",
            "sessionToken": "newSessionToken",
            "accountId": "123456789012",
            "expiresAt": SAAWSLoginSession.formatTimestamp(issuedAt.addingTimeInterval(900))
        ])
        XCTAssertEqual(root["refreshToken"] as? String, "newRefreshToken")
        for key in ["idToken", "dpopKey", "clientId", "tokenType", "futureField"] {
            XCTAssertEqual(root[key] as? String, original[key] as? String, key)
        }
    }

    func testCredentialsThrowSessionExpiredOnceExpired() throws {
        let now = Date()
        let cached = try session(SAAWSLoginTestFixtures.cacheContents(expiresAt: now.addingTimeInterval(-1)))

        XCTAssertThrowsError(try cached.credentials(at: now)) { error in
            XCTAssertEqual(error as? AWSLoginAuthError, .sessionExpired)
        }
    }

    func testTimestampParsingAcceptsSDKFormats() {
        let expected = Date(timeIntervalSince1970: 1_790_675_417)

        XCTAssertEqual(SAAWSLoginSession.parseTimestamp("2026-09-29T09:50:17Z"), expected)
        XCTAssertEqual(SAAWSLoginSession.parseTimestamp("2026-09-29T09:50:17+00:00"), expected)
        XCTAssertEqual(SAAWSLoginSession.parseTimestamp("2026-09-29T11:50:17+02:00"), expected)
        XCTAssertEqual(SAAWSLoginSession.parseTimestamp("2026-09-29T09:50:17.000Z"), expected)
        XCTAssertNotNil(SAAWSLoginSession.parseTimestamp("2026-09-29T11:50:17.123456789+02:00"))
        XCTAssertEqual(SAAWSLoginSession.formatTimestamp(expected), "2026-09-29T09:50:17Z")
    }
}

final class SAAWSLoginTokenResponseTests: XCTestCase {

    func testParsesSuccessfulResponse() throws {
        let response = try SAAWSLoginTokenResponse.parse(data: SAAWSLoginTestFixtures.successResponse, statusCode: 200)

        XCTAssertEqual(response, SAAWSLoginTokenResponse(
            accessKeyId: "ASIANEW0000000000000",
            secretAccessKey: "newSecret",
            sessionToken: "newSessionToken",
            expiresIn: 900,
            refreshToken: "newRefreshToken"
        ))
    }

    func testRejectsIncompleteResponse() {
        let body = Data(#"{"accessToken":{"accessKeyId":"ASIA"},"expiresIn":900,"refreshToken":"r"}"#.utf8)

        XCTAssertThrowsError(try SAAWSLoginTokenResponse.parse(data: body, statusCode: 200)) { error in
            XCTAssertEqual(error as? SAAWSLoginRefreshError, .invalidResponse)
        }
    }

    func testMapsSessionErrorCodes() {
        XCTAssertEqual(parseError(status: 401, code: "TOKEN_EXPIRED") as? AWSLoginAuthError, .sessionExpired)
        XCTAssertEqual(parseError(status: 403, code: "USER_CREDENTIALS_CHANGED") as? SAAWSLoginRefreshError, .credentialsChanged)
        XCTAssertEqual(parseError(status: 403, code: "INSUFFICIENT_PERMISSIONS") as? SAAWSLoginRefreshError, .insufficientPermissions)
        XCTAssertEqual(parseError(status: 400, code: "INVALID_REQUEST") as? SAAWSLoginRefreshError, .grantRejected)
    }

    func testMapsThrottlingAndServerErrorsToRequestFailures() {
        XCTAssertEqual(parseError(status: 429, code: "INVALID_REQUEST", message: "Slow down") as? SAAWSLoginRefreshError,
                       .requestFailed("Slow down"))
        XCTAssertEqual(parseError(status: 500, code: "server_error", message: "Oops") as? SAAWSLoginRefreshError,
                       .requestFailed("Oops"))
    }

    private func parseError(status: Int, code: String, message: String = "") -> Error? {
        let body = Data(#"{"error":"\#(code)","message":"\#(message)"}"#.utf8)
        do {
            _ = try SAAWSLoginTokenResponse.parse(data: body, statusCode: status)
            return nil
        } catch {
            return error
        }
    }
}

final class SAAWSLoginRefreshRequestTests: XCTestCase {

    func testRequestCarriesJSONBodyAndDPoPProof() throws {
        let url = try XCTUnwrap(SAAWSSignInEndpoint.tokenURL(forRegion: "eu-north-1"))
        let request = try SAAWSLoginRefreshRequest.make(
            url: url,
            clientId: "arn:aws:signin:::devtools/same-device",
            refreshToken: "refresh",
            dpopKey: SAAWSLoginTestFixtures.sec1Key,
            issuedAt: Date()
        )

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url, url)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "DPoP")?.split(separator: ".").count, 3)

        let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: String])
        XCTAssertEqual(body, [
            "clientId": "arn:aws:signin:::devtools/same-device",
            "grantType": "refresh_token",
            "refreshToken": "refresh"
        ])
    }
}

final class SAAtomicFileReplacementTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SequelAce-AtomicReplace-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        try? FileManager.default.removeItem(at: directory)
    }

    func testCommitReplacesTheFileWithOwnerOnlyPermissions() throws {
        let file = directory.appendingPathComponent("session.json")
        try Data("old".utf8).write(to: file)

        let replacement = try SAAtomicFileReplacement(replacing: file.path)
        try replacement.commit(Data("new".utf8))

        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "new")
        let permissions = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["session.json"])
    }

    func testDiscardLeavesTheFileAndNoTemporaryFile() throws {
        let file = directory.appendingPathComponent("session.json")
        try Data("old".utf8).write(to: file)

        let replacement = try SAAtomicFileReplacement(replacing: file.path)
        replacement.discard()

        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "old")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["session.json"])
    }

    func testReadOnlyDirectoryRequiresWriteAccess() throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)

        XCTAssertThrowsError(try SAAtomicFileReplacement(replacing: directory.appendingPathComponent("session.json").path)) { error in
            XCTAssertEqual(error as? SAAWSLoginRefreshError, .writeAccessRequired)
        }
        XCTAssertFalse(SAAtomicFileReplacement.canCreateFiles(inDirectory: directory.path))
    }

    func testCanCreateFilesLeavesNothingBehind() throws {
        XCTAssertTrue(SAAtomicFileReplacement.canCreateFiles(inDirectory: directory.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), [])
    }
}

final class SAAWSSignInCommandTests: XCTestCase {

    func testCommandsNameTheProfile() {
        XCTAssertEqual(SAAWSSignInCommand.login(profile: "dev"), "aws login --profile dev")
        XCTAssertEqual(SAAWSSignInCommand.ssoLogin(profile: "dev"), "aws sso login --profile dev")
    }

    func testCommandsNameTheDefaultProfileWhenNoneIsSelected() {
        XCTAssertEqual(SAAWSSignInCommand.login(profile: nil), "aws login --profile default")
        XCTAssertEqual(SAAWSSignInCommand.login(profile: "  "), "aws login --profile default")
        XCTAssertEqual(SAAWSSignInCommand.ssoLogin(profile: ""), "aws sso login --profile default")
    }

    func testProfileNamesAreShellQuotedWhenNeeded() {
        XCTAssertEqual(SAAWSSignInCommand.shellQuoted("team-prod_1.eu"), "team-prod_1.eu")
        XCTAssertEqual(SAAWSSignInCommand.shellQuoted("my profile"), "'my profile'")
        XCTAssertEqual(SAAWSSignInCommand.shellQuoted("it's"), "'it'\\''s'")
        XCTAssertEqual(SAAWSSignInCommand.shellQuoted("dev;rm -rf ~"), "'dev;rm -rf ~'")
        XCTAssertEqual(SAAWSSignInCommand.shellQuoted("$(whoami)"), "'$(whoami)'")
        XCTAssertEqual(SAAWSSignInCommand.login(profile: "my profile"), "aws login --profile 'my profile'")
    }

    func testCommandIsOnlyNamedForErrorsThatSigningInResolves() {
        XCTAssertEqual(SAAWSSignInCommand.command(for: AWSLoginAuthError.sessionExpired, profile: "dev"), "aws login --profile dev")
        XCTAssertEqual(SAAWSSignInCommand.command(for: AWSLoginAuthError.cacheNotFound, profile: "dev"), "aws login --profile dev")
        XCTAssertEqual(SAAWSSignInCommand.command(for: SAAWSLoginRefreshError.grantRejected, profile: "dev"), "aws login --profile dev")
        XCTAssertEqual(SAAWSSignInCommand.command(for: AWSSSOClientError.tokenExpired, profile: "dev"), "aws sso login --profile dev")

        XCTAssertNil(SAAWSSignInCommand.command(for: AWSLoginAuthError.invalidProfile, profile: "dev"))
        XCTAssertNil(SAAWSSignInCommand.command(for: SAAWSLoginRefreshError.insufficientPermissions, profile: "dev"))
        XCTAssertNil(SAAWSSignInCommand.command(for: SAAWSLoginRefreshError.requestFailed("offline"), profile: "dev"))
        XCTAssertNil(SAAWSSignInCommand.command(for: AWSSSOClientError.networkFailure, profile: "dev"))
        XCTAssertNil(SAAWSSignInCommand.command(for: AWSIAMAuthError.tokenGenerationFailed, profile: "dev"))
    }

    func testMessageAppendsTheCommandForTheProfile() {
        XCTAssertEqual(SAAWSSignInCommand.message(for: AWSLoginAuthError.sessionExpired, profile: "dev"),
                       "Your AWS console sign-in session has ended. Run `aws login --profile dev` in Terminal, then try again.")
        XCTAssertEqual(SAAWSSignInCommand.message(for: AWSLoginAuthError.invalidCacheContents, profile: nil),
                       "The cached AWS console sign-in session could not be read. Run `aws login --profile default` in Terminal, then try again.")
        XCTAssertEqual(SAAWSSignInCommand.message(for: SAAWSLoginRefreshError.insufficientPermissions, profile: "dev"),
                       SAAWSLoginRefreshError.insufficientPermissions.localizedDescription)
    }

    func testPresentableErrorKeepsTheDomainAndCode() throws {
        let original = AWSLoginAuthError.sessionExpired as NSError
        let presentable = SAAWSSignInCommand.presentableError(AWSLoginAuthError.sessionExpired, profile: "dev")

        XCTAssertEqual(presentable.domain, original.domain)
        XCTAssertEqual(presentable.code, original.code)
        XCTAssertTrue(presentable.localizedDescription.contains("`aws login --profile dev`"))
        XCTAssertEqual(presentable as Error as? AWSLoginAuthError, .sessionExpired)
    }
}
