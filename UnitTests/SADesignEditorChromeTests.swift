//
//  SADesignEditorChromeTests.swift
//  Unit Tests
//

import AppKit
import XCTest

final class SADesignEditorChromeTests: XCTestCase {

    /// Verifies shortcut hints like the menu shows them.
    func testShortcutString() {
        XCTAssertEqual(SADesignEditorChrome.shortcutString(keyEquivalent: "r", modifiers: .command), "⌘R")
        XCTAssertEqual(SADesignEditorChrome.shortcutString(keyEquivalent: "r", modifiers: [.command, .option]), "⌥⌘R")
        XCTAssertEqual(SADesignEditorChrome.shortcutString(keyEquivalent: "r", modifiers: [.command, .option, .shift, .control]), "⌃⌥⇧⌘R")
        XCTAssertEqual(SADesignEditorChrome.shortcutString(keyEquivalent: "", modifiers: .command), "")
    }

    /// Verifies an uppercase letter key equivalent shows Shift once, and digits, symbols and lowercase letters do not.
    func testUppercaseLetterImpliesShift() {
        XCTAssertEqual(SADesignEditorChrome.shortcutString(keyEquivalent: "D", modifiers: .command), "⇧⌘D")
        XCTAssertEqual(SADesignEditorChrome.shortcutString(keyEquivalent: "D", modifiers: [.command, .shift]), "⇧⌘D")
        XCTAssertEqual(SADesignEditorChrome.shortcutString(keyEquivalent: "d", modifiers: .command), "⌘D")
        XCTAssertEqual(SADesignEditorChrome.shortcutString(keyEquivalent: "1", modifiers: .command), "⌘1")
        XCTAssertEqual(SADesignEditorChrome.shortcutString(keyEquivalent: "[", modifiers: .command), "⌘[")
        XCTAssertEqual(SADesignEditorChrome.shortcutString(keyEquivalent: "Z", modifiers: [.command, .option]), "⌥⇧⌘Z")
    }
}
