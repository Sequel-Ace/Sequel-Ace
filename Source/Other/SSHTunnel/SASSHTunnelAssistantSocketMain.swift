//
//  SASSHTunnelAssistantSocketMain.swift
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

/// The assistant's socket-transport entry point, called from
/// `SequelAceTunnelAssistant.m`'s `main` when the app selected the socket
/// (SSH tunnel IPC plan, Step 3). Assistant target only.
///
/// `public` because the assistant has no bridging header, so only public
/// Swift reaches its generated `sequel-ace-Swift.h`.
@objc public final class SASSHTunnelAssistantSocketMain: NSObject {

    /// True when the app asked for the socket transport in ssh's environment.
    @objc public static func isSelectedInEnvironment() -> Bool {
        ProcessInfo.processInfo.environment[SASSHTunnelSocketIO.EnvironmentKey.transport] == SASSHTunnelSocketIO.TransportValue.socket
    }

    /// Runs the askpass exchange over the socket.
    ///
    /// Returns false when the run can safely be repeated over Distributed
    /// Objects — no socket path in the environment, or it failed without any
    /// prompt having been put in front of the user. The caller then runs the
    /// DO path, which the app always vends alongside the socket:
    /// `SPSSHTunnel` registers its `NSConnection` and exports
    /// `SP_CONNECTION_NAME` / `SP_CONNECTION_VERIFY_HASH` whichever transport
    /// it selected. Before this, an unusable socket failed the tunnel
    /// outright — issue #2689.
    ///
    /// Returns true when the run succeeded, or when repeating it might ask
    /// the user something twice. `exitCode` carries the answer either way and
    /// the caller returns it unchanged.
    @objc(runReturningExitCode:)
    public static func run(returningExitCode exitCode: UnsafeMutablePointer<Int32>) -> Bool {
        let environment = ProcessInfo.processInfo.environment
        let argument = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : nil

        guard let path = environment[SASSHTunnelSocketIO.EnvironmentKey.socketPath] else {
            NSLog("%@", "SSH tunnel: the socket transport was selected but no socket path was passed; using Distributed Objects")
            exitCode.pointee = 1
            return false
        }

        let attempts = Attempts()
        let outcome = SASSHTunnelAskpass.run(argument: argument, environment: environment) {
            // Whatever answers at the socket must be Apple-signed and of this
            // assistant's own team, or it is not the app (Step 4).
            var client = SASSHTunnelSocketClient(path: path)
            client.peerPolicy = SASSHTunnelPeerValidator.appPeerPolicy()
            return { request in
                do {
                    let response = try client.send(request)
                    attempts.recordSuccess(of: request)
                    return response
                } catch {
                    attempts.recordFailure(error, of: request)
                    throw error
                }
            }
        }

        if let output = outcome.output {
            print(output)
        }
        exitCode.pointee = outcome.exitCode

        if outcome.exitCode != 0, attempts.isSafeToRepeatOnAnotherTransport {
            NSLog("%@", "SSH tunnel: the socket transport failed without prompting (\(attempts.summary)); using Distributed Objects")
            return false
        }
        return true
    }

    /// Runs the exchange and returns the process exit code, without the
    /// fallback signal. Kept for callers that cannot take the out-parameter.
    @objc public static func run() -> Int32 {
        var exitCode: Int32 = 1
        _ = run(returningExitCode: &exitCode)
        return exitCode
    }

    /// Tracks whether repeating the whole askpass run over another transport
    /// could ask the user something a second time.
    ///
    /// One run can make several attempts — a refused password becomes a GUI
    /// prompt — and a repeat redoes all of them, so a single prompting
    /// request anywhere in the run is enough to rule it out. A request is
    /// only harmless if it never reached the app (`isPreSend`) or cannot
    /// prompt at all (`SASSHTunnelAuthRequest.mayPromptTheUser`); the latter
    /// is what makes issue #2689's failure recoverable, since a `password`
    /// request is an idempotent keychain read whose `noReply` would otherwise
    /// be indistinguishable from a lost reply to a prompt.
    private final class Attempts {
        private var failures: [Swift.Error] = []
        private var mayHavePrompted = false

        func recordSuccess(of request: SASSHTunnelAuthRequest) {
            // It reached the app, so a prompting request has now prompted.
            if request.mayPromptTheUser { mayHavePrompted = true }
        }

        func recordFailure(_ error: Swift.Error, of request: SASSHTunnelAuthRequest) {
            failures.append(error)
            let neverReachedTheApp = (error as? SASSHTunnelSocketClient.Error)?.isPreSend == true
            if request.mayPromptTheUser && !neverReachedTheApp { mayHavePrompted = true }
        }

        var isSafeToRepeatOnAnotherTransport: Bool { !mayHavePrompted && !failures.isEmpty }

        var summary: String {
            failures.map { String(describing: $0) }.joined(separator: ", ")
        }
    }

    private override init() {}
}
