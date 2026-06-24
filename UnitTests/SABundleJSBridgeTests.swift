//
//  SABundleJSBridgeTests.swift
//  Sequel Ace Unit Tests
//
//  Created as part of the WebView to WKWebView migration.
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import XCTest
import WebKit

final class SABundleJSBridgeTests: XCTestCase {

    private var bridge: SABundleJSBridge!

    override func setUp() {
        super.setUp()
        bridge = SABundleJSBridge()
    }

    override func tearDown() {
        bridge = nil
        super.tearDown()
    }

    private func payload(fn: String, args: [Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: ["fn": fn, "args": args])
        return String(data: data, encoding: .utf8)!
    }

    private func handleSentinelPrompt(fn: String, args: [Any]) -> String? {
        bridge.handlePrompt(SABundleJSBridge.promptSentinel, defaultText: payload(fn: fn, args: args))
    }

    // MARK: - Synchronous channel (prompt tunnel)

    func testGenuinePromptIsNotHandled() {
        XCTAssertNil(bridge.handlePrompt("What is your name?", defaultText: "Hans"))
    }

    func testSentinelWithMalformedPayloadReturnsEmptyString() {
        XCTAssertEqual(bridge.handlePrompt(SABundleJSBridge.promptSentinel, defaultText: "not json"), "")
        XCTAssertEqual(bridge.handlePrompt(SABundleJSBridge.promptSentinel, defaultText: nil), "")
    }

    func testRunReturnsCommandOutput() {
        var received: (command: String, uuid: String?)?
        bridge.actions.run = { command, uuid in
            received = (command, uuid)
            return "command output"
        }

        XCTAssertEqual(handleSentinelPrompt(fn: "run", args: ["echo hi"]), "command output")
        XCTAssertEqual(received?.command, "echo hi")
        XCTAssertNil(received?.uuid)
    }

    func testRunPassesUUIDWhenProvided() {
        var receivedUUID: String?
        bridge.actions.run = { _, uuid in
            receivedUUID = uuid
            return ""
        }

        _ = handleSentinelPrompt(fn: "run", args: ["echo hi", "ABC-123"])

        XCTAssertEqual(receivedUUID, "ABC-123")
    }

    func testRunTreatsJSONNullUUIDAsNil() {
        var runCalled = false
        var receivedUUID: String?
        bridge.actions.run = { _, uuid in
            runCalled = true
            receivedUUID = uuid
            return ""
        }

        // JSON.stringify maps an undefined uuid in the args array to null.
        _ = handleSentinelPrompt(fn: "run", args: ["echo hi", NSNull()])

        XCTAssertTrue(runCalled)
        XCTAssertNil(receivedUUID)
    }

    func testRunWithoutCommandReturnsEmptyStringWithoutInvokingAction() {
        var runCalled = false
        bridge.actions.run = { _, _ in
            runCalled = true
            return "should not happen"
        }

        XCTAssertEqual(handleSentinelPrompt(fn: "run", args: []), "")
        XCTAssertFalse(runCalled)
    }

    func testShellEnvironmentLookup() {
        bridge.actions.shellEnvironment = { name in
            name == "HOME" ? "/Users/test" : nil
        }

        XCTAssertEqual(handleSentinelPrompt(fn: "getShellEnvironmentForName", args: ["HOME"]), "/Users/test")
        XCTAssertEqual(handleSentinelPrompt(fn: "getShellEnvironmentForName", args: ["MISSING"]), "")
    }

    func testUnknownSyncFunctionReturnsEmptyString() {
        XCTAssertEqual(handleSentinelPrompt(fn: "definitelyNotAFunction", args: []), "")
    }

    // MARK: - Fire-and-forget channel (script messages)

    func testInsertTextMessage() {
        var inserted: String?
        bridge.actions.insertText = { inserted = $0 }

        bridge.handleMessage(["fn": "insertText", "args": ["hello"]])

        XCTAssertEqual(inserted, "hello")
    }

    func testSetTextMessage() {
        var text: String?
        bridge.actions.setText = { text = $0 }

        bridge.handleMessage(["fn": "setText", "args": ["replaced"]])

        XCTAssertEqual(text, "replaced")
    }

    func testSetSelectedTextRangeMessage() {
        var range: String?
        bridge.actions.setSelectedTextRange = { range = $0 }

        bridge.handleMessage(["fn": "setSelectedTextRange", "args": ["{0, 5}"]])

        XCTAssertEqual(range, "{0, 5}")
    }

    func testWindowControlMessages() {
        var madeKey = false
        var closed = false
        var suppressed = false
        bridge.actions.makeWindowKey = { madeKey = true }
        bridge.actions.closeWindow = { closed = true }
        bridge.actions.suppressExceptionAlert = { suppressed = true }

        bridge.handleMessage(["fn": "makeHTMLOutputWindowKeyWindow", "args": []])
        bridge.handleMessage(["fn": "closeHTMLOutputWindow", "args": []])
        bridge.handleMessage(["fn": "suppressExceptionAlert", "args": []])

        XCTAssertTrue(madeKey)
        XCTAssertTrue(closed)
        XCTAssertTrue(suppressed)
    }

    func testReportErrorMessage() {
        var report: (message: String, source: String, line: Int)?
        bridge.actions.reportJSError = { message, source, line in
            report = (message, source, line)
        }

        bridge.handleMessage(["fn": "reportError", "args": ["boom", "inline.js", 42]])

        XCTAssertEqual(report?.message, "boom")
        XCTAssertEqual(report?.source, "inline.js")
        XCTAssertEqual(report?.line, 42)
    }

    func testReportErrorMessageWithDoubleLineNumber() {
        // JavaScript numbers can bridge as Double.
        var line: Int?
        bridge.actions.reportJSError = { _, _, reportedLine in
            line = reportedLine
        }

        bridge.handleMessage(["fn": "reportError", "args": ["boom", "inline.js", 42.0]])

        XCTAssertEqual(line, 42)
    }

    func testUnknownOrMalformedMessagesAreIgnored() {
        // None of these should crash or invoke anything.
        bridge.handleMessage(["fn": "noSuchFunction", "args": []])
        bridge.handleMessage(["args": ["missing fn"]])
        bridge.handleMessage("not a dictionary")
        bridge.handleMessage(42)
    }

    // MARK: - Injected user script

    func testUserScriptDefinesLegacySystemAPI() {
        let script = SABundleJSBridge.makeUserScript()

        XCTAssertEqual(script.injectionTime, .atDocumentStart)
        XCTAssertFalse(script.isForMainFrameOnly)

        let legacyFunctions = [
            "run",
            "getShellEnvironmentForName",
            "insertText",
            "setText",
            "setSelectedTextRange",
            "makeHTMLOutputWindowKeyWindow",
            "closeHTMLOutputWindow",
            "suppressExceptionAlert",
        ]
        for function in legacyFunctions {
            XCTAssertTrue(script.source.contains("\(function):"), "user script should define window.system.\(function)")
        }

        XCTAssertTrue(script.source.contains("window.system"))
        XCTAssertTrue(script.source.contains("window.onerror"))
        XCTAssertTrue(script.source.contains(SABundleJSBridge.promptSentinel))
        XCTAssertTrue(script.source.contains("window.webkit.messageHandlers.\(SABundleJSBridge.messageHandlerName)"))
    }
}
