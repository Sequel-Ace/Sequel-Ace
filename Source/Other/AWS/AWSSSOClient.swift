//
//  AWSSSOClient.swift
//  Sequel Ace
//
//  Created for AWS IAM Identity Center (`aws sso login`) authentication support.
//  Copyright (c) 2024 Sequel-Ace. All rights reserved.
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

import Foundation
import CommonCrypto
import OSLog

/// Errors that can occur when resolving IAM Identity Center (`aws sso login`) credentials
@objc enum AWSSSOClientError: Int, Error, LocalizedError {
    case invalidProfile
    case tokenNotFound
    case tokenExpired
    case networkFailure
    case invalidResponse
    case accessDenied
    case requestTimeout

    var errorDescription: String? {
        switch self {
        case .invalidProfile:
            return NSLocalizedString("The profile is not configured for AWS IAM Identity Center", comment: "sso error")
        case .tokenNotFound:
            return NSLocalizedString("No cached AWS SSO session was found. Run `aws sso login` and try again.", comment: "sso error")
        case .tokenExpired:
            return NSLocalizedString("The AWS SSO session has expired. Run `aws sso login` and try again.", comment: "sso error")
        case .networkFailure:
            return NSLocalizedString("Network request to AWS IAM Identity Center failed", comment: "sso error")
        case .invalidResponse:
            return NSLocalizedString("Invalid response from AWS IAM Identity Center", comment: "sso error")
        case .accessDenied:
            return NSLocalizedString("Access denied by AWS IAM Identity Center", comment: "sso error")
        case .requestTimeout:
            return NSLocalizedString("AWS IAM Identity Center request timed out", comment: "sso error")
        }
    }
}

/// Resolves temporary AWS credentials for IAM Identity Center profiles.
///
/// Reads the bearer access token cached by `aws sso login` from `~/.aws/sso/cache`
/// and exchanges it for temporary credentials via the SSO Portal `GetRoleCredentials` API.
@objcMembers final class AWSSSOClient: NSObject {

    private static let log = OSLog(subsystem: "com.sequel-ace.sequel-ace", category: "AWSSSOClient")
    private static let requestTimeout: TimeInterval = 30
    private static let defaultDNSSuffix = "amazonaws.com"

    // MARK: - Resolution (Async)

    static func resolveCredentials(for profileCredentials: AWSCredentials) async throws -> AWSCredentials {
        guard profileCredentials.isSSOProfile,
              let accountID = profileCredentials.ssoAccountID, !accountID.isEmpty,
              let roleName = profileCredentials.ssoRoleName, !roleName.isEmpty else {
            throw AWSSSOClientError.invalidProfile
        }

        guard let cacheKey = tokenCacheKey(for: profileCredentials) else {
            throw AWSSSOClientError.invalidProfile
        }

        let cachePath = tokenCacheDirectory + "/" + cacheFileName(forKey: cacheKey)
        guard let contents = readFileContents(at: cachePath) else {
            log.error("SSO token cache file not found")
            throw AWSSSOClientError.tokenNotFound
        }

        let token = try parseAccessToken(fromJSON: Data(contents.utf8), now: Date())

        let region = resolvedRegion(for: profileCredentials, tokenRegion: token.region)
        guard !region.isEmpty else {
            throw AWSSSOClientError.invalidProfile
        }

        return try await fetchRoleCredentials(
            accountID: accountID,
            roleName: roleName,
            accessToken: token.accessToken,
            region: region
        )
    }

    // MARK: - Token Cache

    static var tokenCacheDirectory: String {
        AWSDirectoryBookmarkManager.shared.awsDirectoryBasePath + "/sso/cache"
    }

    /// The value hashed to locate the cached token: the sso-session name when present,
    /// otherwise the legacy `sso_start_url`.
    static func tokenCacheKey(for profileCredentials: AWSCredentials) -> String? {
        if let session = profileCredentials.ssoSession, !session.isEmpty {
            return session
        }
        if let startURL = profileCredentials.ssoStartURL, !startURL.isEmpty {
            return startURL
        }
        return nil
    }

    /// Token cache file name is the lowercase hex SHA-1 of the cache key plus `.json`.
    static func cacheFileName(forKey key: String) -> String {
        return sha1Hex(key) + ".json"
    }

    /// Parse the cached bearer token, treating tokens at or past `now` as expired.
    static func parseAccessToken(fromJSON data: Data, now: Date) throws -> (accessToken: String, region: String?) {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = root["accessToken"] as? String, !accessToken.isEmpty else {
            throw AWSSSOClientError.invalidResponse
        }

        if let expiresAt = parseISO8601Date(root["expiresAt"] as? String), expiresAt <= now {
            throw AWSSSOClientError.tokenExpired
        }

        return (accessToken, root["region"] as? String)
    }

    // MARK: - Portal Endpoint

    static func portalHost(forRegion region: String) -> String {
        let normalizedRegion = region.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let suffix = normalizedRegion.hasPrefix("cn-") ? "amazonaws.com.cn" : defaultDNSSuffix
        return "portal.sso.\(normalizedRegion).\(suffix)"
    }

    // MARK: - GetRoleCredentials

    private static func fetchRoleCredentials(
        accountID: String,
        roleName: String,
        accessToken: String,
        region: String
    ) async throws -> AWSCredentials {
        var components = URLComponents()
        components.scheme = "https"
        components.host = portalHost(forRegion: region)
        components.path = "/federation/credentials"
        components.queryItems = [
            URLQueryItem(name: "account_id", value: accountID),
            URLQueryItem(name: "role_name", value: roleName)
        ]

        guard let url = components.url else {
            throw AWSSSOClientError.invalidProfile
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = requestTimeout
        request.setValue(accessToken, forHTTPHeaderField: "x-amz-sso_bearer_token")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            log.error("SSO GetRoleCredentials request failed: \(error.localizedDescription)")
            throw AWSSSOClientError.networkFailure
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AWSSSOClientError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            return try parseRoleCredentials(fromJSON: data)
        case 401:
            throw AWSSSOClientError.tokenExpired
        case 403:
            throw AWSSSOClientError.accessDenied
        default:
            log.error("SSO GetRoleCredentials returned status \(httpResponse.statusCode)")
            throw AWSSSOClientError.invalidResponse
        }
    }

    /// Parse a `GetRoleCredentials` response body into temporary credentials.
    static func parseRoleCredentials(fromJSON data: Data) throws -> AWSCredentials {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let roleCredentials = root["roleCredentials"] as? [String: Any] else {
            throw AWSSSOClientError.invalidResponse
        }

        guard let accessKeyId = roleCredentials["accessKeyId"] as? String, !accessKeyId.isEmpty,
              let secretAccessKey = roleCredentials["secretAccessKey"] as? String, !secretAccessKey.isEmpty else {
            throw AWSSSOClientError.invalidResponse
        }

        let sessionToken = roleCredentials["sessionToken"] as? String
        let expiration = expirationDate(fromMilliseconds: roleCredentials["expiration"])

        return AWSCredentials(
            accessKeyId: accessKeyId,
            secretAccessKey: secretAccessKey,
            sessionToken: sessionToken,
            expiration: expiration
        )
    }

    // MARK: - Synchronous Wrapper (Obj-C)

    /// Synchronous version for Objective-C callers - runs async code on a background queue.
    ///
    /// - Warning: This method blocks the calling thread using a semaphore.
    ///   **Do not call from the main thread** as it may cause UI freezes or deadlocks.
    @objc(resolveCredentialsForProfile:error:)
    static func resolveCredentialsObjC(
        for profileCredentials: AWSCredentials,
        error errorPointer: NSErrorPointer
    ) -> AWSCredentials? {
        if Thread.isMainThread {
            os_log(.error, log: log, "AWSSSOClient.resolveCredentials called from main thread - this may cause UI freezes.")
            assertionFailure("AWSSSOClient.resolveCredentials should not be called from the main thread")
        }

        var result: AWSCredentials?
        var asyncError: Error?
        let semaphore = DispatchSemaphore(value: 0)

        DispatchQueue.global(qos: .userInitiated).async {
            Task {
                do {
                    result = try await resolveCredentials(for: profileCredentials)
                } catch {
                    asyncError = error
                }
                semaphore.signal()
            }
        }

        let waitResult = semaphore.wait(timeout: .now() + requestTimeout + 5)

        if waitResult == .timedOut {
            errorPointer?.pointee = nsError(for: .requestTimeout)
            return nil
        }

        if let asyncError = asyncError {
            if let ssoError = asyncError as? AWSSSOClientError {
                errorPointer?.pointee = nsError(for: ssoError)
            } else {
                errorPointer?.pointee = asyncError as NSError
            }
            return nil
        }

        return result
    }

    private static func nsError(for error: AWSSSOClientError) -> NSError {
        NSError(
            domain: "AWSSSOClientErrorDomain",
            code: error.rawValue,
            userInfo: [NSLocalizedDescriptionKey: error.localizedDescription]
        )
    }

    // MARK: - File Reading

    private static func readFileContents(at path: String) -> String? {
        let bookmarkManager = AWSDirectoryBookmarkManager.shared

        if bookmarkManager.isAWSDirectoryAuthorized {
            return bookmarkManager.readAWSFileContents(at: path)
        }

        guard FileManager.default.fileExists(atPath: path) else {
            return nil
        }

        return try? String(contentsOfFile: path, encoding: .utf8)
    }

    // MARK: - Helpers

    private static func resolvedRegion(for profileCredentials: AWSCredentials, tokenRegion: String?) -> String {
        if let ssoRegion = profileCredentials.ssoRegion, !ssoRegion.isEmpty {
            return ssoRegion.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        return (tokenRegion ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func expirationDate(fromMilliseconds value: Any?) -> Date? {
        let milliseconds: Double
        switch value {
        case let number as NSNumber:
            milliseconds = number.doubleValue
        case let string as String:
            guard let parsed = Double(string) else { return nil }
            milliseconds = parsed
        default:
            return nil
        }

        guard milliseconds > 0 else { return nil }
        return Date(timeIntervalSince1970: milliseconds / 1000)
    }

    private static func parseISO8601Date(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }

        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    private static func sha1Hex(_ string: String) -> String {
        let data = Data(string.utf8)
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        data.withUnsafeBytes { ptr in
            _ = CC_SHA1(ptr.baseAddress, CC_LONG(data.count), &digest)
        }
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
