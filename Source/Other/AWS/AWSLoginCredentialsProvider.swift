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
            return NSLocalizedString("No cached AWS console sign-in session was found.", comment: "aws login error")
        case .sessionExpired:
            return NSLocalizedString("Your AWS console sign-in session has ended.", comment: "aws login error: the sign-in session can no longer be renewed")
        case .invalidCacheContents:
            return NSLocalizedString("The cached AWS console sign-in session could not be read", comment: "aws login error")
        }
    }
}

/// Resolves temporary AWS credentials cached by the `aws login` command.
///
/// `aws login` writes temporary credentials to `~/.aws/login/cache/<sha256(login_session)>.json`.
/// Credentials that expire within `SAAWSLoginSession.refreshWindow` are renewed through AWS
/// Sign-In and the renewed session is written back to the cache file.
@objcMembers final class AWSLoginCredentialsProvider: NSObject {

    private static let log = OSLog(subsystem: "com.sequel-ace.sequel-ace", category: "AWSLoginAuth")
    private static let refreshLock = NSLock()

    /// Cached credentials with more than this many seconds left are used when renewal fails.
    private static let minimumFallbackLifetime: TimeInterval = 60

    /// Sends a renewal request and returns the response body and HTTP status code.
    @nonobjc static var refreshTransport: (URLRequest) throws -> (Data, Int) = SAAWSLoginRefreshRequest.send

    /// Resolve temporary credentials for a profile configured with `login_session`,
    /// renewing them when they are about to expire.
    static func resolveCredentials(for profileCredentials: AWSCredentials) throws -> AWSCredentials {
        guard let loginSession = profileCredentials.loginSession, !loginSession.isEmpty else {
            throw AWSLoginAuthError.invalidProfile
        }

        let cachePath = cacheFilePath(forLoginSession: loginSession)
        let session = try loadSession { readFileContents(at: cachePath).map { Data($0.utf8) } }

        let now = Date()
        guard session.needsRefresh(at: now) else {
            return try session.credentials(at: now)
        }

        refreshLock.lock()
        defer { refreshLock.unlock() }

        return try withCacheFileAccess(cachePath) { path in
            try renewCredentials(cachedAt: path, fallbackRegion: profileCredentials.region)
        }
    }

    /// True when `profile` resolves through console sign-in, matching the precedence in `AWSIAMAuthManager`.
    static func resolvesThroughConsoleSignIn(_ profile: AWSCredentials) -> Bool {
        !profile.isSSOProfile && profile.isLoginProfile && !profile.isValid && !profile.requiresRoleAssumption
    }

    /// True when `profile` resolves through console sign-in and its cache directory exists but cannot be written.
    static func needsWriteAccessGrant(for profile: AWSCredentials) -> Bool {
        guard resolvesThroughConsoleSignIn(profile) else { return false }

        return withCacheFileAccess(cacheDirectory) { directory in
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: directory, isDirectory: &isDirectory), isDirectory.boolValue else {
                return false
            }
            return !SAAtomicFileReplacement.canCreateFiles(inDirectory: directory)
        }
    }

    // MARK: - Renewal

    /// Renews the credentials cached at `path` unless they were renewed in the meantime. When renewal
    /// fails, returns credentials another process wrote to `path` meanwhile, or the cached credentials
    /// while they remain usable.
    private static func renewCredentials(cachedAt path: String, fallbackRegion: String?) throws -> AWSCredentials {
        let session = try loadSession { FileManager.default.contents(atPath: path) }

        guard session.needsRefresh(at: Date()) else {
            return try session.credentials(at: Date())
        }

        do {
            return try refresh(session, cachedAt: path, fallbackRegion: fallbackRegion)
        } catch {
            log.error("Console sign-in renewal failed: \(error.localizedDescription)", privacy: .visible)

            let now = Date()
            if let onDisk = try? loadSession({ FileManager.default.contents(atPath: path) }),
               !onDisk.needsRefresh(at: now),
               let onDiskCredentials = try? onDisk.credentials(at: now) {
                return onDiskCredentials
            }

            if let remaining = session.remainingLifetime(at: now), remaining > minimumFallbackLifetime {
                return try session.credentials(at: now)
            }
            throw error
        }
    }

    /// Exchanges the session's refresh token for new credentials and writes the renewed session to `path`.
    private static func refresh(_ session: SAAWSLoginSession, cachedAt path: String, fallbackRegion: String?) throws -> AWSCredentials {
        guard let refreshToken = session.refreshToken,
              let clientId = session.clientId,
              let dpopKey = session.dpopKey else {
            throw AWSLoginAuthError.sessionExpired
        }

        let normalizedFallbackRegion = fallbackRegion?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let region = session.issuingRegion ?? normalizedFallbackRegion,
              let url = SAAWSSignInEndpoint.tokenURL(forRegion: region) else {
            throw SAAWSLoginRefreshError.regionUnavailable
        }

        let replacement = try SAAtomicFileReplacement(replacing: path)
        defer { replacement.discard() }

        let request = try SAAWSLoginRefreshRequest.make(
            url: url,
            clientId: clientId,
            refreshToken: refreshToken,
            dpopKey: dpopKey,
            issuedAt: Date()
        )
        let (data, statusCode) = try refreshTransport(request)
        let response = try SAAWSLoginTokenResponse.parse(data: data, statusCode: statusCode)

        let renewed = session.applying(response, issuedAt: Date())
        let credentials = try renewed.credentials(at: Date())

        if let onDisk = try? SAAWSLoginSession(jsonData: FileManager.default.contents(atPath: path) ?? Data()),
           onDisk.refreshToken != refreshToken {
            log.info("Console sign-in cache changed during renewal; leaving it unchanged")

            let now = Date()
            guard !onDisk.needsRefresh(at: now), let onDiskCredentials = try? onDisk.credentials(at: now) else {
                return credentials
            }
            return onDiskCredentials
        }

        do {
            try replacement.commit(renewed.jsonData())
            log.info("Renewed console sign-in credentials")
        } catch {
            log.error("Could not write the renewed console sign-in session: \(error.localizedDescription)", privacy: .visible)
        }

        return credentials
    }

    /// Parses the cache file returned by `read`, reading it a second time when the first read is incomplete.
    private static func loadSession(_ read: () -> Data?) throws -> SAAWSLoginSession {
        guard let data = read() else {
            log.error("Console sign-in cache file not found at expected path")
            throw AWSLoginAuthError.cacheNotFound
        }

        if let session = try? SAAWSLoginSession(jsonData: data) {
            return session
        }

        Thread.sleep(forTimeInterval: 0.1)

        guard let retried = read() else {
            throw AWSLoginAuthError.cacheNotFound
        }
        return try SAAWSLoginSession(jsonData: retried)
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
        try SAAWSLoginSession(jsonData: data).credentials(at: now)
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

    /// Runs `body` with `path` translated into the authorized AWS directory while access to it is held.
    private static func withCacheFileAccess<T>(_ path: String, _ body: (String) throws -> T) rethrows -> T {
        let bookmarkManager = AWSDirectoryBookmarkManager.shared

        guard bookmarkManager.startAccessingAWSDirectory() else {
            return try body(path)
        }
        defer { bookmarkManager.stopAccessingAWSDirectory() }

        return try body(bookmarkManager.resolvedAWSPath(for: path))
    }

    // MARK: - Helpers

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
