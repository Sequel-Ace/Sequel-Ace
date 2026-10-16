//
//  SASSHAgentRelayInstallerTests.swift
//  Unit Tests
//
//  Created by the Sequel Ace team on October 10, 2026.
//  Copyright (c) 2026 Sequel-Ace. All rights reserved.
//

import XCTest

/// Helper installation into a stand-in Application Scripts folder.
final class SASSHAgentRelayInstallerTests: XCTestCase {

    private var root: URL!
    private var scripts: URL!
    private var bundledScript: URL!
    private var bundledAllowlist: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("sa-installer-\(UUID().uuidString)")
        scripts = root.appendingPathComponent("Application Scripts/com.example.app")
        try FileManager.default.createDirectory(at: scripts, withIntermediateDirectories: true)
        bundledScript = root.appendingPathComponent("bundled.zsh")
        bundledAllowlist = root.appendingPathComponent("bundled.allow")
        try "#!/bin/zsh -f\nprint ready\n".write(to: bundledScript, atomically: true, encoding: .utf8)
        try "~/agent.sock\n".write(to: bundledAllowlist, atomically: true, encoding: .utf8)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        super.tearDown()
    }

    private func makeInstaller() -> SASSHAgentRelayInstaller {
        SASSHAgentRelayInstaller(scriptsDirectory: scripts, bundledScript: bundledScript, bundledAllowlist: bundledAllowlist)
    }

    func testStatusIsNotInstalledUntilTheScriptExists() {
        XCTAssertEqual(makeInstaller().status, .notInstalled)
    }

    func testInstallCopiesAnExecutableScriptAndTheAllowlist() throws {
        let installer = makeInstaller()
        try installer.install(into: scripts)

        XCTAssertEqual(installer.status, .installed)
        XCTAssertEqual(try Data(contentsOf: installer.installedScript), try Data(contentsOf: bundledScript))
        XCTAssertEqual(try String(contentsOf: installer.installedAllowlist, encoding: .utf8), "~/agent.sock\n")
        let mode = try FileManager.default.attributesOfItem(atPath: installer.installedScript.path)[.posixPermissions] as? Int
        XCTAssertEqual(mode, 0o700)
    }

    func testAScriptThatDiffersFromTheBundledOneIsOutdated() throws {
        let installer = makeInstaller()
        try installer.install(into: scripts)
        try "#!/bin/zsh -f\nprint tampered\n".write(to: installer.installedScript, atomically: true, encoding: .utf8)
        XCTAssertEqual(installer.status, .outdated)
    }

    /// The helper will not start without its allowlist. A helper whose
    /// allowlist has gone must not read as installed, or there would be no
    /// button left to put it back.
    func testAMissingAllowlistNeedsRepairAndReinstallingRestoresIt() throws {
        let installer = makeInstaller()
        try installer.install(into: scripts)
        try FileManager.default.removeItem(at: installer.installedAllowlist)

        XCTAssertEqual(installer.status, .outdated)
        XCTAssertNotNil(SASSHAgentRelayInstaller.presentation(status: installer.status, installedThisSession: false).action)

        try installer.install(into: scripts)
        XCTAssertEqual(installer.status, .installed)
        XCTAssertEqual(try String(contentsOf: installer.installedAllowlist, encoding: .utf8), "~/agent.sock\n")
    }

    /// NSUserUnixTask cannot run a script without its execute bit, so such a
    /// copy must not read as installed; reinstalling restores the bit.
    func testAScriptThatLostItsExecuteBitNeedsRepair() throws {
        let installer = makeInstaller()
        try installer.install(into: scripts)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: installer.installedScript.path)
        XCTAssertEqual(installer.status, .outdated)

        try installer.install(into: scripts)
        XCTAssertEqual(installer.status, .installed)
    }

    /// An allowlist that exists but cannot be read is made readable again on
    /// update, keeping the user's entries.
    func testUpdatingMakesAnUnreadableAllowlistReadableAndKeepsItsContents() throws {
        let installer = makeInstaller()
        try installer.install(into: scripts)
        try "~/agent.sock\n/my/own/agent.sock\n".write(to: installer.installedAllowlist, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: installer.installedAllowlist.path)
        XCTAssertEqual(installer.status, .outdated)

        try installer.install(into: scripts)

        XCTAssertEqual(installer.status, .installed)
        XCTAssertEqual(try String(contentsOf: installer.installedAllowlist, encoding: .utf8), "~/agent.sock\n/my/own/agent.sock\n")
    }

    /// The settings sheet shows the error's text, so a failed copy must carry
    /// the system's reason, not a generic one.
    func testInstallErrorsCarryAReadableReason() {
        XCTAssertEqual(SASSHAgentRelayInstaller.InstallError.copyFailed("Permission denied").localizedDescription, "Permission denied")
        XCTAssertFalse(SASSHAgentRelayInstaller.InstallError.wrongFolder.localizedDescription.contains("SASSHAgentRelayInstaller"))
        XCTAssertFalse(SASSHAgentRelayInstaller.InstallError.missingBundledHelper.localizedDescription.contains("SASSHAgentRelayInstaller"))
    }

    func testUpdatingReplacesTheScriptButKeepsTheUsersAllowlist() throws {
        let installer = makeInstaller()
        try installer.install(into: scripts)
        try "~/agent.sock\n/my/own/agent.sock\n".write(to: installer.installedAllowlist, atomically: true, encoding: .utf8)
        try "#!/bin/zsh -f\nprint ready # v2\n".write(to: bundledScript, atomically: true, encoding: .utf8)
        XCTAssertEqual(installer.status, .outdated)

        try installer.install(into: scripts)

        XCTAssertEqual(installer.status, .installed)
        XCTAssertEqual(try String(contentsOf: installer.installedAllowlist, encoding: .utf8),
                       "~/agent.sock\n/my/own/agent.sock\n")
    }

    func testInstallRefusesAnyFolderButTheScriptsFolder() throws {
        let elsewhere = root.appendingPathComponent("Documents")
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        let installer = makeInstaller()

        XCTAssertThrowsError(try installer.install(into: elsewhere)) {
            XCTAssertEqual($0 as? SASSHAgentRelayInstaller.InstallError, .wrongFolder)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: elsewhere.appendingPathComponent(SASSHAgentRelayInstaller.scriptName).path))
        XCTAssertFalse(installer.installedThisSession)
    }

    func testInstallingMarksTheSessionSoTheRelayWaitsForARelaunch() throws {
        let installer = makeInstaller()
        XCTAssertFalse(installer.installedThisSession)
        try installer.install(into: scripts)
        XCTAssertTrue(installer.installedThisSession)
    }

    func testPreferencesOfferTheActionEachStateNeeds() {
        let missing = SASSHAgentRelayInstaller.presentation(status: .notInstalled, installedThisSession: false)
        let outdated = SASSHAgentRelayInstaller.presentation(status: .outdated, installedThisSession: false)
        let installed = SASSHAgentRelayInstaller.presentation(status: .installed, installedThisSession: false)
        let justInstalled = SASSHAgentRelayInstaller.presentation(status: .installed, installedThisSession: true)

        XCTAssertNotNil(missing.action)
        XCTAssertNotNil(outdated.action)
        XCTAssertNotEqual(missing.action, outdated.action)
        XCTAssertNil(installed.action)
        XCTAssertNil(justInstalled.action, "nothing more to install; the app has to relaunch")
        XCTAssertEqual(Set([missing.state, outdated.state, installed.state, justInstalled.state]).count, 4)
    }

    func testSummaryNamesTheDefaultAgentAndWhatItStillNeeds() {
        let onePassword = SASSHAgentSource(kind: .onePassword)
        func summary(_ source: SASSHAgentSource, _ status: SASSHAgentRelayInstaller.Status, relaunch: Bool = false) -> String {
            SASSHAgentRelayInstaller.summary(defaultSource: source, status: status, installedThisSession: relaunch)
        }

        XCTAssertEqual(summary(onePassword, .installed), "1Password")
        XCTAssertTrue(summary(onePassword, .notInstalled).hasPrefix("1Password"))
        XCTAssertNotEqual(summary(onePassword, .notInstalled), summary(onePassword, .outdated))
        XCTAssertNotEqual(summary(onePassword, .installed), summary(onePassword, .installed, relaunch: true))
        XCTAssertEqual(summary(SASSHAgentSource(kind: .custom, customPath: "~/a/agent.sock"), .installed), "~/a/agent.sock")
        // With the agent off the helper's state is beside the point.
        XCTAssertEqual(summary(.off, .notInstalled), summary(.off, .installed))
    }

    private func connectionStatus(_ source: String, default defaultSource: String,
                                  _ status: SASSHAgentRelayInstaller.Status = .installed,
                                  relaunch: Bool = false) -> (text: String, needsAttention: Bool) {
        SASSHAgentRelayInstaller.connectionStatus(connectionSource: source, connectionCustomPath: "",
                                                  defaultSource: defaultSource, defaultCustomPath: "",
                                                  status: status, installedThisSession: relaunch)
    }

    /// The connection form says which agent "Use Default" resolves to.
    func testConnectionStatusNamesTheAgentThatWillBeUsed() {
        XCTAssertTrue(connectionStatus("", default: "1password").text.contains("1Password"))
        XCTAssertTrue(connectionStatus("system", default: "1password").text.contains(connectionStatus("system", default: "").text))
        XCTAssertNotEqual(connectionStatus("", default: "1password").text, connectionStatus("1password", default: "").text,
                          "following the default is said in so many words")
        XCTAssertFalse(connectionStatus("", default: "1password").needsAttention)
    }

    func testConnectionStatusSaysWhenNoAgentIsUsed() {
        XCTAssertFalse(connectionStatus("", default: "").needsAttention)
        XCTAssertFalse(connectionStatus("off", default: "1password").needsAttention)
        XCTAssertFalse(connectionStatus("off", default: "1password").text.contains("1Password"))
        // With no agent in play the helper's state is beside the point.
        XCTAssertEqual(connectionStatus("off", default: "", .notInstalled).text, connectionStatus("off", default: "", .installed).text)
    }

    func testConnectionStatusFlagsAnAgentThatCannotWorkYet() {
        let ready = connectionStatus("1password", default: "")
        for blocked in [connectionStatus("1password", default: "", .notInstalled),
                        connectionStatus("1password", default: "", .outdated),
                        connectionStatus("1password", default: "", .installed, relaunch: true)] {
            XCTAssertTrue(blocked.needsAttention)
            XCTAssertNotEqual(blocked.text, ready.text)
        }
    }

    func testUseDefaultNamesTheCurrentDefault() {
        XCTAssertEqual(SASSHAgentRelayInstaller.useDefaultTitle(defaultSource: "1password", defaultCustomPath: ""), "Use Default (1Password)")
        XCTAssertEqual(SASSHAgentRelayInstaller.useDefaultTitle(defaultSource: "", defaultCustomPath: ""), "Use Default (Off)")
        XCTAssertEqual(SASSHAgentRelayInstaller.useDefaultTitle(defaultSource: "custom", defaultCustomPath: "~/a.sock"), "Use Default (~/a.sock)")
    }

    func testInstallFailsWithoutABundledHelper() {
        let installer = SASSHAgentRelayInstaller(scriptsDirectory: scripts, bundledScript: nil, bundledAllowlist: nil)
        XCTAssertThrowsError(try installer.install(into: scripts)) {
            XCTAssertEqual($0 as? SASSHAgentRelayInstaller.InstallError, .missingBundledHelper)
        }
    }
}
