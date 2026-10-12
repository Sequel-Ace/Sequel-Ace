//
//  SASSHTunnelPeerValidatorTests.swift
//  Unit Tests
//
//  Created by the Sequel Ace team on September 1, 2026.
//  Copyright (c) 2026 Sequel-Ace. All rights reserved.
//

import XCTest

/// Peer validation from a socket's audit token (Step 4 of the SSH tunnel
/// IPC plan), exercised against the one peer a unit test can always reach:
/// itself, over a socket pair. The test host is Xcode's `xctest` agent: its
/// identifier is a real signature to match against, but it need not chain
/// to `anchor apple` (a beta Xcode's does not) and it has no team, so the
/// requirement base and the team expectation are driven explicitly here.
/// The shipping `anchor apple generic` base was proven on the signed app
/// and assistant in the Step 0 spike.
final class SASSHTunnelPeerValidatorTests: XCTestCase {

    private var pair: [Int32] = []

    override func setUp() {
        super.setUp()
        var descriptors: [Int32] = [0, 0]
        XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors), 0)
        pair = descriptors
    }

    override func tearDown() {
        pair.forEach { close($0) }
        super.tearDown()
    }

    private var ownIdentifier: String {
        SASSHTunnelPeerValidator.ownIdentity().identifier ?? ""
    }

    /// A requirement this process satisfies, whatever certificate signed it.
    private var ownRequirement: String { "identifier \"\(ownIdentifier)\"" }

    // MARK: - The audit token

    func testAuditTokenIsReadFromTheSocket() throws {
        let token = try SASSHTunnelPeerValidator.auditToken(ofPeerOn: pair[0]).get()
        XCTAssertEqual(token.val.5, UInt32(getpid()), "the token's pid field is the peer — this process")
    }

    func testNotASocketHasNoAuditToken() {
        let fd = open("/dev/null", O_RDONLY)
        defer { close(fd) }
        XCTAssertEqual(SASSHTunnelPeerValidator.auditToken(ofPeerOn: fd).failure, .noAuditToken(ENOTSOCK))
        XCTAssertEqual(SASSHTunnelPeerValidator.validatePeerSignature(on: -1, requirementText: "anchor apple"), .noAuditToken(EBADF))
    }

    // MARK: - The code requirement

    func testThePeerSignatureIsCheckedAgainstTheRequirement() {
        XCTAssertFalse(ownIdentifier.isEmpty, "the test host is signed")
        XCTAssertNil(SASSHTunnelPeerValidator.validatePeerSignature(on: pair[0], requirementText: ownRequirement))
        XCTAssertNil(SASSHTunnelPeerValidator.validatePeerSignature(on: pair[1], requirementText: ownRequirement), "either end of the pair")
        XCTAssertEqual(SASSHTunnelPeerValidator.validatePeerSignature(on: pair[0], requirementText: "identifier \"\(ownIdentifier).nope\""),
                       .requirementFailed(OSStatus(errSecCSReqFailed)))
    }

    func testAnUnparseableRequirementIsARejection() {
        guard case .badRequirement? = SASSHTunnelPeerValidator.validatePeerSignature(on: pair[0], requirementText: "this is not a requirement") else {
            return XCTFail("expected badRequirement")
        }
    }

    func testRequirementText() {
        XCTAssertEqual(SASSHTunnelPeerValidator.requirement(identifier: nil), "anchor apple generic")
        XCTAssertEqual(SASSHTunnelPeerValidator.requirement(identifier: "SequelAceTunnelAssistant"),
                       "anchor apple generic and identifier \"SequelAceTunnelAssistant\"")
        XCTAssertEqual(SASSHTunnelPeerValidator.requirement(identifier: "x", base: "anchor apple"), "anchor apple and identifier \"x\"")
        XCTAssertEqual(SASSHTunnelPeerValidator.assistantIdentifier, "SequelAceTunnelAssistant")
    }

    func testTheShippingBaseRequirementParses() {
        // Not satisfiable by this host, but it must at least be a valid requirement.
        XCTAssertEqual(SASSHTunnelPeerValidator.validatePeerSignature(on: pair[0], requirementText: SASSHTunnelPeerValidator.requirement(identifier: "x")),
                       .requirementFailed(OSStatus(errSecCSReqFailed)))
    }

    // MARK: - The team check

    func testTeamMismatchIsARejectionEvenWhenTheSignaturePasses() {
        let ownTeam = SASSHTunnelPeerValidator.ownIdentity().teamIdentifier
        XCTAssertEqual(SASSHTunnelPeerValidator.validatePeer(on: pair[0], requirementText: ownRequirement, teamIdentifier: "ZZZZZZZZZZ"),
                       .teamMismatch(expected: "ZZZZZZZZZZ", actual: ownTeam))
    }

    func testTeamMatchPassesWhenThePeerHasThatTeam() throws {
        // Only meaningful when the host is signed with a team (not in CI's unsigned runner).
        guard let ownTeam = SASSHTunnelPeerValidator.ownIdentity().teamIdentifier else {
            throw XCTSkip("test host has no team identifier")
        }
        XCTAssertNil(SASSHTunnelPeerValidator.validatePeer(on: pair[0], requirementText: ownRequirement, teamIdentifier: ownTeam))
    }

    // MARK: - Policies

    func testPolicyRejectsThePeerOnTeamMismatchAndLogsWhy() {
        var logged: [String] = []
        let policy = SASSHTunnelPeerValidator.policy(ownTeamIdentifier: "ZZZZZZZZZZ", expectedIdentifier: nil, baseRequirement: ownRequirement) { logged.append($0) }
        XCTAssertFalse(policy(pair[0]))
        XCTAssertEqual(logged.count, 1)
        XCTAssertTrue(logged[0].contains("teamMismatch"), logged[0])
    }

    func testPolicyRejectsThePeerOnIdentifierMismatch() {
        var logged: [String] = []
        let policy = SASSHTunnelPeerValidator.policy(ownTeamIdentifier: "ZZZZZZZZZZ", expectedIdentifier: ownIdentifier + ".nope", baseRequirement: ownRequirement) { logged.append($0) }
        XCTAssertFalse(policy(pair[0]))
        XCTAssertTrue(logged[0].contains("requirementFailed"), "the signature is checked before the team")
    }

    func testPolicyWithoutAnOwnTeamAcceptsEveryoneAndWarnsOnce() {
        var logged: [String] = []
        let policy = SASSHTunnelPeerValidator.policy(ownTeamIdentifier: nil, expectedIdentifier: "anything") { logged.append($0) }
        XCTAssertTrue(policy(pair[0]))
        XCTAssertTrue(policy(pair[1]))
        XCTAssertTrue(policy(-1), "no check at all, so not even a socket is needed")
        XCTAssertEqual(logged.count, 1)
        XCTAssertTrue(logged[0].contains("no team identifier"))
    }

    func testShippingPoliciesAreBuiltFromThisProcessIdentity() {
        // On a signed build both reject an unrelated peer; on an unsigned test
        // host both degrade to accept-all. Either way they must not crash and
        // must agree with the underlying policy for this process's own team.
        let ownTeam = SASSHTunnelPeerValidator.ownIdentity().teamIdentifier
        let reference = SASSHTunnelPeerValidator.policy(ownTeamIdentifier: ownTeam, expectedIdentifier: nil) { _ in }
        XCTAssertEqual(SASSHTunnelPeerValidator.appPeerPolicy()(pair[0]), reference(pair[0]))
        // No assistant path to read, so the identifier half is dropped and the
        // policy is the team-only one — not a hardcoded-name policy.
        let assistantReference = SASSHTunnelPeerValidator.policy(ownTeamIdentifier: ownTeam, expectedIdentifier: nil) { _ in }
        XCTAssertEqual(SASSHTunnelPeerValidator.assistantPeerPolicy(assistantPath: nil) { _ in }(pair[0]),
                       assistantReference(pair[0]))
    }

    // MARK: - The shipped assistant's identifier (issue #2689)

    /// The bug that broke every tunnel in 6.0.0. `identifier` in a code
    /// requirement is an exact match, and the distribution pipeline re-signs
    /// the assistant — a bare Mach-O, so codesign derives the identifier from
    /// the file name and appends a hash. Shipped 6.0.0 carried
    /// `SequelAceTunnelAssistant-55554944e48d2df47eb331fcba5ba8a3b2434a63`
    /// against a hardcoded `SequelAceTunnelAssistant`, so the app rejected its
    /// own assistant on every connection. A development build is signed with
    /// the bare name, which is why no amount of local testing could show it.
    func testAShippedIdentifierIsNotTheProductNameSoItMustNotBeHardcoded() {
        let shipped = SASSHTunnelPeerValidator.assistantIdentifier + "-55554944e48d2df47eb331fcba5ba8a3b2434a63"
        XCTAssertNotEqual(shipped, SASSHTunnelPeerValidator.assistantIdentifier)

        // Requirements built from each are different, and the shipped one is
        // not satisfied by a requirement naming the bare product name.
        let hardcoded = SASSHTunnelPeerValidator.requirement(identifier: SASSHTunnelPeerValidator.assistantIdentifier)
        let actual = SASSHTunnelPeerValidator.requirement(identifier: shipped)
        XCTAssertNotEqual(hardcoded, actual)
        XCTAssertTrue(actual.contains(shipped))

        // Both must still be well-formed requirement strings.
        for text in [hardcoded, actual] {
            var requirement: SecRequirement?
            XCTAssertEqual(SecRequirementCreateWithString(text as CFString, [], &requirement), errSecSuccess, text)
        }
    }

    /// The expectation is read from a *binary*, not assumed and not taken
    /// from the running process — so whatever the pipeline chose for the
    /// assistant is what gets required.
    ///
    /// This bundle makes the distinction visible: the code under test reads
    /// the test bundle at `executablePath`, while `ownIdentity()` reads the
    /// running process, which is Apple's `xctest` host. They differ, and that
    /// is the whole point — the app must ask about the assistant's binary
    /// rather than about itself.
    func testTheIdentifierIsReadFromTheBinaryOnDiskNotTheRunningProcess() throws {
        let bundlePath = try XCTUnwrap(Bundle(for: Self.self).executablePath)
        guard let identifier = SASSHTunnelPeerValidator.signingIdentifier(ofBinaryAt: bundlePath) else {
            throw XCTSkip("this build is unsigned, so there is no identifier to read")
        }
        XCTAssertFalse(identifier.isEmpty)
        XCTAssertNotEqual(identifier, SASSHTunnelPeerValidator.ownIdentity().identifier,
                          "the disk read must describe the named binary, not whoever is running")
    }

    func testAMissingBinaryYieldsNoIdentifierRatherThanACrash() {
        XCTAssertNil(SASSHTunnelPeerValidator.signingIdentifier(ofBinaryAt: "/nonexistent/SequelAceTunnelAssistant"))
    }

    /// Without a readable identifier the policy must still admit our own
    /// team's Apple-signed code — failing open here, never closed, is the
    /// whole point: a locked-out assistant takes the tunnel with it.
    func testAnUnreadableAssistantPathDegradesToTheTeamCheckAndSaysSo() {
        var logged: [String] = []
        let policy = SASSHTunnelPeerValidator.assistantPeerPolicy(assistantPath: "/nonexistent/x") { logged.append($0) }
        let ownTeam = SASSHTunnelPeerValidator.ownIdentity().teamIdentifier
        let reference = SASSHTunnelPeerValidator.policy(ownTeamIdentifier: ownTeam, expectedIdentifier: nil) { _ in }
        XCTAssertEqual(policy(pair[0]), reference(pair[0]))
        XCTAssertTrue(logged.contains { $0.contains("could not read the assistant's signing identifier") },
                      "got \(logged)")
    }

    // MARK: - Through the transport

    func testServerPolicyRejectionReachesTheClientAsNoReply() throws {
        let server = try SASSHTunnelSocketServer(directories: [NSTemporaryDirectory()],
                                                 handler: { _ in .answer(true) },
                                                 peerPolicy: SASSHTunnelPeerValidator.policy(ownTeamIdentifier: "ZZZZZZZZZZ", expectedIdentifier: nil) { _ in })
        defer { server.close() }
        XCTAssertThrowsError(try SASSHTunnelSocketClient(path: server.path).send(.question("q"))) { error in
            XCTAssertEqual(error as? SASSHTunnelSocketClient.Error, .noReply)
        }
    }

    func testClientPolicyRejectionSendsNothing() throws {
        var served = 0
        let server = try SASSHTunnelSocketServer(directories: [NSTemporaryDirectory()], handler: { _ in served += 1; return .answer(true) })
        defer { server.close() }
        var client = SASSHTunnelSocketClient(path: server.path)
        client.peerPolicy = SASSHTunnelPeerValidator.policy(ownTeamIdentifier: "ZZZZZZZZZZ", expectedIdentifier: nil) { _ in }
        XCTAssertThrowsError(try client.send(.question("q"))) { error in
            XCTAssertEqual(error as? SASSHTunnelSocketClient.Error, .peerRejected)
        }
        Thread.sleep(forTimeInterval: 0.1)
        XCTAssertEqual(served, 0)
    }
}

private extension Result {
    var failure: Failure? {
        if case .failure(let failure) = self { return failure }
        return nil
    }
}
