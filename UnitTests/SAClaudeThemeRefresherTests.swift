//
//  SAClaudeThemeRefresherTests.swift
//  Unit Tests
//

import AppKit
import XCTest

final class SAClaudeThemeRefresherTests: XCTestCase {

    private let suite = "SAClaudeThemeRefresherTests"
    private var defaults: UserDefaults!
    private var registered: SARegistrationDomainSnapshot!
    private var root: URL!
    private var bundled: URL!
    private var installed: URL!

    override func setUpWithError() throws {
        registered = SARegistrationDomainSnapshot()
        UserDefaults().removePersistentDomain(forName: suite)
        defaults = UserDefaults(suiteName: suite)
        root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("SAClaudeThemeRefresherTests-\(UUID().uuidString)")
        bundled = root.appendingPathComponent("bundled")
        installed = root.appendingPathComponent("installed")
        try FileManager.default.createDirectory(at: bundled, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: installed, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        UserDefaults().removePersistentDomain(forName: suite)
        registered.restore()
        try? FileManager.default.removeItem(at: root)
    }

    /// A minimal theme whose background is the given hex and whose other colours are fixed.
    private func themeData(background: String) -> Data {
        let plist: [String: Any] = ["name": "T", "settings": [
            ["settings": ["background": background, "caret": "#112233", "foreground": "#445566",
                          "lineHighlight": "#778899", "selection": "#AABBCC"]],
            ["name": "Comment", "settings": ["foreground": "#010203"]],
        ]]
        return try! PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    }

    private func write(_ data: Data, _ name: String, in dir: URL) throws {
        try data.write(to: dir.appendingPathComponent(name + ".spTheme"))
    }

    private func read(_ name: String, in dir: URL) -> Data? {
        try? Data(contentsOf: dir.appendingPathComponent(name + ".spTheme"))
    }

    private func refresh() -> [String] {
        SAClaudeThemeRefresher.refreshInstalledThemes(from: bundled.path, to: installed.path, defaults: defaults)
    }

    private func modificationDate(_ name: String) -> Date? {
        try? FileManager.default.attributesOfItem(atPath: installed.appendingPathComponent(name + ".spTheme").path)[.modificationDate] as? Date
    }

    /// Verifies a differing installed copy is replaced by the bundled bytes.
    func testDifferingInstalledThemeIsOverwritten() throws {
        let new = themeData(background: "#FFFFFF"), old = themeData(background: "#000000")
        try write(new, "Claude Dark", in: bundled)
        try write(old, "Claude Dark", in: installed)
        XCTAssertEqual(refresh(), ["Claude Dark"])
        XCTAssertEqual(read("Claude Dark", in: installed), new)
    }

    /// Verifies an identical installed copy is left alone and not reported.
    func testIdenticalInstalledThemeIsNotRewritten() throws {
        let data = themeData(background: "#FFFFFF")
        try write(data, "Claude Light", in: bundled)
        try write(data, "Claude Light", in: installed)
        let past = Date(timeIntervalSince1970: 1_000_000)
        try FileManager.default.setAttributes([.modificationDate: past], ofItemAtPath: installed.appendingPathComponent("Claude Light.spTheme").path)
        XCTAssertEqual(refresh(), [])
        XCTAssertEqual(modificationDate("Claude Light"), past)
    }

    /// Verifies a theme that isn't installed is not created (the installer does that).
    func testMissingInstalledThemeIsNotCreated() throws {
        try write(themeData(background: "#FFFFFF"), "Claude Dark", in: bundled)
        XCTAssertEqual(refresh(), [])
        XCTAssertNil(read("Claude Dark", in: installed))
    }

    /// Verifies an installed theme with no bundled counterpart is left alone.
    func testMissingBundledThemeIsSkipped() throws {
        let old = themeData(background: "#000000")
        try write(old, "Claude Dark", in: installed)
        XCTAssertEqual(refresh(), [])
        XCTAssertEqual(read("Claude Dark", in: installed), old)
    }

    /// Verifies refreshing the current theme reloads the editor colours from the new file.
    func testRefreshingTheCurrentThemeReloadsColours() throws {
        let old = themeData(background: "#000000"), new = themeData(background: "#FFFFFF")
        try write(new, "Claude Dark", in: bundled)
        try write(old, "Claude Dark", in: installed)
        XCTAssertEqual(SAEditorThemeLoader.loadTheme(atPath: installed.appendingPathComponent("Claude Dark.spTheme").path, into: defaults), 6)
        defaults.set("claude dark", forKey: SAEditorThemeLoader.themeNameKey)
        let before = defaults.data(forKey: SAEditorThemeLoader.backgroundColourKey)
        XCTAssertEqual(refresh(), ["Claude Dark"])
        let after = defaults.data(forKey: SAEditorThemeLoader.backgroundColourKey)
        XCTAssertNotEqual(before, after)
        XCTAssertEqual(after, SAArchiving.archivedData(forColor: SAEditorThemeLoader.colour(fromHex: "#FFFFFF")!))
    }

    /// Verifies refreshing a theme that isn't current leaves the colour settings alone.
    func testRefreshingANonCurrentThemeLeavesColoursAlone() throws {
        try write(themeData(background: "#FFFFFF"), "Claude Dark", in: bundled)
        try write(themeData(background: "#000000"), "Claude Dark", in: installed)
        defaults.set("Claude Light", forKey: SAEditorThemeLoader.themeNameKey)
        XCTAssertEqual(refresh(), ["Claude Dark"])
        XCTAssertNil(defaults.data(forKey: SAEditorThemeLoader.backgroundColourKey))
        XCTAssertEqual(defaults.string(forKey: SAEditorThemeLoader.themeNameKey), "Claude Light")
    }

    /// Verifies other theme files in the installed directory are never touched.
    func testOtherThemeFilesAreUntouched() throws {
        let mine = themeData(background: "#123456"), bundledOther = themeData(background: "#654321")
        try write(themeData(background: "#FFFFFF"), "Claude Dark", in: bundled)
        try write(themeData(background: "#000000"), "Claude Dark", in: installed)
        try write(bundledOther, "Solarized", in: bundled)
        try write(mine, "Solarized", in: installed)
        try write(mine, "My Theme", in: installed)
        XCTAssertEqual(refresh(), ["Claude Dark"])
        XCTAssertEqual(read("Solarized", in: installed), mine)
        XCTAssertEqual(read("My Theme", in: installed), mine)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: installed.path).sorted(),
                       ["Claude Dark.spTheme", "My Theme.spTheme", "Solarized.spTheme"])
    }
}
