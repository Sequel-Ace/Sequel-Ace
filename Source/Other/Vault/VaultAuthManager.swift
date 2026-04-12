//
//  VaultAuthManager.swift
//  Sequel Ace
//
//  Coordinates Vault token validation, OIDC login, and credential generation.
//  Exposed to Objective-C via @objcMembers.
//

import Foundation
import OSLog

/// Errors surfaced to the Objective-C connection controller.
@objc enum VaultAuthError: Int, Error, LocalizedError {
    case invalidConfiguration
    case loginCancelled
    case loginFailed
    case credentialsFailed
    case emptyCredentials

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return NSLocalizedString("Vault host or credentials path is missing.", comment: "Vault auth config error")
        case .loginCancelled:
            return NSLocalizedString("Vault login was cancelled.", comment: "Vault auth cancelled")
        case .loginFailed:
            return NSLocalizedString("Vault OIDC login failed.", comment: "Vault auth login failed")
        case .credentialsFailed:
            return NSLocalizedString("Failed to generate credentials from Vault.", comment: "Vault auth creds failed")
        case .emptyCredentials:
            return NSLocalizedString("Vault returned empty credentials.", comment: "Vault auth empty creds")
        }
    }
}

@objcMembers final class VaultAuthManager: NSObject {

    private static let log = OSLog(subsystem: "com.sequel-ace.sequel-ace", category: "VaultAuth")
    private static let errorDomain = "VaultAuthErrorDomain"
    private static let cacheExpirationMargin: TimeInterval = 30

    // MARK: - Credential cache (internal for testability)

    private struct CacheEntry {
        let username: String
        let password: String
        let expiration: Date
    }

    private static var credentialCache = [String: CacheEntry]()
    private static let cacheLock = NSLock()

    /// Builds a cache key that includes the Vault server identity so two servers
    /// with the same credentials path don't share cached entries.
    static func cacheKey(baseURL: URL, credPath: String) -> String {
        let host = baseURL.host ?? ""
        let port = baseURL.port.map(String.init) ?? "443"
        return "\(host):\(port)/\(credPath)"
    }

    static func cachedCredentials(for key: String) -> (username: String, password: String)? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        guard let entry = credentialCache[key] else { return nil }
        if Date().addingTimeInterval(cacheExpirationMargin) >= entry.expiration {
            credentialCache.removeValue(forKey: key)
            return nil
        }
        return (entry.username, entry.password)
    }

    static func setCachedCredentials(username: String, password: String, leaseDuration: TimeInterval, for key: String) {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        let expiration = Date().addingTimeInterval(leaseDuration)
        credentialCache[key] = CacheEntry(username: username, password: password, expiration: expiration)
    }

    static func clearCachedCredentials(for key: String?) {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let key = key {
            credentialCache.removeValue(forKey: key)
        } else {
            credentialCache.removeAll()
        }
    }

    /// ObjC-compatible clear — constructs the same composite key used at connect time.
    @objc(clearCachedCredentialsForHost:port:credPath:)
    static func clearCachedCredentials(host: String, port: String, credPath: String) {
        guard let baseURL = VaultClient.buildBaseURL(host: host, port: port) else { return }
        clearCachedCredentials(for: cacheKey(baseURL: baseURL, credPath: credPath))
    }

    // MARK: - Token helpers

    static func isAuthorized(baseURL: URL) -> Bool {
        guard let token = VaultOIDCHandler.readCachedToken() else { return false }
        return (try? VaultClient.tokenLookupSelf(baseURL: baseURL, token: token)) == true
    }

    // MARK: - Main entry point (ObjC-compatible)

    /// Generate ephemeral DB credentials using Vault. Blocks the calling thread.
    /// MUST be called from a background thread — triggers OIDC browser flow if token is expired.
    @objc(generateCredentialsWithHost:port:oidcMount:credPath:username:password:error:)
    static func generateCredentials(
        host: String,
        port: String,
        oidcMount: String,
        credPath: String,
        username: AutoreleasingUnsafeMutablePointer<NSString?>,
        password: AutoreleasingUnsafeMutablePointer<NSString?>,
        error errorPointer: NSErrorPointer
    ) -> Bool {
        assert(!Thread.isMainThread, "generateCredentials must not be called on the main thread")
        let effectiveCredPath = credPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let baseURL = VaultClient.buildBaseURL(host: host, port: port),
              !effectiveCredPath.isEmpty else {
            errorPointer?.pointee = NSError(
                domain: errorDomain,
                code: VaultAuthError.invalidConfiguration.rawValue,
                userInfo: [NSLocalizedDescriptionKey: VaultAuthError.invalidConfiguration.localizedDescription ?? ""]
            )
            return false
        }

        let trimmedMount = oidcMount.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveMount = trimmedMount.isEmpty ? "oidc" : trimmedMount

        let key = cacheKey(baseURL: baseURL, credPath: effectiveCredPath)

        // Return cached credentials if still valid
        if let cached = cachedCredentials(for: key) {
            username.pointee = cached.username as NSString
            password.pointee = cached.password as NSString
            return true
        }

        // Ensure we have a valid Vault token.
        // Distinguish network failures (propagate as errors) from invalid/expired tokens
        // (proceed to OIDC login). Using try? would collapse both cases and trigger a
        // spurious browser login on transient network errors.
        let token: String
        if let rawToken = VaultOIDCHandler.readCachedToken() {
            do {
                let valid = try VaultClient.tokenLookupSelf(baseURL: baseURL, token: rawToken)
                if valid {
                    token = rawToken
                    // Token is valid — skip OIDC and go straight to credential generation.
                    let creds: VaultCredentials
                    do {
                        creds = try VaultClient.generateCredentials(baseURL: baseURL, credPath: effectiveCredPath, token: token)
                    } catch {
                        errorPointer?.pointee = NSError(
                            domain: errorDomain,
                            code: VaultAuthError.credentialsFailed.rawValue,
                            userInfo: [NSLocalizedDescriptionKey: error.localizedDescription]
                        )
                        return false
                    }
                    setCachedCredentials(username: creds.username, password: creds.password, leaseDuration: creds.leaseDuration, for: key)
                    username.pointee = creds.username as NSString
                    password.pointee = creds.password as NSString
                    return true
                }
                // Token is present but invalid/expired — fall through to OIDC login below.
            } catch {
                // Network error talking to Vault — surface this rather than falling through to login.
                os_log("Vault tokenLookupSelf network error: %{public}@", log: log, type: .error, error.localizedDescription)
                errorPointer?.pointee = NSError(
                    domain: errorDomain,
                    code: VaultAuthError.loginFailed.rawValue,
                    userInfo: [NSLocalizedDescriptionKey: error.localizedDescription]
                )
                return false
            }
        }

        // Run OIDC flow — no cached token or token was invalid/expired.
        do {
            token = try VaultOIDCHandler.login(baseURL: baseURL, mount: effectiveMount)
        } catch let oidcError as VaultOIDCError {
            let isCancel = (oidcError == .cancelled)
            let authError: VaultAuthError = isCancel ? .loginCancelled : .loginFailed
            errorPointer?.pointee = NSError(
                domain: errorDomain,
                code: authError.rawValue,
                userInfo: [NSLocalizedDescriptionKey: oidcError.localizedDescription ?? ""]
            )
            os_log("Vault OIDC login failed: %{public}@", log: log, type: .error, oidcError.localizedDescription ?? "unknown")
            return false
        } catch {
            errorPointer?.pointee = NSError(
                domain: errorDomain,
                code: VaultAuthError.loginFailed.rawValue,
                userInfo: [NSLocalizedDescriptionKey: error.localizedDescription]
            )
            os_log("Vault login error: %{public}@", log: log, type: .error, error.localizedDescription)
            return false
        }

        // Generate credentials from Vault.
        let creds: VaultCredentials
        do {
            creds = try VaultClient.generateCredentials(baseURL: baseURL, credPath: effectiveCredPath, token: token)
        } catch {
            errorPointer?.pointee = NSError(
                domain: errorDomain,
                code: VaultAuthError.credentialsFailed.rawValue,
                userInfo: [NSLocalizedDescriptionKey: error.localizedDescription]
            )
            return false
        }

        setCachedCredentials(username: creds.username, password: creds.password, leaseDuration: creds.leaseDuration, for: key)

        username.pointee = creds.username as NSString
        password.pointee = creds.password as NSString
        return true
    }

    /// Check whether there is a valid cached Vault token for the given host.
    @objc(isAuthorizedWithHost:port:)
    static func isAuthorized(host: String, port: String) -> Bool {
        guard let baseURL = VaultClient.buildBaseURL(host: host, port: port) else { return false }
        return isAuthorized(baseURL: baseURL)
    }
}
