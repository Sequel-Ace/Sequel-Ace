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

    /// From another thread the work runs on the main thread and is waited for, even while the main
    /// thread is inside a block on the main queue that only turns its run loop.
    func testWorkReachesAMainThreadThatIsBusyWithAMainQueueBlock() {
        let workReturned = DispatchSemaphore(value: 0)
        let blockEnded = expectation(description: "the main-queue block ended")
        var ranOn: Thread?
        var returnedInTime = false

        DispatchQueue.main.async {
            Thread.detachNewThread {
                SAMainRunLoop.runAndWait { ranOn = Thread.current }
                workReturned.signal()
            }
            let giveUp = Date(timeIntervalSinceNow: 3)
            while !returnedInTime && Date() < giveUp {
                returnedInTime = workReturned.wait(timeout: .now()) == .success
                RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
            }
            blockEnded.fulfill()
        }

        wait(for: [blockEnded], timeout: 5)
        XCTAssertTrue(returnedInTime, "the work was served by the run loop, not held up by the queue")
        XCTAssertTrue(ranOn?.isMainThread ?? false, "and ran on the main thread")
    }
}
