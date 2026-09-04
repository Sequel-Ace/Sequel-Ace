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
        let assistantReference = SASSHTunnelPeerValidator.policy(ownTeamIdentifier: ownTeam, expectedIdentifier: SASSHTunnelPeerValidator.assistantIdentifier) { _ in }
        XCTAssertEqual(SASSHTunnelPeerValidator.assistantPeerPolicy()(pair[0]), assistantReference(pair[0]))
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
