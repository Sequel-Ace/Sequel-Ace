//
//  VaultOIDCHandler.swift
//  Sequel Ace
//
//  Handles the browser-based OIDC login flow. Binds a local HTTP server on
//  a random port, opens the Vault OIDC auth URL in the system browser, waits
//  for the callback, exchanges the code for a Vault token, and persists it
//  in the user's Keychain scoped to the Vault server URL and OIDC mount.
//

import Foundation
import Network
import AppKit
import OSLog
import Security

enum VaultOIDCError: Error, LocalizedError {
    case cancelled
    case noAvailablePort
    case loginInProgress
    case callbackTimeout
    case malformedCallback(String)
    case vaultError(Error)

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return NSLocalizedString("Vault login was cancelled.", comment: "Vault OIDC cancelled")
        case .noAvailablePort:
            return NSLocalizedString("Could not bind a local port for the Vault OIDC callback.", comment: "Vault OIDC port error")
        case .loginInProgress:
            return NSLocalizedString("Another Vault sign-in is already in progress. Finish or cancel it (including in other windows) and try again.", comment: "Vault OIDC login already in progress")
        case .callbackTimeout:
            return NSLocalizedString("Vault OIDC login timed out. Please try again.", comment: "Vault OIDC timeout")
        case .malformedCallback(let detail):
            return String(format: NSLocalizedString("Unexpected Vault OIDC callback: %@", comment: "Vault OIDC parse error"), detail)
        case .vaultError(let e):
            return e.localizedDescription
        }
    }
}

@objcMembers final class VaultOIDCHandler: NSObject {

    private static let log = OSLog(subsystem: "com.sequel-ace.sequel-ace", category: "VaultOIDC")
    private static let callbackTimeoutSeconds: TimeInterval = 120
    private static let keychainService = "Sequel Ace Vault Token"

    // MARK: - Cancellation

    private struct ActiveLogin {
        var semaphore: DispatchSemaphore?
        var cancelled: Bool
    }

    private static let loginLock = NSLock()
    private static var activeLogins: [String: ActiveLogin] = [:]

    // Process-wide serialization of the OIDC callback port. The listener binds a
    // fixed port (8250), so only one login flow can run in the whole process at a
    // time — across every connection window and across connect/test/refresh alike.
    // login() claims this before binding the port and releases it on every exit,
    // so a second concurrent attempt fails fast with a clear message instead of a
    // cryptic EADDRINUSE (.noAvailablePort) or a timeout. Guarded by loginLock.
    private static var loginInProgress = false

    /// Atomically claim the exclusive OIDC login slot. Returns false if a login is
    /// already in flight anywhere in this process.
    private static func beginExclusiveLogin() -> Bool {
        loginLock.lock()
        defer { loginLock.unlock() }
        if loginInProgress { return false }
        loginInProgress = true
        return true
    }

    /// Release the exclusive OIDC login slot claimed by beginExclusiveLogin().
    private static func endExclusiveLogin() {
        loginLock.lock()
        loginInProgress = false
        loginLock.unlock()
    }

    /// Mark that a Vault connection is about to start OIDC work. This lets a
    /// very early UI cancel be recorded before login() has a semaphore to signal.
    @objc(prepareActiveLogin)
    static func prepareActiveLogin() -> String {
        let identifier = UUID().uuidString
        loginLock.lock()
        activeLogins[identifier] = ActiveLogin(semaphore: nil, cancelled: false)
        loginLock.unlock()
        return identifier
    }

    /// Clear a prepared login when credential generation exits before login()
    /// registers its semaphore, such as cache hits or early validation failure.
    @objc(clearPreparedActiveLoginWithIdentifier:)
    static func clearPreparedActiveLogin(identifier: String) {
        loginLock.lock()
        // Remove entries that never registered a semaphore. This includes
        // early-cancelled prepared logins after their owning attempt has
        // observed the cancellation and is exiting.
        if let state = activeLogins[identifier], state.semaphore == nil {
            activeLogins.removeValue(forKey: identifier)
        }
        loginLock.unlock()
    }

    static func clearPreparedActiveLogin() {
        loginLock.lock()
        activeLogins = activeLogins.filter { $0.value.semaphore != nil }
        loginLock.unlock()
    }

    /// Signal the active OIDC browser-wait semaphore so login() returns immediately
    /// with a .cancelled error. Safe to call from any thread at any time.
    @objc(cancelActiveLoginWithIdentifier:)
    static func cancelActiveLogin(identifier: String) {
        // Extract the semaphore under the lock, then signal after releasing it.
        // Signalling while holding loginLock would block the woken login() thread
        // (which calls clearActiveLogin → acquires loginLock) until this function
        // returns — not a deadlock, but unnecessarily delays the cancel path.
        var semaphoreToSignal: DispatchSemaphore?
        loginLock.lock()
        if var state = activeLogins[identifier] {
            state.cancelled = true
            activeLogins[identifier] = state
            semaphoreToSignal = state.semaphore
        } else {
            activeLogins[identifier] = ActiveLogin(semaphore: nil, cancelled: true)
        }
        loginLock.unlock()
        semaphoreToSignal?.signal()
    }

    static func cancelActiveLogin() {
        loginLock.lock()
        let semaphores = activeLogins.values.compactMap { $0.semaphore }
        for identifier in activeLogins.keys {
            activeLogins[identifier]?.cancelled = true
        }
        loginLock.unlock()
        semaphores.forEach { $0.signal() }
    }

    @nonobjc private static func registerActiveLogin(semaphore: DispatchSemaphore, identifier: String) {
        loginLock.lock()
        var state = activeLogins[identifier] ?? ActiveLogin(semaphore: nil, cancelled: false)
        state.semaphore = semaphore
        activeLogins[identifier] = state
        loginLock.unlock()
    }

    @nonobjc private static func clearActiveLogin(semaphore: DispatchSemaphore, identifier: String) {
        loginLock.lock()
        if activeLogins[identifier]?.semaphore === semaphore {
            activeLogins.removeValue(forKey: identifier)
        }
        loginLock.unlock()
    }

    static func isActiveLoginCancelledForTesting(identifier: String) -> Bool {
        loginLock.lock()
        defer { loginLock.unlock() }
        return activeLogins[identifier]?.cancelled == true
    }

    @nonobjc static func registerActiveLoginForTesting(semaphore: DispatchSemaphore, identifier: String) {
        registerActiveLogin(semaphore: semaphore, identifier: identifier)
    }

    @nonobjc static func clearActiveLoginForTesting(semaphore: DispatchSemaphore, identifier: String) {
        clearActiveLogin(semaphore: semaphore, identifier: identifier)
    }

    static func beginExclusiveLoginForTesting() -> Bool { return beginExclusiveLogin() }
    static func endExclusiveLoginForTesting() { endExclusiveLogin() }
    static func isLoginInProgressForTesting() -> Bool {
        loginLock.lock()
        defer { loginLock.unlock() }
        return loginInProgress
    }

    static func isActiveLoginCancelled(identifier: String) -> Bool {
        loginLock.lock()
        defer { loginLock.unlock() }
        return activeLogins[identifier]?.cancelled == true
    }

    // MARK: - Per-mount token scoping

    // Tokens stored in this map were obtained in the current process for a specific
    // Vault server and OIDC mount. The Keychain fallback is keyed by the same scope.
    private static let hostTokenLock = NSLock()
    private static var tokenByScope: [String: String] = [:]
    private static let persistedTokenLock = NSLock()
    private static var persistedTokenByScopeForTesting: [String: String]?

    /// Best available token for `baseURL` and `mount`. Checks the in-session map first,
    /// then reuses a Keychain token stored for the exact same Vault server URL and OIDC mount.
    static func cachedToken(for baseURL: URL, mount: String) -> String? {
        let scopeKey = tokenScopeKey(baseURL: baseURL, mount: mount)
        hostTokenLock.lock()
        let hostToken = tokenByScope[scopeKey]
        hostTokenLock.unlock()
        if let t = hostToken { return t }

        guard let token = readPersistedToken(for: baseURL, mount: mount) else { return nil }
        storeToken(token, for: baseURL, mount: mount)
        return token
    }

    private static func storeToken(_ token: String, for baseURL: URL, mount: String) {
        let scopeKey = tokenScopeKey(baseURL: baseURL, mount: mount)
        hostTokenLock.lock()
        defer { hostTokenLock.unlock() }
        tokenByScope[scopeKey] = token
    }

    static func clearCachedTokensForTesting() {
        hostTokenLock.lock()
        tokenByScope.removeAll()
        hostTokenLock.unlock()
    }

    static func useInMemoryTokenStoreForTesting() {
        persistedTokenLock.lock()
        persistedTokenByScopeForTesting = [:]
        persistedTokenLock.unlock()
    }

    static func clearInMemoryTokenStoreForTesting() {
        persistedTokenLock.lock()
        persistedTokenByScopeForTesting?.removeAll()
        persistedTokenLock.unlock()
    }

    static func disableInMemoryTokenStoreForTesting() {
        persistedTokenLock.lock()
        persistedTokenByScopeForTesting = nil
        persistedTokenLock.unlock()
    }

    /// Fixed callback port matching vault-plugin-auth-jwt CLIHandler default (8250).
    /// Cognito / other OIDC providers only whitelist specific redirect URIs, so
    /// a random port would fail with redirect_mismatch.
    private static let callbackPort: NWEndpoint.Port = 8250

    /// Run the full OIDC browser login flow. Blocks the calling thread until the user
    /// completes (or cancels) login, or the timeout elapses.
    /// - Returns: The new Vault token.
    static func login(baseURL: URL, mount: String, identifier suppliedIdentifier: String? = nil) throws -> String {
        // Claim the process-wide port slot before doing anything else, so a second
        // concurrent login (another window, or connect vs. refresh) fails fast with
        // a clear message rather than racing on the fixed callback port. Placed
        // before identifier setup so a rejected attempt leaves no state behind.
        guard beginExclusiveLogin() else { throw VaultOIDCError.loginInProgress }
        defer { endExclusiveLogin() }

        let loginIdentifier = suppliedIdentifier?.isEmpty == false ? suppliedIdentifier! : prepareActiveLogin()

        // 1. Start the callback listener on the fixed port 8250 (vault-plugin-auth-jwt default).
        let callbackSemaphore = DispatchSemaphore(value: 0)
        var callbackParams: [String: String]?

        let listener = try startCallbackListener(onCallback: { params in
            callbackParams = params
            callbackSemaphore.signal()
        })
        defer { listener.cancel() }
        registerActiveLogin(semaphore: callbackSemaphore, identifier: loginIdentifier)
        defer { clearActiveLogin(semaphore: callbackSemaphore, identifier: loginIdentifier) }
        guard !isActiveLoginCancelled(identifier: loginIdentifier) else { throw VaultOIDCError.cancelled }

        let redirectURI = "http://localhost:\(callbackPort.rawValue)/oidc/callback"

        // 2. Generate state and nonce client-side (mirrors vault-plugin-auth-jwt CLIHandler).
        //    Vault stores them server-side and validates them in the callback.
        let state = randomBase64URLToken()
        let nonce = randomBase64URLToken()

        // 3. Ask Vault for the authorization URL
        let authURL: URL
        do {
            authURL = try VaultClient.oidcAuthURL(baseURL: baseURL, mount: mount,
                                                  redirectURI: redirectURI, role: nil,
                                                  state: state, nonce: nonce)
        } catch {
            throw VaultOIDCError.vaultError(error)
        }

        guard !isActiveLoginCancelled(identifier: loginIdentifier) else { throw VaultOIDCError.cancelled }

        // 4. Open the browser
        DispatchQueue.main.async {
            if !isActiveLoginCancelled(identifier: loginIdentifier) {
                NSWorkspace.shared.open(authURL)
            }
        }

        // 5. Wait for callback (with timeout).
        // The semaphore was registered before the blocking auth_url request so
        // cancelActiveLogin() can interrupt either the browser wait or the setup phase.

        let result = callbackSemaphore.wait(timeout: .now() + callbackTimeoutSeconds)
        if result == .timedOut { throw VaultOIDCError.callbackTimeout }
        // A nil callbackParams means either timeout or cancellation via cancelActiveLogin().
        guard let params = callbackParams else { throw VaultOIDCError.cancelled }

        guard let callbackState = params["state"], let code = params["code"] else {
            if let error = params["error"] {
                throw VaultOIDCError.malformedCallback(error)
            }
            throw VaultOIDCError.malformedCallback("missing state or code")
        }

        // NOTE: The guard below looks correct for a standard OIDC flow, but must NOT be
        // enabled with Vault. vault-plugin-auth-jwt generates its own opaque state value
        // when building the authorization URL it sends to the OIDC provider — our
        // client-provided `state` is stored server-side as metadata (bound to the nonce,
        // redirect URI, and role), but it is NOT the value that ends up in the OIDC
        // redirect. As a result, the `state` echoed back by the OIDC provider in the
        // callback is Vault's internal state, not the one we generated here, so the
        // comparison always fails. Vault itself enforces state integrity: when we call
        // oidcCallback with `callbackState`, Vault looks it up in its own state cache and
        // rejects anything it did not issue — this is the actual CSRF protection.
        //
        // guard callbackState == state else {
        //     throw VaultOIDCError.malformedCallback("state mismatch")
        // }

        // 6. Exchange code for token.
        //    Vault validates the state server-side; nonce was registered with the auth_url request.
        let token: String
        do {
            token = try VaultClient.oidcCallback(baseURL: baseURL, mount: mount,
                                                 state: callbackState, nonce: nonce, code: code)
        } catch {
            throw VaultOIDCError.vaultError(error)
        }

        // 7. Persist in the user's Keychain for this Vault server + OIDC mount and
        //    keep an in-process copy so the token is never forwarded elsewhere.
        //
        // Note: if the caller cancels after this point (between the token exchange
        // and credential generation), the token is already in the Keychain. It is
        // NOT revoked — Vault's TTL handles expiry. The token will be reused on
        // the next connect attempt for this Vault server and OIDC mount, avoiding
        // a redundant browser login.
        saveToken(token, for: baseURL, mount: mount)
        storeToken(token, for: baseURL, mount: mount)

        // 8. Bring the app back to the foreground now that the browser auth is done.
        DispatchQueue.main.async { NSApp.activate(ignoringOtherApps: true) }

        return token
    }

    // MARK: - Token persistence

    static func saveToken(_ token: String, for baseURL: URL, mount: String) {
        let account = keychainAccount(for: baseURL, mount: mount)

        persistedTokenLock.lock()
        if persistedTokenByScopeForTesting != nil {
            persistedTokenByScopeForTesting?[account] = token
            persistedTokenLock.unlock()
            return
        }
        persistedTokenLock.unlock()

        let tokenData = Data(token.utf8)
        let baseQuery = keychainQuery(account: account)
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, [
            kSecValueData as String: tokenData
        ] as CFDictionary)

        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            os_log("Failed to update Vault token in Keychain: status=%d", log: log, type: .error, updateStatus)
            return
        }

        var addQuery = baseQuery
        addQuery[kSecValueData as String] = tokenData
        addQuery[kSecAttrLabel as String] = "Sequel Ace Vault Token"
        addQuery[kSecAttrDescription as String] = "Vault token for \(account)"
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus != errSecSuccess {
            os_log("Failed to save Vault token in Keychain: status=%d", log: log, type: .error, addStatus)
        }
    }

    private static func readPersistedToken(for baseURL: URL, mount: String) -> String? {
        let account = keychainAccount(for: baseURL, mount: mount)

        persistedTokenLock.lock()
        if let persistedTokenByScopeForTesting {
            let token = persistedTokenByScopeForTesting[account]
            persistedTokenLock.unlock()
            return token
        }
        persistedTokenLock.unlock()

        var query = keychainQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else {
            if status != errSecItemNotFound {
                os_log("Failed to read Vault token from Keychain: status=%d", log: log, type: .error, status)
            }
            return nil
        }
        guard let data = result as? Data,
              let token = String(data: data, encoding: .utf8),
              !token.isEmpty else {
            return nil
        }
        return token
    }

    private static func keychainAccount(for baseURL: URL, mount: String) -> String {
        tokenScopeKey(baseURL: baseURL, mount: mount)
    }

    private static func tokenScopeKey(baseURL: URL, mount: String) -> String {
        "\(baseURL.absoluteString)|oidc_mount=\(normalizedMount(mount))"
    }

    private static func normalizedMount(_ mount: String) -> String {
        let trimmedMount = mount.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedMount.isEmpty ? "oidc" : trimmedMount
    }

    private static func keychainQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account
        ]
    }

    static func keychainTokenExistsForTesting(baseURL: URL, mount: String) -> Bool {
        let account = keychainAccount(for: baseURL, mount: mount)
        persistedTokenLock.lock()
        if let persistedTokenByScopeForTesting {
            let exists = persistedTokenByScopeForTesting[account] != nil
            persistedTokenLock.unlock()
            return exists
        }
        persistedTokenLock.unlock()

        var query = keychainQuery(account: account)
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        return SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess
    }

    // MARK: - ObjC bridge

    /// ObjC-compatible login entry point.
    @objc(loginObjCWithBaseURL:mount:error:)
    static func loginObjC(baseURL: URL, mount: String, error errorPointer: NSErrorPointer) -> String? {
        do {
            return try login(baseURL: baseURL, mount: mount)
        } catch {
            errorPointer?.pointee = error as NSError
            return nil
        }
    }

    // MARK: - Callback listener

    private static func startCallbackListener(onCallback: @escaping ([String: String]) -> Void) throws -> NWListener {
        // Restrict to the loopback interface so the callback port is not reachable
        // from the network. requiredInterfaceType = .loopback accepts connections
        // from both 127.0.0.1 (IPv4) and ::1 (IPv6) without restricting to one
        // address family, which is important because macOS browsers may resolve
        // "localhost" to either family depending on system configuration.
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        let listener = try NWListener(using: parameters, on: callbackPort)

        let readySemaphore = DispatchSemaphore(value: 0)
        var listenerError: NWError?

        // One-shot flag — prevents a second concurrent TCP connection from invoking
        // onCallback again and racing against the semaphore consumer in login().
        var callbackFired = false
        let callbackLock = NSLock()

        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                readySemaphore.signal()
            case .failed(let error):
                listenerError = error
                readySemaphore.signal()
            case .waiting:
                // Port is temporarily unavailable — treat as a binding failure rather
                // than waiting indefinitely, which would deadlock login().
                listenerError = NWError.posix(.EADDRINUSE)
                readySemaphore.signal()
            default:
                break
            }
        }

        listener.newConnectionHandler = { connection in
            connection.start(queue: .global(qos: .utility))
            receiveHTTPRequest(on: connection) { requestLine in
                // Only process requests to the expected callback path.
                guard requestLine.hasPrefix("GET /oidc/callback") else {
                    connection.cancel()
                    return
                }
                let responseHTML = "<html><body><h2>Authentication successful. You may close this tab.</h2></body></html>"
                let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: \(responseHTML.utf8.count)\r\nConnection: close\r\n\r\n\(responseHTML)"
                connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
                    // Guard against concurrent callbacks from multiple TCP connections.
                    callbackLock.lock()
                    let alreadyFired = callbackFired
                    if !alreadyFired { callbackFired = true }
                    callbackLock.unlock()
                    guard !alreadyFired else { return }

                    let params = parseQueryParams(from: requestLine)
                    onCallback(params)
                })
            }
        }

        listener.start(queue: .global(qos: .utility))
        readySemaphore.wait()

        if listenerError != nil {
            listener.cancel()
            throw VaultOIDCError.noAvailablePort
        }

        return listener
    }

    private static func receiveHTTPRequest(on connection: NWConnection,
                                           buffer: Data = Data(),
                                           completion: @escaping (String) -> Void) {
        // Buffer chunks until we have at least the first line (terminated by \r\n).
        // A single receive() call may return only a partial chunk if the OS splits
        // the stream, which would cause parseQueryParams to silently miss state/code.
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, isComplete, error in
            var accumulated = buffer
            let receivedData = data ?? Data()
            if !receivedData.isEmpty { accumulated.append(receivedData) }

            // Check whether the first line is complete yet.
            let crlf = Data([0x0D, 0x0A]) // \r\n
            if let range = accumulated.range(of: crlf) {
                let firstLineData = accumulated[accumulated.startIndex..<range.lowerBound]
                let firstLine = String(data: firstLineData, encoding: .utf8) ?? ""
                completion(firstLine)
            } else if isComplete || error != nil || receivedData.isEmpty {
                completion("") // Closed / failed / no-progress connection.
            } else if accumulated.count < 8192 {
                // First line not yet complete — read more (cap at 8 KB to prevent abuse).
                receiveHTTPRequest(on: connection, buffer: accumulated, completion: completion)
            } else {
                completion("") // Oversized / malformed request.
            }
        }
    }

    /// Generates a cryptographically random base64url-encoded token (no padding),
    /// matching the format used by vault-plugin-auth-jwt's CLIHandler.
    static func randomBase64URLToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status != errSecSuccess {
            os_log("SecRandomCopyBytes failed: %d — falling back to arc4random", log: log, type: .fault, status)
            for i in bytes.indices { bytes[i] = UInt8(truncatingIfNeeded: arc4random()) }
        }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func parseQueryParams(from requestLine: String) -> [String: String] {
        // requestLine: "GET /oidc/callback?key=value&... HTTP/1.1"
        var params: [String: String] = [:]
        guard let queryStart = requestLine.range(of: "?"),
              let queryEnd = requestLine.range(of: " HTTP/") else { return params }
        let queryString = String(requestLine[queryStart.upperBound..<queryEnd.lowerBound])
        if let comps = URLComponents(string: "http://x?\(queryString)") {
            for item in comps.queryItems ?? [] {
                params[item.name] = item.value ?? ""
            }
        }
        return params
    }
}

extension VaultOIDCError: Equatable {
    static func == (lhs: VaultOIDCError, rhs: VaultOIDCError) -> Bool {
        switch (lhs, rhs) {
        case (.cancelled, .cancelled): return true
        case (.noAvailablePort, .noAvailablePort): return true
        case (.loginInProgress, .loginInProgress): return true
        case (.callbackTimeout, .callbackTimeout): return true
        case (.malformedCallback(let a), .malformedCallback(let b)): return a == b
        case (.vaultError, .vaultError): return true
        default: return false
        }
    }
}
