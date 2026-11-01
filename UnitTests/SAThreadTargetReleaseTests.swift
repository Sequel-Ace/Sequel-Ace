//
//  SAThreadTargetReleaseTests.swift
//  Unit Tests
//
//  +[NSThread detachNewThreadWithName:target:selector:object:] hands its target's final release to the main
//  queue: a document controller whose tab closed while its task thread ran must not be deallocated on that thread.
//

import XCTest

/// Records where the probe was deallocated. Lives outside the probe so it survives it.
private final class DeallocRecord: @unchecked Sendable {
    let lock = NSLock()
    private var onMainThread: Bool?

    func record(onMainThread value: Bool) {
        lock.lock()
        onMainThread = value
        lock.unlock()
    }

    var recorded: Bool? {
        lock.lock()
        defer { lock.unlock() }
        return onMainThread
    }
}

private final class ThreadTargetProbe: NSObject, @unchecked Sendable {
    private let gate: DispatchSemaphore
    private let ran: XCTestExpectation?
    private let deallocated: XCTestExpectation?
    private let record: DeallocRecord?
    private let receivedLock = NSLock()
    private var _received: Any?

    var received: Any? {
        receivedLock.lock()
        defer { receivedLock.unlock() }
        return _received
    }

    init(gate: DispatchSemaphore = DispatchSemaphore(value: 1),
         ran: XCTestExpectation? = nil,
         deallocated: XCTestExpectation? = nil,
         record: DeallocRecord? = nil) {
        self.gate = gate
        self.ran = ran
        self.deallocated = deallocated
        self.record = record
        super.init()
    }

    @objc func work(_ argument: AnyObject?) {
        receivedLock.lock()
        _received = argument
        receivedLock.unlock()
        ran?.fulfill()
        // Park until the test lets go, then hand the signal back: a semaphore freed below its initial value traps.
        _ = gate.wait(timeout: .now() + 5)
        gate.signal()
    }

    deinit {
        record?.record(onMainThread: Thread.isMainThread)
        deallocated?.fulfill()
    }
}

final class SAThreadTargetReleaseTests: XCTestCase {

    private typealias DetachFunction = @convention(c) (AnyClass, Selector, NSString, AnyObject, Selector, AnyObject?) -> Void

    /// The category lives in Objective-C (SPThreadAdditions.m) and the test target has no bridging header, so it is
    /// called through the runtime.
    private func detach(name: String, target: AnyObject, selector: Selector, object: AnyObject?) throws {
        let detachSelector = NSSelectorFromString("detachNewThreadWithName:target:selector:object:")
        let method = try XCTUnwrap(class_getClassMethod(Thread.self, detachSelector))
        let function = unsafeBitCast(method_getImplementation(method), to: DetachFunction.self)
        function(Thread.self, detachSelector, name as NSString, target, selector, object)
    }

    func testTargetHeldOnlyByItsThreadIsDeallocatedOnTheMainThread() throws {
        let deallocated = expectation(description: "target deallocated")
        let record = DeallocRecord()
        let gate = DispatchSemaphore(value: 0)

        try autoreleasepool {
            let probe = ThreadTargetProbe(gate: gate, deallocated: deallocated, record: record)
            try detach(name: "SAThreadTargetReleaseTests probe", target: probe, selector: #selector(ThreadTargetProbe.work(_:)), object: nil)
        }
        // The test's own references are gone; the thread is parked in -work: and now holds the last one.
        gate.signal()

        wait(for: [deallocated], timeout: 5)
        XCTAssertEqual(record.recorded, true)
    }

    func testTargetStillRunsItsSelectorWithTheArgument() throws {
        let ran = expectation(description: "selector ran")
        let probe = ThreadTargetProbe(ran: ran)
        let payload = "payload" as NSString

        try detach(name: "SAThreadTargetReleaseTests argument", target: probe, selector: #selector(ThreadTargetProbe.work(_:)), object: payload)

        wait(for: [ran], timeout: 5)
        XCTAssertEqual(probe.received as? NSString, payload)
    }
}
