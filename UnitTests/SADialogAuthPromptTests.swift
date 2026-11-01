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

    private func message(_ prompt: String?, secure: Bool = false, isEncrypted: Bool = true, isServerVerified: Bool = true) -> String {
        SADialogAuthPrompt.message(for: prompt, secure: secure, isEncrypted: isEncrypted, isServerVerified: isServerVerified)
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
        XCTAssertTrue(warned.hasSuffix("Password:"))
        XCTAssertGreaterThan(warned.count, "Password:".count)
        XCTAssertTrue(warned.localizedCaseInsensitiveContains("not encrypted"))
    }

    /// An alert's height is capped and the overflow scrolls, so a question
    /// long enough — and the server writes the question — would push a
    /// trailing warning out of view of someone about to answer it.
    func testWarningPrecedesTheServerSuppliedQuestion() {
        let question = String(repeating: "Please confirm your identity. ", count: 200)
        let warned = message(question, secure: true, isEncrypted: false)
        let warningAt = try! XCTUnwrap(warned.range(of: "not encrypted", options: .caseInsensitive))
        let questionAt = try! XCTUnwrap(warned.range(of: "Please confirm"))
        XCTAssertLessThan(warningAt.lowerBound, questionAt.lowerBound)
    }

    func testPasswordOverVerifiedTLSIsNotWarnedAbout() {
        XCTAssertEqual(message("Password:", secure: true, isEncrypted: true), "Password:")
    }

    func testUnverifiedTLSWarnsBeforeTheServerSuppliedQuestion() {
        let question = String(repeating: "Please confirm your identity. ", count: 200)
        let warned = message(question, secure: true, isServerVerified: false)
        XCTAssertTrue(warned.hasPrefix("This connection is encrypted, but the server's identity has not been verified."))
        XCTAssertTrue(warned.hasSuffix(question.trimmingCharacters(in: .whitespacesAndNewlines)))
    }

    func testQuestionTypeCannotSuppressUnverifiedTLSWarning() {
        let password = message("Password:", secure: true, isServerVerified: false)
        let ordinary = message("Password:", secure: false, isServerVerified: false)
        XCTAssertEqual(password, ordinary)
        XCTAssertTrue(ordinary.contains("identity has not been verified"))
    }

    func testMissingVerificationDefaultsToWarning() {
        let warned = SADialogAuthPrompt.message(for: nil, secure: true, isEncrypted: true)
        XCTAssertTrue(warned.contains("identity has not been verified"))
        XCTAssertTrue(warned.hasSuffix(message(nil)))
    }

    func testOrdinaryQuestionOverPlaintextIsAlsoWarnedAbout() {
        let warned = message("Are you sure?", secure: false, isEncrypted: false)
        XCTAssertTrue(warned.hasSuffix("Are you sure?"))
        XCTAssertTrue(warned.localizedCaseInsensitiveContains("not encrypted"))
    }

    /// The question type is the peer's to choose, so it must not be able to
    /// decide whether the user is warned — a server asking for a password can
    /// label the question "ordinary" and would otherwise suppress the warning.
    func testServerSuppliedTypeCannotSuppressTheWarning() {
        let asPassword = message("Password:", secure: true, isEncrypted: false)
        let asOrdinary = message("Password:", secure: false, isEncrypted: false)
        XCTAssertEqual(asPassword, asOrdinary)
    }

    func testOrdinaryQuestionOverTLSIsNotWarnedAbout() {
        XCTAssertEqual(message("Are you sure?", secure: false, isEncrypted: true), "Are you sure?")
    }

    func testFallbackPromptStillCarriesTheWarning() {
        let warned = message(nil, secure: true, isEncrypted: false)
        XCTAssertTrue(warned.hasSuffix(message(nil)))
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
