//
//  SASessionIdentityIntegrationTests.swift
//  SPMySQLFramework
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//
//  More info at <https://github.com/Sequel-Ace/Sequel-Ace>
//

import XCTest
@testable import SPMySQL

/// A connection whose connection check waits for the test before it answers, so that a stop can
/// land while a statement is still waiting for the check - before anything was sent. While the
/// check is held the connection is in the state a check that reconnects puts it in.
private final class SACheckedConnection: SPMySQLConnection {
    let checkStarted = DispatchSemaphore(value: 0)
    let letTheCheckAnswer = DispatchSemaphore(value: 0)
    var holdsTheNextCheck = false

    override func checkIfNecessary() -> Bool {
        if holdsTheNextCheck {
            holdsTheNextCheck = false
            setValue(SPMySQLConnecting.rawValue, forKey: "state")
            checkStarted.signal()
            _ = letTheCheckAnswer.wait(timeout: .now() + 10)
            setValue(SPMySQLConnected.rawValue, forKey: "state")
        }
        return super.checkIfNecessary()
    }
}

/// A connection on which the replacement mark lands right after a connection check - a keepalive
/// that gives up at that moment - so the check could not act on it, and whoever made the check
/// goes on with a session that is marked.
private final class SAMarkedAfterTheCheckConnection: SPMySQLConnection {
    var markAfterTheNextCheck: SASessionReplacementMark?

    override func checkIfNecessary() -> Bool {
        let usable = super.checkIfNecessary()
        if let mark = markAfterTheNextCheck {
            markAfterTheNextCheck = nil
            setValue(mark.rawValue, forKey: "sessionReplacement")
        }
        return usable
    }
}

/// A connection that records whether its session was pinged.
private final class SAPingWatchingConnection: SPMySQLConnection {
    private(set) var pingedTheSession = false

    override func check() -> Bool {
        pingedTheSession = true
        return super.check()
    }
}

/// A connection that changes the session's character set at the moment the statement takes the
/// session - after the call was made, before anything is sent - the way a reconnect that restores
/// another character set does.
private final class SASwitchingConnection: SPMySQLConnection {
    var characterSetToSwitchToBeforeTheNextStatement: String?

    @objc(_lockUsableConnectionForQuery) func switchThenLock() -> Bool {
        if let characterSet = characterSetToSwitchToBeforeTheNextStatement {
            characterSetToSwitchToBeforeTheNextStatement = nil
            // Runs a statement of its own, which takes and releases the connection; the caller's
            // statement has not taken it yet.
            XCTAssertTrue(setEncoding(characterSet), "the session has to move to \(characterSet)")
        }
        let selector = #selector(switchThenLock)
        guard let method = class_getInstanceMethod(SPMySQLConnection.self, selector) else {
            XCTFail("the usable-session lock is missing")
            return false
        }
        typealias Lock = @convention(c) (AnyObject, Selector) -> Bool
        return unsafeBitCast(method_getImplementation(method), to: Lock.self)(self, selector)
    }
}

/// A statement whose serialisation waits for the test: the window a stop can land in once the
/// lease has been told of the query. The first serialisation - the size estimate made before the
/// session is taken - runs through; the one inside the attempt, for the session that is held, waits.
private final class SASlowlySerialisedStatement: NSString {
    private var text: NSString = ""
    private var serialisationsSoFar = 0
    let serialising = DispatchSemaphore(value: 0)
    let letItFinish = DispatchSemaphore(value: 0)

    convenience init(statement: String) {
        self.init()
        text = statement as NSString
    }

    override var length: Int { text.length }

    override func character(at index: Int) -> unichar { text.character(at: index) }

    override func data(using encoding: UInt, allowLossyConversion lossy: Bool) -> Data? {
        serialisationsSoFar += 1
        if serialisationsSoFar == 2 {
            serialising.signal()
            _ = letItFinish.wait(timeout: .now() + 10)
        }
        return text.data(using: encoding, allowLossyConversion: lossy)
    }
}

/// The session identity against a real server: a stop reaches a statement before its first send,
/// a statement is serialised and a value escaped for the session that sends it, and a session
/// marked to be replaced is replaced - unless a transaction is open in it, which keeps it until
/// that is over, and a character set restored meanwhile reaches it.
final class SASessionIdentityIntegrationTests: XCTestCase {

    /// A database of this test's own, dropped afterwards.
    private var database = ""

    /// Connects, or skips when no local server is configured.
    private func connected<T: SPMySQLConnection>(_ connection: T) throws -> T {
        try configureForTheLocalServer(connection)
        guard connection.connect() else {
            throw XCTSkip("Local MySQL connection is unavailable: \(connection.lastErrorMessage() ?? "no error")")
        }
        return connection
    }

    /// Makes the test's database and a table with one VARBINARY column, so the server stores the
    /// literal's bytes as they arrive. The database is selected through the connection, which
    /// selects it again on a session that replaces this one.
    private func prepare(_ connection: SPMySQLConnection) throws {
        database = "sa_identity_\(UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "_"))"
        connection.queryString("CREATE DATABASE \(database)")
        try XCTSkipIf(connection.queryErrored(), "Cannot create a database for the regression.")
        XCTAssertTrue(connection.selectDatabase(database))
        connection.queryString("CREATE TABLE t (id INT PRIMARY KEY AUTO_INCREMENT, v VARBINARY(100)) ENGINE=InnoDB")
        try XCTSkipIf(connection.queryErrored(), "Cannot create the table for the regression.")
    }

    private func dropTheDatabase(_ connection: SPMySQLConnection) {
        if !database.isEmpty {
            connection.queryString("DROP DATABASE IF EXISTS \(database)")
        }
    }

    private func rowCount(_ connection: SPMySQLConnection) -> Int {
        ((connection.getFirstField(fromQuery: "SELECT COUNT(*) FROM \(database).t") as? NSString)?.integerValue) ?? -1
    }

    // MARK: - Stop before the first send

    /// A stop that lands while the statement is still waiting for the connection check - with the
    /// connection in the state a reconnecting check puts it in - keeps that statement from the
    /// server: nothing is written, and the caller is told it was cancelled.
    func testAStopDuringTheConnectionCheckKeepsTheStatementFromTheServer() throws {
        let connection = try connected(SACheckedConnection())
        let observer = try connected(SPMySQLConnection())
        defer {
            dropTheDatabase(observer)
            connection.disconnect()
            observer.disconnect()
        }
        try prepare(connection)

        connection.holdsTheNextCheck = true
        let returned = expectation(description: "the statement returned")
        var result: SPMySQLResult?
        Thread.detachNewThread {
            result = connection.queryString("INSERT INTO t (v) VALUES ('written')")
            returned.fulfill()
        }
        XCTAssertEqual(connection.checkStarted.wait(timeout: .now() + 5), .success, "the statement is in its check")

        // The user stops while the check is still out. Nothing native is running, so this records
        // the stop against the pending statement and returns at once.
        let stopStarted = Date()
        connection.cancelCurrentQuery()
        XCTAssertLessThan(Date().timeIntervalSince(stopStarted), 1)

        // The check answers: connectivity is there, and the statement could be sent. It is not.
        connection.letTheCheckAnswer.signal()
        wait(for: [returned], timeout: 10)

        XCTAssertNil(result)
        XCTAssertTrue(connection.lastQueryWasCancelled)
        XCTAssertEqual(connection.lastErrorID(), 1317)
        XCTAssertEqual(rowCount(observer), 0, "the write never reached the server")

        // And the stop was for that statement alone: the next one runs.
        connection.queryString("INSERT INTO t (v) VALUES ('later')")
        XCTAssertFalse(connection.queryErrored())
        XCTAssertFalse(connection.lastQueryWasCancelled)
        XCTAssertEqual(rowCount(observer), 1)
    }

    /// A stop that lands while the statement's bytes are being built - after the lease was told of
    /// the query, and for a large statement a while before anything is sent - keeps the statement
    /// from the server.
    func testAStopWhileTheStatementIsBeingSerialisedKeepsItFromTheServer() throws {
        let connection = try connected(SPMySQLConnection())
        let observer = try connected(SPMySQLConnection())
        defer {
            dropTheDatabase(observer)
            connection.disconnect()
            observer.disconnect()
        }
        try prepare(connection)

        let statement = SASlowlySerialisedStatement(statement: "INSERT INTO t (v) VALUES ('written')")
        let returned = expectation(description: "the statement returned")
        var result: SPMySQLResult?
        Thread.detachNewThread {
            result = connection.queryString(statement as String)
            returned.fulfill()
        }
        XCTAssertEqual(statement.serialising.wait(timeout: .now() + 5), .success, "the statement is being serialised for the session it holds")

        connection.cancelCurrentQuery()
        statement.letItFinish.signal()
        wait(for: [returned], timeout: 10)

        XCTAssertNil(result)
        XCTAssertTrue(connection.lastQueryWasCancelled)
        XCTAssertEqual(connection.lastErrorID(), 1317)
        XCTAssertEqual(rowCount(observer), 0, "the write never reached the server")
    }

    // MARK: - Serialised for the session that sends it

    /// The statement's bytes are built for the session that is held when it is sent, not for the
    /// character set in force when the call was made.
    ///
    /// The session moves from utf8mb4 to latin1 between the call and the send, as one does when a
    /// reconnect in between restores another character set. `é` is `C3 A9` in the first and `E9`
    /// in the second; a VARBINARY column keeps whichever arrived.
    func testTheStatementIsSerialisedForTheSessionThatSendsIt() throws {
        let connection = try connected(SASwitchingConnection())
        defer {
            dropTheDatabase(connection)
            connection.disconnect()
        }
        try prepare(connection)
        XCTAssertTrue(connection.setEncoding("utf8mb4"))

        connection.characterSetToSwitchToBeforeTheNextStatement = "latin1"
        connection.queryString("INSERT INTO t (v) VALUES ('\u{00E9}')")
        XCTAssertFalse(connection.queryErrored())
        XCTAssertNil(connection.characterSetToSwitchToBeforeTheNextStatement, "the switch happened at the take")

        let stored = connection.getFirstField(fromQuery: "SELECT HEX(v) FROM t") as? String
        XCTAssertEqual(stored, "E9", "serialised for the latin1 session that sent it, not the utf8mb4 one the call was made under")
    }

    /// A statement that fit the session it was measured for, and not the one the send lands on,
    /// is refused with the server's own error rather than sent: the server would refuse it and
    /// close the connection over it.
    ///
    /// The limit is a megabyte for the span of this test. 700 000 `é` are 700 KB in latin1, which
    /// the statement is measured in, and 1.4 MB in utf8mb4, which the session reads by the time
    /// the statement takes it.
    func testAStatementTheSessionCannotTakeAfterTheSwitchIsRefusedNotSent() throws {
        let observer = try connected(SPMySQLConnection())
        defer { observer.disconnect() }
        let limitBefore = try XCTUnwrap(observer.getFirstField(fromQuery: "SELECT @@global.max_allowed_packet") as? String)
        observer.queryString("SET GLOBAL max_allowed_packet = 1048576")
        try XCTSkipIf(observer.queryErrored(), "Cannot set the global packet limit for the regression.")
        defer { observer.queryString("SET GLOBAL max_allowed_packet = \(limitBefore)") }

        // Connected after the limit was set, so it is the limit this connection knows.
        let connection = try connected(SASwitchingConnection())
        defer { connection.disconnect() }
        XCTAssertTrue(connection.setEncoding("latin1"))
        let theSession = connection.getFirstField(fromQuery: "SELECT CONNECTION_ID()") as? String
        XCTAssertNotNil(theSession)

        connection.characterSetToSwitchToBeforeTheNextStatement = "utf8mb4"
        connection.queryString("SELECT LENGTH('\(String(repeating: "\u{00E9}", count: 700_000))')")
        XCTAssertTrue(connection.queryErrored())
        XCTAssertEqual(connection.lastErrorID(), 1153, "refused with the packet-size error")
        XCTAssertNil(connection.characterSetToSwitchToBeforeTheNextStatement, "the switch happened at the take")
        XCTAssertEqual(connection.getFirstField(fromQuery: "SELECT CONNECTION_ID()") as? String, theSession,
                       "nothing was sent, so the session is still there")
    }

    /// An encoding a caller names is the caller's, whatever the session is in: the import sends
    /// a file's statements in the file's encoding.
    func testAnEncodingTheCallerNamesIsKept() throws {
        let connection = try connected(SPMySQLConnection())
        defer {
            dropTheDatabase(connection)
            connection.disconnect()
        }
        try prepare(connection)
        XCTAssertTrue(connection.setEncoding("latin1"))

        // Named as UTF-8 while the session reads latin1: the bytes are the caller's, so the
        // server receives C3 A9 and keeps both bytes.
        _ = connection.queryString("INSERT INTO t (v) VALUES ('\u{00E9}')", usingEncoding: String.Encoding.utf8.rawValue, with: SPMySQLResultAsResult)
        XCTAssertFalse(connection.queryErrored())

        XCTAssertEqual(connection.getFirstField(fromQuery: "SELECT HEX(v) FROM t") as? String, "C3A9")
    }

    // MARK: - Session transitions

    /// A session marked to be replaced is replaced before its next statement, and the mark goes
    /// with it.
    func testAMarkedSessionIsReplacedBeforeItsNextStatement() throws {
        let connection = try connected(SPMySQLConnection())
        defer {
            dropTheDatabase(connection)
            connection.disconnect()
        }
        try prepare(connection)
        let theMarkedSession = connection.mysqlConnectionThreadId

        connection.setValue(SASessionReplacementMark.whenNothingIsOpen.rawValue, forKey: "sessionReplacement")
        XCTAssertEqual(connection.getFirstField(fromQuery: "SELECT 1") as? String, "1")

        XCTAssertNotEqual(connection.mysqlConnectionThreadId, theMarkedSession, "the statement ran on a new session")
        XCTAssertEqual(connection.value(forKey: "sessionReplacement") as? Int, SASessionReplacementMark.notMarked.rawValue, "which starts unmarked")
    }

    /// A session marked to go is replaced by the connection check itself, and not pinged first: a
    /// ping would speak on a session whose protocol cannot be trusted, and read an answer still on
    /// its way as its own.
    func testTheCheckReplacesASessionMarkedToGoWithoutSpeakingOnIt() throws {
        let connection = try connected(SAPingWatchingConnection())
        defer { connection.disconnect() }
        let theMarkedSession = connection.mysqlConnectionThreadId

        // Idle long enough for a check to be necessary, and marked regardless of what is open.
        connection.setValue(0, forKey: "lastConnectionUsedTime")
        connection.setValue(SASessionReplacementMark.regardless.rawValue, forKey: "sessionReplacement")

        XCTAssertTrue(connection.checkIfNecessary())
        XCTAssertFalse(connection.pingedTheSession, "a session whose protocol cannot be trusted is not spoken on")
        XCTAssertNotEqual(connection.mysqlConnectionThreadId, theMarkedSession, "it was replaced")
        XCTAssertEqual(connection.value(forKey: "sessionReplacement") as? Int, SASessionReplacementMark.notMarked.rawValue, "and the new session starts unmarked")
    }

    /// A session marked to go while something holds the connection - the keepalive marks it while
    /// it holds the lock - is not pinged by the check either: the check neither waits for the lock
    /// to speak on the session nor replaces it under somebody's feet. It answers at once and
    /// leaves the session to the statement that next takes the connection, which replaces it.
    func testTheCheckLeavesAMarkedSessionSomethingIsUsingToTheNextStatement() throws {
        let connection = try connected(SAPingWatchingConnection())
        defer { connection.disconnect() }
        let theMarkedSession = connection.mysqlConnectionThreadId

        // Another thread holds the connection, as the keepalive does while it marks.
        let lockHeld = DispatchSemaphore(value: 0)
        let letGoOfTheLock = DispatchSemaphore(value: 0)
        let lockReleased = expectation(description: "the lock was released")
        Thread.detachNewThread {
            _ = connection.perform(NSSelectorFromString("_lockConnection"))
            lockHeld.signal()
            _ = letGoOfTheLock.wait(timeout: .now() + 10)
            _ = connection.perform(NSSelectorFromString("_unlockConnection"))
            lockReleased.fulfill()
        }
        XCTAssertEqual(lockHeld.wait(timeout: .now() + 5), .success)
        connection.setValue(0, forKey: "lastConnectionUsedTime")
        connection.setValue(SASessionReplacementMark.regardless.rawValue, forKey: "sessionReplacement")

        let checked = expectation(description: "the check returned")
        var usable = false
        Thread.detachNewThread {
            usable = connection.checkIfNecessary()
            checked.fulfill()
        }
        wait(for: [checked], timeout: 3)
        XCTAssertTrue(usable)
        XCTAssertFalse(connection.pingedTheSession, "nothing spoke on the session")
        XCTAssertEqual(connection.mysqlConnectionThreadId, theMarkedSession, "and nothing replaced it under the holder's feet")

        letGoOfTheLock.signal()
        wait(for: [lockReleased], timeout: 5)
        XCTAssertEqual(connection.getFirstField(fromQuery: "SELECT 1") as? String, "1")
        XCTAssertNotEqual(connection.mysqlConnectionThreadId, theMarkedSession, "the next statement replaced it")
    }

    /// A marked session with a transaction open is kept until that transaction is over: closing it
    /// would roll back work somebody is still doing. Once the transaction is committed, the next
    /// statement runs on a new session, and the work is there.
    func testAMarkedSessionWithATransactionOpenIsKeptUntilTheTransactionIsOver() throws {
        let connection = try connected(SPMySQLConnection())
        defer {
            dropTheDatabase(connection)
            connection.disconnect()
        }
        try prepare(connection)
        connection.queryString("START TRANSACTION")
        connection.queryString("INSERT INTO t (v) VALUES ('kept')")
        XCTAssertFalse(connection.queryErrored())
        let theSessionWithTheTransaction = connection.mysqlConnectionThreadId

        connection.setValue(SASessionReplacementMark.whenNothingIsOpen.rawValue, forKey: "sessionReplacement")
        XCTAssertEqual(rowCount(connection), 1, "the transaction's own session still sees its row")
        XCTAssertEqual(connection.mysqlConnectionThreadId, theSessionWithTheTransaction, "the session was kept")
        XCTAssertEqual(connection.value(forKey: "sessionReplacement") as? Int, SASessionReplacementMark.whenNothingIsOpen.rawValue, "and the mark stands")

        connection.queryString("COMMIT")
        XCTAssertFalse(connection.queryErrored())
        XCTAssertEqual(connection.mysqlConnectionThreadId, theSessionWithTheTransaction, "the commit went to the session that held the transaction")

        XCTAssertEqual(rowCount(connection), 1, "the committed row is there")
        XCTAssertNotEqual(connection.mysqlConnectionThreadId, theSessionWithTheTransaction, "and the session was replaced once nothing was open in it")
        XCTAssertEqual(connection.value(forKey: "sessionReplacement") as? Int, SASessionReplacementMark.notMarked.rawValue)
    }

    /// A session the protocol cannot be trusted on goes even with a transaction open: an answer
    /// nobody read may still be on its way, and the next statement would read it as its own result.
    /// The transaction is lost with it.
    func testASessionTheProtocolCannotBeTrustedOnGoesEvenWithATransactionOpen() throws {
        let connection = try connected(SPMySQLConnection())
        defer {
            dropTheDatabase(connection)
            connection.disconnect()
        }
        try prepare(connection)
        connection.queryString("START TRANSACTION")
        connection.queryString("INSERT INTO t (v) VALUES ('lost')")
        XCTAssertFalse(connection.queryErrored())
        let theSessionWithTheTransaction = connection.mysqlConnectionThreadId

        connection.setValue(SASessionReplacementMark.regardless.rawValue, forKey: "sessionReplacement")

        XCTAssertEqual(rowCount(connection), 0, "the transaction was rolled back with its session")
        XCTAssertNotEqual(connection.mysqlConnectionThreadId, theSessionWithTheTransaction)
        XCTAssertEqual(connection.value(forKey: "sessionReplacement") as? Int, SASessionReplacementMark.notMarked.rawValue, "the new session can be trusted")
    }

    // MARK: - Escaped for the session that sends it

    /// A value escaped while the session is marked to go is escaped for the session that will send
    /// it, not for the one on its way out: the two escaping modes are not interchangeable.
    ///
    /// The outgoing session is in `NO_BACKSLASH_ESCAPES`, where a backslash is an ordinary byte and
    /// `a\b` needs no escaping. The session that replaces it starts in the server's own mode, which
    /// a mode set in a session does not outlive, and there `a\b` is `a` followed by a backspace. A
    /// VARBINARY column keeps whichever arrived.
    func testAValueEscapedWhileTheSessionIsMarkedIsEscapedForTheSessionThatSendsIt() throws {
        let connection = try connected(SAMarkedAfterTheCheckConnection())
        defer {
            dropTheDatabase(connection)
            connection.disconnect()
        }
        try prepare(connection)
        connection.queryString("SET SESSION sql_mode = CONCAT(@@sql_mode, ',NO_BACKSLASH_ESCAPES')")
        XCTAssertFalse(connection.queryErrored())
        let value = "a\\b"
        XCTAssertEqual(connection.escape(value, includingQuotes: false), "a\\b", "the escaper follows the session it has: the backslash stays")
        let theOutgoingSession = connection.mysqlConnectionThreadId

        // The mark lands after the check escaping makes, so the check cannot replace the session
        // first; the value's mode has to come from the mark.
        connection.markAfterTheNextCheck = .regardless
        let escaped = try XCTUnwrap(connection.escapeAndQuoteString(value))
        XCTAssertNil(connection.markAfterTheNextCheck, "the mark landed")
        XCTAssertEqual(connection.mysqlConnectionThreadId, theOutgoingSession, "escaping sends nothing, so the marked session is still the one there is")

        connection.queryString("INSERT INTO t (v) VALUES (\(escaped))")
        XCTAssertFalse(connection.queryErrored())
        XCTAssertNotEqual(connection.mysqlConnectionThreadId, theOutgoingSession, "the statement ran on the replacement")
        let replacementMode = connection.getFirstField(fromQuery: "SELECT @@sql_mode") as? String ?? ""
        try XCTSkipIf(replacementMode.contains("NO_BACKSLASH_ESCAPES"), "this server starts sessions in NO_BACKSLASH_ESCAPES, so the two modes cannot be told apart here")
        XCTAssertEqual(connection.getFirstField(fromQuery: "SELECT HEX(v) FROM t") as? String, "615C62", "a, backslash, b - not a and a backspace, which is what the replacement makes of the backslash and the b")
    }

    /// A character set restored on a session that is kept - marked, with a transaction open -
    /// reaches that session: the restore goes out as a statement, and a statement takes the session
    /// the way everything else does. The next non-ASCII value is serialised for the character set
    /// the session reads it in, on the kept session and on the one that replaces it afterwards.
    func testACharacterSetRestoredOnAKeptSessionReachesThatSession() throws {
        let connection = try connected(SPMySQLConnection())
        defer {
            dropTheDatabase(connection)
            connection.disconnect()
        }
        try prepare(connection)
        XCTAssertTrue(connection.setEncoding("utf8mb4"))
        connection.storeEncodingForRestoration()
        XCTAssertTrue(connection.setEncoding("latin1"))
        connection.queryString("START TRANSACTION")
        connection.queryString("INSERT INTO t (v) VALUES ('\u{00E9}')")
        XCTAssertFalse(connection.queryErrored())
        let theKeptSession = connection.mysqlConnectionThreadId

        connection.setValue(SASessionReplacementMark.whenNothingIsOpen.rawValue, forKey: "sessionReplacement")
        connection.restoreStoredEncoding()
        XCTAssertEqual(connection.mysqlConnectionThreadId, theKeptSession, "the session with the transaction was kept")
        XCTAssertEqual(connection.getFirstField(fromQuery: "SELECT @@character_set_client") as? String, "utf8mb4", "and it is the session the character set was restored on")
        connection.queryString("INSERT INTO t (v) VALUES ('\u{00E9}')")
        XCTAssertFalse(connection.queryErrored())
        connection.queryString("COMMIT")
        XCTAssertFalse(connection.queryErrored())

        // Nothing is open in it any more: the next statement runs on the replacement, which reads
        // the restored character set too.
        connection.queryString("INSERT INTO t (v) VALUES ('\u{00E9}')")
        XCTAssertFalse(connection.queryErrored())
        XCTAssertNotEqual(connection.mysqlConnectionThreadId, theKeptSession, "replaced once the transaction was over")
        XCTAssertEqual(connection.getFirstField(fromQuery: "SELECT HEX(v) FROM t WHERE id = 1") as? String, "E9", "written while the session read latin1")
        XCTAssertEqual(connection.getFirstField(fromQuery: "SELECT HEX(v) FROM t WHERE id = 2") as? String, "C3A9", "written on the kept session after the restore")
        XCTAssertEqual(connection.getFirstField(fromQuery: "SELECT HEX(v) FROM t WHERE id = 3") as? String, "C3A9", "written on the replacement")
    }

    // MARK: - The local server

    /// Points a connection at the local server named by the environment, or at the usual socket.
    private func configureForTheLocalServer(_ connection: SPMySQLConnection) throws {
        let environment = ProcessInfo.processInfo.environment
        var socketPath = environment["SPMYSQL_TEST_SOCKET"]
        let testHost = environment["SPMYSQL_TEST_HOST"]
        if (socketPath?.isEmpty ?? true), (testHost?.isEmpty ?? true) {
            socketPath = ["/tmp/mysql.sock", "/opt/homebrew/var/mysql/mysql.sock"]
                .first(where: { FileManager.default.fileExists(atPath: $0) })
        }
        let testUser = environment["SPMYSQL_TEST_USER"]
        connection.username = testUser?.isEmpty == false ? testUser : "root"
        connection.password = environment["SPMYSQL_TEST_PASSWORD"]
        connection.useKeepAlive = false
        connection.timeout = 5
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
            throw XCTSkip("No local MySQL connection configured. Set SPMYSQL_TEST_SOCKET or SPMYSQL_TEST_HOST to run this regression.")
        }
    }
}
