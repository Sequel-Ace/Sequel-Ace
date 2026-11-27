//
//  SAStatementReportHold.swift
//  SPMySQLFramework
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import Foundation

/// The report of the statement that still holds the session - a streaming statement, whose rows
/// are read after its report was taken - kept with the connection from before its result exists,
/// which can start downloading at once, until the session is released: what the connection
/// writes meanwhile - the download's error, a stop - goes into that report, under its lock, from
/// whichever thread writes it, and its caller holds the same object.
@objc(SAStatementReportHold)
public final class SAStatementReportHold: NSObject {

    private let lock = NSLock()
    private var held: SAStatementReport?

    /// The report of the statement holding the session, or nil when none does.
    @objc public var current: SAStatementReport? {
        lock.lock()
        defer { lock.unlock() }
        return held
    }

    /// Attaches a fresh report to the statement about to keep the session for its rows - before
    /// its result exists and can start downloading, so that nothing the download writes is missed,
    /// and so that no report is attached to a session the download has let go of already.
    /// - Parameter insertID: The insert ID the connection carries.
    /// - Returns: The attached report.
    @objc(attachWithInsertID:)
    @discardableResult
    public func attach(insertID: UInt64) -> SAStatementReport {
        let report = SAStatementReport(errorMessage: nil, errorID: 0, sqlState: nil, affectedRows: 0,
                                       insertID: insertID, wasCancelled: false)
        lock.lock()
        defer { lock.unlock() }
        held = report
        return report
    }

    /// Lets the attached report go: the session was released, and what is written from here on
    /// is not the statement's.
    @objc public func sessionWasReleased() {
        lock.lock()
        defer { lock.unlock() }
        held = nil
    }

    /// The report of the statement just run: the attached one, with the statement's own final
    /// status - its stop, its rows - taken from the connection's fields, while it is still
    /// attached; a download that has ended already let it go, and the fields - which that
    /// download wrote last - are the report. The fields are read under the hold's lock, so that a
    /// download cannot write its error and let the session go between the reading and the choice:
    /// a release waits for the reading to end, and a reading after the release sees what the
    /// download wrote.
    /// - Parameter fields: Reads what the connection's fields say now. Called once, under the lock,
    ///   so it must not come back to the hold.
    /// - Returns: The report the statement's caller is handed.
    @objc(reportOfStatementSettledWith:)
    public func reportOfStatement(settledWith fields: () -> SAStatementReport) -> SAStatementReport {
        lock.lock()
        defer { lock.unlock() }
        let fields = fields()
        guard let held else {
            return fields
        }
        if fields.wasCancelled {
            held.recordCancellation()
        }
        held.record(affectedRows: fields.affectedRows, insertID: fields.insertID)
        return held
    }
}
