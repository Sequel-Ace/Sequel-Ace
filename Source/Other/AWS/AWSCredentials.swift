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
        !accessKeyId.isEmpty && !secretAccessKey.isEmpty
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
           !envPath.isEmpty {
            return envPath
        }
        return NSHomeDirectory() + "/.aws/credentials"
    }

    @objc static var configFilePath: String {
        if let envPath = ProcessInfo.processInfo.environment["AWS_CONFIG_FILE"],
           !envPath.isEmpty {
            return envPath
        }
        return NSHomeDirectory() + "/.aws/config"
    }

    @objc static var credentialsFileExists: Bool {
        FileManager.default.fileExists(atPath: credentialsFilePath)
    }

    // MARK: - Profile Loading

    /// Returns list of available AWS profiles sorted alphabetically with "default" first
    @objc static func availableProfiles() -> [String] {
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
    private static func loadProfileConfiguration(for profileName: String) throws -> [String: String] {
        var result = [String: String]()
        var foundProfile = false

        // Load from ~/.aws/credentials
        if FileManager.default.fileExists(atPath: credentialsFilePath) {
            if let contents = try? String(contentsOfFile: credentialsFilePath, encoding: .utf8) {
                if let creds = parseAWSFile(contents, forProfile: profileName, isConfigFile: false) {
                    result.merge(creds) { current, _ in current }
                    foundProfile = true
                }
            }
        }

        // Load from ~/.aws/config
        if FileManager.default.fileExists(atPath: configFilePath) {
            if let contents = try? String(contentsOfFile: configFilePath, encoding: .utf8) {
                if let config = parseAWSFile(contents, forProfile: profileName, isConfigFile: true) {
                    // Merge config, credentials take precedence
                    for (key, value) in config where result[key] == nil {
                        result[key] = value
                    }
                    foundProfile = true
                }
            }
        }

        // If profile has source_profile, load credentials from that
        if let sourceProfile = result["source_profile"], result["aws_access_key_id"] == nil {
            if let sourceConfig = try? loadProfileConfiguration(for: sourceProfile) {
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
        }

        guard foundProfile else {
            throw AWSCredentialsError.profileNotFound
        }

        return result
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

                if !key.isEmpty && !value.isEmpty {
                    result[key] = value
                }
            }
        }

        return foundProfile ? result : nil
    }

    /// Add profile names from a file to the set
    private static func addProfiles(from filePath: String, to profiles: inout Set<String>, isConfigFile: Bool) {
        guard FileManager.default.fileExists(atPath: filePath),
              let contents = try? String(contentsOfFile: filePath, encoding: .utf8) else {
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

                if !profile.isEmpty {
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
