//
//  SAEditorThemeAppearanceSettingsTests.swift
//  Unit Tests
//
//  The Theme Appearance section's model on a suite of its own, with a fake
//  "Unsaved Theme" prompt and a counting apply step (no alerts, no switcher).
//

import Combine
import XCTest

final class SAEditorThemeAppearanceSettingsTests: XCTestCase {

    private let suite = "SAEditorThemeAppearanceSettingsTests"
    private var defaults: UserDefaults!
    private var dir: URL!
    private var registered: SARegistrationDomainSnapshot!
    private var promptAnswer = true
    private var prompts = 0
    private var applies = 0
    private var cancellables: Set<AnyCancellable> = []

    private typealias S = SAEditorAppearanceThemeSwitcher

    override func setUpWithError() throws {
        registered = SARegistrationDomainSnapshot()
        UserDefaults().removePersistentDomain(forName: suite)
        defaults = UserDefaults(suiteName: suite)
        SAEditorDefaults.register(in: defaults)
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for name in ["Sequel Ace Light", "Sequel Ace Dark", "Nord"] {
            try Data().write(to: dir.appendingPathComponent(name + ".spTheme"))
        }
        promptAnswer = true
        prompts = 0
        applies = 0
    }

    override func tearDownWithError() throws {
        cancellables.removeAll()
        try? FileManager.default.removeItem(at: dir)
        UserDefaults().removePersistentDomain(forName: suite)
        registered.restore()
    }

    private func makeSettings() -> SAEditorThemeAppearanceSettings {
        SAEditorThemeAppearanceSettings(defaults: defaults, themesDirectory: dir.path,
                                        confirmDiscardUnsaved: { [unowned self] in self.prompts += 1; return self.promptAnswer },
                                        onThemeApplied: {},
                                        applyTheme: { [unowned self] in self.applies += 1 })
    }

    // MARK: - Match system appearance

    /// Verifies Cancel on the "Unsaved Theme" prompt keeps matching off and republishes, so the checkbox flips back.
    func testCancelOnTheUnsavedThemePromptFlipsTheToggleBack() {
        defaults.set(false, forKey: S.matchesAppearanceKey)
        let settings = makeSettings()
        promptAnswer = false
        let republished = expectation(description: "republished after the toggle wrote")
        settings.objectWillChange.sink { republished.fulfill() }.store(in: &cancellables)

        settings.matchesSetting = true

        wait(for: [republished], timeout: 1)
        XCTAssertEqual(prompts, 1)
        XCTAssertFalse(settings.matchesSetting)
        XCTAssertFalse(settings.matches)
        XCTAssertEqual(defaults.persistentDomain(forName: suite)?[S.matchesAppearanceKey] as? Bool, false)
        XCTAssertEqual(applies, 0, "nothing is loaded")
    }

    /// Verifies Proceed turns matching on and loads the theme for the current appearance.
    func testProceedOnTheUnsavedThemePromptApplies() {
        defaults.set(false, forKey: S.matchesAppearanceKey)
        let settings = makeSettings()
        promptAnswer = true

        settings.matchesSetting = true

        XCTAssertEqual(prompts, 1)
        XCTAssertTrue(settings.matchesSetting)
        XCTAssertTrue(defaults.bool(forKey: S.matchesAppearanceKey))
        XCTAssertEqual(applies, 1)
    }

    /// Verifies turning matching off asks nothing and loads nothing.
    func testTurningMatchingOffNeedsNoPrompt() {
        let settings = makeSettings()
        XCTAssertTrue(settings.matchesSetting, "registered default")
        settings.matchesSetting = false
        XCTAssertEqual(prompts, 0)
        XCTAssertEqual(applies, 0)
        XCTAssertFalse(defaults.bool(forKey: S.matchesAppearanceKey))
        XCTAssertFalse(settings.matches)
    }

    // MARK: - Picks

    /// Verifies Light/Dark picks are stored, applied, and read back by a new model (a reopened pane).
    func testPicksPersist() {
        let settings = makeSettings()
        XCTAssertEqual(settings.lightSetting, "Sequel Ace Light")
        XCTAssertEqual(settings.darkSetting, "Sequel Ace Dark")

        settings.lightSetting = "Nord"
        settings.darkSetting = "Default"

        XCTAssertEqual(applies, 2)
        XCTAssertEqual(defaults.persistentDomain(forName: suite)?[S.lightThemeKey] as? String, "Nord")
        XCTAssertEqual(defaults.persistentDomain(forName: suite)?[S.darkThemeKey] as? String, "Default")
        let reopened = makeSettings()
        XCTAssertEqual(reopened.lightSetting, "Nord")
        XCTAssertEqual(reopened.darkSetting, "Default")
    }

    /// Verifies a pick whose file is gone stays listed, shown as missing.
    func testAMissingPickIsListedAsMissing() {
        defaults.set("Gone", forKey: S.darkThemeKey)
        let settings = makeSettings()
        XCTAssertEqual(settings.entries(selected: settings.darkSetting).last, "Gone")
        XCTAssertNotEqual(settings.displayName("Gone"), "Gone")
        XCTAssertEqual(settings.displayName("Nord"), "Nord")
    }

    // MARK: - What the model observes

    /// Verifies a write to one of the three keys from elsewhere (the pane's manual pick, the switcher)
    /// updates the model.
    func testTheThreeKeysAreObserved() {
        let settings = makeSettings()
        defaults.set(false, forKey: S.matchesAppearanceKey)
        defaults.set("Nord", forKey: S.lightThemeKey)
        defaults.set("Default", forKey: S.darkThemeKey)
        XCTAssertFalse(settings.matches)
        XCTAssertEqual(settings.lightTheme, "Nord")
        XCTAssertEqual(settings.darkTheme, "Default")
    }

    /// Verifies the Themes folder is re-read only when asked (appear, theme-list change), not on defaults writes.
    func testTheThemesFolderIsReadOnlyWhenTheListChanges() throws {
        let settings = makeSettings()
        XCTAssertEqual(settings.themeNames, ["Default", "Nord", "Sequel Ace Dark", "Sequel Ace Light"])
        let published = expectation(description: "no change published")
        published.isInverted = true
        settings.objectWillChange.sink { published.fulfill() }.store(in: &cancellables)
        try Data().write(to: dir.appendingPathComponent("Monokai.spTheme"))

        defaults.set(Data([1]), forKey: SAEditorThemeLoader.backgroundColorKey)
        defaults.set("Monokai", forKey: SAEditorThemeLoader.themeNameKey)
        defaults.set(true, forKey: "SAEditorThemeAppearanceSettingsTests.unrelated")

        wait(for: [published], timeout: 0.2)
        XCTAssertFalse(settings.themeNames.contains("Monokai"), "unrelated writes do not rescan")
        cancellables.removeAll()

        S.themeListDidChange()
        let rescanned = expectation(description: "rescanned")
        DispatchQueue.main.async { rescanned.fulfill() }
        wait(for: [rescanned], timeout: 1)
        XCTAssertTrue(settings.themeNames.contains("Monokai"))
    }
}
