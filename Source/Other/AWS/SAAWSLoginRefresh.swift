//
//  SAAWSLoginRefresh.swift
//  Sequel Ace
//
//  Copyright (c) 2026 Sequel-Ace. All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person
//  obtaining a copy of this software and associated documentation
//  files (the "Software"), to deal in the Software without
//  restriction, including without limitation the rights to use,
//  copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the
//  Software is furnished to do so, subject to the following
//  conditions:
//
//  The above copyright notice and this permission notice shall be
//  included in all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
//  EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
//  OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
//  NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
//  HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
//  WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
//  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
//  OTHER DEALINGS IN THE SOFTWARE.
//

import CryptoKit
import Foundation

/// Errors raised while renewing console sign-in (`aws login`) credentials.
enum SAAWSLoginRefreshError: Error, LocalizedError, Equatable {
    case credentialsChanged
    case insufficientPermissions
    case grantRejected
    case regionUnavailable
    case writeAccessRequired
    case invalidSigningKey
    case invalidResponse
    case requestFailed(String)
    case cacheWriteFailed(String)

    var errorDescription: String? {
        switch self {
        case .credentialsChanged:
            return NSLocalizedString("Your AWS sign-in credentials changed after you signed in.", comment: "aws login refresh error: the user's AWS password or credentials changed")
        case .insufficientPermissions:
            return NSLocalizedString("AWS did not allow Sequel Ace to renew your console sign-in session. Your IAM identity needs the signin:CreateOAuth2Token permission.", comment: "aws login refresh error: missing IAM permission")
        case .grantRejected:
            return NSLocalizedString("AWS rejected the renewal of your console sign-in session.", comment: "aws login refresh error: AWS rejected the refresh token")
        case .regionUnavailable:
            return NSLocalizedString("Sequel Ace could not tell which AWS region your console sign-in session belongs to.", comment: "aws login refresh error: no region for the sign-in session")
        case .writeAccessRequired:
            return NSLocalizedString("Your AWS console sign-in credentials have expired. To renew them automatically, Sequel Ace needs permission to update your .aws folder, which it asks for when you connect from the connection window.", comment: "aws login refresh error: the .aws folder is read-only for Sequel Ace")
        case .invalidSigningKey:
            return NSLocalizedString("The cached AWS console sign-in session has an unreadable signing key.", comment: "aws login refresh error: the cached DPoP key cannot be read")
        case .invalidResponse:
            return NSLocalizedString("AWS returned an unexpected response while renewing your console sign-in session.", comment: "aws login refresh error: malformed response")
        case .requestFailed(let detail):
            return String(format: NSLocalizedString("Sequel Ace could not renew your AWS console sign-in session: %@", comment: "aws login refresh error: request failed; %@ is the underlying error"), detail)
        case .cacheWriteFailed(let detail):
            return String(format: NSLocalizedString("Sequel Ace renewed your AWS console sign-in session but could not save it: %@", comment: "aws login refresh error: the renewed session could not be written to the cache file; %@ is the underlying error"), detail)
        }
    }
}

// MARK: - Endpoint

/// Builds AWS Sign-In token endpoint URLs.
enum SAAWSSignInEndpoint {

    private static let partitionDomains: [(regionPrefix: String, domain: String)] = [
        ("us-isob-", "signin.sc2shome.sgov.gov"),
        ("us-isof-", "signin.csphome.hci.ic.gov"),
        ("us-iso-", "signin.c2shome.ic.gov"),
        ("eu-isoe-", "signin.csphome.adc-e.uk"),
        ("us-gov-", "signin.amazonaws-us-gov.com"),
        ("eusc-", "signin.amazonaws-eusc.eu"),
        ("cn-", "signin.amazonaws.cn")
    ]

    private static let defaultDomain = "signin.aws.amazon.com"

    /// Returns true when `region` has the shape of an AWS region name, such as `eu-north-1`.
    static func isValidRegion(_ region: String) -> Bool {
        region.range(of: "^[a-z]{2,5}(-[a-z0-9]+){2,3}$", options: .regularExpression) != nil
    }

    /// The `CreateOAuth2Token` URL for `region`, or nil when `region` is not a valid region name.
    static func tokenURL(forRegion region: String) -> URL? {
        guard isValidRegion(region) else { return nil }

        let domain = partitionDomains.first { region.hasPrefix($0.regionPrefix) }?.domain ?? defaultDomain
        return URL(string: "https://\(region).\(domain)/v1/token")
    }

    /// The region named by a Sign-In issuer URL such as `https://eu-north-1.signin.aws.amazon.com/signin`.
    static func region(fromIssuer issuer: String) -> String? {
        guard let host = URL(string: issuer)?.host?.lowercased() else { return nil }

        let labels = host.split(separator: ".", maxSplits: 1)
        guard labels.count == 2, labels[1].hasPrefix("signin.") else { return nil }

        let region = String(labels[0])
        return isValidRegion(region) ? region : nil
    }
}

// MARK: - DPoP Proof

/// Builds DPoP proofs (RFC 9449) for AWS Sign-In token requests.
enum SAAWSDPoPProof {

    /// A compact ES256 JWT proving possession of `privateKeyPEM` for a POST to `url`.
    static func make(privateKeyPEM: String, url: URL, issuedAt: Date, id: UUID = UUID()) throws -> String {
        let privateKey: P256.Signing.PrivateKey
        do {
            privateKey = try P256.Signing.PrivateKey(pemRepresentation: privateKeyPEM)
        } catch {
            throw SAAWSLoginRefreshError.invalidSigningKey
        }

        let publicKey = privateKey.publicKey.rawRepresentation
        let header: [String: Any] = [
            "typ": "dpop+jwt",
            "alg": "ES256",
            "jwk": [
                "kty": "EC",
                "crv": "P-256",
                "x": base64URLEncoded(publicKey.prefix(32)),
                "y": base64URLEncoded(publicKey.suffix(32))
            ]
        ]
        let claims: [String: Any] = [
            "jti": id.uuidString.lowercased(),
            "htm": "POST",
            "htu": url.absoluteString,
            "iat": Int(issuedAt.timeIntervalSince1970)
        ]

        let signingInput = try base64URLEncoded(jsonData(header)) + "." + base64URLEncoded(jsonData(claims))
        let signature = try privateKey.signature(for: Data(signingInput.utf8))

        return signingInput + "." + base64URLEncoded(signature.rawRepresentation)
    }

    /// Unpadded base64url encoding of `data`.
    static func base64URLEncoded<D: DataProtocol>(_ data: D) -> String {
        Data(data).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Decodes unpadded base64url text.
    static func base64URLDecoded(_ text: String) -> Data? {
        var base64 = text
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        return Data(base64Encoded: base64)
    }

    private static func jsonData(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
    }
}

// MARK: - Cached Session

/// The contents of an `aws login` cache file.
struct SAAWSLoginSession {

    /// Credentials are renewed once they expire within this interval.
    static let refreshWindow: TimeInterval = 5 * 60

    private(set) var root: [String: Any]

    /// Parses cache file JSON; throws `invalidCacheContents` when the credentials are missing.
    init(jsonData: Data) throws {
        guard let root = (try? JSONSerialization.jsonObject(with: jsonData)) as? [String: Any],
              let accessToken = root["accessToken"] as? [String: Any],
              Self.nonEmptyString(accessToken["accessKeyId"]) != nil,
              Self.nonEmptyString(accessToken["secretAccessKey"]) != nil else {
            throw AWSLoginAuthError.invalidCacheContents
        }

        self.root = root
    }

    private var accessToken: [String: Any] {
        root["accessToken"] as? [String: Any] ?? [:]
    }

    /// The cached credential expiry, when present.
    var expiration: Date? {
        Self.parseTimestamp(accessToken["expiresAt"] as? String)
    }

    /// The refresh token, when present.
    var refreshToken: String? {
        Self.nonEmptyString(root["refreshToken"])
    }

    /// The OAuth client ID the session was issued to, when present.
    var clientId: String? {
        Self.nonEmptyString(root["clientId"])
    }

    /// The PEM private key the refresh token is bound to, when present.
    var dpopKey: String? {
        Self.nonEmptyString(root["dpopKey"])
    }

    /// The region the session was issued in, read from the identity token's issuer.
    var issuingRegion: String? {
        for key in ["idToken", "identityToken"] {
            guard let token = Self.nonEmptyString(root[key]),
                  let issuer = Self.issuer(ofJWT: token),
                  let region = SAAWSSignInEndpoint.region(fromIssuer: issuer) else {
                continue
            }
            return region
        }
        return nil
    }

    /// Seconds until the cached credentials expire, or nil when they carry no expiry.
    func remainingLifetime(at now: Date) -> TimeInterval? {
        expiration.map { $0.timeIntervalSince(now) }
    }

    /// True when the cached credentials expire within `refreshWindow` of `now`.
    func needsRefresh(at now: Date) -> Bool {
        guard let remaining = remainingLifetime(at: now) else { return false }
        return remaining <= Self.refreshWindow
    }

    /// The cached credentials; throws `sessionExpired` when they have expired at `now`.
    func credentials(at now: Date) throws -> AWSCredentials {
        if let expiration, expiration <= now {
            throw AWSLoginAuthError.sessionExpired
        }

        return AWSCredentials(
            accessKeyId: Self.nonEmptyString(accessToken["accessKeyId"]) ?? "",
            secretAccessKey: Self.nonEmptyString(accessToken["secretAccessKey"]) ?? "",
            sessionToken: Self.nonEmptyString(accessToken["sessionToken"]),
            expiration: expiration
        )
    }

    /// A copy holding the credentials and refresh token from `response`, issued at `now`.
    func applying(_ response: SAAWSLoginTokenResponse, issuedAt now: Date) -> SAAWSLoginSession {
        var updatedAccessToken = accessToken
        updatedAccessToken["accessKeyId"] = response.accessKeyId
        updatedAccessToken["secretAccessKey"] = response.secretAccessKey
        updatedAccessToken["sessionToken"] = response.sessionToken
        updatedAccessToken["expiresAt"] = Self.formatTimestamp(now.addingTimeInterval(response.expiresIn))

        var updated = self
        updated.root["accessToken"] = updatedAccessToken
        updated.root["refreshToken"] = response.refreshToken
        return updated
    }

    /// The session encoded as cache file JSON.
    func jsonData() throws -> Data {
        try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys, .withoutEscapingSlashes])
    }

    /// Parses an ISO-8601 timestamp with or without fractional seconds.
    static func parseTimestamp(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }

        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    /// Formats `date` as a whole-second UTC ISO-8601 timestamp.
    static func formatTimestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private static func issuer(ofJWT token: String) -> String? {
        let segments = token.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == 3,
              let payload = SAAWSDPoPProof.base64URLDecoded(String(segments[1])),
              let claims = (try? JSONSerialization.jsonObject(with: payload)) as? [String: Any] else {
            return nil
        }
        return claims["iss"] as? String
    }

    private static func nonEmptyString(_ value: Any?) -> String? {
        guard let string = value as? String, !string.isEmpty else { return nil }
        return string
    }
}

// MARK: - Token Response

/// A successful `CreateOAuth2Token` refresh response.
struct SAAWSLoginTokenResponse: Equatable {
    let accessKeyId: String
    let secretAccessKey: String
    let sessionToken: String
    let expiresIn: TimeInterval
    let refreshToken: String

    /// Parses a response body, throwing the error an unsuccessful response reports.
    static func parse(data: Data, statusCode: Int) throws -> SAAWSLoginTokenResponse {
        let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]

        guard statusCode == 200 else {
            throw error(forStatusCode: statusCode, body: root)
        }

        guard let body = (root?["tokenOutput"] as? [String: Any]) ?? root,
              let accessToken = body["accessToken"] as? [String: Any],
              let accessKeyId = accessToken["accessKeyId"] as? String, !accessKeyId.isEmpty,
              let secretAccessKey = accessToken["secretAccessKey"] as? String, !secretAccessKey.isEmpty,
              let sessionToken = accessToken["sessionToken"] as? String, !sessionToken.isEmpty,
              let expiresIn = (body["expiresIn"] as? NSNumber)?.doubleValue, expiresIn > 0,
              let refreshToken = body["refreshToken"] as? String, !refreshToken.isEmpty else {
            throw SAAWSLoginRefreshError.invalidResponse
        }

        return SAAWSLoginTokenResponse(
            accessKeyId: accessKeyId,
            secretAccessKey: secretAccessKey,
            sessionToken: sessionToken,
            expiresIn: expiresIn,
            refreshToken: refreshToken
        )
    }

    /// The error an unsuccessful response reports, keyed on its `error` code.
    static func error(forStatusCode statusCode: Int, body: [String: Any]?) -> Error {
        switch body?["error"] as? String {
        case "TOKEN_EXPIRED":
            return AWSLoginAuthError.sessionExpired
        case "USER_CREDENTIALS_CHANGED":
            return SAAWSLoginRefreshError.credentialsChanged
        case "INSUFFICIENT_PERMISSIONS":
            return SAAWSLoginRefreshError.insufficientPermissions
        default:
            break
        }

        if statusCode == 429 || statusCode >= 500 {
            let message = (body?["message"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                ?? HTTPURLResponse.localizedString(forStatusCode: statusCode)
            return SAAWSLoginRefreshError.requestFailed(message)
        }

        return SAAWSLoginRefreshError.grantRejected
    }
}

// MARK: - Request

/// Builds and sends `CreateOAuth2Token` refresh requests.
enum SAAWSLoginRefreshRequest {

    /// Seconds to wait for the token endpoint.
    static let timeout: TimeInterval = 15

    /// A refresh request for `refreshToken`, carrying a DPoP proof signed with `dpopKey`.
    static func make(url: URL, clientId: String, refreshToken: String, dpopKey: String, issuedAt: Date) throws -> URLRequest {
        let body: [String: String] = [
            "clientId": clientId,
            "grantType": "refresh_token",
            "refreshToken": refreshToken
        ]

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(try SAAWSDPoPProof.make(privateKeyPEM: dpopKey, url: url, issuedAt: issuedAt), forHTTPHeaderField: "DPoP")
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys, .withoutEscapingSlashes])
        return request
    }

    /// Sends `request` and blocks until it completes or `deadline` seconds pass, returning the body and HTTP status code.
    static func send(_ request: URLRequest,
                     configuration: URLSessionConfiguration = .ephemeral,
                     deadline: TimeInterval = SAAWSLoginRefreshRequest.timeout + 5) throws -> (Data, Int) {
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }

        let outcome = SAAsyncResultBox<(Data, Int)>()
        let semaphore = DispatchSemaphore(value: 0)

        let task = session.dataTask(with: request) { data, response, error in
            if let error {
                outcome.fail(SAAWSLoginRefreshError.requestFailed(error.localizedDescription))
            } else if let httpResponse = response as? HTTPURLResponse {
                outcome.succeed((data ?? Data(), httpResponse.statusCode))
            } else {
                outcome.fail(SAAWSLoginRefreshError.invalidResponse)
            }
            semaphore.signal()
        }
        task.resume()

        if semaphore.wait(timeout: .now() + deadline) == .timedOut {
            task.cancel()
            throw SAAWSLoginRefreshError.requestFailed(URLError(.timedOut).localizedDescription)
        }

        switch outcome.result {
        case .success(let value):
            return value
        case .failure(let error):
            throw error
        case nil:
            throw SAAWSLoginRefreshError.invalidResponse
        }
    }
}

// MARK: - Atomic File Replacement

/// Replaces a file atomically through a temporary file created in the same directory.
final class SAAtomicFileReplacement {

    private let destinationPath: String
    private let temporaryPath: String
    private var fileDescriptor: Int32

    /// Creates the temporary file next to `path`; throws `writeAccessRequired` when that is not possible.
    init(replacing path: String) throws {
        destinationPath = path
        temporaryPath = Self.temporaryPath(nextTo: path)
        fileDescriptor = open(temporaryPath, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o600)

        guard fileDescriptor >= 0 else {
            throw SAAWSLoginRefreshError.writeAccessRequired
        }
    }

    deinit {
        discard()
    }

    /// Writes `data` to the temporary file and moves it over the destination file.
    func commit(_ data: Data) throws {
        guard fileDescriptor >= 0 else {
            throw POSIXError(.EBADF)
        }

        let written = data.withUnsafeBytes { buffer -> Bool in
            guard let baseAddress = buffer.baseAddress else { return buffer.isEmpty }

            var offset = 0
            while offset < buffer.count {
                let result = write(fileDescriptor, baseAddress + offset, buffer.count - offset)
                if result < 0 {
                    if errno == EINTR { continue }
                    return false
                }
                offset += result
            }
            return true
        }

        guard written, fsync(fileDescriptor) == 0 else {
            let code = POSIXErrorCode(rawValue: errno) ?? .EIO
            discard()
            throw POSIXError(code)
        }

        close(fileDescriptor)
        fileDescriptor = -1

        guard rename(temporaryPath, destinationPath) == 0 else {
            let code = POSIXErrorCode(rawValue: errno) ?? .EIO
            unlink(temporaryPath)
            throw POSIXError(code)
        }

        let directoryDescriptor = open((destinationPath as NSString).deletingLastPathComponent, O_RDONLY | O_CLOEXEC)
        if directoryDescriptor >= 0 {
            _ = fsync(directoryDescriptor)
            close(directoryDescriptor)
        }
    }

    /// Removes the temporary file unless it has been committed.
    func discard() {
        guard fileDescriptor >= 0 else { return }

        close(fileDescriptor)
        fileDescriptor = -1
        unlink(temporaryPath)
    }

    /// True when a file can be created in `directory`.
    static func canCreateFiles(inDirectory directory: String) -> Bool {
        let probePath = temporaryPath(nextTo: (directory as NSString).appendingPathComponent("probe"))
        let descriptor = open(probePath, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { return false }

        close(descriptor)
        unlink(probePath)
        return true
    }

    private static func temporaryPath(nextTo path: String) -> String {
        let directory = (path as NSString).deletingLastPathComponent
        let name = (path as NSString).lastPathComponent
        return (directory as NSString).appendingPathComponent(".\(name).\(UUID().uuidString).tmp")
    }
}
