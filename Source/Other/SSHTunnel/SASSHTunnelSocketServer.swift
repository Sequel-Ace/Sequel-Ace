//
//  SASSHTunnelSocketServer.swift
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

/// The app's end of the socket transport (SSH tunnel IPC plan, Step 3): a
/// per-tunnel UNIX domain socket in the sandbox container that the
/// sandbox-inheriting askpass assistant connects to, one request per
/// connection.
///
/// Transport only. Every accepted connection is checked by `peerPolicy`,
/// read, decoded, handed to `handler`, answered and closed; the decisions
/// live in `SASSHTunnelAuthService`. A connection the policy rejects, or
/// whose request does not decode, is closed without a reply — the assistant
/// reads EOF and fails closed.
@objc final class SASSHTunnelSocketServer: NSObject {

    typealias Handler = (SASSHTunnelAuthRequest) -> SASSHTunnelAuthResponse

    /// Decides whether the accepted connection on `fd` may be served. The
    /// shipping policy is `SASSHTunnelPeerValidator.assistantPeerPolicy()`
    /// (Step 4); tests inject their own.
    typealias PeerPolicy = (Int32) -> Bool

    enum Error: Swift.Error, Equatable {
        case noUsableDirectory
        case socketFailed(Int32)
        case bindFailed(Int32)
        case listenFailed(Int32)
    }

    /// Seconds an accepted connection may take to deliver its request line.
    /// The reply has no timeout: it waits for the user to answer a prompt.
    static let requestTimeout: Int = 10

    /// The socket's path, handed to ssh under `pathEnvironmentKey`.
    @objc let path: String

    @objc static let pathEnvironmentKey = SASSHTunnelSocketIO.pathEnvironmentKey

    private let listeningDescriptor: Int32
    private let handler: Handler
    private let peerPolicy: PeerPolicy
    private let acceptQueue = DispatchQueue(label: "com.sequel-ace.ssh-tunnel.socket.accept")
    private let serviceQueue = DispatchQueue(label: "com.sequel-ace.ssh-tunnel.socket.serve", attributes: .concurrent)
    private var acceptSource: DispatchSourceRead?
    private let stateLock = NSLock()
    private var isClosed = false

    /// Candidate directories, shortest usable first. Under the sandbox
    /// `NSTemporaryDirectory()` is the container's tmp, which the
    /// `com.apple.security.inherit` assistant shares.
    static func candidateDirectories() -> [String] {
        [NSTemporaryDirectory()]
    }

    /// The socket name is short on purpose: `sun_path` allows 103 bytes and
    /// the container tmp already takes 62 plus the user name; up to a 26-byte
    /// user name the full path fits, beyond that the socket is reached
    /// relative to its directory (see `SASSHTunnelSocketIO.performSocketCall`).
    static func socketFileName() -> String {
        "s-" + String((0..<4).map { _ in String(format: "%02x", Int.random(in: 0...255)) }.joined()) + ".sock"
    }

    /// Our socket names, current shape and the pre-flip `ssh-` one, so a
    /// sweep after an update still clears the older leftovers.
    static func isOwnSocketName(_ name: String) -> Bool {
        name.range(of: "^(s|ssh)-[0-9a-f]+\\.sock$", options: .regularExpression) != nil
    }

    /// Removes sockets a previous app process left behind (a crash or a
    /// kill skips `close()`): anything in the naming scheme that refuses a
    /// connection. A live socket accepts, so it is left alone — its server
    /// just sees one empty connection.
    static func sweepStaleSockets(in directory: String) {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory) else { return }
        for name in names where isOwnSocketName(name) {
            let candidate = (directory as NSString).appendingPathComponent(name)
            guard let fd = SASSHTunnelSocketIO.makeSocket() else { continue }
            let outcome = try? SASSHTunnelSocketIO.performSocketCall(at: candidate) { Darwin.connect(fd, $0, $1) }
            Darwin.close(fd)
            if let outcome, outcome.result != 0, outcome.errno == ECONNREFUSED {
                unlink(candidate)
            }
        }
    }

    /// Objective-C entry: serve a tunnel's `SASSHTunnelAuthService`, admitting
    /// only a connecting process that is Apple-signed, of this app's team and
    /// named as the tunnel assistant.
    @objc convenience init(service: SASSHTunnelAuthService) throws {
        try self.init(handler: service.handle, peerPolicy: SASSHTunnelPeerValidator.assistantPeerPolicy())
    }

    init(directories: [String] = SASSHTunnelSocketServer.candidateDirectories(),
         handler: @escaping Handler,
         peerPolicy: @escaping PeerPolicy = { _ in true }) throws {
        self.handler = handler
        self.peerPolicy = peerPolicy

        // The first directory offered; a long path is fine, the bind below
        // goes relative to the directory when the full path does not fit.
        guard let directory = directories.first else { throw Error.noUsableDirectory }
        let base = directory.hasSuffix("/") ? directory : directory + "/"
        let path = base + Self.socketFileName()
        self.path = path
        Self.sweepStaleSockets(in: directory)

        guard let fd = SASSHTunnelSocketIO.makeSocket() else { throw Error.socketFailed(errno) }
        let bound: (result: Int32, errno: Int32)
        do {
            bound = try SASSHTunnelSocketIO.performSocketCall(at: path) { Darwin.bind(fd, $0, $1) }
        } catch {
            Darwin.close(fd)
            throw error
        }
        guard bound.result == 0 else {
            Darwin.close(fd)
            throw Error.bindFailed(bound.errno)
        }
        // Belt and braces: the container is private already, the socket
        // file is owner-only regardless of umask.
        chmod(path, 0o600)
        // One askpass launch at a time is the real load; the backlog is generous
        // because macOS refuses (rather than queues) connects beyond it.
        guard Darwin.listen(fd, 32) == 0 else {
            let code = errno
            Darwin.close(fd)
            unlink(path)
            throw Error.listenFailed(code)
        }
        SASSHTunnelSocketIO.setBlocking(fd, false)
        listeningDescriptor = fd
        super.init()

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: acceptQueue)
        source.setEventHandler { [weak self] in self?.acceptPending() }
        source.setCancelHandler {
            Darwin.close(fd)
            unlink(path)
        }
        source.resume()
        acceptSource = source
    }

    deinit {
        close()
    }

    /// Stops accepting, closes the listening socket and removes its file.
    /// Connections already being served finish on their own.
    @objc func close() {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard !isClosed else { return }
        isClosed = true
        acceptSource?.cancel()
        acceptSource = nil
    }

    // MARK: - Accepting

    private func acceptPending() {
        while true {
            let client = Darwin.accept(listeningDescriptor, nil, nil)
            if client < 0 {
                if errno == EINTR { continue }
                return  // EWOULDBLOCK: backlog drained; anything else: give up for now
            }
            SASSHTunnelSocketIO.configure(client)
            SASSHTunnelSocketIO.setBlocking(client, true)
            serviceQueue.async { [handler, peerPolicy] in
                Self.serve(client, handler: handler, peerPolicy: peerPolicy)
            }
        }
    }

    // MARK: - Serving one connection

    private static func serve(_ client: Int32, handler: Handler, peerPolicy: PeerPolicy) {
        defer { Darwin.close(client) }

        guard peerPolicy(client) else {
            NSLog("SSH tunnel: rejected an askpass connection that failed peer validation")
            return
        }

        var timeout = timeval(tv_sec: requestTimeout, tv_usec: 0)
        _ = setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        guard let line = SASSHTunnelSocketIO.readLine(client) else {
            NSLog("SSH tunnel: askpass connection sent no request")
            return
        }
        let request: SASSHTunnelAuthRequest
        do {
            request = try SASSHTunnelAuthWire.decodeRequest(line)
        } catch {
            NSLog("SSH tunnel: askpass request not understood (%@)", "\(error)")
            return
        }

        let response = handler(request)
        if !SASSHTunnelSocketIO.writeAll(client, SASSHTunnelAuthWire.encode(response)) {
            NSLog("SSH tunnel: could not deliver the askpass reply (errno %d)", errno)
        }
    }
}
