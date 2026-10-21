//
//  SAClaudeQueryRunActionTests.swift
//  Unit Tests
//
//  The Run split button remembers the last run action.
//

import XCTest

final class SAClaudeQueryRunActionTests: XCTestCase {

    private var defaults: UserDefaults!
    private let suite = "SAClaudeQueryRunActionTests"

    override func setUp() {
        super.setUp()
        UserDefaults().removePersistentDomain(forName: suite)
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: suite)
        defaults = nil
        super.tearDown()
    }

    private var state: (SAClaudeQueryRunAction, SAClaudeQueryRunAction, SAClaudeQueryRunAction, Bool) {
        (SAClaudeQueryRunDefault.primaryAction(in: defaults), SAClaudeQueryRunDefault.secondaryAction(in: defaults),
         SAClaudeQueryRunDefault.tertiaryAction(in: defaults), SAClaudeQueryRunDefault.showsTertiary(in: defaults))
    }

    /// Verifies a fresh install runs the current query, ⌥⌘R runs all, and no tertiary item shows.
    func testDefaultIsRunCurrent() {
        XCTAssertTrue(state == (.current, .all, .current, false))
    }

    /// Verifies the keys stay those SPCustomQuery and the settings use.
    func testKeys() {
        XCTAssertEqual(SAClaudeQueryRunDefault.runsAllKey, "QueryPrimaryControlRunsAll")
        XCTAssertEqual(SAClaudeQueryRunDefault.runsScriptKey, "ClaudeQueryPrimaryRunsScript")
    }

    /// Verifies running Run all makes it the button's, and Run current back again.
    func testRunningAllThenCurrentIsRemembered() {
        SAClaudeQueryRunDefault.remember(.all, in: defaults)
        XCTAssertTrue(state == (.all, .current, .all, false))
        SAClaudeQueryRunDefault.remember(.current, in: defaults)
        XCTAssertTrue(state == (.current, .all, .current, false))
    }

    /// Verifies running the script makes it the button's, keeps ⌥⌘R on the other of current/all, and offers the
    /// one the button showed before as the tertiary item.
    func testRunningTheScriptIsRemembered() {
        SAClaudeQueryRunDefault.remember(.script, in: defaults)
        XCTAssertTrue(state == (.script, .all, .current, true))
        SAClaudeQueryRunDefault.remember(.all, in: defaults)
        SAClaudeQueryRunDefault.remember(.script, in: defaults)
        XCTAssertTrue(state == (.script, .current, .all, true))
        // Running the tertiary (Run all) leaves the script.
        SAClaudeQueryRunDefault.remember(.all, in: defaults)
        XCTAssertTrue(state == (.all, .current, .all, false))
    }

    /// Verifies the choice survives a relaunch (a new defaults object on the same domain).
    func testRememberedAcrossLaunches() {
        SAClaudeQueryRunDefault.remember(.script, in: defaults)
        let relaunched = UserDefaults(suiteName: suite)!
        XCTAssertEqual(SAClaudeQueryRunDefault.primaryAction(in: relaunched), .script)
    }

    /// Verifies Switch Default flips Run current / Run all, and from the script goes to the other of the one the
    /// button showed before it.
    func testSwitchDefault() {
        SAClaudeQueryRunDefault.switchDefault(in: defaults)
        XCTAssertEqual(SAClaudeQueryRunDefault.primaryAction(in: defaults), .all)
        SAClaudeQueryRunDefault.switchDefault(in: defaults)
        XCTAssertEqual(SAClaudeQueryRunDefault.primaryAction(in: defaults), .current)
        SAClaudeQueryRunDefault.remember(.script, in: defaults)
        SAClaudeQueryRunDefault.switchDefault(in: defaults)
        XCTAssertTrue(state == (.all, .current, .all, false))
    }

    /// Verifies the script label is localized with an English value.
    func testScriptButtonTitle() {
        XCTAssertEqual(SAClaudeQueryRunDefault.scriptButtonTitle, "Run as script")
    }
}
