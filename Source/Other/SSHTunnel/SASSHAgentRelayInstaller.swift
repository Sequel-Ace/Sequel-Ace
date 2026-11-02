//
//  SASSHAgentRelayInstaller.swift
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

/// Where the SSH agent helper lives and whether the installed copy can be run.
/// User-facing description: `docs/get-started/remote-connection.md`.
///
/// The helper is a script in the app's Application Scripts folder, which is
/// the one place a sandboxed app may run code from outside its sandbox. The
/// sandbox lets the app *read* that folder but not write it, so installing
/// takes a folder the user has just picked in an open panel. No bookmark is
/// kept: the app must not hold standing write access to code it runs
/// unsandboxed.
///
/// App and Unit Tests targets.
final class SASSHAgentRelayInstaller {

    enum Status: Equatable {
        case notInstalled
        case installed
        /// A copy is installed but differs from the bundled one.
        case outdated
    }

    enum InstallError: Error, Equatable {
        /// The user picked some other folder in the panel.
        case wrongFolder
        case missingBundledHelper
        case copyFailed(String)
    }

    static let scriptName = "ssh-agent-relay.zsh"
    static let allowlistName = "ssh-agent-relay.allow"

    let scriptsDirectory: URL
    private let bundledScript: URL?
    private let bundledAllowlist: URL?
    private let fileManager: FileManager

    private let stateLock = NSLock()
    private let launchLock = NSLock()
    private var installedThisSessionFlag = false
    /// How long a launch waits for another copy of the app that installed the
    /// helper to quit; long enough to cover a relaunch.
    let otherInstallerWait: TimeInterval
    /// The scripts folder, held with a shared lock from this process's first
    /// install until it exits. Guarded by `launchLock`.
    private var installBarrier: Int32 = -1

    enum LaunchRefusal: Error, Equatable {
        case notInstalled
        case outdated
        /// Installed or updated by this process, which still holds the panel's
        /// write access to the folder.
        case relaunchRequired
        /// Another copy of the app installed or updated the helper and is still
        /// running, so it still holds write access to the folder.
        case installedByAnotherCopy
    }

    /// Runs `body` with the installed script if it may be launched now, with
    /// installation blocked until `body` returns.
    func whileLaunchable<T>(_ body: (URL) throws -> T) throws -> T {
        launchLock.lock()
        defer { launchLock.unlock() }
        guard !installedThisSession else { throw LaunchRefusal.relaunchRequired }
        let lockedOut = try lockOutOtherInstallers()
        defer { close(lockedOut) }
        switch status {
        case .notInstalled: throw LaunchRefusal.notInstalled
        case .outdated: throw LaunchRefusal.outdated
        case .installed: return try body(installedScript)
        }
    }

    /// The in-process flag above cannot see other copies of the app — the one
    /// a relaunch opens while the installing copy is still quitting, or a
    /// second instance. A copy that installs holds a shared lock on the
    /// scripts folder until it exits, which macOS releases however it ends;
    /// a launch takes the folder exclusively, waiting out such a copy for
    /// `otherInstallerWait`. Holding it also keeps any copy from installing
    /// while the launch is under way.
    private func lockOutOtherInstallers() throws -> Int32 {
        let folder = open(scriptsDirectory.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard folder >= 0 else { throw LaunchRefusal.notInstalled }
        let deadline = Date().addingTimeInterval(otherInstallerWait)
        while flock(folder, LOCK_EX | LOCK_NB) != 0 {
            guard errno == EWOULDBLOCK || errno == EINTR, Date() < deadline else {
                close(folder)
                throw LaunchRefusal.installedByAnotherCopy
            }
            usleep(50_000)
        }
        return folder
    }

    /// Taken before anything is written, waiting out a launch under way in
    /// another copy, and kept until this process exits.
    private func holdInstallBarrier() throws {
        guard installBarrier < 0 else { return }
        let folder = open(scriptsDirectory.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard folder >= 0 else { throw InstallError.copyFailed(String(cString: strerror(errno))) }
        guard flock(folder, LOCK_SH) == 0 else {
            let reason = String(cString: strerror(errno))
            close(folder)
            throw InstallError.copyFailed(reason)
        }
        installBarrier = folder
    }

    init(scriptsDirectory: URL, bundledScript: URL?, bundledAllowlist: URL?, fileManager: FileManager = .default,
         otherInstallerWait: TimeInterval = 5) {
        self.scriptsDirectory = scriptsDirectory
        self.bundledScript = bundledScript
        self.bundledAllowlist = bundledAllowlist
        self.fileManager = fileManager
        self.otherInstallerWait = otherInstallerWait
    }

    deinit {
        if installBarrier >= 0 { close(installBarrier) }
    }

    /// The installer for the running app. `nil` when the Application Scripts
    /// folder cannot be located.
    static let shared: SASSHAgentRelayInstaller? = {
        guard let directory = try? FileManager.default.url(for: .applicationScriptsDirectory, in: .userDomainMask,
                                                           appropriateFor: nil, create: true) else { return nil }
        return SASSHAgentRelayInstaller(
            scriptsDirectory: directory,
            bundledScript: Bundle.main.url(forResource: scriptName, withExtension: nil),
            bundledAllowlist: Bundle.main.url(forResource: allowlistName, withExtension: nil))
    }()

    var installedScript: URL { scriptsDirectory.appendingPathComponent(Self.scriptName) }
    var installedAllowlist: URL { scriptsDirectory.appendingPathComponent(Self.allowlistName) }

    /// Compares the installed script with the bundled one byte for byte. The
    /// script runs outside the sandbox, so anything but an exact match is
    /// treated as outdated and never run. The allowlist is the user's to edit
    /// and is not compared — but it has to be there: the helper refuses to
    /// start without it, so a missing one also counts as outdated, which
    /// brings back the button that reinstalls it.
    var status: Status {
        guard let installed = fileManager.contents(atPath: installedScript.path) else { return .notInstalled }
        guard let bundledScript, let bundled = fileManager.contents(atPath: bundledScript.path) else { return .outdated }
        // It also has to be runnable, and its allowlist readable: otherwise every
        // agent connection fails, and only "outdated" brings back the repair button.
        guard installed == bundled,
              fileManager.isExecutableFile(atPath: installedScript.path),
              isReadableRegularFile(installedAllowlist.path) else { return .outdated }
        return .installed
    }

    private func isReadableRegularFile(_ path: String) -> Bool {
        (try? fileManager.attributesOfItem(atPath: path))?[.type] as? FileAttributeType == .typeRegular
            && fileManager.isReadableFile(atPath: path)
    }

    private func isRegularFileOrLinkToOne(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: path, isDirectory: &isDirectory) && !isDirectory.boolValue
            && (try? fileManager.attributesOfItem(atPath: path))?[.type] as? FileAttributeType == .typeRegular
    }

    /// True once this process has installed or updated the helper. The open
    /// panel's write access to the folder lasts until the app quits, so the
    /// relay refuses to run until the app has been relaunched.
    var installedThisSession: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return installedThisSessionFlag
    }

    /// Copies the bundled helper into `folder`, which must be the Application
    /// Scripts folder — the panel lets the user navigate anywhere. An existing
    /// allowlist is left alone so the user's edits survive updates.
    func install(into folder: URL) throws {
        // Held for the whole install, and by `whileLaunchable` around a helper
        // launch: a launch can never slip in between the new helper landing and
        // the "installed this session" flag being set.
        launchLock.lock()
        defer { launchLock.unlock() }
        guard folder.standardizedFileURL.resolvingSymlinksInPath().path
                == scriptsDirectory.standardizedFileURL.resolvingSymlinksInPath().path else {
            throw InstallError.wrongFolder
        }
        guard let bundledScript, let bundledAllowlist,
              let script = fileManager.contents(atPath: bundledScript.path),
              let allowlist = fileManager.contents(atPath: bundledAllowlist.path) else {
            throw InstallError.missingBundledHelper
        }
        try holdInstallBarrier()
        let scriptDestination = folder.appendingPathComponent(Self.scriptName)
        let allowlistDestination = folder.appendingPathComponent(Self.allowlistName)
        do {
            // A folder at the script's name would make every write fail; the
            // script is never the user's to keep, so anything there is replaced.
            if (try? fileManager.attributesOfItem(atPath: scriptDestination.path)) != nil,
               !isRegularFileOrLinkToOne(scriptDestination.path) {
                try fileManager.removeItem(at: scriptDestination)
            }
            try script.write(to: scriptDestination, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptDestination.path)
            // Something other than a plain file at the allowlist's name (a folder,
            // a link to elsewhere) cannot be the allowlist; replace it.
            let existsAtAllowlist = (try? fileManager.attributesOfItem(atPath: allowlistDestination.path)) != nil
            if existsAtAllowlist, !isRegularFileOrLinkToOne(allowlistDestination.path) {
                try fileManager.removeItem(at: allowlistDestination)
            }
            if !fileManager.fileExists(atPath: allowlistDestination.path) {
                try allowlist.write(to: allowlistDestination, options: .atomic)
                try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: allowlistDestination.path)
            } else if !fileManager.isReadableFile(atPath: allowlistDestination.path) {
                // Keep the user's list, but make it readable again.
                try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: allowlistDestination.path)
            }
        } catch {
            throw InstallError.copyFailed(error.localizedDescription)
        }
        stateLock.lock()
        installedThisSessionFlag = true
        stateLock.unlock()
    }
}

// MARK: - Presentation

extension SASSHAgentRelayInstaller {

    /// One line for Preferences > Network: the default agent, and what still
    /// stands between it and working, so neither needs the settings sheet
    /// opened to be seen.
    static func summary(defaultSource: SASSHAgentSource, status: Status, installedThisSession: Bool) -> String {
        let name: String
        switch defaultSource.kind {
        case .off: return NSLocalizedString("Off", comment: "ssh agent source : no agent")
        case .automatic: name = NSLocalizedString("Automatic (from SSH config)", comment: "ssh agent source : whatever ssh itself would use")
        case .system: name = NSLocalizedString("System Agent", comment: "ssh agent source : macOS ssh-agent")
        case .onePassword: name = "1Password"
        case .custom:
            name = defaultSource.customPath.isEmpty
                ? NSLocalizedString("Custom Socket", comment: "ssh agent source : user supplied socket path")
                : defaultSource.customPath
        }
        if installedThisSession {
            return String(format: NSLocalizedString("%@ — relaunch to finish", comment: "network preferences : ssh agent summary; %@ is the agent name"), name)
        }
        switch status {
        case .installed: return name
        case .notInstalled:
            return String(format: NSLocalizedString("%@ — helper not installed", comment: "network preferences : ssh agent summary; %@ is the agent name"), name)
        case .outdated:
            return String(format: NSLocalizedString("%@ — helper update required", comment: "network preferences : ssh agent summary; %@ is the agent name"), name)
        }
    }

    /// "Use Default (1Password)": the per-connection menu item that follows the
    /// default, naming what that default currently is.
    static func useDefaultTitle(defaultSource: String, defaultCustomPath: String) -> String {
        let source = SASSHAgentSource.stored(defaultSource, customPath: defaultCustomPath) ?? .off
        return String(format: NSLocalizedString("Use Default (%@)", comment: "ssh agent source : follow the default from preferences; %@ is the current default agent"),
                      summary(defaultSource: source, status: .installed, installedThisSession: false))
    }

    /// What a connection's SSH settings say about the agent it will use, so
    /// the outcome of "Use Default" and the helper's readiness are visible
    /// where the connection is edited. `needsAttention` is true when an agent
    /// is selected but the helper cannot run yet.
    static func connectionStatus(connectionSource: String, connectionCustomPath: String,
                                 defaultSource: String, defaultCustomPath: String,
                                 status: Status, installedThisSession: Bool) -> (text: String, needsAttention: Bool) {
        let effective = SASSHAgentSource.effective(connectionSource: connectionSource, connectionCustomPath: connectionCustomPath,
                                                   defaultSource: defaultSource, defaultCustomPath: defaultCustomPath)
        let followsDefault = SASSHAgentSource.stored(connectionSource, customPath: connectionCustomPath) == nil
        guard effective.kind != .off else {
            return (followsDefault
                        ? NSLocalizedString("No SSH agent is used (the default is Off). Authentication uses the SSH password or key.", comment: "connection view : ssh agent status")
                        : NSLocalizedString("No SSH agent is used. Authentication uses the SSH password or key.", comment: "connection view : ssh agent status"),
                    false)
        }
        let name = summary(defaultSource: effective, status: .installed, installedThisSession: false)
        if installedThisSession {
            return (String(format: NSLocalizedString("%@ will be used after Sequel Ace is relaunched.", comment: "connection view : ssh agent status; %@ is the agent name"), name), true)
        }
        switch status {
        case .notInstalled:
            return (String(format: NSLocalizedString("%@ is selected, but the SSH agent helper is not installed.", comment: "connection view : ssh agent status; %@ is the agent name"), name), true)
        case .outdated:
            return (String(format: NSLocalizedString("%@ is selected, but the SSH agent helper needs to be updated.", comment: "connection view : ssh agent status; %@ is the agent name"), name), true)
        case .installed:
            return (String(format: followsDefault
                               ? NSLocalizedString("Keys come from %@ (the default). Leave SSH Password empty unless the server also asks for one.", comment: "connection view : ssh agent status; %@ is the agent name")
                               : NSLocalizedString("Keys come from %@. Leave SSH Password empty unless the server also asks for one.", comment: "connection view : ssh agent status; %@ is the agent name"), name), false)
        }
    }

    /// What the preferences show for the helper: its state in words, and the
    /// title of the button that fixes it (`nil` when nothing needs doing).
    static func presentation(status: Status, installedThisSession: Bool) -> (state: String, action: String?) {
        if installedThisSession {
            return (NSLocalizedString("Installed. Relaunch Sequel Ace to start using it.", comment: "SSH agent helper state"), nil)
        }
        switch status {
        case .notInstalled:
            return (NSLocalizedString("Not installed", comment: "SSH agent helper state"),
                    NSLocalizedString("Install Helper…", comment: "SSH agent helper button"))
        case .outdated:
            return (NSLocalizedString("Update required", comment: "SSH agent helper state"),
                    NSLocalizedString("Update Helper…", comment: "SSH agent helper button"))
        case .installed:
            return (NSLocalizedString("Installed", comment: "SSH agent helper state"), nil)
        }
    }
}

extension SASSHAgentRelayInstaller.InstallError: LocalizedError {

    var errorDescription: String? {
        switch self {
        case .wrongFolder:
            return NSLocalizedString("The helper can only be installed in the folder the panel opens with. Try again without changing the folder.", comment: "ssh agent helper install error")
        case .missingBundledHelper:
            return NSLocalizedString("The SSH agent helper is missing from this copy of Sequel Ace.", comment: "ssh agent helper install error")
        case .copyFailed(let detail):
            return detail
        }
    }
}
