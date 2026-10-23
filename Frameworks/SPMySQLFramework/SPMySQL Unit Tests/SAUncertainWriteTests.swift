//
//  SAUncertainWriteTests.swift
//  SPMySQLFramework
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//
//  More info at <https://github.com/Sequel-Ace/Sequel-Ace>
//

import XCTest
@testable import SPMySQL

/// When what became of a statement is unknown rather than known.
final class SAUncertainWriteTests: XCTestCase {

    private func outcomeIsUnknown(reached: Bool = true, changesData: Bool = true,
                                  connectionLoss: Bool = true, rollsBack: Bool = false,
                                  mayCommit: Bool = false) -> Bool {
        SAUncertainWrite.outcomeIsUnknown(statementReachedTheServer: reached,
                                          changesData: changesData,
                                          errorIsConnectionLoss: connectionLoss,
                                          sessionRollsItBack: rollsBack,
                                          statementMayCommit: mayCommit)
    }

    /// A write sent under autocommit whose reply never came: the one case nothing can settle.
    func testAWriteSentUnderAutocommitThatLostItsConnection() {
        XCTAssertTrue(outcomeIsUnknown())
    }

    /// A statement that was never sent did not happen.
    func testAStatementThatNeverReachedTheServer() {
        XCTAssertFalse(outcomeIsUnknown(reached: false))
    }

    /// A read costs nothing to send twice, which is what retrying is for.
    func testAReadIsNotUncertain() {
        XCTAssertFalse(outcomeIsUnknown(changesData: false))
    }

    /// A server that answered said what happened, whatever it said.
    func testAnErrorFromTheServerIsAnAnswer() {
        XCTAssertFalse(outcomeIsUnknown(connectionLoss: false))
    }

    /// Work the server rolls back with the session has a known outcome: it did not happen.
    func testWorkTheSessionTakesWithItIsNotUncertain() {
        XCTAssertFalse(outcomeIsUnknown(rollsBack: true))
    }

    /// Every reason on its own is enough to make the outcome known.
    func testOneKnownReasonIsEnough() {
        XCTAssertFalse(outcomeIsUnknown(reached: false, changesData: false,
                                        connectionLoss: false, rollsBack: true))
    }

    /// A statement that can commit is unknown whenever its reply is lost, whatever the session
    /// last said about its transaction.
    ///
    /// The flags describe the statement before this one: a COMMIT that may just have committed
    /// would still be sitting behind an "open transaction" of its own making.
    func testACommitIsNotSettledByTheFlagsItLeavesBehind() {
        XCTAssertTrue(outcomeIsUnknown(rollsBack: true, mayCommit: true))
        XCTAssertTrue(outcomeIsUnknown(changesData: false, rollsBack: true, mayCommit: true))
    }

    /// But it is still only in question once it has been sent and the reply is what went missing.
    func testACommitThatWasNeverSentOrWasAnsweredIsSettled() {
        XCTAssertFalse(outcomeIsUnknown(reached: false, mayCommit: true))
        XCTAssertFalse(outcomeIsUnknown(connectionLoss: false, mayCommit: true))
    }
}


/// Replaces only the three primitives that read the handle, so that the end of a result read can be
/// reported - with the error of a read cut off by a connection loss, or of a normal end - on a
/// connection that has no handle.
private final class SACutOffReadConnection: SPMySQLConnection {
    /// What the handle would report: the error number of the read that just ended.
    var errorIDToReport: UInt = 0
    /// What the handle would report: the message of that error.
    var errorMessageToReport = ""

    @objc(_updateLastErrorID:) func reportErrorID(_ theErrorID: UInt) {
        setValue(theErrorID == UInt(bitPattern: NSNotFound) ? errorIDToReport : theErrorID, forKey: "queryErrorID")
    }

    @objc(_updateLastErrorMessage:) func reportErrorMessage(_ theErrorMessage: String?) {
        setValue(theErrorMessage ?? errorMessageToReport, forKey: "queryErrorMessage")
    }

    @objc(_updateLastSqlstate:) func reportSqlstate(_ theSqlstate: String?) {
        setValue(theSqlstate ?? "", forKey: "querySqlstate")
    }
}

/// A result read that a connection loss cut off, reported where the streaming results report the
/// end of a read: a statement that changes data is then as unsettled as one whose reply never came.
final class SACutOffResultReadTests: XCTestCase {
    private let lostConnection: UInt = 2013
    private let note = "may or may not have been carried out"

    private func connection(outcomeUnknownIfCutOff: Bool, errorID: UInt) -> SACutOffReadConnection {
        let connection = SACutOffReadConnection()
        connection.useKeepAlive = false
        connection.setValue(SPMySQLConnected.rawValue, forKey: "state")
        connection.setValue(outcomeUnknownIfCutOff, forKey: "runningResultOutcomeIsUnknownIfCutOff")
        connection.errorIDToReport = errorID
        connection.errorMessageToReport = errorID == 0 ? "" : "Lost connection to MySQL server during query"
        return connection
    }

    private func endTheRead(of connection: SACutOffReadConnection) -> (message: String, state: Int, flag: Bool) {
        _ = connection.perform(NSSelectorFromString("_updateLastErrorInfos"))
        return ((connection.value(forKey: "queryErrorMessage") as? String) ?? "",
                (connection.value(forKey: "state") as? Int) ?? -1,
                (connection.value(forKey: "runningResultOutcomeIsUnknownIfCutOff") as? Bool) ?? true)
    }

    /// The read of a write's result, cut off by the connection going: the error says the outcome
    /// is unknown - after what the handle said - the session counts as lost, and the mark is used up.
    func testACutOffReadOfAWritesResultSaysTheOutcomeIsUnknown() {
        let ended = endTheRead(of: connection(outcomeUnknownIfCutOff: true, errorID: lostConnection))
        XCTAssertTrue(ended.message.hasPrefix("Lost connection"), ended.message)
        XCTAssertTrue(ended.message.contains(note), ended.message)
        XCTAssertEqual(ended.state, Int(SPMySQLConnectionLostInBackground.rawValue))
        XCTAssertFalse(ended.flag, "the read is over")
    }

    /// A read's result cut off, a write's result read to its end, and a write the server refused
    /// while its result was read: a plain error or none, and the session stays.
    func testOnlyTheCutOffReadOfAWritesResultGetsTheNote() {
        let read = endTheRead(of: connection(outcomeUnknownIfCutOff: false, errorID: lostConnection))
        XCTAssertFalse(read.message.contains(note), read.message)
        XCTAssertEqual(read.state, Int(SPMySQLConnected.rawValue))

        let finished = endTheRead(of: connection(outcomeUnknownIfCutOff: true, errorID: 0))
        XCTAssertEqual(finished.message, "")
        XCTAssertEqual(finished.state, Int(SPMySQLConnected.rawValue))
        XCTAssertFalse(finished.flag, "used up by a read that ended normally too")

        let refused = endTheRead(of: connection(outcomeUnknownIfCutOff: true, errorID: 1064))
        XCTAssertFalse(refused.message.contains(note), refused.message)
        XCTAssertEqual(refused.state, Int(SPMySQLConnected.rawValue))
    }
}
