//
//  SASSHTunnelAskpassTests.swift
//  Unit Tests
//
//  Created by the Sequel Ace team on September 1, 2026.
//  Copyright (c) 2026 Sequel-Ace. All rights reserved.
//

import XCTest

/// The askpass assistant's decisions, pinned against a fake channel (Step 3
/// of the SSH tunnel IPC plan). Each case mirrors a branch of the
/// Objective-C `main` it was lifted from.
final class SASSHTunnelAskpassTests: XCTestCase {

    private typealias Outcome = SASSHTunnelAskpass.Outcome

    private final class Channel {
        var connectAttempts = 0
        var connectFails = false
        var requests: [SASSHTunnelAuthRequest] = []
        var respond: (SASSHTunnelAuthRequest) throws -> SASSHTunnelAuthResponse = { _ in .refused }
        var logs: [String] = []

        func connect() throws -> SASSHTunnelAskpass.Transport {
            connectAttempts += 1
            if connectFails { throw Failure() }
            return { request in
                self.requests.append(request)
                return try self.respond(request)
            }
        }
        struct Failure: Error {}
    }

    private var channel = Channel()

    private let baseEnvironment = [
        "SP_PASSWORD_METHOD": "1",
        "SP_CONNECTION_NAME": "NKQ4HJ66PX.sequel-ace.SequelAce-1",
        "SP_CONNECTION_VERIFY_HASH": "hash-1",
    ]

    private func run(_ argument: String?, environment: [String: String]? = nil) -> Outcome {
        SASSHTunnelAskpass.run(argument: argument, environment: environment ?? baseEnvironment,
                               connect: channel.connect, log: { self.channel.logs.append($0) })
    }

    // MARK: - Preconditions

    func testNoPasswordMethodExitsWithoutConnecting() {
        XCTAssertEqual(run("host's password:", environment: [:]), Outcome(output: nil, exitCode: 1))
        XCTAssertEqual(channel.connectAttempts, 0)
    }

    func testNoArgumentExitsWithoutConnecting() {
        XCTAssertEqual(run(nil), Outcome(output: nil, exitCode: 1))
        XCTAssertEqual(channel.connectAttempts, 0)
    }

    // MARK: - Questions

    func testQuestionIsAnsweredYesOrNo() {
        channel.respond = { _ in .answer(true) }
        XCTAssertEqual(run("Are you sure you want to continue connecting (yes/no/[fingerprint])? "), Outcome(output: "yes", exitCode: 0))
        channel.respond = { _ in .answer(false) }
        XCTAssertEqual(run("Are you sure you want to continue connecting (yes/no)? "), Outcome(output: "no", exitCode: 0))
        XCTAssertEqual(channel.requests, [
            .question("Are you sure you want to continue connecting (yes/no/[fingerprint])? "),
            .question("Are you sure you want to continue connecting (yes/no)? "),
        ])
    }

    func testQuestionTakesPrecedenceOverAPasswordLookingPrompt() {
        channel.respond = { _ in .answer(true) }
        XCTAssertEqual(run("Reset password: continue (yes/no)?").output, "yes")
        XCTAssertEqual(channel.requests.count, 1)
        if case .question = channel.requests[0] {} else { XCTFail("expected a question") }
    }

    func testQuestionFailsClosedWhenTheAppIsUnreachable() {
        channel.connectFails = true
        XCTAssertEqual(run("continue (yes/no)?"), Outcome(output: nil, exitCode: 1))
        XCTAssertEqual(channel.logs, ["SSH Tunnel: unable to connect to Sequel Ace to show SSH question"])
    }

    func testQuestionFailsClosedOnATransportErrorOrARefusal() {
        channel.respond = { _ in throw Channel.Failure() }
        XCTAssertEqual(run("continue (yes/no)?"), Outcome(output: nil, exitCode: 1))
        channel.respond = { _ in .refused }
        XCTAssertEqual(run("continue (yes/no)?"), Outcome(output: nil, exitCode: 1))
    }

    // MARK: - The SSH password

    func testPasswordIsFetchedFromTheAppWithTheHash() {
        channel.respond = { _ in .secret("hunter2") }
        XCTAssertEqual(run("me@bastion's password: "), Outcome(output: "hunter2", exitCode: 0))
        XCTAssertEqual(channel.requests, [.password(verificationHash: "hash-1")])
        XCTAssertEqual(channel.connectAttempts, 1)
    }

    func testPasswordPromptMatchesCaseInsensitively() {
        channel.respond = { _ in .secret("pw") }
        XCTAssertEqual(run("PASSWORD:").output, "pw")
    }

    func testPasswordNeedsBothConnectionDetails() {
        var environment = baseEnvironment
        environment.removeValue(forKey: "SP_CONNECTION_VERIFY_HASH")
        XCTAssertEqual(run("password:", environment: environment), Outcome(output: nil, exitCode: 1))
        environment = baseEnvironment
        environment.removeValue(forKey: "SP_CONNECTION_NAME")
        XCTAssertEqual(run("password:", environment: environment), Outcome(output: nil, exitCode: 1))
        XCTAssertEqual(channel.connectAttempts, 0)
        XCTAssertEqual(channel.logs.last, "SSH Tunnel: internal authentication specified but insufficient details supplied")
    }

    func testPasswordFailsClosedWhenTheAppIsUnreachable() {
        channel.connectFails = true
        XCTAssertEqual(run("password:"), Outcome(output: nil, exitCode: 1))
        XCTAssertEqual(channel.logs, ["SSH Tunnel: unable to connect to Sequel Ace for internal authentication"])
    }

    func testPasswordTransportErrorFailsClosedWithoutTheFallback() {
        // Only an explicit refusal may reach the GUI fallback; a broken channel
        // must not open a second connection and possibly print a secret.
        channel.respond = { request in
            if case .password = request { throw Channel.Failure() }
            return .secret("must-not-be-printed")
        }
        XCTAssertEqual(run("me@bastion's password: "), Outcome(output: nil, exitCode: 1))
        XCTAssertEqual(channel.requests, [.password(verificationHash: "hash-1")])
        XCTAssertEqual(channel.connectAttempts, 1)
        XCTAssertTrue(channel.logs.last?.contains("unable to obtain the password") == true)
    }

    func testUnexpectedReplyKindToThePasswordRequestFailsClosed() {
        channel.respond = { _ in .answer(true) }
        XCTAssertEqual(run("me@bastion's password: "), Outcome(output: nil, exitCode: 1))
        XCTAssertEqual(channel.requests.count, 1)
    }

    func testHeldPasswordMissFallsBackToTheGUIPromptWithTheDirectMessage() {
        channel.respond = { request in
            if case .query(let text, _) = request { return .secret("typed:" + text) }
            return .refused
        }
        let outcome = run("me@bastion's password: ")
        let expected = String(format: NSLocalizedString("The SSH password could not be loaded; please enter the SSH password for %@:", comment: ""), "NKQ4HJ66PX.sequel-ace.SequelAce-1")
        XCTAssertEqual(outcome, Outcome(output: "typed:" + expected, exitCode: 0))
        XCTAssertEqual(channel.requests, [.password(verificationHash: "hash-1"), .query(expected, verificationHash: "hash-1")])
        XCTAssertEqual(channel.connectAttempts, 2, "one connection per request, as the Objective-C original re-resolved its proxy")
        XCTAssertEqual(channel.logs, ["SSH Tunnel: unable to successfully request password from Sequel Ace for internal authentication"])
    }

    func testKeychainMissFallsBackWithTheKeychainMessage() {
        var environment = baseEnvironment
        environment["SP_PASSWORD_METHOD"] = "0"
        channel.respond = { request in
            if case .query(let text, _) = request { return .secret("typed:" + text) }
            return .refused
        }
        let outcome = run("password:", environment: environment)
        let expected = String(format: NSLocalizedString("The SSH password could not be loaded from the keychain; please enter the SSH password for %@:", comment: ""), "NKQ4HJ66PX.sequel-ace.SequelAce-1")
        XCTAssertEqual(outcome, Outcome(output: "typed:" + expected, exitCode: 0))
        XCTAssertEqual(channel.logs, ["SSH Tunnel: specified keychain password not found"])
    }

    func testFallbackPromptCancelExitsNonZero() {
        channel.respond = { _ in .refused }
        XCTAssertEqual(run("password:"), Outcome(output: nil, exitCode: 1))
        XCTAssertEqual(channel.requests.count, 2)
    }

    func testPasswordMethodNoneGoesStraightToTheGUIPromptWithTheOriginalText() {
        var environment = baseEnvironment
        environment["SP_PASSWORD_METHOD"] = "2"
        channel.respond = { _ in .secret("typed") }
        XCTAssertEqual(run("me@bastion's password: ", environment: environment), Outcome(output: "typed", exitCode: 0))
        XCTAssertEqual(channel.requests, [.query("me@bastion's password: ", verificationHash: "hash-1")])
    }

    func testNonNumericPasswordMethodReadsAsKeychainLikeIntegerValueDid() {
        var environment = baseEnvironment
        environment["SP_PASSWORD_METHOD"] = "keychain"
        channel.respond = { _ in .refused }
        _ = run("password:", environment: environment)
        XCTAssertEqual(channel.logs.first, "SSH Tunnel: specified keychain password not found")
    }

    // MARK: - Passphrases and everything else

    func testPassphraseQueryGoesToTheGUIPrompt() {
        channel.respond = { _ in .secret("pp") }
        XCTAssertEqual(run("Enter passphrase for key '/Users/me/.ssh/id_ed25519': "), Outcome(output: "pp", exitCode: 0))
        XCTAssertEqual(channel.requests, [.query("Enter passphrase for key '/Users/me/.ssh/id_ed25519': ", verificationHash: "hash-1")])
    }

    func testAnyOtherPromptGoesToTheGUIPromptToo() {
        channel.respond = { _ in .secret("123456") }
        XCTAssertEqual(run("Enter PASSCODE: ").output, "123456")
    }

    func testQueryRefusedExitsNonZeroWithoutOutput() {
        channel.respond = { _ in .refused }
        XCTAssertEqual(run("Enter passphrase for key '/k': "), Outcome(output: nil, exitCode: 1))
    }

    func testQueryNeedsTheHash() {
        var environment = baseEnvironment
        environment.removeValue(forKey: "SP_CONNECTION_VERIFY_HASH")
        XCTAssertEqual(run("Enter passphrase for key '/k': ", environment: environment), Outcome(output: nil, exitCode: 1))
        XCTAssertEqual(channel.connectAttempts, 0)
        XCTAssertEqual(channel.logs, ["SSH Tunnel: key passphrase authentication required but insufficient details supplied to connect to GUI"])
    }

    func testQueryFailsClosedWhenTheAppIsUnreachableOrTheTransportFails() {
        channel.connectFails = true
        XCTAssertEqual(run("Enter passphrase for key '/k': "), Outcome(output: nil, exitCode: 1))
        channel = Channel()
        channel.respond = { _ in throw Channel.Failure() }
        XCTAssertEqual(run("Enter passphrase for key '/k': "), Outcome(output: nil, exitCode: 1))
    }
}
