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
