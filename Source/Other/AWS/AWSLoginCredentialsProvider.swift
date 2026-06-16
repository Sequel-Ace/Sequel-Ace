//
//  AWSLoginCredentialsProvider.swift
//  Sequel Ace
//
//  Created for AWS console sign-in (`aws login`) authentication support.
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

/// Errors that can occur when reading console sign-in (`aws login`) credentials
@objc enum AWSLoginAuthError: Int, Error, LocalizedError {
    case invalidProfile
    case cacheNotFound
    case sessionExpired
    case invalidCacheContents

    var errorDescription: String? {
        switch self {
        case .invalidProfile:
            return NSLocalizedString("The profile is not configured for AWS console sign-in", comment: "aws login error")
        case .cacheNotFound:
            return NSLocalizedString("No cached AWS console sign-in session was found. Run `aws login` and try again.", comment: "aws login error")
        case .sessionExpired:
            return NSLocalizedString("The cached AWS console sign-in credentials have expired. They refresh about every 15 minutes. Run `aws login` and reconnect.", comment: "aws login error")
        case .invalidCacheContents:
            return NSLocalizedString("The cached AWS console sign-in session could not be read", comment: "aws login error")
        }
    }
}

/// Resolves temporary AWS credentials cached by the `aws login` command.
///
/// `aws login` writes ready-to-use temporary credentials to
/// `~/.aws/login/cache/<sha256(login_session)>.json`, so no network call is required.
@objcMembers final class AWSLoginCredentialsProvider: NSObject {

    private static let log = OSLog(subsystem: "com.sequel-ace.sequel-ace", category: "AWSLoginAuth")

    /// Resolve temporary credentials for a profile configured with `login_session`.
    static func resolveCredentials(for profileCredentials: AWSCredentials) throws -> AWSCredentials {
        guard let loginSession = profileCredentials.loginSession, !loginSession.isEmpty else {
            throw AWSLoginAuthError.invalidProfile
        }

        let cachePath = cacheFilePath(forLoginSession: loginSession)

        guard let contents = readFileContents(at: cachePath) else {
            log.error("Console sign-in cache file not found at expected path")
            throw AWSLoginAuthError.cacheNotFound
        }

        return try parseCachedCredentials(fromJSON: Data(contents.utf8), now: Date())
    }

    // MARK: - Cache Location

    /// Directory holding `aws login` cached sessions, honoring `AWS_LOGIN_CACHE_DIRECTORY`.
    static var cacheDirectory: String {
        if let override = ProcessInfo.processInfo.environment["AWS_LOGIN_CACHE_DIRECTORY"], !override.isEmpty {
            return override
        }
        return AWSDirectoryBookmarkManager.shared.awsDirectoryBasePath + "/login/cache"
    }

    /// Path to the cache file for a given `login_session` value.
    static func cacheFilePath(forLoginSession loginSession: String) -> String {
        return cacheDirectory + "/" + cacheFileName(forLoginSession: loginSession)
    }

    /// Cache file name is the lowercase hex SHA-256 of the `login_session` value plus `.json`.
    static func cacheFileName(forLoginSession loginSession: String) -> String {
        return sha256Hex(loginSession) + ".json"
    }

    // MARK: - Cache Parsing

    /// Parse cached console sign-in credentials, treating sessions at or past `now` as expired.
    static func parseCachedCredentials(fromJSON data: Data, now: Date) throws -> AWSCredentials {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = root["accessToken"] as? [String: Any] else {
            throw AWSLoginAuthError.invalidCacheContents
        }

        guard let accessKeyId = accessToken["accessKeyId"] as? String, !accessKeyId.isEmpty,
              let secretAccessKey = accessToken["secretAccessKey"] as? String, !secretAccessKey.isEmpty else {
            throw AWSLoginAuthError.invalidCacheContents
        }

        let sessionToken = accessToken["sessionToken"] as? String
        let expiration = parseISO8601Date(accessToken["expiresAt"] as? String)

        if let expiration = expiration, expiration <= now {
            throw AWSLoginAuthError.sessionExpired
        }

        return AWSCredentials(
            accessKeyId: accessKeyId,
            secretAccessKey: secretAccessKey,
            sessionToken: sessionToken,
            expiration: expiration
        )
    }

    // MARK: - File Reading

    /// Read a file under the AWS directory, using security-scoped access when authorized.
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

    /// Parse an ISO-8601 timestamp, accepting both fractional and whole-second forms.
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

    /// Lowercase hex SHA-256 of the string.
    private static func sha256Hex(_ string: String) -> String {
        let data = Data(string.utf8)
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { ptr in
            _ = CC_SHA256(ptr.baseAddress, CC_LONG(data.count), &digest)
        }
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Objective-C Compatibility

extension AWSLoginCredentialsProvider {

    /// Objective-C compatible method that returns nil on error
    @objc(resolveCredentialsForProfile:error:)
    static func resolveCredentialsObjC(
        for profileCredentials: AWSCredentials,
        error errorPointer: NSErrorPointer
    ) -> AWSCredentials? {
        do {
            return try resolveCredentials(for: profileCredentials)
        } catch let loginError as AWSLoginAuthError {
            errorPointer?.pointee = NSError(
                domain: "AWSLoginAuthErrorDomain",
                code: loginError.rawValue,
                userInfo: [NSLocalizedDescriptionKey: loginError.localizedDescription]
            )
            return nil
        } catch let otherError {
            errorPointer?.pointee = otherError as NSError
            return nil
        }
    }
}
