//
//  SASSHTunnelAuthMessage.swift
//  Sequel Ace
//
//  Created by the Sequel Ace team on September 1, 2026.
//  Copyright (c) 2026 Sequel-Ace. All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person
//  obtaining a copy of this software and associated documentation
//  files (the "Software"), to deal in the Software without
//  restriction, including without limitation the rights to use,
//  copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the
//  Software is furnished to do so, subject to the following
//  conditions:
//
//  The above copyright notice and this permission notice shall be
//  included in all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
//  EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
//  OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
//  NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
//  HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
//  WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
//  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
//  OTHER DEALINGS IN THE SOFTWARE.
//
//  More info at <https://github.com/Sequel-Ace/Sequel-Ace>

import Foundation

// The wire contract between the SSH tunnel and its askpass assistant —
// Step 2 of docs/development/ssh-tunnel-xpc-migration-plan.md.
//
// Compiled into the app, the SequelAceTunnelAssistant tool and the Unit
// Tests target, so: pure Foundation, no project Objective-C types, and
// nothing here needs to be `public` (the assistant's Objective-C `main`
// never touches these types directly).

/// The one thing an askpass launch asks the app. ssh execs the assistant
/// once per prompt, so a connection carries exactly one request and one
/// response.
enum SASSHTunnelAuthRequest: Equatable {
    /// A yes/no question — host key mismatches and the like.
    case question(String)
    /// The SSH password the app holds (in memory or in the keychain).
    case password(verificationHash: String)
    /// A key passphrase, a SecurID code, or any other prompt ssh raises.
    case query(String, verificationHash: String)
}

enum SASSHTunnelAuthResponse: Equatable {
    /// The answer to a `question`.
    case answer(Bool)
    /// The secret for a `password` or `query` request.
    case secret(String)
    /// No secret: wrong hash, nothing stored, or the user cancelled. The
    /// assistant exits non-zero (or, for a keychain miss, re-asks through the
    /// GUI) — never prints an empty line for ssh to read as an empty password.
    case refused
}

enum SASSHTunnelAuthWireError: Error, Equatable {
    case malformed
    case unsupportedVersion(Int)
    case unknownKind(String)
    case missingField(String)
}

/// Line-delimited JSON: one object per line, no raw newlines inside a line
/// (JSON escapes them, and ssh prompts do contain them). Keys are sorted so
/// the encoding is byte-stable and the fixtures in the tests can pin it.
///
/// Every message carries `v`, currently 1. A reader refuses any other
/// version rather than guessing.
enum SASSHTunnelAuthWire {

    static let version = 1

    // MARK: Encoding

    static func encode(_ request: SASSHTunnelAuthRequest) -> Data {
        switch request {
        case .question(let text):
            return encode(["kind": "question", "text": text])
        case .password(let verificationHash):
            return encode(["kind": "password", "hash": verificationHash])
        case .query(let text, let verificationHash):
            return encode(["kind": "query", "text": text, "hash": verificationHash])
        }
    }

    static func encode(_ response: SASSHTunnelAuthResponse) -> Data {
        switch response {
        case .answer(let answer):
            return encode(["kind": "answer", "answer": answer])
        case .secret(let secret):
            return encode(["kind": "secret", "secret": secret])
        case .refused:
            return encode(["kind": "refused"])
        }
    }

    private static func encode(_ fields: [String: Any]) -> Data {
        var object = fields
        object["v"] = version
        // Only strings, bools and an Int go in, so serialization cannot fail.
        var data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
        data.append(0x0A)
        return data
    }

    // MARK: Decoding

    static func decodeRequest(_ line: Data) throws -> SASSHTunnelAuthRequest {
        let object = try decodeObject(line)
        switch try kind(of: object) {
        case "question":
            return .question(try string("text", in: object))
        case "password":
            return .password(verificationHash: try string("hash", in: object))
        case "query":
            return .query(try string("text", in: object), verificationHash: try string("hash", in: object))
        case let other:
            throw SASSHTunnelAuthWireError.unknownKind(other)
        }
    }

    static func decodeResponse(_ line: Data) throws -> SASSHTunnelAuthResponse {
        let object = try decodeObject(line)
        switch try kind(of: object) {
        case "answer":
            return .answer(try bool("answer", in: object))
        case "secret":
            return .secret(try string("secret", in: object))
        case "refused":
            return .refused
        case let other:
            throw SASSHTunnelAuthWireError.unknownKind(other)
        }
    }

    private static func decodeObject(_ line: Data) throws -> [String: Any] {
        var trimmed = line
        while trimmed.last == 0x0A || trimmed.last == 0x0D { trimmed.removeLast() }
        guard !trimmed.isEmpty,
              let parsed = try? JSONSerialization.jsonObject(with: trimmed),
              let object = parsed as? [String: Any] else {
            throw SASSHTunnelAuthWireError.malformed
        }
        let version = try int("v", in: object)
        guard version == Self.version else { throw SASSHTunnelAuthWireError.unsupportedVersion(version) }
        return object
    }

    private static func kind(of object: [String: Any]) throws -> String {
        try string("kind", in: object)
    }

    private static func string(_ key: String, in object: [String: Any]) throws -> String {
        guard let value = object[key] as? String else { throw SASSHTunnelAuthWireError.missingField(key) }
        return value
    }

    // JSONSerialization hands back NSNumber for every scalar, and Swift's
    // bridging happily reads 1 as true and true as 1. A mistyped field must
    // fail, not coerce (Codex review on the wire format), so the underlying
    // JSON type is checked: a Bool must be a JSON boolean, an Int a JSON
    // integer.

    private static func bool(_ key: String, in object: [String: Any]) throws -> Bool {
        guard let number = object[key] as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else {
            throw SASSHTunnelAuthWireError.missingField(key)
        }
        return number.boolValue
    }

    private static func int(_ key: String, in object: [String: Any]) throws -> Int {
        guard let number = object[key] as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              !CFNumberIsFloatType(number) else {
            throw SASSHTunnelAuthWireError.missingField(key)
        }
        return number.intValue
    }
}
