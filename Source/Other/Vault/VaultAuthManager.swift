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
        let token: String  // Vault token that generated these credentials; used to detect identity changes
    }

    private static var credentialCache = [String: CacheEntry]()
    private static let cacheLock = NSLock()

    // Per-key in-flight coalescing: if two threads simultaneously miss the cache for
    // the same key, the second waits for the first to finish and then reads from cache
    // rather than launching a duplicate OIDC flow and creating extra Vault leases.
    //
    // Lock ordering: inFlightCondition is always acquired BEFORE VaultOIDCHandler.loginLock.
    // The 100ms wait loop checks isActiveLoginCancelled (which acquires loginLock) while
    // inFlightCondition is held. The reverse order — loginLock then inFlightCondition —
    // never occurs, so there is no deadlock risk. Do not violate this ordering.
    private static var inFlightKeys = Set<String>()
    private static let inFlightCondition = NSCondition()

    /// Builds a cache key unique per Vault server + OIDC mount + credentials path.
    /// All three must be included: two favorites sharing the same DB host and cred path
    /// but pointing at different OIDC mounts would otherwise collide and reuse each
    /// other's cached DB credentials.
    static func cacheKey(baseURL: URL, oidcMount: String, credPath: String) -> String {
        let host = baseURL.host ?? ""
        let port = baseURL.port.map(String.init) ?? "443"
        return "\(host):\(port)@\(oidcMount)/\(credPath)"
    }

    /// Look up cached credentials. Evicts the entry if it has expired or if `matchingToken`
    /// is provided and differs from the token that generated the entry (identity change).
    static func cachedCredentials(for key: String, matchingToken: String? = nil) -> (username: String, password: String)? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        guard let entry = credentialCache[key] else { return nil }
        if Date().addingTimeInterval(cacheExpirationMargin) >= entry.expiration {
            credentialCache.removeValue(forKey: key)
            return nil
        }
        if let current = matchingToken, !entry.token.isEmpty, entry.token != current {
            credentialCache.removeValue(forKey: key)
            return nil
        }
        return (entry.username, entry.password)
    }

    static func setCachedCredentials(username: String, password: String, leaseDuration: TimeInterval, token: String = "", for key: String) {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        let expiration = Date().addingTimeInterval(leaseDuration)
        credentialCache[key] = CacheEntry(username: username, password: password, expiration: expiration, token: token)
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
    @objc(clearCachedCredentialsForHost:port:oidcMount:credPath:)
    static func clearCachedCredentials(host: String, port: String, oidcMount: String, credPath: String) {
        guard let baseURL = VaultClient.buildBaseURL(host: host, port: port) else { return }
        let effectiveMount = oidcMount.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedMount = effectiveMount.isEmpty ? "oidc" : effectiveMount
        let effectiveCredPath = credPath.trimmingCharacters(in: .whitespacesAndNewlines)
        clearCachedCredentials(for: cacheKey(baseURL: baseURL, oidcMount: normalizedMount, credPath: effectiveCredPath))
    }

    // MARK: - Token helpers

    /// Check whether there is a valid cached Vault token for the given Vault server and OIDC mount.
    /// MUST be called from a background thread — performs synchronous network I/O.
    static func isAuthorized(baseURL: URL, mount: String) -> Bool {
        assert(!Thread.isMainThread, "isAuthorized must not be called on the main thread")
        guard let token = VaultOIDCHandler.cachedToken(for: baseURL, mount: mount) else { return false }
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
        generateCredentials(host: host, port: port, oidcMount: oidcMount, credPath: credPath, loginIdentifier: "",
                            username: username, password: password, error: errorPointer)
    }

    /// Generate ephemeral DB credentials using Vault, with cancellation scoped to
    /// the caller's OIDC login attempt.
    @objc(generateCredentialsWithHost:port:oidcMount:credPath:loginIdentifier:username:password:error:)
    static func generateCredentials(
        host: String,
        port: String,
        oidcMount: String,
        credPath: String,
        loginIdentifier: String,
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
                userInfo: [NSLocalizedDescriptionKey: VaultAuthError.invalidConfiguration.localizedDescription]
            )
            return false
        }

        let effectiveMount = effectiveOIDCMount(oidcMount)

        let key = cacheKey(baseURL: baseURL, oidcMount: effectiveMount, credPath: effectiveCredPath)
        let activeLoginIdentifier = loginIdentifier.isEmpty ? nil : loginIdentifier

        func failCancelled() -> Bool {
            errorPointer?.pointee = NSError(
                domain: errorDomain,
                code: VaultAuthError.loginCancelled.rawValue,
                userInfo: [NSLocalizedDescriptionKey: VaultAuthError.loginCancelled.localizedDescription]
            )
            return false
        }

        if let activeLoginIdentifier,
           VaultOIDCHandler.isActiveLoginCancelled(identifier: activeLoginIdentifier) {
            return failCancelled()
        }

        // Read the best available token for this Vault server + OIDC mount: in-session map first,
        // then the Keychain item scoped to this Vault address and mount.
        let preReadToken = VaultOIDCHandler.cachedToken(for: baseURL, mount: effectiveMount)

        // Return cached credentials if still valid under the same Vault identity.
        // Passing preReadToken evicts the entry when the known token changes.
        if let cached = cachedCredentials(for: key, matchingToken: preReadToken) {
            username.pointee = cached.username as NSString
            password.pointee = cached.password as NSString
            return true
        }

        // Coalesce concurrent misses for the same key: if another thread is already
        // running the OIDC + generateCredentials flow for this key, wait for it to
        // finish and then read its result from the cache rather than launching a
        // duplicate flow that creates extra Vault leases and races the callback listener.
        inFlightCondition.lock()
        while inFlightKeys.contains(key) {
            if let activeLoginIdentifier,
               VaultOIDCHandler.isActiveLoginCancelled(identifier: activeLoginIdentifier) {
                inFlightCondition.unlock()
                return failCancelled()
            }
            inFlightCondition.wait(until: Date().addingTimeInterval(0.1))
        }
        if let activeLoginIdentifier,
           VaultOIDCHandler.isActiveLoginCancelled(identifier: activeLoginIdentifier) {
            inFlightCondition.unlock()
            return failCancelled()
        }
        // Re-check cache after waking — the in-flight thread may have populated it.
        // Re-fetch the token: the in-flight thread may have obtained a new one via OIDC,
        // so preReadToken could be stale and would evict the fresh entry.
        let postWaitToken = VaultOIDCHandler.cachedToken(for: baseURL, mount: effectiveMount)
        if let cached = cachedCredentials(for: key, matchingToken: postWaitToken) {
            inFlightCondition.unlock()
            username.pointee = cached.username as NSString
            password.pointee = cached.password as NSString
            return true
        }
        inFlightKeys.insert(key)
        inFlightCondition.unlock()

        // Helper: signal waiting threads and remove the in-flight marker on any exit.
        func finishInFlight() {
            inFlightCondition.lock()
            inFlightKeys.remove(key)
            inFlightCondition.broadcast()
            inFlightCondition.unlock()
        }

        if let activeLoginIdentifier,
           VaultOIDCHandler.isActiveLoginCancelled(identifier: activeLoginIdentifier) {
            finishInFlight()
            return failCancelled()
        }

        // Ensure we have a valid Vault token.
        // Distinguish network failures (propagate as errors) from invalid/expired tokens
        // (proceed to OIDC login). Using try? would collapse both cases and trigger a
        // spurious browser login on transient network errors.
        let token: String
        if let rawToken = preReadToken {
            do {
                let valid = try VaultClient.tokenLookupSelf(baseURL: baseURL, token: rawToken)
                if valid {
                    token = rawToken
                    if let activeLoginIdentifier,
                       VaultOIDCHandler.isActiveLoginCancelled(identifier: activeLoginIdentifier) {
                        finishInFlight()
                        return failCancelled()
                    }
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
                        finishInFlight(); return false
                    }
                    guard !creds.username.isEmpty, !creds.password.isEmpty else {
                        errorPointer?.pointee = NSError(
                            domain: errorDomain,
                            code: VaultAuthError.emptyCredentials.rawValue,
                            userInfo: [NSLocalizedDescriptionKey: VaultAuthError.emptyCredentials.localizedDescription]
                        )
                        finishInFlight(); return false
                    }
                    setCachedCredentials(username: creds.username, password: creds.password, leaseDuration: creds.leaseDuration, token: token, for: key)
                    finishInFlight()
                    username.pointee = creds.username as NSString
                    password.pointee = creds.password as NSString
                    return true
                }
                // Token is present but invalid/expired — fall through to OIDC login below.
            } catch {
                // Network or service error (including 429/5xx) — surface this rather than
                // falling through to OIDC login, which would open a spurious browser window.
                os_log("Vault tokenLookupSelf error: %{public}@", log: log, type: .error, error.localizedDescription)
                errorPointer?.pointee = NSError(
                    domain: errorDomain,
                    code: VaultAuthError.loginFailed.rawValue,
                    userInfo: [NSLocalizedDescriptionKey: error.localizedDescription]
                )
                finishInFlight(); return false
            }
        }

        // Run OIDC flow — no cached token or token was invalid/expired.
        do {
            if let activeLoginIdentifier,
               VaultOIDCHandler.isActiveLoginCancelled(identifier: activeLoginIdentifier) {
                finishInFlight()
                return failCancelled()
            }
            token = try VaultOIDCHandler.login(baseURL: baseURL, mount: effectiveMount, identifier: activeLoginIdentifier)
        } catch let oidcError as VaultOIDCError {
            let isCancel = (oidcError == .cancelled)
            let authError: VaultAuthError = isCancel ? .loginCancelled : .loginFailed
            errorPointer?.pointee = NSError(
                domain: errorDomain,
                code: authError.rawValue,
                userInfo: [NSLocalizedDescriptionKey: oidcError.localizedDescription]
            )
            os_log("Vault OIDC login failed: %{public}@", log: log, type: .error, oidcError.localizedDescription)
            finishInFlight(); return false
        } catch {
            errorPointer?.pointee = NSError(
                domain: errorDomain,
                code: VaultAuthError.loginFailed.rawValue,
                userInfo: [NSLocalizedDescriptionKey: error.localizedDescription]
            )
            os_log("Vault login error: %{public}@", log: log, type: .error, error.localizedDescription)
            finishInFlight(); return false
        }

        // Generate credentials from Vault.
        if let activeLoginIdentifier,
           VaultOIDCHandler.isActiveLoginCancelled(identifier: activeLoginIdentifier) {
            finishInFlight()
            return failCancelled()
        }
        let creds: VaultCredentials
        do {
            creds = try VaultClient.generateCredentials(baseURL: baseURL, credPath: effectiveCredPath, token: token)
        } catch {
            errorPointer?.pointee = NSError(
                domain: errorDomain,
                code: VaultAuthError.credentialsFailed.rawValue,
                userInfo: [NSLocalizedDescriptionKey: error.localizedDescription]
            )
            finishInFlight(); return false
        }

        guard !creds.username.isEmpty, !creds.password.isEmpty else {
            errorPointer?.pointee = NSError(
                domain: errorDomain,
                code: VaultAuthError.emptyCredentials.rawValue,
                userInfo: [NSLocalizedDescriptionKey: VaultAuthError.emptyCredentials.localizedDescription]
            )
            finishInFlight(); return false
        }
        setCachedCredentials(username: creds.username, password: creds.password, leaseDuration: creds.leaseDuration, token: token, for: key)
        finishInFlight()

        username.pointee = creds.username as NSString
        password.pointee = creds.password as NSString
        return true
    }

    /// Normalize an OIDC auth mount, defaulting to "oidc" when blank.
    private static func effectiveOIDCMount(_ mount: String) -> String {
        let trimmed = mount.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "oidc" : trimmed
    }

    /// Whether `error` is a user/lifecycle cancellation of a Vault login (declined
    /// browser confirmation, tab switch, or document teardown). Callers use this to
    /// stay silent instead of surfacing a "failure" alert for an expected abort.
    @objc(isLoginCancellationError:)
    static func isLoginCancellation(_ error: NSError?) -> Bool {
        guard let error = error else { return false }
        return error.domain == errorDomain && error.code == VaultAuthError.loginCancelled.rawValue
    }

    /// List database roles under `mount`, ensuring a valid Vault token first
    /// (reusing the cached token, else running the OIDC login flow).
    /// MUST be called from a background thread.
    ///
    /// `confirmBrowserLogin` is invoked (synchronously) only when a browser OIDC
    /// login is about to open — i.e. there is no valid cached token, covering both
    /// the "no token" and "cached-but-expired token" cases. Return false to abort
    /// without opening the browser; the call then fails with `.loginCancelled`.
    static func listRoles(
        host: String,
        port: String,
        oidcMount: String,
        mount: String,
        loginIdentifier: String,
        confirmBrowserLogin: () -> Bool,
        error errorPointer: NSErrorPointer
    ) -> [String]? {
        assert(!Thread.isMainThread, "listRoles must not be called on the main thread")

        let trimmedMountValue = mount.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let baseURL = VaultClient.buildBaseURL(host: host, port: port), !trimmedMountValue.isEmpty else {
            errorPointer?.pointee = NSError(
                domain: errorDomain,
                code: VaultAuthError.invalidConfiguration.rawValue,
                userInfo: [NSLocalizedDescriptionKey: VaultAuthError.invalidConfiguration.localizedDescription ?? ""])
            return nil
        }

        let oidcMountResolved = effectiveOIDCMount(oidcMount)

        // Resolve a valid token: cached-and-valid, else OIDC login.
        let token: String
        do {
            if let cached = VaultOIDCHandler.cachedToken(for: baseURL, mount: oidcMountResolved),
               try VaultClient.tokenLookupSelf(baseURL: baseURL, token: cached) {
                token = cached
            } else {
                // No valid cached token (missing or expired): a browser login is
                // about to open. But the refresh may have been cancelled while the
                // cached-token check ran — editing the Vault host/mount, leaving the
                // Vault tab, or document teardown all call cancelActiveLogin. Honor
                // that cancellation before prompting or opening the browser (the `||`
                // short-circuits, so a cancelled refresh never shows the dialog), and
                // confirm first otherwise so a login is never a surprise. Either way
                // the completion stays silent via isLoginCancellation.
                let effectiveIdentifier = loginIdentifier.isEmpty ? nil : loginIdentifier
                let alreadyCancelled = effectiveIdentifier.map { VaultOIDCHandler.isActiveLoginCancelled(identifier: $0) } ?? false
                if alreadyCancelled || !confirmBrowserLogin() {
                    errorPointer?.pointee = NSError(
                        domain: errorDomain,
                        code: VaultAuthError.loginCancelled.rawValue,
                        userInfo: [NSLocalizedDescriptionKey: VaultAuthError.loginCancelled.localizedDescription ?? ""])
                    return nil
                }
                os_log("Vault listRoles: no valid cached token, falling through to OIDC login", log: log, type: .info)
                token = try VaultOIDCHandler.login(baseURL: baseURL, mount: oidcMountResolved, identifier: effectiveIdentifier)
            }
        } catch let oidcError as VaultOIDCError {
            let authError: VaultAuthError = (oidcError == .cancelled) ? .loginCancelled : .loginFailed
            errorPointer?.pointee = NSError(
                domain: errorDomain,
                code: authError.rawValue,
                userInfo: [NSLocalizedDescriptionKey: oidcError.localizedDescription ?? ""])
            os_log("Vault OIDC login failed: %{public}@", log: log, type: .error, oidcError.localizedDescription ?? "unknown")
            return nil
        } catch {
            errorPointer?.pointee = NSError(
                domain: errorDomain,
                code: VaultAuthError.loginFailed.rawValue,
                userInfo: [NSLocalizedDescriptionKey: error.localizedDescription])
            os_log("Vault login error: %{public}@", log: log, type: .error, error.localizedDescription)
            return nil
        }

        do {
            return try VaultClient.listDatabaseRoles(baseURL: baseURL, mount: trimmedMountValue, token: token)
        } catch {
            errorPointer?.pointee = NSError(
                domain: errorDomain,
                code: VaultAuthError.credentialsFailed.rawValue,
                userInfo: [NSLocalizedDescriptionKey: error.localizedDescription])
            return nil
        }
    }

    /// Check whether there is a valid cached Vault token for the default OIDC mount on the given host.
    /// MUST be called from a background thread — performs synchronous network I/O.
    @objc(isAuthorizedWithHost:port:)
    static func isAuthorized(host: String, port: String) -> Bool {
        assert(!Thread.isMainThread, "isAuthorized must not be called on the main thread")
        guard let baseURL = VaultClient.buildBaseURL(host: host, port: port) else { return false }
        return isAuthorized(baseURL: baseURL, mount: "oidc")
    }

    /// Check whether there is a valid cached Vault token for the given host and OIDC mount.
    /// MUST be called from a background thread — performs synchronous network I/O.
    @objc(isAuthorizedWithHost:port:oidcMount:)
    static func isAuthorized(host: String, port: String, oidcMount: String) -> Bool {
        assert(!Thread.isMainThread, "isAuthorized must not be called on the main thread")
        guard let baseURL = VaultClient.buildBaseURL(host: host, port: port) else { return false }
        return isAuthorized(baseURL: baseURL, mount: effectiveOIDCMount(oidcMount))
    }
}
