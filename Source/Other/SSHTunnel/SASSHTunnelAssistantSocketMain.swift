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
    /// Returns false when the socket never carried a request — no path in the
    /// environment, or every attempt failed before anything reached the app
    /// (`SASSHTunnelSocketClient.Error.isPreSend`). The caller then runs the
    /// Distributed Objects path instead, which the app always vends alongside
    /// the socket: `SPSSHTunnel` registers its `NSConnection` and exports
    /// `SP_CONNECTION_NAME` / `SP_CONNECTION_VERIFY_HASH` whichever transport
    /// it selected. Before this, an unreachable socket failed the tunnel
    /// outright — issue #2689.
    ///
    /// Returns true once the app has been asked anything, including when the
    /// exchange then failed: the app may already be prompting the user, and a
    /// second run over another transport would ask twice. `exitCode` carries
    /// the answer in that case, and the caller returns it unchanged.
    @objc(runReturningExitCode:)
    public static func run(returningExitCode exitCode: UnsafeMutablePointer<Int32>) -> Bool {
        let environment = ProcessInfo.processInfo.environment
        let argument = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : nil

        guard let path = environment[SASSHTunnelSocketIO.EnvironmentKey.socketPath] else {
            NSLog("%@", "SSH tunnel: the socket transport was selected but no socket path was passed; using Distributed Objects")
            exitCode.pointee = 1
            return false
        }

        let reachability = Reachability()
        let outcome = SASSHTunnelAskpass.run(argument: argument, environment: environment) {
            // Whatever answers at the socket must be Apple-signed and of this
            // assistant's own team, or it is not the app (Step 4).
            var client = SASSHTunnelSocketClient(path: path)
            client.peerPolicy = SASSHTunnelPeerValidator.appPeerPolicy()
            return { request in
                do {
                    let response = try client.send(request)
                    reachability.recordReachedTheApp()
                    return response
                } catch {
                    reachability.record(error)
                    throw error
                }
            }
        }

        if let output = outcome.output {
            print(output)
        }
        exitCode.pointee = outcome.exitCode

        if outcome.exitCode != 0, reachability.neverReachedTheApp {
            NSLog("%@", "SSH tunnel: the socket transport never reached the app (\(reachability.summary)); using Distributed Objects")
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

    /// Whether the socket ever carried a request to the app. The askpass run
    /// may make several attempts (a refused password becomes a GUI prompt);
    /// only a run where *every* attempt failed pre-send, and at least one was
    /// made, is safe to repeat over Distributed Objects.
    private final class Reachability {
        private var failures: [Swift.Error] = []
        private var reachedTheApp = false

        func recordReachedTheApp() { reachedTheApp = true }

        func record(_ error: Swift.Error) {
            failures.append(error)
            if (error as? SASSHTunnelSocketClient.Error)?.isPreSend != true { reachedTheApp = true }
        }

        var neverReachedTheApp: Bool { !reachedTheApp && !failures.isEmpty }

        var summary: String {
            failures.map { String(describing: $0) }.joined(separator: ", ")
        }
    }

    private override init() {}
}
