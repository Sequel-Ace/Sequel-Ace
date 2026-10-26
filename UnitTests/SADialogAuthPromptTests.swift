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

    private func message(_ prompt: String?, secure: Bool = false, isEncrypted: Bool = true) -> String {
        SADialogAuthPrompt.message(for: prompt, secure: secure, isEncrypted: isEncrypted)
    }

    func testServerPromptIsShownAsSent() {
        XCTAssertEqual(message("Password, please:"), "Password, please:")
    }

    func testPromptIsTrimmed() {
        XCTAssertEqual(message("  Enter PIN \n"), "Enter PIN")
    }

    func testEmptyOrMissingPromptFallsBackToAFullSentence() {
        let fallback = message(nil)
        XCTAssertFalse(fallback.isEmpty)
        XCTAssertEqual(message(""), fallback)
        XCTAssertEqual(message("   \n "), fallback)
    }

    func testNonASCIIPromptSurvives() {
        XCTAssertEqual(message("Contraseña:"), "Contraseña:")
    }

    // MARK: - Plaintext warning

    /// The dialog protocol sends every answer in clear text, and the client
    /// only requires TLS when SSL or the cleartext plugin was asked for, so a
    /// password question can arrive on a plaintext connection.
    func testPasswordOverPlaintextCarriesAWarning() {
        let warned = message("Password:", secure: true, isEncrypted: false)
        XCTAssertTrue(warned.hasPrefix("Password:"))
        XCTAssertGreaterThan(warned.count, "Password:".count)
        XCTAssertTrue(warned.localizedCaseInsensitiveContains("not encrypted"))
    }

    func testPasswordOverTLSIsNotWarnedAbout() {
        XCTAssertEqual(message("Password:", secure: true, isEncrypted: true), "Password:")
    }

    func testOrdinaryQuestionOverPlaintextIsNotWarnedAbout() {
        // Only a secret is worth interrupting for; the server asks ordinary
        // questions (a username, a one-time code prompt) over the same channel.
        XCTAssertEqual(message("Are you sure?", secure: false, isEncrypted: false), "Are you sure?")
    }

    func testFallbackPromptStillCarriesTheWarning() {
        let warned = message(nil, secure: true, isEncrypted: false)
        XCTAssertTrue(warned.hasPrefix(message(nil)))
        XCTAssertTrue(warned.localizedCaseInsensitiveContains("not encrypted"))
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
