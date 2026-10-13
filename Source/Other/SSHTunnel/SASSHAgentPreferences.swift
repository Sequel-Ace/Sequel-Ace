//
//  SASSHAgentPreferences.swift
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

import AppKit
import SwiftUI

/// The SSH agent settings: the default agent for SSH connections and the
/// helper that reaches it.
/// Shown as a sheet from Preferences > Network.
///
/// App target only.
@objc final class SASSHAgentPreferences: NSObject {

    /// True while the app is quitting because the user clicked Relaunch after
    /// installing the helper. The app delegate skips its "close the app?"
    /// confirmation then: the user has just asked for exactly this, and by
    /// that point the new copy is already starting.
    @objc static private(set) var isRelaunching = false

    fileprivate static func beginRelaunch() { isRelaunching = true }

    /// Shows the default agent beside the Configure… button, so it can be seen
    /// without opening the sheet.
    private static weak var summaryLabel: NSTextField?

    /// Re-reads the default agent and the helper's state into the row.
    static func refreshSummary() {
        let defaults = UserDefaults.standard
        let source = SASSHAgentSource.stored(defaults.string(forKey: SASSHAgentSource.DefaultsKey.defaultSource) ?? "",
                                             customPath: defaults.string(forKey: SASSHAgentSource.DefaultsKey.customSocketPath) ?? "") ?? .off
        let installer = SASSHAgentRelayInstaller.shared
        summaryLabel?.stringValue = SASSHAgentRelayInstaller.summary(
            defaultSource: source,
            status: installer?.status ?? .notInstalled,
            installedThisSession: installer?.installedThisSession ?? false)
    }

    /// Adds an "SSH Agent" row under `anchor` (the Known Hosts chooser) in the
    /// Network pane. The pane's layout lives in a XIB; the row is spliced into
    /// its vertical constraint chain here so the XIB needs no new controls.
    @objc(installRowInView:belowView:target:action:)
    static func installRow(in paneView: NSView, below anchor: NSView, target: AnyObject, action: Selector) {
        guard let chain = paneView.constraints.first(where: {
            $0.secondItem === anchor && $0.secondAttribute == .bottom && $0.firstAttribute == .top
                && $0.firstItem is NSBox
        }), let below = chain.firstItem as? NSView else { return }
        // The row's label lines up with the label of the row above it.
        let anchorLabel = paneView.constraints.lazy
            .filter { $0.secondItem === anchor && $0.firstAttribute == .firstBaseline }
            .compactMap { $0.firstItem as? NSTextField }.first

        let label = NSTextField(labelWithString: NSLocalizedString("SSH Agent:", comment: "network preferences : ssh agent row label"))
        label.alignment = .right
        let button = NSButton(title: NSLocalizedString("Configure…", comment: "network preferences : ssh agent settings button"),
                              target: target, action: action)
        button.bezelStyle = .roundRect
        button.controlSize = .regular
        let summary = NSTextField(labelWithString: "")
        summary.textColor = .secondaryLabelColor
        summary.lineBreakMode = .byTruncatingMiddle
        summary.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        for view in [label, button, summary] {
            view.translatesAutoresizingMaskIntoConstraints = false
            paneView.addSubview(view)
        }
        summaryLabel = summary
        refreshSummary()

        let spacing = chain.constant
        chain.isActive = false
        var constraints = [
            button.topAnchor.constraint(equalTo: anchor.bottomAnchor, constant: spacing),
            button.leadingAnchor.constraint(equalTo: anchor.leadingAnchor),
            below.topAnchor.constraint(equalTo: button.bottomAnchor, constant: spacing),
            label.firstBaselineAnchor.constraint(equalTo: button.firstBaselineAnchor),
            summary.leadingAnchor.constraint(equalTo: button.trailingAnchor, constant: 8),
            summary.firstBaselineAnchor.constraint(equalTo: button.firstBaselineAnchor),
            summary.trailingAnchor.constraint(lessThanOrEqualTo: anchor.trailingAnchor),
        ]
        if let anchorLabel {
            constraints.append(label.trailingAnchor.constraint(equalTo: anchorLabel.trailingAnchor))
            constraints.append(label.leadingAnchor.constraint(equalTo: anchorLabel.leadingAnchor))
        } else {
            constraints.append(label.trailingAnchor.constraint(equalTo: button.leadingAnchor, constant: -8))
        }
        // The preferences window sizes itself from the pane's fitting size, so
        // lengthening the chain is all it takes to make room for the row.
        NSLayoutConstraint.activate(constraints)
    }

    @objc(presentSettingsFromWindow:)
    static func presentSettings(from window: NSWindow?) {
        guard let window else { return }
        SASSHAgentSettingsWindowController().beginSheet(on: window)
    }
}

// MARK: - Sheet

final class SASSHAgentSettingsWindowController: NSWindowController {

    /// A sheet is not retained by its parent while it is up.
    private static var presented: SASSHAgentSettingsWindowController?

    convenience init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 400),
                              styleMask: [.titled], backing: .buffered, defer: true)
        self.init(window: window)
        let model = SASSHAgentSettingsModel()
        model.dismiss = { [weak self] in self?.endSheet() }
        window.contentView = NSHostingView(rootView: SASSHAgentSettingsView(model: model) { [weak self] in
            self?.endSheet()
        })
    }

    func beginSheet(on parent: NSWindow) {
        guard let window else { return }
        window.setContentSize(window.contentView?.fittingSize ?? window.frame.size)
        Self.presented = self
        parent.beginSheet(window) { _ in
            Self.presented = nil
            SASSHAgentPreferences.refreshSummary()
        }
    }

    private func endSheet() {
        guard let window, let parent = window.sheetParent else { return }
        parent.endSheet(window)
    }
}

// MARK: - Model

final class SASSHAgentSettingsModel: ObservableObject {

    private let installer = SASSHAgentRelayInstaller.shared
    private var defaults: UserDefaults { UserDefaults.standard }

    /// The default agent source. An unset default is shown, and behaves, as off.
    @Published var defaultSource: String {
        didSet { defaults.set(defaultSource, forKey: SASSHAgentSource.DefaultsKey.defaultSource) }
    }
    @Published var customSocketPath: String {
        didSet { defaults.set(customSocketPath, forKey: SASSHAgentSource.DefaultsKey.customSocketPath) }
    }
    @Published private(set) var status: SASSHAgentRelayInstaller.Status = .notInstalled
    @Published private(set) var installedThisSession = false
    @Published var installError: String?
    @Published var isPresentingInstallError = false
    @Published var isPresentingRelaunchPrompt = false

    /// Closes the settings sheet. Set by the window controller.
    var dismiss: (() -> Void)?

    init() {
        let stored = UserDefaults.standard.string(forKey: SASSHAgentSource.DefaultsKey.defaultSource) ?? ""
        defaultSource = SASSHAgentSource.Kind(rawValue: stored)?.rawValue ?? SASSHAgentSource.Kind.off.rawValue
        customSocketPath = UserDefaults.standard.string(forKey: SASSHAgentSource.DefaultsKey.customSocketPath) ?? ""
        refresh()
    }

    func refresh() {
        status = installer?.status ?? .notInstalled
        installedThisSession = installer?.installedThisSession ?? false
    }

    /// The sandbox lets the app read its Application Scripts folder but not
    /// write it, so the copy needs the folder back from an open panel. No
    /// bookmark is kept: every install or update is a fresh, visible grant.
    func installHelper() {
        guard let installer else { return }
        let panel = NSOpenPanel()
        panel.directoryURL = installer.scriptsDirectory
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.message = NSLocalizedString("To install the SSH agent helper, Sequel Ace needs your permission to add it to this folder. Select the folder shown and click Install.", comment: "ssh agent helper install panel message")
        panel.prompt = NSLocalizedString("Install", comment: "ssh agent helper install panel button")
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        do {
            try installer.install(into: folder)
            // The helper is not used until the app has relaunched; say so now
            // instead of leaving it to be discovered at the next connection.
            isPresentingRelaunchPrompt = true
        } catch SASSHAgentRelayInstaller.InstallError.wrongFolder {
            presentInstallError(NSLocalizedString("The helper can only be installed in the folder the panel opens with. Try again without changing the folder.", comment: "ssh agent helper install error"))
        } catch {
            presentInstallError(String(format: NSLocalizedString("The SSH agent helper could not be installed. %@", comment: "ssh agent helper install error; %@ is the reason"), error.localizedDescription))
        }
        refresh()
    }

    private func presentInstallError(_ message: String) {
        installError = message
        isPresentingInstallError = true
    }

    func revealHelper() {
        guard let installer else { return }
        let script = installer.installedScript
        if FileManager.default.fileExists(atPath: script.path) {
            NSWorkspace.shared.activateFileViewerSelecting([script, installer.installedAllowlist])
        } else {
            NSWorkspace.shared.open(installer.scriptsDirectory)
        }
    }

    /// Relaunches the app, which ends the panel's write access to the helper's
    /// folder (it lasts for the life of the process).
    ///
    /// The app will not quit while a sheet is up, and this is called from a
    /// button on the settings sheet or on an alert over it. So the sheet is
    /// closed first, and only then is the new copy started and this one quit.
    func relaunch() {
        // Let the alert that carried the button finish closing.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [self] in
            guard let dismiss else { return Self.startNewInstanceAndQuit(onFailure: presentRelaunchError) }
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                Self.startNewInstanceAndQuit(onFailure: Self.showRelaunchFailure)
            }
        }
    }

    private static func startNewInstanceAndQuit(onFailure: @escaping (String) -> Void) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { application, error in
            DispatchQueue.main.async {
                if application != nil, error == nil {
                    SASSHAgentPreferences.beginRelaunch()
                    NSApp.terminate(nil)
                } else {
                    onFailure(error?.localizedDescription ?? "")
                }
            }
        }
    }

    private static let relaunchFailureMessage = NSLocalizedString("Sequel Ace could not relaunch itself. Quit Sequel Ace and open it again to finish installing the helper.", comment: "ssh agent settings : relaunch failed message")

    /// Shares the sheet's one alert: two `.alert` modifiers on a view do not
    /// both work.
    private func presentRelaunchError(_ detail: String) {
        presentInstallError([Self.relaunchFailureMessage, detail].filter { !$0.isEmpty }.joined(separator: "\n\n"))
    }

    /// The sheet has gone by the time this can fail, so the alert stands alone.
    private static func showRelaunchFailure(_ detail: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = NSLocalizedString("SSH Agent Helper", comment: "ssh agent settings : install error title")
        alert.informativeText = [relaunchFailureMessage, detail].filter { !$0.isEmpty }.joined(separator: "\n\n")
        alert.runModal()
    }
}

// MARK: - View

struct SASSHAgentSettingsView: View {

    @ObservedObject var model: SASSHAgentSettingsModel
    let done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("SSH Agent", comment: "ssh agent settings : title")
                .font(.headline)

            Text("Sequel Ace can authenticate SSH connections with keys held by an SSH agent such as 1Password, Secretive or the macOS agent. Each connection can override the default chosen here.", comment: "ssh agent settings : introduction")
                .fixedSize(horizontal: false, vertical: true)

            Form {
                SASSHAgentSourcePicker(source: $model.defaultSource, customPath: $model.customSocketPath,
                                       includesUseDefault: false) {
                    Text("Default agent:", comment: "ssh agent settings : default source label")
                }
            }

            Divider()

            SASSHAgentHelperSection(model: model)

            HStack {
                Spacer()
                Button(action: done) {
                    Text("Done", comment: "ssh agent settings : close button")
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520)
        .alert(Text("SSH Agent Helper", comment: "ssh agent settings : install error title"),
               isPresented: $model.isPresentingInstallError) {
            Button(role: .cancel) {} label: { Text("OK", comment: "ssh agent settings : dismiss error") }
        } message: {
            Text(verbatim: model.installError ?? "")
        }

    }
}

/// The helper's state and the buttons that act on it.
private struct SASSHAgentHelperSection: View {

    @ObservedObject var model: SASSHAgentSettingsModel

    var body: some View {
        let presentation = SASSHAgentRelayInstaller.presentation(status: model.status,
                                                                 installedThisSession: model.installedThisSession)
        VStack(alignment: .leading, spacing: 8) {
            Text("Helper", comment: "ssh agent settings : helper section title")
                .font(.headline)

            Text("Sequel Ace is sandboxed and cannot reach an SSH agent by itself. A small helper script, which you install once, passes connections on to the agents listed in its ssh-agent-relay.allow file. Your agent may show the request as coming from “com.apple.foundation.UserScriptService”, the macOS service that runs the helper.", comment: "ssh agent settings : helper explanation")
                .font(.callout)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Text(verbatim: presentation.state)
                Spacer()
                if model.installedThisSession {
                    Button { model.relaunch() } label: {
                        Text("Relaunch", comment: "ssh agent settings : relaunch button")
                    }
                } else if let action = presentation.action {
                    Button { model.installHelper() } label: { Text(verbatim: action) }
                }
                Button { model.revealHelper() } label: {
                    Text("Show in Finder", comment: "ssh agent settings : reveal helper button")
                }
            }
        }
        .alert(Text("Relaunch Sequel Ace to finish installing the helper?", comment: "ssh agent settings : relaunch prompt title"),
               isPresented: $model.isPresentingRelaunchPrompt) {
            Button { model.relaunch() } label: {
                Text("Relaunch", comment: "ssh agent settings : relaunch button")
            }
            .keyboardShortcut(.defaultAction)
            Button(role: .cancel) {} label: {
                Text("Later", comment: "ssh agent settings : postpone relaunch button")
            }
        } message: {
            Text("The SSH agent helper is installed, but Sequel Ace will not use it until it has been relaunched. Open connections will be closed.", comment: "ssh agent settings : relaunch prompt message")
        }
    }
}

/// The agent choices, shared by the default in Preferences and the override
/// on each connection.
struct SASSHAgentSourcePicker<Label: View>: View {

    @Binding var source: String
    @Binding var customPath: String
    /// The per-connection picker starts on "Use Default" (an empty source).
    let includesUseDefault: Bool
    @ViewBuilder let label: () -> Label

    var body: some View {
        Picker(selection: $source, label: label()) {
            if includesUseDefault {
                Text("Use Default", comment: "ssh agent source : follow the default from preferences").tag("")
                Divider()
            }
            Text("Off", comment: "ssh agent source : no agent").tag(SASSHAgentSource.Kind.off.rawValue)
            Text("Automatic (from SSH config)", comment: "ssh agent source : whatever ssh itself would use")
                .tag(SASSHAgentSource.Kind.automatic.rawValue)
            Text("System Agent", comment: "ssh agent source : macOS ssh-agent").tag(SASSHAgentSource.Kind.system.rawValue)
            Text(verbatim: "1Password").tag(SASSHAgentSource.Kind.onePassword.rawValue)
            Text("Custom Socket", comment: "ssh agent source : user supplied socket path").tag(SASSHAgentSource.Kind.custom.rawValue)
        }
        if source == SASSHAgentSource.Kind.custom.rawValue {
            TextField(text: $customPath, prompt: Text(verbatim: "~/Library/…/agent.sock")) {
                Text("Agent Socket", comment: "ssh agent source : custom socket path field label")
            }
        }
    }
}
