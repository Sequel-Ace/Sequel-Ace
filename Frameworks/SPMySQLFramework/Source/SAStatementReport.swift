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
/// was about; it stands until that thread's next statement on the connection, or the next turn
/// of its run loop, whichever comes first - the caller reads it straight after the call that
/// handed it back - and nothing of it is ever written over the report of a statement running.
/// A thread reads the connection's own report - the last statement's, whichever thread ran it -
/// only when nothing is handed back to it: a thread that ran a statement of its own on the
/// connection earlier in the same turn reads that statement's report, not another thread's.
@objc(SAStatementReport)
public final class SAStatementReport: NSObject {

    /// The reports handed back to one thread, by the connection they are about.
    private final class SAHandedBackReports {
        var byConnection: [ObjectIdentifier: SAStatementReport] = [:]
    }

    /// The key under which a thread keeps the reports handed back to it.
    private static let handedBackKey = "SAStatementReport.handedBack"

    /// The reports handed back to the current thread.
    private static var handedBackToThisThread: SAHandedBackReports {
        let dictionary = Thread.current.threadDictionary
        if let reports = dictionary[handedBackKey] as? SAHandedBackReports {
            return reports
        }
        let reports = SAHandedBackReports()
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
        let key = ObjectIdentifier(connection)
        reports.byConnection[key] = report
        // Read straight after the call that handed it back, within the same turn of the run loop;
        // what this thread reads in a later turn - about a statement another thread ran - is the
        // connection's own report again. In the common modes, so that a turn spent in a modal
        // session or an event-tracking loop ends it too.
        RunLoop.current.perform(inModes: [.common]) {
            if reports.byConnection[key] === report {
                reports.byConnection[key] = nil
            }
        }
    }

    /// Forgets a report handed back to the current thread about this connection, as a new
    /// statement on it begins.
    /// - Parameter connection: The connection.
    @objc(forgetReportHandedBackToThisThreadFor:)
    public static func forgetReportHandedBackToThisThread(for connection: AnyObject) {
        handedBackToThisThread.byConnection[ObjectIdentifier(connection)] = nil
    }

    /// The report handed back to the current thread about this connection, if one stands.
    /// - Parameter connection: The connection.
    /// - Returns: The report, or nil when the thread reads the connection's own.
    @objc(reportHandedBackToThisThreadFor:)
    public static func reportHandedBackToThisThread(for connection: AnyObject) -> SAStatementReport? {
        handedBackToThisThread.byConnection[ObjectIdentifier(connection)]
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
