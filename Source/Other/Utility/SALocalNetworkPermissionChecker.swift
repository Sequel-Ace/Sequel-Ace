//
//  Created by Codex on 2026-02-25.
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import Foundation
import Network

@objcMembers final class SALocalNetworkPermissionChecker: NSObject {
    /// Performs a short Network.framework probe for the provided endpoint and
    /// returns true when the system reports Local Network access is denied.
    static func isLocalNetworkAccessDenied(forHost host: String, port: Int, timeout: TimeInterval = 1.5) -> Bool {
        guard #available(macOS 15.0, *) else { return false }

        let trimmedHost = normalizedHost(host)
        guard !trimmedHost.isEmpty else { return false }
        guard (1...65535).contains(port), let endpointPort = NWEndpoint.Port(rawValue: UInt16(port)) else { return false }

        let endpointHost = NWEndpoint.Host(trimmedHost)
        let connection = NWConnection(host: endpointHost, port: endpointPort, using: .tcp)
        let queue = DispatchQueue(label: "com.sequel-ace.local-network-permission-check")
        let semaphore = DispatchSemaphore(value: 0)

        var localNetworkDenied = false
        var didComplete = false

        func finish() {
            if didComplete {
                return
            }
            didComplete = true
            semaphore.signal()
        }

        connection.stateUpdateHandler = { [weak connection] state in
            switch state {
            case .waiting, .failed:
                if connection?.currentPath?.unsatisfiedReason == .localNetworkDenied {
                    localNetworkDenied = true
                }
                finish()
            case .ready, .cancelled:
                finish()
            default:
                break
            }
        }

        connection.start(queue: queue)

        _ = semaphore.wait(timeout: .now() + max(0.1, timeout))

        queue.sync {
            if connection.currentPath?.unsatisfiedReason == .localNetworkDenied {
                localNetworkDenied = true
            }
            connection.stateUpdateHandler = nil
            connection.cancel()
        }

        return localNetworkDenied
    }

    /// Whether a failed MySQL connection attempt is worth a Local Network probe.
    ///
    /// Only a failure to reach the host can come from a denied Local Network
    /// permission; an answer from the server, such as an access-denied error,
    /// cannot. The probe decides; this only keeps it from running after errors
    /// the permission cannot cause. The error message alone never says that
    /// the permission is denied: macOS reports the denial as an ordinary
    /// unreachable host.
    ///
    /// - Parameters:
    ///   - errorID: The error number of the failed attempt.
    ///   - errorMessage: Its message.
    /// - Returns: Whether to probe the host.
    static func shouldProbe(afterMySQLErrorID errorID: UInt, message errorMessage: String) -> Bool {
        // Access denied: the server answered, so the host was reached.
        if errorID == 1045 {
            return false
        }
        // CR_CONNECTION_ERROR and CR_CONN_HOST_ERROR: the connection itself failed.
        if errorID == 2002 || errorID == 2003 {
            return true
        }
        let message = errorMessage.lowercased()
        return ["can't connect", "timed out", "no route to host", "network is unreachable"].contains { message.contains($0) }
    }

    private static func normalizedHost(_ host: String) -> String {
        var trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedHost.hasPrefix("[") && trimmedHost.hasSuffix("]") && trimmedHost.count > 2 {
            trimmedHost.removeFirst()
            trimmedHost.removeLast()
        }
        return trimmedHost
    }
}
