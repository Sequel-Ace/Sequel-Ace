//
//  SAScriptConsoleModelTests.swift
//  Unit Tests
//

import Combine
import XCTest

final class SAScriptConsoleModelTests: XCTestCase {

    private var cancellables = Set<AnyCancellable>()

    override func tearDown() {
        cancellables.removeAll()
        super.tearDown()
    }

    func testAppendIsBufferedUntilFlush() {
        let model = SAScriptConsoleModel(flushInterval: 60)
        model.append("a")
        model.append("b")
        XCTAssertEqual(model.text, "")
        model.flush()
        XCTAssertEqual(model.text, "ab")
    }

    func testFlushPublishesOnlyTheNewChunk() {
        let model = SAScriptConsoleModel(flushInterval: 60)
        var chunks: [String] = []
        model.appended.sink { chunks.append($0) }.store(in: &cancellables)
        model.append("one")
        model.flush()
        model.append("two")
        model.flush()
        model.flush()
        XCTAssertEqual(chunks, ["one", "two"])
        XCTAssertEqual(model.text, "onetwo")
    }

    func testScheduledFlushDeliversOnMainThread() {
        let model = SAScriptConsoleModel(flushInterval: 0.01)
        let delivered = expectation(description: "flushed")
        model.appended.sink { chunk in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertEqual(chunk, "bg")
            delivered.fulfill()
        }.store(in: &cancellables)
        DispatchQueue.global().async { model.append("bg") }
        wait(for: [delivered], timeout: 2)
        XCTAssertEqual(model.text, "bg")
    }

    func testConcurrentAppendsAreNotLost() {
        let model = SAScriptConsoleModel(flushInterval: 60)
        DispatchQueue.concurrentPerform(iterations: 1000) { _ in model.append("x") }
        model.flush()
        XCTAssertEqual(model.text.count, 1000)
    }

    func testClearDropsTextAndPendingOutput() {
        let model = SAScriptConsoleModel(flushInterval: 60)
        var clearCount = 0
        model.cleared.sink { clearCount += 1 }.store(in: &cancellables)
        model.append("old")
        model.flush()
        model.append("pending")
        model.clear()
        model.flush()
        XCTAssertEqual(model.text, "")
        XCTAssertEqual(clearCount, 1)
    }
}
