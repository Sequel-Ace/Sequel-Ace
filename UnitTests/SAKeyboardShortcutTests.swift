//
//  SAKeyboardShortcutTests.swift
//  Unit Tests
//
//  Created as part of the modernization effort.
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import AppKit
import XCTest

final class SAKeyboardShortcutTests: XCTestCase {

    private let commandF = SAKeyboardShortcut.commandF

    private func matches(_ modifiers: NSEvent.ModifierFlags, _ characters: String?) -> Bool {
        commandF.matches(modifierFlags: modifiers, charactersIgnoringModifiers: characters)
    }

    // MARK: - The chord it is meant to match

    func testPlainCommandFMatches() {
        XCTAssertTrue(matches(.command, "f"))
    }

    func testCapsLockedCharacterMatches() {
        // charactersIgnoringModifiers honours Caps Lock, so the character arrives uppercased
        // even though no shift-like modifier is reported.
        XCTAssertTrue(matches([.command, .capsLock], "F"))
    }

    // MARK: - Modifier supersets belong to other shortcuts

    func testControlCommandFDoesNotMatch() {
        // ⌃⌘F is View → Enter Full Screen.
        XCTAssertFalse(matches([.command, .control], "f"))
    }

    func testOptionCommandFDoesNotMatch() {
        // ⌥⌘F is View → Filter Content.
        XCTAssertFalse(matches([.command, .option], "f"))
    }

    func testControlOptionCommandFDoesNotMatch() {
        // ⌃⌥⌘F is View → Filter Tables.
        XCTAssertFalse(matches([.command, .control, .option], "f"))
    }

    func testShiftCommandFDoesNotMatch() {
        XCTAssertFalse(matches([.command, .shift], "F"))
    }

    // MARK: - Insignificant modifiers are ignored

    func testFunctionAndNumericPadFlagsAreIgnored() {
        XCTAssertTrue(matches([.command, .function, .numericPad], "f"))
    }

    // MARK: - Other events pass through

    func testMissingCommandDoesNotMatch() {
        XCTAssertFalse(matches([], "f"))
        XCTAssertFalse(matches(.control, "f"))
    }

    func testDifferentCharacterDoesNotMatch() {
        XCTAssertFalse(matches(.command, "g"))
    }

    func testNilCharactersDoNotMatch() {
        XCTAssertFalse(matches(.command, nil))
    }

    func testEmptyCharactersDoNotMatch() {
        XCTAssertFalse(matches(.command, ""))
    }

    // MARK: - Initialisation

    func testInsignificantModifiersAreStrippedFromTheChord() {
        let shortcut = SAKeyboardShortcut(character: "f", modifiers: [.command, .capsLock])

        XCTAssertEqual(shortcut.modifiers, .command)
        XCTAssertTrue(shortcut.matches(modifierFlags: .command, charactersIgnoringModifiers: "f"))
    }

    func testMatchingAnNSEvent() throws {
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown,
                                                  location: .zero,
                                                  modifierFlags: .command,
                                                  timestamp: 0,
                                                  windowNumber: 0,
                                                  context: nil,
                                                  characters: "\u{06}",
                                                  charactersIgnoringModifiers: "f",
                                                  isARepeat: false,
                                                  keyCode: 3))

        XCTAssertTrue(commandF.matches(event))
    }
}
