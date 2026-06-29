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
        "ssh_host", "ssh_port", "ssh_user", "ssh_password", "ssh_keyLocationEnabled", "ssh_keyLocation", "ssh_remote_socket_path",
        "aws_region", "aws_profile",
        "autoConnect", "enable_cleartext_plugin", "get_server_public_key", "request_server_public_key"
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

        // Parse basic connection info (with percent-decoding)
        if let host = url.host, !host.isEmpty {
            let decodedHost = host.removingPercentEncoding ?? host
            details["host"] = decodedHost
        } else {
            // Default to localhost if no host specified
            details["host"] = "127.0.0.1"
        }

        if let user = url.user, !user.isEmpty {
            let decodedUser = user.removingPercentEncoding ?? user
            details["user"] = decodedUser
        }

        if let password = url.password {
            let decodedPassword = password.removingPercentEncoding ?? password
            details["password"] = decodedPassword
            // Auto-connect when password is present in URL
            autoConnect = true
        }

        if let port = url.port {
            details["port"] = "\(port)"
        }

        // Parse database from path (with percent-decoding)
        let pathComponents = url.pathComponents
        if pathComponents.count > 1 {  // first object is "/"
            let database = pathComponents[1]
            let decodedDatabase = database.removingPercentEncoding ?? database
            if !decodedDatabase.isEmpty {
                details["database"] = decodedDatabase
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
                    if let typeString = connectionTypeString(from: value) {
                        details["type"] = typeString
                    } else {
                        invalidParameters.append(key)
                    }

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

                case "ssh_remote_socket_path":
                    details["ssh_remote_socket_path"] = value
                    details["sshRemoteSocketPath"] = value

                case "aws_region":
                    details["aws_region"] = value

                case "aws_profile":
                    details["aws_profile"] = value

                case "enable_cleartext_plugin":
                    // Map URL-style snake_case to the favorite plist key and normalize to NSNumber
                    let boolValue = (value.lowercased() == "true" || value == "1" || value.lowercased() == "yes" || value.lowercased() == "y")
                    details["enableClearTextPlugin"] = NSNumber(value: boolValue)

                case "get_server_public_key", "request_server_public_key":
                    let boolValue = (value.lowercased() == "true" || value == "1" || value.lowercased() == "yes" || value.lowercased() == "y")
                    details["requestServerPublicKey"] = NSNumber(value: boolValue)

                default:
                    break
                }
            }
        }

        // Set default connection type if not specified, based on query parameter hints
        if details["type"] == nil {
            let hasAWSIAMIndicators = (details["aws_profile"] as? String)?.isEmpty == false ||
                                     (details["aws_region"] as? String)?.isEmpty == false
            let hasSocketIndicators = (details["socket"] as? String)?.isEmpty == false
            let hasSSHIndicators = (details["ssh_host"] as? String)?.isEmpty == false ||
                                   (details["ssh_remote_socket_path"] as? String)?.isEmpty == false

            if hasAWSIAMIndicators {
                details["type"] = "SPAWSIAMConnection"
            } else if hasSocketIndicators {
                details["type"] = "SPSocketConnection"
            } else if hasSSHIndicators {
                details["type"] = "SPSSHTunnelConnection"
            } else {
                details["type"] = "SPTCPIPConnection"
            }
        }

        let success = invalidParameters.isEmpty
        return ConnectionStringParseResult(details: details, autoConnect: autoConnect, invalidParameters: invalidParameters, success: success)
    }

    /// Converts a connection type URL parameter to the internal string representation
    /// Returns nil if the type is not recognized
    private static func connectionTypeString(from urlParam: String) -> String? {
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
            return nil
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
