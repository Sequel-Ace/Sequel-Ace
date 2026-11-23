//
//  SAClaudeEditorOptionTests.swift
//  Unit Tests
//

import XCTest

final class SAClaudeEditorOptionTests: XCTestCase {

    func testEveryOptionIsInExactlyOneSection() {
        let listed = SAClaudeEditorOptionSection.all.flatMap(\.options)
        XCTAssertEqual(listed.count, SAClaudeEditorOption.allCases.count)
        for option in SAClaudeEditorOption.allCases {
            XCTAssertEqual(listed.filter { $0 == option }.count, 1, "\(option)")
        }
        XCTAssertEqual(SAClaudeEditorOptionSection.all.map(\.title), ["History", "Editing", "Completion", "Typing"])
    }

    func testMenuItemsMapToOptions() {
        // The ⋯ menu in DBView.xib (menu 7232): tags, value bindings, actions.
        XCTAssertEqual(SAClaudeEditorOption.option(tag: 3, boundDefaultsKey: nil, hasAction: true), .previousHistory)
        XCTAssertEqual(SAClaudeEditorOption.option(tag: 4, boundDefaultsKey: nil, hasAction: true), .nextHistory)
        XCTAssertEqual(SAClaudeEditorOption.option(tag: 0, boundDefaultsKey: "QueryHistoryReplacesContent", hasAction: false), .historyReplacesContent)
        XCTAssertEqual(SAClaudeEditorOption.option(tag: 0, boundDefaultsKey: "QueryFavoriteReplacesContent", hasAction: false), .favoriteReplacesContent)
        XCTAssertEqual(SAClaudeEditorOption.option(tag: 6, boundDefaultsKey: nil, hasAction: true), .shiftRight)
        XCTAssertEqual(SAClaudeEditorOption.option(tag: 7, boundDefaultsKey: nil, hasAction: true), .shiftLeft)
        XCTAssertEqual(SAClaudeEditorOption.option(tag: 11, boundDefaultsKey: nil, hasAction: true), .commentLine)
        XCTAssertEqual(SAClaudeEditorOption.option(tag: 12, boundDefaultsKey: nil, hasAction: true), .commentQuery)
        XCTAssertEqual(SAClaudeEditorOption.option(tag: 8, boundDefaultsKey: nil, hasAction: true), .completionList)
        XCTAssertEqual(SAClaudeEditorOption.option(tag: 8000, boundDefaultsKey: nil, hasAction: true), .completeDatabases)
        XCTAssertEqual(SAClaudeEditorOption.option(tag: 8001, boundDefaultsKey: nil, hasAction: true), .completeTables)
        XCTAssertEqual(SAClaudeEditorOption.option(tag: 8002, boundDefaultsKey: nil, hasAction: true), .completeFields)
        XCTAssertEqual(SAClaudeEditorOption.option(tag: 9, boundDefaultsKey: "CustomQueryAutoIndent", hasAction: true), .autoIndent)
        XCTAssertEqual(SAClaudeEditorOption.option(tag: 10, boundDefaultsKey: "CustomQueryAutoPairCharacters", hasAction: true), .autoPair)
        XCTAssertEqual(SAClaudeEditorOption.option(tag: 0, boundDefaultsKey: "CustomQueryAutoUppercaseKeywords", hasAction: true), .autoUppercase)
        XCTAssertEqual(SAClaudeEditorOption.option(tag: 0, boundDefaultsKey: "CustomQueryAutoComplete", hasAction: false), .autoComplete)
        XCTAssertEqual(SAClaudeEditorOption.option(tag: 0, boundDefaultsKey: "CustomQueryUpdateAutoHelp", hasAction: true), .autoHelp)
        XCTAssertEqual(SAClaudeEditorOption.option(tag: 0, boundDefaultsKey: nil, hasAction: true), .editorFont)
        // The hidden title item 0 and the "Show Completion List" parent have neither.
        XCTAssertNil(SAClaudeEditorOption.option(tag: 0, boundDefaultsKey: nil, hasAction: false))
        XCTAssertNil(SAClaudeEditorOption.option(tag: 0, boundDefaultsKey: "SomethingElse", hasAction: false))
    }

    func testSwitchesMapToDefaultsKeys() {
        let switches = SAClaudeEditorOption.allCases.filter(\.isSwitch)
        XCTAssertEqual(switches, [.historyReplacesContent, .favoriteReplacesContent, .autoIndent, .autoPair, .autoUppercase, .autoComplete, .autoHelp])
        XCTAssertEqual(switches.compactMap(\.defaultsKey), ["QueryHistoryReplacesContent", "QueryFavoriteReplacesContent", "CustomQueryAutoIndent",
                                                            "CustomQueryAutoPairCharacters", "CustomQueryAutoUppercaseKeywords",
                                                            "CustomQueryAutoComplete", "CustomQueryUpdateAutoHelp"])
        XCTAssertTrue(SAClaudeEditorOption.allCases.filter { !$0.isSwitch }.allSatisfy { $0.defaultsKey == nil && $0.closesPopover })
        XCTAssertTrue(switches.allSatisfy { !$0.closesPopover })
    }

    func testTitlesAreSentenceCase() {
        XCTAssertEqual(SAClaudeEditorOption.historyReplacesContent.title, "History replaces editor content")
        XCTAssertEqual(SAClaudeEditorOption.autoUppercase.title, "Auto-uppercase keywords")
        XCTAssertEqual(SAClaudeEditorOption.completeDatabases.title, "Databases")
        XCTAssertEqual(SAClaudeEditorOption.editorFont.title, "Editor font")
    }
}
