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
