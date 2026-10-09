//
//  SAScriptConsoleAppearanceTests.swift
//  Unit Tests
//

import AppKit
import XCTest

final class SAScriptConsoleAppearanceTests: XCTestCase {

    private var suiteName = ""
    private var defaults: UserDefaults!

    private typealias Appearance = SAScriptConsoleAppearance

    private let editorFont = NSFont(name: "Menlo-Regular", size: 13) ?? .userFixedPitchFont(ofSize: 13)!
    private let editorText = NSColor(srgbRed: 0.1, green: 0.2, blue: 0.3, alpha: 1)
    private let editorBackground = NSColor(srgbRed: 0.9, green: 0.8, blue: 0.7, alpha: 1)
    private let customFont = NSFont(name: "Courier", size: 15) ?? .userFixedPitchFont(ofSize: 15)!
    private let customText = NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
    private let customBackground = NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)

    override func setUp() {
        super.setUp()
        suiteName = "SAScriptConsoleAppearanceTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func storeEditorValues() {
        defaults.set(SAArchiving.archivedData(forFont: editorFont), forKey: Appearance.editorFontKey)
        defaults.set(SAArchiving.archivedData(forColor: editorText), forKey: Appearance.editorTextColorKey)
        defaults.set(SAArchiving.archivedData(forColor: editorBackground), forKey: Appearance.editorBackgroundColorKey)
    }

    private func storeCustomValues() {
        defaults.set(SAArchiving.archivedData(forFont: customFont), forKey: Appearance.customFontKey)
        defaults.set(SAArchiving.archivedData(forColor: customText), forKey: Appearance.customTextColorKey)
        defaults.set(SAArchiving.archivedData(forColor: customBackground), forKey: Appearance.customBackgroundColorKey)
    }

    private func assertFont(_ font: NSFont?, equals expected: NSFont, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(font?.fontName, expected.fontName, file: file, line: line)
        XCTAssertEqual(font?.pointSize, expected.pointSize, file: file, line: line)
    }

    private func assertColor(_ color: NSColor?, equals expected: NSColor, file: StaticString = #filePath, line: UInt = #line) {
        guard let actual = color?.usingColorSpace(.sRGB), let wanted = expected.usingColorSpace(.sRGB) else {
            return XCTFail("colour not convertible to sRGB: \(String(describing: color))", file: file, line: line)
        }
        XCTAssertEqual(actual.redComponent, wanted.redComponent, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actual.greenComponent, wanted.greenComponent, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actual.blueComponent, wanted.blueComponent, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actual.alphaComponent, wanted.alphaComponent, accuracy: 0.001, file: file, line: line)
    }

    // MARK: - resolve

    func testOverrideOffReturnsEditorValues() {
        storeEditorValues()
        storeCustomValues()
        defaults.set(false, forKey: Appearance.useCustomKey)

        let appearance = Appearance.resolve(from: defaults)

        assertFont(appearance.font, equals: editorFont)
        assertColor(appearance.textColor, equals: editorText)
        assertColor(appearance.backgroundColor, equals: editorBackground)
    }

    func testOverrideOnReturnsCustomValues() {
        storeEditorValues()
        storeCustomValues()
        defaults.set(true, forKey: Appearance.useCustomKey)

        let appearance = Appearance.resolve(from: defaults)

        assertFont(appearance.font, equals: customFont)
        assertColor(appearance.textColor, equals: customText)
        assertColor(appearance.backgroundColor, equals: customBackground)
    }

    func testOverrideOnMissingCustomValueFallsBackToEditorValue() {
        storeEditorValues()
        storeCustomValues()
        defaults.removeObject(forKey: Appearance.customTextColorKey)
        defaults.set(Data([0x00, 0x01, 0x02]), forKey: Appearance.customFontKey)
        defaults.set(true, forKey: Appearance.useCustomKey)

        let appearance = Appearance.resolve(from: defaults)

        assertFont(appearance.font, equals: editorFont)
        assertColor(appearance.textColor, equals: editorText)
        assertColor(appearance.backgroundColor, equals: customBackground)
    }

    func testMissingOrCorruptEditorDataFallsBackToDefaults() {
        defaults.set(Data([0xDE, 0xAD, 0xBE, 0xEF]), forKey: Appearance.editorFontKey)
        defaults.set(Data([0x00]), forKey: Appearance.editorTextColorKey)
        // Background key left missing.

        let appearance = Appearance.resolve(from: defaults)

        assertFont(appearance.font, equals: .monospacedSystemFont(ofSize: 11, weight: .regular))
        XCTAssertEqual(appearance.textColor, NSColor.textColor)
        XCTAssertEqual(appearance.backgroundColor, NSColor.textBackgroundColor)
    }

    func testResolveIsEquatableForIdenticalDefaults() {
        storeEditorValues()
        XCTAssertEqual(Appearance.resolve(from: defaults), Appearance.resolve(from: defaults))
    }

    // MARK: - setUseCustom / copyEditorValuesToCustom

    func testFirstEnableSeedsCustomKeysFromEditorValues() {
        storeEditorValues()

        Appearance.setUseCustom(true, in: defaults)

        XCTAssertTrue(defaults.bool(forKey: Appearance.useCustomKey))
        assertFont(SAArchiving.font(from: defaults.data(forKey: Appearance.customFontKey)), equals: editorFont)
        assertColor(SAArchiving.color(from: defaults.data(forKey: Appearance.customTextColorKey)), equals: editorText)
        assertColor(SAArchiving.color(from: defaults.data(forKey: Appearance.customBackgroundColorKey)), equals: editorBackground)
    }

    func testSecondEnableDoesNotOverwriteExistingCustomValues() {
        storeEditorValues()
        Appearance.setUseCustom(true, in: defaults)
        storeCustomValues()
        Appearance.setUseCustom(false, in: defaults)
        XCTAssertFalse(defaults.bool(forKey: Appearance.useCustomKey))

        Appearance.setUseCustom(true, in: defaults)

        let appearance = Appearance.resolve(from: defaults)
        assertFont(appearance.font, equals: customFont)
        assertColor(appearance.textColor, equals: customText)
        assertColor(appearance.backgroundColor, equals: customBackground)
    }

    func testCopyEditorValuesToCustomOverwritesCustomValues() {
        storeEditorValues()
        storeCustomValues()

        Appearance.copyEditorValuesToCustom(in: defaults)

        assertFont(SAArchiving.font(from: defaults.data(forKey: Appearance.customFontKey)), equals: editorFont)
        assertColor(SAArchiving.color(from: defaults.data(forKey: Appearance.customTextColorKey)), equals: editorText)
        assertColor(SAArchiving.color(from: defaults.data(forKey: Appearance.customBackgroundColorKey)), equals: editorBackground)
    }

    // MARK: - Font panel

    func testApplyFontChangeConvertsCurrentCustomFontAndSavesIt() {
        storeEditorValues()
        storeCustomValues()
        defaults.set(true, forKey: Appearance.useCustomKey)
        var converted: NSFont?

        SAScriptConsoleFontPanel.applyFontChange(in: defaults) { font in
            converted = font
            return NSFontManager.shared.convert(font, toSize: 20)
        }

        assertFont(converted, equals: customFont)
        let saved = SAArchiving.font(from: defaults.data(forKey: Appearance.customFontKey))
        XCTAssertEqual(saved?.fontName, customFont.fontName)
        XCTAssertEqual(saved?.pointSize, 20)
    }
}
