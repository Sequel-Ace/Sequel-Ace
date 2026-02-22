//
//  AWSCredentials.swift
//  Sequel Ace
//
//  Created for AWS IAM authentication support.
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

/// Errors that can occur when loading or validating AWS credentials
@objc enum AWSCredentialsError: Int, Error, LocalizedError {
    case profileNotFound
    case missingCredentials
    case invalidCredentials
    case fileReadError
    case directoryAccessFailed

    var errorDescription: String? {
        switch self {
        case .profileNotFound:
            return NSLocalizedString("AWS profile not found", comment: "AWS credentials error")
        case .missingCredentials:
            return NSLocalizedString("AWS credentials are missing required fields (access key ID or secret access key)", comment: "AWS credentials error")
        case .invalidCredentials:
            return NSLocalizedString("Invalid AWS credentials", comment: "AWS credentials error")
        case .fileReadError:
            return NSLocalizedString("Failed to read AWS credentials file", comment: "AWS credentials error")
        case .directoryAccessFailed:
            return NSLocalizedString("Failed to access the AWS credentials directory", comment: "AWS credentials error")
        }
    }
}

/// Represents AWS credentials loaded from a profile or provided manually
@objc final class AWSCredentials: NSObject {

    // MARK: - Properties

    @objc let accessKeyId: String
    @objc let secretAccessKey: String
    @objc let sessionToken: String?
    @objc let profileName: String?

    // Profile configuration for role assumption
    @objc let roleArn: String?
    @objc let mfaSerial: String?
    @objc let sourceProfile: String?
    @objc let region: String?

    private static let log = OSLog(subsystem: "com.sequel-ace.sequel-ace", category: "AWSCredentials")

    // MARK: - Initialization

    /// Initialize with explicit credentials
    @objc init(accessKeyId: String, secretAccessKey: String, sessionToken: String? = nil) {
        self.accessKeyId = accessKeyId
        self.secretAccessKey = secretAccessKey
        self.sessionToken = sessionToken
        self.profileName = nil
        self.roleArn = nil
        self.mfaSerial = nil
        self.sourceProfile = nil
        self.region = nil
        super.init()
    }

    /// Initialize from an AWS profile
    @objc init(profile profileName: String?) throws {
        let effectiveProfile = profileName ?? "default"
        self.profileName = effectiveProfile

        let config = try Self.loadProfileConfiguration(for: effectiveProfile)

        self.accessKeyId = config["aws_access_key_id"] ?? ""
        self.secretAccessKey = config["aws_secret_access_key"] ?? ""
        self.sessionToken = config["aws_session_token"]
        self.roleArn = config["role_arn"]
        self.mfaSerial = config["mfa_serial"]
        self.sourceProfile = config["source_profile"]
        self.region = config["region"]

        super.init()

        guard isValid else {
            throw AWSCredentialsError.missingCredentials
        }
    }

    // MARK: - Validation

    @objc var isValid: Bool {
        accessKeyId.isNotEmpty && secretAccessKey.isNotEmpty
    }

    @objc var requiresMFA: Bool {
        mfaSerial?.isEmpty == false
    }

    @objc var requiresRoleAssumption: Bool {
        roleArn?.isEmpty == false
    }

    // MARK: - File Paths

    @objc static var credentialsFilePath: String {
        if let envPath = ProcessInfo.processInfo.environment["AWS_SHARED_CREDENTIALS_FILE"],
           envPath.isNotEmpty {
            return envPath
        }
        return AWSDirectoryBookmarkManager.shared.awsDirectoryBasePath + "/credentials"
    }

    @objc static var configFilePath: String {
        if let envPath = ProcessInfo.processInfo.environment["AWS_CONFIG_FILE"],
           envPath.isNotEmpty {
            return envPath
        }
        return AWSDirectoryBookmarkManager.shared.awsDirectoryBasePath + "/config"
    }

    @objc static var credentialsFileExists: Bool {
        // First check if we have bookmark access
        let bookmarkManager = AWSDirectoryBookmarkManager.shared
        if bookmarkManager.isAWSDirectoryAuthorized {
            return bookmarkManager.awsFileExists(at: credentialsFilePath)
        }
        // Fall back to direct access check (works in non-sandboxed builds)
        return FileManager.default.fileExists(atPath: credentialsFilePath)
    }

    /// Check if AWS directory access is authorized (for sandbox support)
    @objc static var isAWSDirectoryAuthorized: Bool {
        AWSDirectoryBookmarkManager.shared.isAWSDirectoryAuthorized
    }

    // MARK: - Profile Loading

    /// Returns list of available AWS profiles sorted alphabetically with "default" first
    /// Returns empty array if AWS directory is not authorized (sandboxed apps)
    @objc static func availableProfiles() -> [String] {
        // Ensure we have access to the AWS directory
        let bookmarkManager = AWSDirectoryBookmarkManager.shared
        guard bookmarkManager.isAWSDirectoryAuthorized else {
            os_log(.info, log: log, "AWS directory not authorized, returning empty profiles")
            return []
        }

        // Start accessing the directory
        guard bookmarkManager.startAccessingAWSDirectory() else {
            os_log(.error, log: log, "Failed to start accessing AWS directory while loading profiles")
            return []
        }

        var profiles = Set<String>()

        addProfiles(from: credentialsFilePath, to: &profiles, isConfigFile: false)
        addProfiles(from: configFilePath, to: &profiles, isConfigFile: true)

        var sorted = profiles.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

        if let defaultIndex = sorted.firstIndex(of: "default") {
            sorted.remove(at: defaultIndex)
            sorted.insert("default", at: 0)
        }

        return sorted
    }

    /// Load configuration for a specific profile
    /// - Parameters:
    ///   - profileName: The name of the profile to load
    ///   - visited: Set of already visited profiles to detect cycles (used internally)
    private static func loadProfileConfiguration(for profileName: String, visited: Set<String> = []) throws -> [String: String] {
        // Guard against cyclical source_profile chains
        if visited.contains(profileName) {
            os_log(.error, log: log, "Cyclical source_profile detected for profile: %{public}@", profileName)
            throw AWSCredentialsError.invalidCredentials
        }
        var visited = visited
        visited.insert(profileName)

        var result = [String: String]()
        var foundProfile = false

        let bookmarkManager = AWSDirectoryBookmarkManager.shared
        let environment = ProcessInfo.processInfo.environment
        let usesDefaultCredentialsPath = environment["AWS_SHARED_CREDENTIALS_FILE"]?.isNotEmpty != true
        let usesDefaultConfigPath = environment["AWS_CONFIG_FILE"]?.isNotEmpty != true

        // Default ~/.aws paths require sandbox bookmark access. Explicit file
        // overrides can be read directly and do not require AWS directory access.
        if usesDefaultCredentialsPath || usesDefaultConfigPath {
            guard bookmarkManager.startAccessingAWSDirectory() else {
                os_log(.error, log: log, "Failed to access AWS directory while loading profile: %{public}@", profileName)
                throw AWSCredentialsError.directoryAccessFailed
            }
        }

        // Load from ~/.aws/credentials
        if let contents = readAWSFileContents(at: credentialsFilePath) {
            if let creds = parseAWSFile(contents, forProfile: profileName, isConfigFile: false) {
                result.merge(creds) { current, _ in current }
                foundProfile = true
            }
        }

        // Load from ~/.aws/config
        if let contents = readAWSFileContents(at: configFilePath) {
            if let config = parseAWSFile(contents, forProfile: profileName, isConfigFile: true) {
                // Merge config, credentials take precedence
                for (key, value) in config where result[key] == nil {
                    result[key] = value
                }
                foundProfile = true
            }
        }

        // If profile has source_profile, load credentials from that
        if let sourceProfile = result["source_profile"], result["aws_access_key_id"] == nil {
            let sourceConfig = try loadProfileConfiguration(for: sourceProfile, visited: visited)
            if let accessKey = sourceConfig["aws_access_key_id"] {
                result["aws_access_key_id"] = accessKey
            }
            if let secretKey = sourceConfig["aws_secret_access_key"] {
                result["aws_secret_access_key"] = secretKey
            }
            if result["aws_session_token"] == nil, let token = sourceConfig["aws_session_token"] {
                result["aws_session_token"] = token
            }
        }

        guard foundProfile else {
            throw AWSCredentialsError.profileNotFound
        }

        return result
    }

    /// Read AWS file contents using security-scoped access when needed
    private static func readAWSFileContents(at path: String) -> String? {
        let bookmarkManager = AWSDirectoryBookmarkManager.shared

        // Try via bookmark manager first (sandbox-compatible)
        if bookmarkManager.isAWSDirectoryAuthorized {
            return bookmarkManager.readAWSFileContents(at: path)
        }

        // Fall back to direct access (non-sandboxed builds)
        guard FileManager.default.fileExists(atPath: path) else {
            return nil
        }

        return try? String(contentsOfFile: path, encoding: .utf8)
    }

    /// Parse an AWS credentials or config file for a specific profile
    private static func parseAWSFile(_ contents: String, forProfile profileName: String, isConfigFile: Bool) -> [String: String]? {
        var result = [String: String]()
        var currentProfile: String?
        var foundProfile = false

        // In config file, profile sections are named "profile xyz" except for "default"
        let targetSection = profileName
        let targetSectionAlt: String? = isConfigFile && profileName != "default"
            ? "profile \(profileName)"
            : nil

        let lines = contents.components(separatedBy: .newlines)

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            // Skip empty lines and comments
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix(";") {
                continue
            }

            // Check for profile header [profile_name]
            if line.hasPrefix("[") && line.hasSuffix("]") {
                currentProfile = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)

                let isTargetProfile = currentProfile == targetSection ||
                    (targetSectionAlt != nil && currentProfile == targetSectionAlt)

                if isTargetProfile {
                    foundProfile = true
                } else if foundProfile {
                    // We've moved past our target profile
                    break
                }
                continue
            }

            // Parse key=value pairs within the target profile
            if foundProfile, let equalIndex = line.firstIndex(of: "=") {
                let key = String(line[..<equalIndex]).trimmingCharacters(in: .whitespaces)
                let value = String(line[line.index(after: equalIndex)...]).trimmingCharacters(in: .whitespaces)

                if key.isNotEmpty && value.isNotEmpty {
                    result[key] = value
                }
            }
        }

        return foundProfile ? result : nil
    }

    /// Add profile names from a file to the set
    private static func addProfiles(from filePath: String, to profiles: inout Set<String>, isConfigFile: Bool) {
        guard let contents = readAWSFileContents(at: filePath) else {
            return
        }

        for rawLine in contents.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.hasPrefix("[") && line.hasSuffix("]") {
                var profile = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)

                // In config file, profiles are named "profile xyz" except for "default"
                if isConfigFile && profile.hasPrefix("profile ") {
                    profile = String(profile.dropFirst(8)).trimmingCharacters(in: .whitespaces)
                }

                if profile.isNotEmpty {
                    profiles.insert(profile)
                }
            }
        }
    }

    // MARK: - Description

    override var description: String {
        let truncatedKey = accessKeyId.prefix(4)
        return "<AWSCredentials: profile=\(profileName ?? "(manual)"), accessKeyId=\(truncatedKey)...>"
    }
}

// MARK: - Objective-C Compatibility

extension AWSCredentials {

    /// Objective-C compatible factory method that returns nil on error
    @objc static func credentials(withProfile profileName: String?, error errorPointer: NSErrorPointer) -> AWSCredentials? {
        do {
            return try AWSCredentials(profile: profileName)
        } catch let credError as AWSCredentialsError {
            errorPointer?.pointee = NSError(
                domain: "AWSCredentialsErrorDomain",
                code: credError.rawValue,
                userInfo: [NSLocalizedDescriptionKey: credError.localizedDescription]
            )
            return nil
        } catch let otherError {
            errorPointer?.pointee = otherError as NSError
            return nil
        }
    }

    /// Get profile configuration for Objective-C callers
    @objc static func profileConfiguration(forProfile profileName: String?) -> [String: String]? {
        let effectiveProfile = profileName ?? "default"
        return try? loadProfileConfiguration(for: effectiveProfile)
    }
}
