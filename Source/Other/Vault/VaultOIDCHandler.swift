//
//  VaultOIDCHandler.swift
//  Sequel Ace
//
//  Handles the browser-based OIDC login flow. Binds a local HTTP server on
//  a random port, opens the Vault OIDC auth URL in the system browser, waits
//  for the callback, exchanges the code for a Vault token, and persists it
//  to ~/.vault-token (mode 0600).
//

import Foundation
import Network
import AppKit
import OSLog

enum VaultOIDCError: Error, LocalizedError {
    case cancelled
    case noAvailablePort
    case callbackTimeout
    case malformedCallback(String)
    case vaultError(Error)

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return NSLocalizedString("Vault login was cancelled.", comment: "Vault OIDC cancelled")
        case .noAvailablePort:
            return NSLocalizedString("Could not bind a local port for the Vault OIDC callback.", comment: "Vault OIDC port error")
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
    private static let vaultTokenFileName = ".vault-token"
    /// Fixed callback port matching vault-plugin-auth-jwt CLIHandler default (8250).
    /// Cognito / other OIDC providers only whitelist specific redirect URIs, so
    /// a random port would fail with redirect_mismatch.
    private static let callbackPort: NWEndpoint.Port = 8250

    /// Run the full OIDC browser login flow. Blocks the calling thread until the user
    /// completes (or cancels) login, or the timeout elapses.
    /// - Returns: The new Vault token.
    static func login(baseURL: URL, mount: String) throws -> String {
        // 1. Start the callback listener on the fixed port 8250 (vault-plugin-auth-jwt default).
        let callbackSemaphore = DispatchSemaphore(value: 0)
        var callbackParams: [String: String]?

        let listener = try startCallbackListener(onCallback: { params in
            callbackParams = params
            callbackSemaphore.signal()
        })
        defer { listener.cancel() }

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

        // 4. Open the browser
        DispatchQueue.main.async {
            NSWorkspace.shared.open(authURL)
        }

        // 5. Wait for callback (with timeout)
        let result = callbackSemaphore.wait(timeout: .now() + callbackTimeoutSeconds)
        if result == .timedOut { throw VaultOIDCError.callbackTimeout }
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

        // 7. Persist to ~/.vault-token (mode 0600, shared with vault CLI)
        saveToken(token)

        // 8. Bring the app back to the foreground now that the browser auth is done.
        DispatchQueue.main.async { NSApp.activate(ignoringOtherApps: true) }

        return token
    }

    // MARK: - Token persistence

    static func tokenFilePath() -> String {
        let home = NSHomeDirectory()
        return (home as NSString).appendingPathComponent(vaultTokenFileName)
    }

    static func saveToken(_ token: String) {
        let path = tokenFilePath()
        // ~/.vault-token is the conventional location shared with the Vault CLI.
        // We use this instead of the Keychain so tokens are interoperable with the
        // Vault CLI without extra setup.
        // Open with O_CREAT so mode 0600 is applied at creation time by the kernel —
        // avoids the race window that exists when writing and then calling setAttributes.
        let fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0o600)
        guard fd >= 0 else {
            os_log("Failed to open ~/.vault-token for writing: errno=%d", log: log, type: .error, Darwin.errno)
            return
        }
        defer { close(fd) }
        // Enforce 0600 even if the file already existed — O_CREAT mode only applies at creation time.
        if fchmod(fd, 0o600) != 0 {
            os_log("Failed to set ~/.vault-token permissions: errno=%d", log: log, type: .error, Darwin.errno)
        }
        let data = Data(token.utf8)
        guard !data.isEmpty else { return }
        var totalWritten = 0
        data.withUnsafeBytes { buffer in
            while totalWritten < buffer.count {
                let n = write(fd, buffer.baseAddress!.advanced(by: totalWritten), buffer.count - totalWritten)
                if n <= 0 {
                    os_log("Failed to write ~/.vault-token: errno=%d", log: log, type: .error, Darwin.errno)
                    return
                }
                totalWritten += n
            }
        }
    }

    static func readCachedToken() -> String? {
        let path = tokenFilePath()
        guard let data = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        let token = data.trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty ? nil : token
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
        let parameters = NWParameters.tcp
        let listener = try NWListener(using: parameters, on: callbackPort)

        let readySemaphore = DispatchSemaphore(value: 0)
        var listenerError: NWError?

        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                readySemaphore.signal()
            case .failed(let error):
                listenerError = error
                readySemaphore.signal()
            default:
                break
            }
        }

        listener.newConnectionHandler = { connection in
            connection.start(queue: .global(qos: .utility))
            receiveHTTPRequest(on: connection) { requestLine in
                let responseHTML = "<html><body><h2>Authentication successful. You may close this tab.</h2></body></html>"
                let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: \(responseHTML.utf8.count)\r\nConnection: close\r\n\r\n\(responseHTML)"
                connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
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

    private static func receiveHTTPRequest(on connection: NWConnection, completion: @escaping (String) -> Void) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, _, _ in
            guard let data = data, let request = String(data: data, encoding: .utf8) else {
                completion("")
                return
            }
            let firstLine = request.components(separatedBy: "\r\n").first ?? ""
            completion(firstLine)
        }
    }

    /// Generates a cryptographically random base64url-encoded token (no padding),
    /// matching the format used by vault-plugin-auth-jwt's CLIHandler.
    static func randomBase64URLToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
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
        case (.callbackTimeout, .callbackTimeout): return true
        case (.malformedCallback(let a), .malformedCallback(let b)): return a == b
        case (.vaultError, .vaultError): return true
        default: return false
        }
    }
}
