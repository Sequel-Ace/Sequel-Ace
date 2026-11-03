//
//  SAStatementReport.swift
//  SPMySQLFramework
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
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
/// after the call that handed it back. While it stands the thread reads it and nothing else; the
/// connection's own fields are read by a thread that has nothing handed back to it.
///
/// A statement that still holds the session when its report is taken - a streaming statement,
/// whose rows are read after - keeps its report with the connection as well, and what the
/// connection writes while the session is held - the download's error, a stop - goes into that
/// report, under its lock, from whichever thread writes it. The connection lets the report go as
/// the session is released; nothing written after that is the statement's.
@objc(SAStatementReport)
public final class SAStatementReport: NSObject {

    // MARK: - The reports handed back to threads

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
    /// - Returns: The report, or nil when the thread reads the connection's own fields.
    @objc(reportHandedBackToThisThreadFor:)
    public static func reportHandedBackToThisThread(for connection: AnyObject) -> SAStatementReport? {
        handedBackToThisThread.object(forKey: connection)
    }

    // MARK: - What the statement reported

    /// Guards what the connection may still write while the statement holds the session.
    private let lock = NSLock()
    private var storedErrorMessage: String?
    private var storedErrorID: UInt
    private var storedSqlState: String?
    private var storedWasCancelled: Bool

    /// The error message, or nil when the statement did not fail.
    @objc public var errorMessage: String? {
        lock.lock()
        defer { lock.unlock() }
        return storedErrorMessage
    }

    /// The error number; zero when the statement did not fail.
    @objc public var errorID: UInt {
        lock.lock()
        defer { lock.unlock() }
        return storedErrorID
    }

    /// The SQL state, or nil when the statement did not fail.
    @objc public var sqlState: String? {
        lock.lock()
        defer { lock.unlock() }
        return storedSqlState
    }

    /// The rows the statement changed, deleted, inserted or selected.
    @objc public let affectedRows: UInt64

    /// The insert ID the connection carries, which an insert sets and other statements leave.
    @objc public let insertID: UInt64

    /// Whether the statement was cancelled.
    @objc public var wasCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return storedWasCancelled
    }

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
        storedErrorMessage = errorMessage
        storedErrorID = errorID
        storedSqlState = sqlState
        self.affectedRows = affectedRows
        self.insertID = insertID
        storedWasCancelled = wasCancelled
        super.init()
    }

    // MARK: - What the connection writes while the statement holds the session

    /// Records the error message the connection wrote while the statement held the session.
    /// - Parameter message: The message, or nil for no error.
    @objc(recordErrorMessage:)
    public func recordErrorMessage(_ message: String?) {
        lock.lock()
        defer { lock.unlock() }
        storedErrorMessage = message
    }

    /// Records the error number the connection wrote while the statement held the session.
    /// - Parameter errorID: The number; zero for no error.
    @objc(recordErrorID:)
    public func recordErrorID(_ errorID: UInt) {
        lock.lock()
        defer { lock.unlock() }
        storedErrorID = errorID
    }

    /// Records the SQL state the connection wrote while the statement held the session.
    /// - Parameter sqlState: The state, or nil.
    @objc(recordSqlState:)
    public func recordSqlState(_ sqlState: String?) {
        lock.lock()
        defer { lock.unlock() }
        storedSqlState = sqlState
    }

    /// Records that the statement was cancelled while it held the session.
    @objc public func recordCancellation() {
        lock.lock()
        defer { lock.unlock() }
        storedWasCancelled = true
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
