//
//  SAConnectionLivenessProbeTests.swift
//  SPMySQLFramework
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//
//  More info at <https://github.com/Sequel-Ace/Sequel-Ace>
//

import Darwin
import XCTest
@testable import SPMySQL

final class SAConnectionLivenessProbeTests: XCTestCase {
    private var openDescriptors: [Int32] = []

    override func tearDown() {
        for descriptor in openDescriptors {
            Darwin.close(descriptor)
        }
        openDescriptors = []
        super.tearDown()
    }

    func testQuietSocketWithALivePeerIsLeftAlone() throws {
        let pair = try makeLocalPair()
        XCTAssertFalse(SAConnectionLivenessProbe.shouldVerifyConnection(idleFor: 5, socket: pair.first))
    }

    func testClosedPeerIsVerified() throws {
        let pair = try makeLocalPair()
        closeDescriptor(pair.second)
        XCTAssertTrue(SAConnectionLivenessProbe.shouldVerifyConnection(idleFor: 5, socket: pair.first))
    }

    func testRecentTrafficSkipsTheProbeEntirely() throws {
        let pair = try makeLocalPair()
        closeDescriptor(pair.second)
        XCTAssertFalse(SAConnectionLivenessProbe.shouldVerifyConnection(idleFor: 0.5, socket: pair.first))
    }

    func testPendingDataDoesNotCountAsALostPeer() throws {
        let pair = try makeLocalPair()
        var byte: UInt8 = 42
        XCTAssertEqual(Darwin.send(pair.second, &byte, 1, 0), 1)
        XCTAssertFalse(SAConnectionLivenessProbe.shouldVerifyConnection(idleFor: 5, socket: pair.first))
    }

    func testMissingDescriptorIsLeftAlone() {
        XCTAssertFalse(SAConnectionLivenessProbe.shouldVerifyConnection(idleFor: 5, socket: -1))
    }

    func testRoutableLoopbackPeerIsLeftAlone() throws {
        let connection = try makeLoopbackConnection()
        XCTAssertFalse(SAConnectionLivenessProbe.shouldVerifyConnection(idleFor: 5, socket: connection.client))
    }

    func testLoopbackPeerThatWentAwayIsVerified() throws {
        let connection = try makeLoopbackConnection()
        closeDescriptor(connection.server)
        XCTAssertTrue(waitForProbeToReportAGonePeer(on: connection.client))
    }

    /// Waits briefly for the close to reach the other socket, which happens on its own schedule.
    private func waitForProbeToReportAGonePeer(on descriptor: Int32) -> Bool {
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if SAConnectionLivenessProbe.shouldVerifyConnection(idleFor: 5, socket: descriptor) {
                return true
            }
            usleep(10_000)
        }
        return false
    }

    /// Closes one of the test's sockets and stops tracking it, so it is closed exactly once.
    private func closeDescriptor(_ descriptor: Int32) {
        openDescriptors.removeAll { $0 == descriptor }
        Darwin.close(descriptor)
    }

    /// A connected pair of local sockets, closed again when the test ends.
    private func makeLocalPair() throws -> (first: Int32, second: Int32) {
        var descriptors: [Int32] = [-1, -1]
        try XCTSkipUnless(socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors) == 0, "no local socket pair available")
        openDescriptors.append(contentsOf: descriptors)
        return (descriptors[0], descriptors[1])
    }

    /// A TCP connection over the loopback interface, closed again when the test ends.
    private func makeLoopbackConnection() throws -> (client: Int32, server: Int32) {
        let listener = socket(AF_INET, SOCK_STREAM, 0)
        try XCTSkipUnless(listener >= 0, "no listening socket available")
        openDescriptors.append(listener)

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_port = 0

        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { boundAddress in
                Darwin.bind(listener, boundAddress, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        try XCTSkipUnless(bound == 0, "loopback is not bindable here")
        try XCTSkipUnless(Darwin.listen(listener, 1) == 0, "loopback does not accept connections here")

        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { namedAddress in
                Darwin.getsockname(listener, namedAddress, &length)
            }
        }
        try XCTSkipUnless(named == 0, "the listening port cannot be read")

        let client = socket(AF_INET, SOCK_STREAM, 0)
        try XCTSkipUnless(client >= 0, "no client socket available")
        openDescriptors.append(client)

        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { targetAddress in
                Darwin.connect(client, targetAddress, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        try XCTSkipUnless(connected == 0, "loopback connections are not possible here")

        let server = Darwin.accept(listener, nil, nil)
        try XCTSkipUnless(server >= 0, "the loopback connection was not accepted")
        openDescriptors.append(server)

        return (client, server)
    }
}
