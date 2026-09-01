//
//  SASSHTunnelSocketIO.swift
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

/// The BSD-socket plumbing both ends of the tunnel/assistant channel share
/// (SSH tunnel IPC plan, Step 3). Compiled into the app, the assistant and
/// the Unit Tests target; pure Foundation + Darwin.
enum SASSHTunnelSocketIO {

    enum Error: Swift.Error, Equatable {
        /// `sockaddr_un.sun_path` holds 104 bytes including the terminator.
        case pathTooLong(Int)
    }

    /// Longest socket path (in UTF-8 bytes) that fits `sun_path`.
    static let maximumPathLength = 103

    /// The environment key the app uses to tell the assistant where its
    /// tunnel's socket is, next to `SP_CONNECTION_NAME` / `SP_CONNECTION_VERIFY_HASH`
    /// in `SPSSHTunnel.m`.
    static let pathEnvironmentKey = "SP_CONNECTION_SOCKET_PATH"

    static func address(for path: String) throws -> sockaddr_un {
        let length = path.utf8.count
        guard length <= maximumPathLength else { throw Error.pathTooLong(length) }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let capacity = maximumPathLength + 1
        withUnsafeMutablePointer(to: &address.sun_path) { tuple in
            tuple.withMemoryRebound(to: CChar.self, capacity: capacity) { destination in
                _ = strlcpy(destination, path, capacity)
            }
        }
        return address
    }

    /// A fresh AF_UNIX stream socket, or nil (errno set) on failure.
    static func makeSocket() -> Int32? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        configure(fd)
        return fd
    }

    /// Close-on-exec so ssh and its children never inherit the descriptor,
    /// and no SIGPIPE if the peer went away mid-write (the write just fails).
    static func configure(_ fd: Int32) {
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
        var one: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
    }

    static func setBlocking(_ fd: Int32, _ blocking: Bool) {
        let flags = fcntl(fd, F_GETFL)
        guard flags >= 0 else { return }
        _ = fcntl(fd, F_SETFL, blocking ? (flags & ~O_NONBLOCK) : (flags | O_NONBLOCK))
    }

    /// Reads up to and including the first newline. Returns whatever arrived
    /// before EOF when the peer closed without one, nil on a read error,
    /// timeout, an empty stream, or a line beyond `limit` bytes.
    static func readLine(_ fd: Int32, limit: Int = 64 * 1024) -> Data? {
        var line = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while line.count <= limit {
            let count = read(fd, &chunk, chunk.count)
            if count < 0 {
                if errno == EINTR { continue }
                return nil
            }
            if count == 0 {
                return line.isEmpty ? nil : line
            }
            line.append(contentsOf: chunk[0..<count])
            if let newline = line.firstIndex(of: 0x0A) {
                return line[...newline]
            }
        }
        return nil
    }

    static func writeAll(_ fd: Int32, _ data: Data) -> Bool {
        var offset = 0
        while offset < data.count {
            let written = data.withUnsafeBytes { buffer -> Int in
                guard let base = buffer.baseAddress else { return -1 }
                return write(fd, base + offset, data.count - offset)
            }
            if written < 0 {
                if errno == EINTR { continue }
                return false
            }
            offset += written
        }
        return true
    }
}
