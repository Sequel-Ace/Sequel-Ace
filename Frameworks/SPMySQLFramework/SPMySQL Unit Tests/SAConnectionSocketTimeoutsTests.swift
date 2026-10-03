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

    /// The limits end a connection well before the connection timeout.
    func testTheLimitsEndAConnectionWellBeforeTheConnectionTimeout() {
        let keepAliveTotal = SAConnectionSocketTimeouts.keepAliveIdle
            + SAConnectionSocketTimeouts.keepAliveInterval * SAConnectionSocketTimeouts.keepAliveCount
        XCTAssertLessThan(keepAliveTotal, 30)
        XCTAssertLessThan(SAConnectionSocketTimeouts.retransmitDropTime, 30)
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
