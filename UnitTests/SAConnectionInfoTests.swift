//
//  SAConnectionInfoTests.swift
//  Unit Tests
//
//  Tests for SAConnectionInfoObjC (the ObjC-bridged connection info).
//

import XCTest

final class SAConnectionInfoTests: XCTestCase {

    func testDefaultInit() {
        let info = SAConnectionInfoObjC()

        XCTAssertEqual(info.type, .tcpIP)
        XCTAssertEqual(info.host, "")
        XCTAssertEqual(info.user, "")
        XCTAssertEqual(info.port, "")
        XCTAssertEqual(info.name, "")
        XCTAssertEqual(info.password, "")
        XCTAssertEqual(info.database, "")
        XCTAssertEqual(info.socket, "")
        XCTAssertEqual(info.colorIndex, 0)
        XCTAssertFalse(info.useCompression)
    }

    func testSetBasicProperties() {
        let info = SAConnectionInfoObjC()
        info.type = .sshTunnel
        info.host = "db.example.com"
        info.user = "admin"
        info.password = "secret"
        info.database = "mydb"
        info.port = "3306"
        info.colorIndex = 3
        info.useCompression = true

        XCTAssertEqual(info.type, .sshTunnel)
        XCTAssertEqual(info.host, "db.example.com")
        XCTAssertEqual(info.user, "admin")
        XCTAssertEqual(info.password, "secret")
        XCTAssertEqual(info.database, "mydb")
        XCTAssertEqual(info.port, "3306")
        XCTAssertEqual(info.colorIndex, 3)
        XCTAssertTrue(info.useCompression)
    }

    func testSSLProperties() {
        let info = SAConnectionInfoObjC()
        info.useSSL = 1
        info.sslKeyFileLocationEnabled = 1
        info.sslKeyFileLocation = "/path/to/key.pem"
        info.sslCertificateFileLocationEnabled = 1
        info.sslCertificateFileLocation = "/path/to/cert.pem"
        info.sslCACertFileLocationEnabled = 1
        info.sslCACertFileLocation = "/path/to/ca.pem"

        XCTAssertEqual(info.useSSL, 1)
        XCTAssertEqual(info.sslKeyFileLocationEnabled, 1)
        XCTAssertEqual(info.sslKeyFileLocation, "/path/to/key.pem")
        XCTAssertEqual(info.sslCertificateFileLocationEnabled, 1)
        XCTAssertEqual(info.sslCertificateFileLocation, "/path/to/cert.pem")
        XCTAssertEqual(info.sslCACertFileLocationEnabled, 1)
        XCTAssertEqual(info.sslCACertFileLocation, "/path/to/ca.pem")
    }

    func testSSHProperties() {
        let info = SAConnectionInfoObjC()
        info.sshHost = "jump.example.com"
        info.sshUser = "tunnel"
        info.sshPassword = "sshpass"
        info.sshKeyLocationEnabled = 1
        info.sshKeyLocation = "/path/to/ssh_key"
        info.sshPort = "22"

        XCTAssertEqual(info.sshHost, "jump.example.com")
        XCTAssertEqual(info.sshUser, "tunnel")
        XCTAssertEqual(info.sshPassword, "sshpass")
        XCTAssertEqual(info.sshKeyLocationEnabled, 1)
        XCTAssertEqual(info.sshKeyLocation, "/path/to/ssh_key")
        XCTAssertEqual(info.sshPort, "22")
    }

    func testKeychainProperties() {
        let info = SAConnectionInfoObjC()
        info.connectionKeychainID = "keychain-123"
        info.connectionKeychainItemName = "Sequel Ace : localhost"
        info.connectionKeychainItemAccount = "root@localhost"
        info.connectionSSHKeychainItemName = "SSH: jump"
        info.connectionSSHKeychainItemAccount = "tunnel@jump"

        XCTAssertEqual(info.connectionKeychainID, "keychain-123")
        XCTAssertEqual(info.connectionKeychainItemName, "Sequel Ace : localhost")
        XCTAssertEqual(info.connectionKeychainItemAccount, "root@localhost")
        XCTAssertEqual(info.connectionSSHKeychainItemName, "SSH: jump")
        XCTAssertEqual(info.connectionSSHKeychainItemAccount, "tunnel@jump")
    }

    func testConnectionTypeRawValues() {
        XCTAssertEqual(SAConnectionType.tcpIP.rawValue, 0)
        XCTAssertEqual(SAConnectionType.socket.rawValue, 1)
        XCTAssertEqual(SAConnectionType.sshTunnel.rawValue, 2)
        XCTAssertEqual(SAConnectionType.awsIAM.rawValue, 3)
    }

    func testTimeZoneProperties() {
        let info = SAConnectionInfoObjC()
        info.timeZoneMode = .useFixedTZ
        info.timeZoneIdentifier = "America/New_York"

        XCTAssertEqual(info.timeZoneMode, .useFixedTZ)
        XCTAssertEqual(info.timeZoneIdentifier, "America/New_York")
    }

    func testAWSProperties() {
        let info = SAConnectionInfoObjC()
        info.type = .awsIAM
        info.useAWSIAMAuth = 1
        info.awsRegion = "us-east-1"
        info.awsProfile = "production"

        XCTAssertEqual(info.type, .awsIAM)
        XCTAssertEqual(info.useAWSIAMAuth, 1)
        XCTAssertEqual(info.awsRegion, "us-east-1")
        XCTAssertEqual(info.awsProfile, "production")
    }
}
