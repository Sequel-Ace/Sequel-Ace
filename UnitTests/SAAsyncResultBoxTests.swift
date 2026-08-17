//
//  SAAsyncResultBoxTests.swift
//  Unit Tests
//
//  Created as part of the Swift 6 readiness work.
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import XCTest

final class SAAsyncResultBoxTests: XCTestCase {

    private enum TestError: Error, Equatable {
        case boom
        case other
    }

    func testAnUncompletedBoxHasNoResult() {
        let box = SAAsyncResultBox<Int>()

        XCTAssertNil(box.result)
    }

    func testSuccessIsRecorded() throws {
        let box = SAAsyncResultBox<String>()

        box.succeed("credentials")

        let result = try XCTUnwrap(box.result)
        XCTAssertEqual(try result.get(), "credentials")
    }

    func testFailureIsRecorded() throws {
        let box = SAAsyncResultBox<String>()

        box.fail(TestError.boom)

        let result = try XCTUnwrap(box.result)
        switch result {
        case .success(let value):
            XCTFail("expected a failure, got \(value)")
        case .failure(let error):
            XCTAssertEqual(error as? TestError, .boom)
        }
    }

    func testTheLastOutcomeWins() throws {
        let box = SAAsyncResultBox<String>()

        box.fail(TestError.boom)
        box.succeed("recovered")

        let result = try XCTUnwrap(box.result)
        XCTAssertEqual(try result.get(), "recovered")
    }

    /// The box exists because the waiting thread can time out while the task is
    /// still writing, so concurrent access must be safe.
    func testConcurrentCompletionsAreSafe() throws {
        let box = SAAsyncResultBox<Int>()

        DispatchQueue.concurrentPerform(iterations: 200) { iteration in
            if iteration.isMultiple(of: 2) {
                box.succeed(iteration)
            } else {
                box.fail(TestError.other)
            }
            _ = box.result
        }

        XCTAssertNotNil(box.result)
    }
}
