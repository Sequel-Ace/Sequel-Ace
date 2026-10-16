//
//  SASSHAgentRelayTests.swift
//  Unit Tests
//
//  Created by the Sequel Ace team on October 10, 2026.
//  Copyright (c) 2026 Sequel-Ace. All rights reserved.
//

import XCTest

/// The relay service driving the real helper script against a stand-in agent
/// socket. The test bundle is not sandboxed, so the script is started with
/// `Process` instead of `NSUserUnixTask`; everything else is the shipped code.
///
/// The script finds its allowlist, and "~", from where it is installed, so
/// each test builds a miniature home folder:
///
///     <root>/Library/Application Scripts/b/ssh-agent-relay.zsh
///     <root>/Library/Containers/b/Data/.keys/
final class SASSHAgentRelayTests: XCTestCase {

    private var root: URL!
    private var scripts: URL!
    private var containerData: URL!
    private var agent: FakeAgent!
    private var launches: HelperLaunches!

    override func setUpWithError() throws {
        // /private/tmp keeps socket paths well inside sun_path's 104 bytes,
        // which the per-user temporary directory does not.
        var template = Array("/private/tmp/sa-relay-XXXXXX".utf8CString)
        guard let created = mkdtemp(&template) else { throw CocoaError(.fileWriteUnknown) }
        root = URL(fileURLWithPath: String(cString: created))
        scripts = root.appendingPathComponent("Library/Application Scripts/b")
        containerData = root.appendingPathComponent("Library/Containers/b/Data")
        try FileManager.default.createDirectory(at: scripts, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: containerData.appendingPathComponent(".keys"),
                                                withIntermediateDirectories: true)

        let bundle = Bundle(for: Self.self)
        let script = try XCTUnwrap(bundle.url(forResource: SASSHAgentRelayInstaller.scriptName, withExtension: nil),
                                   "the helper script must be a resource of the Unit Tests bundle")
        try FileManager.default.copyItem(at: script, to: scripts.appendingPathComponent(SASSHAgentRelayInstaller.scriptName))
        try FileManager.default.setAttributes([.posixPermissions: 0o700],
                                              ofItemAtPath: scripts.appendingPathComponent(SASSHAgentRelayInstaller.scriptName).path)

        agent = try FakeAgent(path: root.appendingPathComponent("agent.sock").path)
        try allow([agent.path])
        launches = HelperLaunches()
    }

    override func tearDown() {
        launches.stopAll()
        agent.close()
        try? FileManager.default.removeItem(at: root)
        super.tearDown()
    }

    private func allow(_ lines: [String]) throws {
        try (lines.joined(separator: "\n") + "\n")
            .write(to: scripts.appendingPathComponent(SASSHAgentRelayInstaller.allowlistName), atomically: true, encoding: .utf8)
    }

    private func makeInstaller() -> SASSHAgentRelayInstaller {
        let bundle = Bundle(for: Self.self)
        return SASSHAgentRelayInstaller(
            scriptsDirectory: scripts,
            bundledScript: bundle.url(forResource: SASSHAgentRelayInstaller.scriptName, withExtension: nil),
            bundledAllowlist: bundle.url(forResource: SASSHAgentRelayInstaller.allowlistName, withExtension: nil))
    }

    private func makeRelay(installer: SASSHAgentRelayInstaller? = nil, containerData override: String? = nil,
                           startTimeout: TimeInterval = 5, processIdentifier: Int32 = 4242) -> SASSHAgentRelay {
        SASSHAgentRelay(installer: installer ?? makeInstaller(), launcher: launches.launcher,
                        containerDataDirectory: override ?? containerData.path, processIdentifier: processIdentifier,
                        startTimeout: startTimeout)
    }

    private func assertRefused(_ expectedReason: String, _ body: () throws -> Void,
                               file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try body(), file: file, line: line) { error in
            guard case .helperRefused(let reason, _, _) = error as? SASSHAgentRelay.RelayError else {
                return XCTFail("expected a refusal, got \(error)", file: file, line: line)
            }
            XCTAssertEqual(reason, expectedReason, file: file, line: line)
        }
    }

    // MARK: - Relaying

    func testRelaysBytesBothWaysThroughASocketInsideTheContainer() throws {
        let listenPath = try makeRelay().listenPath(forTarget: agent.path)

        XCTAssertTrue(listenPath.hasPrefix(containerData.path + "/.keys/a-"))
        XCTAssertEqual(try SocketClient.exchange("hello", at: listenPath), "pong:hello")
        XCTAssertEqual(try SocketClient.exchange("again", at: listenPath), "pong:again")
    }

    func testTwoClientsAtOnceEachGetTheirOwnAnswer() throws {
        let listenPath = try makeRelay().listenPath(forTarget: agent.path)
        let first = try SocketClient(path: listenPath)
        let second = try SocketClient(path: listenPath)
        defer { first.close(); second.close() }

        try second.send("two")
        try first.send("one")

        XCTAssertEqual(try first.receive(), "pong:one")
        XCTAssertEqual(try second.receive(), "pong:two")
    }

    func testSocketIsPrivateToTheUser() throws {
        let listenPath = try makeRelay().listenPath(forTarget: agent.path)
        let mode = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: listenPath)[.posixPermissions] as? Int)
        XCTAssertEqual(mode & 0o077, 0)
    }

    // MARK: - Lifecycle

    func testSecondRequestReusesTheRunningHelper() throws {
        let relay = makeRelay()
        let first = try relay.listenPath(forTarget: agent.path)
        let second = try relay.listenPath(forTarget: agent.path)

        XCTAssertEqual(first, second)
        XCTAssertEqual(launches.count, 1)
    }

    func testConcurrentRequestsShareOneLaunch() throws {
        let relay = makeRelay()
        let target = agent.path
        let results = Locked<[String]>([])
        DispatchQueue.concurrentPerform(iterations: 6) { _ in
            if let path = try? relay.listenPath(forTarget: target) { results.mutate { $0.append(path) } }
        }

        XCTAssertEqual(results.value.count, 6)
        XCTAssertEqual(Set(results.value).count, 1)
        XCTAssertEqual(launches.count, 1)
    }

    func testHelperExitsAndItsSocketIsRemovedWhenTheAppClosesItsInput() throws {
        let relay = makeRelay()
        let listenPath = try relay.listenPath(forTarget: agent.path)
        let helper = try XCTUnwrap(launches.processes.first)

        launches.closeInputs()

        XCTAssertTrue(wait(until: { !helper.isRunning }), "the helper must exit when its input closes")
        XCTAssertTrue(wait(until: { !FileManager.default.fileExists(atPath: listenPath) }),
                      "the socket must be removed once its helper has gone")
    }

    /// Quitting must take every relayed connection down with it, including
    /// ones still being set up: a pump left running would keep a connection
    /// to the user's agent open after Sequel Ace has gone.
    func testNoAgentConnectionOutlivesTheHelper() throws {
        for round in 0..<6 {
            let relay = makeRelay()
            let listenPath = try relay.listenPath(forTarget: agent.path)
            let clients = try (0..<12).map { _ in try SocketClient(path: listenPath) }
            // Vary how far connection setup has got when the helper is told to quit.
            usleep(UInt32(round) * 15_000)
            launches.closeInputs()
            XCTAssertTrue(wait(until: { self.launches.processes.allSatisfy { !$0.isRunning } }), "round \(round)")
            XCTAssertTrue(wait(until: { self.agent.openConnections == 0 }, timeout: 3),
                          "round \(round): \(agent.openConnections) agent connection(s) left open")
            clients.forEach { $0.close() }
        }
    }

    func testAKilledHelperIsStartedAgainByTheNextRequest() throws {
        let relay = makeRelay()
        let listenPath = try relay.listenPath(forTarget: agent.path)
        let helper = try XCTUnwrap(launches.processes.first)

        kill(helper.processIdentifier, SIGKILL)
        XCTAssertTrue(wait(until: { self.launches.exits == 1 }))

        XCTAssertEqual(try relay.listenPath(forTarget: agent.path), listenPath)
        XCTAssertEqual(launches.count, 2)
        XCTAssertEqual(try SocketClient.exchange("back", at: listenPath), "pong:back")
    }

    /// A helper can say "ready" and then die before the launch has finished.
    /// It must not be remembered as running, or every later connection would
    /// be handed its dead socket until the app relaunched.
    func testAHelperThatExitsDuringStartupIsNotCachedAsRunning() throws {
        let exitDuringStartup = Locked<Bool>(true)
        let launchCount = Locked<Int>(0)
        let real = launches.launcher
        let relay = SASSHAgentRelay(installer: makeInstaller(), launcher: { script, arguments, socket, onExit in
            launchCount.mutate { $0 += 1 }
            guard exitDuringStartup.value else { return try real(script, arguments, socket, onExit) }
            let status = Pipe()
            status.fileHandleForWriting.write(Data("ready\n".utf8))
            try? status.fileHandleForWriting.close()
            onExit()
            return SASSHAgentRelay.Helper(status: status.fileHandleForReading, closeInput: {})
        }, containerDataDirectory: containerData.path, processIdentifier: 4242)

        XCTAssertThrowsError(try relay.listenPath(forTarget: agent.path)) {
            XCTAssertEqual($0 as? SASSHAgentRelay.RelayError, .helperExited(detail: ""))
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: containerData.path + "/.keys"), [],
                       "the dead helper's socket must not be left behind")

        exitDuringStartup.mutate { $0 = false }
        let listenPath = try relay.listenPath(forTarget: agent.path)
        XCTAssertEqual(launchCount.value, 2, "the next request must start a fresh helper")
        XCTAssertEqual(try SocketClient.exchange("alive", at: listenPath), "pong:alive")
    }

    /// The helper's reason and its explanation usually arrive in one read;
    /// the explanation must not be lost with the rest of that read.
    func testKeepsTheHelpersExplanationWhenItArrivesWithTheStatusLine() throws {
        let relay = SASSHAgentRelay(installer: makeInstaller(), launcher: { _, _, _, onExit in
            let status = Pipe()
            status.fileHandleForWriting.write(Data("error no-allowlist\nssh-agent-relay: the allowlist is missing\n".utf8))
            try? status.fileHandleForWriting.close()
            onExit()
            return SASSHAgentRelay.Helper(status: status.fileHandleForReading, closeInput: {})
        }, containerDataDirectory: containerData.path, processIdentifier: 4242)

        XCTAssertThrowsError(try relay.listenPath(forTarget: agent.path)) {
            XCTAssertEqual($0 as? SASSHAgentRelay.RelayError,
                           .helperRefused(reason: "no-allowlist", target: agent.path,
                                          detail: "ssh-agent-relay: the allowlist is missing"))
        }
    }

    func testAHelperThatNeverAnswersTimesOutAndIsToldToQuit() throws {
        let toldToQuit = Locked<Bool>(false)
        let relay = SASSHAgentRelay(installer: makeInstaller(), launcher: { _, _, _, _ in
            let status = Pipe()
            return SASSHAgentRelay.Helper(status: status.fileHandleForReading, closeInput: {
                toldToQuit.mutate { $0 = true }
                try? status.fileHandleForWriting.close()
            })
        }, containerDataDirectory: containerData.path, processIdentifier: 4242, startTimeout: 0.3)

        XCTAssertThrowsError(try relay.listenPath(forTarget: agent.path)) {
            XCTAssertEqual($0 as? SASSHAgentRelay.RelayError, .startTimedOut)
        }
        XCTAssertTrue(toldToQuit.value, "a helper that timed out must have its input closed")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: containerData.path + "/.keys"), [],
                       "a failed start must not leave its socket behind")
    }

    func testManyClientsConnectingAtTheSameMomentAreAllServed() throws {
        let listenPath = try makeRelay().listenPath(forTarget: agent.path)
        let answers = Locked<[String]>([])
        DispatchQueue.concurrentPerform(iterations: 8) { index in
            if let answer = try? SocketClient.exchange("c\(index)", at: listenPath) { answers.mutate { $0.append(answer) } }
        }
        XCTAssertEqual(answers.value.sorted(), (0..<8).map { "pong:c\($0)" })
    }

    func testReplacesASocketLeftBehindByAnEarlierRun() throws {
        let name = SASSHAgentRelay.socketName(target: agent.path, processIdentifier: 4242)
        let stale = SASSHAgentRelay.listenPath(containerDataDirectory: containerData.path, socketName: name, processIdentifier: 4242)
        close(try SASSHAgentRelay.makeListeningSocket(at: stale))

        let listenPath = try makeRelay().listenPath(forTarget: agent.path)
        XCTAssertEqual(listenPath, stale)
        XCTAssertEqual(try SocketClient.exchange("fresh", at: listenPath), "pong:fresh")
    }

    /// Socket names are short hashes. If the name for this target is already
    /// taken by a socket something is listening on — another agent's relay,
    /// or another copy of the app — taking it over would send that relay's
    /// clients to the wrong agent.
    func testNeverTakesOverASocketThatIsStillInUse() throws {
        // A live process id, as the running app's own would be.
        let pid = getpid()
        let name = SASSHAgentRelay.socketName(target: agent.path, processIdentifier: pid)
        let taken = SASSHAgentRelay.listenPath(containerDataDirectory: containerData.path, socketName: name, processIdentifier: pid)
        let owner = try SASSHAgentRelay.makeListeningSocket(at: taken)
        defer { close(owner) }

        let relay = makeRelay(processIdentifier: pid)
        let listenPath = try relay.listenPath(forTarget: agent.path)

        XCTAssertNotEqual(listenPath, taken)
        XCTAssertEqual(try SocketClient.exchange("mine", at: listenPath), "pong:mine")
        // The original socket is untouched and still its owner's.
        let probe = try SocketClient(path: taken)
        probe.close()
        var pending = pollfd(fd: owner, events: Int16(POLLIN), revents: 0)
        XCTAssertEqual(poll(&pending, 1, 1000), 1, "the connection must have reached the original listener")
    }

    func testTwoAgentsWhoseNamesWouldCollideGetSeparateSockets() throws {
        let other = try FakeAgent(path: root.appendingPathComponent("other.sock").path)
        defer { other.close() }
        try allow([agent.path, other.path])
        // Every target hashes to the same first-choice name.
        let relay = SASSHAgentRelay(installer: makeInstaller(), launcher: launches.launcher,
                                    containerDataDirectory: containerData.path, processIdentifier: 4242,
                                    socketNamer: { _, _, attempt in String(format: "0000000%x", attempt) })

        let first = try relay.listenPath(forTarget: agent.path)
        let second = try relay.listenPath(forTarget: other.path)

        XCTAssertNotEqual(first, second)
        XCTAssertEqual(launches.count, 2)
        // Each socket leads to its own agent, not the other's.
        let viaFirst = try SocketClient(path: first)
        defer { viaFirst.close() }
        try viaFirst.send("a")
        XCTAssertEqual(try viaFirst.receive(), "pong:a")
        XCTAssertEqual(agent.openConnections, 1)
        XCTAssertEqual(other.openConnections, 0)
        let viaSecond = try SocketClient(path: second)
        defer { viaSecond.close() }
        try viaSecond.send("b")
        XCTAssertEqual(try viaSecond.receive(), "pong:b")
        XCTAssertEqual(other.openConnections, 1)
    }

    /// A process id that certainly belongs to no running process: a child that
    /// has run and been reaped.
    private func deadProcessIdentifier() throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try process.run()
        process.waitUntilExit()
        return process.processIdentifier
    }

    /// Another live copy of the app may have a socket that refuses a probe —
    /// not listening yet, or a full backlog. Its process id says it is alive,
    /// so the sweep leaves it.
    func testSweepLeavesSocketsOfLiveProcessesEvenWhenTheyRefuseConnections() throws {
        let keys = containerData.path + "/.keys"
        let otherLiveCopy = keys + "/a-0000f00d-\(getpid())"
        close(try SASSHAgentRelay.makeListeningSocket(at: otherLiveCopy))   // refuses connections now

        SASSHAgentRelay.removeAbandonedSockets(inDirectory: keys)
        XCTAssertTrue(FileManager.default.fileExists(atPath: otherLiveCopy))
    }

    func testSweepsAbandonedSocketsOfOtherProcessesButNotLiveOnesOrOtherFiles() throws {
        let keys = containerData.path + "/.keys"
        let abandoned = keys + "/a-0000dead-\(try deadProcessIdentifier())"
        close(try SASSHAgentRelay.makeListeningSocket(at: abandoned))
        let live = keys + "/a-0000beef-\(getpid())"
        let liveDescriptor = try SASSHAgentRelay.makeListeningSocket(at: live)
        defer { close(liveDescriptor) }
        try "keep".write(toFile: keys + "/ssh_known_hosts_strict", atomically: true, encoding: .utf8)

        _ = try makeRelay().listenPath(forTarget: agent.path)

        XCTAssertFalse(FileManager.default.fileExists(atPath: abandoned))
        XCTAssertTrue(FileManager.default.fileExists(atPath: live))
        XCTAssertTrue(FileManager.default.fileExists(atPath: keys + "/ssh_known_hosts_strict"))
    }

    // MARK: - What the helper refuses

    func testRefusesATargetThatIsNotInTheAllowlist() throws {
        let other = try FakeAgent(path: root.appendingPathComponent("other.sock").path)
        defer { other.close() }
        assertRefused("not-allowed") { _ = try makeRelay().listenPath(forTarget: other.path) }
    }

    func testAllowlistAcceptsTildeAndSingleComponentWildcards() throws {
        let folder = root.appendingPathComponent("com.apple.launchd.AbC123")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let wild = try FakeAgent(path: folder.appendingPathComponent("Listeners").path)
        defer { wild.close() }
        try allow(["# comment", "", "~/com.apple.launchd.*/Listeners"])

        let listenPath = try makeRelay().listenPath(forTarget: wild.path)
        XCTAssertEqual(try SocketClient.exchange("hi", at: listenPath), "pong:hi")
    }

    /// Lines people type by hand: indented, with a trailing comment, or saved
    /// with Windows line endings. `zsh -f` has no extended globbing, which a
    /// first version of the trimming silently depended on.
    func testAllowlistIgnoresSurroundingWhitespaceTrailingCommentsAndCarriageReturns() throws {
        for line in ["  \(agent.path)  ", "\(agent.path) # my agent", "\t\(agent.path)\r", "\(agent.path)\t#x\r"] {
            try allow(["# header", line])
            let relay = makeRelay()
            let listenPath = try relay.listenPath(forTarget: agent.path)
            XCTAssertEqual(try SocketClient.exchange("hi", at: listenPath), "pong:hi", "line: \(line.debugDescription)")
            launches.stopAll()
        }
    }

    /// "#" starts a comment only at the start of a line or after whitespace.
    /// Cutting at any "#" would turn a listed path that contains one into
    /// permission for a different, shorter path.
    func testAHashInsideAListedPathIsPartOfThePathNotAComment() throws {
        let folder = root.appendingPathComponent("agents#1")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let hashed = try FakeAgent(path: folder.appendingPathComponent("a.sock").path)
        // What the listed line would shrink to if it were cut at the "#".
        let shortened = try FakeAgent(path: root.appendingPathComponent("agents").path)
        defer { hashed.close(); shortened.close() }
        try allow([hashed.path])

        let listenPath = try makeRelay().listenPath(forTarget: hashed.path)
        XCTAssertEqual(try SocketClient.exchange("hi", at: listenPath), "pong:hi")
        launches.stopAll()
        assertRefused("not-allowed") { _ = try makeRelay().listenPath(forTarget: shortened.path) }
    }

    /// A listed name can sit in a folder other people can write to (/tmp).
    /// A link planted under such a name must not lead the helper to a socket
    /// that is not listed.
    func testALinkUnderAListedNameDoesNotReachAnUnlistedSocket() throws {
        let unlisted = try FakeAgent(path: root.appendingPathComponent("docker.sock").path)
        defer { unlisted.close() }
        let folder = root.appendingPathComponent("com.apple.launchd.Evil")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let planted = folder.appendingPathComponent("Listeners")
        try FileManager.default.createSymbolicLink(atPath: planted.path, withDestinationPath: unlisted.path)
        try allow(["~/com.apple.launchd.*/Listeners"])

        XCTAssertThrowsError(try makeRelay().listenPath(forTarget: planted.path)) { error in
            // The refusal names where the link leads: that is what would have to be listed.
            XCTAssertEqual(error as? SASSHAgentRelay.RelayError,
                           .helperRefused(reason: "not-allowed", target: unlisted.path,
                                          detail: (error as? SASSHAgentRelay.RelayError).flatMap {
                                              if case .helperRefused(_, _, let detail) = $0 { return detail }
                                              return nil
                                          } ?? ""))
        }
        XCTAssertEqual(unlisted.openConnections, 0)
    }

    /// A listed path may itself be a link (~/.1password/agent.sock is one);
    /// both it and its destination are then acceptable spellings.
    func testAListedLinkAllowsTheSocketItPointsTo() throws {
        let link = root.appendingPathComponent("agent-link.sock")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: agent.path)
        try allow([link.path])

        let listenPath = try makeRelay().listenPath(forTarget: link.path)
        XCTAssertEqual(try SocketClient.exchange("hi", at: listenPath), "pong:hi")
    }

    /// A line that is not an absolute path would otherwise be resolved
    /// against wherever the helper happens to run.
    func testRelativeAllowlistLinesAreIgnored() throws {
        try allow(["agent.sock", "./agent.sock", (agent.path as NSString).lastPathComponent])
        assertRefused("not-allowed") { _ = try makeRelay().listenPath(forTarget: agent.path) }
    }

    /// If the socket disappears from under a running helper, the next
    /// request starts a fresh one instead of handing out the missing path.
    func testARelayWhoseSocketWasRemovedIsReplaced() throws {
        let relay = makeRelay()
        let listenPath = try relay.listenPath(forTarget: agent.path)
        unlink(listenPath)

        XCTAssertEqual(try relay.listenPath(forTarget: agent.path), listenPath)
        XCTAssertEqual(launches.count, 2)
        XCTAssertEqual(try SocketClient.exchange("again", at: listenPath), "pong:again")
    }

    func testWildcardDoesNotReachIntoDeeperFolders() throws {
        let folder = root.appendingPathComponent("a/b")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let deep = try FakeAgent(path: folder.appendingPathComponent("s.sock").path)
        defer { deep.close() }
        try allow(["~/*/s.sock"])

        assertRefused("not-allowed") { _ = try makeRelay().listenPath(forTarget: deep.path) }
    }

    func testRefusesAListedTargetThatIsNotASocket() throws {
        let file = root.appendingPathComponent("plain.sock")
        try "not a socket".write(to: file, atomically: true, encoding: .utf8)
        try allow([file.path])

        assertRefused("no-target") { _ = try makeRelay().listenPath(forTarget: file.path) }
    }

    func testRefusesATargetWithDotDotComponents() throws {
        try allow([root.path + "/x/../agent.sock"])
        assertRefused("not-allowed") { _ = try makeRelay().listenPath(forTarget: root.path + "/x/../agent.sock") }
    }

    func testScriptRejectsAnythingButExactlyOneArgument() throws {
        for arguments in [[], [agent.path, agent.path]] {
            let process = Process()
            process.executableURL = scripts.appendingPathComponent(SASSHAgentRelayInstaller.scriptName)
            process.arguments = arguments
            let status = Pipe()
            process.standardOutput = FileHandle.nullDevice
            process.standardError = status
            process.standardInput = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            let output = String(decoding: status.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            XCTAssertTrue(output.hasPrefix("error usage\n"), "arguments: \(arguments)")
        }
    }

    // MARK: - What the service refuses before launching anything

    func testDoesNotLaunchWhenTheHelperIsMissingOrDiffers() throws {
        let installer = makeInstaller()
        try FileManager.default.removeItem(at: installer.installedScript)
        XCTAssertThrowsError(try makeRelay(installer: installer).listenPath(forTarget: agent.path)) {
            XCTAssertEqual($0 as? SASSHAgentRelay.RelayError, .helperNotInstalled)
        }

        try "#!/bin/zsh -f\nprint ready\n".write(to: installer.installedScript, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try makeRelay(installer: installer).listenPath(forTarget: agent.path)) {
            XCTAssertEqual($0 as? SASSHAgentRelay.RelayError, .helperOutdated)
        }
        XCTAssertEqual(launches.count, 0)
    }

    func testDoesNotLaunchInTheSessionThatInstalledTheHelper() throws {
        let installer = makeInstaller()
        try installer.install(into: scripts)

        XCTAssertThrowsError(try makeRelay(installer: installer).listenPath(forTarget: agent.path)) {
            XCTAssertEqual($0 as? SASSHAgentRelay.RelayError, .relaunchRequired)
        }
        XCTAssertEqual(launches.count, 0)
    }

    func testNeverRemovesARegularFileSittingAtItsSocketPath() throws {
        let name = SASSHAgentRelay.socketName(target: agent.path, processIdentifier: 4242)
        let squatter = SASSHAgentRelay.listenPath(containerDataDirectory: containerData.path, socketName: name, processIdentifier: 4242)
        try "precious".write(toFile: squatter, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try makeRelay().listenPath(forTarget: agent.path)) {
            XCTAssertEqual($0 as? SASSHAgentRelay.RelayError, .listenPathBlocked(squatter))
        }
        XCTAssertEqual(try String(contentsOfFile: squatter, encoding: .utf8), "precious")
        XCTAssertEqual(launches.count, 0)
    }

    func testDoesNotLaunchWhenTheSocketPathWouldNotFit() {
        let long = containerData.path + "/" + String(repeating: "d", count: 80)
        XCTAssertThrowsError(try makeRelay(containerData: long).listenPath(forTarget: agent.path)) {
            guard case .listenPathTooLong = $0 as? SASSHAgentRelay.RelayError else { return XCTFail("\($0)") }
        }
        XCTAssertEqual(launches.count, 0)
    }

    // MARK: - Names and messages

    func testSocketNameIsEightHexDigitsAndDiffersPerProcessAndTarget() {
        let name = SASSHAgentRelay.socketName(target: "/a/agent.sock", processIdentifier: 100)
        XCTAssertNotNil(name.range(of: "^[0-9a-f]{8}$", options: .regularExpression))
        XCTAssertEqual(name, SASSHAgentRelay.socketName(target: "/a/agent.sock", processIdentifier: 100))
        XCTAssertNotEqual(name, SASSHAgentRelay.socketName(target: "/a/agent.sock", processIdentifier: 101))
        XCTAssertNotEqual(name, SASSHAgentRelay.socketName(target: "/b/agent.sock", processIdentifier: 100))
    }

    func testNotAllowedMessageQuotesTheLineToAdd() {
        XCTAssertEqual(SASSHAgentRelay.RelayError.allowlistLine(for: "/Users/tester/x/agent.sock", realHome: "/Users/tester"),
                       "~/x/agent.sock")
        XCTAssertEqual(SASSHAgentRelay.RelayError.allowlistLine(for: "/opt/agent.sock", realHome: "/Users/tester"),
                       "/opt/agent.sock")
        let message = SASSHAgentRelay.RelayError.helperRefused(reason: "not-allowed", target: "/opt/agent.sock", detail: "")
            .errorDescription ?? ""
        XCTAssertTrue(message.contains("/opt/agent.sock"))
        XCTAssertTrue(message.contains("ssh-agent-relay.allow"))
    }

    func testEveryRefusalAndFailureHasItsOwnMessage() {
        let errors: [SASSHAgentRelay.RelayError] = [
            .helperUnavailable, .helperNotInstalled, .helperOutdated, .relaunchRequired, .listenPathTooLong("/p"),
            .listenPathBlocked("/p"), .listenFailed("x"), .startTimedOut, .launchFailed("x"), .helperExited(detail: "x"),
            .helperRefused(reason: "not-allowed", target: "/t", detail: ""),
            .helperRefused(reason: "no-target", target: "/t", detail: ""),
            .helperRefused(reason: "not-owned", target: "/t", detail: ""),
            .helperRefused(reason: "socket-module", target: "/t", detail: ""),
            .helperRefused(reason: "bind", target: "/t", detail: "could not listen"),
        ]
        let messages = errors.compactMap(\.errorDescription)
        XCTAssertEqual(messages.count, errors.count)
        XCTAssertEqual(Set(messages).count, errors.count)
    }

    // MARK: - Helpers

    private func wait(until condition: @escaping () -> Bool, timeout: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            usleep(20_000)
        }
        return condition()
    }
}

// MARK: - Test doubles

private final class Locked<Value> {
    private let lock = NSLock()
    private var stored: Value
    init(_ value: Value) { stored = value }
    var value: Value { lock.lock(); defer { lock.unlock() }; return stored }
    func mutate(_ body: (inout Value) -> Void) { lock.lock(); body(&stored); lock.unlock() }
}

/// Starts the helper with `Process` and remembers every launch.
private final class HelperLaunches {
    private let state = Locked<(processes: [Process], inputs: [FileHandle], exits: Int)>(([], [], 0))

    var count: Int { state.value.processes.count }
    var exits: Int { state.value.exits }
    var processes: [Process] { state.value.processes }

    lazy var launcher: SASSHAgentRelay.Launcher = { [unowned self] script, arguments, listeningSocket, onExit in
        let process = Process()
        let input = Pipe(), status = Pipe()
        process.executableURL = script
        process.arguments = arguments
        process.standardInput = input
        process.standardOutput = listeningSocket
        process.standardError = status
        process.terminationHandler = { [weak self] _ in
            self?.state.mutate { $0.exits += 1 }
            onExit()
        }
        try process.run()
        try? status.fileHandleForWriting.close()
        try? input.fileHandleForReading.close()
        self.state.mutate { $0.processes.append(process); $0.inputs.append(input.fileHandleForWriting) }
        return SASSHAgentRelay.Helper(status: status.fileHandleForReading,
                                      closeInput: { try? input.fileHandleForWriting.close() })
    }

    func closeInputs() {
        state.value.inputs.forEach { try? $0.close() }
    }

    func stopAll() {
        closeInputs()
        for process in state.value.processes where process.isRunning {
            process.terminate()
        }
    }
}

private enum SocketError: Error { case failed(String, Int32) }

private func makeAddress(_ path: String) throws -> sockaddr_un {
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let bytes = Array(path.utf8)
    guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else { throw SocketError.failed("path too long", 0) }
    withUnsafeMutableBytes(of: &address.sun_path) { buffer in
        buffer.copyBytes(from: bytes)
    }
    return address
}

private func withSockaddr<T>(_ address: inout sockaddr_un, _ body: (UnsafePointer<sockaddr>, socklen_t) -> T) -> T {
    withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { body($0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
    }
}

/// A stand-in agent: answers every message with "pong:" + the message.
private final class FakeAgent {
    let path: String
    private let descriptor: Int32
    private let open = Locked<Int>(0)

    /// Connections the agent has accepted and not yet seen closed.
    var openConnections: Int { open.value }

    init(path: String) throws {
        self.path = path
        descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        var address = try makeAddress(path)
        guard withSockaddr(&address, { bind(descriptor, $0, $1) }) == 0 else { throw SocketError.failed("bind", errno) }
        guard listen(descriptor, 8) == 0 else { throw SocketError.failed("listen", errno) }
        let listening = descriptor
        let open = self.open
        Thread.detachNewThread {
            while true {
                let client = accept(listening, nil, nil)
                if client < 0 { return }
                open.mutate { $0 += 1 }
                Thread.detachNewThread {
                    defer { open.mutate { $0 -= 1 } }
                    var buffer = [UInt8](repeating: 0, count: 4096)
                    while true {
                        let count = read(client, &buffer, buffer.count)
                        if count <= 0 { break }
                        let reply = Array("pong:".utf8) + buffer[0..<count]
                        _ = reply.withUnsafeBytes { write(client, $0.baseAddress, reply.count) }
                    }
                    Darwin.close(client)
                }
            }
        }
    }

    func close() {
        Darwin.close(descriptor)
        unlink(path)
    }
}

private final class SocketClient {
    private let descriptor: Int32

    init(path: String) throws {
        descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        var address = try makeAddress(path)
        guard withSockaddr(&address, { connect(descriptor, $0, $1) }) == 0 else {
            let code = errno
            Darwin.close(descriptor)
            throw SocketError.failed("connect", code)
        }
        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    }

    func send(_ text: String) throws {
        let bytes = Array(text.utf8)
        guard bytes.withUnsafeBytes({ write(descriptor, $0.baseAddress, bytes.count) }) == bytes.count else {
            throw SocketError.failed("write", errno)
        }
    }

    func receive() throws -> String {
        var buffer = [UInt8](repeating: 0, count: 4096)
        let count = read(descriptor, &buffer, buffer.count)
        guard count > 0 else { throw SocketError.failed("read", errno) }
        return String(decoding: buffer[0..<count], as: UTF8.self)
    }

    func close() { Darwin.close(descriptor) }

    static func exchange(_ text: String, at path: String) throws -> String {
        let client = try SocketClient(path: path)
        defer { client.close() }
        try client.send(text)
        return try client.receive()
    }
}
