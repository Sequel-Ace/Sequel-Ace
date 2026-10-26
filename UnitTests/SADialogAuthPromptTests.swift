//
//  SADialogAuthPromptTests.swift
//  Unit Tests
//
//  Created by Sequel Ace on October 26, 2026.
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import XCTest

final class SADialogAuthPromptTests: XCTestCase {

    // MARK: - Question types

    func testOnlyTypeTwoIsAPassword() {
        XCTAssertTrue(SADialogAuthPrompt.isSecure(type: 2))
        XCTAssertFalse(SADialogAuthPrompt.isSecure(type: 1))
        // The plugin passes the server's byte through unchecked, so anything
        // it has not seen before is shown rather than hidden.
        XCTAssertFalse(SADialogAuthPrompt.isSecure(type: 0))
        XCTAssertFalse(SADialogAuthPrompt.isSecure(type: 3))
    }

    // MARK: - Prompt text

    func testServerPromptIsShownAsSent() {
        XCTAssertEqual(SADialogAuthPrompt.message(for: "Password, please:"), "Password, please:")
    }

    func testPromptIsTrimmed() {
        XCTAssertEqual(SADialogAuthPrompt.message(for: "  Enter PIN \n"), "Enter PIN")
    }

    func testEmptyOrMissingPromptFallsBackToAFullSentence() {
        let fallback = SADialogAuthPrompt.message(for: nil)
        XCTAssertFalse(fallback.isEmpty)
        XCTAssertEqual(SADialogAuthPrompt.message(for: ""), fallback)
        XCTAssertEqual(SADialogAuthPrompt.message(for: "   \n "), fallback)
    }

    func testNonASCIIPromptSurvives() {
        XCTAssertEqual(SADialogAuthPrompt.message(for: "Contraseña:"), "Contraseña:")
    }

    // MARK: - Handing the answer to the plugin

    func testAnswerIsCopiedAsANulTerminatedCString() {
        let copy = try! XCTUnwrap(SADialogAuthPrompt.duplicate("hunter2"))
        defer { free(copy) }
        XCTAssertEqual(String(cString: copy), "hunter2")
    }

    func testEmptyAnswerIsStillAValidCString() {
        let copy = try! XCTUnwrap(SADialogAuthPrompt.duplicate(""))
        defer { free(copy) }
        XCTAssertEqual(copy.pointee, 0)
    }

    func testMultibyteAnswerIsCopiedWholeRatherThanCutShort() {
        // The plugin's own buffer is a fixed 1 KB; the answer is returned on
        // the heap instead so a long or multibyte secret is sent intact.
        let answer = String(repeating: "pässwörd", count: 400)
        let copy = try! XCTUnwrap(SADialogAuthPrompt.duplicate(answer))
        defer { free(copy) }
        XCTAssertEqual(String(cString: copy), answer)
        XCTAssertEqual(strlen(copy), strlen(answer))
    }
}
