//
//  SASSHTunnelSocketClient.swift
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

/// The assistant's end of the socket transport (SSH tunnel IPC plan,
/// Step 3): connect, validate the peer, send one request, read one reply.
/// Compiled into the assistant and the Unit Tests target.
struct SASSHTunnelSocketClient {

    /// Decides whether the connected socket's peer is the app. The shipping
    /// policy is `SASSHTunnelPeerValidator.appPeerPolicy()` (Step 4); tests
    /// inject their own.
    typealias PeerPolicy = (Int32) -> Bool

    enum Error: Swift.Error, Equatable {
        case socketFailed(Int32)
        case connectFailed(Int32)
        /// The listener did not pass `peerPolicy`; nothing was sent.
        case peerRejected
        case sendFailed(Int32)
        /// The app closed without answering — it refused the connection or
        /// could not read the request. Fail closed.
        case noReply
        case malformedReply(SASSHTunnelAuthWireError)
    }

    let path: String
    var peerPolicy: PeerPolicy = { _ in true }

    func send(_ request: SASSHTunnelAuthRequest) throws -> SASSHTunnelAuthResponse {
        guard let fd = SASSHTunnelSocketIO.makeSocket() else { throw Error.socketFailed(errno) }
        defer { Darwin.close(fd) }

        let connected = try SASSHTunnelSocketIO.performSocketCall(at: path) { Darwin.connect(fd, $0, $1) }
        guard connected.result == 0 else { throw Error.connectFailed(connected.errno) }
        guard peerPolicy(fd) else { throw Error.peerRejected }

        guard SASSHTunnelSocketIO.writeAll(fd, SASSHTunnelAuthWire.encode(request)) else {
            throw Error.sendFailed(errno)
        }
        // The reply has no timeout: the app may be waiting on the user.
        guard let line = SASSHTunnelSocketIO.readLine(fd) else { throw Error.noReply }
        do {
            return try SASSHTunnelAuthWire.decodeResponse(line)
        } catch let wireError as SASSHTunnelAuthWireError {
            throw Error.malformedReply(wireError)
        }
    }
}
