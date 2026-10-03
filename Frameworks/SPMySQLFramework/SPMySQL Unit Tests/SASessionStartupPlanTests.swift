//
//  SASessionStartupPlanTests.swift
//  SPMySQLFramework
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//
//  More info at <https://github.com/Sequel-Ace/Sequel-Ace>
//

import XCTest
@testable import SPMySQL

/// What a session that has just reported its variables still needs.
final class SASessionStartupPlanTests: XCTestCase {

    /// Quotes the way the server expects, so the statements can be asserted whole.
    private func quote(_ value: String) -> String { "'\(value)'" }

    /// Builds a plan, recording whether the ProxySQL question was asked.
    private func plan(reported: String?,
                      tracking: String?,
                      isProxySQL: Bool = false,
                      proxySQLWasAsked: UnsafeMutablePointer<Bool>? = nil) -> SASessionStartupPlan {
        SASessionStartupPlan.plan(forReportedCharacterSet: reported,
                                  trackingList: tracking,
                                  quote: { self.quote($0) },
                                  serverIsProxySQL: {
                                      proxySQLWasAsked?.pointee = true
                                      return isProxySQL
                                  })
    }

    /// A server at its default needs nothing: it already reports character set changes, and the
    /// character set it is in can be converted for.
    func testAServerAtItsDefaultNeedsNothing() {
        var asked = false
        let result = plan(reported: "utf8mb4",
                          tracking: "time_zone,autocommit,character_set_client,character_set_results,character_set_connection",
                          proxySQLWasAsked: &asked)
        XCTAssertNil(result.trackingStatement)
        XCTAssertEqual(result.characterSetMoves.count, 0)
        XCTAssertEqual(result.characterSet, "utf8mb4")
        XCTAssertFalse(result.movesToAnotherCharacterSet)
        XCTAssertFalse(asked, "the ProxySQL question costs a round trip and must not be asked for nothing")
    }

    /// A server that reports nothing is asked to report the character set.
    func testASessionThatReportsNothingIsAskedTo() {
        let result = plan(reported: "utf8mb4", tracking: "")
        XCTAssertEqual(result.trackingStatement, "SET SESSION session_track_system_variables = 'character_set_client'")
        XCTAssertEqual(result.characterSetMoves.count, 0)
        XCTAssertEqual(result.characterSet, "utf8mb4")
    }

    /// What the server already reports is kept, not replaced.
    func testWhatIsAlreadyReportedIsKept() {
        let result = plan(reported: "utf8mb4", tracking: "time_zone")
        XCTAssertEqual(result.trackingStatement, "SET SESSION session_track_system_variables = 'time_zone,character_set_client'")
    }

    /// Behind ProxySQL the tracking statement is not sent: it does not know the variable, and a
    /// SET it does not track pins the connection to its hostgroup.
    func testBehindProxySQLTheTrackingStatementIsNotSent() {
        var asked = false
        let result = plan(reported: "utf8mb4", tracking: "", isProxySQL: true, proxySQLWasAsked: &asked)
        XCTAssertNil(result.trackingStatement)
        XCTAssertEqual(result.characterSetMoves.count, 0)
        XCTAssertTrue(asked, "the question has to be asked when a statement would otherwise be sent")
        XCTAssertEqual(result.characterSet, "utf8mb4")
    }

    /// A character set nothing can carry moves the session to the fallback.
    func testACharacterSetThatCannotBeCarriedMovesTheSession() {
        let result = plan(reported: "swe7", tracking: "character_set_client")
        XCTAssertNil(result.trackingStatement)
        XCTAssertEqual(result.characterSetMoves.map(\.statement), ["SET NAMES 'utf8mb4'", "SET NAMES 'utf8'"])
        XCTAssertEqual(result.characterSet, "utf8mb4")
        XCTAssertTrue(result.movesToAnotherCharacterSet)
    }

    /// A server too old to take the fallback keeps what it reported.
    func testAFailedMoveKeepsWhatWasReported() {
        let result = plan(reported: "swe7", tracking: "character_set_client")
        XCTAssertEqual(result.characterSetWithoutStatements, "swe7")
    }

    /// Both needs at once, in the order they have to run: the tracking first, so the move itself
    /// is reported.
    func testBothNeedsComeInOrder() {
        let result = plan(reported: "hp8", tracking: "")
        XCTAssertEqual(result.trackingStatement, "SET SESSION session_track_system_variables = 'character_set_client'")
        XCTAssertEqual(result.characterSetMoves.map(\.statement), ["SET NAMES 'utf8mb4'", "SET NAMES 'utf8'"])
        XCTAssertEqual(result.characterSet, "utf8mb4")
    }

    /// A tracking statement that fails does not decide the character set: the session is in the
    /// one its own statement left it in. On a server too old to have the tracking variable, the
    /// move to the fallback still counts.
    func testTheTwoOutcomesAreIndependent() {
        let result = plan(reported: "swe7", tracking: "")
        XCTAssertNotNil(result.trackingStatement, "an old server is still asked, and may refuse")
        XCTAssertEqual(result.characterSetMoves.map(\.statement), ["SET NAMES 'utf8mb4'", "SET NAMES 'utf8'"])
        XCTAssertEqual(result.characterSet, "utf8mb4", "which is where a successful move leaves it")
        XCTAssertEqual(result.characterSetWithoutStatements, "swe7", "and where a failed one leaves it")
    }

    /// The candidates come best first, and the second exists for servers too old for the first:
    /// `utf8mb4` arrived in MySQL 5.5, `utf8` in 4.1.
    func testTheFallbackOffersAnOlderCharacterSetToo() {
        let result = plan(reported: "keybcs2", tracking: "character_set_client")
        XCTAssertEqual(result.characterSetMoves.map(\.characterSet), ["utf8mb4", "utf8"])
        XCTAssertEqual(result.characterSet, "utf8mb4", "the first is what a current server lands on")
        XCTAssertEqual(result.characterSetWithoutStatements, "keybcs2",
                       "and a server that refuses both keeps what it reported")
    }

    /// The name comes back in the spelling the encoding table is keyed by, which matches
    /// case-sensitively.
    func testTheCharacterSetComesBackNormalised() {
        let result = plan(reported: "LATIN5", tracking: "character_set_client")
        XCTAssertEqual(result.characterSet, "latin5")
        XCTAssertFalse(result.movesToAnotherCharacterSet)
    }

    /// A session that reports no character set at all is moved to the fallback rather than left
    /// on a name nothing can convert for.
    func testNoReportedCharacterSetMovesToTheFallback() {
        let result = plan(reported: nil, tracking: "character_set_client")
        XCTAssertNil(result.trackingStatement)
        XCTAssertEqual(result.characterSetMoves.map(\.statement), ["SET NAMES 'utf8mb4'", "SET NAMES 'utf8'"])
        XCTAssertTrue(result.movesToAnotherCharacterSet)
    }
}
