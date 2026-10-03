//
//  SAConnectionAttemptSequenceTests.swift
//  Unit Tests
//
//  Copyright (c) 2026 Sequel-Ace. All rights reserved.
//

import XCTest

final class SAConnectionAttemptSequenceTests: XCTestCase {

    private var service: SAHeldConnectionService!
    private var attempts: SAConnectionAttemptSequence!
    private var handOffs: [String] = []
    private var alerts: [String] = []

    override func setUp() {
        super.setUp()
        service = SAHeldConnectionService()
        attempts = SAConnectionAttemptSequence { [unowned self] in self.service.cancel() }
        handOffs = []
        alerts = []
    }

    func testStaleSuccessOfAnEarlierConnectionIsDroppedWhileTheNewerAttemptWaitsForCredentials() {
        let first = connect("A")
        let second = beginAttemptWithDelayedCredentials("B")

        service.deliver(.success("A"), toConnectionAt: 0)

        XCTAssertEqual(handOffs, [])
        XCTAssertEqual(alerts, [])
        XCTAssertEqual(service.cancelCount, 2, "starting B cancels A's connection")
        XCTAssertFalse(attempts.isCurrent(first))

        second()
        service.deliver(.success("B"), toConnectionAt: 1)

        XCTAssertEqual(handOffs, ["B"])
        XCTAssertEqual(alerts, [])
    }

    func testStaleFailureOfAnEarlierConnectionIsDroppedWhileTheNewerAttemptWaitsForCredentials() {
        _ = connect("A")
        let second = beginAttemptWithDelayedCredentials("B")

        service.deliver(.failure("A"), toConnectionAt: 0)

        XCTAssertEqual(handOffs, [])
        XCTAssertEqual(alerts, [])

        second()
        service.deliver(.failure("B"), toConnectionAt: 1)

        XCTAssertEqual(handOffs, [])
        XCTAssertEqual(alerts, ["B"])
    }

    func testLateCredentialsOfASupersededAttemptNeverConnect() {
        let first = beginAttemptWithDelayedCredentials("A")
        _ = connect("B")

        first()

        XCTAssertEqual(service.pending.count, 1, "only B connects")
        service.deliver(.success("B"), toConnectionAt: 0)
        XCTAssertEqual(handOffs, ["B"])
    }

    func testCancellingDropsTheCurrentAttempt() {
        _ = connect("A")

        attempts.cancel()
        service.deliver(.success("A"), toConnectionAt: 0)

        XCTAssertEqual(service.cancelCount, 2)
        XCTAssertEqual(handOffs, [])
        XCTAssertEqual(alerts, [])
    }

    // MARK: - Helpers

    /// Starts an attempt whose credentials are already resolved and begins connecting it.
    private func connect(_ name: String) -> UInt {
        let attemptID = attempts.begin()
        service.connect(completion: attempts.deliver(to: attemptID) { [unowned self] result in self.handle(result) })
        return attemptID
    }

    /// Starts an attempt and returns the call that delivers its credentials, which then connects it.
    private func beginAttemptWithDelayedCredentials(_ name: String) -> () -> Void {
        let attemptID = attempts.begin()
        let credentialsArrive = attempts.deliver(to: attemptID) { [unowned self] (_: Void) in
            self.service.connect(completion: self.attempts.deliver(to: attemptID) { [unowned self] result in self.handle(result) })
        }
        return { credentialsArrive(()) }
    }

    private func handle(_ result: SAHeldConnectionService.Result) {
        switch result {
        case .success(let name):
            handOffs.append(name)
        case .failure(let name):
            alerts.append(name)
        }
    }
}

/// A connection service stand-in that holds every completion until the test delivers it,
/// including completions of connections that were cancelled.
private final class SAHeldConnectionService {

    enum Result {
        case success(String)
        case failure(String)
    }

    private(set) var pending: [(Result) -> Void] = []
    private(set) var cancelCount = 0

    func connect(completion: @escaping (Result) -> Void) {
        pending.append(completion)
    }

    func cancel() {
        cancelCount += 1
    }

    func deliver(_ result: Result, toConnectionAt index: Int) {
        pending[index](result)
    }
}
