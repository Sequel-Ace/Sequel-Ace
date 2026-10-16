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

    /// Posted when an SSH agent settings sheet closes: the default agent or the
    /// helper may have changed.
    static let settingsDidCloseNotification = Notification.Name("SASSHAgentSettingsDidClose")

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

    /// A sheet is not retained by its parent while it is up, and more than one
    /// can be up at once (Preferences and a connection window each open one).
    private static var presented: [SASSHAgentSettingsWindowController] = []

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
        Self.presented.append(self)
        parent.beginSheet(window) { [self] _ in
            Self.presented.removeAll { $0 === self }
            SASSHAgentPreferences.refreshSummary()
            NotificationCenter.default.post(name: SASSHAgentPreferences.settingsDidCloseNotification, object: nil)
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
            presentInstallError(SASSHAgentRelayInstaller.InstallError.wrongFolder.localizedDescription)
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

/// Under a connection's SSH Agent picker: which agent that choice comes to,
/// and whether the helper is ready for it — with a way into the settings when
/// it is not. Without this, "Use Default" says nothing about what will happen.
struct SASSHAgentConnectionStatus: View {

    let source: String
    let customPath: String
    /// So the line follows changes made in the settings sheet it opens.
    @AppStorage(SASSHAgentSource.DefaultsKey.defaultSource) private var defaultSource = ""
    @AppStorage(SASSHAgentSource.DefaultsKey.customSocketPath) private var defaultCustomPath = ""

    var body: some View {
        let installer = SASSHAgentRelayInstaller.shared
        let status = SASSHAgentRelayInstaller.connectionStatus(
            connectionSource: source, connectionCustomPath: customPath,
            defaultSource: defaultSource,
            defaultCustomPath: defaultCustomPath,
            status: installer?.status ?? .notInstalled,
            installedThisSession: installer?.installedThisSession ?? false)
        HStack(alignment: .firstTextBaseline) {
            Text(verbatim: status.text)
                .font(.callout)
                .foregroundColor(status.needsAttention ? .orange : .secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button {
                SASSHAgentPreferences.presentSettings(from: NSApp.keyWindow)
            } label: {
                Text("SSH Agent Settings…", comment: "connection view : open ssh agent settings button")
            }
            .controlSize(.small)
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
    @AppStorage(SASSHAgentSource.DefaultsKey.defaultSource) private var defaultSource = ""
    @AppStorage(SASSHAgentSource.DefaultsKey.customSocketPath) private var defaultCustomPath = ""

    var body: some View {
        Picker(selection: $source, label: label()) {
            if includesUseDefault {
                Text(verbatim: SASSHAgentRelayInstaller.useDefaultTitle(defaultSource: defaultSource,
                                                                        defaultCustomPath: defaultCustomPath)).tag("")
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

// MARK: - Legacy connection view

/// The SSH agent row in the XIB-based connection view's SSH tab: a popup for
/// the connection's own choice and, under it, what that choice comes to.
///
/// That tab is laid out with fixed frames in `ConnectionView.xib`. Rather than
/// renumber every frame there, the row is inserted here: the container grows
/// by the row's height, everything above the insertion point moves up with
/// its top edge, and the controls below stay where they are.
@objc final class SASSHAgentConnectionRow: NSObject {

    private static let addedHeight: CGFloat = 74

    private let popup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let status = NSTextField(wrappingLabelWithString: "")
    private weak var controller: SPConnectionController?
    private let onChange: () -> Void
    private var observations: [NSKeyValueObservation] = []
    private var notificationObservers: [NSObjectProtocol] = []
    /// The default agent as last shown, to ignore unrelated preference writes.
    private var shownDefault: [String] = []

    /// `anchor` is the control the row goes above (the SSH tab's time zone
    /// popup); `siblingsBelow` are views that sit under `container` in its
    /// superview and have to move down with its bottom edge.
    @objc(installInContainer:aboveView:siblingsBelow:controller:onChange:)
    static func install(in container: NSView, above anchor: NSView, siblingsBelow: [NSView],
                        controller: SPConnectionController, onChange: @escaping () -> Void) -> SASSHAgentConnectionRow {
        let row = SASSHAgentConnectionRow(controller: controller, onChange: onChange)
        let height = addedHeight
        let threshold = anchor.frame.maxY

        let resizesSubviews = container.autoresizesSubviews
        container.autoresizesSubviews = false
        var frame = container.frame
        frame.origin.y -= height
        frame.size.height += height
        container.frame = frame
        for view in container.subviews where view.frame.minY >= threshold {
            view.setFrameOrigin(NSPoint(x: view.frame.minX, y: view.frame.minY + height))
        }
        container.autoresizesSubviews = resizesSubviews
        for sibling in siblingsBelow {
            sibling.setFrameOrigin(NSPoint(x: sibling.frame.minX, y: sibling.frame.minY - height))
        }

        // Line the new label up with the label of the row below.
        let anchorLabel = container.subviews.compactMap { $0 as? NSTextField }.first {
            !$0.isEditable && $0.frame.maxX <= anchor.frame.minX + 4 && abs($0.frame.midY - anchor.frame.midY) < 8
        }
        let label = NSTextField(labelWithString: NSLocalizedString("SSH Agent:", comment: "network preferences : ssh agent row label"))
        label.alignment = anchorLabel?.alignment ?? .right
        label.font = anchorLabel?.font ?? .systemFont(ofSize: NSFont.systemFontSize)

        let statusY = anchor.frame.minY + 33
        let statusHeight: CGFloat = 42
        let popupY = statusY + statusHeight + 2
        row.popup.frame = NSRect(x: anchor.frame.minX, y: popupY, width: anchor.frame.width, height: anchor.frame.height)
        row.status.frame = NSRect(x: anchor.frame.minX + 3, y: statusY, width: anchor.frame.width - 6, height: statusHeight)
        label.frame = NSRect(x: anchorLabel?.frame.minX ?? 7, y: popupY + 5,
                             width: anchorLabel?.frame.width ?? 98, height: anchorLabel?.frame.height ?? 17)
        for view in [label, row.popup, row.status] as [NSView] {
            view.autoresizingMask = [.maxXMargin, .minYMargin]
            container.addSubview(view)
        }
        row.refresh()
        return row
    }

    private init(controller: SPConnectionController, onChange: @escaping () -> Void) {
        self.controller = controller
        self.onChange = onChange
        super.init()

        let choices: [(String, String)] = [
            (NSLocalizedString("Use Default", comment: "ssh agent source : follow the default from preferences"), ""),
            (NSLocalizedString("Off", comment: "ssh agent source : no agent"), SASSHAgentSource.Kind.off.rawValue),
            (NSLocalizedString("Automatic (from SSH config)", comment: "ssh agent source : whatever ssh itself would use"), SASSHAgentSource.Kind.automatic.rawValue),
            (NSLocalizedString("System Agent", comment: "ssh agent source : macOS ssh-agent"), SASSHAgentSource.Kind.system.rawValue),
            ("1Password", SASSHAgentSource.Kind.onePassword.rawValue),
            (NSLocalizedString("Custom Socket…", comment: "ssh agent source : user supplied socket path, asks for the path"), SASSHAgentSource.Kind.custom.rawValue),
        ]
        for (index, choice) in choices.enumerated() {
            popup.addItem(withTitle: choice.0)
            popup.lastItem?.representedObject = choice.1
            if index == 0 { popup.menu?.addItem(.separator()) }
        }
        popup.target = self
        popup.action = #selector(choose(_:))

        status.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        status.maximumNumberOfLines = 3
        // Wrap; only the last visible line may be cut short. (Truncating-tail
        // on its own turns the label into a single truncated line.)
        status.lineBreakMode = .byWordWrapping
        status.cell?.truncatesLastVisibleLine = true

        // Selecting a favorite sets these on the controller; follow it.
        observations = [
            controller.observe(\.sshAgentSource) { [weak self] _, _ in self?.refreshOnMain() },
            controller.observe(\.sshAgentSocketPath) { [weak self] _, _ in self?.refreshOnMain() },
        ]
        // The default agent and the helper's state change what "Use Default" means.
        // Any preference write in the app posts didChange, so only a change to the
        // agent keys refreshes; the helper can only change in the settings sheet.
        let center = NotificationCenter.default
        notificationObservers = [
            center.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
                guard let self, self.currentDefault() != self.shownDefault else { return }
                self.refresh()
            },
            center.addObserver(forName: SASSHAgentPreferences.settingsDidCloseNotification, object: nil, queue: .main) { [weak self] _ in
                self?.refresh()
            },
        ]
    }

    deinit {
        notificationObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    private func currentDefault() -> [String] {
        let defaults = UserDefaults.standard
        return [defaults.string(forKey: SASSHAgentSource.DefaultsKey.defaultSource) ?? "",
                defaults.string(forKey: SASSHAgentSource.DefaultsKey.customSocketPath) ?? ""]
    }

    private func refreshOnMain() {
        if Thread.isMainThread { refresh() } else { DispatchQueue.main.async { [weak self] in self?.refresh() } }
    }

    private func refresh() {
        let source = controller?.sshAgentSource ?? ""
        let path = controller?.sshAgentSocketPath ?? ""
        let known = SASSHAgentSource.Kind(rawValue: source) != nil ? source : ""
        if let index = popup.itemArray.firstIndex(where: { ($0.representedObject as? String) == known }) {
            popup.selectItem(at: index)
        }
        shownDefault = currentDefault()
        let defaultSource = shownDefault[0]
        let defaultCustomPath = shownDefault[1]
        popup.item(at: 0)?.title = SASSHAgentRelayInstaller.useDefaultTitle(defaultSource: defaultSource,
                                                                          defaultCustomPath: defaultCustomPath)
        let installer = SASSHAgentRelayInstaller.shared
        let state = SASSHAgentRelayInstaller.connectionStatus(
            connectionSource: source, connectionCustomPath: path,
            defaultSource: defaultSource,
            defaultCustomPath: defaultCustomPath,
            status: installer?.status ?? .notInstalled,
            installedThisSession: installer?.installedThisSession ?? false)
        status.stringValue = state.text
        status.textColor = state.needsAttention ? .systemOrange : .secondaryLabelColor
        status.toolTip = state.text
    }

    @objc private func choose(_ sender: NSPopUpButton) {
        guard let controller, let source = sender.selectedItem?.representedObject as? String else { return }
        var path = ""
        if source == SASSHAgentSource.Kind.custom.rawValue {
            guard let entered = Self.askForSocketPath(current: controller.sshAgentSocketPath ?? "") else {
                refresh()   // cancelled: put the popup back
                return
            }
            path = entered
        }
        controller.sshAgentSource = source
        controller.sshAgentSocketPath = path
        refresh()
        onChange()
    }

    /// The legacy tab has no room for another field, so a custom agent's
    /// socket path is asked for when "Custom Socket…" is chosen.
    private static func askForSocketPath(current: String) -> String? {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("SSH Agent Socket", comment: "connection view : custom ssh agent socket prompt title")
        alert.informativeText = NSLocalizedString("Enter the path of your SSH agent's socket.", comment: "connection view : custom ssh agent socket prompt message")
        alert.addButton(withTitle: NSLocalizedString("OK", comment: "OK button"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "cancel button"))
        let field = NSTextField(string: current)
        field.placeholderString = "~/Library/…/agent.sock"
        field.frame = NSRect(x: 0, y: 0, width: 320, height: 22)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let path = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }
}
