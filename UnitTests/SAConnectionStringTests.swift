//
//  SAConnectionStringTests.swift
//  Unit Tests
//
//  Tests for connection string generation and parsing.
//

import XCTest

final class SAConnectionStringTests: XCTestCase {

    // MARK: - Connection String Generation Tests

    func testBasicTCPIPConnectionString() {
        var info = SAConnectionInfo()
        info.type = .tcpIP
        info.host = "localhost"
        info.user = "root"
        info.port = "3306"
        info.database = "testdb"

        let connectionString = info.toConnectionString(includePassword: false)

        XCTAssertNotNil(connectionString)
        XCTAssertTrue(connectionString!.hasPrefix("mysql://"))
        XCTAssertTrue(connectionString!.contains("root@localhost"))
        XCTAssertTrue(connectionString!.contains("3306"))
        XCTAssertTrue(connectionString!.contains("/testdb"))
    }

    func testConnectionStringWithPassword() {
        var info = SAConnectionInfo()
        info.type = .tcpIP
        info.host = "db.example.com"
        info.user = "admin"
        info.password = "secret123"
        info.database = "production"

        let withPassword = info.toConnectionString(includePassword: true)
        let withoutPassword = info.toConnectionString(includePassword: false)

        XCTAssertNotNil(withPassword)
        XCTAssertNotNil(withoutPassword)
        XCTAssertTrue(withPassword!.contains("secret123"))
        XCTAssertFalse(withoutPassword!.contains("secret123"))
    }

    func testSocketConnectionString() {
        var info = SAConnectionInfo()
        info.type = .socket
        info.host = "localhost"
        info.user = "root"
        info.socket = "/tmp/mysql.sock"

        let connectionString = info.toConnectionString(includePassword: false)

        XCTAssertNotNil(connectionString)
        XCTAssertTrue(connectionString!.contains("type=socket"))
        XCTAssertTrue(connectionString!.contains("socket=/tmp/mysql.sock"))
    }

    func testSSHTunnelConnectionString() {
        var info = SAConnectionInfo()
        info.type = .sshTunnel
        info.host = "db.internal.com"
        info.user = "dbuser"
        info.sshHost = "bastion.example.com"
        info.sshUser = "ubuntu"
        info.sshPort = "2222"

        let connectionString = info.toConnectionString(includePassword: false)

        XCTAssertNotNil(connectionString)
        XCTAssertTrue(connectionString!.contains("type=ssh"))
        XCTAssertTrue(connectionString!.contains("ssh_host=bastion.example.com"))
        XCTAssertTrue(connectionString!.contains("ssh_user=ubuntu"))
        XCTAssertTrue(connectionString!.contains("ssh_port=2222"))
    }

    func testSSHKeyPathExcludedByDefault() {
        var info = SAConnectionInfo()
        info.type = .sshTunnel
        info.host = "db.example.com"
        info.user = "dbuser"
        info.sshHost = "bastion.example.com"
        info.sshUser = "ubuntu"
        info.sshKeyLocationEnabled = 1
        info.sshKeyLocation = "/Users/test/.ssh/id_rsa"

        let connectionString = info.toConnectionString(includePassword: false, includeSSHKeyPath: false)

        XCTAssertNotNil(connectionString)
        XCTAssertFalse(connectionString!.contains("ssh_keyLocation"))
        XCTAssertFalse(connectionString!.contains("id_rsa"))
    }

    func testSSHKeyPathIncludedWhenRequested() {
        var info = SAConnectionInfo()
        info.type = .sshTunnel
        info.host = "db.example.com"
        info.user = "dbuser"
        info.sshHost = "bastion.example.com"
        info.sshUser = "ubuntu"
        info.sshKeyLocationEnabled = 1
        info.sshKeyLocation = "/Users/test/.ssh/id_rsa"

        let connectionString = info.toConnectionString(includePassword: false, includeSSHKeyPath: true)

        XCTAssertNotNil(connectionString)
        XCTAssertTrue(connectionString!.contains("ssh_keyLocation"))
    }

    func testAWSIAMConnectionString() {
        var info = SAConnectionInfo()
        info.type = .awsIAM
        info.host = "mydb.region.rds.amazonaws.com"
        info.user = "dbuser"
        info.awsRegion = "us-east-1"
        info.awsProfile = "production"

        let connectionString = info.toConnectionString(includePassword: false)

        XCTAssertNotNil(connectionString)
        XCTAssertTrue(connectionString!.contains("type=aws_iam"))
        XCTAssertTrue(connectionString!.contains("aws_region=us-east-1"))
        XCTAssertTrue(connectionString!.contains("aws_profile=production"))
    }

    func testEmptyHostDefaultsToLocalhost() {
        var info = SAConnectionInfo()
        info.type = .tcpIP
        info.host = ""
        info.user = "root"

        let connectionString = info.toConnectionString(includePassword: false)

        XCTAssertNotNil(connectionString)
        XCTAssertTrue(connectionString!.contains("127.0.0.1"))
    }

    func testURLEncoding() {
        var info = SAConnectionInfo()
        info.type = .tcpIP
        info.host = "db.example.com"
        info.user = "user@domain"
        info.password = "p@ss word!"
        info.database = "my database"

        let connectionString = info.toConnectionString(includePassword: true)

        XCTAssertNotNil(connectionString)
        // URL encoding should handle special characters
        XCTAssertTrue(connectionString!.contains("%"))
    }

    // MARK: - ObjC Bridge Tests

    func testObjCBridgeConnectionString() {
        let infoObjC = SAConnectionInfoObjC()
        infoObjC.type = .tcpIP
        infoObjC.host = "localhost"
        infoObjC.user = "root"
        infoObjC.port = "3306"

        let connectionString = infoObjC.toConnectionString(includePassword: false)

        XCTAssertNotNil(connectionString)
        XCTAssertTrue(connectionString!.contains("mysql://"))
        XCTAssertTrue(connectionString!.contains("root@localhost"))
    }

    // MARK: - Edge Cases

    func testMinimalConnectionString() {
        var info = SAConnectionInfo()
        info.type = .tcpIP
        // Only host set, everything else default

        let connectionString = info.toConnectionString(includePassword: false)

        XCTAssertNotNil(connectionString)
        XCTAssertTrue(connectionString!.hasPrefix("mysql://"))
    }

    func testConnectionStringWithSpecialCharacters() {
        var info = SAConnectionInfo()
        info.type = .tcpIP
        info.host = "db-server.example.com"
        info.user = "user_123"
        info.database = "test_db-2024"

        let connectionString = info.toConnectionString(includePassword: false)

        XCTAssertNotNil(connectionString)
        XCTAssertTrue(connectionString!.contains("user_123"))
        XCTAssertTrue(connectionString!.contains("test_db-2024"))
    }
}
