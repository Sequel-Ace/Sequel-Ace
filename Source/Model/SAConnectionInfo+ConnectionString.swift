//
//  SAConnectionInfo+ConnectionString.swift
//  Sequel Ace
//
//  Extension to generate MySQL connection strings from connection info.
//

import Foundation

extension SAConnectionInfo {

    /// Generates a mysql:// connection string from the connection info.
    /// Format: mysql://[user[:password]@]host[:port][/database][?params]
    /// - Parameters:
    ///   - includePassword: Whether to include passwords (default: true)
    ///   - includeSSHKeyPath: Whether to include SSH key file paths (default: false)
    ///     Note: SSH key paths are local to the machine and won't work for recipients
    func toConnectionString(includePassword: Bool = true, includeSSHKeyPath: Bool = false) -> String? {
        var components = URLComponents()
        components.scheme = "mysql"

        // User and password
        if !user.isEmpty {
            components.user = user
            if includePassword && !password.isEmpty {
                components.password = password
            }
        }

        // Host
        let hostString = host.isEmpty ? "127.0.0.1" : host
        components.host = hostString

        // Port
        if !port.isEmpty {
            components.port = Int(port)
        }

        // Database
        if !database.isEmpty {
            components.path = "/\(database)"
        }

        // Query parameters
        var queryItems: [URLQueryItem] = []

        // Connection type
        switch type {
        case .socket:
            queryItems.append(URLQueryItem(name: "type", value: "socket"))
            if !socket.isEmpty {
                queryItems.append(URLQueryItem(name: "socket", value: socket))
            }

        case .sshTunnel:
            queryItems.append(URLQueryItem(name: "type", value: "ssh"))
            if !sshHost.isEmpty {
                queryItems.append(URLQueryItem(name: "ssh_host", value: sshHost))
            }
            if !sshPort.isEmpty {
                queryItems.append(URLQueryItem(name: "ssh_port", value: sshPort))
            }
            if !sshUser.isEmpty {
                queryItems.append(URLQueryItem(name: "ssh_user", value: sshUser))
            }
            if includePassword && !sshPassword.isEmpty {
                queryItems.append(URLQueryItem(name: "ssh_password", value: sshPassword))
            }
            // Only include SSH key path if explicitly requested (it's local to the machine)
            if includeSSHKeyPath && sshKeyLocationEnabled != 0 && !sshKeyLocation.isEmpty {
                queryItems.append(URLQueryItem(name: "ssh_keyLocationEnabled", value: "1"))
                queryItems.append(URLQueryItem(name: "ssh_keyLocation", value: sshKeyLocation))
            }

        case .awsIAM:
            queryItems.append(URLQueryItem(name: "type", value: "aws_iam"))
            if !awsRegion.isEmpty {
                queryItems.append(URLQueryItem(name: "aws_region", value: awsRegion))
            }
            if !awsProfile.isEmpty {
                queryItems.append(URLQueryItem(name: "aws_profile", value: awsProfile))
            }

        case .tcpIP:
            // tcpip is the default, only add if needed for clarity
            break

        @unknown default:
            break
        }

        // Add cleartext plugin flag if enabled (for LDAP/cleartext auth)
        if enableClearTextPlugin != 0 {
            queryItems.append(URLQueryItem(name: "enable_cleartext_plugin", value: "1"))
        }
        if requestServerPublicKey != 0 {
            queryItems.append(URLQueryItem(name: "get_server_public_key", value: "1"))
        }

        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }

        return components.url?.absoluteString
    }
}

extension SAConnectionInfoObjC {

    /// Generates a mysql:// connection string from the connection info.
    /// - Parameters:
    ///   - includePassword: Whether to include passwords (default: true)
    ///   - includeSSHKeyPath: Whether to include SSH key paths (default: false)
    /// - Returns: The connection string, or nil if generation fails
    @objc func toConnectionString(includePassword: Bool = true, includeSSHKeyPath: Bool = false) -> String? {
        return info.toConnectionString(includePassword: includePassword, includeSSHKeyPath: includeSSHKeyPath)
    }
}

extension SPFavoriteNode {

    /// Generates a mysql:// connection string from the favorite node.
    /// - Parameter includePassword: Whether to include passwords in the string (default: false for security)
    /// - Returns: The connection string, or nil if generation fails
    @objc(toConnectionString:)
    func toConnectionString(includePassword: Bool) -> String? {
        guard let favoriteDict = nodeFavorite as? [String: Any] else {
            return nil
        }

        var components = URLComponents()
        components.scheme = "mysql"

        // User and password
        if let user = favoriteDict[SPFavoriteUserKey] as? String, !user.isEmpty {
            components.user = user

            // Fetch password from keychain if requested
            if includePassword {
                let keychain = SPKeychain()
                let favoriteID = favoriteDict[SPFavoriteIDKey] as? NSNumber ?? NSNumber(value: -1)
                let favoriteName = favoriteDict[SPFavoriteNameKey] as? String ?? ""
                let host = favoriteDict[SPFavoriteHostKey] as? String ?? ""
                let database = favoriteDict[SPFavoriteDatabaseKey] as? String ?? ""
                let typeTag = favoriteDict[SPFavoriteTypeKey] as? Int ?? 0

                // Normalize host for keychain lookup (socket connections use "localhost")
                let hostForKeychain = (typeTag == 1) ? "localhost" : host

                let keychainName = keychain.name(forFavoriteName: favoriteName, id: "\(favoriteID)")
                let keychainAccount = keychain.account(forUser: user, host: hostForKeychain, database: database)

                if let password = keychain.getPasswordForName(keychainName, account: keychainAccount), !password.isEmpty {
                    components.password = password
                }
            }
        }

        // Host
        let host = (favoriteDict[SPFavoriteHostKey] as? String) ?? ""
        components.host = host.isEmpty ? "127.0.0.1" : host

        // Port
        if let port = favoriteDict[SPFavoritePortKey] as? String, !port.isEmpty {
            components.port = Int(port)
        }

        // Database
        if let database = favoriteDict[SPFavoriteDatabaseKey] as? String, !database.isEmpty {
            components.path = "/\(database)"
        }

        // Query parameters
        var queryItems: [URLQueryItem] = []

        // Connection type
        let typeValue = favoriteDict[SPFavoriteTypeKey] as? Int ?? 0

        if typeValue == 1 { // SPSocketConnection
            queryItems.append(URLQueryItem(name: "type", value: "socket"))
            if let socket = favoriteDict[SPFavoriteSocketKey] as? String, !socket.isEmpty {
                queryItems.append(URLQueryItem(name: "socket", value: socket))
            }
        }
        else if typeValue == 2 { // SPSSHTunnelConnection
            queryItems.append(URLQueryItem(name: "type", value: "ssh"))
            if let sshHost = favoriteDict[SPFavoriteSSHHostKey] as? String, !sshHost.isEmpty {
                queryItems.append(URLQueryItem(name: "ssh_host", value: sshHost))
            }
            if let sshPort = favoriteDict[SPFavoriteSSHPortKey] as? String, !sshPort.isEmpty {
                queryItems.append(URLQueryItem(name: "ssh_port", value: sshPort))
            }
            if let sshUser = favoriteDict[SPFavoriteSSHUserKey] as? String, !sshUser.isEmpty {
                queryItems.append(URLQueryItem(name: "ssh_user", value: sshUser))
            }

            // Fetch SSH password from keychain if requested
            if includePassword, let sshUser = favoriteDict[SPFavoriteSSHUserKey] as? String, !sshUser.isEmpty,
               let sshHost = favoriteDict[SPFavoriteSSHHostKey] as? String, !sshHost.isEmpty {
                let keychain = SPKeychain()
                let favoriteID = favoriteDict[SPFavoriteIDKey] as? NSNumber ?? NSNumber(value: -1)
                let favoriteName = favoriteDict[SPFavoriteNameKey] as? String ?? ""

                let keychainName = keychain.nameForSSH(forFavoriteName: favoriteName, id: "\(favoriteID)")
                let keychainAccount = keychain.account(forSSHUser: sshUser, sshHost: sshHost)

                if let sshPassword = keychain.getPasswordForName(keychainName, account: keychainAccount), !sshPassword.isEmpty {
                    queryItems.append(URLQueryItem(name: "ssh_password", value: sshPassword))
                }
            }

            // Note: SSH key paths are excluded by default as they are local to the machine
            // If needed, use toConnectionString(includePassword:includeSSHKeyPath:) with includeSSHKeyPath: true
        }
        else if typeValue == 3 { // SPAWSIAMConnection
            queryItems.append(URLQueryItem(name: "type", value: "aws_iam"))
            if let awsRegion = favoriteDict["awsRegion"] as? String, !awsRegion.isEmpty {
                queryItems.append(URLQueryItem(name: "aws_region", value: awsRegion))
            }
            if let awsProfile = favoriteDict["awsProfile"] as? String, !awsProfile.isEmpty {
                queryItems.append(URLQueryItem(name: "aws_profile", value: awsProfile))
            }
        }

        // Add cleartext plugin flag if enabled (for LDAP/cleartext auth)
        if let enableClearText = favoriteDict[SPFavoriteEnableClearTextPluginKey] as? NSNumber,
           enableClearText.boolValue {
            queryItems.append(URLQueryItem(name: "enable_cleartext_plugin", value: "1"))
        }
        if let requestServerPublicKey = favoriteDict[SPFavoriteRequestServerPublicKeyKey] as? NSNumber,
           requestServerPublicKey.boolValue {
            queryItems.append(URLQueryItem(name: "get_server_public_key", value: "1"))
        }

        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }

        return components.url?.absoluteString
    }
}
