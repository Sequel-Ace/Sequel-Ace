//
//  SAMainRunLoopTests.swift
//  SPMySQLFramework
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//
//  More info at <https://github.com/Sequel-Ace/Sequel-Ace>
//

import XCTest
@testable import SPMySQL

/// Work connection threads ask of the main thread reaches it while the main thread waits for them.
final class SAMainRunLoopTests: XCTestCase {

    /// On the main thread the work simply runs, and runs there.
    func testOnTheMainThreadTheWorkRunsAtOnce() {
        var ranOn: Thread?
        SAMainRunLoop.runAndWait { ranOn = Thread.current }
        XCTAssertTrue(ranOn?.isMainThread ?? false)
    }

    /// From another thread the work runs on the main thread and is waited for - the block has
    /// finished before `runAndWait` returns - even while the main thread is inside a block on the
    /// main queue that only turns its run loop.
    func testWorkReachesAMainThreadThatIsBusyWithAMainQueueBlock() {
        assertWorkReachesTheBusyMainThread(pumping: .default)
    }

    /// The same while the main thread turns its loop in the modal panel mode - what a modal alert
    /// does, which is where the MFA dialog asks from. The block is scheduled in the common modes,
    /// so it is served there as well; scheduled in the default mode alone it would wait for the
    /// alert to end. The application makes the modal mode a common one; this process has no
    /// application, so the test does what the application does.
    func testWorkReachesAMainThreadInAModalRunLoopMode() {
        CFRunLoopAddCommonMode(CFRunLoopGetMain(), CFRunLoopMode(RunLoop.Mode.modalPanel.rawValue as CFString))
        assertWorkReachesTheBusyMainThread(pumping: .modalPanel)
    }

    /// Runs the work from another thread while the main thread is busy with a main-queue block
    /// that turns its run loop in the given mode, and checks that the work was done on the main
    /// thread and had finished before `runAndWait` returned.
    private func assertWorkReachesTheBusyMainThread(pumping mode: RunLoop.Mode, file: StaticString = #filePath, line: UInt = #line) {
        let workReturned = DispatchSemaphore(value: 0)
        let blockEnded = expectation(description: "the main-queue block ended")
        var ranOn: Thread?
        var finishedBeforeReturn = false
        var returnedInTime = false

        DispatchQueue.main.async {
            Thread.detachNewThread {
                var finished = false
                SAMainRunLoop.runAndWait {
                    ranOn = Thread.current
                    finished = true
                }
                finishedBeforeReturn = finished
                workReturned.signal()
            }
            let giveUp = Date(timeIntervalSinceNow: 3)
            while !returnedInTime && Date() < giveUp {
                returnedInTime = workReturned.wait(timeout: .now()) == .success
                RunLoop.current.run(mode: mode, before: Date(timeIntervalSinceNow: 0.01))
            }
            blockEnded.fulfill()
        }

        wait(for: [blockEnded], timeout: 5)
        XCTAssertTrue(returnedInTime, "the work was served by the run loop, not held up by the queue", file: file, line: line)
        XCTAssertTrue(ranOn?.isMainThread ?? false, "and ran on the main thread", file: file, line: line)
        XCTAssertTrue(finishedBeforeReturn, "and had finished before the call returned", file: file, line: line)
    }
}
