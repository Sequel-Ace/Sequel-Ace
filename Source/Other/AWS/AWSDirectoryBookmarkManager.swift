//
//  AWSDirectoryBookmarkManager.swift
//  Sequel Ace
//
//  Created for sandbox-compatible AWS credentials access.
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
import OSLog

/// Manages access to the AWS credentials directory (~/.aws) via security-scoped bookmarks
/// for sandbox-compatible AWS IAM authentication.
@objcMembers final class AWSDirectoryBookmarkManager: NSObject {

    static let shared = AWSDirectoryBookmarkManager()

    private static let log = OSLog(subsystem: "com.sequel-ace.sequel-ace", category: "AWSDirectoryBookmark")

    /// The bookmark creation options for security-scoped access
    private let bookmarkCreationOptions: URL.BookmarkCreationOptions = [
        .withSecurityScope,
        .securityScopeAllowOnlyReadAccess
    ]
    private let stateLock = NSLock()

    /// Track if we're currently accessing the AWS directory
    private var isAccessingAWSDirectory = false
    private var accessReferenceCount = 0

    /// The resolved URL for the AWS directory (if access has been started)
    private var resolvedAWSDirectoryURL: URL?

    override private init() {
        super.init()
    }

    // MARK: - Public API

    /// The expected path to the AWS credentials directory
    static var awsDirectoryPath: String {
        return NSHomeDirectory() + "/.aws"
    }

    /// The active AWS directory path when bookmark access is active.
    var awsDirectoryBasePath: String {
        if let resolvedPath = currentResolvedAWSDirectoryURL()?.path, resolvedPath.isNotEmpty {
            return resolvedPath
        }
        return Self.awsDirectoryPath
    }

    // MARK: - Debug/Testing Options

    // Uncomment the following lines to simulate sandboxed environment for testing:
    // private let simulateSandboxedEnvironment = true
    // private var authorizedThisSession = false

    /// Check if the AWS directory bookmark exists and is valid
    var isAWSDirectoryAuthorized: Bool {
        // DEBUG: Uncomment to simulate sandboxed environment for testing UI
        // if simulateSandboxedEnvironment && !authorizedThisSession {
        //     os_log(.info, log: Self.log, "Simulating sandboxed environment - requires authorization")
        //     return false
        // }

        // First check if we have a bookmark for the AWS directory.
        // Validate that the bookmark still resolves and grants access.
        if hasAWSDirectoryBookmark() {
            if startAccessingAWSDirectory() {
                defer { stopAccessingAWSDirectory() }
                os_log(.info, log: Self.log, "AWS directory authorized via bookmark")
                return true
            }

            os_log(.error, log: Self.log, "AWS bookmark exists but no longer grants access; revoking stale bookmark")
            revokeAllAWSDirectoryBookmarks()
        }

        // Also check if the directory is directly accessible (non-sandboxed builds)
        let awsPath = Self.awsDirectoryPath
        if FileManager.default.isReadableFile(atPath: awsPath + "/credentials") {
            os_log(.info, log: Self.log, "AWS directory is directly readable (non-sandboxed or already authorized)")
            return true
        }

        os_log(.info, log: Self.log, "AWS directory not authorized")
        return false
    }

    /// Check if we have a bookmark specifically for the AWS directory
    private func hasAWSDirectoryBookmark() -> Bool {
        let bookmarkManager = SecureBookmarkManager.sharedInstance

        for bookmarkDict in bookmarkManager.bookmarks {
            for key in bookmarkDict.keys {
                if isAWSDirectoryBookmarkKey(key) {
                    os_log(.info, log: Self.log, "Found AWS directory bookmark: %{public}@", key)
                    return true
                }
            }
        }
        return false
    }

    private func revokeAllAWSDirectoryBookmarks() {
        let bookmarkManager = SecureBookmarkManager.sharedInstance

        for bookmarkDict in bookmarkManager.bookmarks {
            for key in bookmarkDict.keys where isAWSDirectoryBookmarkKey(key) {
                _ = bookmarkManager.revokeBookmark(filename: key)
            }
        }
    }

    /// Start accessing the AWS directory via security-scoped bookmark
    /// Returns true if access was successfully started
    @discardableResult
    func startAccessingAWSDirectory() -> Bool {
        stateLock.lock()
        if isAccessingAWSDirectory {
            accessReferenceCount += 1
            let activeReferences = accessReferenceCount
            stateLock.unlock()
            os_log(.debug, log: Self.log, "Already accessing AWS directory (%{public}d active references)", activeReferences)
            return true
        }

        let bookmarkManager = SecureBookmarkManager.sharedInstance

        // Look for the AWS directory bookmark
        for bookmarkDict in bookmarkManager.bookmarks {
            for (key, _) in bookmarkDict {
                if isAWSDirectoryBookmarkKey(key) {
                    // Try to get the resolved URL via the bookmark manager
                    if let resolvedURL = bookmarkManager.bookmarkFor(filename: key) {
                        resolvedAWSDirectoryURL = resolvedURL
                        isAccessingAWSDirectory = true
                        accessReferenceCount = 1
                        stateLock.unlock()
                        os_log(.info, log: Self.log, "Started accessing AWS directory via bookmark")
                        return true
                    }
                }
            }
        }

        // Check if directly accessible (non-sandboxed)
        let awsPath = Self.awsDirectoryPath
        if FileManager.default.isReadableFile(atPath: awsPath + "/credentials") {
            resolvedAWSDirectoryURL = nil
            isAccessingAWSDirectory = true
            accessReferenceCount = 1
            stateLock.unlock()
            os_log(.info, log: Self.log, "AWS directory directly accessible")
            return true
        }

        stateLock.unlock()
        os_log(.error, log: Self.log, "Failed to start accessing AWS directory")
        return false
    }

    /// Stop accessing the AWS directory
    func stopAccessingAWSDirectory() {
        var urlToStop: URL?
        var remainingReferences = 0

        stateLock.lock()
        if accessReferenceCount > 1 {
            accessReferenceCount -= 1
            remainingReferences = accessReferenceCount
            stateLock.unlock()
            os_log(.debug, log: Self.log, "Retaining AWS directory access (%{public}d active references)", remainingReferences)
            return
        }

        if accessReferenceCount == 1 {
            urlToStop = resolvedAWSDirectoryURL
        }

        resolvedAWSDirectoryURL = nil
        accessReferenceCount = 0
        isAccessingAWSDirectory = false
        stateLock.unlock()

        if let url = urlToStop {
            url.stopAccessingSecurityScopedResource()
        }
        os_log(.debug, log: Self.log, "Stopped accessing AWS directory")
    }

    /// Add a bookmark for the AWS directory from a user-selected URL
    /// Call this after the user selects the ~/.aws folder via NSOpenPanel
    func addAWSDirectoryBookmark(from url: URL) -> Bool {
        let bookmarkManager = SecureBookmarkManager.sharedInstance

        // Create bookmark with security scope
        let success = bookmarkManager.addBookmarkFor(
            url: url,
            options: UInt(bookmarkCreationOptions.rawValue),
            isForStaleBookmark: false,
            isForKnownHostsFile: false
        )

        if success {
            os_log(.info, log: Self.log, "Successfully added AWS directory bookmark for: %{public}@", url.path)
            // DEBUG: Uncomment if using simulateSandboxedEnvironment for testing
            // authorizedThisSession = true

            // Validate that the bookmark can be opened, then release.
            if startAccessingAWSDirectory() {
                stopAccessingAWSDirectory()
            }
        } else {
            os_log(.error, log: Self.log, "Failed to add AWS directory bookmark")
        }

        return success
    }

    /// Revoke the AWS directory bookmark
    func revokeAWSDirectoryBookmark() -> Bool {
        stopAllAccessingAWSDirectory()

        let bookmarkManager = SecureBookmarkManager.sharedInstance

        // Find and revoke the AWS directory bookmark
        for bookmarkDict in bookmarkManager.bookmarks {
            for key in bookmarkDict.keys {
                if isAWSDirectoryBookmarkKey(key) {
                    if bookmarkManager.revokeBookmark(filename: key) {
                        os_log(.info, log: Self.log, "Revoked AWS directory bookmark")
                        return true
                    }
                }
            }
        }

        return false
    }

    private func isAWSDirectoryBookmarkKey(_ key: String) -> Bool {
        let decodedKey = key.removingPercentEncoding ?? key
        let path: String

        if let url = URL(string: decodedKey), url.isFileURL {
            path = url.path
        } else {
            path = decodedKey
        }

        let normalizedPath = path.replacingOccurrences(of: "\\", with: "/")
        return normalizedPath.hasSuffix("/.aws") || URL(fileURLWithPath: normalizedPath).lastPathComponent == ".aws"
    }

    // MARK: - File Reading

    /// Read contents of a file within the AWS directory with security-scoped access
    /// Returns nil if the file cannot be read
    func readAWSFileContents(at path: String) -> String? {
        // Ensure we have access
        guard startAccessingAWSDirectory() else {
            os_log(.error, log: Self.log, "Cannot read AWS file: no access to AWS directory")
            return nil
        }
        defer { stopAccessingAWSDirectory() }

        let resolvedPath = resolvePathForCurrentAWSDirectory(path)

        // Try to read the file
        do {
            let contents = try String(contentsOfFile: resolvedPath, encoding: .utf8)
            os_log(.debug, log: Self.log, "Successfully read AWS file: %{public}@", resolvedPath)
            return contents
        } catch {
            os_log(.error, log: Self.log, "Failed to read AWS file %{public}@: %{public}@", resolvedPath, error.localizedDescription)
            return nil
        }
    }

    /// Check if a file exists within the AWS directory
    func awsFileExists(at path: String) -> Bool {
        // Ensure we have access first
        guard startAccessingAWSDirectory() else {
            return false
        }
        defer { stopAccessingAWSDirectory() }

        return FileManager.default.fileExists(atPath: resolvePathForCurrentAWSDirectory(path))
    }

    private func resolvePathForCurrentAWSDirectory(_ path: String) -> String {
        guard let resolvedURL = currentResolvedAWSDirectoryURL() else {
            return path
        }

        let normalizedInputPath = URL(fileURLWithPath: path).standardized.path
        let normalizedDefaultAWSPath = URL(fileURLWithPath: Self.awsDirectoryPath).standardized.path

        if normalizedInputPath == normalizedDefaultAWSPath {
            return resolvedURL.path
        }

        let defaultPrefix = normalizedDefaultAWSPath + "/"
        if normalizedInputPath.hasPrefix(defaultPrefix) {
            let relativeComponent = String(normalizedInputPath.dropFirst(defaultPrefix.count))
            return resolvedURL.appendingPathComponent(relativeComponent).path
        }

        return path
    }

    private func currentResolvedAWSDirectoryURL() -> URL? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return resolvedAWSDirectoryURL
    }

    private func stopAllAccessingAWSDirectory() {
        while true {
            stateLock.lock()
            let hasActiveReferences = accessReferenceCount > 0
            stateLock.unlock()

            if !hasActiveReferences {
                return
            }

            stopAccessingAWSDirectory()
        }
    }
}

// MARK: - Notification for Authorization Changes

extension Notification.Name {
    static let AWSDirectoryAuthorizationChanged = Notification.Name("AWSDirectoryAuthorizationChanged")
}
