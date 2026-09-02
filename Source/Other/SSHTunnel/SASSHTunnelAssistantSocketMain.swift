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

    /// Runs the askpass exchange and returns the process exit code, having
    /// printed the answer (if any) to stdout for ssh.
    @objc public static func run() -> Int32 {
        let environment = ProcessInfo.processInfo.environment
        let argument = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : nil

        let outcome = SASSHTunnelAskpass.run(argument: argument, environment: environment) {
            guard let path = environment[SASSHTunnelSocketIO.EnvironmentKey.socketPath] else {
                throw MissingSocketPath()
            }
            // Whatever answers at the socket must be Apple-signed and of this
            // assistant's own team, or it is not the app (Step 4).
            var client = SASSHTunnelSocketClient(path: path)
            client.peerPolicy = SASSHTunnelPeerValidator.appPeerPolicy()
            return { try client.send($0) }
        }

        if let output = outcome.output {
            print(output)
        }
        return outcome.exitCode
    }

    private struct MissingSocketPath: Error {}

    private override init() {}
}
