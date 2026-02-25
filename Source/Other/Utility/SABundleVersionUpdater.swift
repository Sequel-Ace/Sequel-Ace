//
//  Created by Codex on 2026-02-25.
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import Foundation
import Network

@objcMembers final class SALocalNetworkPermissionChecker: NSObject {
    /// Performs a short Network.framework probe for the provided endpoint and
    /// returns true when the system reports Local Network access is denied.
    class func isLocalNetworkAccessDenied(forHost host: String, port: Int, timeout: TimeInterval = 1.5) -> Bool {
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
            if didComplete { return }
            didComplete = true
            semaphore.signal()
        }

        connection.stateUpdateHandler = { state in
            switch state {
            case .waiting, .failed:
                if connection.currentPath?.unsatisfiedReason == .localNetworkDenied {
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

        if connection.currentPath?.unsatisfiedReason == .localNetworkDenied {
            localNetworkDenied = true
        }

        connection.cancel()
        return localNetworkDenied
    }

    private class func normalizedHost(_ host: String) -> String {
        var trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedHost.hasPrefix("[") && trimmedHost.hasSuffix("]") && trimmedHost.count > 2 {
            trimmedHost.removeFirst()
            trimmedHost.removeLast()
        }
        return trimmedHost
    }
}
