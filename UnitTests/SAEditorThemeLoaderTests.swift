//
//  SAEditorThemeLoaderTests.swift
//  Unit Tests
//

import AppKit
import XCTest

final class SAEditorThemeLoaderTests: XCTestCase {

    private var defaults: UserDefaults!
    private let suite = "SAEditorThemeLoaderTests"
    private var registered: SARegistrationDomainSnapshot!

    override func setUp() {
        super.setUp()
        registered = SARegistrationDomainSnapshot()
        UserDefaults().removePersistentDomain(forName: suite)
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: suite)
        registered.restore()
        super.tearDown()
    }

    private func components(_ colour: NSColor?) -> [Int] {
        guard let c = colour?.usingColorSpace(.genericRGB) else { return [] }
        return [c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent].map { Int(($0 * 255).rounded()) }
    }

    private func stored(_ key: String) -> [Int] {
        components(SAArchiving.color(from: defaults.data(forKey: key)))
    }

    /// Verifies the hex forms the old +[NSColor colorWithRGBHexString:] accepted.
    func testHexFormsMatchTheOldParser() {
        XCTAssertEqual(components(SAEditorThemeLoader.colour(fromHex: "#151515")), [21, 21, 21, 255])
        XCTAssertEqual(components(SAEditorThemeLoader.colour(fromHex: "F0EFEC")), [240, 239, 236, 255])
        XCTAssertEqual(components(SAEditorThemeLoader.colour(fromHex: "#fe3")), [255, 238, 51, 255])
        XCTAssertEqual(components(SAEditorThemeLoader.colour(fromHex: "#ffee3380")), [255, 238, 51, 128])
        XCTAssertEqual(components(SAEditorThemeLoader.colour(fromHex: "#151515zz")), [21, 21, 21, 255], "scanning stops at the first non-hex character")
        // The old NSScanner skipped leading whitespace/newlines, but only after the '#' check on the raw string.
        XCTAssertEqual(components(SAEditorThemeLoader.colour(fromHex: " 151515")), [21, 21, 21, 255])
        XCTAssertEqual(components(SAEditorThemeLoader.colour(fromHex: "# 151515")), [21, 21, 21, 255])
        XCTAssertEqual(components(SAEditorThemeLoader.colour(fromHex: "#\t151515")), [21, 21, 21, 255])
        XCTAssertEqual(components(SAEditorThemeLoader.colour(fromHex: "#\n151515")), [21, 21, 21, 255])
        XCTAssertEqual(components(SAEditorThemeLoader.colour(fromHex: "\n\t fe3")), [255, 238, 51, 255])
        XCTAssertNil(SAEditorThemeLoader.colour(fromHex: " #151515"), "a space before the '#' was nil in the old parser")
        XCTAssertNil(SAEditorThemeLoader.colour(fromHex: "##151515"))
        XCTAssertNil(SAEditorThemeLoader.colour(fromHex: ""))
        XCTAssertNil(SAEditorThemeLoader.colour(fromHex: "#1234"))
        XCTAssertNil(SAEditorThemeLoader.colour(fromHex: "zz"))
        XCTAssertEqual(SAEditorThemeLoader.colour(fromHex: "#151515")?.colorSpace, NSColorSpace.genericRGB, "calibrated RGB, like the old parser")
    }

    private var sampleTheme: [String: Any] {
        ["settings": [
            ["settings": ["background": "#151515", "caret": "#D97757", "foreground": "#F0EFEC", "lineHighlight": "#1E1E1D", "selection": "#383835"]],
            ["name": "Comment", "settings": ["foreground": "#898781"]],
            ["name": "String", "settings": ["foreground": "#55BF50"]],
            ["name": "Keyword", "settings": ["foreground": "#6DA7EC"]],
            ["name": "User-defined constant", "settings": ["foreground": "#F4ABAB"]],
            ["name": "Number", "settings": ["foreground": "#EC835A"]],
            ["name": "Variable", "settings": ["foreground": "#A096EB"]],
        ]]
    }

    /// Verifies a full theme writes all 11 settings with the old key mapping.
    func testFullThemeWritesAllElevenSettings() {
        XCTAssertEqual(SAEditorThemeLoader.writeColours(fromThemePlist: sampleTheme, into: defaults), 11)
        XCTAssertEqual(stored("CustomQueryEditorBackgroundColor"), [21, 21, 21, 255])
        XCTAssertEqual(stored("CustomQueryEditorCaretColor"), [217, 119, 87, 255])
        XCTAssertEqual(stored("CustomQueryEditorTextColor"), [240, 239, 236, 255])
        XCTAssertEqual(stored("CustomQueryEditorHighlightQueryColor"), [30, 30, 29, 255])
        XCTAssertEqual(stored("CustomQueryEditorSelectionColor"), [56, 56, 53, 255])
        XCTAssertEqual(stored("CustomQueryEditorCommentColor"), [137, 135, 129, 255])
        XCTAssertEqual(stored("CustomQueryEditorQuoteColor"), [85, 191, 80, 255])
        XCTAssertEqual(stored("CustomQueryEditorSQLKeywordColor"), [109, 167, 236, 255])
        XCTAssertEqual(stored("CustomQueryEditorBacktickColor"), [244, 171, 171, 255])
        XCTAssertEqual(stored("CustomQueryEditorNumericColor"), [236, 131, 90, 255])
        XCTAssertEqual(stored("CustomQueryEditorVariableColor"), [160, 150, 235, 255])
        XCTAssertEqual(SAEditorThemeLoader.colourKeys.count, 11)
    }

    /// Verifies the old parser's tolerance: non-dictionary entries skipped, unknown
    /// scopes ignored, bad hex skipped, later duplicates win, empty or wrong roots give nothing.
    func testThemePlistEdgeCases() {
        let theme: [String: Any] = ["settings": [
            ["settings": ["background": "#000000", "caret": "nothex"]],
            "not a dictionary",
            ["name": "Keyword", "settings": ["foreground": "#111111"]],
            ["name": "Unknown scope", "settings": ["foreground": "#222222"]],
            ["name": "Keyword", "settings": ["foreground": "#333333"]],
            ["name": "Number"],
        ]]
        let colours = SAEditorThemeLoader.colours(fromThemePlist: theme)
        XCTAssertEqual(Set(colours.keys), ["CustomQueryEditorBackgroundColor", "CustomQueryEditorSQLKeywordColor"])
        XCTAssertEqual(components(colours["CustomQueryEditorSQLKeywordColor"]), [51, 51, 51, 255])
        XCTAssertTrue(SAEditorThemeLoader.colours(fromThemePlist: ["settings": []]).isEmpty)
        XCTAssertTrue(SAEditorThemeLoader.colours(fromThemePlist: ["nope": 1]).isEmpty)
        XCTAssertTrue(SAEditorThemeLoader.colours(fromThemePlist: "string").isEmpty)
        // settings[0] that is not a dictionary does not shift the scope entries
        let shifted: [String: Any] = ["settings": ["x", ["name": "Comment", "settings": ["foreground": "#444444"]]]]
        XCTAssertEqual(Set(SAEditorThemeLoader.colours(fromThemePlist: shifted).keys), ["CustomQueryEditorCommentColor"])
    }

    /// Verifies file loading: count, unreadable file, file with no colours.
    func testLoadThemeAtPath() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let good = dir.appendingPathComponent("Good.spTheme")
        try PropertyListSerialization.data(fromPropertyList: sampleTheme, format: .xml, options: 0).write(to: good)
        let empty = dir.appendingPathComponent("Empty.spTheme")
        try PropertyListSerialization.data(fromPropertyList: ["settings": []], format: .xml, options: 0).write(to: empty)

        XCTAssertEqual(SAEditorThemeLoader.loadTheme(atPath: good.path, into: defaults), 11)
        XCTAssertEqual(SAEditorThemeLoader.loadTheme(atPath: empty.path, into: defaults), 0)
        XCTAssertEqual(SAEditorThemeLoader.loadTheme(atPath: dir.appendingPathComponent("Missing.spTheme").path, into: defaults), -1)
    }

    /// Verifies "Default" copies the registered colours, as -setDefaultColors: does.
    func testLoadDefaultColoursCopiesRegisteredValues() {
        let registered = SAArchiving.archivedData(forColor: NSColor(calibratedRed: 0.5, green: 0.25, blue: 0, alpha: 1))!
        defaults.register(defaults: ["CustomQueryEditorTextColor": registered])
        defaults.set(SAArchiving.archivedData(forColor: .red), forKey: "CustomQueryEditorTextColor")
        SAEditorThemeLoader.loadDefaultColours(into: defaults)
        XCTAssertEqual(stored("CustomQueryEditorTextColor"), [128, 64, 0, 255])
    }

    /// Verifies byte-for-byte colour precision: the old parser divided in 32-bit float.
    func testComponentsUseFloatPrecisionLikeTheOldParser() {
        let parsed = SAEditorThemeLoader.colour(fromHex: "#151515")!
        let expected = CGFloat(Float(0x15) / 255)
        XCTAssertEqual(parsed.redComponent, expected)
        XCTAssertEqual(parsed.greenComponent, expected)
        XCTAssertEqual(parsed.blueComponent, expected)
        XCTAssertNotEqual(parsed.redComponent, CGFloat(0x15) / 255, "a Double division would differ")

        // Archiving keeps ~11 significant digits, which still separates Float from Double division.
        let archived = SAArchiving.color(from: SAArchiving.archivedData(forColor: parsed))!
        let reference = SAArchiving.color(from: SAArchiving.archivedData(forColor: NSColor(calibratedRed: expected, green: expected, blue: expected, alpha: 1)))!
        let doubleDivision = CGFloat(0x15) / 255
        let doubleReference = SAArchiving.color(from: SAArchiving.archivedData(forColor: NSColor(calibratedRed: doubleDivision, green: doubleDivision, blue: doubleDivision, alpha: 1)))!
        XCTAssertEqual(archived.redComponent, reference.redComponent)
        XCTAssertEqual(archived.blueComponent, reference.blueComponent)
        XCTAssertNotEqual(archived.redComponent, doubleReference.redComponent)

        let short = SAEditorThemeLoader.colour(fromHex: "#fe3")!
        XCTAssertEqual(short.greenComponent, CGFloat(Float(0xEE) / 255))
        let withAlpha = SAEditorThemeLoader.colour(fromHex: "#ffee3380")!
        XCTAssertEqual(withAlpha.alphaComponent, CGFloat(Float(0x80) / 255))
        XCTAssertEqual(withAlpha.blueComponent, CGFloat(Float(0x33) / 255))
    }

    /// Verifies the bundled themes load completely with the exact values in their files.
    func testBundledThemesLoadWithExactValues() throws {
        let themes = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("SharedSupport/Default Themes")

        XCTAssertEqual(SAEditorThemeLoader.loadTheme(atPath: themes.appendingPathComponent("Nord.spTheme").path, into: defaults), 11)
        XCTAssertEqual(stored("CustomQueryEditorBackgroundColor"), [34, 38, 49, 255])   // #222631
        XCTAssertEqual(stored("CustomQueryEditorTextColor"), [231, 234, 241, 255])      // #E7EAF1
        XCTAssertEqual(stored("CustomQueryEditorCommentColor"), [59, 67, 87, 255])      // #3B4357

        XCTAssertEqual(SAEditorThemeLoader.loadTheme(atPath: themes.appendingPathComponent("Monokai.spTheme").path, into: defaults), 11)
        XCTAssertEqual(stored("CustomQueryEditorBackgroundColor"), [39, 40, 34, 255])   // #272822
        XCTAssertEqual(stored("CustomQueryEditorSQLKeywordColor"), [249, 38, 114, 255]) // #F92672
        XCTAssertEqual(stored("CustomQueryEditorVariableColor"), [79, 173, 236, 255])  // #4FADEC
    }
}
