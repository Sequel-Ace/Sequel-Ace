//
//  SAStatementReport.swift
//  SPMySQLFramework
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//
//  More info at <https://github.com/Sequel-Ace/Sequel-Ace>
//

import Foundation

/// What a statement reported, as the connection keeps it for its caller to read: the error, the
/// rows it affected, the row it inserted, and whether it was cancelled.
///
/// The connection keeps one such report, the last statement's. While the main thread waits for a
/// statement that runs on the connection's worker, the wait delivers the window's events, and one
/// of them can run a statement of its own on the same connection - whose report then stands on
/// the connection when the first statement returns to its caller. Each statement therefore takes
/// its report with its result, and puts it back for its caller.
@objc(SAStatementReport)
public final class SAStatementReport: NSObject {

    /// The error message, or nil when the statement did not fail.
    @objc public let errorMessage: String?

    /// The error number; zero when the statement did not fail.
    @objc public let errorID: UInt

    /// The SQL state, or nil when the statement did not fail.
    @objc public let sqlState: String?

    /// The rows the statement changed, deleted, inserted or selected.
    @objc public let affectedRows: UInt64

    /// The insert ID the connection carries, which an insert sets and other statements leave.
    @objc public let insertID: UInt64

    /// Whether the statement was cancelled.
    @objc public let wasCancelled: Bool

    /// Keeps what the connection reports now.
    /// - Parameters:
    ///   - errorMessage: The error message, or nil.
    ///   - errorID: The error number.
    ///   - sqlState: The SQL state, or nil.
    ///   - affectedRows: The rows affected.
    ///   - insertID: The insert ID carried.
    ///   - wasCancelled: Whether the statement was cancelled.
    @objc(initWithErrorMessage:errorID:sqlState:affectedRows:insertID:wasCancelled:)
    public init(errorMessage: String?, errorID: UInt, sqlState: String?, affectedRows: UInt64, insertID: UInt64, wasCancelled: Bool) {
        self.errorMessage = errorMessage
        self.errorID = errorID
        self.sqlState = sqlState
        self.affectedRows = affectedRows
        self.insertID = insertID
        self.wasCancelled = wasCancelled
        super.init()
    }
}

/// A statement's result together with its report, as the work that ran the statement hands both
/// back to the caller that asked for it.
@objc(SAStatementRun)
public final class SAStatementRun: NSObject {

    /// What the statement returned, or nil when it failed.
    @objc public let result: Any?

    /// What the statement reported.
    @objc public let report: SAStatementReport

    /// Keeps a result with its report.
    /// - Parameters:
    ///   - result: What the statement returned, or nil.
    ///   - report: What it reported.
    @objc(initWithResult:report:)
    public init(result: Any?, report: SAStatementReport) {
        self.result = result
        self.report = report
        super.init()
    }
}
