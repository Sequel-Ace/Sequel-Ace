//
//  SASSHTunnelSecretResolver.swift
//  Sequel Ace
//
//  Created by the Sequel Ace team on August 31, 2026.
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

/// The app-side keychain lookups the SSH tunnel serves over its channel —
/// Step 3 of `docs/development/keychain-secitem-migration-plan.md` moved
/// these here from the tunnel assistant, and SPSSHTunnel calls them through
/// thin trampolines (per the language policy: new logic in Swift, a bridge
/// in the legacy file).
@objc final class SASSHTunnelSecretResolver: NSObject {

    /// The ssh askpass prompt for an encrypted key, as emitted by OpenSSH.
    /// Same pattern the tunnel's own passphrase dialog parses.
    private static let passphraseQueryPattern = "^\\s*Enter passphrase for key \\'(.*)\\':\\s*$"

    /// The password for a keychain-backed tunnel connection, resolved at ask
    /// time so the secret never has to be readable by a second process. A
    /// missing item returns nil, which the assistant turns into its
    /// keychain-specific UI fallback prompt.
    @objc(passwordForKeychainName:account:)
    static func password(forKeychainName name: String?, account: String?) -> String? {
        SAKeychainAccess.make().password(name: name, account: account)
    }

    /// The stored `"SSH"/<key name>` passphrase for an askpass query, or nil
    /// when the query is not a key-passphrase prompt or no item is stored —
    /// the caller then raises its UI prompt. The exists-then-get shape
    /// mirrors the retired assistant-side check for exact behavioural
    /// parity.
    @objc(storedPassphraseForQuery:)
    static func storedPassphrase(forQuery query: String?) -> String? {
        guard let query, let keyName = passphraseKeyName(in: query), !keyName.isEmpty else { return nil }
        let keychain = SAKeychainAccess.make()
        guard keychain.passwordExists(name: "SSH", account: keyName) else { return nil }
        return keychain.password(name: "SSH", account: keyName)
    }

    private static func passphraseKeyName(in query: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: passphraseQueryPattern),
              let match = regex.firstMatch(in: query, range: NSRange(query.startIndex..., in: query)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: query) else { return nil }
        return String(query[range])
    }

    private override init() {}
}
