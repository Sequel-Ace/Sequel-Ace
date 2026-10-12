//
//  SASSHAgentSourceTests.swift
//  Unit Tests
//
//  Created by the Sequel Ace team on October 10, 2026.
//  Copyright (c) 2026 Sequel-Ace. All rights reserved.
//

import XCTest

/// The pure decisions behind SSH agent support: which source a connection
/// uses, which socket that means, and which ssh options follow.
final class SASSHAgentSourceTests: XCTestCase {

    private let home = "/Users/tester"
    private let neverAutomatic: () throws -> SASSHAgentSource.AutomaticAgent = {
        XCTFail("ssh -G must not run for this source")
        return .environment
    }

    // MARK: - Stored form and defaults

    func testStoredValuesRoundTrip() {
        for kind in SASSHAgentSource.Kind.allCases {
            let source = SASSHAgentSource(kind: kind, customPath: "/tmp/a.sock")
            XCTAssertEqual(SASSHAgentSource.stored(source.storedValue, customPath: "/tmp/a.sock"), source)
        }
    }

    func testEmptyOrUnknownStoredValueIsNoChoice() {
        XCTAssertNil(SASSHAgentSource.stored("", customPath: ""))
        XCTAssertNil(SASSHAgentSource.stored("yubikey", customPath: ""))
    }

    func testCustomPathIsKeptOnlyForCustom() {
        XCTAssertEqual(SASSHAgentSource(kind: .system, customPath: "/tmp/a.sock").customPath, "")
        XCTAssertEqual(SASSHAgentSource.stored("custom", customPath: " /tmp/a.sock ")?.customPath, "/tmp/a.sock")
    }

    func testConnectionChoiceWinsOverDefault() {
        let source = SASSHAgentSource.effective(connectionSource: "off", connectionCustomPath: "",
                                                defaultSource: "1password", defaultCustomPath: "")
        XCTAssertEqual(source, .off)
    }

    func testConnectionWithoutChoiceFollowsDefault() {
        let source = SASSHAgentSource.effective(connectionSource: "", connectionCustomPath: "/ignored",
                                                defaultSource: "custom", defaultCustomPath: "~/agent.sock")
        XCTAssertEqual(source, SASSHAgentSource(kind: .custom, customPath: "~/agent.sock"))
    }

    // MARK: - Connection strings

    private func exported(_ source: String, socket: String = "", localPaths: Bool = false) -> [String] {
        SASSHAgentSource.connectionStringQueryItems(source: source, socketPath: socket, includeLocalPaths: localPaths)
            .map { "\($0.name)=\($0.value ?? "")" }
    }

    func testAgentKindTravelsInAConnectionString() {
        XCTAssertEqual(exported("1password"), ["ssh_agent=1password"])
        XCTAssertEqual(exported("automatic"), ["ssh_agent=automatic"])
        XCTAssertEqual(exported("system"), ["ssh_agent=system"])
    }

    /// Off is a choice too: it overrides the recipient's default.
    func testExplicitOffTravelsButNoChoiceExportsNothing() {
        XCTAssertEqual(exported("off"), ["ssh_agent=off"])
        XCTAssertEqual(exported(""), [])
        XCTAssertEqual(exported("unknown"), [])
    }

    /// A custom agent's socket is a path on this machine, like a key file. A
    /// custom choice without its path would import broken, so it is dropped.
    func testCustomAgentTravelsOnlyWithItsPathAndOnlyWhenLocalPathsAreWanted() {
        let socket = "~/Library/Containers/agent/Data/socket.ssh"
        XCTAssertEqual(exported("custom", socket: socket), [])
        XCTAssertEqual(exported("custom", socket: "", localPaths: true), [])
        XCTAssertEqual(exported("custom", socket: socket, localPaths: true),
                       ["ssh_agent=custom", "ssh_agent_socket=\(socket)"])
    }

    /// The importer accepts exactly the values the exporter writes.
    func testEveryExportedKindIsOneTheParserAccepts() {
        for kind in SASSHAgentSource.Kind.allCases {
            let value = SASSHAgentSource.connectionStringQueryItems(source: kind.rawValue, socketPath: "/s",
                                                                    includeLocalPaths: true).first?.value
            XCTAssertEqual(value.flatMap(SASSHAgentSource.Kind.init(rawValue:)), kind)
        }
    }

    // MARK: - Regression: agent off changes nothing

    /// Existing users never set either value. That must resolve to off, with
    /// no socket and without consulting ssh, so the tunnel launches ssh
    /// exactly as before.
    func testUnsetConnectionAndUnsetDefaultMeanNoRelayAtAll() throws {
        let source = SASSHAgentSource.effective(connectionSource: "", connectionCustomPath: "",
                                                defaultSource: "", defaultCustomPath: "")
        XCTAssertEqual(source, .off)
        XCTAssertNil(try source.targetPath(realHome: home, environment: ["SSH_AUTH_SOCK": "/tmp/sys.sock"],
                                           automatic: neverAutomatic))
    }

    func testExplicitOffMeansNoRelayEvenWithADefault() throws {
        let source = SASSHAgentSource.effective(connectionSource: "off", connectionCustomPath: "",
                                                defaultSource: "system", defaultCustomPath: "")
        XCTAssertNil(try source.targetPath(realHome: home, environment: ["SSH_AUTH_SOCK": "/tmp/sys.sock"],
                                           automatic: neverAutomatic))
    }

    func testRelayRefusesNothingAndLaunchesNothingForOff() throws {
        let relay = SASSHAgentRelay(installer: nil, launcher: { _, _, _, _ in
            XCTFail("no helper may be launched when the agent is off")
            throw CocoaError(.featureUnsupported)
        })
        for source in ["", "off", "unknown"] {
            let plan = try relay.launchPlan(source: source, customPath: "", host: "db.example.com", user: "", port: 0,
                                            hasKeyFile: false)
            XCTAssertFalse(plan.isActive)
            XCTAssertEqual(plan.sshArguments, [])
        }
    }

    // MARK: - Target socket

    func testOnePasswordTargetIsUnderTheRealHome() throws {
        let target = try SASSHAgentSource(kind: .onePassword).targetPath(realHome: home, environment: [:],
                                                                         automatic: neverAutomatic)
        XCTAssertEqual(target, "/Users/tester/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock")
    }

    func testSystemTargetIsTheInheritedSocket() throws {
        let source = SASSHAgentSource(kind: .system)
        XCTAssertEqual(try source.targetPath(realHome: home, environment: ["SSH_AUTH_SOCK": "/var/run/x/Listeners"],
                                             automatic: neverAutomatic), "/var/run/x/Listeners")
        XCTAssertThrowsError(try source.targetPath(realHome: home, environment: [:], automatic: neverAutomatic)) {
            XCTAssertEqual($0 as? SASSHAgentSource.ResolveError, .noSystemAgent)
        }
    }

    func testCustomTargetExpandsTildeAndRejectsBadPaths() throws {
        XCTAssertEqual(try SASSHAgentSource(kind: .custom, customPath: "~/a/agent.sock")
            .targetPath(realHome: home, environment: [:], automatic: neverAutomatic), "/Users/tester/a/agent.sock")
        XCTAssertThrowsError(try SASSHAgentSource(kind: .custom, customPath: "")
            .targetPath(realHome: home, environment: [:], automatic: neverAutomatic)) {
            XCTAssertEqual($0 as? SASSHAgentSource.ResolveError, .emptyCustomPath)
        }
        XCTAssertThrowsError(try SASSHAgentSource(kind: .custom, customPath: "agent.sock")
            .targetPath(realHome: home, environment: [:], automatic: neverAutomatic)) {
            XCTAssertEqual($0 as? SASSHAgentSource.ResolveError, .relativePath("agent.sock"))
        }
    }

    func testAutomaticFollowsWhatSSHReports() throws {
        let source = SASSHAgentSource(kind: .automatic)
        let environment = ["SSH_AUTH_SOCK": "/var/run/x/Listeners"]
        XCTAssertEqual(try source.targetPath(realHome: home, environment: environment) { .path("~/p/agent.sock") },
                       "/Users/tester/p/agent.sock")
        XCTAssertEqual(try source.targetPath(realHome: home, environment: environment) { .environment },
                       "/var/run/x/Listeners")
        XCTAssertNil(try source.targetPath(realHome: home, environment: environment) { .disabled })
    }

    // MARK: - ssh -G output

    func testParsesAnIdentityAgentPath() throws {
        let dump = "user root\nhostname db\nidentityagent /Users/tester/Library/Group Containers/x/agent.sock\nport 22\n"
        XCTAssertEqual(try SASSHAgentSource.parseAutomaticAgent(sshConfigDump: dump),
                       .path("/Users/tester/Library/Group Containers/x/agent.sock"))
    }

    func testParsesQuotedNoneAbsentAndEnvironmentForms() throws {
        XCTAssertEqual(try SASSHAgentSource.parseAutomaticAgent(sshConfigDump: "identityagent \"~/a b/agent.sock\"\n"),
                       .path("~/a b/agent.sock"))
        XCTAssertEqual(try SASSHAgentSource.parseAutomaticAgent(sshConfigDump: "IdentityAgent none\n"), .disabled)
        XCTAssertEqual(try SASSHAgentSource.parseAutomaticAgent(sshConfigDump: "identityagent SSH_AUTH_SOCK\n"), .environment)
        XCTAssertEqual(try SASSHAgentSource.parseAutomaticAgent(sshConfigDump: "user root\nidentitiesonly yes\n"), .environment)
    }

    func testRejectsAnEnvironmentVariableIdentityAgent() {
        XCTAssertThrowsError(try SASSHAgentSource.parseAutomaticAgent(sshConfigDump: "identityagent $MY_AGENT\n")) {
            XCTAssertEqual($0 as? SASSHAgentSource.ResolveError, .unsupportedIdentityAgent("$MY_AGENT"))
        }
    }

    // MARK: - ssh -G lookup

    private func stubSSH(_ body: String) throws -> String {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("stub-ssh-\(UUID().uuidString).sh")
        try "#!/bin/sh\n\(body)\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url.path
    }

    func testLookupPassesHostUserPortAndConfigToSSH() throws {
        let ssh = try stubSSH(#"echo "identityagent /seen/$*""#)
        let agent = try SASSHAgentSource.lookUpAutomaticAgent(sshPath: ssh, configPath: "/c/config", host: "db",
                                                              user: "root", port: 2222)
        XCTAssertEqual(agent, .path("/seen/-G -F /c/config -p 2222 root@db"))
    }

    func testLookupTimesOutAndStopsSSH() throws {
        let ssh = try stubSSH("exec /bin/sleep 30")
        let started = Date()
        XCTAssertThrowsError(try SASSHAgentSource.lookUpAutomaticAgent(sshPath: ssh, configPath: nil, host: "db",
                                                                       user: "", port: 0, timeout: 0.3)) {
            XCTAssertEqual($0 as? SASSHAgentSource.ResolveError, .lookupTimedOut)
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 5)
    }

    func testLookupReportsAFailingSSH() throws {
        let ssh = try stubSSH("exit 255")
        XCTAssertThrowsError(try SASSHAgentSource.lookUpAutomaticAgent(sshPath: ssh, configPath: nil, host: "db",
                                                                       user: "", port: 0)) {
            guard case .lookupFailed = $0 as? SASSHAgentSource.ResolveError else { return XCTFail("\($0)") }
        }
    }

    // MARK: - ssh options

    func testBundledConfigWithoutKeyFileOffersAgentKeysButNeverAddsKeys() {
        XCTAssertEqual(SASSHAgentSource.sshArguments(listenPath: "/c/.keys/a-1", usesBundledConfig: true, hasKeyFile: false),
                       ["-o", "IdentityAgent=\"/c/.keys/a-1\"", "-o", "IdentitiesOnly=no", "-o", "AddKeysToAgent=no"])
    }

    func testBundledConfigWithKeyFileKeepsIdentitiesOnlySoAPublicKeyPinsOneAgentKey() {
        XCTAssertEqual(SASSHAgentSource.sshArguments(listenPath: "/c/.keys/a-1", usesBundledConfig: true, hasKeyFile: true),
                       ["-o", "IdentityAgent=\"/c/.keys/a-1\"", "-o", "AddKeysToAgent=no"])
    }

    func testAUsersOwnConfigOnlyGetsTheAgentRedirected() {
        for hasKeyFile in [true, false] {
            XCTAssertEqual(SASSHAgentSource.sshArguments(listenPath: "/c/.keys/a-1", usesBundledConfig: false,
                                                         hasKeyFile: hasKeyFile),
                           ["-o", "IdentityAgent=\"/c/.keys/a-1\""])
        }
    }
}
