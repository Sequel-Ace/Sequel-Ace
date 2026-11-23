//
//  SASheetEndingTests.swift
//  Unit Tests
//

import AppKit
import XCTest

final class SASheetEndingTests: XCTestCase {

    private var windows: [NSWindow] = []

    override func tearDown() {
        for window in windows {
            for sheet in window.sheets { window.endSheet(sheet) }
            window.orderOut(nil)
        }
        windows = []
        super.tearDown()
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 400, height: 300),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        windows.append(window)
        return window
    }

    func testTheResponseIsCancelNotAbort() {
        XCTAssertEqual(SASheetEnding.response, .cancel)
        XCTAssertEqual(SASheetEnding.response.rawValue, 0)
        XCTAssertNotEqual(SASheetEnding.response, .abort)
    }

    func testAWindowWithoutSheetsIsLeftAlone() {
        SASheetEnding.endAll(of: makeWindow())
    }

    func testASheetEndsWithCancelAndDetaches() {
        let window = makeWindow()
        let sheet = makeWindow()
        var responses: [NSApplication.ModalResponse] = []
        window.beginSheet(sheet) { responses.append($0) }
        XCTAssertNotNil(window.attachedSheet)
        SASheetEnding.endAll(of: window)
        XCTAssertEqual(responses, [.cancel])
        XCTAssertNil(window.attachedSheet)
        XCTAssertNil(sheet.sheetParent)
    }

    /// The completion handlers upstream write as `if (returnCode)` / `returnCode ? ... : ...` take the cancel path.
    func testTheResponseIsFalsyToATruthinessCheck() {
        let window = makeWindow()
        let sheet = makeWindow()
        var proceeded: Bool?
        window.beginSheet(sheet) { proceeded = ($0.rawValue != 0) }
        SASheetEnding.endAll(of: window)
        XCTAssertEqual(proceeded, false)
    }

    func testASheetOnASheetEndsFirst() {
        let window = makeWindow()
        let outer = makeWindow()
        let inner = makeWindow()
        var order: [String] = []
        window.beginSheet(outer) { order.append("outer \($0.rawValue)") }
        outer.beginSheet(inner) { order.append("inner \($0.rawValue)") }
        SASheetEnding.endAll(of: window)
        XCTAssertEqual(order, ["inner 0", "outer 0"])
        XCTAssertNil(window.attachedSheet)
        XCTAssertNil(outer.attachedSheet)
    }

    /// A handler that presents another sheet as the first one ends (a queued or chained sheet) is ended too.
    func testASheetPresentedByACompletionHandlerIsEndedToo() {
        let window = makeWindow()
        let first = makeWindow()
        let second = makeWindow()
        var order: [String] = []
        window.beginSheet(first) { [unowned window] response in
            order.append("first \(response.rawValue)")
            window.beginSheet(second) { order.append("second \($0.rawValue)") }
        }
        SASheetEnding.endAll(of: window)
        XCTAssertEqual(order, ["first 0", "second 0"])
        XCTAssertNil(window.attachedSheet)
    }

    /// A handler that keeps presenting sheets cannot make the close spin: three passes, then it gives up.
    func testARunawayChainOfSheetsStopsAfterThreePasses() {
        let window = makeWindow()
        var begun = 0
        var keepGoing = true
        func present() {
            let sheet = makeWindow()
            begun += 1
            window.beginSheet(sheet) { _ in if keepGoing { present() } }
        }
        present()
        SASheetEnding.endAll(of: window)
        keepGoing = false
        XCTAssertEqual(begun, 4)
        XCTAssertNotNil(window.attachedSheet)
    }
}
