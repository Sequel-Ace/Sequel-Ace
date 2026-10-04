//
//  SASSHTunnelPromptCoordinatorTests.swift
//  Unit Tests
//
//  Created by the Sequel Ace team on September 2, 2026.
//  Copyright (c) 2026 Sequel-Ace. All rights reserved.
//

import XCTest

/// The prompt-teardown state machine behind the SSH tunnel's askpass
/// sheets (Step 1 of the SSH tunnel IPC plan), driven with a synchronous or
/// hand-pumped "main thread" so every ordering is deterministic.
final class SASSHTunnelPromptCoordinatorTests: XCTestCase {

    private var lock: NSLock!
    private var queued: [() -> Void] = []
    private var dismissals = 0

    override func setUp() {
        super.setUp()
        lock = NSLock()
        queued = []
        dismissals = 0
    }

    /// Runs teardown blocks immediately, as if already on the main thread.
    private func immediate() -> SASSHTunnelPromptCoordinator {
        SASSHTunnelPromptCoordinator(answerLock: lock, runOnMain: { $0() })
    }

    /// Queues teardown blocks so the test decides when "main" gets to them.
    private func pumped() -> SASSHTunnelPromptCoordinator {
        SASSHTunnelPromptCoordinator(answerLock: lock, runOnMain: { self.queued.append($0) })
    }

    private func pump() {
        let blocks = queued
        queued = []
        blocks.forEach { $0() }
    }

    private func present(_ coordinator: SASSHTunnelPromptCoordinator) {
        coordinator.promptDidPresent { [self] in
            dismissals += 1
            lock.unlock()
        }
    }

    // MARK: - Nothing in flight

    func testTeardownWithNothingInFlightChangesNothing() {
        let coordinator = immediate()
        coordinator.cancelPendingPrompt()
        XCTAssertTrue(coordinator.shouldPresentPrompt(whileSSHRunning: true), "no latch was set")
        XCTAssertFalse(coordinator.isPresenting)
        XCTAssertTrue(lock.try(), "the lock was left free")
        lock.unlock()
    }

    // MARK: - Prompt started, sheet not yet up

    func testTeardownBeforeTheWorkerLatchesAndTheWorkerDoesNotPresent() {
        let coordinator = immediate()
        lock.lock()  // the prompt request took the answer lock on main
        coordinator.cancelPendingPrompt()
        XCTAssertFalse(coordinator.shouldPresentPrompt(whileSSHRunning: true), "latched")
        XCTAssertTrue(coordinator.shouldPresentPrompt(whileSSHRunning: true), "the latch is consumed")
        XCTAssertEqual(dismissals, 0)
        lock.unlock()
    }

    func testLatchIsClearedByANewAttempt() {
        let coordinator = immediate()
        lock.lock()
        coordinator.cancelPendingPrompt()
        lock.unlock()
        coordinator.reset()
        XCTAssertTrue(coordinator.shouldPresentPrompt(whileSSHRunning: true))
    }

    // MARK: - Sheet on screen

    func testTeardownDismissesAPresentedSheet() {
        let coordinator = immediate()
        lock.lock()
        XCTAssertTrue(coordinator.shouldPresentPrompt(whileSSHRunning: true))
        present(coordinator)
        XCTAssertTrue(coordinator.isPresenting)

        coordinator.cancelPendingPrompt()

        XCTAssertEqual(dismissals, 1)
        XCTAssertFalse(coordinator.isPresenting)
        XCTAssertTrue(coordinator.shouldPresentPrompt(whileSSHRunning: true), "dismissal does not also latch")
        XCTAssertTrue(lock.try(), "the dismisser released the answer lock")
        lock.unlock()
    }

    func testUserAnswerClearsThePresentationSoTeardownHasNothingToDismiss() {
        let coordinator = immediate()
        lock.lock()
        present(coordinator)
        coordinator.promptDidClose()
        lock.unlock()
        coordinator.cancelPendingPrompt()
        XCTAssertEqual(dismissals, 0)
    }

    // MARK: - Orderings on the real main thread

    func testTeardownQueuedBeforeTheWorkerRunsIsAppliedAfterTheSheetAppears() {
        // Teardown's block and the prompt's worker race for the main thread;
        // when the worker wins, the block must still dismiss the sheet.
        let coordinator = pumped()
        lock.lock()
        coordinator.cancelPendingPrompt()  // queued, not yet run
        XCTAssertTrue(coordinator.shouldPresentPrompt(whileSSHRunning: true), "no latch yet — the block has not run")
        present(coordinator)
        pump()
        XCTAssertEqual(dismissals, 1)
        XCTAssertFalse(coordinator.isPresenting)
    }

    func testTeardownRunningBeforeTheWorkerLatchesInstead() {
        let coordinator = pumped()
        lock.lock()
        coordinator.cancelPendingPrompt()
        pump()  // the block wins the race
        XCTAssertFalse(coordinator.shouldPresentPrompt(whileSSHRunning: true))
        XCTAssertEqual(dismissals, 0)
        lock.unlock()
    }

    // MARK: - ssh gone

    func testWorkerDoesNotPresentOnceSSHHasExited() {
        let coordinator = immediate()
        XCTAssertFalse(coordinator.shouldPresentPrompt(whileSSHRunning: false))
    }

    // MARK: - Dealloc

    func testInvalidatedCoordinatorIgnoresTeardown() {
        let coordinator = pumped()
        lock.lock()
        present(coordinator)
        coordinator.invalidate()
        coordinator.cancelPendingPrompt()
        XCTAssertTrue(queued.isEmpty, "nothing is dispatched after invalidation")
        XCTAssertEqual(dismissals, 0)
        lock.unlock()
    }

    // MARK: - Objective-C surface

    func testConvenienceInitializerDispatchesToTheMainQueue() {
        let coordinator = SASSHTunnelPromptCoordinator(answerLock: lock)
        lock.lock()
        let ran = expectation(description: "teardown block ran on main")
        coordinator.promptDidPresent { [self] in
            XCTAssertTrue(Thread.isMainThread)
            dismissals += 1
            lock.unlock()
            ran.fulfill()
        }
        DispatchQueue.global().async { coordinator.cancelPendingPrompt() }
        wait(for: [ran], timeout: 5)
        XCTAssertEqual(dismissals, 1)
    }
}
