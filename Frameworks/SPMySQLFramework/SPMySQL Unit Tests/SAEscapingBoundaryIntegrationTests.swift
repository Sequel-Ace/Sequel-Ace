//
//  SAEscapingBoundaryIntegrationTests.swift
//  SPMySQLFramework
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//
//  More info at <https://github.com/Sequel-Ace/Sequel-Ace>
//

import XCTest
@testable import SPMySQL

/// Escaping against a real server, where the session's character set changes only with the last
/// of a statement's result packets.
///
/// The escaping state is recorded where the connection is released, after everything the
/// statement produced has been read. Recorded any earlier - right after the statement was sent -
/// it misses a change the server reports in a trailing packet, and values are then escaped for
/// the character set the session was in before. For a session moved to GBK that lets a value
/// break out of its literal: `BF 27` escaped for latin1 is `BF 5C 27`, and GBK reads `BF 5C` as
/// one character, leaving the quote unescaped.
final class SAEscapingBoundaryIntegrationTests: XCTestCase {

    /// `CLIENT_MULTI_STATEMENTS`. The framework does not offer this flag, so the application
    /// cannot send several statements in one call; the test sets it to put a character set change
    /// behind the first result packet, which is the case the recording boundary has to cope with.
    private let multiStatements = SPMySQLClientFlags(rawValue: 1 << 16)

    /// A value whose latin1 bytes are `BF 27 …`: the shape that breaks out of a literal when it
    /// is escaped for a single-byte character set and read as GBK.
    private let dangerousValue = "\u{00BF}' OR 1=1 -- "

    func testACharacterSetChangeInATrailingPacketIsNotMissed() throws {
        guard let connection = newLocalConnection() else {
            throw XCTSkip("No local MySQL connection configured. Set SPMYSQL_TEST_SOCKET or SPMYSQL_TEST_HOST to run this integration regression.")
        }
        connection.addClientFlags(multiStatements)
        guard connection.connect() else {
            throw XCTSkip("Local MySQL connection is unavailable for the escaping boundary regression.")
        }
        defer { connection.disconnect() }

        let database = "sa_escaping_\(UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "_"))"
        connection.queryString("CREATE DATABASE \(database)")
        try XCTSkipIf(connection.queryErrored(), "Cannot create a database for the regression.")
        defer { connection.queryString("DROP DATABASE IF EXISTS \(database)") }

        connection.queryString("USE \(database)")
        // VARBINARY, so the server stores the literal's bytes without converting them and the
        // comparison is against the value's own bytes.
        connection.queryString("CREATE TABLE v (id INT PRIMARY KEY, value VARBINARY(100)) CHARACTER SET gbk")
        try XCTSkipIf(connection.queryErrored(), "Cannot create the table for the regression.")

        XCTAssertTrue(connection.setEncoding("latin1"), "the session has to start on latin1")

        // The change arrives only with the second statement's packet, and a SET NAMES outside a
        // stored program stays in force afterwards.
        connection.queryString("SELECT 1; SET NAMES gbk")
        XCTAssertFalse(connection.queryErrored(), "the multi-statement itself has to succeed")

        let literal = try XCTUnwrap(connection.escapeAndQuoteString(dangerousValue),
                                    "the value has to be escapable")
        connection.queryString("INSERT INTO v (id, value) VALUES (1, \(literal))")
        XCTAssertFalse(connection.queryErrored(),
                       "a literal escaped for the session's character set parses; one escaped for the previous one does not")

        let stored = connection.getFirstField(fromQuery: "SELECT HEX(value) FROM v WHERE id = 1")
        let storedHex = (stored as? Data).map { String(decoding: $0) } ?? (stored as? String)
        let expected = try XCTUnwrap(dangerousValue.data(using: .windowsCP1252)).hexString
        XCTAssertEqual(storedHex?.uppercased(), expected,
                       "the stored bytes have to be the value's own, not what a breakout left behind")
    }

    // MARK: - Helpers

    private func newLocalConnection() -> SPMySQLConnection? {
        let environment = ProcessInfo.processInfo.environment
        var socketPath = environment["SPMYSQL_TEST_SOCKET"]
        let testHost = environment["SPMYSQL_TEST_HOST"]

        if (socketPath?.isEmpty ?? true), (testHost?.isEmpty ?? true) {
            socketPath = ["/tmp/mysql.sock", "/opt/homebrew/var/mysql/mysql.sock"]
                .first(where: { FileManager.default.fileExists(atPath: $0) })
        }

        let connection = SPMySQLConnection()
        let testUser = environment["SPMYSQL_TEST_USER"]
        connection.username = testUser?.isEmpty == false ? testUser : "root"
        connection.password = environment["SPMYSQL_TEST_PASSWORD"]
        connection.useKeepAlive = false

        if let testHost, !testHost.isEmpty {
            connection.useSocket = false
            connection.host = testHost
            if let port = environment["SPMYSQL_TEST_PORT"].flatMap(UInt.init) {
                connection.port = port
            }
        } else if let socketPath, !socketPath.isEmpty {
            connection.useSocket = true
            connection.socketPath = socketPath
        } else {
            return nil
        }
        return connection
    }
}

private extension String {
    /// Reads bytes that are known to be ASCII, as `HEX()` returns them.
    init(decoding data: Data) {
        self = String(data: data, encoding: .ascii) ?? ""
    }
}

private extension Data {
    /// The bytes as uppercase hex, in the form `HEX()` returns.
    var hexString: String {
        map { String(format: "%02X", $0) }.joined()
    }
}
