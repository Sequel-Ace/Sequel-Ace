//
//  SAScriptConsoleEvent.swift
//  Sequel Ace
//
//  Structured Run All console output, emitted next to the text log so the
//  console can draw statement blocks; the text log stays the source of
//  Copy all / Save.
//

import Foundation

enum SAScriptConsoleEvent: Equatable {
    /// The echoed statement (comments stripped, as the text log echoes it).
    case statementStarted(sql: String)
    /// `SAScriptOutputFormatter.resultHeader(columns:)` text.
    case resultHeader(String)
    /// `SAScriptOutputFormatter.row(_:)` text.
    case row(String)
    case rowsInSet(count: UInt64)
    case queryOK(affectedRows: UInt64)
    /// The error line without trailing newlines.
    case failed(message: String)
    case cancelled
    /// `time` in seconds; `continuing` is false when the run stops after this statement.
    case statementFinished(time: Double, continuing: Bool)
}
