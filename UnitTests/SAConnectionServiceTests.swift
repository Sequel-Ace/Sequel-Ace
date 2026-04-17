//
//  SAConnectionServiceTests.swift
//  Unit Tests
//
//  Tests for the connection info → service parameter mapping.
//  SAConnectionResult and SAConnectionPreferences live in the app target
//  (depend on SPMySQL), so they're tested via integration, not here.
//

import XCTest

// MARK: - Connection Info Parameter Mapping Tests

/// Tests that SAConnectionInfoObjC correctly stores and retrieves all
/// connection parameters that SAConnectionService will consume.
final class SAConnectionInfoMappingTests: XCTestCase {

    func testTCPIPInfoSetup() {
        let info = SAConnectionInfoObjC()
        info.type = .tcpIP
        info.host = "db.example.com"
        info.port = "3306"
        info.user = "admin"
        info.password = "secret"
        info.database = "mydb"

        XCTAssertEqual(info.type, .tcpIP)
        XCTAssertEqual(info.host, "db.example.com")
        XCTAssertEqual(info.port, "3306")
        XCTAssertEqual(info.user, "admin")
        XCTAssertEqual(info.password, "secret")
        XCTAssertEqual(info.database, "mydb")
        XCTAssertEqual(info.socket, "")
    }

    func testSocketInfoSetup() {
        let info = SAConnectionInfoObjC()
        info.type = .socket
        info.socket = "/tmp/mysql.sock"
        info.user = "root"

        XCTAssertEqual(info.type, .socket)
        XCTAssertEqual(info.socket, "/tmp/mysql.sock")
        XCTAssertEqual(info.host, "")
    }

    func testSSHTunnelInfoSetup() {
        let info = SAConnectionInfoObjC()
        info.type = .sshTunnel
        info.host = "internal-db.local"
        info.port = "3306"
        info.sshHost = "jump.example.com"
        info.sshUser = "tunnel"
        info.sshPort = "22"
        info.sshPassword = "sshpass"

        XCTAssertEqual(info.type, .sshTunnel)
        XCTAssertEqual(info.host, "internal-db.local")
        XCTAssertEqual(info.sshHost, "jump.example.com")
        XCTAssertEqual(info.sshUser, "tunnel")
        XCTAssertEqual(info.sshPort, "22")
        XCTAssertEqual(info.sshPassword, "sshpass")
    }

    func testAWSIAMInfoSetup() {
        let info = SAConnectionInfoObjC()
        info.type = .awsIAM
        info.host = "mydb.cluster.us-east-1.rds.amazonaws.com"
        info.port = "3306"
        info.user = "iam_user"
        info.useAWSIAMAuth = 1
        info.awsRegion = "us-east-1"
        info.awsProfile = "production"

        XCTAssertEqual(info.type, .awsIAM)
        XCTAssertEqual(info.useAWSIAMAuth, 1)
        XCTAssertEqual(info.awsRegion, "us-east-1")
        XCTAssertEqual(info.awsProfile, "production")
    }

    func testSSLEnabledPropagatesAllFields() {
        let info = SAConnectionInfoObjC()
        info.useSSL = 1
        info.sslKeyFileLocationEnabled = 1
        info.sslKeyFileLocation = "/path/key.pem"
        info.sslCertificateFileLocationEnabled = 1
        info.sslCertificateFileLocation = "/path/cert.pem"
        info.sslCACertFileLocationEnabled = 1
        info.sslCACertFileLocation = "/path/ca.pem"

        XCTAssertEqual(info.useSSL, 1)
        XCTAssertEqual(info.sslKeyFileLocationEnabled, 1)
        XCTAssertEqual(info.sslKeyFileLocation, "/path/key.pem")
        XCTAssertEqual(info.sslCertificateFileLocationEnabled, 1)
        XCTAssertEqual(info.sslCertificateFileLocation, "/path/cert.pem")
        XCTAssertEqual(info.sslCACertFileLocationEnabled, 1)
        XCTAssertEqual(info.sslCACertFileLocation, "/path/ca.pem")
    }

    func testSSLDisabledByDefault() {
        let info = SAConnectionInfoObjC()
        XCTAssertEqual(info.useSSL, 0)
        XCTAssertEqual(info.sslKeyFileLocationEnabled, 0)
        XCTAssertEqual(info.sslCertificateFileLocationEnabled, 0)
        XCTAssertEqual(info.sslCACertFileLocationEnabled, 0)
    }

    func testCompressionDefaults() {
        let info = SAConnectionInfoObjC()
        XCTAssertFalse(info.useCompression)

        info.useCompression = true
        XCTAssertTrue(info.useCompression)
    }

    func testTimeZoneModes() {
        let info = SAConnectionInfoObjC()

        info.timeZoneMode = .useServerTZ
        XCTAssertEqual(info.timeZoneMode, .useServerTZ)

        info.timeZoneMode = .useSystemTZ
        XCTAssertEqual(info.timeZoneMode, .useSystemTZ)

        info.timeZoneMode = .useFixedTZ
        info.timeZoneIdentifier = "America/New_York"
        XCTAssertEqual(info.timeZoneMode, .useFixedTZ)
        XCTAssertEqual(info.timeZoneIdentifier, "America/New_York")
    }

    func testKeychainFieldsForServicePassthrough() {
        let info = SAConnectionInfoObjC()
        info.connectionSSHKeychainItemName = "SSH: jump"
        info.connectionSSHKeychainItemAccount = "tunnel@jump"

        XCTAssertEqual(info.connectionSSHKeychainItemName, "SSH: jump")
        XCTAssertEqual(info.connectionSSHKeychainItemAccount, "tunnel@jump")
    }

    func testSpecialSettingsForService() {
        let info = SAConnectionInfoObjC()
        info.allowDataLocalInfile = 1
        info.enableClearTextPlugin = 1

        XCTAssertEqual(info.allowDataLocalInfile, 1)
        XCTAssertEqual(info.enableClearTextPlugin, 1)
    }

    /// Ensures localhost-specific grants still work through SSH tunnel forwarding.
    func testResolvedMySQLConnectHostPreservesLocalhostForSSHTunnelConnections() {
        let info = SAConnectionInfoObjC()
        info.type = .sshTunnel
        info.host = "localhost"

        XCTAssertEqual(SAConnectionInfoObjC.resolvedMySQLConnectHost(for: info), "localhost")
    }

    /// Ensures remote SSH target hosts do not leak into the local MySQL connect host.
    func testResolvedMySQLConnectHostUsesLoopbackForCustomHostForSSHTunnelConnections() {
        let info = SAConnectionInfoObjC()
        info.type = .sshTunnel
        info.host = "db.internal"

        XCTAssertEqual(SAConnectionInfoObjC.resolvedMySQLConnectHost(for: info), "127.0.0.1")
    }

    /// Falls back to loopback when no explicit TCP host has been supplied.
    func testResolvedMySQLConnectHostDefaultsToLoopbackWhenBlank() {
        let info = SAConnectionInfoObjC()
        info.type = .sshTunnel
        info.host = ""

        XCTAssertEqual(SAConnectionInfoObjC.resolvedMySQLConnectHost(for: info), "127.0.0.1")
    }

    /// Leaves socket connections without a TCP host override.
    func testResolvedMySQLConnectHostReturnsNilForSocketConnections() {
        let info = SAConnectionInfoObjC()
        info.type = .socket

        XCTAssertNil(SAConnectionInfoObjC.resolvedMySQLConnectHost(for: info))
    }
}
