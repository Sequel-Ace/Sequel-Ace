//
//  SASessionReplacementTests.swift
//  SPMySQLFramework
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//
//  More info at <https://github.com/Sequel-Ace/Sequel-Ace>
//

import XCTest
@testable import SPMySQL

/// A connection as the replacement sees it: scripted readings, and a record of every step taken.
private final class SAScriptedReplacementHost: NSObject, SASessionReplacementHost {
    var sessionReplacementMark = SASessionReplacementMark.regardless
    var hasProxy = false
    var nativeHandleIsReadingOrWriting = false
    var nativeHandleHasTransport = true
    var nativeHandleHasBuffer = true
    private(set) var steps: [String] = []
    /// What the session was recorded as lost to, once it was.
    private(set) var lostAfterFailedCheck: Bool?
    /// What was recorded about the proxy, once it was.
    private(set) var proxyUntouched: Bool?

    func retireSessionLease() { steps.append("retire lease") }
    func closeNativeHandle() { steps.append("close handle") }
    func leaveNativeHandleBehind() { steps.append("leave handle") }
    func recordSessionLost(afterFailedCheck: Bool) {
        steps.append("lost")
        lostAfterFailedCheck = afterFailedCheck
    }
    func recordProxyUntouched(bySessionReplacement untouched: Bool) {
        steps.append("proxy")
        proxyUntouched = untouched
    }
    func forgetServerVersion() { steps.append("forget version") }
    func clearSessionReplacementMark() {
        steps.append("clear mark")
        sessionReplacementMark = .notMarked
    }
    func forgetEscapedSession() { steps.append("forget escaping") }
}

/// Closing a session marked to be replaced, against a scripted connection.
final class SASessionReplacementTests: XCTestCase {

    /// The lease's own handle goes before the handle it belongs to; the state that went with the
    /// session goes after both; the mark is cleared once everything that needs it has read it.
    func testTheStepsGoInOrder() {
        let host = SAScriptedReplacementHost()

        SASessionReplacement.closeMarkedSession(on: host)

        XCTAssertEqual(host.steps, ["retire lease", "close handle", "lost", "proxy", "forget version", "clear mark", "forget escaping"])
    }

    /// A handle at rest is closed with the session.
    func testAHandleAtRestIsClosed() {
        let host = SAScriptedReplacementHost()

        SASessionReplacement.closeMarkedSession(on: host)

        XCTAssertTrue(host.steps.contains("close handle"))
        XCTAssertFalse(host.steps.contains("leave handle"))
    }

    /// A handle a cut-off ping left in the middle of a read is left behind, not closed.
    func testAHandleLeftMidReadIsLeftBehind() {
        let host = SAScriptedReplacementHost()
        host.nativeHandleIsReadingOrWriting = true

        SASessionReplacement.closeMarkedSession(on: host)

        XCTAssertTrue(host.steps.contains("leave handle"))
        XCTAssertFalse(host.steps.contains("close handle"))
    }

    /// A handle whose transport is already gone, or that is not there at all, is left behind too.
    func testAHandleAlreadyGoneIsLeftBehind() {
        let transportGone = SAScriptedReplacementHost()
        transportGone.nativeHandleHasTransport = false
        SASessionReplacement.closeMarkedSession(on: transportGone)
        XCTAssertTrue(transportGone.steps.contains("leave handle"), "transport gone")
        XCTAssertFalse(transportGone.steps.contains("close handle"), "transport gone")

        let noHandle = SAScriptedReplacementHost()
        noHandle.nativeHandleHasTransport = false
        noHandle.nativeHandleHasBuffer = false
        SASessionReplacement.closeMarkedSession(on: noHandle)
        XCTAssertTrue(noHandle.steps.contains("leave handle"), "no handle")
        XCTAssertFalse(noHandle.steps.contains("close handle"), "no handle")
    }

    /// A session marked to go regardless went because a ping was cut off - a failed check - and
    /// is recorded as lost to one, so that it is restored on the check's limits. The mark is read
    /// before it is cleared: the scripted host clears it for real. A session marked to go once
    /// nothing is open in it was not lost to a check.
    func testASessionTheProtocolCannotBeTrustedOnWasLostToAFailedCheck() {
        let cutOff = SAScriptedReplacementHost()
        cutOff.sessionReplacementMark = .regardless
        SASessionReplacement.closeMarkedSession(on: cutOff)
        XCTAssertEqual(cutOff.lostAfterFailedCheck, true)
        XCTAssertEqual(cutOff.sessionReplacementMark, .notMarked, "and the mark is cleared")

        let letGo = SAScriptedReplacementHost()
        letGo.sessionReplacementMark = .whenNothingIsOpen
        SASessionReplacement.closeMarkedSession(on: letGo)
        XCTAssertEqual(letGo.lostAfterFailedCheck, false)
        XCTAssertEqual(letGo.sessionReplacementMark, .notMarked)
    }

    /// A tunnel under the session is left as it stands, and the reconnect is told so; with no
    /// proxy there is nothing to leave.
    func testATunnelUnderTheSessionIsLeftAsItStands() {
        let tunnelled = SAScriptedReplacementHost()
        tunnelled.hasProxy = true
        SASessionReplacement.closeMarkedSession(on: tunnelled)
        XCTAssertEqual(tunnelled.proxyUntouched, true)

        let direct = SAScriptedReplacementHost()
        SASessionReplacement.closeMarkedSession(on: direct)
        XCTAssertEqual(direct.proxyUntouched, false)
    }

    /// What the session reported goes with it: the server's version, and the character set the
    /// escaper had from it.
    func testWhatTheSessionReportedGoesWithIt() {
        let host = SAScriptedReplacementHost()

        SASessionReplacement.closeMarkedSession(on: host)

        XCTAssertEqual(host.steps.filter { $0 == "forget version" }.count, 1)
        XCTAssertEqual(host.steps.filter { $0 == "forget escaping" }.count, 1)
        XCTAssertEqual(host.steps.filter { $0 == "retire lease" }.count, 1)
    }
}
