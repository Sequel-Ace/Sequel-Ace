//
//  SAClaudeAppearanceChangeTests.swift
//  Unit Tests
//

import AppKit
import XCTest

final class SAClaudeAppearanceChangeTests: XCTestCase {

    private var suiteName = ""
    private var defaults: UserDefaults!
    private var centre: NotificationCenter!
    private var posted: [Set<String>] = []
    private var token: NSObjectProtocol?

    override func setUp() {
        super.setUp()
        suiteName = "SAClaudeAppearanceChangeTests." + UUID().uuidString
        defaults = UserDefaults(suiteName: suiteName)
        centre = NotificationCenter()
        posted = []
        token = centre.addObserver(forName: SAClaudeAppearanceChange.didChangeNotification, object: nil, queue: nil) { [weak self] note in
            XCTAssertTrue(Thread.isMainThread)
            self?.posted.append(note.userInfo?[SAClaudeAppearanceChange.changedKeysKey] as? Set<String> ?? ["<missing>"])
        }
    }

    override func tearDown() {
        if let token { centre.removeObserver(token) }
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        centre = nil
        super.tearDown()
    }

    private func newValue() -> Data { Data(UUID().uuidString.utf8) }

    // MARK: - Posting

    func testEveryWatchedKeyPostsWithThatKey() {
        let tracker = SAClaudeAppearanceChange.Tracker(defaults: defaults)
        for key in SAClaudeAppearanceChange.watchedKeys {
            posted = []
            defaults.set(newValue(), forKey: key)
            tracker.check(postingTo: centre)
            XCTAssertEqual(posted, [[key]], key)
        }
    }

    func testWindowFrameAndOtherAutosavesDoNotPost() {
        let tracker = SAClaudeAppearanceChange.Tracker(defaults: defaults)
        for key in ["NSWindow Frame MainWindow", "NSSplitView Subview Frames DbViewSplitter", "NSTableView Columns v2 SAProcessList",
                    "SPLastSQLFileEncoding", "QueryHistory"] {
            defaults.set(newValue(), forKey: key)
            tracker.check(postingTo: centre)
        }
        XCTAssertEqual(posted, [])
    }

    func testWritingTheSameValueAgainDoesNotPost() {
        let key = SAEditorThemeLoader.backgroundColourKey
        let value = newValue()
        defaults.set(value, forKey: key)
        let tracker = SAClaudeAppearanceChange.Tracker(defaults: defaults)
        defaults.set(value, forKey: key)
        tracker.check(postingTo: centre)
        defaults.set(Data(value), forKey: key)
        tracker.check(postingTo: centre)
        XCTAssertEqual(posted, [])
    }

    func testRemovingAWatchedKeyPosts() {
        defaults.set(newValue(), forKey: SAClaudeAccent.defaultsKey)
        let tracker = SAClaudeAppearanceChange.Tracker(defaults: defaults)
        defaults.removeObject(forKey: SAClaudeAccent.defaultsKey)
        tracker.check(postingTo: centre)
        XCTAssertEqual(posted, [[SAClaudeAccent.defaultsKey]])
    }

    func testAChangeIsReportedOnce() {
        let tracker = SAClaudeAppearanceChange.Tracker(defaults: defaults)
        defaults.set(newValue(), forKey: SAEditorThemeLoader.textColourKey)
        tracker.check(postingTo: centre)
        tracker.check(postingTo: centre)
        XCTAssertEqual(posted, [[SAEditorThemeLoader.textColourKey]])
    }

    func testBeforePostingSeesTheChangedKeysFirst() {
        let tracker = SAClaudeAppearanceChange.Tracker(defaults: defaults)
        var seen: [Set<String>] = []
        defaults.set(newValue(), forKey: SAClaudeAccent.defaultsKey)
        tracker.check(postingTo: centre) { changed in
            XCTAssertEqual(self.posted, [])
            seen.append(changed)
        }
        XCTAssertEqual(seen, [[SAClaudeAccent.defaultsKey]])
        XCTAssertEqual(posted, [[SAClaudeAccent.defaultsKey]])
    }

    func testABackgroundWritePostsOnTheMainThread() {
        let tracker = SAClaudeAppearanceChange.Tracker(defaults: defaults)
        let done = expectation(description: "posted")
        let observer = centre.addObserver(forName: SAClaudeAppearanceChange.didChangeNotification, object: nil, queue: nil) { _ in done.fulfill() }
        DispatchQueue.global().async {
            self.defaults.set(self.newValue(), forKey: "CustomQueryEditorFont")
            tracker.check(postingTo: self.centre)
        }
        wait(for: [done], timeout: 5)
        centre.removeObserver(observer)
        XCTAssertEqual(posted, [["CustomQueryEditorFont"]])
    }

    /// The app's monitor on `.standard`: a watched write reaches `addObserver` once, an autosave never does.
    func testTheMonitorPostsWatchedStandardWritesOnly() {
        let standard = UserDefaults.standard
        let key = SAClaudeQueryCopyAction.defaultsKey
        let frameKey = "NSWindow Frame SAClaudeAppearanceChangeTests"
        let saved = standard.object(forKey: key)
        var received: [Set<String>] = []
        let observer = SAClaudeAppearanceChange.addObserver { received.append($0) }
        defer {
            NotificationCenter.default.removeObserver(observer)
            if let saved { standard.set(saved, forKey: key) } else { standard.removeObject(forKey: key) }
            standard.removeObject(forKey: frameKey)
        }
        standard.set("{{0, 0}, {800, 600}}", forKey: frameKey)
        XCTAssertEqual(received, [])
        standard.set(Int.random(in: 100...999), forKey: key)
        XCTAssertEqual(received, [[key]])
        standard.set("{{40, 0}, {800, 600}}", forKey: frameKey)
        XCTAssertEqual(received, [[key]])
    }

    // MARK: - Keys and diff

    /// Every setting a Claude view reads live (see the task 3 inventory).
    func testWatchedKeysCoverTheClaudeLook() {
        let watched = Set(SAClaudeAppearanceChange.watchedKeys)
        let expected: [String] = [
            "CustomQueryEditorBackgroundColor", "CustomQueryEditorTextColor", "CustomQueryEditorCaretColor",
            "CustomQueryEditorHighlightQueryColor", "CustomQueryEditorSelectionColor", "CustomQueryEditorCommentColor",
            "CustomQueryEditorQuoteColor", "CustomQueryEditorSQLKeywordColor", "CustomQueryEditorBacktickColor",
            "CustomQueryEditorNumericColor", "CustomQueryEditorVariableColor",
            "ClaudeAccentColour", "ClaudeConnectionColourStyle", "DisplayConnectionColorInTitlebar",
            "fontSettings", "CustomQueryEditorFont",
            "ScriptConsoleUseCustomAppearance", "ScriptConsoleFont", "ScriptConsoleTextColor", "ScriptConsoleBackgroundColor",
            "ClaudeQueryCopyDefaultAction", "ConsoleEnableLogging",
            "QueryHistoryReplacesContent", "QueryFavoriteReplacesContent", "CustomQueryAutoIndent", "CustomQueryAutoPairCharacters",
            "CustomQueryAutoUppercaseKeywords", "CustomQueryAutoComplete", "CustomQueryUpdateAutoHelp",
        ]
        XCTAssertEqual(watched, Set(expected))
        XCTAssertEqual(SAClaudeAppearanceChange.watchedKeys.count, watched.count, "no duplicates")
    }

    func testChangedKeysAreTheSetChangedAndRemovedOnes() {
        let old: [String: NSObject] = ["a": NSNumber(value: 1), "b": "x" as NSString, "c": NSData()]
        let new: [String: NSObject] = ["a": NSNumber(value: 1), "b": "y" as NSString, "d": NSNumber(value: true)]
        XCTAssertEqual(SAClaudeAppearanceChange.changedKeys(from: old, to: new), ["b", "c", "d"])
        XCTAssertEqual(SAClaudeAppearanceChange.changedKeys(from: old, to: old), [])
        XCTAssertEqual(SAClaudeAppearanceChange.changedKeys(from: [:], to: [:]), [])
    }

    func testSnapshotReadsOnlyTheGivenPresentKeys() {
        defaults.set(3, forKey: "watched")
        defaults.set(4, forKey: "other")
        let snapshot = SAClaudeAppearanceChange.snapshot(of: defaults, keys: ["watched", "absent"])
        XCTAssertEqual(snapshot, ["watched": NSNumber(value: 3)])
    }

    // MARK: - Theme colours cache

    func testThemeColoursAreDecodedOncePerThemeData() {
        let red = NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
        let blue = NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)
        defaults.set(SAArchiving.archivedData(forColor: red), forKey: SAEditorThemeLoader.textColourKey)
        let first = SAClaudeThemeColours.from(defaults: defaults)
        let second = SAClaudeThemeColours.from(defaults: defaults)
        XCTAssertEqual(first.text.usingColorSpace(.sRGB), red)
        XCTAssertTrue(first.text === second.text, "unchanged theme data reuses the decoded colours")
        XCTAssertEqual(first, second)

        defaults.set(SAArchiving.archivedData(forColor: blue), forKey: SAEditorThemeLoader.textColourKey)
        let third = SAClaudeThemeColours.from(defaults: defaults)
        XCTAssertEqual(third.text.usingColorSpace(.sRGB), blue)
        XCTAssertEqual(third.keyword.usingColorSpace(.sRGB), blue, "fallbacks follow the new text colour")
    }
}
