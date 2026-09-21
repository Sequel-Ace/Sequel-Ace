//
//  SASSHTunnelPeerValidator.swift
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
import Security

/// Who is on the other end of the tunnel/assistant socket — Step 4 of the
/// SSH tunnel IPC plan, the replacement for the environment shared secret
/// as the primary check.
///
/// The peer's identity comes from the socket itself:
/// `getsockopt(LOCAL_PEERTOKEN)` yields the peer's audit token, which is
/// pid-race-free by construction and the same primitive XPC's own peer
/// validation is built on. `SecCodeCopyGuestWithAttributes` turns it into
/// the running code, which must (1) satisfy a code requirement — `anchor
/// apple generic`, plus the expected identifier when there is exactly one —
/// and (2) carry the same team identifier as *this* process. Team equality
/// is read from the signing information rather than expressed as a
/// `subject.OU` requirement so it holds across Developer ID, App Store and
/// development certificates alike.
///
/// Each side derives its expectations from its own signature (never
/// hardcoded: the Beta build has a different app identifier, and the
/// assistant's identifier is its product name). A build with no team
/// identifier — ad-hoc or unsigned local builds — cannot express the check;
/// it logs once and accepts, leaving the verification hash as the only
/// guard, exactly as before this step.
///
/// Compiled into the app, the assistant and the Unit Tests target.
enum SASSHTunnelPeerValidator {

    /// What a *locally built* assistant's code-signing identifier is: a bare
    /// executable, so codesign derives it from the product name rather than
    /// from `PRODUCT_BUNDLE_IDENTIFIER` (which the target sets, and which is
    /// ignored for a Mach-O with no Info.plist).
    ///
    /// Do not require this of a peer. The distribution pipeline re-signs the
    /// assistant with a hash suffix — shipped 6.0.0 carries
    /// `SequelAceTunnelAssistant-<40 hex>` — and `identifier` in a code
    /// requirement is an exact match, so demanding the bare name rejected
    /// every shipped assistant and broke every tunnel (issue #2689) while
    /// passing in every development build. `assistantPeerPolicy` reads the
    /// identifier off the binary instead; this constant is the documented
    /// default and what the tests pin.
    static let assistantIdentifier = "SequelAceTunnelAssistant"

    static let baseRequirement = "anchor apple generic"

    struct Identity: Equatable {
        var identifier: String?
        var teamIdentifier: String?
    }

    enum Failure: Error, Equatable {
        case noAuditToken(Int32)
        case noGuest(OSStatus)
        case badRequirement(OSStatus)
        case requirementFailed(OSStatus)
        case noSigningInformation(OSStatus)
        case teamMismatch(expected: String, actual: String?)
    }

    // MARK: - Policies

    /// The app's check on a connecting assistant.
    ///
    /// `assistantPath` is the binary the app is about to hand ssh as
    /// `SSH_ASKPASS`; its signing identifier is read from disk and required of
    /// the peer, because that identifier is not predictable — see
    /// `assistantIdentifier`. Deriving it here is what the rest of this file
    /// already does for the team: expectations come from a signature, never
    /// from a literal.
    ///
    /// When it cannot be read — an unsigned local build, a missing path — the
    /// identifier half is dropped and the peer is held to `anchor apple
    /// generic` plus this process's team. That is weaker than naming the
    /// binary but still admits only Apple-signed code of our own team, and it
    /// fails open rather than locking every tunnel out, which is the failure
    /// this whole change exists to prevent.
    ///
    /// `log` defaults to the app's own log; `SPSSHTunnel` passes a sink that
    /// also reaches the tunnel's debug window (issue #2689).
    static func assistantPeerPolicy(assistantPath: String?,
                                    log: @escaping (String) -> Void = { NSLog("%@", $0) }) -> (Int32) -> Bool {
        let expected = assistantPath.flatMap { signingIdentifier(ofBinaryAt: $0) }
        if expected == nil {
            log("SSH tunnel: could not read the assistant's signing identifier; admitting any Apple-signed peer of this team")
        }
        return policy(ownTeamIdentifier: ownIdentity().teamIdentifier,
                      expectedIdentifier: expected,
                      log: log)
    }

    /// The code-signing identifier recorded in the binary at `path`, or nil if
    /// it has none or cannot be read.
    static func signingIdentifier(ofBinaryAt path: String) -> String? {
        var staticCode: SecStaticCode?
        let created = SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &staticCode)
        guard created == errSecSuccess, let staticCode else { return nil }
        return try? identity(ofStaticCode: staticCode).get().identifier
    }

    /// The assistant's check on whatever answered at the socket path.
    static func appPeerPolicy() -> (Int32) -> Bool {
        policy(ownTeamIdentifier: ownIdentity().teamIdentifier, expectedIdentifier: nil)
    }

    /// A policy requiring the peer to be Apple-anchored, of `ownTeamIdentifier`,
    /// and (when given) of `expectedIdentifier`. Without an own team the
    /// check is impossible: the policy logs once and accepts every peer.
    static func policy(ownTeamIdentifier: String?,
                       expectedIdentifier: String?,
                       baseRequirement: String = SASSHTunnelPeerValidator.baseRequirement,
                       log: @escaping (String) -> Void = { NSLog("%@", $0) }) -> (Int32) -> Bool {
        guard let team = ownTeamIdentifier else {
            var warned = false
            let lock = NSLock()
            return { _ in
                lock.lock()
                if !warned {
                    warned = true
                    log("SSH tunnel: this build has no team identifier, so the socket peer cannot be validated; relying on the verification hash")
                }
                lock.unlock()
                return true
            }
        }
        let requirementText = requirement(identifier: expectedIdentifier, base: baseRequirement)
        return { fd in
            if let failure = validatePeer(on: fd, requirementText: requirementText, teamIdentifier: team) {
                log("SSH tunnel: socket peer rejected: \(failure)")
                return false
            }
            return true
        }
    }

    static func requirement(identifier: String?, base: String = SASSHTunnelPeerValidator.baseRequirement) -> String {
        guard let identifier else { return base }
        return base + " and identifier \"" + identifier + "\""
    }

    // MARK: - Checks

    /// nil when the peer on `fd` satisfies `requirementText` and carries
    /// `teamIdentifier`; otherwise the first failure.
    static func validatePeer(on fd: Int32, requirementText: String, teamIdentifier: String) -> Failure? {
        switch peerCode(on: fd) {
        case .failure(let failure):
            return failure
        case .success(let code):
            if let failure = check(code, against: requirementText) { return failure }
            switch identity(of: code) {
            case .failure(let failure):
                return failure
            case .success(let identity):
                guard identity.teamIdentifier == teamIdentifier else {
                    return .teamMismatch(expected: teamIdentifier, actual: identity.teamIdentifier)
                }
                return nil
            }
        }
    }

    /// The requirement half alone, for callers (and tests) that want to
    /// ask about the peer's signature without a team expectation.
    static func validatePeerSignature(on fd: Int32, requirementText: String) -> Failure? {
        switch peerCode(on: fd) {
        case .failure(let failure): return failure
        case .success(let code): return check(code, against: requirementText)
        }
    }

    static func auditToken(ofPeerOn fd: Int32) -> Result<audit_token_t, Failure> {
        var token = audit_token_t()
        var length = socklen_t(MemoryLayout<audit_token_t>.size)
        guard getsockopt(fd, SOL_LOCAL, LOCAL_PEERTOKEN, &token, &length) == 0 else {
            return .failure(.noAuditToken(errno))
        }
        return .success(token)
    }

    // MARK: - This process

    static func ownIdentity() -> Identity {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return Identity() }
        return (try? identity(of: code).get()) ?? Identity()
    }

    // MARK: - Security framework plumbing

    private static func peerCode(on fd: Int32) -> Result<SecCode, Failure> {
        switch auditToken(ofPeerOn: fd) {
        case .failure(let failure):
            return .failure(failure)
        case .success(var token):
            let tokenData = withUnsafeBytes(of: &token) { Data($0) }
            var code: SecCode?
            let status = SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributeAudit: tokenData] as CFDictionary, [], &code)
            guard status == errSecSuccess, let code else { return .failure(.noGuest(status)) }
            return .success(code)
        }
    }

    private static func check(_ code: SecCode, against requirementText: String) -> Failure? {
        var requirement: SecRequirement?
        let created = SecRequirementCreateWithString(requirementText as CFString, [], &requirement)
        guard created == errSecSuccess, let requirement else { return .badRequirement(created) }
        let validity = SecCodeCheckValidity(code, [], requirement)
        return validity == errSecSuccess ? nil : .requirementFailed(validity)
    }

    private static func identity(of code: SecCode) -> Result<Identity, Failure> {
        var staticCode: SecStaticCode?
        let copied = SecCodeCopyStaticCode(code, [], &staticCode)
        guard copied == errSecSuccess, let staticCode else { return .failure(.noSigningInformation(copied)) }
        return identity(ofStaticCode: staticCode)
    }

    static func identity(ofStaticCode staticCode: SecStaticCode) -> Result<Identity, Failure> {
        var information: CFDictionary?
        let status = SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information)
        guard status == errSecSuccess, let information = information as? [String: Any] else {
            return .failure(.noSigningInformation(status))
        }
        return .success(Identity(identifier: information[kSecCodeInfoIdentifier as String] as? String,
                                 teamIdentifier: information[kSecCodeInfoTeamIdentifier as String] as? String))
    }
}
