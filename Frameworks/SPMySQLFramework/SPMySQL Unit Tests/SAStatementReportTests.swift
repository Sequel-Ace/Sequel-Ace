//
//  SAStatementReportTests.swift
//  SPMySQL Unit Tests
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import XCTest
@testable import SPMySQL

/// What a thread reads a statement's report from, and how long a report handed back to it stands.
final class SAStatementReportTests: XCTestCase {

    private func report(errorID: UInt = 0, statementNumber: UInt64 = 0) -> SAStatementReport {
        SAStatementReport(errorMessage: errorID == 0 ? nil : "error \(errorID)", errorID: errorID, sqlState: nil,
                          affectedRows: 0, insertID: 0, wasCancelled: false)
    }

    /// Calls one of the connection's private writers that takes a string, by way of the runtime.
    private func write(_ selector: String, _ message: String?, on connection: SPMySQLConnection) {
        let selector = NSSelectorFromString(selector)
        guard let implementation = class_getMethodImplementation(SPMySQLConnection.self, selector) else {
            return XCTFail("no \(selector)")
        }
        typealias Writer = @convention(c) (AnyObject, Selector, NSString?) -> Void
        unsafeBitCast(implementation, to: Writer.self)(connection, selector, message as NSString?)
    }

    /// Calls one of the connection's private writers that takes a number, by way of the runtime.
    private func write(_ selector: String, _ number: UInt, on connection: SPMySQLConnection) {
        let selector = NSSelectorFromString(selector)
        guard let implementation = class_getMethodImplementation(SPMySQLConnection.self, selector) else {
            return XCTFail("no \(selector)")
        }
        typealias Writer = @convention(c) (AnyObject, Selector, UInt) -> Void
        unsafeBitCast(implementation, to: Writer.self)(connection, selector, number)
    }

    /// What the connection writes while a statement still holds the session - a streaming
    /// download's error, a stop - goes into that statement's report, which its caller reads; once
    /// the session is released nothing more does.
    func testWhatTheConnectionWritesWhileTheStatementHoldsTheSessionReachesItsReport() {
        let connection = SPMySQLConnection()
        let report = self.report()
        connection.setValue(report, forKey: "currentStatementReport")
        SAStatementReport.handBack(report, for: connection)
        defer { SAStatementReport.forgetReportHandedBackToThisThread(for: connection) }
        XCTAssertFalse(connection.queryErrored())
        XCTAssertFalse(connection.lastQueryWasCancelled)

        // The download is stopped: written on the connection after the report was taken, from the
        // stopping thread and the downloading one.
        write("_updateLastErrorMessage:", "Query execution was interrupted", on: connection)
        write("_updateLastErrorID:", UInt(1317), on: connection)
        connection.perform(NSSelectorFromString("markRunningQueryCancelled"))
        XCTAssertTrue(connection.queryErrored())
        XCTAssertEqual(connection.lastErrorMessage(), "Query execution was interrupted")
        XCTAssertEqual(connection.lastErrorID(), 1317)
        XCTAssertTrue(connection.lastQueryWasCancelled)

        // The session is released: the report is the statement's as it ended, whatever is written next.
        connection.perform(NSSelectorFromString("_tryLockConnection"))
        connection.perform(NSSelectorFromString("_unlockConnection"))
        XCTAssertNil(connection.value(forKey: "currentStatementReport"))
        write("_updateLastErrorMessage:", "a later statement's error", on: connection)
        write("_updateLastErrorID:", UInt(1146), on: connection)
        XCTAssertEqual(connection.lastErrorMessage(), "Query execution was interrupted")
        XCTAssertEqual(connection.lastErrorID(), 1317)
    }

    /// An explicit stop of the connection's work - a KILL issued over another connection, marked
    /// here - reaches the report of a statement that still holds the session, and every caller
    /// until the next statement starts.
    func testAnExplicitStopReachesTheHeldReportAndEveryCallerUntilTheNextStatement() {
        let connection = SPMySQLConnection()
        let held = report()
        connection.setValue(held, forKey: "currentStatementReport")
        let earlier = report()
        SAStatementReport.handBack(earlier, for: connection)
        defer { SAStatementReport.forgetReportHandedBackToThisThread(for: connection) }
        XCTAssertFalse(connection.lastQueryWasCancelled)

        connection.lastQueryWasCancelled = true
        XCTAssertTrue(held.wasCancelled, "the statement holding the session is stopped")
        XCTAssertFalse(earlier.wasCancelled, "an earlier statement's report is not rewritten")
        XCTAssertTrue(connection.lastQueryWasCancelled, "but its caller reads the stop until the next statement")
    }

    /// The connection as the statement call sees it, for a statement that ran.
    private final class SAScriptedCallHost: NSObject, SAStatementCallHost {
        let sessionAccess = SAConnectionSessionAccess()
        var insertIDCarried: UInt64 = 0
        var explicitStopsForgotten = 0
        /// What the connection's fields say.
        var fields = SAStatementReport(errorMessage: nil, errorID: 0, sqlState: nil, affectedRows: 0, insertID: 0, wasCancelled: false)
        var reportFromTheConnectionsFields: SAStatementReport { fields }
        func forgetAnExplicitStop() { explicitStopsForgotten += 1 }
        func runWorkKeepingInterfaceAlive(_ work: @escaping () -> Any?) -> Any? { work() }
        func runConnectionWorkKeepingInterfaceAlive(_ work: @escaping () -> Bool) -> Bool { work() }
    }

    /// A failed check hands the connection's fields to the calling thread - past a report handed
    /// back earlier, a stopped statement's included; not past the stop of this very check, which
    /// arrives during it. A check that passes hands nothing back.
    func testAFailedCheckHandsItsErrorBackUnlessThisCheckWasStopped() {
        let host = SAScriptedCallHost()
        defer { SAStatementReport.forgetReportHandedBackToThisThread(for: host) }
        host.fields = SAStatementReport(errorMessage: "The check failed", errorID: 2006, sqlState: "HY000",
                                        affectedRows: 0, insertID: 0, wasCancelled: false)
        let earlierStop = SAStatementReport(errorMessage: "Query cancelled.", errorID: 1317, sqlState: "70100",
                                            affectedRows: 0, insertID: 0, wasCancelled: true)

        SAStatementReport.handBack(earlierStop, for: host)
        XCTAssertTrue(SAStatementCall.runCheck({ true }, handedOver: true, on: host))
        XCTAssertTrue(SAStatementReport.reportHandedBackToThisThread(for: host) === earlierStop, "a check that passes hands nothing back")

        XCTAssertFalse(SAStatementCall.runCheck({ false }, handedOver: true, on: host))
        XCTAssertEqual(SAStatementReport.reportHandedBackToThisThread(for: host)?.errorID, 2006, "the check's error, past the earlier stop")

        let stopOfThisCheck = SAStatementReport(errorMessage: "Query cancelled.", errorID: 1317, sqlState: "70100",
                                                affectedRows: 0, insertID: 0, wasCancelled: true)
        XCTAssertFalse(SAStatementCall.runCheck({
            SAStatementReport.handBack(stopOfThisCheck, for: host)
            return false
        }, handedOver: false, on: host))
        XCTAssertTrue(SAStatementReport.reportHandedBackToThisThread(for: host) === stopOfThisCheck, "the stop of this check stands")
    }

    /// A statement that ran and failed keeps its own report, whatever refusal marker may stand on
    /// the thread: the refusal report is for a statement that never ran.
    func testAStatementThatRanAndFailedKeepsItsReportPastARefusalMarker() {
        let host = SAScriptedCallHost()
        defer { SAStatementReport.forgetReportHandedBackToThisThread(for: host) }
        host.sessionAccess.noteThisThreadsCallWasRefused(whileWaitingForEarlierWork: true)
        let failure = SAStatementReport(errorMessage: "Table 'x' doesn't exist", errorID: 1146, sqlState: "42S02",
                                        affectedRows: 0, insertID: 0, wasCancelled: false)

        let result = SAStatementCall.run({ SAStatementRun(result: nil, report: failure) }, on: host)

        XCTAssertNil(result)
        XCTAssertTrue(SAStatementReport.reportHandedBackToThisThread(for: host) === failure, "the statement's own failure")
        XCTAssertEqual(host.explicitStopsForgotten, 1)
        XCTAssertFalse(host.sessionAccess.takeTheRefusalOfThisThreadsLastCall(), "the marker was taken all the same")
    }

    /// A report handed back is read whatever the connection's fields say - a refusal, a stop
    /// before the send, a statement another thread has since run.
    func testAHandedBackReportIsReadWhateverTheConnectionsFieldsSay() {
        let connection = SPMySQLConnection()
        SAStatementReport.handBack(SAStatementReport(errorMessage: "refused", errorID: 2013, sqlState: "HY000",
                                                     affectedRows: 0, insertID: 0, wasCancelled: false), for: connection)
        defer { SAStatementReport.forgetReportHandedBackToThisThread(for: connection) }
        write("_updateLastErrorMessage:", nil, on: connection)
        write("_updateLastErrorID:", UInt(0), on: connection)
        XCTAssertTrue(connection.queryErrored())
        XCTAssertEqual(connection.lastErrorMessage(), "refused")
        XCTAssertEqual(connection.lastErrorID(), 2013)
    }

    /// On the main thread a report handed back stands until the next turn of the run loop.
    func testAReportHandedBackOnTheMainThreadIsGoneAfterTheNextTurnOfTheRunLoop() {
        let connection = NSObject()
        SAStatementReport.handBack(report(statementNumber: 1), for: connection)
        XCTAssertNotNil(SAStatementReport.reportHandedBackToThisThread(for: connection))
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        XCTAssertNil(SAStatementReport.reportHandedBackToThisThread(for: connection))
    }

    /// On a thread that never turns its run loop - a task thread, a dispatch worker - a report
    /// handed back is let go of by the next one, not kept by a block waiting for a turn that never
    /// comes.
    func testAReportHandedBackOnAThreadThatDoesNotTurnItsRunLoopIsLetGoOfByTheNext() {
        let connection = NSObject()
        let done = DispatchSemaphore(value: 0)
        var firstWasLetGoOf = false
        Thread.detachNewThread {
            weak var first: SAStatementReport?
            autoreleasepool {
                let report = self.report(statementNumber: 1)
                first = report
                SAStatementReport.handBack(report, for: connection)
                SAStatementReport.handBack(self.report(statementNumber: 2), for: connection)
            }
            firstWasLetGoOf = first == nil
            SAStatementReport.forgetReportHandedBackToThisThread(for: connection)
            done.signal()
        }
        XCTAssertEqual(done.wait(timeout: .now() + 5), .success)
        XCTAssertTrue(firstWasLetGoOf)
    }

    /// A report is kept by the connection it is about, not by its address: once the connection is
    /// gone, a connection that comes to be where it was does not read it.
    func testAReportAboutAConnectionThatIsGoneIsNotReadForOneAtItsAddress() throws {
        var address: ObjectIdentifier?
        autoreleasepool {
            let gone = NSObject()
            address = ObjectIdentifier(gone)
            SAStatementReport.handBack(report(errorID: 1146, statementNumber: 1), for: gone)
        }
        // The allocator hands a freed slot out again soon; a few tries find it.
        for _ in 0..<1000 {
            let newcomer = NSObject()
            if ObjectIdentifier(newcomer) == address {
                XCTAssertNil(SAStatementReport.reportHandedBackToThisThread(for: newcomer))
                return
            }
        }
        throw XCTSkip("no object came to be at the gone connection's address")
    }
}
