//
//  SAConnectionStringTests.swift
//  Unit Tests
//
//  Tests for connection string generation and parsing.
//

import XCTest

final class SAConnectionStringTests: XCTestCase {

    // MARK: - Connection String Generation Tests

    func testBasicTCPIPConnectionString() throws {
        var info = SAConnectionInfo()
        info.type = .tcpIP
        info.host = "localhost"
        info.user = "root"
        info.port = "3306"
        info.database = "testdb"

        let connectionString = try XCTUnwrap(info.toConnectionString(includePassword: false))

        XCTAssertTrue(connectionString.hasPrefix("mysql://"))
        XCTAssertTrue(connectionString.contains("root@localhost"))
        XCTAssertTrue(connectionString.contains("3306"))
        XCTAssertTrue(connectionString.contains("/testdb"))
    }

    func testConnectionStringWithPassword() throws {
        var info = SAConnectionInfo()
        info.type = .tcpIP
        info.host = "db.example.com"
        info.user = "admin"
        info.password = "secret123"
        info.database = "production"

        let withPassword = try XCTUnwrap(info.toConnectionString(includePassword: true))
        let withoutPassword = try XCTUnwrap(info.toConnectionString(includePassword: false))

        XCTAssertTrue(withPassword.contains("secret123"))
        XCTAssertFalse(withoutPassword.contains("secret123"))
    }

    func testSocketConnectionString() throws {
        var info = SAConnectionInfo()
        info.type = .socket
        info.host = "localhost"
        info.user = "root"
        info.socket = "/tmp/mysql.sock"

        let connectionString = try XCTUnwrap(info.toConnectionString(includePassword: false))

        XCTAssertTrue(connectionString.contains("type=socket"))
        XCTAssertTrue(connectionString.contains("socket=/tmp/mysql.sock"))
    }

    func testSSHTunnelConnectionString() throws {
        var info = SAConnectionInfo()
        info.type = .sshTunnel
        info.host = "db.internal.com"
        info.user = "dbuser"
        info.sshHost = "bastion.example.com"
        info.sshUser = "ubuntu"
        info.sshPort = "2222"

        let connectionString = try XCTUnwrap(info.toConnectionString(includePassword: false))

        XCTAssertTrue(connectionString.contains("type=ssh"))
        XCTAssertTrue(connectionString.contains("ssh_host=bastion.example.com"))
        XCTAssertTrue(connectionString.contains("ssh_user=ubuntu"))
        XCTAssertTrue(connectionString.contains("ssh_port=2222"))
    }

    func testSSHTunnelConnectionStringIncludesRemoteSocketPath() throws {
        var info = SAConnectionInfo()
        info.type = .sshTunnel
        info.host = "127.0.0.1"
        info.user = "dbuser"
        info.sshHost = "bastion.example.com"
        info.sshUser = "ubuntu"
        info.sshRemoteSocketPath = "/var/run/mysqld/mysqld.sock"

        let connectionString = try XCTUnwrap(info.toConnectionString(includePassword: false))

        XCTAssertTrue(connectionString.contains("type=ssh"))
        XCTAssertTrue(connectionString.contains("ssh_remote_socket_path=/var/run/mysqld/mysqld.sock"))
    }

    func testSSHKeyPathExcludedByDefault() throws {
        var info = SAConnectionInfo()
        info.type = .sshTunnel
        info.host = "db.example.com"
        info.user = "dbuser"
        info.sshHost = "bastion.example.com"
        info.sshUser = "ubuntu"
        info.sshKeyLocationEnabled = 1
        info.sshKeyLocation = "/Users/test/.ssh/id_rsa"

        let connectionString = try XCTUnwrap(info.toConnectionString(includePassword: false, includeSSHKeyPath: false))

        XCTAssertFalse(connectionString.contains("ssh_keyLocation"))
        XCTAssertFalse(connectionString.contains("id_rsa"))
    }

    func testSSHKeyPathIncludedWhenRequested() throws {
        var info = SAConnectionInfo()
        info.type = .sshTunnel
        info.host = "db.example.com"
        info.user = "dbuser"
        info.sshHost = "bastion.example.com"
        info.sshUser = "ubuntu"
        info.sshKeyLocationEnabled = 1
        info.sshKeyLocation = "/Users/test/.ssh/id_rsa"

        let connectionString = try XCTUnwrap(info.toConnectionString(includePassword: false, includeSSHKeyPath: true))

        XCTAssertTrue(connectionString.contains("ssh_keyLocation"))
    }

    func testAWSIAMConnectionString() throws {
        var info = SAConnectionInfo()
        info.type = .awsIAM
        info.host = "mydb.region.rds.amazonaws.com"
        info.user = "dbuser"
        info.awsRegion = "us-east-1"
        info.awsProfile = "production"

        let connectionString = try XCTUnwrap(info.toConnectionString(includePassword: false))

        XCTAssertTrue(connectionString.contains("type=aws_iam"))
        XCTAssertTrue(connectionString.contains("aws_region=us-east-1"))
        XCTAssertTrue(connectionString.contains("aws_profile=production"))
    }

    func testConnectionStringIncludesServerPublicKeyRequest() throws {
        var info = SAConnectionInfo()
        info.type = .tcpIP
        info.host = "127.0.0.1"
        info.requestServerPublicKey = 1

        let connectionString = try XCTUnwrap(info.toConnectionString(includePassword: false))

        XCTAssertTrue(connectionString.contains("get_server_public_key=1"))
    }

    func testConnectionStringParsesServerPublicKeyRequest() throws {
        let url = try XCTUnwrap(URL(string: "mysql://root@127.0.0.1:13306?get_server_public_key=1"))
        let result = ConnectionStringParser.parse(url)

        XCTAssertTrue(result.success)
        XCTAssertEqual((result.details["requestServerPublicKey"] as? NSNumber)?.boolValue, true)
    }

    func testConnectionStringParsesSSHRemoteSocketPath() throws {
        let url = try XCTUnwrap(URL(string: "mysql://dbuser@127.0.0.1?ssh_host=bastion.example.com&ssh_user=ubuntu&ssh_remote_socket_path=%2Fvar%2Frun%2Fmysqld%2Fmysqld.sock"))
        let result = ConnectionStringParser.parse(url)

        XCTAssertTrue(result.success)
        XCTAssertEqual(result.details["type"] as? String, "SPSSHTunnelConnection")
        XCTAssertEqual(result.details["ssh_remote_socket_path"] as? String, "/var/run/mysqld/mysqld.sock")
        XCTAssertEqual(result.details["sshRemoteSocketPath"] as? String, "/var/run/mysqld/mysqld.sock")
    }

    func testConnectionStringInfersSSHTunnelFromRemoteSocketPath() throws {
        let url = try XCTUnwrap(URL(string: "mysql://dbuser@127.0.0.1?ssh_remote_socket_path=%2Fvar%2Frun%2Fmysqld%2Fmysqld.sock"))
        let result = ConnectionStringParser.parse(url)

        XCTAssertTrue(result.success)
        XCTAssertEqual(result.details["type"] as? String, "SPSSHTunnelConnection")
    }

    func testEmptyHostDefaultsToLocalhost() throws {
        var info = SAConnectionInfo()
        info.type = .tcpIP
        info.host = ""
        info.user = "root"

        let connectionString = try XCTUnwrap(info.toConnectionString(includePassword: false))

        XCTAssertTrue(connectionString.contains("127.0.0.1"))
    }

    func testURLEncoding() throws {
        var info = SAConnectionInfo()
        info.type = .tcpIP
        info.host = "db.example.com"
        info.user = "user@domain"
        info.password = "p@ss word!"
        info.database = "my database"

        let connectionString = try XCTUnwrap(info.toConnectionString(includePassword: true))

        // URL encoding should handle special characters correctly
        XCTAssertTrue(connectionString.contains("user%40domain"), "User with @ should be percent-encoded")
        XCTAssertTrue(connectionString.contains("p%40ss%20word%21"), "Password with special chars should be percent-encoded")
        XCTAssertTrue(connectionString.contains("/my%20database"), "Database with space should be percent-encoded")
    }

    // MARK: - ObjC Bridge Tests

    func testObjCBridgeConnectionString() throws {
        let infoObjC = SAConnectionInfoObjC()
        infoObjC.type = .tcpIP
        infoObjC.host = "localhost"
        infoObjC.user = "root"
        infoObjC.port = "3306"

        let connectionString = try XCTUnwrap(infoObjC.toConnectionString(includePassword: false))

        XCTAssertTrue(connectionString.contains("mysql://"))
        XCTAssertTrue(connectionString.contains("root@localhost"))
    }

    // MARK: - Edge Cases

    func testMinimalConnectionString() throws {
        var info = SAConnectionInfo()
        info.type = .tcpIP
        // Only host set, everything else default

        let connectionString = try XCTUnwrap(info.toConnectionString(includePassword: false))

        XCTAssertTrue(connectionString.hasPrefix("mysql://"))
    }

    func testConnectionStringWithSpecialCharacters() throws {
        var info = SAConnectionInfo()
        info.type = .tcpIP
        info.host = "db-server.example.com"
        info.user = "user_123"
        info.database = "test_db-2024"

        let connectionString = try XCTUnwrap(info.toConnectionString(includePassword: false))

        XCTAssertTrue(connectionString.contains("user_123"))
        XCTAssertTrue(connectionString.contains("test_db-2024"))
    }
}
