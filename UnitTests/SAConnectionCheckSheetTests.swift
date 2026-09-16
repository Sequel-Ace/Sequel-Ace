//
//  SAConnectionCheckSheetTests.swift
//  Unit Tests
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import XCTest

/// How the connection wait sheet ends its waits, alone and nested, and what nested waits show.
final class SAConnectionCheckSheetTests: XCTestCase {

    private let windowA = NSObject()
    private let windowB = NSObject()

    /// The wait loops deliver events, which needs an application object.
    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
    }

    /// Describes one wait for the sheet decision.
    private func wait(_ window: NSObject?, suspended: Bool = false, ended: Bool = false) -> SAConnectionWaitSheetInput {
        return SAConnectionWaitSheetInput(window: window.map(ObjectIdentifier.init), isSuspended: suspended, hasEnded: ended)
    }

    /// Stopping a wait asks its work to stop once, and ends the wait.
    func testStoppingAWaitCancelsItsWorkOnce() {
        let sheet = SAConnectionCheckSheet()
        var checks = 0
        var cancellations = 0

        sheet.wait(in: nil, untilFinished: {
            checks += 1
            if checks == 2 {
                sheet.cancelButtonPressed()
            }
            return checks > 1_000
        }, whenCancelled: {
            cancellations += 1
        })

        XCTAssertEqual(cancellations, 1)
        XCTAssertLessThan(checks, 1_000)
    }

    /// A wait stopped while another wait's loop runs inside its own has its work stopped right away.
    func testStoppingAnOuterWaitCancelsItsWorkWhileAnInnerWaitRuns() {
        let outer = SAConnectionCheckSheet()
        let inner = SAConnectionCheckSheet()
        let deadline = Date().addingTimeInterval(2)
        var outerChecks = 0
        var innerChecks = 0
        var outerCancelled = false
        var cancelledDuringInnerWait = false

        outer.wait(in: nil, untilFinished: {
            outerChecks += 1

            // The first check comes before the wait has started; the second one stands in for an
            // event that starts another wait.
            if outerChecks == 2 {
                inner.wait(in: nil, untilFinished: {
                    innerChecks += 1

                    // The first check comes before the inner loop runs; the third is inside it.
                    if innerChecks == 3 {
                        outer.cancelButtonPressed()
                    }
                    if innerChecks > 3 {
                        cancelledDuringInnerWait = outerCancelled
                        return true
                    }
                    return Date() > deadline
                }, whenCancelled: nil)
            }
            return Date() > deadline
        }, whenCancelled: {
            outerCancelled = true
        })

        XCTAssertGreaterThan(innerChecks, 3)
        XCTAssertTrue(cancelledDuringInnerWait)
        XCTAssertLessThan(Date(), deadline)
    }

    /// What connection work asks of the main thread is done while a wait runs, even a wait inside
    /// a block on the main queue.
    func testWorkThatAsksTheMainThreadIsServedDuringAWait() {
        let sheet = SAConnectionCheckSheet()
        let deadline = Date().addingTimeInterval(2)
        let lock = NSLock()
        var askedOnMainThread = false
        var waitEndedInTime = false
        let waitEnded = expectation(description: "the wait is over")

        DispatchQueue.main.async {
            // The main thread is busy with this block until the wait below is over, so the work can
            // only be served by the wait.
            Thread.detachNewThread {
                SAMainRunLoop.runAndWait {
                    lock.lock()
                    askedOnMainThread = Thread.isMainThread
                    lock.unlock()
                }
            }
            sheet.wait(in: nil, untilFinished: {
                lock.lock()
                defer { lock.unlock() }
                return askedOnMainThread || Date() > deadline
            }, whenCancelled: nil)
            waitEndedInTime = Date() <= deadline
            waitEnded.fulfill()
        }

        wait(for: [waitEnded], timeout: 3)
        lock.lock()
        defer { lock.unlock() }
        XCTAssertTrue(askedOnMainThread)
        XCTAssertTrue(waitEndedInTime)
    }

    /// The time a wait shows is counted from the start of that wait, whether or not a sheet is up yet.
    func testEachWaitCountsItsTimeFromItsOwnStart() {
        let sheet = SAConnectionCheckSheet()

        /// Runs one wait without a window and returns when it started, as seen while it was going on.
        func startOfAWait() -> Date? {
            var checks = 0
            var seenStart: Date?
            sheet.wait(in: nil, untilFinished: {
                checks += 1
                if checks == 2 {
                    seenStart = sheet.waitStartDate
                }
                return checks >= 2
            }, whenCancelled: nil)
            return seenStart
        }

        let beforeFirstWait = Date()
        let firstStart = startOfAWait()
        XCTAssertNotNil(firstStart)
        XCTAssertGreaterThanOrEqual(firstStart ?? .distantPast, beforeFirstWait)

        let beforeSecondWait = Date()
        let secondStart = startOfAWait()
        XCTAssertGreaterThanOrEqual(secondStart ?? .distantPast, beforeSecondWait)
    }

    /// A single wait shows its sheet, and none once it is over.
    func testASingleWaitShowsItsSheetUntilItIsOver() {
        XCTAssertEqual(SAConnectionCheckSheet.sheetStates(for: [wait(windowA)]), [.waiting])
        XCTAssertEqual(SAConnectionCheckSheet.sheetStates(for: [wait(windowA, ended: true)]), [.hidden])
    }

    /// A wait that is over beneath another one keeps its window blocked.
    func testAnEndedWaitBeneathAnotherKeepsItsWindowBlocked() {
        XCTAssertEqual(SAConnectionCheckSheet.sheetStates(for: [wait(windowA, ended: true), wait(windowB)]),
                       [.finishing, .waiting])
        XCTAssertEqual(SAConnectionCheckSheet.sheetStates(for: [wait(windowA, ended: true), wait(windowB, ended: true)]),
                       [.finishing, .hidden])
    }

    /// A window shows the sheet of its innermost wait only.
    func testAWindowShowsTheSheetOfItsInnermostWait() {
        XCTAssertEqual(SAConnectionCheckSheet.sheetStates(for: [wait(windowA), wait(windowA)]), [.hidden, .waiting])
        XCTAssertEqual(SAConnectionCheckSheet.sheetStates(for: [wait(windowA), wait(windowA, ended: true)]), [.waiting, .hidden])
        XCTAssertEqual(SAConnectionCheckSheet.sheetStates(for: [wait(windowA), wait(windowA, ended: true), wait(windowB)]),
                       [.hidden, .finishing, .waiting])
    }

    /// An ended wait beneath a wait of its own window leaves that window to it.
    func testAnEndedWaitBeneathAWaitOfItsOwnWindowShowsNothing() {
        XCTAssertEqual(SAConnectionCheckSheet.sheetStates(for: [wait(windowA, ended: true), wait(windowA, ended: true)]),
                       [.hidden, .hidden])
        XCTAssertEqual(SAConnectionCheckSheet.sheetStates(for: [wait(windowA, ended: true), wait(windowB), wait(windowA)]),
                       [.hidden, .waiting, .waiting])
    }

    /// Waits that stepped aside for a question show nothing and hold nothing.
    func testSuspendedWaitsShowNothing() {
        XCTAssertEqual(SAConnectionCheckSheet.sheetStates(for: [wait(windowA, suspended: true)]), [.hidden])
        XCTAssertEqual(SAConnectionCheckSheet.sheetStates(for: [wait(windowA), wait(windowA, suspended: true)]), [.waiting, .hidden])
    }

    /// Waits without a window never hold one.
    func testWaitsWithoutAWindowHoldNone() {
        XCTAssertEqual(SAConnectionCheckSheet.sheetStates(for: [wait(nil), wait(nil)]), [.waiting, .waiting])
    }
}
