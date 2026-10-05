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
