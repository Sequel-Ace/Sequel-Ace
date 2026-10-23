//
//  SATableLoadStopTests.swift
//  Unit Tests
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//
//  More info at <https://github.com/Sequel-Ace/Sequel-Ace>
//

import XCTest

/// What a table load the user stopped leaves behind, and what one that merely heard the button
/// after it had finished does not.
final class SATableLoadStopTests: XCTestCase {

    /// An interrupted load: Stop arrives with stages still to come, and they do not run.
    func testAnInterruptedLoadLeavesItsRemainingStagesUndone() {
        let stop = SATableLoadStop()
        stop.loadIsStarting()

        XCTAssertTrue(stop.shouldRunNextStage(), "the first stage runs")
        stop.stopWasAskedFor()
        XCTAssertFalse(stop.shouldRunNextStage(), "and the ones after the press do not")
        XCTAssertFalse(stop.shouldRunNextStage())

        XCTAssertTrue(stop.stopWasAsked)
        XCTAssertTrue(stop.aStageWasLeftUndone, "so the table's information is not there")
    }

    /// The last stage is let through and then cut off inside its own query. There is no gate after
    /// it to read the press, so the stage itself has to say that it did not finish - otherwise the
    /// table looks fully loaded with work that never happened.
    func testAStageCutOffAfterItsGateCountsAsUndone() {
        let stop = SATableLoadStop()
        stop.loadIsStarting()

        XCTAssertTrue(stop.shouldRunNextStage(), "the last stage is let through")
        stop.stopWasAskedFor()
        stop.noteStageEnded(havingCompleted: false)

        XCTAssertTrue(stop.aStageWasLeftUndone, "so the table's information is not all there")
    }

    /// A stage that finished records nothing, which is what keeps a press arriving after the last
    /// stage from costing a reload of a table that is sitting there complete.
    func testAStageThatFinishedRecordsNothing() {
        let stop = SATableLoadStop()
        stop.loadIsStarting()

        XCTAssertTrue(stop.shouldRunNextStage())
        stop.noteStageEnded(havingCompleted: true)
        stop.stopWasAskedFor()
        stop.noteStageEnded(havingCompleted: true)

        XCTAssertTrue(stop.stopWasAsked, "the press is still the press")
        XCTAssertFalse(stop.aStageWasLeftUndone, "but it prevented nothing")
    }

    /// A load that had already finished: the button is still live for the moment between the last
    /// stage and the end of the task, and a press in there prevented nothing.
    func testAnAlreadyCompletedLoadIsNotTakenForAStoppedOne() {
        let stop = SATableLoadStop()
        stop.loadIsStarting()

        for _ in 0..<4 {
            XCTAssertTrue(stop.shouldRunNextStage())
        }
        // The last stage has run; the press lands before the task ends.
        stop.stopWasAskedFor()

        XCTAssertTrue(stop.stopWasAsked, "the user did press it")
        XCTAssertFalse(stop.aStageWasLeftUndone,
                       "but nothing was left to stop, so the table is loaded and needs no reload")
    }

    /// The two questions are asked for different things, and only one of them follows the press
    /// on its own.
    func testPressingStopIsNotTheSameAsStoppingSomething() {
        let stop = SATableLoadStop()
        stop.loadIsStarting()
        XCTAssertFalse(stop.stopWasAsked)
        XCTAssertFalse(stop.aStageWasLeftUndone)

        stop.stopWasAskedFor()
        XCTAssertTrue(stop.stopWasAsked, "the press is known at once")
        XCTAssertFalse(stop.aStageWasLeftUndone, "and still nothing has been prevented")

        _ = stop.shouldRunNextStage()
        XCTAssertTrue(stop.aStageWasLeftUndone, "until a stage asks and is turned away")
    }

    /// A press while the load is already stopping changes nothing.
    func testPressingTwiceChangesNothing() {
        let stop = SATableLoadStop()
        stop.loadIsStarting()
        stop.stopWasAskedFor()
        XCTAssertFalse(stop.shouldRunNextStage())
        stop.stopWasAskedFor()
        XCTAssertFalse(stop.shouldRunNextStage())
        XCTAssertTrue(stop.aStageWasLeftUndone)
    }

    /// The next load starts clean, so what the one before it left does not follow the table.
    func testTheNextLoadStartsClean() {
        let stop = SATableLoadStop()
        stop.loadIsStarting()
        stop.stopWasAskedFor()
        XCTAssertFalse(stop.shouldRunNextStage())
        XCTAssertTrue(stop.aStageWasLeftUndone)

        stop.loadIsStarting()
        XCTAssertFalse(stop.stopWasAsked)
        XCTAssertFalse(stop.aStageWasLeftUndone)
        XCTAssertTrue(stop.shouldRunNextStage(), "and its stages run again")
    }
}
