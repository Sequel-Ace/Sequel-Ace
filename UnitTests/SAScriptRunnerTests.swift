//
//  SAScriptRunnerTests.swift
//  Unit Tests
//
//  Drives SAScriptRunner against a fake connection that records every SQL
//  string submitted, so cancellation races can be reproduced deterministically.
//

import XCTest

final class SAScriptRunnerTests: XCTestCase {

    // MARK: - Sanity

    func testRunsEveryStatementInOrderWithoutCancellation() {
        let connection = FakeScriptConnection()
        connection.outcomes["SELECT 1"] = .rows(columns: ["1"], rows: [[.text("1")]])
        let (summary, output) = run(["SELECT 1", "INSERT INTO t VALUES (1)", "UPDATE t SET a = 2"],
                                    on: connection)

        XCTAssertEqual(connection.submitted, ["SELECT 1", "INSERT INTO t VALUES (1)", "UPDATE t SET a = 2"])
        XCTAssertFalse(summary.wasCancelled)
        XCTAssertEqual(summary.queriesRun, 3)
        XCTAssertEqual(summary.executedStatements, connection.submitted)
        XCTAssertTrue(output.contains("1\n1\n1 row in set\n\n"))
        XCTAssertFalse(output.contains(SAScriptOutputFormatter.cancelled))
    }

    func testErrorIsReportedAndRunContinuesOnlyWhenAsked() {
        for continueOnError in [true, false] {
            let connection = FakeScriptConnection()
            connection.outcomes["BAD"] = .error(code: 1064, sqlState: "42000", message: "syntax")
            let (summary, output) = run(["SELECT 1", "BAD", "SELECT 3"], on: connection, continueOnError: continueOnError)

            XCTAssertEqual(connection.submitted, continueOnError ? ["SELECT 1", "BAD", "SELECT 3"] : ["SELECT 1", "BAD"])
            XCTAssertEqual(summary.errorCount, 1)
            XCTAssertEqual(summary.errorLines, ["ERROR 1064 (42000) at line 2: syntax"])
            XCTAssertTrue(output.contains("ERROR 1064 (42000) at line 2: syntax\n\n"))
            XCTAssertFalse(summary.wasCancelled)
        }
    }

    // MARK: - R1: a Stop after the loop-top check must keep the next SQL off the wire

    func testStopFromProgressCallbackNeverSubmitsTheNextStatement() {
        let connection = FakeScriptConnection()
        let token = SAScriptCancellationToken()
        let (summary, output) = run(["INSERT INTO t VALUES (1)", "DELETE FROM t"],
                                    on: connection,
                                    token: token,
                                    onProgress: { index in if index == 1 { token.cancel() } })

        XCTAssertEqual(connection.submitted, ["INSERT INTO t VALUES (1)"])
        XCTAssertTrue(summary.wasCancelled)
        XCTAssertTrue(output.hasSuffix(SAScriptOutputFormatter.cancelled))
        XCTAssertEqual(occurrences(of: SAScriptOutputFormatter.cancelled, in: output), 1)
    }

    func testStopWhileStatementHeaderIsPrintedNeverSubmitsTheStatement() {
        let connection = FakeScriptConnection()
        let token = SAScriptCancellationToken()
        let (summary, output) = run(["INSERT INTO t VALUES (1)", "DROP TABLE t"],
                                    on: connection,
                                    token: token,
                                    onOutput: { text in if text.contains("DROP TABLE t") { token.cancel() } })

        XCTAssertEqual(connection.submitted, ["INSERT INTO t VALUES (1)"])
        XCTAssertTrue(summary.wasCancelled)
        XCTAssertFalse(summary.tableListNeedsReload)
        XCTAssertTrue(output.hasSuffix(SAScriptOutputFormatter.cancelled))
    }

    func testStopDuringDatabaseCaseLookupNeverSubmitsTheDrop() {
        let connection = FakeScriptConnection()
        let token = SAScriptCancellationToken()
        connection.whileExecuting = { sql in
            if sql == "SELECT @@lower_case_table_names" { token.cancel() }
        }
        let (summary, output) = run(["DROP DATABASE SHOP"], on: connection, database: "shop", token: token)

        XCTAssertEqual(connection.submitted, ["SELECT @@lower_case_table_names"])
        XCTAssertTrue(summary.wasCancelled)
        XCTAssertFalse(summary.databaseChanged)
        XCTAssertEqual(summary.finalDatabase, "shop")
        XCTAssertTrue(output.hasSuffix(SAScriptOutputFormatter.cancelled))
    }

    // MARK: - R2: a statement that completed keeps its side-effect bookkeeping

    func testUseThatCompletesWhileStopRacesStillTracksTheDatabase() {
        let connection = FakeScriptConnection()
        let token = SAScriptCancellationToken()
        connection.outcomes["USE other_db"] = .ok(affectedRows: 0)
        connection.whileExecuting = { sql in
            guard sql == "USE other_db" else { return }
            // Stop arrives as the server finishes: token first, then the
            // connection-level cancel that finds nothing left to kill.
            token.cancel()
            connection.scriptLastQueryWasCancelled = true
        }
        let (summary, output) = run(["USE other_db", "DELETE FROM t"], on: connection, token: token)

        XCTAssertEqual(connection.submitted, ["USE other_db"])
        XCTAssertTrue(summary.wasCancelled)
        XCTAssertTrue(summary.databaseChanged)
        XCTAssertEqual(summary.finalDatabase, "other_db")
        XCTAssertTrue(output.hasSuffix("Query OK, 0 rows affected\n\n" + SAScriptOutputFormatter.cancelled))
    }

    func testCreateTableThatCompletesWhileStopRacesStillReloadsTables() {
        let connection = FakeScriptConnection()
        let token = SAScriptCancellationToken()
        connection.outcomes["CREATE TABLE t (id INT)"] = .ok(affectedRows: 0)
        connection.whileExecuting = { sql in if sql.hasPrefix("CREATE") { token.cancel() } }
        let (summary, output) = run(["CREATE TABLE t (id INT)", "INSERT INTO t VALUES (1)"], on: connection, token: token)

        XCTAssertEqual(connection.submitted, ["CREATE TABLE t (id INT)"])
        XCTAssertTrue(summary.wasCancelled)
        XCTAssertTrue(summary.tableListNeedsReload)
        XCTAssertTrue(output.hasSuffix("Query OK, 0 rows affected\n\n" + SAScriptOutputFormatter.cancelled))
    }

    func testStatementInterruptedByStopIsNotTreatedAsCompleted() {
        let connection = FakeScriptConnection()
        let token = SAScriptCancellationToken()
        connection.outcomes["DROP TABLE t"] = .error(code: 1317, sqlState: "70100", message: "Query execution was interrupted")
        connection.whileExecuting = { sql in if sql == "DROP TABLE t" { token.cancel() } }
        let (summary, output) = run(["DROP TABLE t", "SELECT 1"], on: connection, token: token)

        XCTAssertEqual(connection.submitted, ["DROP TABLE t"])
        XCTAssertTrue(summary.wasCancelled)
        XCTAssertFalse(summary.tableListNeedsReload)
        XCTAssertEqual(summary.errorCount, 0)
        XCTAssertFalse(output.contains("Query OK"))
        XCTAssertTrue(output.hasSuffix(SAScriptOutputFormatter.cancelled))
    }

    func testStopWhileStreamingRowsCancelsTheLoad() {
        let connection = FakeScriptConnection()
        let token = SAScriptCancellationToken()
        connection.outcomes["SELECT a FROM t"] = .rows(columns: ["a"], rows: [[.text("1")], [.text("2")], [.text("3")]])
        let (summary, output) = run(["SELECT a FROM t", "SELECT 2"],
                                    on: connection,
                                    token: token,
                                    onOutput: { text in if text == "1\n" { token.cancel() } })

        XCTAssertEqual(connection.submitted, ["SELECT a FROM t"])
        XCTAssertTrue(summary.wasCancelled)
        XCTAssertEqual(connection.cancelledLoads, 1)
        XCTAssertFalse(output.contains("in set"))
        XCTAssertTrue(output.hasSuffix("a\n1\n" + SAScriptOutputFormatter.cancelled))
    }

    // MARK: - Token admission

    func testAdmitQueryRunsTheOperationUntilCancelled() {
        let token = SAScriptCancellationToken()
        var runs = 0

        XCTAssertEqual(token.admitQuery { () -> Int in runs += 1; return 7 }, 7)
        token.cancel()
        XCTAssertTrue(token.isCancelled)
        XCTAssertNil(token.admitQuery { () -> Int in runs += 1; return 8 })
        XCTAssertEqual(runs, 1)
    }

    func testRequestQueryCancellationRetriesWhileAQueryIsAdmittedAndStopsWhenItEnds() {
        let token = SAScriptCancellationToken()
        let queryStarted = expectation(description: "query admitted")
        let secondAttempt = expectation(description: "cancellation retried")
        let queryFinished = expectation(description: "query finished")
        let allowQueryToFinish = DispatchSemaphore(value: 0)
        let countLock = NSLock()
        var attempts = 0

        DispatchQueue.global().async {
            _ = token.admitQuery { () -> Bool in
                queryStarted.fulfill()
                allowQueryToFinish.wait()
                return true
            }
            queryFinished.fulfill()
        }
        wait(for: [queryStarted], timeout: 2)

        token.cancel()
        token.requestQueryCancellation {
            XCTAssertFalse(Thread.isMainThread)
            countLock.lock()
            attempts += 1
            let attempt = attempts
            countLock.unlock()
            // The first attempt models a cancel that reaches the connection
            // before the admitted query does, so the query keeps running.
            if attempt == 2 {
                secondAttempt.fulfill()
                allowQueryToFinish.signal()
            }
        }
        wait(for: [secondAttempt, queryFinished], timeout: 2)

        // admitQuery has returned, so any later attempt finds nothing admitted.
        countLock.lock()
        let attemptsWhenQueryEnded = attempts
        countLock.unlock()
        let noLaterAttempt = expectation(description: "no attempt after the query ended")
        noLaterAttempt.isInverted = true
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) {
            countLock.lock()
            let later = attempts
            countLock.unlock()
            if later != attemptsWhenQueryEnded { noLaterAttempt.fulfill() }
        }
        wait(for: [noLaterAttempt], timeout: 0.3)
    }

    func testRequestQueryCancellationDoesNothingWithoutAnAdmittedQuery() {
        let token = SAScriptCancellationToken()
        let attempted = expectation(description: "cancellation attempted")
        attempted.isInverted = true

        token.cancel()
        token.requestQueryCancellation { attempted.fulfill() }

        wait(for: [attempted], timeout: 0.1)
    }

    // MARK: - Helpers

    private func occurrences(of needle: String, in haystack: String) -> Int {
        haystack.components(separatedBy: needle).count - 1
    }

    private func run(_ sql: [String],
                     on connection: FakeScriptConnection,
                     database: String? = "shop",
                     continueOnError: Bool = false,
                     token: SAScriptCancellationToken = SAScriptCancellationToken(),
                     onProgress: ((Int) -> Void)? = nil,
                     onOutput: ((String) -> Void)? = nil) -> (SAScriptRunSummary, String) {
        var output = ""
        let runner = SAScriptRunner(connection: connection,
                                    cancellation: token,
                                    output: { text in
                                        output += text
                                        onOutput?(text)
                                    },
                                    progress: { index, _ in onProgress?(index) })
        let statements = sql.enumerated().map { SAScriptStatement(text: $0.element, line: $0.offset + 1) }
        let summary = runner.run(statements: statements, database: database, continueOnError: continueOnError)
        return (summary, output)
    }
}

// MARK: - Fakes

private final class FakeScriptResult: SAScriptQueryResult {
    let fieldNames: [String]
    private var rows: [[SAScriptCell]]
    private let onCancelLoad: () -> Void

    init(columns: [String], rows: [[SAScriptCell]], onCancelLoad: @escaping () -> Void) {
        fieldNames = columns
        self.rows = rows
        self.onCancelLoad = onCancelLoad
    }

    var numberOfFields: Int { fieldNames.count }
    var queryExecutionTime: Double { 0.001 }

    func nextRow() -> [SAScriptCell]? {
        rows.isEmpty ? nil : rows.removeFirst()
    }

    func cancelLoad() {
        rows.removeAll()
        onCancelLoad()
    }
}

private final class FakeScriptConnection: SAScriptQueryConnection {

    enum Outcome {
        case ok(affectedRows: UInt64)
        case rows(columns: [String], rows: [[SAScriptCell]])
        case error(code: Int, sqlState: String, message: String)
    }

    /// Every SQL string handed to the connection, lookups included, in order.
    private(set) var submitted: [String] = []
    /// Outcome per statement; anything not listed succeeds with 1 row affected.
    var outcomes: [String: Outcome] = [:]
    /// Called while a statement or lookup is "executing" on the server.
    var whileExecuting: ((String) -> Void)?
    /// Value returned for `SELECT @@lower_case_table_names`.
    var lowerCaseTableNames: Any? = "0"

    var retryQueriesOnConnectionFailure = true
    var scriptServerVersion = 80_036
    var scriptServerVersionString: String? = "8.0.36"
    private(set) var scriptQueryErrored = false
    private(set) var scriptLastErrorID = 0
    private(set) var scriptLastSqlstate: String?
    private(set) var scriptLastErrorMessage: String?
    private(set) var scriptRowsAffectedByLastQuery: UInt64 = 0
    var scriptLastQueryWasCancelled = false
    /// How many streamed results the runner discarded with cancelLoad().
    private(set) var cancelledLoads = 0

    func runScriptStatement(_ statement: String, assertingDatabaseContext database: String?) -> SAScriptQueryResult? {
        begin(statement)
        whileExecuting?(statement)
        switch outcomes[statement] ?? .ok(affectedRows: 1) {
        case .ok(let affectedRows):
            scriptRowsAffectedByLastQuery = affectedRows
            return makeResult(columns: [], rows: [])
        case .rows(let columns, let rows):
            scriptRowsAffectedByLastQuery = UInt64(rows.count)
            return makeResult(columns: columns, rows: rows)
        case .error(let code, let sqlState, let message):
            scriptQueryErrored = true
            scriptLastErrorID = code
            scriptLastSqlstate = sqlState
            scriptLastErrorMessage = message
            return nil
        }
    }

    func scriptFirstField(fromQuery query: String, assertingDatabase database: String?) -> Any? {
        begin(query)
        whileExecuting?(query)
        return lowerCaseTableNames
    }

    private func makeResult(columns: [String], rows: [[SAScriptCell]]) -> FakeScriptResult {
        FakeScriptResult(columns: columns, rows: rows, onCancelLoad: { [weak self] in self?.cancelledLoads += 1 })
    }

    /// Mirrors SPMySQLConnection: each new query starts with fresh error and
    /// cancellation state.
    private func begin(_ sql: String) {
        submitted.append(sql)
        scriptQueryErrored = false
        scriptLastErrorID = 0
        scriptLastSqlstate = nil
        scriptLastErrorMessage = nil
        scriptLastQueryWasCancelled = false
    }
}
