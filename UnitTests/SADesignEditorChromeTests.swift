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
}
