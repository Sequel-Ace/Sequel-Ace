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

    private func report(errorID: UInt = 0, statementNumber: UInt64) -> SAStatementReport {
        SAStatementReport(errorMessage: errorID == 0 ? nil : "error \(errorID)", errorID: errorID, sqlState: nil,
                          affectedRows: 0, insertID: 0, wasCancelled: false, statementNumber: statementNumber)
    }

    /// The connection's own fields are read for the statement the hand-back is about, as long as
    /// no later statement has started: what the statement reports after its report was taken - a
    /// streaming download's error or stop, a failed connection check - reaches its caller.
    func testTheConnectionsOwnFieldsAreReadWhileTheyDescribeTheStatementHandedBack() {
        let connection = SPMySQLConnection()
        connection.setValue(7, forKey: "statementNumber")
        SAStatementReport.handBack(report(statementNumber: 7), for: connection)
        defer { SAStatementReport.forgetReportHandedBackToThisThread(for: connection) }
        XCTAssertFalse(connection.queryErrored())
        XCTAssertFalse(connection.lastQueryWasCancelled)

        // The download is stopped, or fails, or the check does: written on the connection, after
        // the statement's report was taken.
        connection.setValue("Query execution was interrupted", forKey: "queryErrorMessage")
        connection.setValue(1317, forKey: "queryErrorID")
        connection.perform(NSSelectorFromString("markRunningQueryCancelled"))
        XCTAssertTrue(connection.queryErrored())
        XCTAssertEqual(connection.lastErrorID(), 1317)
        XCTAssertTrue(connection.lastQueryWasCancelled)

        // Another statement starts on the connection: the fields are its, the hand-back the caller's.
        connection.setValue(8, forKey: "statementNumber")
        XCTAssertFalse(connection.queryErrored())
        XCTAssertEqual(connection.lastErrorID(), 0)
        XCTAssertFalse(connection.lastQueryWasCancelled)
    }

    /// A report about no statement that ran - a refusal, a stop before the send - is read whatever
    /// the connection's fields say.
    func testAReportAboutNoStatementIsAlwaysRead() {
        let connection = SPMySQLConnection()
        connection.setValue(3, forKey: "statementNumber")
        SAStatementReport.handBack(SAStatementReport(errorMessage: "refused", errorID: 2013, sqlState: "HY000",
                                                     affectedRows: 0, insertID: 0, wasCancelled: false), for: connection)
        defer { SAStatementReport.forgetReportHandedBackToThisThread(for: connection) }
        XCTAssertEqual(SAStatementReport.reportHandedBackToThisThread(for: connection)?.statementNumber, SAStatementReport.noStatement)
        XCTAssertTrue(connection.queryErrored())
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
