//
//  SASSHAgentRelay.swift
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


import CryptoKit
import Foundation

/// What a tunnel needs in order to authenticate through the relay: the ssh
/// options to append, and the relay's socket for `SSH_AUTH_SOCK` (ProxyJump
/// children do not see the parent's `-o` options). Inactive when the agent
/// turned out to be disabled for the host (`IdentityAgent none`).
@objc final class SASSHAgentLaunchPlan: NSObject {
    @objc let isActive: Bool
    @objc let sshArguments: [String]
    @objc let listenPath: String
    /// The agent socket being relayed. Part of the tunnel's multiplexing key,
    /// so connections that chose different agents never share a master.
    @objc let targetPath: String

    init(sshArguments: [String], listenPath: String, targetPath: String) {
        self.isActive = true
        self.sshArguments = sshArguments
        self.listenPath = listenPath
        self.targetPath = targetPath
    }

    private override init() {
        self.isActive = false
        self.sshArguments = []
        self.listenPath = ""
        self.targetPath = ""
    }

    static let inactive = SASSHAgentLaunchPlan()
}

/// Runs the SSH agent helper and hands tunnels its socket.
///
/// The sandbox stops ssh from opening an agent's socket, so a small script,
/// installed by the user in the app's Application Scripts folder, runs
/// outside the sandbox and relays connections to the agent. The app itself
/// opens the listening socket, inside its container, and hands it to the
/// helper as standard output — the helper never creates or removes a file.
/// One helper runs per agent socket and is shared by every tunnel. It is
/// started on demand each time a tunnel is about to launch ssh — first
/// connect or reconnect — and exits when the app closes its standard input,
/// so it cannot outlive the app.
///
/// Every call blocks for up to `startTimeout`; the tunnel calls from its own
/// launch thread, never the main thread.
///
/// App and Unit Tests targets.
@objc final class SASSHAgentRelay: NSObject {

    /// A running helper as the relay sees it.
    struct Helper {
        /// The helper's standard error: one status line, "ready" or
        /// "error <reason>", then diagnostics.
        let status: FileHandle
        /// Closes the helper's standard input, which makes it exit.
        let closeInput: () -> Void
    }

    /// Starts the installed script with `arguments` and `listeningSocket` as
    /// its standard output. `onExit` must be called once when it has exited,
    /// after which `status` reaches EOF.
    typealias Launcher = (_ script: URL, _ arguments: [String], _ listeningSocket: FileHandle,
                          _ onExit: @escaping () -> Void) throws -> Helper

    enum RelayError: Error, Equatable {
        case helperUnavailable
        case helperNotInstalled
        case helperOutdated
        /// The helper was installed or updated by this process; the app still
        /// holds the panel's write access to its folder until it relaunches.
        case relaunchRequired
        case listenPathTooLong(String)
        /// Something that is not a socket already sits at the socket's path.
        case listenPathBlocked(String)
        case listenFailed(String)
        case startTimedOut
        /// The helper printed `error <reason>`.
        case helperRefused(reason: String, target: String, detail: String)
        case helperExited(detail: String)
        case launchFailed(String)
    }

    static let startTimeout: TimeInterval = 5
    /// `sockaddr_un.sun_path` is 104 bytes including the terminator.
    static let maximumSocketPathLength = 103

    private let installer: SASSHAgentRelayInstaller?
    private let launcher: Launcher
    private let containerDataDirectory: String
    private let processIdentifier: Int32
    private let startTimeout: TimeInterval
    private let socketNamer: SocketNamer

    /// Names the relay socket for a target; `attempt` counts up when a name
    /// turns out to be taken.
    typealias SocketNamer = (_ target: String, _ processIdentifier: Int32, _ attempt: Int) -> String

    private enum Entry {
        /// `exited` records a helper that quit before its launch finished —
        /// after printing "ready", say — so it is never cached as running.
        case launching(token: Int, exited: Bool)
        case running(listenPath: String, helper: Helper, token: Int)
    }

    private let condition = NSCondition()
    /// Held while a socket name is chosen and bound, so two launches cannot
    /// settle on the same name.
    private let bindLock = NSLock()
    private var entries: [String: Entry] = [:]
    private var nextToken = 0

    init(installer: SASSHAgentRelayInstaller?,
         launcher: @escaping Launcher = SASSHAgentRelay.userScriptLauncher,
         containerDataDirectory: String = NSHomeDirectory(),
         processIdentifier: Int32 = ProcessInfo.processInfo.processIdentifier,
         startTimeout: TimeInterval = SASSHAgentRelay.startTimeout,
         socketNamer: @escaping SocketNamer = SASSHAgentRelay.socketName(target:processIdentifier:attempt:)) {
        self.installer = installer
        self.launcher = launcher
        self.containerDataDirectory = containerDataDirectory
        self.processIdentifier = processIdentifier
        self.startTimeout = startTimeout
        self.socketNamer = socketNamer
    }

    @objc static let shared = SASSHAgentRelay(installer: SASSHAgentRelayInstaller.shared)

    // MARK: - Tunnel entry point

    /// Everything a tunnel needs for one ssh launch: resolves the agent socket
    /// for `source`, makes sure a helper is relaying it, and returns the ssh
    /// options. Called by `SPSSHTunnel` on its launch thread.
    ///
    /// `keyFilePath` is the connection's SSH key, empty for none. A public key
    /// is only an identity while an agent holds the private half, so if the
    /// agent turns out to be disabled for this host the launch fails here with
    /// a reason, not later as "Permission denied".
    @objc(launchPlanForSource:customPath:host:user:port:keyFilePath:error:)
    func launchPlan(source: String, customPath: String, host: String, user: String, port: Int,
                    keyFilePath: String) throws -> SASSHAgentLaunchPlan {
        guard let agentSource = SASSHAgentSource.stored(source, customPath: customPath), agentSource.kind != .off else {
            return .inactive
        }
        let defaults = UserDefaults.standard
        let bundledConfig = Bundle.main.path(forResource: SASSHAgentSource.DefaultsKey.sshConfigFile, ofType: "")
        let configPath = defaults.string(forKey: SASSHAgentSource.DefaultsKey.sshConfigFile) ?? bundledConfig
        let customClient = defaults.string(forKey: SASSHAgentSource.DefaultsKey.sshClientPath) ?? ""
        let sshPath = customClient.isEmpty ? "/usr/bin/ssh" : customClient

        let target = try agentSource.targetPath(realHome: SASSHAgentSource.realHomeDirectory(),
                                                environment: ProcessInfo.processInfo.environment) {
            try SASSHAgentSource.lookUpAutomaticAgent(sshPath: sshPath, configPath: configPath,
                                                      host: host, user: user, port: port)
        }
        guard let target else {
            // Automatic resolved to "no agent" for this host (IdentityAgent none).
            if SASSHAgentSource.isPublicKeyFile(keyFilePath) {
                throw SASSHAgentSource.ResolveError.publicKeyWithoutAgent((keyFilePath as NSString).lastPathComponent)
            }
            return .inactive
        }

        let listenPath = try self.listenPath(forTarget: target)
        let arguments = SASSHAgentSource.sshArguments(listenPath: listenPath,
                                                      usesBundledConfig: configPath == bundledConfig,
                                                      hasKeyFile: !keyFilePath.isEmpty)
        return SASSHAgentLaunchPlan(sshArguments: arguments, listenPath: listenPath, targetPath: target)
    }

    /// Whether a connection with this agent choice authenticates through an
    /// agent, given the current default. The key chooser uses it: only then
    /// is a public key file a usable identity.
    @objc(isAgentInEffectForConnectionSource:)
    static func isAgentInEffect(connectionSource: String) -> Bool {
        let defaultSource = UserDefaults.standard.string(forKey: SASSHAgentSource.DefaultsKey.defaultSource) ?? ""
        return SASSHAgentSource.effective(connectionSource: connectionSource, connectionCustomPath: "",
                                          defaultSource: defaultSource, defaultCustomPath: "").kind != .off
    }

    // MARK: - Relay lifecycle

    /// The 8 hex digit name of the relay socket. Includes the process id so
    /// two running copies of the app never share a socket.
    ///
    /// The name is a short hash because the whole path must fit in 103 bytes,
    /// so two targets can share one. `attempt` gives the next candidate; the
    /// relay never reuses a name that is still in use.
    static func socketName(target: String, processIdentifier: Int32, attempt: Int = 0) -> String {
        let suffix = attempt == 0 ? "" : "\u{0}\(attempt)"
        let digest = SHA256.hash(data: Data("\(target)\u{0}\(processIdentifier)\(suffix)".utf8))
        return digest.prefix(4).map { String(format: "%02x", $0) }.joined()
    }

    static func listenPath(containerDataDirectory: String, socketName: String) -> String {
        containerDataDirectory + "/.keys/a-" + socketName
    }

    /// The socket of a helper relaying `target`, starting one if none is
    /// running. Concurrent callers for one target share a single launch.
    func listenPath(forTarget target: String) throws -> String {
        // Long enough for a launch already under way to finish or give up on
        // its own: it allows startTimeout from the helper's start, after the
        // sweep and file reads that come first.
        let deadline = Date().addingTimeInterval(startTimeout * 2 + 1)
        condition.lock()
        waiting: while true {
            switch entries[target] {
            case .running(let listenPath, let helper, _):
                if Self.isSocket(listenPath) {
                    condition.unlock()
                    return listenPath
                }
                // The socket has gone from under a running helper; start over.
                entries[target] = nil
                helper.closeInput()
                continue waiting
            case .launching:
                guard condition.wait(until: deadline) else {
                    condition.unlock()
                    throw RelayError.startTimedOut
                }
            case nil:
                break waiting
            }
        }
        nextToken += 1
        let token = nextToken
        entries[target] = .launching(token: token, exited: false)
        condition.unlock()

        do {
            let (listenPath, helper) = try start(target: target, token: token)
            condition.lock()
            if case .launching(_, true) = entries[target] {
                entries[target] = nil
                unlink(listenPath)
                condition.broadcast()
                condition.unlock()
                throw RelayError.helperExited(detail: "")
            }
            entries[target] = .running(listenPath: listenPath, helper: helper, token: token)
            condition.broadcast()
            condition.unlock()
            return listenPath
        } catch {
            condition.lock()
            entries[target] = nil
            condition.broadcast()
            condition.unlock()
            throw error
        }
    }

    private func start(target: String, token: Int) throws -> (String, Helper) {
        guard let installer else { throw RelayError.helperUnavailable }
        guard !installer.installedThisSession else { throw RelayError.relaunchRequired }
        switch installer.status {
        case .notInstalled: throw RelayError.helperNotInstalled
        case .outdated: throw RelayError.helperOutdated
        case .installed: break
        }

        let directory = containerDataDirectory + "/.keys"
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        // The sweep is under the lock too: a socket another launch has bound
        // but not yet started listening on refuses connections, and must not
        // be mistaken for an abandoned one.
        bindLock.lock()
        Self.removeAbandonedSockets(inDirectory: directory, sparing: runningListenPaths())
        let listenPath: String
        let descriptor: Int32
        do {
            listenPath = try freeListenPath(forTarget: target)
            descriptor = try Self.makeListeningSocket(at: listenPath)
        } catch {
            bindLock.unlock()
            throw error
        }
        bindLock.unlock()
        var handedOver = false
        defer {
            // Once the helper is accepting, it holds the socket; this copy is
            // only needed to hand it over.
            close(descriptor)
            if !handedOver { unlink(listenPath) }
        }

        let helper: Helper
        do {
            helper = try launcher(installer.installedScript, [target],
                                  FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)) { [weak self] in
                self?.helperExited(target: target, token: token, listenPath: listenPath)
            }
        } catch {
            throw RelayError.launchFailed(error.localizedDescription)
        }

        let firstLine = DispatchSemaphore(value: 0)
        var line: String?
        var afterLine = Data()
        DispatchQueue.global(qos: .userInitiated).async {
            (line, afterLine) = Self.readLine(from: helper.status)
            firstLine.signal()
        }
        guard firstLine.wait(timeout: .now() + startTimeout) == .success else {
            helper.closeInput()
            throw RelayError.startTimedOut
        }
        if line == "ready" {
            handedOver = true
            return (listenPath, helper)
        }

        helper.closeInput()
        // The explanation usually arrives in the same read as the status line.
        let detail = String(decoding: afterLine + helper.status.availableData, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let line, line.hasPrefix("error ") {
            // "error <reason>", or "error not-allowed <path>" naming where the
            // target really leads once links are followed — the path the
            // user would have to list.
            let fields = line.dropFirst("error ".count).split(separator: " ", maxSplits: 1)
            let reason = fields.first.map(String.init) ?? ""
            let resolved = fields.count > 1 ? String(fields[1]) : target
            throw RelayError.helperRefused(reason: reason, target: resolved, detail: detail)
        }
        throw RelayError.helperExited(detail: detail)
    }

    /// A socket path for `target` that nothing else is using. A name already
    /// serving another agent, or another copy of the app, is never taken over:
    /// that relay's clients would silently be talking to the wrong agent.
    private func runningListenPaths() -> Set<String> {
        condition.lock()
        defer { condition.unlock() }
        return Set(entries.values.compactMap { entry -> String? in
            if case .running(let listenPath, _, _) = entry { return listenPath }
            return nil
        })
    }

    private func freeListenPath(forTarget target: String) throws -> String {
        let inUse = runningListenPaths()

        for attempt in 0..<8 {
            let name = socketNamer(target, processIdentifier, attempt)
            let candidate = Self.listenPath(containerDataDirectory: containerDataDirectory, socketName: name)
            guard candidate.utf8.count <= Self.maximumSocketPathLength else {
                throw RelayError.listenPathTooLong(candidate)
            }
            if inUse.contains(candidate) { continue }
            // Only a socket that definitely has no listener may be replaced.
            if Self.isSocket(candidate), !Self.isAbandoned(candidate) { continue }
            return candidate
        }
        throw RelayError.listenFailed("no free socket name")
    }

    private func helperExited(target: String, token: Int, listenPath: String) {
        condition.lock()
        switch entries[target] {
        case .running(_, _, let running) where running == token:
            entries[target] = nil
            unlink(listenPath)
        case .launching(let launching, _) where launching == token:
            entries[target] = .launching(token: token, exited: true)
        default:
            break
        }
        condition.unlock()
    }

    // MARK: - The listening socket

    private static func socketAddress(_ path: String) -> sockaddr_un {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: Array(path.utf8).prefix(maximumSocketPathLength)) }
        return address
    }

    private static func withSocketAddress<T>(_ path: String, _ body: (UnsafePointer<sockaddr>, socklen_t) -> T) -> T {
        var address = socketAddress(path)
        return withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { body($0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
    }

    private static func isSocket(_ path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFSOCK
    }

    /// Whether the socket at `path` looks abandoned: the connection is refused,
    /// or the file is gone. Any other outcome counts as in use. A full backlog
    /// is also refused on macOS, so callers spare their own live relays
    /// (see `removeAbandonedSockets(inDirectory:sparing:)`).
    private static func isAbandoned(_ path: String) -> Bool {
        let probe = socket(AF_UNIX, SOCK_STREAM, 0)
        guard probe >= 0 else { return false }
        defer { close(probe) }
        guard withSocketAddress(path, { Darwin.connect(probe, $0, $1) }) != 0 else { return false }
        return errno == ECONNREFUSED || errno == ENOENT
    }

    /// Binds and listens at `path`, replacing a socket left by an earlier
    /// helper but never any other kind of file. The backlog matters: several
    /// tunnels restored together reach the agent at the same moment.
    static func makeListeningSocket(at path: String) throws -> Int32 {
        if FileManager.default.fileExists(atPath: path) || (try? FileManager.default.destinationOfSymbolicLink(atPath: path)) != nil {
            guard isSocket(path) else { throw RelayError.listenPathBlocked(path) }
            unlink(path)
        }
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw RelayError.listenFailed(String(cString: strerror(errno))) }
        guard withSocketAddress(path, { Darwin.bind(descriptor, $0, $1) }) == 0 else {
            let reason = String(cString: strerror(errno))
            close(descriptor)
            throw RelayError.listenFailed(reason)
        }
        chmod(path, 0o600)
        guard listen(descriptor, 16) == 0 else {
            let reason = String(cString: strerror(errno))
            close(descriptor)
            unlink(path)
            throw RelayError.listenFailed(reason)
        }
        return descriptor
    }

    /// Relay sockets are named per process, so a crash leaves one behind.
    /// Removes those nothing is listening on any more. `sparing` are this
    /// process's own live relays: a busy one can refuse a probe too.
    static func removeAbandonedSockets(inDirectory directory: String, sparing: Set<String> = []) {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory) else { return }
        for name in names where name.range(of: "^a-[0-9a-f]{8}$", options: .regularExpression) != nil {
            let path = directory + "/" + name
            guard !sparing.contains(path), isSocket(path) else { continue }
            if isAbandoned(path) { unlink(path) }
        }
    }

    /// Reads up to the first newline (`nil` at EOF with nothing read), and
    /// hands back whatever was read past it.
    private static func readLine(from handle: FileHandle) -> (line: String?, rest: Data) {
        var bytes = Data()
        while true {
            let chunk = handle.availableData
            if chunk.isEmpty { break }
            if let newline = chunk.firstIndex(of: 0x0A) {
                bytes.append(chunk[chunk.startIndex..<newline])
                return (String(decoding: bytes, as: UTF8.self), Data(chunk[chunk.index(after: newline)...]))
            }
            bytes.append(chunk)
        }
        return (bytes.isEmpty ? nil : String(decoding: bytes, as: UTF8.self), Data())
    }

    // MARK: - Launching outside the sandbox

    /// Runs the script with `NSUserUnixTask`, the sanctioned way for a
    /// sandboxed app to run a user-installed script outside its sandbox.
    static let userScriptLauncher: Launcher = { script, arguments, listeningSocket, onExit in
        let task = try NSUserUnixTask(url: script)
        let input = Pipe()
        let status = Pipe()
        task.standardInput = input.fileHandleForReading
        task.standardOutput = listeningSocket
        task.standardError = status.fileHandleForWriting
        // The completion error is not a failure signal here: asking the helper
        // to quit ends it with SIGTERM, which is reported as an error.
        task.execute(withArguments: arguments) { _ in
            try? status.fileHandleForWriting.close()
            onExit()
        }
        return Helper(status: status.fileHandleForReading,
                      closeInput: { try? input.fileHandleForWriting.close() })
    }
}

// MARK: - Messages

extension SASSHAgentRelay.RelayError: LocalizedError {

    var errorDescription: String? {
        switch self {
        case .helperUnavailable:
            return NSLocalizedString("The SSH agent helper folder could not be found.", comment: "SSH agent relay error")
        case .helperNotInstalled:
            return NSLocalizedString("This connection uses an SSH agent, but the SSH agent helper is not installed. Install it in Preferences > Network.", comment: "SSH agent relay error")
        case .helperOutdated:
            return NSLocalizedString("The SSH agent helper needs to be updated. Update it in Preferences > Network.", comment: "SSH agent relay error")
        case .relaunchRequired:
            return NSLocalizedString("The SSH agent helper was just installed. Relaunch Sequel Ace to start using it.", comment: "SSH agent relay error")
        case .listenPathTooLong:
            return NSLocalizedString("The SSH agent helper could not be started because the path to its socket is too long.", comment: "SSH agent relay error")
        case .listenPathBlocked(let path):
            return String(format: NSLocalizedString("The SSH agent helper could not be started because something else is in the way of its socket: %@", comment: "SSH agent relay error; %@ is a path"), path)
        case .listenFailed(let detail):
            return String(format: NSLocalizedString("The SSH agent helper's socket could not be created: %@", comment: "SSH agent relay error; %@ is the system's reason"), detail)
        case .startTimedOut:
            return NSLocalizedString("The SSH agent helper did not start in time.", comment: "SSH agent relay error")
        case .launchFailed(let detail):
            return String(format: NSLocalizedString("The SSH agent helper could not be started: %@", comment: "SSH agent relay error; %@ is the system's reason"), detail)
        case .helperExited(let detail):
            return String(format: NSLocalizedString("The SSH agent helper stopped unexpectedly. %@", comment: "SSH agent relay error; %@ is the helper's own message"), detail)
        case .helperRefused(let reason, let target, let detail):
            switch reason {
            case "not-allowed":
                return String(format: NSLocalizedString("The SSH agent helper is not allowed to connect to this socket. To allow it, add this line to ssh-agent-relay.allow:\n\n%@", comment: "SSH agent relay error; %@ is a socket path"), Self.allowlistLine(for: target))
            case "not-owned":
                return String(format: NSLocalizedString("The socket at this path belongs to another user, so it cannot be your SSH agent.\n\n%@", comment: "SSH agent relay error; %@ is a socket path"), target)
            case "no-target":
                return String(format: NSLocalizedString("The SSH agent's socket was not found. Is the agent running?\n\n%@", comment: "SSH agent relay error; %@ is a socket path"), target)
            case "socket-module":
                return NSLocalizedString("The SSH agent helper cannot run on this version of macOS.", comment: "SSH agent relay error")
            default:
                return String(format: NSLocalizedString("The SSH agent helper could not start. %@", comment: "SSH agent relay error; %@ is the helper's own message"), detail.isEmpty ? reason : detail)
            }
        }
    }

    /// The target as the user would write it in the allowlist.
    static func allowlistLine(for target: String, realHome: String = SASSHAgentSource.realHomeDirectory()) -> String {
        target.hasPrefix(realHome + "/") ? "~" + target.dropFirst(realHome.count) : target
    }
}

extension SASSHAgentSource.ResolveError: LocalizedError {

    var errorDescription: String? {
        switch self {
        case .noSystemAgent:
            return NSLocalizedString("No system SSH agent is available (SSH_AUTH_SOCK is not set).", comment: "SSH agent error")
        case .emptyCustomPath:
            return NSLocalizedString("This connection uses a custom SSH agent socket, but no socket path is set.", comment: "SSH agent error")
        case .relativePath(let path):
            return String(format: NSLocalizedString("The SSH agent socket path must be absolute: %@", comment: "SSH agent error; %@ is a path"), path)
        case .unsupportedIdentityAgent(let value):
            return String(format: NSLocalizedString("The SSH config sets IdentityAgent to %@, which Sequel Ace cannot resolve. Choose the agent explicitly instead of Automatic.", comment: "SSH agent error; %@ is a config value"), value)
        case .lookupFailed(let detail):
            return String(format: NSLocalizedString("Could not read the SSH config to find the SSH agent. %@", comment: "SSH agent error; %@ is the reason"), detail)
        case .lookupTimedOut:
            return NSLocalizedString("Reading the SSH config to find the SSH agent took too long.", comment: "SSH agent error")
        case .publicKeyWithoutAgent(let name):
            return String(format: NSLocalizedString("“%@” is a public key, which only works together with an SSH agent, and the SSH config turns the agent off for this host (IdentityAgent none). Choose the private key, or choose an SSH agent for this connection.", comment: "SSH agent error; %@ is a file name"), name)
        }
    }
}
