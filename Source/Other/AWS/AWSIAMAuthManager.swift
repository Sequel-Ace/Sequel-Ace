//
//  AWSIAMAuthManager.swift
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
import AppKit
import OSLog
import Security

/// Errors that can occur during IAM authentication
@objc enum AWSIAMAuthError: Int, Error, LocalizedError {
    case credentialsNotFound
    case credentialsInvalid
    case mfaCancelled
    case roleAssumptionFailed
    case tokenGenerationFailed
    case keychainError

    var errorDescription: String? {
        switch self {
        case .credentialsNotFound:
            return NSLocalizedString("AWS credentials not found", comment: "IAM auth error")
        case .credentialsInvalid:
            return NSLocalizedString("AWS credentials are invalid", comment: "IAM auth error")
        case .mfaCancelled:
            return NSLocalizedString("MFA authentication was cancelled", comment: "IAM auth error")
        case .roleAssumptionFailed:
            return NSLocalizedString("Failed to assume IAM role", comment: "IAM auth error")
        case .tokenGenerationFailed:
            return NSLocalizedString("Failed to generate IAM authentication token", comment: "IAM auth error")
        case .keychainError:
            return NSLocalizedString("Failed to access keychain", comment: "IAM auth error")
        }
    }
}

/// Manages AWS IAM authentication flow including credential loading, role assumption, and token generation
@objcMembers final class AWSIAMAuthManager: NSObject {

    // MARK: - Keychain Constants

    private static let keychainServicePrefix = "Sequel Ace AWS"
    private static let log = OSLog(subsystem: "com.sequel-ace.sequel-ace", category: "AWSIAMAuth")
    private static let awsRegionCatalogURL = URL(string: "https://ip-ranges.amazonaws.com/ip-ranges.json")!
    private static let awsRegionCacheKey = "AWSIAMAvailableRegionsCache"
    private static let awsRegionCacheTimestampKey = "AWSIAMAvailableRegionsCacheTimestamp"
    private static let awsRegionCacheTTL: TimeInterval = 60 * 60 * 24 * 7 // 7 days
    private static let fallbackRegions: [String] = [
        "af-south-1",
        "ap-east-1",
        "ap-northeast-1",
        "ap-northeast-2",
        "ap-northeast-3",
        "ap-south-1",
        "ap-south-2",
        "ap-southeast-1",
        "ap-southeast-2",
        "ap-southeast-3",
        "ap-southeast-4",
        "ca-central-1",
        "ca-west-1",
        "cn-north-1",
        "cn-northwest-1",
        "eu-central-1",
        "eu-central-2",
        "eu-north-1",
        "eu-south-1",
        "eu-south-2",
        "eu-west-1",
        "eu-west-2",
        "eu-west-3",
        "il-central-1",
        "me-central-1",
        "me-south-1",
        "mx-central-1",
        "sa-east-1",
        "us-east-1",
        "us-east-2",
        "us-gov-east-1",
        "us-gov-west-1",
        "us-west-1",
        "us-west-2"
    ]

    // MARK: - Credential Caching

    /// Cache for temporary credentials from role assumption (to avoid MFA prompts on reconnect)
    /// Key: profile name, Value: (credentials, expiration date)
    private static var credentialCache = [String: (credentials: AWSCredentials, expiration: Date)]()
    private static let cacheLock = NSLock()
    private static let defaultRoleCredentialCacheDuration: TimeInterval = 3600
    private static let minimumRoleCredentialCacheDuration: TimeInterval = 1
    private static let maximumRoleCredentialCacheDuration: TimeInterval = 3600

    /// Cache duration margin - refresh credentials 5 minutes before expiration
    private static let cacheExpirationMargin: TimeInterval = 300

    static func preferredSTSRegion(baseRegion: String?, fallbackRegion: String) -> String {
        let trimmedBaseRegion = baseRegion?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedBaseRegion.isEmpty ? fallbackRegion : trimmedBaseRegion
    }

    // MARK: - Token Generation

    /// Generate an IAM authentication token for a database connection
    /// - Parameters:
    ///   - hostname: Database hostname
    ///   - port: Database port
    ///   - username: Database username
    ///   - region: AWS region (optional, will detect from hostname)
    ///   - profile: AWS profile name (required, uses "default" if nil/empty)
    ///   - accessKey: Deprecated, ignored (kept for API compatibility)
    ///   - secretKey: Deprecated, ignored (kept for API compatibility)
    ///   - parentWindow: Parent window for MFA dialog
    /// - Returns: Authentication token to use as database password
    /// - Note: Only AWS CLI profiles are supported. Manual credentials are ignored.
    @nonobjc static func generateAuthToken(
        hostname: String,
        port: Int,
        username: String,
        region: String?,
        profile: String?,
        accessKey: String?,
        secretKey: String?,
        parentWindow: NSWindow?
    ) throws -> String {
        // Determine region
        var effectiveRegion = region ?? ""
        if effectiveRegion.isEmpty {
            effectiveRegion = RDSIAMAuthentication.regionFromHostname(hostname) ?? ""
        }
        if effectiveRegion.isEmpty {
            effectiveRegion = "us-east-1" // Default fallback
        }

        // Use profile-based authentication only
        // Manual credentials (accessKey/secretKey) are ignored - they were never securely persisted
        let effectiveProfile = (profile?.isEmpty == false) ? profile! : "default"

        let credentials = try loadCredentialsFromProfile(
            effectiveProfile,
            region: effectiveRegion,
            parentWindow: parentWindow
        )

        // Generate the authentication token
        do {
            return try RDSIAMAuthentication.generateAuthToken(
                forHost: hostname,
                port: port,
                username: username,
                region: effectiveRegion,
                credentials: credentials
            )
        } catch {
            log.error("Failed to generate IAM auth token: \(error.localizedDescription)")
            throw AWSIAMAuthError.tokenGenerationFailed
        }
    }

    // MARK: - Credential Loading

    /// Load credentials from an AWS profile, handling role assumption and MFA as needed
    private static func loadCredentialsFromProfile(
        _ profileName: String,
        region: String,
        parentWindow: NSWindow?
    ) throws -> AWSCredentials {
        // Load base credentials from profile
        let baseCredentials: AWSCredentials
        do {
            baseCredentials = try AWSCredentials(profile: profileName)
        } catch {
            log.error("Failed to load profile '\(profileName)': \(error.localizedDescription)")
            throw AWSIAMAuthError.credentialsNotFound
        }

        // Check if role assumption is needed (FIX: Handle roles without MFA)
        guard baseCredentials.requiresRoleAssumption else {
            // No role assumption needed, use base credentials directly
            return baseCredentials
        }

        // Role assumption is required
        log.info("Profile '\(profileName)' requires role assumption")

        // Check if we have cached credentials from a previous role assumption
        // This avoids prompting for MFA on every reconnect
        if let cachedCredentials = getCachedCredentials(for: profileName) {
            log.info("Using cached credentials for profile '\(profileName)'")
            return cachedCredentials
        }

        // Check if MFA is required
        let assumedCredentials: AWSCredentials
        if baseCredentials.requiresMFA {
            assumedCredentials = try assumeRoleWithMFA(
                baseCredentials: baseCredentials,
                profileName: profileName,
                region: region,
                parentWindow: parentWindow
            )
        } else {
            // Role assumption without MFA
            assumedCredentials = try assumeRoleWithoutMFA(
                baseCredentials: baseCredentials,
                region: region
            )
        }

        // Cache for the remaining STS credential lifetime when available.
        // If expiration is absent, fall back to the default one-hour behavior.
        let cacheDuration = cacheDurationForAssumedCredentials(assumedCredentials)
        cacheCredentials(assumedCredentials, for: profileName, duration: cacheDuration)

        return assumedCredentials
    }

    // MARK: - Credential Caching

    /// Get cached credentials if they haven't expired
    private static func getCachedCredentials(for profileName: String) -> AWSCredentials? {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        guard let cached = credentialCache[profileName] else {
            return nil
        }

        // Check if credentials are still valid (with margin)
        let now = Date()
        if now.addingTimeInterval(cacheExpirationMargin) >= cached.expiration {
            // Credentials are expired or about to expire
            credentialCache.removeValue(forKey: profileName)
            return nil
        }

        return cached.credentials
    }

    /// Cache credentials for a profile
    private static func cacheCredentials(_ credentials: AWSCredentials, for profileName: String, duration: TimeInterval) {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        let expiration = Date().addingTimeInterval(duration)
        credentialCache[profileName] = (credentials, expiration)
        log.info("Cached credentials for profile '\(profileName)' until \(expiration)")
    }

    private static func cacheDurationForAssumedCredentials(_ credentials: AWSCredentials) -> TimeInterval {
        guard let expiration = credentials.expiration else {
            return defaultRoleCredentialCacheDuration
        }

        let secondsRemaining = expiration.timeIntervalSinceNow
        if !secondsRemaining.isFinite {
            return defaultRoleCredentialCacheDuration
        }

        return min(
            maximumRoleCredentialCacheDuration,
            max(minimumRoleCredentialCacheDuration, secondsRemaining)
        )
    }

    /// Clear cached credentials for a profile (call when connection is closed)
    static func clearCachedCredentials(for profileName: String?) {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        if let profileName = profileName {
            credentialCache.removeValue(forKey: profileName)
        } else {
            credentialCache.removeAll()
        }
    }

    /// Assume a role with MFA authentication
    private static func assumeRoleWithMFA(
        baseCredentials: AWSCredentials,
        profileName: String,
        region: String,
        parentWindow: NSWindow?
    ) throws -> AWSCredentials {
        guard let roleArn = baseCredentials.roleArn,
              let mfaSerial = baseCredentials.mfaSerial else {
            throw AWSIAMAuthError.roleAssumptionFailed
        }

        // Prompt for MFA token
        guard let mfaToken = AWSMFATokenDialog.promptForMFAToken(
            profile: profileName,
            mfaSerial: mfaSerial,
            parentWindow: parentWindow
        ) else {
            throw AWSIAMAuthError.mfaCancelled
        }

        // Determine region for STS call
        let stsRegion = preferredSTSRegion(baseRegion: baseCredentials.region, fallbackRegion: region)

        // Call STS AssumeRole with MFA
        var error: NSError?
        guard let tempCredentials = AWSSTSClient.assumeRoleWithMFA(
            roleArn,
            mfaSerialNumber: mfaSerial,
            mfaTokenCode: mfaToken,
            region: stsRegion,
            credentials: baseCredentials,
            error: &error
        ) else {
            if let error = error {
                log.error("STS AssumeRole with MFA failed: \(error.localizedDescription)")
            }
            throw AWSIAMAuthError.roleAssumptionFailed
        }

        return tempCredentials
    }

    /// Assume a role without MFA (FIX: This was missing in original implementation)
    private static func assumeRoleWithoutMFA(
        baseCredentials: AWSCredentials,
        region: String
    ) throws -> AWSCredentials {
        guard let roleArn = baseCredentials.roleArn else {
            throw AWSIAMAuthError.roleAssumptionFailed
        }

        // Determine region for STS call
        let stsRegion = preferredSTSRegion(baseRegion: baseCredentials.region, fallbackRegion: region)

        // Call STS AssumeRole without MFA
        var error: NSError?
        guard let tempCredentials = AWSSTSClient.assumeRole(
            roleArn,
            roleSessionName: nil,
            mfaSerialNumber: nil,
            mfaTokenCode: nil,
            durationSeconds: 3600,
            region: stsRegion,
            credentials: baseCredentials,
            error: &error
        ) else {
            if let error = error {
                log.error("STS AssumeRole failed: \(error.localizedDescription)")
            }
            throw AWSIAMAuthError.roleAssumptionFailed
        }

        return tempCredentials
    }

    // MARK: - Keychain Management

    /// Save AWS secret key to keychain
    static func saveSecretKey(
        _ secretKey: String,
        forAccessKey accessKey: String,
        connectionName: String
    ) -> Bool {
        let service = "\(keychainServicePrefix) - \(connectionName)"
        let account = accessKey

        // Delete any existing item first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add new item
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: secretKey.data(using: .utf8)!,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)

        if status != errSecSuccess {
            log.error("Failed to save secret key to keychain: \(status)")
            return false
        }

        return true
    }

    /// Retrieve AWS secret key from keychain
    static func getSecretKey(
        forAccessKey accessKey: String,
        connectionName: String
    ) -> String? {
        let service = "\(keychainServicePrefix) - \(connectionName)"
        let account = accessKey

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let secretKey = String(data: data, encoding: .utf8) else {
            return nil
        }

        return secretKey
    }

    /// Delete AWS secret key from keychain
    static func deleteSecretKey(
        forAccessKey accessKey: String,
        connectionName: String
    ) -> Bool {
        let service = "\(keychainServicePrefix) - \(connectionName)"
        let account = accessKey

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    // MARK: - Utility Methods

    /// Check if AWS credentials file exists
    static var credentialsFileExists: Bool {
        AWSCredentials.credentialsFileExists
    }

    /// Get list of available AWS profiles
    static func availableProfiles() -> [String] {
        AWSCredentials.availableProfiles()
    }

    /// Regions used by the connection UI.
    /// Returns cached regions when available, otherwise a built-in fallback list.
    static func cachedOrFallbackRegions() -> [String] {
        if let cachedRegions = cachedRegions() {
            return cachedRegions
        }
        return fallbackRegions
    }

    /// Refresh the cached region catalog from AWS when cache is stale.
    /// Falls back to cached or built-in regions if refresh fails.
    @objc(refreshAWSRegionsIfNeededWithCompletion:)
    static func refreshAWSRegionsIfNeeded(completion: @escaping ([String]) -> Void) {
        if isRegionCacheFresh(), let cachedRegions = cachedRegions() {
            DispatchQueue.main.async {
                completion(cachedRegions)
            }
            return
        }

        let request = URLRequest(
            url: awsRegionCatalogURL,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 15
        )

        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error {
                log.error("Failed to refresh AWS region catalog: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion(cachedOrFallbackRegions())
                }
                return
            }

            guard let data = data,
                  let parsedRegions = regionsFromIPRangesResponse(data),
                  !parsedRegions.isEmpty else {
                log.error("Failed to parse AWS region catalog response")
                DispatchQueue.main.async {
                    completion(cachedOrFallbackRegions())
                }
                return
            }

            let mergedRegions = mergeWithFallbackRegions(parsedRegions)
            persistRegionCache(mergedRegions)

            DispatchQueue.main.async {
                completion(mergedRegions)
            }
        }.resume()
    }

    /// Check if a hostname appears to be an RDS endpoint
    static func isRDSHostname(_ hostname: String) -> Bool {
        RDSIAMAuthentication.isRDSHostname(hostname)
    }

    /// Extract region from RDS hostname
    static func regionFromHostname(_ hostname: String) -> String? {
        RDSIAMAuthentication.regionFromHostname(hostname)
    }

    // MARK: - Region Catalog Helpers

    static func regionsFromIPRangesResponse(_ data: Data) -> [String]? {
        guard let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let ipv4Regions = (jsonObject["prefixes"] as? [[String: Any]] ?? [])
            .compactMap { $0["region"] as? String }
        let ipv6Regions = (jsonObject["ipv6_prefixes"] as? [[String: Any]] ?? [])
            .compactMap { $0["region"] as? String }

        let uniqueRegions = Set((ipv4Regions + ipv6Regions).map { $0.lowercased() })
        let validRegions = uniqueRegions.filter { region in
            region != "global" && RDSIAMAuthentication.isValidAWSRegion(region)
        }

        return validRegions.sorted { lhs, rhs in
            lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }
    }

    static func mergeWithFallbackRegions(_ regions: [String]) -> [String] {
        let merged = Set(fallbackRegions.map { $0.lowercased() })
            .union(regions.map { $0.lowercased() })

        return merged.sorted { lhs, rhs in
            lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }
    }

    private static func cachedRegions() -> [String]? {
        guard let regions = UserDefaults.standard.array(forKey: awsRegionCacheKey) as? [String],
              !regions.isEmpty else {
            return nil
        }
        return mergeWithFallbackRegions(regions)
    }

    private static func isRegionCacheFresh() -> Bool {
        let timestamp = UserDefaults.standard.double(forKey: awsRegionCacheTimestampKey)
        guard timestamp > 0 else {
            return false
        }
        return Date().timeIntervalSince1970 - timestamp < awsRegionCacheTTL
    }

    private static func persistRegionCache(_ regions: [String]) {
        UserDefaults.standard.set(regions, forKey: awsRegionCacheKey)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: awsRegionCacheTimestampKey)
    }
}

// MARK: - Objective-C Compatibility

extension AWSIAMAuthManager {

    /// Objective-C compatible method that returns nil on error
    /// Note: Uses a different method name to avoid selector conflicts with the throwing version
    @objc(generateAuthTokenWithHostname:port:username:region:profile:accessKey:secretKey:parentWindow:error:)
    static func generateAuthTokenObjC(
        hostname: String,
        port: Int,
        username: String,
        region: String?,
        profile: String?,
        accessKey: String?,
        secretKey: String?,
        parentWindow: NSWindow?,
        error errorPointer: NSErrorPointer
    ) -> String? {
        do {
            return try generateAuthToken(
                hostname: hostname,
                port: port,
                username: username,
                region: region,
                profile: profile,
                accessKey: accessKey,
                secretKey: secretKey,
                parentWindow: parentWindow
            )
        } catch let authError as AWSIAMAuthError {
            errorPointer?.pointee = NSError(
                domain: "AWSIAMAuthErrorDomain",
                code: authError.rawValue,
                userInfo: [NSLocalizedDescriptionKey: authError.localizedDescription]
            )
            return nil
        } catch let otherError {
            errorPointer?.pointee = otherError as NSError
            return nil
        }
    }
}
