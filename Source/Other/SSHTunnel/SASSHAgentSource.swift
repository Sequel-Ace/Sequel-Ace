//
//  SASSHAgentSource.swift
//  Sequel Ace
//
//  Created by the Sequel Ace team on October 10, 2026.
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

/// Which SSH agent a tunnel authenticates with, and everything decided from
/// that choice before ssh is launched.
///
/// The app is sandboxed, so ssh cannot open an agent's socket directly; a
/// non-`off` source is reached through `SASSHAgentRelay`. This type only
/// decides *which* socket and *which* ssh options — it is pure apart from
/// `lookUpAutomaticAgent`, which runs `ssh -G`.
///
/// App and Unit Tests targets.
struct SASSHAgentSource: Equatable {

    enum Kind: String, CaseIterable {
        case off
        /// Whatever ssh itself would use for the host: `IdentityAgent` from
        /// the active config, else `SSH_AUTH_SOCK`.
        case automatic
        /// The app's inherited `SSH_AUTH_SOCK` (launchd's ssh-agent).
        case system
        case onePassword = "1password"
        case custom
    }

    var kind: Kind
    /// Only meaningful for `.custom`. May start with `~`.
    var customPath: String

    init(kind: Kind, customPath: String = "") {
        self.kind = kind
        self.customPath = kind == .custom ? customPath : ""
    }

    static let off = SASSHAgentSource(kind: .off)

    // MARK: - Stored form

    /// Keep in sync with SPConstants.m (`SPSSHAgentDefaultSource`,
    /// `SPSSHAgentCustomSocketPath`, `SPSSHConfigFile`, `SPSSHClientPath`).
    enum DefaultsKey {
        static let defaultSource = "SSHAgentDefaultSource"
        static let customSocketPath = "SSHAgentCustomSocketPath"
        static let sshConfigFile = "ssh_config"
        static let sshClientPath = "SSHClientPath"
    }

    /// A stored source string. Empty or unrecognised is `nil`: for a
    /// connection that means "use the default", for the default it means off.
    static func stored(_ value: String, customPath: String) -> SASSHAgentSource? {
        guard let kind = Kind(rawValue: value.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        return SASSHAgentSource(kind: kind, customPath: customPath.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var storedValue: String { kind.rawValue }

    /// The source a connection actually uses: its own choice if it made one,
    /// otherwise the global default, otherwise off.
    static func effective(connectionSource: String, connectionCustomPath: String,
                          defaultSource: String, defaultCustomPath: String) -> SASSHAgentSource {
        if let own = stored(connectionSource, customPath: connectionCustomPath) { return own }
        return stored(defaultSource, customPath: defaultCustomPath) ?? .off
    }

    // MARK: - Connection strings

    /// The agent choice given to every connection that comes from a `mysql://`
    /// connection string. A connection string is untrusted input — it can
    /// arrive as a clicked link and connect without a confirmation — and an
    /// agent offers the user's keys to whatever SSH host the string names.
    /// So such a connection never uses an agent, not even the user's default;
    /// the user can choose one in the connection form afterwards.
    static let sourceForConnectionString = Kind.off.rawValue

    // MARK: - Target socket

    enum ResolveError: Error, Equatable {
        /// `SSH_AUTH_SOCK` is not set, so there is no system agent to reach.
        case noSystemAgent
        case emptyCustomPath
        /// The path is not absolute after `~` expansion.
        case relativePath(String)
        /// `IdentityAgent` names an environment variable, which cannot be
        /// resolved on ssh's behalf.
        case unsupportedIdentityAgent(String)
        case lookupFailed(String)
        case lookupTimedOut
        /// The SSH key is a public key, but no agent is in effect for the host
        /// after all, so nothing holds its private half.
        case publicKeyWithoutAgent(String)
    }

    /// What `ssh -G` says about the agent for one host.
    enum AutomaticAgent: Equatable {
        case path(String)
        /// `IdentityAgent none`.
        case disabled
        /// No `IdentityAgent`, or the literal `SSH_AUTH_SOCK`.
        case environment
    }

    static let onePasswordSocketSuffix = "/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"

    /// The agent socket to relay to, or `nil` when no relay is wanted. With a
    /// `nil` result nothing about how ssh is launched may change.
    ///
    /// `realHome` is the user's home directory, not the sandbox container.
    /// `automatic` is only called for `.automatic`.
    func targetPath(realHome: String, environment: [String: String],
                    automatic: () throws -> AutomaticAgent) throws -> String? {
        switch kind {
        case .off:
            return nil
        case .system:
            return try Self.systemAgentPath(environment)
        case .onePassword:
            return realHome + Self.onePasswordSocketSuffix
        case .custom:
            guard !customPath.isEmpty else { throw ResolveError.emptyCustomPath }
            return try Self.absolutePath(customPath, realHome: realHome)
        case .automatic:
            switch try automatic() {
            case .disabled: return nil
            case .environment: return try Self.systemAgentPath(environment)
            case .path(let path): return try Self.absolutePath(path, realHome: realHome)
            }
        }
    }

    private static func systemAgentPath(_ environment: [String: String]) throws -> String {
        guard let path = environment["SSH_AUTH_SOCK"], !path.isEmpty else { throw ResolveError.noSystemAgent }
        return path
    }

    private static func absolutePath(_ path: String, realHome: String) throws -> String {
        var expanded = path
        if expanded == "~" {
            expanded = realHome
        } else if expanded.hasPrefix("~/") {
            expanded = realHome + String(expanded.dropFirst(1))
        }
        guard expanded.hasPrefix("/") else { throw ResolveError.relativePath(path) }
        return expanded
    }

    /// Whether `path` names a public key file, which ssh can only use as an
    /// identity when an agent holds the matching private key.
    static func isPublicKeyFile(_ path: String) -> Bool {
        (path as NSString).pathExtension.lowercased() == "pub"
    }

    /// The user's home directory. `NSHomeDirectory()` is the container under
    /// the sandbox, so ask the password database.
    static func realHomeDirectory() -> String {
        if let entry = getpwuid(getuid()), let dir = entry.pointee.pw_dir {
            return String(cString: dir)
        }
        return NSHomeDirectory()
    }

    // MARK: - Automatic lookup

    /// Reads the `identityagent` line out of `ssh -G` output.
    static func parseAutomaticAgent(sshConfigDump: String) throws -> AutomaticAgent {
        for line in sshConfigDump.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.lowercased().hasPrefix("identityagent ") else { continue }
            var value = String(trimmed.dropFirst("identityagent ".count)).trimmingCharacters(in: .whitespaces)
            if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") {
                value = String(value.dropFirst().dropLast())
            }
            if value.isEmpty || value == "SSH_AUTH_SOCK" { return .environment }
            if value.lowercased() == "none" { return .disabled }
            if value.hasPrefix("$") { throw ResolveError.unsupportedIdentityAgent(value) }
            return .path(value)
        }
        return .environment
    }

    static let lookupTimeout: TimeInterval = 5

    /// Asks ssh which agent its config selects for a host. Blocks for up to
    /// `timeout`; call it off the main thread.
    static func lookUpAutomaticAgent(sshPath: String, configPath: String?, host: String, user: String, port: Int,
                                     timeout: TimeInterval = lookupTimeout) throws -> AutomaticAgent {
        var arguments = ["-G"]
        if let configPath, !configPath.isEmpty { arguments += ["-F", configPath] }
        if port > 0 { arguments += ["-p", String(port)] }
        arguments.append(user.isEmpty ? host : "\(user)@\(host)")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: sshPath)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        let finished = DispatchSemaphore(value: 0)
        var collected = Data()
        do {
            try process.run()
        } catch {
            throw ResolveError.lookupFailed(error.localizedDescription)
        }
        DispatchQueue.global(qos: .userInitiated).async {
            collected = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            finished.signal()
        }
        guard finished.wait(timeout: .now() + timeout) == .success else {
            process.terminate()
            throw ResolveError.lookupTimedOut
        }
        guard process.terminationStatus == 0 else {
            throw ResolveError.lookupFailed("ssh -G exited with status \(process.terminationStatus)")
        }
        return try parseAutomaticAgent(sshConfigDump: String(decoding: collected, as: UTF8.self))
    }

    // MARK: - ssh options

    /// The extra ssh options for a tunnel that authenticates through the relay
    /// socket at `listenPath`.
    ///
    /// Command-line options win over the config file, so `IdentityAgent` here
    /// also redirects one a user's own config points at the real socket.
    /// The two overrides apply only to the bundled default config, which sets
    /// `IdentitiesOnly yes` with a dummy identity (hiding every agent key)
    /// and `AddKeysToAgent yes` (dormant until an agent became reachable).
    /// A user's own config, and a connection that names a key file, keep
    /// ssh's normal rules — so a `.pub` key file pins one agent key.
    static func sshArguments(listenPath: String, usesBundledConfig: Bool, hasKeyFile: Bool) -> [String] {
        var arguments = ["-o", "IdentityAgent=\"\(listenPath)\""]
        if usesBundledConfig {
            if !hasKeyFile { arguments += ["-o", "IdentitiesOnly=no"] }
            arguments += ["-o", "AddKeysToAgent=no"]
        }
        return arguments
    }
}
