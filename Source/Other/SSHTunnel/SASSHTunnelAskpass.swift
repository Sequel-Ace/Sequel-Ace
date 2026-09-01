//
//  SASSHTunnelAskpass.swift
//  SequelAceTunnelAssistant
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

/// What the askpass assistant does with the prompt ssh handed it — the
/// decisions of `SequelAceTunnelAssistant.m`, transport-agnostic and
/// therefore testable (SSH tunnel IPC plan, Step 3). Compiled into the
/// assistant and the Unit Tests target.
///
/// `connect` is called lazily, at most once per run, in exactly the places
/// the Objective-C original resolved its proxy; a failure there is "unable
/// to connect to Sequel Ace", exit 1. A transport error during the request
/// is also exit 1: the assistant never prints an empty line for ssh to read
/// as an empty password.
enum SASSHTunnelAskpass {

    struct Outcome: Equatable {
        /// What to print to stdout (ssh reads it as the answer), or nothing.
        var output: String?
        var exitCode: Int32
    }

    /// Keep in sync with `SPSSHTunnelPasswordMode` in `SPConstants.h`.
    enum PasswordMethod: Int {
        case usesKeychain = 0
        case asksUI = 1
        case none = 2
    }

    enum EnvironmentKey {
        static let passwordMethod = "SP_PASSWORD_METHOD"
        static let connectionName = "SP_CONNECTION_NAME"
        static let verificationHash = "SP_CONNECTION_VERIFY_HASH"
    }

    typealias Transport = (SASSHTunnelAuthRequest) throws -> SASSHTunnelAuthResponse
    typealias Connect = () throws -> Transport

    static func run(argument: String?,
                    environment: [String: String],
                    connect: Connect,
                    log: (String) -> Void = { NSLog("%@", $0) }) -> Outcome {
        guard let methodValue = environment[EnvironmentKey.passwordMethod] else {
            return Outcome(output: nil, exitCode: 1)
        }
        let connectionName = environment[EnvironmentKey.connectionName]
        let verificationHash = environment[EnvironmentKey.verificationHash]
        var argument = argument

        // A yes/no question (host key mismatches and the like).
        if let question = argument, question.contains(" (yes/no") {
            guard let transport = try? connect() else {
                log("SSH Tunnel: unable to connect to Sequel Ace to show SSH question")
                return Outcome(output: nil, exitCode: 1)
            }
            guard case .answer(let yes)? = try? transport(.question(question)) else {
                log("SSH Tunnel: unable to obtain an answer from Sequel Ace for SSH question")
                return Outcome(output: nil, exitCode: 1)
            }
            return Outcome(output: yes ? "yes" : "no", exitCode: 0)
        }

        // The SSH password itself: ask the app, which either holds it or
        // resolves it from the keychain at ask time.
        if let prompt = argument, prompt.lowercased().contains("password:") {
            // -[NSString integerValue] semantics: anything non-numeric is 0.
            let method = PasswordMethod(rawValue: Int(methodValue) ?? 0)
            if method == .usesKeychain || method == .asksUI {
                guard let connectionName, let verificationHash else {
                    log("SSH Tunnel: internal authentication specified but insufficient details supplied")
                    return Outcome(output: nil, exitCode: 1)
                }
                guard let transport = try? connect() else {
                    log("SSH Tunnel: unable to connect to Sequel Ace for internal authentication")
                    return Outcome(output: nil, exitCode: 1)
                }
                if case .secret(let password)? = try? transport(.password(verificationHash: verificationHash)) {
                    return Outcome(output: password, exitCode: 0)
                }
                // No password: explain per method and fall back to the GUI prompt.
                if method == .usesKeychain {
                    log("SSH Tunnel: specified keychain password not found")
                    argument = String(format: NSLocalizedString("The SSH password could not be loaded from the keychain; please enter the SSH password for %@:", comment: "Prompt for SSH password when keychain fetch failed"), connectionName)
                } else {
                    log("SSH Tunnel: unable to successfully request password from Sequel Ace for internal authentication")
                    argument = String(format: NSLocalizedString("The SSH password could not be loaded; please enter the SSH password for %@:", comment: "Prompt for SSH password when direct fetch failed"), connectionName)
                }
            }
        }

        // Key passphrases and anything else ssh asks go to the app's GUI
        // prompt (which serves a stored passphrase first). Also covers RSA
        // SecurID and the fallback prompts built above.
        if let query = argument {
            guard let verificationHash else {
                log("SSH Tunnel: key passphrase authentication required but insufficient details supplied to connect to GUI")
                return Outcome(output: nil, exitCode: 1)
            }
            guard let transport = try? connect() else {
                log("SSH Tunnel: unable to connect to Sequel Ace to show SSH question")
                return Outcome(output: nil, exitCode: 1)
            }
            guard case .secret(let passphrase)? = try? transport(.query(query, verificationHash: verificationHash)) else {
                return Outcome(output: nil, exitCode: 1)
            }
            return Outcome(output: passphrase, exitCode: 0)
        }

        return Outcome(output: nil, exitCode: 1)
    }
}
