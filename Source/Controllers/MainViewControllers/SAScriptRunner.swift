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

import Foundation

struct SAScriptStatement: Equatable {
    /// Normalised statement text, as sent to the server.
    let text: String
    /// 1-based line, within the text that was run, of the statement's first
    /// non-whitespace character (mysql's "at line N").
    let line: Int
}

enum SAScriptStatementSplitter {

    /// Split `sql` into executable statements, honouring `DELIMITER`
    /// commands, quoted strings and comments the same way Run All does.
    static func statements(in sql: String) -> [SAScriptStatement] {
        let text = sql as NSString
        let parser = SPSQLParser(string: sql)
        parser.setDelimiterSupport(true)
        let semicolon = UInt16(UnicodeScalar(";").value)
        let ranges = (parser.splitStringIntoRanges(byCharacter: semicolon) as? [NSValue]) ?? []

        return ranges.compactMap { value in
            let range = NSIntersectionRange(value.rangeValue, NSRange(location: 0, length: text.length))
            let raw = text.substring(with: range)
            guard !SAScriptStatementLocator.isEmptyStatement(raw) else { return nil }
            let start = SAScriptStatementLocator.firstNonWhitespaceOffset(in: range, of: text)
            let normalised = SPSQLParser.normaliseQuery(forExecution: raw)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return SAScriptStatement(text: normalised,
                                     line: SAScriptStatementLocator.lineNumber(ofOffset: start, in: text))
        }
    }
}

struct SAScriptRunSummary {
    var queriesRun = 0
    var totalAffectedRows: UInt64 = 0
    var executionTime: Double = 0
    var errorCount = 0
    var wasCancelled = false
    var finalDatabase: String?
    var databaseChanged = false
    var tableListNeedsReload = false
    var executedStatements: [String] = []
}

extension SAScriptCell {
    init(mysqlValue value: Any) {
        switch value {
        case is NSNull:
            self = .null
        case let geometry as SPMySQLGeometryData:
            self = .binary(geometry.data() ?? Data())
        case let data as Data:
            self = .binary(data)
        case let string as String:
            self = .text(string)
        case let number as NSNumber:
            self = .text(number.stringValue)
        default:
            self = .text(String(describing: value))
        }
    }
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

    private let connection: SPMySQLConnection
    private let cancellation: SAScriptCancellationToken
    private let output: (String) -> Void
    private let progress: (_ index: Int, _ total: Int) -> Void

    init(connection: SPMySQLConnection,
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
        let serverVersion = Int(connection.serverMajorVersion()) * 10000
            + Int(connection.serverMinorVersion()) * 100
            + Int(connection.serverReleaseVersion())
        let serverIsMariaDB = (connection.serverVersionString() ?? "").range(of: "mariadb", options: .caseInsensitive) != nil
        var databaseNamesAreCaseSensitive = false
        var caseSensitivityLoaded = false

        connection.retryQueriesOnConnectionFailure = false
        defer { connection.retryQueriesOnConnectionFailure = true }

        for (index, statement) in statements.enumerated() {
            if isCancelled {
                finishCancelled(&summary, result: nil)
                break
            }
            progress(index, statements.count)
            summary.executedStatements.append(statement.text)
            output(SAScriptOutputFormatter.statementHeader(statement.text))

            if !caseSensitivityLoaded
                && SASQLDatabaseContext.requiresDatabaseNameCaseSensitivityLookup(for: statement.text,
                                                                                currentDatabase: currentDatabase,
                                                                                serverVersion: serverVersion,
                                                                                serverIsMariaDB: serverIsMariaDB) {
                let setting = connection.getFirstField(fromQuery: "SELECT @@lower_case_table_names", assertingDatabase: currentDatabase)
                // If the setting cannot be read, prefer clearing a case-only match over retaining a stale assertion.
                databaseNamesAreCaseSensitive = (setting as? NSString)?.integerValue == 0 || (setting as? NSNumber)?.intValue == 0
                caseSensitivityLoaded = true
            }

            let result = connection.queryString(statement.text,
                                                usingEncoding: connection.stringEncoding(),
                                                with: SPMySQLResultAsFastStreamingResult,
                                                assertingDatabaseContext: currentDatabase) as? SPMySQLResult
            summary.queriesRun += 1
            summary.executionTime += result?.queryExecutionTime() ?? 0

            if isCancelled {
                finishCancelled(&summary, result: result)
                break
            }

            // A nil result means the query never ran (e.g. disconnected), even
            // when the connection recorded no error.
            guard let result, !connection.queryErrored() else {
                summary.errorCount += 1
                output(errorText(for: statement))
                if continueOnError { continue }
                break
            }

            if result.numberOfFields() > 0 {
                let columns = (result.fieldNames() as? [String]) ?? []
                var rowCount: UInt64 = 0
                var cancelledWhileStreaming = false
                while let row = result.getRowAsArray() {
                    if rowCount == 0 {
                        output(SAScriptOutputFormatter.resultHeader(columns: columns))
                    }
                    output(SAScriptOutputFormatter.row(row.map(SAScriptCell.init(mysqlValue:))))
                    rowCount += 1
                    if isCancelled {
                        cancelledWhileStreaming = true
                        break
                    }
                }
                if cancelledWhileStreaming || isCancelled {
                    finishCancelled(&summary, result: result)
                    break
                }
                if connection.queryErrored() {
                    // An error while streaming rows (e.g. lost connection).
                    summary.errorCount += 1
                    output(errorText(for: statement))
                    if continueOnError { continue }
                    break
                }
                output(SAScriptOutputFormatter.rowsInSetFooter(count: rowCount))
                summary.totalAffectedRows += rowCount
            } else {
                let affected = connection.rowsAffectedByLastQuery()
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

    private var isCancelled: Bool {
        cancellation.isCancelled || connection.lastQueryWasCancelled
    }

    /// Single exit path for every cancellation: drain/cancel any open
    /// streaming result so the connection is not left mid-result.
    private func finishCancelled(_ summary: inout SAScriptRunSummary, result: SPMySQLResult?) {
        (result as? SPMySQLStreamingResult)?.cancelLoad()
        output(SAScriptOutputFormatter.cancelled)
        summary.wasCancelled = true
    }

    private func errorText(for statement: SAScriptStatement) -> String {
        if connection.queryErrored() {
            let sqlState = connection.lastSqlstate().flatMap { $0.isEmpty ? nil : $0 } ?? "HY000"
            return SAScriptOutputFormatter.error(code: Int(connection.lastErrorID()),
                                                 sqlState: sqlState,
                                                 line: statement.line,
                                                 message: connection.lastErrorMessage() ?? "")
        }
        // No result and no recorded error: synthesise mysql's CR_SERVER_GONE_ERROR.
        let message = connection.lastErrorMessage().flatMap { $0.isEmpty ? nil : $0 } ?? "MySQL server has gone away"
        return SAScriptOutputFormatter.error(code: 2006, sqlState: "HY000", line: statement.line, message: message)
    }
}
