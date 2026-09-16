//
//  SAConnectionWorkCoordinatorTests.swift
//  SPMySQLFramework
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//
//  More info at <https://github.com/Sequel-Ace/Sequel-Ace>
//

import XCTest
@testable import SPMySQL

final class SAConnectionWorkCoordinatorTests: XCTestCase {
    private let coordinator = SAConnectionWorkCoordinator()

    func testQuickWorkIsNeverHandedToTheInterface() {
        var interfaceWasAsked = false
        let outcome = coordinator.run({ "done" }, whenSlow: { _ in interfaceWasAsked = true }, whenAbandonedWorkFinishes: {})

        XCTAssertTrue(outcome.finished)
        XCTAssertEqual(outcome.result as? String, "done")
        XCTAssertFalse(interfaceWasAsked)
    }

    func testWorkRunsAwayFromTheCallingThread() {
        let callingThread = Thread.current
        let outcome = coordinator.run({ Thread.current == callingThread }, whenSlow: { _ in }, whenAbandonedWorkFinishes: {})

        XCTAssertEqual(outcome.result as? Bool, false)
    }

    func testSlowWorkIsWaitedForByTheInterface() {
        let outcome = coordinator.run({
            Thread.sleep(forTimeInterval: 0.4)
            return "late"
        }, whenSlow: { isFinished in
            while !isFinished() {
                usleep(5_000)
            }
        }, whenAbandonedWorkFinishes: {})

        XCTAssertTrue(outcome.finished)
        XCTAssertEqual(outcome.result as? String, "late")
    }

    func testAnInterfaceThatStopsWaitingGetsNoResult() {
        let workStarted = DispatchSemaphore(value: 0)
        let workMayFinish = DispatchSemaphore(value: 0)
        let abandonedWorkReportedBack = DispatchSemaphore(value: 0)

        let outcome = coordinator.run({
            workStarted.signal()
            workMayFinish.wait()
            return "too late"
        }, whenSlow: { _ in
            // The interface gives up rather than waiting for the work to finish.
        }, whenAbandonedWorkFinishes: {
            abandonedWorkReportedBack.signal()
        })

        XCTAssertFalse(outcome.finished)
        XCTAssertNil(outcome.result)

        XCTAssertEqual(workStarted.wait(timeout: .now() + 2), .success)
        workMayFinish.signal()

        // The work that nobody waited for says so when it finally finishes.
        XCTAssertEqual(abandonedWorkReportedBack.wait(timeout: .now() + 2), .success)
    }

    func testWorkThatWasAbandonedDoesNotHoldUpWhatFollows() {
        let stuckWorkMayFinish = DispatchSemaphore(value: 0)

        _ = coordinator.run({
            stuckWorkMayFinish.wait()
            return nil
        }, whenSlow: { _ in }, whenAbandonedWorkFinishes: {})

        // The thread the abandoned work sits on must not be the one the next work waits for.
        let outcome = coordinator.run({ "next" }, whenSlow: { _ in }, whenAbandonedWorkFinishes: {})

        XCTAssertTrue(outcome.finished)
        XCTAssertEqual(outcome.result as? String, "next")

        stuckWorkMayFinish.signal()
    }

    func testTheNextPieceOfWorkStillRunsAfterACancellation() {
        coordinator.cancel()

        let outcome = coordinator.run({ 42 }, whenSlow: { _ in }, whenAbandonedWorkFinishes: {})

        XCTAssertTrue(outcome.finished)
        XCTAssertEqual(outcome.result as? Int, 42)
    }
}
