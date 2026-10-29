//
//  SPMySQLConnectionServerInfoTests.swift
//  Unit Tests
//
//  Server version questions must stay answerable once a connection is gone.
//  Closing a tab hands the connection to a background disconnect thread while
//  UI code can still be drawing (see issue #2413); answering from the raw MYSQL
//  handle crashed in mysql_get_server_info once that handle was released.
//

import XCTest
import SPMySQL

final class SPMySQLConnectionServerInfoTests: XCTestCase {

    /// A connection that has reached the handshake, without a live server.
    private func handshakenConnection(serverVersion: String) -> SPMySQLConnection {
        let connection = SPMySQLConnection()
        connection.setValue(serverVersion, forKey: "serverVariableVersion")
        return connection
    }

    func testIsMariaDBAnswersFromTheHandshakeVersion() {
        XCTAssertTrue(handshakenConnection(serverVersion: "10.11.8-MariaDB").isMariaDB)
        XCTAssertFalse(handshakenConnection(serverVersion: "8.4.0").isMariaDB)
        XCTAssertFalse(handshakenConnection(serverVersion: "5.7.44-ubuntu-log").isMariaDB)
        // A vendor suffix that only shares a letter with MariaDB is still MySQL
        XCTAssertFalse(handshakenConnection(serverVersion: "8.0.33-debug").isMariaDB)
        // The MariaDB suffix can follow a "5.5.5-" compatibility prefix
        XCTAssertTrue(handshakenConnection(serverVersion: "5.5.5-10.11.8-MariaDB-ubu2204").isMariaDB)
    }

    func testServerVersionQuestionsSurviveADisconnect() {
        let connection = handshakenConnection(serverVersion: "10.5.27-MariaDB")
        connection.disconnect()

        XCTAssertTrue(connection.isMariaDB)
        XCTAssertFalse(connection.isNotMariadb103)
    }

    func testANeverConnectedConnectionReportsNoMariaDBInsteadOfCrashing() {
        let connection = SPMySQLConnection()

        XCTAssertFalse(connection.isMariaDB)
        XCTAssertTrue(connection.isNotMariadb103)
    }
}
