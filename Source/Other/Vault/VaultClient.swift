//
//  VaultClient.swift
//  Sequel Ace
//
//  REST API wrapper for HashiCorp Vault. All methods are synchronous
//  (blocking the calling thread via DispatchSemaphore) so they can be
//  called from the background thread used by initiateMySQLConnection.
//

import Foundation
import OSLog

enum VaultClientError: Error, LocalizedError {
    case invalidBaseURL
    case networkError(Error)
    case httpError(Int, String?)
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return NSLocalizedString("Invalid Vault host or port.", comment: "Vault client error")
        case .networkError(let e):
            return e.localizedDescription
        case .httpError(let code, let detail):
            let base = String(format: NSLocalizedString("Vault returned HTTP %d.", comment: "Vault HTTP error"), code)
            if let detail = detail, !detail.isEmpty {
                return "\(base) \(detail)"
            }
            return base
        case .parseError(let detail):
            return String(format: NSLocalizedString("Vault response parse error: %@", comment: "Vault parse error"), detail)
        }
    }
}

struct VaultCredentials {
    let username: String
    let password: String
    let leaseDuration: TimeInterval
}

final class VaultClient {

    private static let log = OSLog(subsystem: "com.sequel-ace.sequel-ace", category: "VaultClient")

    // MARK: - URL helpers (static, testable)

    static func buildBaseURL(host: String, port: String) -> URL? {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty else { return nil }
        let trimmedPort = port.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectivePort = trimmedPort.isEmpty ? "443" : trimmedPort
        return URL(string: "https://\(trimmedHost):\(effectivePort)")
    }

    // MARK: - Response parsers (static, testable)

    static func parseCredentials(from data: Data) throws -> VaultCredentials {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataDict = json["data"] as? [String: Any],
              let username = dataDict["username"] as? String, !username.isEmpty,
              let password = dataDict["password"] as? String, !password.isEmpty else {
            throw VaultClientError.parseError("missing username or password in credentials response")
        }
        let leaseDuration = (json["lease_duration"] as? Double) ?? 3600
        return VaultCredentials(username: username, password: password, leaseDuration: leaseDuration)
    }

    static func parseOIDCAuthURL(from data: Data) throws -> URL {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataDict = json["data"] as? [String: Any],
              let urlString = dataDict["auth_url"] as? String,
              let url = URL(string: urlString) else {
            throw VaultClientError.parseError("missing auth_url in OIDC response")
        }
        return url
    }

    /// Extract the first error string from a Vault `{"errors":["..."]}` response body.
    static func parseVaultErrors(from data: Data?) -> String? {
        guard let data = data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let errors = json["errors"] as? [String], !errors.isEmpty else { return nil }
        return errors.joined(separator: "; ")
    }

    static func parseToken(from data: Data) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let auth = json["auth"] as? [String: Any],
              let token = auth["client_token"] as? String, !token.isEmpty else {
            throw VaultClientError.parseError("missing client_token in auth response")
        }
        return token
    }

    // MARK: - Network calls

    /// Validate a token. Returns true if valid, false if expired/invalid, throws on network error.
    static func tokenLookupSelf(baseURL: URL, token: String) throws -> Bool {
        let url = baseURL.appendingPathComponent("v1/auth/token/lookup-self")
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.httpMethod = "GET"
        request.setValue(token, forHTTPHeaderField: "X-Vault-Token")

        let (_, response, error) = synchronousDataTask(with: request)
        if let error = error {
            os_log("tokenLookupSelf network error: %{public}@", log: log, type: .error, error.localizedDescription)
            throw VaultClientError.networkError(error)
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw VaultClientError.parseError("no HTTP response")
        }
        return httpResponse.statusCode == 200
    }

    /// Fetch the OIDC authorization URL from Vault.
    /// - Parameters:
    ///   - state: Client-generated opaque state value (mirrors vault-plugin-auth-jwt CLIHandler).
    ///   - nonce: Client-generated nonce (mirrors vault-plugin-auth-jwt CLIHandler).
    static func oidcAuthURL(baseURL: URL, mount: String, redirectURI: String, role: String?,
                            state: String, nonce: String) throws -> URL {
        let trimmedMount = mount.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveMount = trimmedMount.isEmpty ? "oidc" : trimmedMount
        let url = baseURL.appendingPathComponent("v1/auth/\(effectiveMount)/oidc/auth_url")
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = [
            "redirect_uri": redirectURI,
            "state": state,
            "nonce": nonce,
        ]
        if let role = role, !role.isEmpty { body["role"] = role }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let (data, response, error) = synchronousDataTask(with: request)
        if let error = error {
            os_log("oidcAuthURL network error: %{public}@", log: log, type: .error, error.localizedDescription)
            throw VaultClientError.networkError(error)
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw VaultClientError.parseError("no HTTP response")
        }
        guard httpResponse.statusCode == 200, let data = data else {
            os_log("oidcAuthURL HTTP error: %d", log: log, type: .error, httpResponse.statusCode)
            throw VaultClientError.httpError(httpResponse.statusCode, nil)
        }
        return try parseOIDCAuthURL(from: data)
    }

    /// Exchange OIDC callback parameters for a Vault token.
    static func oidcCallback(baseURL: URL, mount: String, state: String, nonce: String, code: String) throws -> String {
        let trimmedMount = mount.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveMount = trimmedMount.isEmpty ? "oidc" : trimmedMount
        guard var components = URLComponents(url: baseURL.appendingPathComponent("v1/auth/\(effectiveMount)/oidc/callback"), resolvingAgainstBaseURL: false) else {
            throw VaultClientError.invalidBaseURL
        }
        components.queryItems = [
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "nonce", value: nonce),
            URLQueryItem(name: "code", value: code)
        ]
        guard let url = components.url else { throw VaultClientError.invalidBaseURL }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.httpMethod = "GET"

        let (data, response, error) = synchronousDataTask(with: request)
        if let error = error {
            os_log("oidcCallback network error: %{public}@", log: log, type: .error, error.localizedDescription)
            throw VaultClientError.networkError(error)
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw VaultClientError.parseError("no HTTP response")
        }
        guard httpResponse.statusCode == 200, let data = data else {
            os_log("oidcCallback HTTP error: %d", log: log, type: .error, httpResponse.statusCode)
            throw VaultClientError.httpError(httpResponse.statusCode, nil)
        }
        return try parseToken(from: data)
    }

    /// Generate ephemeral database credentials.
    static func generateCredentials(baseURL: URL, credPath: String, token: String) throws -> VaultCredentials {
        let path = credPath.hasPrefix("/") ? String(credPath.dropFirst()) : credPath
        let url = baseURL.appendingPathComponent("v1/\(path)")
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.httpMethod = "GET"
        request.setValue(token, forHTTPHeaderField: "X-Vault-Token")

        let (data, response, error) = synchronousDataTask(with: request)
        if let error = error {
            os_log("generateCredentials network error: %{public}@", log: log, type: .error, error.localizedDescription)
            throw VaultClientError.networkError(error)
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw VaultClientError.parseError("no HTTP response")
        }
        guard httpResponse.statusCode == 200, let data = data else {
            let vaultDetail = parseVaultErrors(from: data)
            os_log("generateCredentials HTTP error: %d%{public}@", log: log, type: .error,
                   httpResponse.statusCode, vaultDetail.map { " – \($0)" } ?? "")
            throw VaultClientError.httpError(httpResponse.statusCode, vaultDetail)
        }
        return try parseCredentials(from: data)
    }

    // MARK: - Synchronous helper

    private static func synchronousDataTask(with request: URLRequest) -> (Data?, URLResponse?, Error?) {
        var resultData: Data?
        var resultResponse: URLResponse?
        var resultError: Error?
        let semaphore = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { data, response, error in
            resultData = data
            resultResponse = response
            resultError = error
            semaphore.signal()
        }.resume()
        semaphore.wait()
        return (resultData, resultResponse, resultError)
    }
}
