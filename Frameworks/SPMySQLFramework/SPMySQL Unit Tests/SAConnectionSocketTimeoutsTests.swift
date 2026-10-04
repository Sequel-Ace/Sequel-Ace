//
//  SAConnectionSocketTimeoutsTests.swift
//  SPMySQLFramework
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//
//  More info at <https://github.com/Sequel-Ace/Sequel-Ace>
//

import Darwin
import XCTest
@testable import SPMySQL

final class SAConnectionSocketTimeoutsTests: XCTestCase {
    private var openDescriptors: [Int32] = []

    /// Closes every socket the test opened.
    override func tearDown() {
        for descriptor in openDescriptors {
            Darwin.close(descriptor)
        }
        openDescriptors = []
        super.tearDown()
    }

    /// A TCP socket keeps the limits it was given.
    func testATCPSocketKeepsTheLimitsItWasGiven() throws {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        try XCTSkipUnless(descriptor >= 0, "no socket available")
        openDescriptors.append(descriptor)

        XCTAssertTrue(SAConnectionSocketTimeouts.apply(toSocket: descriptor))
        // A set flag reads back as the socket's own bit for it, not as one.
        XCTAssertNotEqual(readOption(descriptor, SOL_SOCKET, SO_KEEPALIVE), 0)
        XCTAssertEqual(readOption(descriptor, IPPROTO_TCP, TCP_KEEPALIVE), SAConnectionSocketTimeouts.keepAliveIdle)
        XCTAssertEqual(readOption(descriptor, IPPROTO_TCP, TCP_KEEPINTVL), SAConnectionSocketTimeouts.keepAliveInterval)
        XCTAssertEqual(readOption(descriptor, IPPROTO_TCP, TCP_KEEPCNT), SAConnectionSocketTimeouts.keepAliveCount)
        XCTAssertEqual(readOption(descriptor, IPPROTO_TCP, TCP_RXT_CONNDROPTIME), SAConnectionSocketTimeouts.retransmitDropTime)
    }

    /// A quiet session is kept across an ordinary handover, and still ends rather than lingering
    /// until the server's own timeout.
    ///
    /// The keepalive limits decide only quiet sockets, and dropping one of those costs any
    /// transaction it has open while nobody is waiting on it - so they are tolerant. Wi-Fi roams
    /// and VPN reconnects routinely take longer than half a minute; a session has to outlast that.
    func testAQuietSessionOutlastsAnOrdinaryHandover() {
        let keepAliveTotal = SAConnectionSocketTimeouts.keepAliveIdle
            + SAConnectionSocketTimeouts.keepAliveInterval * SAConnectionSocketTimeouts.keepAliveCount
        XCTAssertGreaterThanOrEqual(keepAliveTotal, 60, "an ordinary handover must not cost the session")
        XCTAssertEqual(keepAliveTotal, 110, "60 s quiet, then five questions ten seconds apart")
        XCTAssertLessThan(keepAliveTotal, 300, "and it still ends, well inside the server's wait_timeout")
    }

    /// Each limit is at or above the baseline the maintainers settled on.
    func testTheLimitsMeetTheAgreedBaseline() {
        XCTAssertGreaterThanOrEqual(SAConnectionSocketTimeouts.keepAliveIdle, 60)
        XCTAssertGreaterThanOrEqual(SAConnectionSocketTimeouts.keepAliveInterval, 10)
        XCTAssertGreaterThanOrEqual(SAConnectionSocketTimeouts.keepAliveCount, 5)
        XCTAssertGreaterThanOrEqual(SAConnectionSocketTimeouts.retransmitDropTime, 60)
    }

    /// The two kinds of limit are not interchangeable, and only one of them bounds a query that is
    /// waiting for its reply.
    ///
    /// `retransmitDropTime` ends the wait for data that was sent and never acknowledged, which is
    /// the route-disappeared case. It restarts with every acknowledgement, so a slow or lossy link
    /// - where acknowledgements arrive late but do arrive - is not mistaken for a dead one. The
    /// keepalive limits never see that case at all.
    func testTheWaitForAReplyIsBoundedSeparatelyFromAQuietSession() {
        XCTAssertLessThan(SAConnectionSocketTimeouts.retransmitDropTime,
                          SAConnectionSocketTimeouts.keepAliveIdle
                            + SAConnectionSocketTimeouts.keepAliveInterval * SAConnectionSocketTimeouts.keepAliveCount,
                          "unacknowledged data is given up on sooner than a session that is merely quiet")
        // And the explicit checks, which do not destroy a session to find out it is gone, stay
        // shorter than either: that is what notices a dead route promptly.
        XCTAssertLessThan(Int32(SAConnectionCheckBudget.pingLimit), SAConnectionSocketTimeouts.keepAliveIdle)
        XCTAssertLessThan(Int32(SAConnectionCheckBudget.connectLimit), SAConnectionSocketTimeouts.retransmitDropTime)
    }

    /// A local socket is left unchanged.
    func testALocalSocketIsLeftUnchanged() throws {
        var descriptors: [Int32] = [-1, -1]
        try XCTSkipUnless(socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors) == 0, "no local socket pair available")
        openDescriptors.append(contentsOf: descriptors)

        XCTAssertFalse(SAConnectionSocketTimeouts.apply(toSocket: descriptors[0]))
    }

    /// A missing descriptor is refused.
    func testAMissingDescriptorIsRefused() {
        XCTAssertFalse(SAConnectionSocketTimeouts.apply(toSocket: -1))
    }

    /// Reads one integer socket option back, so the test checks the socket rather than the code.
    private func readOption(_ descriptor: Int32, _ level: Int32, _ option: Int32) -> Int32 {
        var value: Int32 = -1
        var length = socklen_t(MemoryLayout<Int32>.size)
        guard getsockopt(descriptor, level, option, &value, &length) == 0 else {
            return -1
        }
        return value
    }
}
