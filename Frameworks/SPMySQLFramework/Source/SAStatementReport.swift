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
/// The connection keeps one such report, the last statement's, written by the statement while it
/// holds the session. A caller that was handed its statement's result - the main thread, whose
/// statement ran on the connection's worker while the window kept answering - reads a report
/// handed back to it instead: by the time it reads, another statement can have run on the
/// connection and written its own report there, from an event the wait delivered or from another
/// thread. A report handed back belongs to the thread it was handed to, and to the connection it
/// was about; it stands until that thread's next statement on the connection or, on the main
/// thread, the next turn of its run loop, whichever comes first - the caller reads it straight
/// after the call that handed it back - and nothing of it is ever written over the report of a
/// statement running. A thread reads the connection's own report - the last statement's,
/// whichever thread ran it - when nothing is handed back to it, and also while those fields still
/// describe the statement handed back, that is until a later statement starts on the connection
/// (``statementNumber``): what a statement reports after its report was taken - the error or stop
/// of a streaming download, a failed connection check - reaches its caller that way.
@objc(SAStatementReport)
public final class SAStatementReport: NSObject {

    /// The key under which a thread keeps the reports handed back to it.
    private static let handedBackKey = "SAStatementReport.handedBack"

    /// The reports handed back to the current thread, by the connection they are about - held by
    /// the connection itself, weakly, not by its address: a report about a connection that is
    /// gone is not read for another that comes to be where it was.
    private static var handedBackToThisThread: NSMapTable<AnyObject, SAStatementReport> {
        let dictionary = Thread.current.threadDictionary
        if let reports = dictionary[handedBackKey] as? NSMapTable<AnyObject, SAStatementReport> {
            return reports
        }
        let reports = NSMapTable<AnyObject, SAStatementReport>(keyOptions: [.weakMemory, .objectPointerPersonality],
                                                                valueOptions: [.strongMemory, .objectPersonality])
        dictionary[handedBackKey] = reports
        return reports
    }

    /// Hands a report back to the current thread, for it to read as its last statement's on this
    /// connection.
    /// - Parameters:
    ///   - report: The report.
    ///   - connection: The connection the statement ran on.
    @objc(handBack:for:)
    public static func handBack(_ report: SAStatementReport, for connection: AnyObject) {
        let reports = handedBackToThisThread
        reports.setObject(report, forKey: connection)
        // Read straight after the call that handed it back, within the same turn of the run loop;
        // what the main thread reads in a later turn - about a statement another thread ran - is
        // the connection's own report again. In the common modes, so that a turn spent in a modal
        // session or an event-tracking loop ends it too. On the main thread only, whose run loop
        // always turns: queued on a thread that never turns its own - a task thread, a dispatch
        // worker - the block would stay, and keep the report, for every statement the thread
        // runs. Such a thread keeps the report until its next statement on the connection.
        guard Thread.isMainThread else {
            return
        }
        RunLoop.current.perform(inModes: [.common]) { [weak connection] in
            if let connection, reports.object(forKey: connection) === report {
                reports.removeObject(forKey: connection)
            }
        }
    }

    /// Forgets a report handed back to the current thread about this connection, as a new
    /// statement on it begins.
    /// - Parameter connection: The connection.
    @objc(forgetReportHandedBackToThisThreadFor:)
    public static func forgetReportHandedBackToThisThread(for connection: AnyObject) {
        handedBackToThisThread.removeObject(forKey: connection)
    }

    /// The report handed back to the current thread about this connection, if one stands.
    /// - Parameter connection: The connection.
    /// - Returns: The report, or nil when nothing is handed back.
    @objc(reportHandedBackToThisThreadFor:)
    public static func reportHandedBackToThisThread(for connection: AnyObject) -> SAStatementReport? {
        handedBackToThisThread.object(forKey: connection)
    }

    /// The report the current thread reads the last statement from: one handed back to it about a
    /// statement the connection has since moved on from - or nil, for the connection's own fields.
    /// Those fields describe the statement handed back until a later one starts, and carry what
    /// that statement reported after its report was taken: the error or stop of a streaming
    /// download, a failed connection check. A report about no statement that ran is read whatever
    /// the fields say.
    /// - Parameters:
    ///   - connection: The connection.
    ///   - statementNumber: The number of the statement the connection's fields describe now.
    /// - Returns: The report to read, or nil for the connection's own fields.
    @objc(reportThisThreadReadsFor:statementNumber:)
    public static func reportThisThreadReads(for connection: AnyObject, statementNumber: UInt64) -> SAStatementReport? {
        guard let handedBack = reportHandedBackToThisThread(for: connection), handedBack.statementNumber != statementNumber else {
            return nil
        }
        return handedBack
    }

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

    /// The number of the statement the report is about, as the connection counts the statements
    /// that start on it; ``noStatement`` for a report about no statement that ran - a refusal, a
    /// stop before the send. While the connection's own fields are of this number they describe
    /// the same statement, and the thread reads them rather than the report.
    @objc public let statementNumber: UInt64

    /// The statement number of a report about no statement that ran.
    public static let noStatement: UInt64 = .max

    /// Keeps what the connection reports now about the statement of a number.
    /// - Parameters:
    ///   - errorMessage: The error message, or nil.
    ///   - errorID: The error number.
    ///   - sqlState: The SQL state, or nil.
    ///   - affectedRows: The rows affected.
    ///   - insertID: The insert ID carried.
    ///   - wasCancelled: Whether the statement was cancelled.
    ///   - statementNumber: The statement's number on the connection.
    @objc(initWithErrorMessage:errorID:sqlState:affectedRows:insertID:wasCancelled:statementNumber:)
    public init(errorMessage: String?, errorID: UInt, sqlState: String?, affectedRows: UInt64, insertID: UInt64, wasCancelled: Bool,
                statementNumber: UInt64) {
        self.errorMessage = errorMessage
        self.errorID = errorID
        self.sqlState = sqlState
        self.affectedRows = affectedRows
        self.insertID = insertID
        self.wasCancelled = wasCancelled
        self.statementNumber = statementNumber
        super.init()
    }

    /// Keeps what is reported about no statement that ran: a refusal, or a stop before the send.
    /// - Parameters:
    ///   - errorMessage: The error message, or nil.
    ///   - errorID: The error number.
    ///   - sqlState: The SQL state, or nil.
    ///   - affectedRows: The rows affected.
    ///   - insertID: The insert ID carried.
    ///   - wasCancelled: Whether the statement was cancelled.
    @objc(initWithErrorMessage:errorID:sqlState:affectedRows:insertID:wasCancelled:)
    public convenience init(errorMessage: String?, errorID: UInt, sqlState: String?, affectedRows: UInt64, insertID: UInt64, wasCancelled: Bool) {
        self.init(errorMessage: errorMessage, errorID: errorID, sqlState: sqlState, affectedRows: affectedRows, insertID: insertID,
                  wasCancelled: wasCancelled, statementNumber: Self.noStatement)
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
