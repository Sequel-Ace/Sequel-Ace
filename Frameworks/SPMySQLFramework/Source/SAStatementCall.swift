//
//  SAStatementCall.swift
//  SPMySQLFramework
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import Foundation

/// The connection as a statement call sees it: what runs the statement with the interface alive,
/// the lease that records a call turned away, and the insert ID a report carries.
@objc(SAStatementCallHost)
public protocol SAStatementCallHost: AnyObject {

    /// The lease, which records a call it or the hand-off turned away, and why.
    @objc var sessionAccess: SAConnectionSessionAccess { get }

    /// The insert ID the connection carries, as the last statement left it.
    @objc var insertIDCarried: UInt64 { get }

    /// Ends the reach of an explicit stop recorded on the connection: a statement is being asked
    /// for, and the stop was of the work before it.
    @objc func forgetAnExplicitStop()

    /// Runs the work on the connection's worker when asked for on the main thread, waiting with
    /// the interface alive, and where it was asked for otherwise.
    /// - Parameter work: The statement, run under the lease.
    /// - Returns: What the work returned, or nil when it was refused or given up on.
    @objc func runWorkKeepingInterfaceAlive(_ work: @escaping () -> Any?) -> Any?
}

/// A statement call as `queryString:` makes it: the statement runs through the hand-off, takes
/// its report with its result while the session is still held, and the report is handed to the
/// calling thread - a statement refused the session, or given up on, is reported to that thread
/// the same way, with the reason.
@objc(SAStatementCall)
public final class SAStatementCall: NSObject {

    /// Runs a statement and hands its report to the calling thread.
    ///
    /// A statement that was refused the session never reached the server. Saying so is what keeps
    /// it apart from one that ran and changed nothing: callers read the row count and the error
    /// together, and both would still describe the statement before this one - which is how an
    /// edit that was never written comes to be treated as saved. The refusal is this caller's to
    /// read, handed to its thread like a statement's report, with its reason: the question out to
    /// the main thread, or the earlier work this thread is waiting for.
    /// - Parameters:
    ///   - work: The statement, run under the lease; returns its result with its report, taken
    ///     while the session is still held.
    ///   - host: The connection.
    /// - Returns: The statement's result, or nil when it failed, was refused or was given up on.
    @objc(run:on:)
    public static func run(_ work: @escaping () -> SAStatementRun?, on host: SAStatementCallHost) -> Any? {
        SAStatementReport.forgetReportHandedBackToThisThread(for: host)
        // An explicit stop reaches every caller until the next statement is asked for - this one,
        // refused or not: a refused statement is not one the user stopped.
        host.forgetAnExplicitStop()
        let run = host.runWorkKeepingInterfaceAlive { work() } as? SAStatementRun
        var result: Any?
        if let run {
            SAStatementReport.handBack(run.report, for: host)
            result = run.result
        }

        // No run means the statement was refused or given up on, and the connection records that
        // itself; given up on, its caller was already told. A refusal is reported here.
        let lease = host.sessionAccess
        let refusedWhileWaiting = lease.thisThreadsLastCallWasRefusedWhileWaitingForEarlierWork
        let refused = lease.takeTheRefusalOfThisThreadsLastCall()
        if result == nil, refused {
            let reason = refusedWhileWaiting
                ? NSLocalizedString("The connection is still waiting for an earlier statement from this window. Let it finish, or stop waiting for it, then try again.",
                                    comment: "Error shown for a statement asked for while the window is waiting for an earlier statement on the same connection")
                : NSLocalizedString("The connection cannot be used while you are being asked what to do about it. Answer that question, then try again.",
                                    comment: "Error shown for a statement refused while the lost-connection question is open")
            SAStatementReport.handBack(SAStatementReport(errorMessage: reason, errorID: 2013, sqlState: "HY000", affectedRows: 0,
                                                         insertID: host.insertIDCarried, wasCancelled: false), for: host)
        }
        return result
    }

    /// Records work the user stopped waiting for as cancelled, for the thread that asked for it.
    ///
    /// Handed to that thread rather than written over the connection's report, which a statement
    /// another thread is running may be writing. Nothing was affected, as far as anybody can say:
    /// callers work out success from the count - the content view's row deletion compares it with
    /// how many rows it meant to delete and, on a match, takes them off the screen without asking
    /// the error - and a stopped DELETE must not look like one that worked.
    /// - Parameter host: The connection.
    @objc(recordWorkAsCancelledOn:)
    public static func recordWorkAsCancelled(on host: SAStatementCallHost) {
        SAStatementReport.handBack(SAStatementReport(errorMessage: NSLocalizedString("Query cancelled.", comment: "Query cancelled error"),
                                                     errorID: 1317, sqlState: "70100", affectedRows: 0,
                                                     insertID: host.insertIDCarried, wasCancelled: true), for: host)
    }
}
