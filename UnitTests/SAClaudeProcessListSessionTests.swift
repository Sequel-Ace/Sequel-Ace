//
//  SAClaudeProcessListSessionTests.swift
//  Unit Tests
//

import XCTest
import SPMySQL

/// A Process List backend that records what ran and where. Rows are what SPMySQL returns (every column a string or NSNull).
private final class FakeProcessListBackend: SAClaudeProcessListBackend {
    private let lock = NSLock()
    private var _rows: [[String: Any]]
    private var _executed: [String] = []
    private var _fetchCount = 0
    private var _fetchedOnMain = false
    private var _closed = false

    var executeResult: SAClaudeProcessStatementResult = .ok
    var fetchError: String?
    /// Runs inside every fetch/execute before it answers (block here to simulate a busy connection).
    var gate: (() -> Void)?
    var serverVersion: String? = "8.4.0"
    var connectionId: Int64 = 77

    init(rows: [[String: Any]] = []) { _rows = rows }

    var rows: [[String: Any]] {
        get { lock.lock(); defer { lock.unlock() }; return _rows }
        set { lock.lock(); _rows = newValue; lock.unlock() }
    }
    var executed: [String] { lock.lock(); defer { lock.unlock() }; return _executed }
    var fetchCount: Int { lock.lock(); defer { lock.unlock() }; return _fetchCount }
    var fetchedOnMain: Bool { lock.lock(); defer { lock.unlock() }; return _fetchedOnMain }
    var closed: Bool { lock.lock(); defer { lock.unlock() }; return _closed }

    func fetchProcessRows() -> Result<[[String: Any]], SAClaudeProcessListError> {
        gate?()
        lock.lock(); defer { lock.unlock() }
        _fetchCount += 1
        if Thread.isMainThread { _fetchedOnMain = true }
        if let fetchError { return .failure(SAClaudeProcessListError(message: fetchError)) }
        return .success(_rows)
    }

    func execute(_ statement: String) -> SAClaudeProcessStatementResult {
        gate?()
        lock.lock(); defer { lock.unlock() }
        if Thread.isMainThread { _fetchedOnMain = true }
        _executed.append(statement)
        return executeResult
    }

    func close() { lock.lock(); _closed = true; lock.unlock() }
}

private func row(_ id: Int64, user: String = "app", command: String = "Query", time: Int = 3,
                 state: String? = "executing", info: String? = nil) -> [String: Any] {
    ["Id": String(id), "User": user, "Host": "10.0.0.5:5123", "db": "shop", "Command": command,
     "Time": String(time), "State": state as Any? ?? NSNull(), "Info": info as Any? ?? NSNull()]
}

private func process(_ id: Int64, info: String?) -> SAClaudeProcess {
    SAClaudeProcess(id: id, user: "app", host: "h", db: nil, command: info == nil ? "Sleep" : "Query", time: 1, state: nil, info: info)
}

final class SAClaudeProcessListSessionTests: XCTestCase {

    // MARK: Pure decisions

    func testKillTargetsShownConnectionId() {
        // The panel showed #4812 (then at row 0). A refresh reorders: another connection now sits at row 0.
        let before = [process(4812, info: "UPDATE stock SET n = n - 1"), process(17, info: nil)]
        let after = [process(9001, info: "SELECT 1"), process(17, info: nil), process(4812, info: "UPDATE stock SET n = n - 1")]
        XCTAssertEqual(before.first?.id, 4812)
        XCTAssertEqual(SAClaudeProcessKillDecision.killTarget(shownId: 4812, in: after), 4812)
        XCTAssertEqual(SAClaudeProcessKillDecision.statement(kind: .query, id: 4812, isTiDB: false), "KILL QUERY 4812")
        XCTAssertEqual(SAClaudeProcessKillDecision.statement(kind: .connection, id: 4812, isTiDB: false), "KILL CONNECTION 4812")
    }

    func testKillQueryWarnsWhenQueryChanged() {
        XCTAssertTrue(SAClaudeProcessKillDecision.queryChanged(shown: "SELECT SLEEP(60)", current: "DELETE FROM carts"))
        XCTAssertFalse(SAClaudeProcessKillDecision.queryChanged(shown: "SELECT SLEEP(60)", current: "SELECT SLEEP(60)"))
        XCTAssertTrue(SAClaudeProcessKillDecision.queryChanged(shown: "SELECT SLEEP(60)", current: nil), "went idle")
        XCTAssertFalse(SAClaudeProcessKillDecision.queryChanged(shown: nil, current: ""), "idle either way")

        let current = [process(4812, info: "DELETE FROM carts")]
        XCTAssertEqual(SAClaudeProcessKillDecision.preflight(kind: .query, id: 4812, expectedQuery: "SELECT SLEEP(60)", current: current),
                       .changed(current: current[0]))
        XCTAssertEqual(SAClaudeProcessKillDecision.preflight(kind: .query, id: 4812, expectedQuery: "DELETE FROM carts", current: current), .proceed)
        // Kill connection confirms as today: a different query doesn't stop it.
        XCTAssertEqual(SAClaudeProcessKillDecision.preflight(kind: .connection, id: 4812, expectedQuery: "SELECT SLEEP(60)", current: current), .proceed)
    }

    func testEndedConnectionDisablesKill() {
        let current = [process(17, info: nil)]
        XCTAssertNil(SAClaudeProcessKillDecision.killTarget(shownId: 4812, in: current))
        XCTAssertFalse(SAClaudeProcessKillDecision.canKill(shownId: 4812, in: current))
        XCTAssertFalse(SAClaudeProcessKillDecision.canKill(shownId: nil, in: current))
        XCTAssertTrue(SAClaudeProcessKillDecision.canKill(shownId: 17, in: current))
        XCTAssertEqual(SAClaudeProcessKillDecision.preflight(kind: .query, id: 4812, expectedQuery: "SELECT 1", current: current), .ended)
        XCTAssertEqual(SAClaudeProcessKillDecision.preflight(kind: .connection, id: 4812, expectedQuery: nil, current: current), .ended)
    }

    func testKillStatementsAndOutcomes() {
        XCTAssertEqual(SAClaudeProcessKillDecision.statement(kind: .query, id: 5, isTiDB: true), "KILL TIDB QUERY 5")
        XCTAssertEqual(SAClaudeProcessKillDecision.statement(kind: .connection, id: 5, isTiDB: true), "KILL TIDB CONNECTION 5")
        XCTAssertTrue(SAClaudeProcessKillDecision.isTiDB(serverVersion: "8.0.11-TiDB-v7.5.0"))
        XCTAssertFalse(SAClaudeProcessKillDecision.isTiDB(serverVersion: "11.4.2-MariaDB"))
        XCTAssertEqual(SAClaudeProcessKillDecision.outcome(of: .ok), .killed)
        XCTAssertEqual(SAClaudeProcessKillDecision.outcome(of: .error(id: 1094, message: "Unknown thread id: 5")), .ended)
        XCTAssertEqual(SAClaudeProcessKillDecision.outcome(of: .error(id: 1095, message: "You are not owner of thread 5")),
                       .failed(message: "You are not owner of thread 5"))
    }

    func testNormalizedRowKeepsTodaysShape() {
        let fixed = SAClaudeProcessKillDecision.normalizedRow(row(9_000_000_000, time: 42, info: "SELECT 1"))
        XCTAssertEqual(fixed["Id"] as? NSNumber, NSNumber(value: Int64(9_000_000_000)))
        XCTAssertEqual(fixed["Time"] as? NSNumber, NSNumber(value: Int32(42)))
        XCTAssertEqual(fixed["Info"] as? String, "SELECT 1")
        XCTAssertTrue(fixed["db"] is String)
        XCTAssertTrue(SAClaudeProcessKillDecision.normalizedRow(row(1))["Info"] is NSNull)
    }

    func testAlertExcerptClipsLongQueries() {
        XCTAssertEqual(SAClaudeProcessKillDecision.alertExcerpt("SELECT 1"), "SELECT 1")
        let long = String(repeating: "x", count: 5000)
        let clipped = SAClaudeProcessKillDecision.alertExcerpt(long, limit: 600)
        XCTAssertEqual(clipped.count, 601)
        XCTAssertTrue(clipped.hasSuffix("…"))
        XCTAssertTrue(SAClaudeProcessListSession.changedMessage(connectionId: 4812, currentQuery: "DELETE FROM carts")
            .contains("Connection #4812 is now running a different query:\n\nDELETE FROM carts\n\nKill it anyway?"))
    }

    // MARK: Session (fake backends)

    private func makeSession(dedicated: FakeProcessListBackend?, shared: FakeProcessListBackend = FakeProcessListBackend(),
                             busy: @escaping () -> Bool = { false }) -> SAClaudeProcessListSession {
        SAClaudeProcessListSession(dedicated: { dedicated }, shared: shared, sharedIsBusy: busy)
    }

    private func refreshed(_ session: SAClaudeProcessListSession, file: StaticString = #filePath, line: UInt = #line) -> SAClaudeProcessListRefresh? {
        var result: SAClaudeProcessListRefresh?
        let done = expectation(description: "refresh")
        session.refresh { r in
            XCTAssertTrue(Thread.isMainThread, "refresh results arrive on main", file: file, line: line)
            result = r
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        return result
    }

    private func killed(_ session: SAClaudeProcessListSession, _ kind: SAClaudeProcessKillKind, id: Int64, expected: String?) -> SAClaudeProcessKillOutcome? {
        var outcome: SAClaudeProcessKillOutcome?
        let done = expectation(description: "kill")
        session.kill(kind, connectionId: id, expectedQuery: expected) { o in
            XCTAssertTrue(Thread.isMainThread)
            outcome = o
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        return outcome
    }

    func testRefreshRunsOffMainAndDeliversTypedProcessesOnMain() {
        let dedicated = FakeProcessListBackend(rows: [row(4812, info: "SELECT SLEEP(60)"), row(17, command: "Sleep", state: "", info: nil)])
        let session = makeSession(dedicated: dedicated)
        var callbackProcesses: [SAClaudeProcess] = []
        session.onRefresh = { if case let .fetched(processes, _) = $0 { callbackProcesses = processes } }

        guard case let .fetched(processes, rows)? = refreshed(session) else { return XCTFail("expected a fetched list") }
        XCTAssertFalse(dedicated.fetchedOnMain)
        XCTAssertEqual(processes.map(\.id), [4812, 17])
        XCTAssertEqual(processes.first?.info, "SELECT SLEEP(60)")
        XCTAssertEqual(rows.first?["Id"] as? NSNumber, NSNumber(value: Int64(4812)))
        XCTAssertEqual(session.processes, processes)
        XCTAssertEqual(callbackProcesses, processes)
        XCTAssertFalse(session.usesSharedConnection)
        XCTAssertNil(session.sharedConnectionNote)
        XCTAssertEqual(session.ownConnectionId, 77)
    }

    func testDedicatedConnectionRefreshesWhileTheDocumentIsBusy() {
        let dedicated = FakeProcessListBackend(rows: [row(1, info: "SELECT 1")])
        let shared = FakeProcessListBackend()
        let session = makeSession(dedicated: dedicated, shared: shared, busy: { true })
        guard case .fetched? = refreshed(session) else { return XCTFail("a busy document must not block the dedicated connection") }
        XCTAssertEqual(shared.fetchCount, 0)
    }

    func testFallsBackToTheSharedConnectionWhenItsOwnCannotOpen() {
        let shared = FakeProcessListBackend(rows: [row(3, info: "SELECT 3")])
        var busy = false
        let session = makeSession(dedicated: nil, shared: shared, busy: { busy })
        guard case let .fetched(processes, _)? = refreshed(session) else { return XCTFail("shared fallback refreshes") }
        XCTAssertEqual(processes.map(\.id), [3])
        XCTAssertTrue(session.usesSharedConnection)
        XCTAssertNotNil(session.sharedConnectionNote)
        XCTAssertEqual(session.ownConnectionId, 0)

        // Today's rule on the shared connection: no refresh while the document is working; the list is kept.
        busy = true
        guard case .skipped? = refreshed(session) else { return XCTFail("busy document skips the shared refresh") }
        XCTAssertEqual(shared.fetchCount, 1)
        XCTAssertEqual(session.processes.map(\.id), [3])

        session.close()
        let drained = expectation(description: "close drained")
        session.refresh { _ in drained.fulfill() }
        wait(for: [drained], timeout: 5)
        XCTAssertFalse(shared.closed, "the document's connection is never closed by the Process List")
    }

    func testKillTargetsShownConnectionIdAfterRowsReorder() {
        let dedicated = FakeProcessListBackend(rows: [row(4812, info: "UPDATE stock SET n = n - 1"), row(17, command: "Sleep", info: nil)])
        let session = makeSession(dedicated: dedicated)
        _ = refreshed(session)
        let shown = session.processes[0]

        // Rows are replaced and reordered; row 0 is now another connection.
        dedicated.rows = [row(9001, info: "SELECT 1"), row(17, command: "Sleep", info: nil), row(4812, info: "UPDATE stock SET n = n - 1")]
        _ = refreshed(session)
        XCTAssertEqual(session.processes[0].id, 9001)

        XCTAssertEqual(killed(session, .query, id: shown.id, expected: shown.info), .killed)
        XCTAssertEqual(killed(session, .connection, id: shown.id, expected: nil), .killed)
        XCTAssertEqual(dedicated.executed, ["KILL QUERY 4812", "KILL CONNECTION 4812"])
    }

    func testKillQueryChecksTheQueryFirst() {
        let dedicated = FakeProcessListBackend(rows: [row(4812, info: "DELETE FROM carts")])
        let session = makeSession(dedicated: dedicated)

        guard case let .changed(current)? = killed(session, .query, id: 4812, expected: "SELECT SLEEP(60)") else {
            return XCTFail("a different query must be confirmed first")
        }
        XCTAssertEqual(current.info, "DELETE FROM carts")
        XCTAssertEqual(dedicated.executed, [], "nothing is killed before the confirmation")

        // Confirmed: ask again with the query now shown.
        XCTAssertEqual(killed(session, .query, id: 4812, expected: current.info), .killed)
        XCTAssertEqual(dedicated.executed, ["KILL QUERY 4812"])

        // Went idle meanwhile: reported as changed with no query; nothing killed.
        dedicated.rows = [row(4812, command: "Sleep", state: "", info: nil)]
        guard case let .changed(idle)? = killed(session, .query, id: 4812, expected: "DELETE FROM carts") else { return XCTFail() }
        XCTAssertNil(idle.info)
        XCTAssertEqual(dedicated.executed, ["KILL QUERY 4812"])
    }

    func testKillOnAnEndedConnectionReportsEnded() {
        let dedicated = FakeProcessListBackend(rows: [row(17, command: "Sleep", info: nil)])
        let session = makeSession(dedicated: dedicated)
        XCTAssertEqual(killed(session, .query, id: 4812, expected: "SELECT 1"), .ended)
        XCTAssertEqual(dedicated.executed, [])

        // Kill connection doesn't re-read; the server's "Unknown thread id" says it ended.
        dedicated.executeResult = .error(id: 1094, message: "Unknown thread id: 4812")
        XCTAssertEqual(killed(session, .connection, id: 4812, expected: nil), .ended)
        dedicated.executeResult = .error(id: 1095, message: "You are not owner of thread 4812")
        XCTAssertEqual(killed(session, .connection, id: 4812, expected: nil), .failed(message: "You are not owner of thread 4812"))
    }

    func testRefreshFailureKeepsTheLastList() {
        let dedicated = FakeProcessListBackend(rows: [row(1, info: "SELECT 1")])
        let session = makeSession(dedicated: dedicated)
        _ = refreshed(session)
        dedicated.fetchError = "Lost connection to MySQL server during query"
        guard case let .failed(message)? = refreshed(session) else { return XCTFail() }
        XCTAssertEqual(message, "Lost connection to MySQL server during query")
        XCTAssertEqual(session.lastRefreshError, message)
        XCTAssertEqual(session.processes.map(\.id), [1])
    }

    func testOverlappingRefreshIsSkipped() {
        let release = DispatchSemaphore(value: 0)
        let dedicated = FakeProcessListBackend(rows: [row(1, info: "SELECT 1")])
        dedicated.gate = { release.wait() }
        let session = makeSession(dedicated: dedicated)

        let first = expectation(description: "first")
        session.refresh { if case .fetched = $0 { first.fulfill() } }
        guard case .skipped? = refreshed(session) else { return XCTFail("a second refresh while one runs is skipped") }
        release.signal()
        wait(for: [first], timeout: 5)
    }

    /// Review focus 2 with fakes: the document's connection is stuck in a long query (its backend never answers);
    /// the Process List still refreshes and kills on its own connection, and main stays free throughout.
    func testABlockedDocumentConnectionNeverBlocksTheList() {
        let stuck = DispatchSemaphore(value: 0)
        let shared = FakeProcessListBackend(rows: [row(5, info: "SELECT SLEEP(600)")])
        shared.gate = { stuck.wait() }
        let dedicated = FakeProcessListBackend(rows: [row(5, info: "SELECT SLEEP(600)")])
        let session = makeSession(dedicated: dedicated, shared: shared, busy: { true })

        let start = Date()
        guard case .fetched? = refreshed(session) else { return XCTFail() }
        XCTAssertEqual(killed(session, .query, id: 5, expected: "SELECT SLEEP(600)"), .killed)
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
        XCTAssertEqual(shared.fetchCount, 0)
        XCTAssertEqual(dedicated.executed, ["KILL QUERY 5"])
        stuck.signal()
    }

    func testCloseClosesOnlyTheDedicatedConnection() {
        let dedicated = FakeProcessListBackend(rows: [])
        let session = makeSession(dedicated: dedicated)
        _ = refreshed(session)
        session.close()
        guard case .skipped? = refreshed(session) else { return XCTFail("a closed session refreshes nothing") }
        XCTAssertEqual(killed(session, .query, id: 1, expected: nil), .failed(message: "The process list's connection is closed."))
        let drained = expectation(description: "drained")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { drained.fulfill() }
        wait(for: [drained], timeout: 5)
        XCTAssertTrue(dedicated.closed)
    }
}

// MARK: - Live (throwaway local server only)

/// Runs only when SA_PROCESSLIST_TEST_SOCKET or SA_PROCESSLIST_TEST_HOST/PORT name a throwaway local mysqld
/// (user SA_PROCESSLIST_TEST_USER, default root, no password). Deliberately no default socket: it must never reach a
/// developer's own server.
final class SAClaudeProcessListSessionLiveTests: XCTestCase {
    private func makeParent() throws -> SPMySQLConnection {
        let environment = ProcessInfo.processInfo.environment
        let connection = SPMySQLConnection()
        connection.username = environment["SA_PROCESSLIST_TEST_USER"] ?? "root"
        connection.password = environment["SA_PROCESSLIST_TEST_PASSWORD"] ?? ""
        connection.useKeepAlive = false
        connection.timeout = 3
        if let socket = environment["SA_PROCESSLIST_TEST_SOCKET"], !socket.isEmpty {
            connection.useSocket = true
            connection.socketPath = socket
        } else if let host = environment["SA_PROCESSLIST_TEST_HOST"], !host.isEmpty,
                  let port = environment["SA_PROCESSLIST_TEST_PORT"].flatMap(UInt.init) {
            connection.useSocket = false
            connection.host = host
            connection.port = port
        } else {
            throw XCTSkip("Set SA_PROCESSLIST_TEST_SOCKET or SA_PROCESSLIST_TEST_HOST/PORT to a throwaway local mysqld.")
        }
        guard connection.connect() else {
            throw XCTSkip("Throwaway mysqld unavailable: \(connection.lastErrorMessage() ?? "unknown error")")
        }
        return connection
    }

    private func refresh(_ session: SAClaudeProcessListSession) -> [SAClaudeProcess] {
        var processes: [SAClaudeProcess] = []
        let done = expectation(description: "refresh")
        session.refresh { if case let .fetched(p, _) = $0 { processes = p }; done.fulfill() }
        wait(for: [done], timeout: 10)
        return processes
    }

    /// Review focus 2 live: the "document" connection runs SELECT SLEEP(30); the session (a copy of it) still lists,
    /// detects a changed query, kills the sleeping query, and main is never blocked.
    func testLiveListAndKillWhileTheDocumentConnectionIsBusy() throws {
        let parent = try makeParent()
        defer { parent.disconnect() }
        let parentId = Int64(parent.mysqlConnectionThreadId)
        let query = "SELECT SLEEP(30) AS process_list_harness"

        let session = SAClaudeProcessListSession(documentConnection: parent, documentIsBusy: { true })
        defer { session.close() }

        let finished = expectation(description: "document query returned")
        var queryElapsed: TimeInterval = 0
        Thread.detachNewThread {
            let start = Date()
            _ = parent.queryString(query)
            queryElapsed = Date().timeIntervalSince(start)
            finished.fulfill()
        }

        // The list refreshes while the document's connection is blocked.
        var shown: SAClaudeProcess?
        for _ in 0..<40 where shown == nil {
            let started = Date()
            shown = refresh(session).first { $0.id == parentId && $0.info == query }
            XCTAssertLessThan(Date().timeIntervalSince(started), 3, "refresh stalled behind the busy document connection")
            if shown == nil { Thread.sleep(forTimeInterval: 0.1) }
        }
        XCTAssertFalse(session.usesSharedConnection)
        XCTAssertNotEqual(session.ownConnectionId, parentId)
        guard let shown else { return XCTFail("the sleeping document query never showed in the list") }

        // A stale snapshot is caught before anything is killed.
        var outcome: SAClaudeProcessKillOutcome?
        var done = expectation(description: "changed")
        session.kill(.query, connectionId: shown.id, expectedQuery: "SELECT 1") { outcome = $0; done.fulfill() }
        wait(for: [done], timeout: 10)
        guard case .changed? = outcome else { return XCTFail("expected changed, got \(String(describing: outcome))") }

        // Main stays responsive while the kill runs: a main-queue tick lands before/while it completes.
        let tick = expectation(description: "main tick")
        DispatchQueue.main.async { tick.fulfill() }
        done = expectation(description: "killed")
        session.kill(.query, connectionId: shown.id, expectedQuery: shown.info) { outcome = $0; done.fulfill() }
        wait(for: [tick, done], timeout: 10)
        XCTAssertEqual(outcome, .killed)

        wait(for: [finished], timeout: 10)
        XCTAssertLessThan(queryElapsed, 15, "KILL QUERY interrupted SELECT SLEEP(30)")

        // Closing the window closes the Process List's own connection (and never the document's).
        let ownId = session.ownConnectionId
        session.close()
        var ownStillListed = true
        for _ in 0..<50 where ownStillListed {
            Thread.sleep(forTimeInterval: 0.1)
            let ids = (parent.getAllRows(fromQuery: "SHOW PROCESSLIST") as? [[String: Any]] ?? []).compactMap { ($0["Id"] as? NSNumber)?.int64Value ?? Int64(($0["Id"] as? String) ?? "") }
            XCTAssertTrue(ids.contains(parentId), "the document's connection stays open")
            ownStillListed = ids.contains(ownId)
        }
        XCTAssertFalse(ownStillListed, "the dedicated connection closes with the session")
    }
}
