//
//  SASSHTunnelAuthService.swift
//  Sequel Ace
//
//  Created by the Sequel Ace team on September 1, 2026.
//  Copyright (c) 2026 Sequel-Ace. All rights reserved.
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
//  More info at <https://github.com/Sequel-Ace/Sequel-Ace>

import Foundation

/// The object the SSH tunnel vends to its askpass assistant — Step 1 of
/// `docs/development/ssh-tunnel-xpc-migration-plan.md`.
///
/// Before this, `SPSSHTunnel` handed *itself* to the connection, exposing
/// every method it has to whatever held the proxy. This façade exposes
/// exactly the three calls the assistant makes, and owns the decisions
/// behind them: the verification-hash check, the keychain-versus-held
/// password branch, the stored-passphrase lookup and the cancelled-prompt
/// refusal. The tunnel supplies state and the blocking sheets through
/// `SASSHTunnelAuthSource`.
///
/// Held weakly: the tunnel owns the service, not the other way round. A
/// call that arrives after the tunnel is gone fails closed (`false` /
/// nil) rather than crashing or blocking.
@objc final class SASSHTunnelAuthService: NSObject {

    /// The ssh askpass prompt for an encrypted key, as emitted by OpenSSH.
    /// Same pattern the tunnel's own passphrase dialog parses.
    private static let passphraseQueryPattern = "^\\s*Enter passphrase for key \\'(.*)\\':\\s*$"

    private weak var source: SASSHTunnelAuthSource?
    private let keychain: SAKeychainProviding

    @objc init(source: SASSHTunnelAuthSource, keychain: SAKeychainProviding) {
        self.source = source
        self.keychain = keychain
    }

    // MARK: - The vended surface

    /// Answers a yes/no question (host key mismatches and the like) by
    /// running the tunnel's question sheet. No hash check, as before: the
    /// answer is not a secret.
    @objc(getResponseForQuestion:)
    func response(forQuestion question: String?) -> Bool {
        guard let source, let question else { return false }
        return source.promptForResponse(toQuestion: question)
    }

    /// The SSH password: resolved from the keychain at ask time in keychain
    /// mode, otherwise the password held in memory. nil unless the caller
    /// presents the tunnel's verification hash.
    @objc(getPasswordWithVerificationHash:)
    func password(verificationHash: String?) -> String? {
        guard let source, verificationHash == source.verificationHash else { return nil }
        if source.usesKeychainPassword {
            return keychain.password(name: source.keychainItemName, account: source.keychainItemAccount)
        }
        return source.heldPassword
    }

    /// Key passphrases and any other prompt ssh raises. Refused (nil)
    /// without the verification hash or once the user has cancelled a
    /// prompt; a passphrase stored under `"SSH"/<key name>` is served
    /// without prompting; everything else runs the password sheet.
    @objc(getPasswordForQuery:verificationHash:)
    func password(forQuery query: String?, verificationHash: String?) -> String? {
        guard let source, verificationHash == source.verificationHash, let query else { return nil }
        if source.passwordPromptCancelled { return nil }
        if let stored = storedPassphrase(forQuery: query) { return stored }
        return source.promptForPassword(forQuery: query)
    }

    // MARK: - Wire dispatch

    /// The socket transport's entry point: one request in, one response out,
    /// mapped onto the three calls above. Transport-agnostic on purpose so
    /// the server stays plumbing only (SSH tunnel IPC plan, Step 2).
    func handle(_ request: SASSHTunnelAuthRequest) -> SASSHTunnelAuthResponse {
        switch request {
        case .question(let text):
            return .answer(response(forQuestion: text))
        case .password(let verificationHash):
            return password(verificationHash: verificationHash).map { .secret($0) } ?? .refused
        case .query(let text, let verificationHash):
            return password(forQuery: text, verificationHash: verificationHash).map { .secret($0) } ?? .refused
        }
    }

    // MARK: - Stored passphrases

    /// The stored `"SSH"/<key name>` passphrase for an askpass query, or nil
    /// when the query is not a key-passphrase prompt or no item is stored.
    /// The exists-then-get shape mirrors the retired assistant-side check
    /// for exact behavioural parity.
    func storedPassphrase(forQuery query: String) -> String? {
        guard let keyName = Self.passphraseKeyName(in: query), !keyName.isEmpty else { return nil }
        guard keychain.passwordExists(name: "SSH", account: keyName) else { return nil }
        return keychain.password(name: "SSH", account: keyName)
    }

    static func passphraseKeyName(in query: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: passphraseQueryPattern),
              let match = regex.firstMatch(in: query, range: NSRange(query.startIndex..., in: query)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: query) else { return nil }
        return String(query[range])
    }
}
