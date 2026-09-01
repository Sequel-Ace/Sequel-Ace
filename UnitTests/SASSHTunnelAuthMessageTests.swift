//
//  SASSHTunnelAuthMessageTests.swift
//  Unit Tests
//
//  Created by the Sequel Ace team on September 1, 2026.
//  Copyright (c) 2026 Sequel-Ace. All rights reserved.
//

import XCTest

/// Pins the tunnel/assistant wire format byte for byte (Step 2 of the SSH
/// tunnel IPC plan). A fixture changing here means the format changed, which
/// means both ends must ship together.
final class SASSHTunnelAuthMessageTests: XCTestCase {

    private func line(_ text: String) -> Data { Data((text + "\n").utf8) }

    // MARK: - Request fixtures

    func testQuestionRequestEncoding() {
        let request = SASSHTunnelAuthRequest.question("Are you sure you want to continue connecting (yes/no/[fingerprint])? ")
        XCTAssertEqual(SASSHTunnelAuthWire.encode(request),
                       line(#"{"kind":"question","text":"Are you sure you want to continue connecting (yes/no/[fingerprint])? ","v":1}"#))
    }

    func testPasswordRequestEncoding() {
        XCTAssertEqual(SASSHTunnelAuthWire.encode(.password(verificationHash: "1234567890")),
                       line(#"{"hash":"1234567890","kind":"password","v":1}"#))
    }

    func testQueryRequestEncoding() {
        XCTAssertEqual(SASSHTunnelAuthWire.encode(.query("Enter passphrase for key '/Users/me/.ssh/id_ed25519': ", verificationHash: "42")),
                       line(#"{"hash":"42","kind":"query","text":"Enter passphrase for key '/Users/me/.ssh/id_ed25519': ","v":1}"#))
    }

    // MARK: - Response fixtures

    func testAnswerResponseEncoding() {
        XCTAssertEqual(SASSHTunnelAuthWire.encode(.answer(true)), line(#"{"answer":true,"kind":"answer","v":1}"#))
        XCTAssertEqual(SASSHTunnelAuthWire.encode(.answer(false)), line(#"{"answer":false,"kind":"answer","v":1}"#))
    }

    func testSecretResponseEncoding() {
        XCTAssertEqual(SASSHTunnelAuthWire.encode(.secret("hunter2")), line(#"{"kind":"secret","secret":"hunter2","v":1}"#))
    }

    func testRefusedResponseEncoding() {
        XCTAssertEqual(SASSHTunnelAuthWire.encode(.refused), line(#"{"kind":"refused","v":1}"#))
    }

    // MARK: - Round trips

    func testEveryRequestRoundTrips() throws {
        let requests: [SASSHTunnelAuthRequest] = [
            .question("q"),
            .password(verificationHash: "h"),
            .query("text", verificationHash: "h"),
        ]
        for request in requests {
            XCTAssertEqual(try SASSHTunnelAuthWire.decodeRequest(SASSHTunnelAuthWire.encode(request)), request)
        }
    }

    func testEveryResponseRoundTrips() throws {
        let responses: [SASSHTunnelAuthResponse] = [.answer(true), .answer(false), .secret("s"), .secret(""), .refused]
        for response in responses {
            XCTAssertEqual(try SASSHTunnelAuthWire.decodeResponse(SASSHTunnelAuthWire.encode(response)), response)
        }
    }

    func testMultilinePromptsAndUnicodeStayOnOneLine() throws {
        let prompt = "The authenticity of host 'db (10.0.0.1)' can't be established.\nED25519 key fingerprint is SHA256:abc/def+ghi=.\nAre you sure you want to continue connecting (yes/no/[fingerprint])? "
        let secret = "pässwörd \u{1F511} \"quoted\" back\\slash"
        let encodedPrompt = SASSHTunnelAuthWire.encode(.question(prompt))
        let encodedSecret = SASSHTunnelAuthWire.encode(.secret(secret))

        // Exactly one newline each, at the very end.
        XCTAssertEqual(encodedPrompt.filter { $0 == 0x0A }.count, 1)
        XCTAssertEqual(encodedPrompt.last, 0x0A)
        XCTAssertEqual(encodedSecret.filter { $0 == 0x0A }.count, 1)

        XCTAssertEqual(try SASSHTunnelAuthWire.decodeRequest(encodedPrompt), .question(prompt))
        XCTAssertEqual(try SASSHTunnelAuthWire.decodeResponse(encodedSecret), .secret(secret))
    }

    func testTrailingCarriageReturnAndMissingNewlineAreTolerated() throws {
        XCTAssertEqual(try SASSHTunnelAuthWire.decodeResponse(Data(#"{"kind":"refused","v":1}"#.utf8)), .refused)
        XCTAssertEqual(try SASSHTunnelAuthWire.decodeResponse(Data("{\"kind\":\"refused\",\"v\":1}\r\n".utf8)), .refused)
    }

    // MARK: - Refusals

    func testGarbageIsMalformed() {
        XCTAssertThrowsError(try SASSHTunnelAuthWire.decodeRequest(Data())) { XCTAssertEqual($0 as? SASSHTunnelAuthWireError, .malformed) }
        XCTAssertThrowsError(try SASSHTunnelAuthWire.decodeRequest(Data("not json\n".utf8))) { XCTAssertEqual($0 as? SASSHTunnelAuthWireError, .malformed) }
        XCTAssertThrowsError(try SASSHTunnelAuthWire.decodeRequest(Data("[1,2]\n".utf8))) { XCTAssertEqual($0 as? SASSHTunnelAuthWireError, .malformed) }
    }

    func testOtherVersionsAreRefusedNotGuessed() {
        XCTAssertThrowsError(try SASSHTunnelAuthWire.decodeRequest(line(#"{"kind":"question","text":"q","v":2}"#))) {
            XCTAssertEqual($0 as? SASSHTunnelAuthWireError, .unsupportedVersion(2))
        }
        XCTAssertThrowsError(try SASSHTunnelAuthWire.decodeResponse(line(#"{"kind":"refused"}"#))) {
            XCTAssertEqual($0 as? SASSHTunnelAuthWireError, .missingField("v"))
        }
    }

    func testUnknownKindsAreRefused() {
        XCTAssertThrowsError(try SASSHTunnelAuthWire.decodeRequest(line(#"{"kind":"disconnect","v":1}"#))) {
            XCTAssertEqual($0 as? SASSHTunnelAuthWireError, .unknownKind("disconnect"))
        }
        XCTAssertThrowsError(try SASSHTunnelAuthWire.decodeResponse(line(#"{"kind":"question","text":"q","v":1}"#))) {
            XCTAssertEqual($0 as? SASSHTunnelAuthWireError, .unknownKind("question"))
        }
    }

    func testMissingFieldsAreRefused() {
        XCTAssertThrowsError(try SASSHTunnelAuthWire.decodeRequest(line(#"{"kind":"password","v":1}"#))) {
            XCTAssertEqual($0 as? SASSHTunnelAuthWireError, .missingField("hash"))
        }
        XCTAssertThrowsError(try SASSHTunnelAuthWire.decodeRequest(line(#"{"hash":"h","kind":"query","v":1}"#))) {
            XCTAssertEqual($0 as? SASSHTunnelAuthWireError, .missingField("text"))
        }
        XCTAssertThrowsError(try SASSHTunnelAuthWire.decodeResponse(line(#"{"kind":"answer","v":1}"#))) {
            XCTAssertEqual($0 as? SASSHTunnelAuthWireError, .missingField("answer"))
        }
        XCTAssertThrowsError(try SASSHTunnelAuthWire.decodeResponse(line(#"{"kind":"secret","secret":null,"v":1}"#))) {
            XCTAssertEqual($0 as? SASSHTunnelAuthWireError, .missingField("secret"))
        }
        XCTAssertThrowsError(try SASSHTunnelAuthWire.decodeRequest(line(#"{"kind":"password","hash":5,"v":1}"#))) {
            XCTAssertEqual($0 as? SASSHTunnelAuthWireError, .missingField("hash"))
        }
    }

    // MARK: - Dispatch onto the service

    func testServiceHandlesEachRequestKind() {
        let tunnel = DispatchTunnel()
        let service = SASSHTunnelAuthService(source: tunnel, keychain: InertKeychain())

        tunnel.questionAnswer = true
        XCTAssertEqual(service.handle(.question("q")), .answer(true))
        XCTAssertEqual(tunnel.questionsAsked, ["q"])

        tunnel.heldPassword = "pw"
        XCTAssertEqual(service.handle(.password(verificationHash: DispatchTunnel.hash)), .secret("pw"))
        XCTAssertEqual(service.handle(.password(verificationHash: "wrong")), .refused)

        tunnel.passphraseAnswer = "pp"
        XCTAssertEqual(service.handle(.query("Enter PASSCODE:", verificationHash: DispatchTunnel.hash)), .secret("pp"))
        tunnel.passphraseAnswer = nil
        XCTAssertEqual(service.handle(.query("Enter PASSCODE:", verificationHash: DispatchTunnel.hash)), .refused)
    }
}

// MARK: - Fakes

private final class DispatchTunnel: NSObject, SASSHTunnelAuthSource {
    static let hash = "h"
    var verificationHash = DispatchTunnel.hash
    var heldPassword: String?
    var usesKeychainPassword = false
    var keychainItemName: String?
    var keychainItemAccount: String?
    var passwordPromptCancelled = false
    var questionAnswer = false
    var questionsAsked: [String] = []
    var passphraseAnswer: String?
    func promptForResponse(toQuestion question: String) -> Bool { questionsAsked.append(question); return questionAnswer }
    func promptForPassword(forQuery query: String) -> String? { passphraseAnswer }
}

private final class InertKeychain: NSObject, SAKeychainProviding {
    func add(password: String?, name: String?, account: String?) {}
    func add(password: String?, name: String?, account: String?, label: String?) {}
    func password(name: String?, account: String?) -> String? { nil }
    func deletePassword(name: String?, account: String?) {}
    func passwordExists(name: String?, account: String?) -> Bool { false }
    func updateItem(name: String?, account: String?, toName newName: String?, newAccount: String?, password: String?) {}
    func name(favoriteName: String?, id favoriteID: Any?) -> String? { nil }
    func account(user: String?, host: String?, database: String?) -> String? { nil }
    func sshName(favoriteName: String?, id favoriteID: Any?) -> String? { nil }
    func sshAccount(user: String?, host: String?) -> String? { nil }
}
