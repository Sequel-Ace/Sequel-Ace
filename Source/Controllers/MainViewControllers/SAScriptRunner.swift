//
//  SAScriptRunner.swift
//  Sequel Ace
//
//  Executes the statements of a "Run All as Script" run on the tab's
//  connection and streams mysql -vv style text for every statement. Mirrors
//  the bookkeeping of -[SPCustomQuery performQueriesTask:] (database context
//  tracking, table-list reload detection, retry suppression) but keeps every
//  result set instead of only the last one.
//
//  Talks to the connection through SAScriptQueryConnection so it is free of
//  project ObjC types and also builds in the Unit Tests target; the
//  SPMySQLConnection conformance lives in SAScriptRunner+SPMySQL.swift.
//

import Foundation

struct SAScriptStatement: Equatable {
    /// Normalised statement text, as sent to the server.
    let text: String
    /// 1-based line, within the text that was run, of the statement's first
    /// non-whitespace character (mysql's "at line N").
    let line: Int
}

struct SAScriptRunSummary {
    var queriesRun = 0
    var totalAffectedRows: UInt64 = 0
    var executionTime: Double = 0
    var errorCount = 0
    /// Each `ERROR … at line N: …` line printed, without its trailing blank line.
    var errorLines: [String] = []
    var wasCancelled = false
    var finalDatabase: String?
    var databaseChanged = false
    var tableListNeedsReload = false
    var executedStatements: [String] = []
}

/// A result returned by `SAScriptQueryConnection.runScriptStatement`.
protocol SAScriptQueryResult: AnyObject {
    var numberOfFields: Int { get }
    var fieldNames: [String] { get }
    var queryExecutionTime: Double { get }
    /// The next row of a streamed result set, or nil once it is exhausted.
    func nextRow() -> [SAScriptCell]?
    /// Discard the rest of a streamed result set.
    func cancelLoad()
}

/// The connection operations a script run needs.
protocol SAScriptQueryConnection: AnyObject {
    var retryQueriesOnConnectionFailure: Bool { get set }
    /// major * 10000 + minor * 100 + release.
    var scriptServerVersion: Int { get }
    var scriptServerVersionString: String? { get }
    /// Run one statement as a streamed result, asserting the database context.
    func runScriptStatement(_ statement: String, assertingDatabaseContext database: String?) -> SAScriptQueryResult?
    func scriptFirstField(fromQuery query: String, assertingDatabase database: String?) -> Any?
    var scriptQueryErrored: Bool { get }
    var scriptLastErrorID: Int { get }
    var scriptLastSqlstate: String? { get }
    var scriptLastErrorMessage: String? { get }
    var scriptRowsAffectedByLastQuery: UInt64 { get }
    var scriptLastQueryWasCancelled: Bool { get }
}

/// Passed as the task's cancellation callback object. SATaskController calls
/// `cancel()` and then routes the connection-level cancel through
/// `requestQueryCancellation(_:)`. Every query the runner starts goes through
/// `admitQuery(_:)`, so once Stop is recorded no further SQL is submitted, and
/// a query admitted just before Stop keeps being cancelled until it ends.
@objc final class SAScriptCancellationToken: NSObject, SAQueryCancellationRequesting {
    private let admission = SAQueryAdmission(
        cancellationQueueLabel: "com.sequel-ace.script-query-cancellation"
    )

    var isCancelled: Bool {
        admission.isCancellationRequested
    }

    @objc func cancel() {
        admission.requestCancellation()
    }

    /// Runs `operation`, which starts (and may stream) one query, unless Stop
    /// was already requested; returns nil without running it in that case.
    func admitQuery<T>(_ operation: () -> T) -> T? {
        admission.admit(operation)
    }

    func requestQueryCancellation(_ cancellation: @escaping () -> Void) {
        admission.requestQueryCancellation(cancellation)
    }
}

final class SAScriptRunner {

    // Same patterns -[SPCustomQuery performQueriesTask:] uses.
    private static let tableListChangeRegex = try! NSRegularExpression(pattern: "^\\s*\\b(create|alter|drop|rename)\\b\\s+.", options: [.caseInsensitive])
    private static let databaseChangeRegex = try! NSRegularExpression(pattern: "^\\s*\\b(use|drop\\s+database|drop\\s+schema)\\b\\s+.", options: [.caseInsensitive])

    private let connection: SAScriptQueryConnection
    private let cancellation: SAScriptCancellationToken
    private let output: (String) -> Void
    private let progress: (_ index: Int, _ total: Int) -> Void

    init(connection: SAScriptQueryConnection,
         cancellation: SAScriptCancellationToken,
         output: @escaping (String) -> Void,
         progress: @escaping (_ index: Int, _ total: Int) -> Void) {
        self.connection = connection
        self.cancellation = cancellation
        self.output = output
        self.progress = progress
    }

    /// Run `statements` in order. Must be called off the main thread.
    func run(statements: [SAScriptStatement], database: String?, continueOnError: Bool) -> SAScriptRunSummary {
        var summary = SAScriptRunSummary()
        var currentDatabase = database
        let serverVersion = connection.scriptServerVersion
        let serverIsMariaDB = (connection.scriptServerVersionString ?? "").range(of: "mariadb", options: .caseInsensitive) != nil
        var databaseNamesAreCaseSensitive = false
        var caseSensitivityLoaded = false

        connection.retryQueriesOnConnectionFailure = false
        defer { connection.retryQueriesOnConnectionFailure = true }

        for (index, statement) in statements.enumerated() {
            // A cheap early exit only: admission below is what guarantees no
            // SQL is submitted after Stop. (Only the token here: the
            // connection's lastQueryWasCancelled can be stale from an earlier
            // Stop until this run issues its first query.)
            if cancellation.isCancelled {
                finishCancelled(&summary)
                break
            }
            progress(index, statements.count)
            output(SAScriptOutputFormatter.statementHeader(SAScriptOutputFormatter.echoText(for: statement.text)))

            if !caseSensitivityLoaded
                && SASQLDatabaseContext.requiresDatabaseNameCaseSensitivityLookup(for: statement.text,
                                                                                currentDatabase: currentDatabase,
                                                                                serverVersion: serverVersion,
                                                                                serverIsMariaDB: serverIsMariaDB) {
                guard let setting = cancellation.admitQuery({
                    connection.scriptFirstField(fromQuery: "SELECT @@lower_case_table_names", assertingDatabase: currentDatabase)
                }) else {
                    finishCancelled(&summary)
                    break
                }
                // If the setting cannot be read, prefer clearing a case-only match over retaining a stale assertion.
                databaseNamesAreCaseSensitive = (setting as? NSString)?.integerValue == 0 || (setting as? NSNumber)?.intValue == 0
                caseSensitivityLoaded = true
            }

            // The statement stays admitted while its rows stream, so a Stop
            // during a long result set still interrupts the query.
            guard let execution = cancellation.admitQuery({ execute(statement, in: currentDatabase) }) else {
                finishCancelled(&summary)
                break
            }
            summary.queriesRun += 1
            summary.executedStatements.append(statement.text)
            summary.executionTime += execution.time

            switch execution.outcome {
            case .cancelled:
                finishCancelled(&summary)
            case .failed:
                reportError(for: statement, in: &summary)
            case .completed(let affectedRows, let stopRequested):
                summary.totalAffectedRows += affectedRows
                // The server committed the statement: record its side effects
                // even when Stop raced its completion.
                recordSideEffects(of: statement.text,
                                  currentDatabase: &currentDatabase,
                                  databaseNamesAreCaseSensitive: databaseNamesAreCaseSensitive,
                                  serverVersion: serverVersion,
                                  serverIsMariaDB: serverIsMariaDB,
                                  in: &summary)
                if stopRequested {
                    finishCancelled(&summary)
                }
            }
            if summary.wasCancelled { break }
            if case .failed = execution.outcome, !continueOnError { break }
        }

        summary.finalDatabase = currentDatabase
        return summary
    }

    private enum StatementOutcome {
        /// Interrupted (or its result discarded) by Stop; nothing to record.
        case cancelled
        /// Errored, or never ran; the connection holds the error state.
        case failed
        /// Completed on the server. `stopRequested` when Stop raced it.
        case completed(affectedRows: UInt64, stopRequested: Bool)
    }

    /// Runs one statement and prints its result. Called inside admission.
    private func execute(_ statement: SAScriptStatement, in database: String?) -> (outcome: StatementOutcome, time: Double) {
        let result = connection.runScriptStatement(statement.text, assertingDatabaseContext: database)
        let time = result?.queryExecutionTime ?? 0
        // The query just reset lastQueryWasCancelled, so it reflects a Stop of
        // this statement only.
        let stopRequested = cancellation.isCancelled || connection.scriptLastQueryWasCancelled

        // A nil result means the query never ran (e.g. disconnected), even
        // when the connection recorded no error.
        guard let result, !connection.scriptQueryErrored else {
            return (stopRequested ? .cancelled : .failed, time)
        }

        guard result.numberOfFields > 0 else {
            let affected = connection.scriptRowsAffectedByLastQuery
            let count = affected == UInt64.max ? 0 : affected
            output(SAScriptOutputFormatter.queryOK(affectedRows: count))
            return (.completed(affectedRows: count, stopRequested: stopRequested), time)
        }

        // Drain/cancel an open streaming result so the connection is not
        // left mid-result.
        if stopRequested {
            result.cancelLoad()
            return (.cancelled, time)
        }
        let columns = result.fieldNames
        var rowCount: UInt64 = 0
        while !cancellation.isCancelled, let row = result.nextRow() {
            if rowCount == 0 {
                output(SAScriptOutputFormatter.resultHeader(columns: columns))
            }
            output(SAScriptOutputFormatter.row(row))
            rowCount += 1
        }
        if cancellation.isCancelled {
            result.cancelLoad()
            return (.cancelled, time)
        }
        if connection.scriptQueryErrored {
            // An error while streaming rows (e.g. lost connection).
            return (.failed, time)
        }
        output(SAScriptOutputFormatter.rowsInSetFooter(count: rowCount))
        return (.completed(affectedRows: rowCount, stopRequested: false), time)
    }

    private func recordSideEffects(of statement: String,
                                   currentDatabase: inout String?,
                                   databaseNamesAreCaseSensitive: Bool,
                                   serverVersion: Int,
                                   serverIsMariaDB: Bool,
                                   in summary: inout SAScriptRunSummary) {
        let fullRange = NSRange(location: 0, length: (statement as NSString).length)
        if Self.tableListChangeRegex.firstMatch(in: statement, range: fullRange) != nil {
            summary.tableListNeedsReload = true
        }
        if Self.databaseChangeRegex.firstMatch(in: statement, range: fullRange) != nil {
            summary.databaseChanged = true
        }
        let updatedDatabase = SASQLDatabaseContext.databaseName(afterSuccessfulQuery: statement,
                                                                currentDatabase: currentDatabase,
                                                                databaseNamesAreCaseSensitive: databaseNamesAreCaseSensitive,
                                                                serverVersion: serverVersion,
                                                                serverIsMariaDB: serverIsMariaDB)
        if SASQLDatabaseContext.databaseNameChanged(from: currentDatabase, to: updatedDatabase) {
            summary.databaseChanged = true
        }
        currentDatabase = updatedDatabase
    }

    /// Single exit path for every cancellation.
    private func finishCancelled(_ summary: inout SAScriptRunSummary) {
        output(SAScriptOutputFormatter.cancelled)
        summary.wasCancelled = true
    }

    private func reportError(for statement: SAScriptStatement, in summary: inout SAScriptRunSummary) {
        let text = errorText(for: statement)
        output(text)
        summary.errorCount += 1
        summary.errorLines.append(text.trimmingCharacters(in: .newlines))
    }

    private func errorText(for statement: SAScriptStatement) -> String {
        if connection.scriptQueryErrored {
            let sqlState = connection.scriptLastSqlstate.flatMap { $0.isEmpty ? nil : $0 } ?? "HY000"
            return SAScriptOutputFormatter.error(code: connection.scriptLastErrorID,
                                                 sqlState: sqlState,
                                                 line: statement.line,
                                                 message: connection.scriptLastErrorMessage ?? "")
        }
        // No result and no recorded error: synthesise mysql's CR_SERVER_GONE_ERROR.
        let message = connection.scriptLastErrorMessage.flatMap { $0.isEmpty ? nil : $0 } ?? "MySQL server has gone away"
        return SAScriptOutputFormatter.error(code: 2006, sqlState: "HY000", line: statement.line, message: message)
    }
}
