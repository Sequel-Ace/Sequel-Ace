//
//  SASSHTunnelTransport.swift
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

/// Which channel a tunnel's askpass assistant answers over (SSH tunnel IPC
/// plan, Step 3). Selected once per tunnel from a hidden preference and
/// handed to ssh in its environment, so a tunnel never changes transport
/// mid-life and support can flip the default without a rebuild. The socket
/// is the default since Step 5; the rollback to Distributed Objects is:
///
///     defaults write com.sequel-ace.sequel-ace SPSSHTunnelUseSocketTransport -bool NO
///
/// App and Unit Tests targets.
@objc enum SASSHTunnelTransport: Int {
    case distributedObjects
    case socket

    /// The value written to `SP_CONNECTION_TRANSPORT`.
    var environmentValue: String {
        switch self {
        case .distributedObjects: return SASSHTunnelSocketIO.TransportValue.distributedObjects
        case .socket: return SASSHTunnelSocketIO.TransportValue.socket
        }
    }
}

@objc final class SASSHTunnelTransportSelection: NSObject {

    /// Hidden preference: a Bool. Absent means `defaultTransport`.
    static let defaultsKey = "SPSSHTunnelUseSocketTransport"

    /// What a fresh install gets: the socket transport (Step 5, first
    /// release). Distributed Objects remains selectable as the rollback until
    /// Step 5's second release deletes it.
    static let defaultTransport: SASSHTunnelTransport = .socket

    @objc static let transportEnvironmentKey = SASSHTunnelSocketIO.EnvironmentKey.transport
    @objc static let socketPathEnvironmentKey = SASSHTunnelSocketIO.EnvironmentKey.socketPath

    static func selectedTransport(from defaults: UserDefaults) -> SASSHTunnelTransport {
        guard defaults.object(forKey: defaultsKey) != nil else { return defaultTransport }
        return defaults.bool(forKey: defaultsKey) ? .socket : .distributedObjects
    }

    @objc static func selectedTransport() -> SASSHTunnelTransport {
        selectedTransport(from: .standard)
    }

    @objc(environmentValueForTransport:)
    static func environmentValue(for transport: SASSHTunnelTransport) -> String {
        transport.environmentValue
    }

    private override init() {}
}
