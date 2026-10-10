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

/// Passed as the task's cancellation callback object: SATaskController calls
/// `cancel()` before cancelling the in-flight query, so the runner also notices
/// a cancel that arrives between statements or while buffered rows are being
/// emitted (when the connection has no query in flight to flag).
@objc final class SAScriptCancellationToken: NSObject {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    @objc func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
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
            // Only the token here: the connection's lastQueryWasCancelled can be
            // stale from an earlier Stop until this run issues its first query.
            if cancellation.isCancelled {
                finishCancelled(&summary, result: nil)
                break
            }
            progress(index, statements.count)
            summary.executedStatements.append(statement.text)
            output(SAScriptOutputFormatter.statementHeader(SAScriptOutputFormatter.echoText(for: statement.text)))

            if !caseSensitivityLoaded
                && SASQLDatabaseContext.requiresDatabaseNameCaseSensitivityLookup(for: statement.text,
                                                                                currentDatabase: currentDatabase,
                                                                                serverVersion: serverVersion,
                                                                                serverIsMariaDB: serverIsMariaDB) {
                let setting = connection.scriptFirstField(fromQuery: "SELECT @@lower_case_table_names", assertingDatabase: currentDatabase)
                // If the setting cannot be read, prefer clearing a case-only match over retaining a stale assertion.
                databaseNamesAreCaseSensitive = (setting as? NSString)?.integerValue == 0 || (setting as? NSNumber)?.intValue == 0
                caseSensitivityLoaded = true
            }

            let result = connection.runScriptStatement(statement.text, assertingDatabaseContext: currentDatabase)
            summary.queriesRun += 1
            summary.executionTime += result?.queryExecutionTime ?? 0

            // queryString just reset lastQueryWasCancelled, so here it reflects
            // a Stop of this statement only.
            if cancellation.isCancelled || connection.scriptLastQueryWasCancelled {
                finishCancelled(&summary, result: result)
                break
            }

            // A nil result means the query never ran (e.g. disconnected), even
            // when the connection recorded no error.
            guard let result, !connection.scriptQueryErrored else {
                reportError(for: statement, in: &summary)
                if continueOnError { continue }
                break
            }

            if result.numberOfFields > 0 {
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
                    finishCancelled(&summary, result: result)
                    break
                }
                if connection.scriptQueryErrored {
                    // An error while streaming rows (e.g. lost connection).
                    reportError(for: statement, in: &summary)
                    if continueOnError { continue }
                    break
                }
                output(SAScriptOutputFormatter.rowsInSetFooter(count: rowCount))
                summary.totalAffectedRows += rowCount
            } else {
                let affected = connection.scriptRowsAffectedByLastQuery
                let count = affected == UInt64.max ? 0 : affected
                output(SAScriptOutputFormatter.queryOK(affectedRows: count))
                summary.totalAffectedRows += count
            }

            let fullRange = NSRange(location: 0, length: (statement.text as NSString).length)
            if Self.tableListChangeRegex.firstMatch(in: statement.text, range: fullRange) != nil {
                summary.tableListNeedsReload = true
            }
            if Self.databaseChangeRegex.firstMatch(in: statement.text, range: fullRange) != nil {
                summary.databaseChanged = true
            }
            let updatedDatabase = SASQLDatabaseContext.databaseName(afterSuccessfulQuery: statement.text,
                                                                    currentDatabase: currentDatabase,
                                                                    databaseNamesAreCaseSensitive: databaseNamesAreCaseSensitive,
                                                                    serverVersion: serverVersion,
                                                                    serverIsMariaDB: serverIsMariaDB)
            if SASQLDatabaseContext.databaseNameChanged(from: currentDatabase, to: updatedDatabase) {
                summary.databaseChanged = true
            }
            currentDatabase = updatedDatabase
        }

        summary.finalDatabase = currentDatabase
        return summary
    }

    /// Single exit path for every cancellation: drain/cancel any open
    /// streaming result so the connection is not left mid-result.
    private func finishCancelled(_ summary: inout SAScriptRunSummary, result: SAScriptQueryResult?) {
        result?.cancelLoad()
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
