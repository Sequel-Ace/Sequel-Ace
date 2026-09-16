//
//  SAConnectionCheckSheetTests.swift
//  Unit Tests
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import XCTest

/// How the connection wait sheet ends its waits, alone and nested.
final class SAConnectionCheckSheetTests: XCTestCase {

    /// The wait loops deliver events, which needs an application object.
    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
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

    /// A wait stopped while another wait runs inside its loop has its work stopped right away.
    func testStoppingAnOuterWaitCancelsItsWorkWhileAnInnerWaitRuns() {
        let outer = SAConnectionCheckSheet()
        let inner = SAConnectionCheckSheet()
        let deadline = Date().addingTimeInterval(2)
        var outerChecks = 0
        var outerCancelled = false
        var cancelledDuringInnerWait = false

        outer.wait(in: nil, untilFinished: {
            outerChecks += 1

            // The first check comes before the wait has started; the second one stands in for an
            // event that starts another wait.
            if outerChecks == 2 {
                inner.wait(in: nil, untilFinished: {
                    if !outerCancelled {
                        outer.cancelButtonPressed()
                    }
                    cancelledDuringInnerWait = outerCancelled
                    return cancelledDuringInnerWait || Date() > deadline
                }, whenCancelled: nil)
            }
            return Date() > deadline
        }, whenCancelled: {
            outerCancelled = true
        })

        XCTAssertTrue(cancelledDuringInnerWait)
        XCTAssertLessThan(Date(), deadline)
    }
}
