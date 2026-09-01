//
//  SASSHTunnelAuthServiceTests.swift
//  Unit Tests
//
//  Created by the Sequel Ace team on September 1, 2026.
//  Copyright (c) 2026 Sequel-Ace. All rights reserved.
//

import XCTest

/// The decisions the SSH tunnel makes for its askpass assistant, pinned
/// against a fake tunnel and an in-memory keychain — Step 1 of the SSH
/// tunnel IPC plan. None of this was testable while the logic sat on
/// `SPSSHTunnel` behind the connection.
final class SASSHTunnelAuthServiceTests: XCTestCase {

    private var source: FakeTunnel!
    private var keychain: FakeKeychain!
    private var service: SASSHTunnelAuthService!

    override func setUp() {
        super.setUp()
        source = FakeTunnel()
        keychain = FakeKeychain()
        service = SASSHTunnelAuthService(source: source, keychain: keychain)
    }

    // MARK: - Questions

    func testQuestionRunsThePromptAndReturnsItsAnswer() {
        source.questionAnswer = true
        XCTAssertTrue(service.response(forQuestion: "Are you sure you want to continue connecting (yes/no)?"))
        XCTAssertEqual(source.questionsAsked, ["Are you sure you want to continue connecting (yes/no)?"])

        source.questionAnswer = false
        XCTAssertFalse(service.response(forQuestion: "again?"))
    }

    func testQuestionNeedsNoVerificationHash() {
        // Parity: the answer is not a secret, and the legacy method never checked.
        source.questionAnswer = true
        XCTAssertTrue(service.response(forQuestion: "q"))
    }

    func testNilQuestionIsAnsweredNoWithoutPrompting() {
        source.questionAnswer = true
        XCTAssertFalse(service.response(forQuestion: nil))
        XCTAssertTrue(source.questionsAsked.isEmpty)
    }

    // MARK: - The SSH password

    func testHeldPasswordIsServedForTheRightHash() {
        source.heldPassword = "hunter2"
        XCTAssertEqual(service.password(verificationHash: FakeTunnel.hash), "hunter2")
    }

    func testPasswordIsRefusedForWrongOrMissingHash() {
        source.heldPassword = "hunter2"
        XCTAssertNil(service.password(verificationHash: "not the hash"))
        XCTAssertNil(service.password(verificationHash: ""))
        XCTAssertNil(service.password(verificationHash: nil))
    }

    func testNoHeldPasswordYieldsNil() {
        XCTAssertNil(service.password(verificationHash: FakeTunnel.hash))
    }

    func testKeychainModeResolvesTheItemAtAskTime() {
        source.usesKeychainPassword = true
        source.keychainItemName = "Sequel Ace SSHTunnel : Prod (42)"
        source.keychainItemAccount = "me@bastion"
        source.heldPassword = "ignored in keychain mode"
        keychain.items[FakeKeychain.key("Sequel Ace SSHTunnel : Prod (42)", "me@bastion")] = "from-keychain"

        XCTAssertEqual(service.password(verificationHash: FakeTunnel.hash), "from-keychain")
    }

    func testKeychainModeMissReturnsNil() {
        // The assistant turns this into its keychain-specific fallback prompt.
        source.usesKeychainPassword = true
        source.keychainItemName = "Sequel Ace SSHTunnel : Prod (42)"
        source.keychainItemAccount = "me@bastion"
        XCTAssertNil(service.password(verificationHash: FakeTunnel.hash))
    }

    func testKeychainModeStillRequiresTheHash() {
        source.usesKeychainPassword = true
        source.keychainItemName = "n"
        source.keychainItemAccount = "a"
        keychain.items[FakeKeychain.key("n", "a")] = "secret"
        XCTAssertNil(service.password(verificationHash: "wrong"))
    }

    // MARK: - Passphrases and other queries

    func testQueryIsRefusedWithoutTheHashAndNeverPrompts() {
        source.passphraseAnswer = "pp"
        XCTAssertNil(service.password(forQuery: "Enter passphrase for key '/k':", verificationHash: "wrong"))
        XCTAssertNil(service.password(forQuery: "Enter passphrase for key '/k':", verificationHash: nil))
        XCTAssertTrue(source.queriesPrompted.isEmpty)
    }

    func testNilQueryIsRefused() {
        XCTAssertNil(service.password(forQuery: nil, verificationHash: FakeTunnel.hash))
        XCTAssertTrue(source.queriesPrompted.isEmpty)
    }

    func testCancelledPromptRefusesLaterQueriesWithoutPrompting() {
        source.passwordPromptCancelled = true
        source.passphraseAnswer = "pp"
        XCTAssertNil(service.password(forQuery: "Enter passphrase for key '/k':", verificationHash: FakeTunnel.hash))
        XCTAssertTrue(source.queriesPrompted.isEmpty)
    }

    func testStoredPassphraseIsServedWithoutPrompting() {
        keychain.items[FakeKeychain.key("SSH", "/Users/me/.ssh/id_ed25519")] = "stored-pp"
        source.passphraseAnswer = "typed-pp"

        let result = service.password(forQuery: "Enter passphrase for key '/Users/me/.ssh/id_ed25519': ",
                                      verificationHash: FakeTunnel.hash)

        XCTAssertEqual(result, "stored-pp")
        XCTAssertTrue(source.queriesPrompted.isEmpty)
    }

    func testPassphraseQueryWithoutStoredItemPrompts() {
        source.passphraseAnswer = "typed-pp"
        let query = "Enter passphrase for key '/Users/me/.ssh/id_ed25519':"
        XCTAssertEqual(service.password(forQuery: query, verificationHash: FakeTunnel.hash), "typed-pp")
        XCTAssertEqual(source.queriesPrompted, [query])
    }

    func testStoredItemThatExistsButReadsBackNilFallsThroughToThePrompt() {
        // The exists-then-get shape: a read miss after an exists hit prompts.
        keychain.existsWithoutValue.insert(FakeKeychain.key("SSH", "/k"))
        source.passphraseAnswer = "typed-pp"
        XCTAssertEqual(service.password(forQuery: "Enter passphrase for key '/k':", verificationHash: FakeTunnel.hash), "typed-pp")
        XCTAssertEqual(source.queriesPrompted.count, 1)
    }

    func testNonPassphraseQueryPromptsAndNeverTouchesTheKeychain() {
        source.passphraseAnswer = "123456"
        XCTAssertEqual(service.password(forQuery: "Enter PASSCODE:", verificationHash: FakeTunnel.hash), "123456")
        XCTAssertEqual(source.queriesPrompted, ["Enter PASSCODE:"])
        XCTAssertTrue(keychain.lookups.isEmpty)
    }

    func testPromptCancelReturnsNil() {
        source.passphraseAnswer = nil
        XCTAssertNil(service.password(forQuery: "Enter passphrase for key '/k':", verificationHash: FakeTunnel.hash))
        XCTAssertEqual(source.queriesPrompted.count, 1)
    }

    func testPassphraseKeyNameExtraction() {
        XCTAssertEqual(SASSHTunnelAuthService.passphraseKeyName(in: "Enter passphrase for key '/a/b':"), "/a/b")
        XCTAssertEqual(SASSHTunnelAuthService.passphraseKeyName(in: "  Enter passphrase for key '/with space/id':  "), "/with space/id")
        XCTAssertNil(SASSHTunnelAuthService.passphraseKeyName(in: "Enter passphrase for key '/a/b': extra"))
        XCTAssertNil(SASSHTunnelAuthService.passphraseKeyName(in: "Password:"))
        XCTAssertNil(SASSHTunnelAuthService.passphraseKeyName(in: ""))
    }

    func testEmptyKeyNameIsNotLookedUp() {
        source.passphraseAnswer = "typed"
        XCTAssertEqual(service.password(forQuery: "Enter passphrase for key '':", verificationHash: FakeTunnel.hash), "typed")
        XCTAssertTrue(keychain.lookups.isEmpty)
    }

    // MARK: - Lifetime: the tunnel is gone

    func testEveryCallFailsClosedOnceTheTunnelIsReleased() {
        var tunnel: FakeTunnel? = FakeTunnel()
        tunnel?.questionAnswer = true
        tunnel?.heldPassword = "pw"
        tunnel?.passphraseAnswer = "pp"
        let orphaned = SASSHTunnelAuthService(source: tunnel!, keychain: keychain)
        tunnel = nil

        XCTAssertFalse(orphaned.response(forQuestion: "q"))
        XCTAssertNil(orphaned.password(verificationHash: FakeTunnel.hash))
        XCTAssertNil(orphaned.password(forQuery: "Enter passphrase for key '/k':", verificationHash: FakeTunnel.hash))
    }

    func testServiceDoesNotRetainTheTunnel() {
        var tunnel: FakeTunnel? = FakeTunnel()
        weak var weakTunnel = tunnel
        let held = SASSHTunnelAuthService(source: tunnel!, keychain: keychain)
        tunnel = nil
        XCTAssertNil(weakTunnel)
        _ = held
    }
}

// MARK: - Fakes

private final class FakeTunnel: NSObject, SASSHTunnelAuthSource {
    static let hash = "1234567890"

    var verificationHash: String = FakeTunnel.hash
    var heldPassword: String?
    var usesKeychainPassword = false
    var keychainItemName: String?
    var keychainItemAccount: String?
    var passwordPromptCancelled = false

    var questionAnswer = false
    var questionsAsked: [String] = []
    var passphraseAnswer: String?
    var queriesPrompted: [String] = []

    func promptForResponse(toQuestion question: String) -> Bool {
        questionsAsked.append(question)
        return questionAnswer
    }

    func promptForPassword(forQuery query: String) -> String? {
        queriesPrompted.append(query)
        return passphraseAnswer
    }
}

/// In-memory `SAKeychainProviding`: only the lookups the service uses do
/// anything; the rest are inert.
private final class FakeKeychain: NSObject, SAKeychainProviding {
    static func key(_ name: String?, _ account: String?) -> String { "\(name ?? "<nil>")|\(account ?? "<nil>")" }

    var items: [String: String] = [:]
    /// Keys that report as existing but read back nil.
    var existsWithoutValue: Set<String> = []
    private(set) var lookups: [String] = []

    func password(name: String?, account: String?) -> String? {
        lookups.append(Self.key(name, account))
        return items[Self.key(name, account)]
    }

    func passwordExists(name: String?, account: String?) -> Bool {
        lookups.append(Self.key(name, account))
        let key = Self.key(name, account)
        return items[key] != nil || existsWithoutValue.contains(key)
    }

    func add(password: String?, name: String?, account: String?) {}
    func add(password: String?, name: String?, account: String?, label: String?) {}
    func deletePassword(name: String?, account: String?) {}
    func updateItem(name: String?, account: String?, toName newName: String?, newAccount: String?, password: String?) {}
    func name(favoriteName: String?, id favoriteID: Any?) -> String? { nil }
    func account(user: String?, host: String?, database: String?) -> String? { nil }
    func sshName(favoriteName: String?, id favoriteID: Any?) -> String? { nil }
    func sshAccount(user: String?, host: String?) -> String? { nil }
}
