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

    /// A session whose SQL-input character set differs from the one results come back in, with
    /// the server reporting no changes at all.
    ///
    /// `character_set_client` is what the server reads statements in and `character_set_results`
    /// what it sends results in. `SET NAMES` sets both, so they usually agree - but an
    /// `init_connect` can set them apart, and then escaping and result decoding need different
    /// character sets. Escaping follows the input one: a value escaped for latin1 while the server
    /// parses the statement as GBK becomes `BF 5C 27`, GBK reads `BF 5C` as one character, and the
    /// quote that follows ends the literal. Result decoding has to keep following the results one,
    /// rather than being quietly changed to match.
    ///
    /// `init_connect` also turns the session-state tracking off, so nothing the server reports can
    /// stand in for the two variables - which is the state the escaper has to get right from the
    /// variable list alone.
    func testInputAndResultCharacterSetsAreFollowedSeparately() throws {
        guard let privileged = newDisposableServerConnection() else {
            throw XCTSkip("This regression changes a global server setting, so it needs a server named for the purpose: a socket at \(Self.disposableServerSocket), or SPMYSQL_TEST_DISPOSABLE_SOCKET pointing at one.")
        }
        guard privileged.connect() else {
            throw XCTSkip("Local MySQL connection is unavailable for the character set regression.")
        }
        defer { privileged.disconnect() }

        let suffix = UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "_")
        let database = "sa_charsets_\(suffix)"
        let user = "sa_cs_\(suffix.prefix(16))"

        // init_connect is skipped for a user with SUPER, so the session below needs its own.
        let previousInitConnect = privileged.getFirstField(fromQuery: "SELECT @@global.init_connect") as? String
        privileged.queryString("CREATE DATABASE \(database)")
        try XCTSkipIf(privileged.queryErrored(), "Cannot create a database for the regression.")
        defer { privileged.queryString("DROP DATABASE IF EXISTS \(database)") }

        privileged.queryString("CREATE USER '\(user)'@'%' IDENTIFIED BY 'probe'")
        try XCTSkipIf(privileged.queryErrored(), "Cannot create a user without SUPER for the regression.")
        defer {
            privileged.queryString("SET GLOBAL init_connect = \(privileged.escapeAndQuoteString(previousInitConnect ?? "") ?? "''")")
            privileged.queryString("DROP USER IF EXISTS '\(user)'@'%'")
        }
        privileged.queryString("GRANT ALL ON \(database).* TO '\(user)'@'%'")
        try XCTSkipIf(privileged.queryErrored(), "Cannot grant the regression user its database.")

        // The session starts with its statements read as GBK, its results sent as latin1, and
        // nothing reported.
        privileged.queryString("""
            SET GLOBAL init_connect = "SET character_set_client = 'gbk', character_set_connection = 'gbk', \
            character_set_results = 'latin1', SESSION session_track_system_variables = ''"
            """)
        try XCTSkipIf(privileged.queryErrored(), "Cannot set init_connect for the regression.")

        guard let session = newDisposableServerConnection() else {
            throw XCTSkip("No disposable server configured.")
        }
        session.username = user
        session.password = "probe"
        guard session.connect() else {
            throw XCTSkip("The regression user cannot connect: \(session.lastErrorMessage() ?? "no error")")
        }
        defer { session.disconnect() }
        session.queryString("USE \(database)")
        try XCTSkipIf(session.queryErrored(), "The regression user cannot use its database.")

        // What the server actually reports, so a server that ignored init_connect skips rather
        // than passing for a mismatch.
        let reportedInput = session.getFirstField(fromQuery: "SELECT @@session.character_set_client") as? String
        let reportedResults = session.getFirstField(fromQuery: "SELECT @@session.character_set_results") as? String
        try XCTSkipIf(reportedInput != "gbk" || reportedResults != "latin1",
                      "init_connect did not take effect (client \(reportedInput ?? "?"), results \(reportedResults ?? "?")).")

        // Result decoding keeps following the results character set. This is the half that must
        // not be quietly changed to match the input one.
        XCTAssertEqual(session.encoding(), "latin1",
                       "the record follows character_set_results, which is what results are decoded with")
        let decoded = session.getFirstField(fromQuery: "SELECT _latin1 0xE4") as? String
        XCTAssertEqual(decoded, "\u{00E4}", "a latin1 byte still decodes as latin1")

        // VARBINARY, so the server stores the literal's bytes without converting them.
        session.queryString("CREATE TABLE v (id INT PRIMARY KEY, value VARBINARY(100))")
        try XCTSkipIf(session.queryErrored(), "Cannot create the table for the regression.")

        // Startup: escaping has to follow the input character set, which no statement of this
        // connection's has set - it came from init_connect and was never reported.
        let startupLiteral = try XCTUnwrap(session.escapeAndQuoteString(dangerousValue),
                                           "the value has to be escapable")
        session.queryString("INSERT INTO v (id, value) VALUES (1, \(startupLiteral))")
        XCTAssertFalse(session.queryErrored(),
                       "a literal escaped for the character set the statement is read in parses")
        let startupStored = storedHex(from: session, id: 1)
        let ownBytes = try XCTUnwrap(dangerousValue.data(using: .windowsCP1252)).hexString
        XCTAssertEqual(startupStored, ownBytes,
                       "the stored bytes have to be the value's own, not what a breakout left behind")

        // Asking for the character set the record already names still has to move the session:
        // the server reads statements in another one, so the two do not agree yet and there is
        // work to do, however much the record looks right.
        XCTAssertTrue(session.setEncoding("latin1"), "the session has to be moved, not reported as already there")
        let alignedInput = session.getFirstField(fromQuery: "SELECT @@session.character_set_client") as? String
        XCTAssertEqual(alignedInput, "latin1",
                       "a successful setEncoding: has to leave the server reading statements in that character set")

        // A connection-owned change sets both, so the two agree again and escaping follows along.
        XCTAssertTrue(session.setEncoding("gbk"), "the connection has to be able to move the session")
        XCTAssertEqual(session.encoding(), "gbk", "and the record follows its own statement")
        let afterChange = try XCTUnwrap(session.escapeAndQuoteString(backslashValue),
                                        "the value has to be escapable after the change")
        session.queryString("INSERT INTO v (id, value) VALUES (2, \(afterChange))")
        XCTAssertFalse(session.queryErrored(), "a literal escaped for the moved session parses")
        XCTAssertEqual(storedHex(from: session, id: 2),
                       try XCTUnwrap(backslashValue.data(using: .ascii)).hexString,
                       "and stores its own bytes")
    }

    // MARK: - Helpers

    /// A value whose bytes end in a backslash before the closing quote, which is the shape a
    /// misplaced escape lets out of its literal. ASCII, so it is the same bytes in either
    /// character set.
    private let backslashValue = "a\\"

    /// The stored bytes of one row, as `HEX()` returns them.
    private func storedHex(from connection: SPMySQLConnection, id: Int) -> String? {
        let stored = connection.getFirstField(fromQuery: "SELECT HEX(value) FROM v WHERE id = \(id)")
        let hex = (stored as? Data).map { String(decoding: $0) } ?? (stored as? String)
        return hex?.uppercased()
    }


    /// Where a server that may be reconfigured out from under its other sessions is expected.
    ///
    /// Named for the purpose on purpose: the regression below sets `init_connect`, which every
    /// new session on that server then starts with, so it must never run against a server that
    /// merely happens to be listening locally. A socket under this name can only exist because
    /// someone put a throwaway server there.
    static let disposableServerSocket = "/tmp/sa-escaping-regression.sock"

    /// A connection to that server, or nil when none has been named.
    private func newDisposableServerConnection() -> SPMySQLConnection? {
        let environment = ProcessInfo.processInfo.environment
        let named = environment["SPMYSQL_TEST_DISPOSABLE_SOCKET"]
        let socketPath = (named?.isEmpty ?? true) ? Self.disposableServerSocket : named!
        guard FileManager.default.fileExists(atPath: socketPath) else {
            return nil
        }
        let connection = SPMySQLConnection()
        let testUser = environment["SPMYSQL_TEST_USER"]
        connection.username = testUser?.isEmpty == false ? testUser : "root"
        connection.password = environment["SPMYSQL_TEST_PASSWORD"]
        connection.useKeepAlive = false
        connection.useSocket = true
        connection.socketPath = socketPath
        return connection
    }

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
