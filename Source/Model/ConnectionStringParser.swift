//
//  ConnectionStringParser.swift
//  Sequel Ace
//
//  Centralized parser for mysql:// connection strings.
//  Can be used by clipboard import, App URL handlers, and future features.
//

import Foundation

/// Result of parsing a MySQL connection string
@objc public class ConnectionStringParseResult: NSObject {
    @objc public let details: [String: Any]
    @objc public let autoConnect: Bool
    @objc public let invalidParameters: [String]
    @objc public let success: Bool

    init(details: [String: Any], autoConnect: Bool, invalidParameters: [String], success: Bool) {
        self.details = details
        self.autoConnect = autoConnect
        self.invalidParameters = invalidParameters
        self.success = success
    }
}

/// Parser for MySQL connection strings in mysql:// URL format
@objc public class ConnectionStringParser: NSObject {

    /// Valid query parameters for mysql:// URLs
    @objc public static let validQueryParameters: [String] = [
        "type", "socket",
        "ssh_host", "ssh_port", "ssh_user", "ssh_password", "ssh_keyLocationEnabled", "ssh_keyLocation",
        "aws_region", "aws_profile",
        "autoConnect", "enable_cleartext_plugin"
    ]

    /// Parses a mysql:// URL into connection details
    /// - Parameter url: The URL to parse
    /// - Returns: Parse result with connection details, autoConnect flag, and any invalid parameters
    @objc public static func parse(_ url: URL) -> ConnectionStringParseResult {
        guard url.scheme?.lowercased() == "mysql" else {
            return ConnectionStringParseResult(details: [:], autoConnect: false, invalidParameters: [], success: false)
        }

        var details: [String: Any] = [:]
        var autoConnect = false
        var invalidParameters: [String] = []

        // Parse basic connection info
        if let host = url.host, !host.isEmpty {
            details["host"] = host
        }

        if let user = url.user, !user.isEmpty {
            details["user"] = user
        }

        if let password = url.password, !password.isEmpty {
            details["password"] = password
        }

        if let port = url.port {
            details["port"] = "\(port)"
        }

        // Parse database from path
        let path = url.path
        if path.hasPrefix("/") && path.count > 1 {
            let database = String(path.dropFirst())
            if !database.isEmpty {
                details["database"] = database
            }
        }

        // Parse query parameters
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let queryItems = components.queryItems {

            for item in queryItems {
                let key = item.name
                let value = item.value ?? ""

                // Check if parameter is valid
                if !validQueryParameters.contains(key) {
                    invalidParameters.append(key)
                    continue
                }

                // Handle special parameters
                switch key {
                case "autoConnect":
                    autoConnect = (value.lowercased() == "true" || value == "1")

                case "type":
                    details["type"] = connectionTypeString(from: value)

                case "socket":
                    details["socket"] = value

                case "ssh_host":
                    details["ssh_host"] = value

                case "ssh_port":
                    details["ssh_port"] = value

                case "ssh_user":
                    details["ssh_user"] = value

                case "ssh_password":
                    details["ssh_password"] = value

                case "ssh_keyLocationEnabled":
                    details["ssh_keyLocationEnabled"] = value

                case "ssh_keyLocation":
                    details["ssh_keyLocation"] = value

                case "aws_region":
                    details["aws_region"] = value

                case "aws_profile":
                    details["aws_profile"] = value

                case "enable_cleartext_plugin":
                    details["enable_cleartext_plugin"] = value

                default:
                    break
                }
            }
        }

        // Set default connection type if not specified
        if details["type"] == nil {
            details["type"] = "SPTCPIPConnection"
        }

        let success = invalidParameters.isEmpty
        return ConnectionStringParseResult(details: details, autoConnect: autoConnect, invalidParameters: invalidParameters, success: success)
    }

    /// Converts a connection type URL parameter to the internal string representation
    private static func connectionTypeString(from urlParam: String) -> String {
        switch urlParam.lowercased() {
        case "socket":
            return "SPSocketConnection"
        case "ssh":
            return "SPSSHTunnelConnection"
        case "aws_iam", "awsiam":
            return "SPAWSIAMConnection"
        case "tcpip", "tcp":
            return "SPTCPIPConnection"
        default:
            return "SPTCPIPConnection"
        }
    }

    /// Validates a connection string URL
    /// - Parameter urlString: The URL string to validate
    /// - Returns: The validated URL, or nil if invalid
    @objc public static func validateConnectionString(_ urlString: String) -> URL? {
        guard let url = URL(string: urlString),
              url.scheme?.lowercased() == "mysql" else {
            return nil
        }
        return url
    }
}
