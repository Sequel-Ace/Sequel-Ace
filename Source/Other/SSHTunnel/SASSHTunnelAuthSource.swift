//
//  SASSHTunnelAuthSource.swift
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

/// What `SASSHTunnelAuthService` needs from the SSH tunnel it fronts:
/// the per-launch secret, the configured password source, and the two
/// blocking UI prompts. `SPSSHTunnel` implements it; tests implement a
/// fake.
///
/// Pure Foundation so the service and its tests compile into the
/// Unit Tests target (which has no bridging header and cannot see
/// `SPSSHTunnel`).
@objc(SASSHTunnelAuthSource)
protocol SASSHTunnelAuthSource: AnyObject {

    /// The per-tunnel secret handed to ssh's environment as
    /// `SP_CONNECTION_VERIFY_HASH`; the assistant must echo it back on the
    /// two password requests.
    @objc var verificationHash: String { get }

    /// The password kept in memory when the tunnel was configured with
    /// `setPassword:`, nil otherwise.
    @objc var heldPassword: String? { get }

    /// True when the tunnel was configured with `setPasswordKeychainName:account:`
    /// and the password is resolved from the keychain at ask time.
    @objc var usesKeychainPassword: Bool { get }

    /// The keychain item the password lives under in keychain mode.
    @objc var keychainItemName: String? { get }
    @objc var keychainItemAccount: String? { get }

    /// True once the user has cancelled a password prompt; later password
    /// requests are refused without prompting again.
    @objc var passwordPromptCancelled: Bool { get }

    /// Runs the yes/no question sheet and blocks until it is answered or
    /// dismissed by teardown (which answers "no").
    @objc(promptForResponseToQuestion:)
    func promptForResponse(toQuestion question: String) -> Bool

    /// Runs the password sheet and blocks until it is answered, cancelled
    /// (nil) or dismissed by teardown (nil).
    @objc(promptForPasswordForQuery:)
    func promptForPassword(forQuery query: String) -> String?
}
