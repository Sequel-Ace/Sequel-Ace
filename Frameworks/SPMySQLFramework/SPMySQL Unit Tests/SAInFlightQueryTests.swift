//
//  SAInFlightQueryTests.swift
//  SPMySQLFramework
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//
//  More info at <https://github.com/Sequel-Ace/Sequel-Ace>
//

import Darwin
import XCTest
@testable import SPMySQL

final class SAInFlightQueryTests: XCTestCase {
    private let inFlightQuery = SAInFlightQuery()
    private var descriptors: [Int32] = [-1, -1]

    override func setUpWithError() throws {
        try super.setUpWithError()
        try XCTSkipUnless(socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors) == 0, "no local socket pair available")
    }

    override func tearDown() {
        descriptors.filter { $0 >= 0 }.forEach { Darwin.close($0) }
        super.tearDown()
    }

    func testOnlyTheWaitingQueryIsEnded() {
        inFlightQuery.beginWaiting(forGeneration: 5, onSocket: descriptors[0], serverThread: 42)

        XCTAssertFalse(inFlightQuery.closeSocket(ifGenerationIsWaiting: 4, beforeClosing: {}))
        XCTAssertFalse(peerSawTheSocketClose())

        XCTAssertTrue(inFlightQuery.closeSocket(ifGenerationIsWaiting: 5, beforeClosing: {}))
        XCTAssertTrue(peerSawTheSocketClose())
    }

    func testAQueryThatStoppedWaitingIsLeftAlone() {
        inFlightQuery.beginWaiting(forGeneration: 5, onSocket: descriptors[0], serverThread: 42)
        inFlightQuery.endWaiting(forGeneration: 5)

        XCTAssertFalse(inFlightQuery.closeSocket(ifGenerationIsWaiting: 5, beforeClosing: {}))
        XCTAssertFalse(peerSawTheSocketClose())
    }

    func testAStaleEndDoesNotEndTheQueryThatFollowed() {
        inFlightQuery.beginWaiting(forGeneration: 6, onSocket: descriptors[0], serverThread: 42)
        inFlightQuery.endWaiting(forGeneration: 5)

        XCTAssertTrue(inFlightQuery.closeSocket(ifGenerationIsWaiting: 6, beforeClosing: {}))
    }

    func testThePreparationRunsOnlyWhenTheSocketIsClosed() {
        var preparedFor: [UInt] = []
        inFlightQuery.beginWaiting(forGeneration: 7, onSocket: descriptors[0], serverThread: 42)

        inFlightQuery.closeSocket(ifGenerationIsWaiting: 3, beforeClosing: { preparedFor.append(3) })
        inFlightQuery.closeSocket(ifGenerationIsWaiting: 7, beforeClosing: { preparedFor.append(7) })

        XCTAssertEqual(preparedFor, [7])
    }

    func testAnActionOnlyConcernsTheQueryThatIsStillWaiting() {
        var killedServerThreads: [UInt] = []
        inFlightQuery.beginWaiting(forGeneration: 8, onSocket: descriptors[0], serverThread: 17)

        XCTAssertFalse(inFlightQuery.perform(ifGenerationIsWaiting: 7) { killedServerThreads.append($0) })
        XCTAssertTrue(inFlightQuery.perform(ifGenerationIsWaiting: 8) { killedServerThreads.append($0) })

        inFlightQuery.endWaiting(forGeneration: 8)
        XCTAssertFalse(inFlightQuery.perform(ifGenerationIsWaiting: 8) { killedServerThreads.append($0) })

        XCTAssertEqual(killedServerThreads, [17])
    }

    func testNothingIsEverWaitingBeforeTheFirstQuery() {
        XCTAssertFalse(inFlightQuery.closeSocket(ifGenerationIsWaiting: 0, beforeClosing: {}))
    }

    /// Whether the other end of the pair has seen its peer shut down, without waiting for it.
    private func peerSawTheSocketClose() -> Bool {
        var byte: UInt8 = 0
        return recv(descriptors[1], &byte, 1, MSG_PEEK | MSG_DONTWAIT) == 0
    }
}
