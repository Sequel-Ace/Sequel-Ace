//
//  SAConnectionInfo.swift
//  Sequel Ace
//
//  Created as part of the modernization effort to decouple
//  connection parameters from SPConnectionController.
//

import Foundation

// MARK: - Connection Type

/// Mirrors SPConnectionType from SPConstants.h for Swift usage.
@objc enum SAConnectionType: Int {
    case tcpIP = 0
    case socket = 1
    case sshTunnel = 2
    case awsIAM = 3
}

// MARK: - Time Zone Mode

/// Mirrors SPConnectionTimeZoneMode from SPConnectionController.h for Swift usage.
@objc enum SAConnectionTimeZoneMode: Int {
    case useServerTZ = 0
    case useSystemTZ = 1
    case useFixedTZ = 2
}

// MARK: - SAConnectionInfo

/// A value type capturing all parameters needed to establish a MySQL connection.
/// This consolidates the 30+ ivars scattered across SPConnectionController into a single model.
struct SAConnectionInfo {

    // MARK: Basic Connection

    var type: SAConnectionType = .tcpIP
    var name: String = ""
    var host: String = ""
    var user: String = ""
    var password: String = ""
    var database: String = ""
    var socket: String = ""
    var port: String = ""
    var colorIndex: Int = 0
    var useCompression: Bool = false

    // MARK: Time Zone

    var timeZoneMode: SAConnectionTimeZoneMode = .useServerTZ
    var timeZoneIdentifier: String = ""

    // MARK: Special Settings

    var allowDataLocalInfile: Int = 0
    var enableClearTextPlugin: Int = 0

    // MARK: AWS IAM Authentication

    var useAWSIAMAuth: Int = 0
    var awsRegion: String = ""
    var awsProfile: String = ""

    // MARK: SSL

    var useSSL: Int = 0
    var sslKeyFileLocationEnabled: Int = 0
    var sslKeyFileLocation: String = ""
    var sslCertificateFileLocationEnabled: Int = 0
    var sslCertificateFileLocation: String = ""
    var sslCACertFileLocationEnabled: Int = 0
    var sslCACertFileLocation: String = ""

    // MARK: SSH Tunnel

    var sshHost: String = ""
    var sshUser: String = ""
    var sshPassword: String = ""
    var sshKeyLocationEnabled: Int = 0
    var sshKeyLocation: String = ""
    var sshPort: String = ""

    // MARK: Keychain

    var connectionKeychainID: String = ""
    var connectionKeychainItemName: String = ""
    var connectionKeychainItemAccount: String = ""
    var connectionSSHKeychainItemName: String = ""
    var connectionSSHKeychainItemAccount: String = ""
}

// MARK: - ObjC Bridging

/// An `@objc`-compatible reference type wrapping `SAConnectionInfo` for use from Objective-C.
/// ObjC code can create, populate, and pass this object; Swift code can read `.info` to get the value type.
@objc class SAConnectionInfoObjC: NSObject {

    var info: SAConnectionInfo

    @objc override init() {
        self.info = SAConnectionInfo()
        super.init()
    }

    init(info: SAConnectionInfo) {
        self.info = info
        super.init()
    }

    /// Returns the client-side MySQL host for the supplied connection details.
    @objc class func resolvedMySQLConnectHost(for info: SAConnectionInfoObjC) -> String? {
        let trimmedHost = info.host.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedHost = trimmedHost.lowercased()

        switch info.type {
        case .socket:
            return nil

        case .sshTunnel:
            // Preserve explicit loopback values so localhost-specific grants
            // continue to work through the local forwarded endpoint.
            if normalizedHost == "localhost" || normalizedHost == "127.0.0.1" || normalizedHost == "::1" {
                return trimmedHost
            }
            return "127.0.0.1"

        case .tcpIP, .awsIAM:
            return trimmedHost.isEmpty ? "127.0.0.1" : trimmedHost

        @unknown default:
            return trimmedHost.isEmpty ? "127.0.0.1" : trimmedHost
        }
    }

    // MARK: Basic Connection

    @objc var type: SAConnectionType {
        get { info.type }
        set { info.type = newValue }
    }

    @objc var name: String {
        get { info.name }
        set { info.name = newValue }
    }

    @objc var host: String {
        get { info.host }
        set { info.host = newValue }
    }

    @objc var user: String {
        get { info.user }
        set { info.user = newValue }
    }

    @objc var password: String {
        get { info.password }
        set { info.password = newValue }
    }

    @objc var database: String {
        get { info.database }
        set { info.database = newValue }
    }

    @objc var socket: String {
        get { info.socket }
        set { info.socket = newValue }
    }

    @objc var port: String {
        get { info.port }
        set { info.port = newValue }
    }

    @objc var colorIndex: Int {
        get { info.colorIndex }
        set { info.colorIndex = newValue }
    }

    @objc var useCompression: Bool {
        get { info.useCompression }
        set { info.useCompression = newValue }
    }

    // MARK: Time Zone

    @objc var timeZoneMode: SAConnectionTimeZoneMode {
        get { info.timeZoneMode }
        set { info.timeZoneMode = newValue }
    }

    @objc var timeZoneIdentifier: String {
        get { info.timeZoneIdentifier }
        set { info.timeZoneIdentifier = newValue }
    }

    // MARK: Special Settings

    @objc var allowDataLocalInfile: Int {
        get { info.allowDataLocalInfile }
        set { info.allowDataLocalInfile = newValue }
    }

    @objc var enableClearTextPlugin: Int {
        get { info.enableClearTextPlugin }
        set { info.enableClearTextPlugin = newValue }
    }

    // MARK: AWS IAM

    @objc var useAWSIAMAuth: Int {
        get { info.useAWSIAMAuth }
        set { info.useAWSIAMAuth = newValue }
    }

    @objc var awsRegion: String {
        get { info.awsRegion }
        set { info.awsRegion = newValue }
    }

    @objc var awsProfile: String {
        get { info.awsProfile }
        set { info.awsProfile = newValue }
    }

    // MARK: SSL

    @objc var useSSL: Int {
        get { info.useSSL }
        set { info.useSSL = newValue }
    }

    @objc var sslKeyFileLocationEnabled: Int {
        get { info.sslKeyFileLocationEnabled }
        set { info.sslKeyFileLocationEnabled = newValue }
    }

    @objc var sslKeyFileLocation: String {
        get { info.sslKeyFileLocation }
        set { info.sslKeyFileLocation = newValue }
    }

    @objc var sslCertificateFileLocationEnabled: Int {
        get { info.sslCertificateFileLocationEnabled }
        set { info.sslCertificateFileLocationEnabled = newValue }
    }

    @objc var sslCertificateFileLocation: String {
        get { info.sslCertificateFileLocation }
        set { info.sslCertificateFileLocation = newValue }
    }

    @objc var sslCACertFileLocationEnabled: Int {
        get { info.sslCACertFileLocationEnabled }
        set { info.sslCACertFileLocationEnabled = newValue }
    }

    @objc var sslCACertFileLocation: String {
        get { info.sslCACertFileLocation }
        set { info.sslCACertFileLocation = newValue }
    }

    // MARK: SSH

    @objc var sshHost: String {
        get { info.sshHost }
        set { info.sshHost = newValue }
    }

    @objc var sshUser: String {
        get { info.sshUser }
        set { info.sshUser = newValue }
    }

    @objc var sshPassword: String {
        get { info.sshPassword }
        set { info.sshPassword = newValue }
    }

    @objc var sshKeyLocationEnabled: Int {
        get { info.sshKeyLocationEnabled }
        set { info.sshKeyLocationEnabled = newValue }
    }

    @objc var sshKeyLocation: String {
        get { info.sshKeyLocation }
        set { info.sshKeyLocation = newValue }
    }

    @objc var sshPort: String {
        get { info.sshPort }
        set { info.sshPort = newValue }
    }

    // MARK: Keychain

    @objc var connectionKeychainID: String {
        get { info.connectionKeychainID }
        set { info.connectionKeychainID = newValue }
    }

    @objc var connectionKeychainItemName: String {
        get { info.connectionKeychainItemName }
        set { info.connectionKeychainItemName = newValue }
    }

    @objc var connectionKeychainItemAccount: String {
        get { info.connectionKeychainItemAccount }
        set { info.connectionKeychainItemAccount = newValue }
    }

    @objc var connectionSSHKeychainItemName: String {
        get { info.connectionSSHKeychainItemName }
        set { info.connectionSSHKeychainItemName = newValue }
    }

    @objc var connectionSSHKeychainItemAccount: String {
        get { info.connectionSSHKeychainItemAccount }
        set { info.connectionSSHKeychainItemAccount = newValue }
    }
}
