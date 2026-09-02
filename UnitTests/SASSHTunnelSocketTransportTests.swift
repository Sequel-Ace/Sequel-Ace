//
//  SASSHTunnelSocketTransportTests.swift
//  Unit Tests
//
//  Created by the Sequel Ace team on September 1, 2026.
//  Copyright (c) 2026 Sequel-Ace. All rights reserved.
//

import XCTest

/// Both ends of the socket transport, in-process over a socket in the test
/// runner's temporary directory (Step 3 of the SSH tunnel IPC plan). Covers
/// the wire contract end to end and every refusal path; peer validation
/// itself is Step 4's, exercised here only through the policy hooks.
final class SASSHTunnelSocketTransportTests: XCTestCase {

    private var servers: [SASSHTunnelSocketServer] = []

    override func tearDown() {
        servers.forEach { $0.close() }
        servers = []
        super.tearDown()
    }

    private func startServer(peerPolicy: @escaping SASSHTunnelSocketServer.PeerPolicy = { _ in true },
                             handler: @escaping SASSHTunnelSocketServer.Handler) throws -> SASSHTunnelSocketServer {
        let server = try SASSHTunnelSocketServer(directories: [NSTemporaryDirectory()], handler: handler, peerPolicy: peerPolicy)
        servers.append(server)
        return server
    }

    private static func echo(_ request: SASSHTunnelAuthRequest) -> SASSHTunnelAuthResponse {
        switch request {
        case .question(let text): return .answer(text.contains("yes"))
        case .password(let hash): return .secret("pw-" + hash)
        case .query(let text, let hash): return text.isEmpty ? .refused : .secret(text + "|" + hash)
        }
    }

    // MARK: - Happy path

    func testEveryRequestKindRoundTrips() throws {
        let server = try startServer(handler: Self.echo)
        let client = SASSHTunnelSocketClient(path: server.path)

        XCTAssertEqual(try client.send(.question("continue? yes")), .answer(true))
        XCTAssertEqual(try client.send(.question("continue?")), .answer(false))
        XCTAssertEqual(try client.send(.password(verificationHash: "42")), .secret("pw-42"))
        XCTAssertEqual(try client.send(.query("Enter passphrase for key '/k':", verificationHash: "42")),
                       .secret("Enter passphrase for key '/k':|42"))
        XCTAssertEqual(try client.send(.query("", verificationHash: "42")), .refused)
    }

    func testMultilinePromptSurvivesTheSocket() throws {
        let prompt = "line one\nline two\nAre you sure (yes/no)? "
        let server = try startServer { request in
            guard case .question(let text) = request else { return .refused }
            return .answer(text == prompt)
        }
        XCTAssertEqual(try SASSHTunnelSocketClient(path: server.path).send(.question(prompt)), .answer(true))
    }

    func testConcurrentConnectionsAreAllServed() throws {
        let server = try startServer(handler: Self.echo)
        let client = SASSHTunnelSocketClient(path: server.path)
        let results = SAAsyncResultBoxLite()
        DispatchQueue.concurrentPerform(iterations: 12) { index in
            let response = try? client.send(.password(verificationHash: "\(index)"))
            results.record(index: index, response: response)
        }
        for index in 0..<12 {
            XCTAssertEqual(results[index], .secret("pw-\(index)"), "connection \(index)")
        }
    }

    func testHandlerRunsOffTheAcceptLoopSoASlowPromptDoesNotBlockOthers() throws {
        let slowStarted = expectation(description: "slow request reached the handler")
        let release = DispatchSemaphore(value: 0)
        let server = try startServer { request in
            if case .question = request {
                slowStarted.fulfill()
                release.wait()
                return .answer(true)
            }
            return Self.echo(request)
        }
        let client = SASSHTunnelSocketClient(path: server.path)

        let slowDone = expectation(description: "slow request answered")
        DispatchQueue.global().async {
            XCTAssertEqual(try? client.send(.question("blocks")), .answer(true))
            slowDone.fulfill()
        }
        wait(for: [slowStarted], timeout: 5)

        // While the first connection is parked in its handler, another is served.
        XCTAssertEqual(try client.send(.password(verificationHash: "fast")), .secret("pw-fast"))

        release.signal()
        wait(for: [slowDone], timeout: 5)
    }

    // MARK: - The socket file

    func testSocketFileIsOwnerOnlyAndRemovedOnClose() throws {
        let server = try startServer(handler: Self.echo)
        var status = stat()
        XCTAssertEqual(stat(server.path, &status), 0)
        XCTAssertEqual(status.st_mode & S_IFMT, S_IFSOCK)
        XCTAssertEqual(status.st_mode & 0o777, 0o600)
        XCTAssertLessThanOrEqual(server.path.utf8.count, SASSHTunnelSocketIO.maximumPathLength)

        server.close()
        let deadline = Date().addingTimeInterval(3)
        while FileManager.default.fileExists(atPath: server.path) && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: server.path))

        XCTAssertThrowsError(try SASSHTunnelSocketClient(path: server.path).send(.question("q"))) { error in
            guard case SASSHTunnelSocketClient.Error.connectFailed = error else { return XCTFail("\(error)") }
        }
        XCTAssertNoThrow(server.close(), "closing twice is harmless")
    }

    func testStaleSocketsFromADeadProcessAreSweptButLiveOnesStay() throws {
        // A bound-then-closed socket is what a killed app leaves behind.
        let stale = NSTemporaryDirectory() + "ssh-deadbeef00.sock"
        unlink(stale)
        close(try rawListener(at: stale))
        XCTAssertTrue(FileManager.default.fileExists(atPath: stale))

        let live = try startServer(handler: Self.echo)
        let next = try startServer(handler: Self.echo)

        XCTAssertFalse(FileManager.default.fileExists(atPath: stale), "swept when the next server started")
        XCTAssertTrue(FileManager.default.fileExists(atPath: live.path), "the live socket survived the sweep")
        XCTAssertEqual(try SASSHTunnelSocketClient(path: live.path).send(.password(verificationHash: "a")), .secret("pw-a"))
        XCTAssertEqual(try SASSHTunnelSocketClient(path: next.path).send(.password(verificationHash: "b")), .secret("pw-b"))
    }

    func testTwoServersGetDistinctPaths() throws {
        let first = try startServer(handler: Self.echo)
        let second = try startServer(handler: Self.echo)
        XCTAssertNotEqual(first.path, second.path)
    }

    func testSocketNameShapeAndSweepRecognition() {
        let name = SASSHTunnelSocketServer.socketFileName()
        XCTAssertEqual(name.count, 15, "the path budget in the container tmp depends on this")
        XCTAssertTrue(SASSHTunnelSocketServer.isOwnSocketName(name))
        XCTAssertTrue(SASSHTunnelSocketServer.isOwnSocketName("ssh-deadbeef00.sock"), "pre-flip leftovers are still swept")
        XCTAssertFalse(SASSHTunnelSocketServer.isOwnSocketName("agent.sock"))
        XCTAssertFalse(SASSHTunnelSocketServer.isOwnSocketName("s-.sock"))
        XCTAssertFalse(SASSHTunnelSocketServer.isOwnSocketName("s-zz.sock"))
        // Exact widths only: neither shorter nor longer hex runs are ours.
        XCTAssertFalse(SASSHTunnelSocketServer.isOwnSocketName("s-1.sock"))
        XCTAssertFalse(SASSHTunnelSocketServer.isOwnSocketName("s-deadbee.sock"))
        XCTAssertFalse(SASSHTunnelSocketServer.isOwnSocketName("s-deadbeef0.sock"))
        XCTAssertFalse(SASSHTunnelSocketServer.isOwnSocketName("ssh-deadbeef.sock"))
        XCTAssertFalse(SASSHTunnelSocketServer.isOwnSocketName("ssh-deadbeef001.sock"))
        XCTAssertTrue(SASSHTunnelSocketServer.isOwnSocketName("s-deadbeef.sock"))
        XCTAssertFalse(SASSHTunnelSocketServer.isOwnSocketName("S-DEADBEEF.sock"), "lower-case hex, as generated")
    }

    func testDirectoryThatCannotFitTheNameIsSkippedAndNoneIsAnError() {
        let tooLong = "/" + String(repeating: "a", count: 110)
        XCTAssertThrowsError(try SASSHTunnelSocketServer(directories: [tooLong], handler: Self.echo)) { error in
            XCTAssertEqual(error as? SASSHTunnelSocketServer.Error, .noUsableDirectory)
        }
        XCTAssertNoThrow(try SASSHTunnelSocketServer(directories: [tooLong, NSTemporaryDirectory()], handler: Self.echo).close())
    }

    // MARK: - Refusals

    func testServerRejectingThePeerClosesWithoutAReply() throws {
        var handled = 0
        let server = try startServer(peerPolicy: { _ in false }) { request in handled += 1; return Self.echo(request) }
        XCTAssertThrowsError(try SASSHTunnelSocketClient(path: server.path).send(.password(verificationHash: "h"))) { error in
            XCTAssertEqual(error as? SASSHTunnelSocketClient.Error, .noReply)
        }
        XCTAssertEqual(handled, 0)
    }

    func testClientRejectingThePeerSendsNothing() throws {
        var handled = 0
        let server = try startServer { request in handled += 1; return Self.echo(request) }
        var client = SASSHTunnelSocketClient(path: server.path)
        var inspected = 0
        client.peerPolicy = { _ in inspected += 1; return false }
        XCTAssertThrowsError(try client.send(.password(verificationHash: "h"))) { error in
            XCTAssertEqual(error as? SASSHTunnelSocketClient.Error, .peerRejected)
        }
        XCTAssertEqual(inspected, 1)
        Thread.sleep(forTimeInterval: 0.1)
        XCTAssertEqual(handled, 0)
    }

    func testMalformedRequestIsDroppedAndTheServerKeepsServing() throws {
        var handled = 0
        let server = try startServer { request in handled += 1; return Self.echo(request) }

        let raw = try rawConnection(to: server.path)
        XCTAssertTrue(SASSHTunnelSocketIO.writeAll(raw, Data("this is not json\n".utf8)))
        XCTAssertNil(SASSHTunnelSocketIO.readLine(raw), "no reply for garbage — EOF")
        close(raw)
        XCTAssertEqual(handled, 0)

        XCTAssertEqual(try SASSHTunnelSocketClient(path: server.path).send(.password(verificationHash: "h")), .secret("pw-h"))
        XCTAssertEqual(handled, 1)
    }

    func testUnsupportedVersionIsRefusedNotGuessed() throws {
        let server = try startServer(handler: Self.echo)
        let raw = try rawConnection(to: server.path)
        XCTAssertTrue(SASSHTunnelSocketIO.writeAll(raw, Data((#"{"hash":"h","kind":"password","v":2}"# + "\n").utf8)))
        XCTAssertNil(SASSHTunnelSocketIO.readLine(raw))
        close(raw)
    }

    func testMalformedReplyIsAnErrorForTheClient() throws {
        // A listener that answers with nonsense.
        let path = NSTemporaryDirectory() + "sa-test-\(UUID().uuidString.prefix(8)).sock"
        let listener = try rawListener(at: path)
        defer { close(listener); unlink(path) }
        DispatchQueue.global().async {
            let client = accept(listener, nil, nil)
            guard client >= 0 else { return }
            _ = SASSHTunnelSocketIO.readLine(client)
            _ = SASSHTunnelSocketIO.writeAll(client, Data("{\"v\":1,\"kind\":\"nope\"}\n".utf8))
            close(client)
        }
        XCTAssertThrowsError(try SASSHTunnelSocketClient(path: path).send(.question("q"))) { error in
            XCTAssertEqual(error as? SASSHTunnelSocketClient.Error, .malformedReply(.unknownKind("nope")))
        }
    }

    func testMissingSocketIsAConnectFailure() {
        XCTAssertThrowsError(try SASSHTunnelSocketClient(path: NSTemporaryDirectory() + "sa-nonexistent.sock").send(.question("q"))) { error in
            XCTAssertEqual(error as? SASSHTunnelSocketClient.Error, .connectFailed(ENOENT))
        }
    }

    func testClientRefusesAPathThatCannotFitSunPath() {
        let tooLong = "/" + String(repeating: "b", count: 110)
        XCTAssertThrowsError(try SASSHTunnelSocketClient(path: tooLong).send(.question("q"))) { error in
            XCTAssertEqual(error as? SASSHTunnelSocketIO.Error, .pathTooLong(111))
        }
    }

    // MARK: - Raw socket helpers

    private func rawConnection(to path: String) throws -> Int32 {
        var address = try SASSHTunnelSocketIO.address(for: path)
        let fd = try XCTUnwrap(SASSHTunnelSocketIO.makeSocket())
        let rc = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        XCTAssertEqual(rc, 0, "connect errno \(errno)")
        return fd
    }

    private func rawListener(at path: String) throws -> Int32 {
        var address = try SASSHTunnelSocketIO.address(for: path)
        let fd = try XCTUnwrap(SASSHTunnelSocketIO.makeSocket())
        let rc = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        XCTAssertEqual(rc, 0, "bind errno \(errno)")
        XCTAssertEqual(listen(fd, 2), 0)
        return fd
    }
}

/// Lock-protected result collection for the concurrency test.
private final class SAAsyncResultBoxLite {
    private let lock = NSLock()
    private var responses: [Int: SASSHTunnelAuthResponse?] = [:]
    func record(index: Int, response: SASSHTunnelAuthResponse?) {
        lock.lock(); responses[index] = response; lock.unlock()
    }
    subscript(index: Int) -> SASSHTunnelAuthResponse? {
        lock.lock(); defer { lock.unlock() }
        return responses[index] ?? nil
    }
}
