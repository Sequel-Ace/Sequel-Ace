//
//  SAClaudeSettingsSecurity.swift
//  Sequel Ace
//
//  The Settings window's SSH and security pane and MCP server pane rows, registered with each window's
//  SAClaudeSettingsViewRegistry from SAClaudeSettingsPanes.register(in:). Every row calls the old pane controller's
//  own code (SPNetworkPreferencePane, SPFilePreferencePane, SPMCPPreferencePane), reached through the preference
//  controller:
//
//  - SSH program: the path in a field look ("System default") + Change… → -pickSSHClient: (its warning alert, path
//    field and file browser with the "Show hidden files" accessory).
//  - SSH config / known hosts: pills over the chooser menus the pane builds from the granted files
//    (-sshFileMenuTitlesForKnownHosts:); choosing runs the pane's chooser action (-chooseSSHFileMenuItemAtIndex:…);
//    the menus are rebuilt whenever the granted files change.
//  - SSL cipher order and the accessible files: the panes' own table views (with their scroll views, data sources,
//    delegates, drag registration and double-click) re-parented into a disclosure under the row, in the skin's quiet
//    grid look; Reset / Add Files… / Revoke Selected Files call the panes' actions; the stale hint follows the pane.
//  - MCP: the server switch (-setServerEnabled:) with the pane's status line under it, live as the server starts and
//    stops; the port field validates, alerts and restarts through -applyPortWithText:; export folder Choose… and
//    address Copy are the pane's actions. Read only is a plain switch.
//
//  App target only.
//

import AppKit
import Combine
import SwiftUI

private func localized(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

enum SAClaudeSettingsSecurityPanes {

    /// Called from SAClaudeSettingsPanes.register(in:), once per Settings window.
    @MainActor static func register(in registry: SAClaudeSettingsViewRegistry) {
        let disclosure = SAClaudeSettingsListDisclosure()
        let mcp = SAClaudeSettingsMCPModel()

        // SSH and security ▸ SSH tunnels.
        registry.registerControl(for: .sshProgram) { context in
            SAClaudeSettingsSSHProgramControl(row: context.row, host: context.host)
        }
        registry.registerControl(forDynamicSource: "sshConfig") { context in
            SAClaudeSettingsSSHFilePill(row: context.row, knownHosts: false, host: context.host)
        }
        registry.registerControl(forDynamicSource: "knownHosts") { context in
            SAClaudeSettingsSSHFilePill(row: context.row, knownHosts: true, host: context.host)
        }
        // SSH and security ▸ Encryption, File access.
        registry.registerRow("cipherOrder") { context in
            SAClaudeSettingsCipherRow(context: context, disclosure: disclosure)
        }
        registry.registerRow("accessibleFiles") { context in
            SAClaudeSettingsAccessibleFilesRow(context: context, disclosure: disclosure)
        }

        // MCP server.
        registry.registerRow("mcpServer") { context in
            SAClaudeSettingsMCPServerRow(context: context, mcp: mcp.attached(to: context.host))
        }
        registry.registerControl(forRow: "mcpPort") { context in
            SAClaudeSettingsMCPPortField(row: context.row, mcp: mcp.attached(to: context.host))
        }
        registry.registerControl(for: .mcpExportFolder) { context in
            SAClaudeSettingsMCPExportFolderControl(row: context.row, mcp: mcp.attached(to: context.host))
        }
        registry.registerControl(for: .mcpAddress) { context in
            SAClaudeSettingsMCPAddressControl(row: context.row, mcp: mcp.attached(to: context.host))
        }
    }
}

// MARK: - Shared pieces

/// A read-only value in a field look (`.form` chrome, never focused): a path or address in mono, middle-truncated,
/// selectable (to copy it), the whole value as its tooltip; `placeholder` in the muted colour when there is none.
/// `width` nil sizes the field to the whole value (the MCP address).
struct SAClaudeSettingsValueField: View {
    @EnvironmentObject private var palette: SAClaudeSwiftUIPalette
    let value: String
    var placeholder: String = ""
    let accessibilityName: String
    var width: CGFloat? = 190

    var body: some View {
        let shown = value.isEmpty ? placeholder : value
        SAClaudeFieldChrome(isFocused: false, size: .form) {
            Text(shown)
                .textSelection(.enabled)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundColor(value.isEmpty ? palette.muted : palette.text)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: width == nil ? nil : .infinity, alignment: .leading)
        }
        .frame(width: width)
        .fixedSize(horizontal: width == nil, vertical: false)
        .help(shown)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityName))
        .accessibilityValue(Text(shown))
    }
}

/// "Edit list" / "N files": a pill that opens and closes the list under its row, with a chevron that turns. VoiceOver
/// reads its title, whether the list is shown, and the row's name as the hint.
struct SAClaudeSettingsDisclosureButton: View {
    let title: String
    let isOpen: Bool
    let accessibilityName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8.5, weight: .semibold))
                    .rotationEffect(.degrees(isOpen ? 180 : 0))
            }
        }
        .buttonStyle(SAClaudeSettingsPillButtonStyle())
        .accessibilityLabel(Text(title))
        .accessibilityHint(Text(accessibilityName))
        .accessibilityValue(Text(isOpen ? localized("ClaudeSettings.ui.infoShown") : localized("ClaudeSettings.ui.infoHidden")))
    }
}

/// Which disclosed lists are open in one Settings window (they stay open across pane switches). A reveal that targets a
/// list's row (Settings opened on the accessible files, e.g. from the launch alert) opens it, once per reveal.
@MainActor
final class SAClaudeSettingsListDisclosure: ObservableObject {
    @Published private(set) var openRowIDs: Set<String> = []
    private var handledRevealSerials: [String: Int] = [:]

    func isOpen(_ rowID: String) -> Bool { openRowIDs.contains(rowID) }

    func toggle(_ rowID: String) {
        if openRowIDs.contains(rowID) { openRowIDs.remove(rowID) } else { openRowIDs.insert(rowID) }
    }

    func open(_ rowID: String) {
        if !openRowIDs.contains(rowID) { openRowIDs.insert(rowID) }
    }

    func follow(_ reveal: SAClaudeSettingsReveal?, rowID: String) {
        guard let reveal, reveal.rowID == rowID, handledRevealSerials[rowID] != reveal.serial else { return }
        handledRevealSerials[rowID] = reveal.serial
        open(rowID)
    }
}

/// A list under its row: the inset box holding the hosted table, then a footer line (hint at the left, buttons right).
struct SAClaudeSettingsDisclosedList<Footer: View>: View {
    @EnvironmentObject private var palette: SAClaudeSwiftUIPalette
    let table: NSTableView
    let home: NSView?
    let height: CGFloat
    @ViewBuilder let footer: () -> Footer

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let scrollView = table.enclosingScrollView {
                SAClaudeSettingsHostedTable(scrollView: scrollView, table: table, home: home,
                                            hairline: NSColor(palette.hairline), isDark: palette.isDark,
                                            surface: palette.surface)
                    .frame(height: height)
            }
            HStack(spacing: 8) { footer() }
        }
        .padding(.horizontal, SAClaudeSettingsMetrics.rowHorizontalPadding)
        .padding(.bottom, 12)
    }
}

/// Hosts a pane's existing table — its scroll view moved out of the hidden XIB pane view — inside the SwiftUI
/// content: the same table, data source, delegate, drag registration and double-click. The skin skips everything
/// inside the hosting view, so the table gets the skin's quiet grid look here (theme background, no alternating
/// rows, hairline grid, Claude header), again whenever the palette changes; the box has a 7pt radius and a hairline.
/// When the disclosure closes the scroll view goes back into its pane view (hidden), so the pane's outlets and the
/// table's window stay as they were.
struct SAClaudeSettingsHostedTable: NSViewRepresentable {
    let scrollView: NSScrollView
    let table: NSTableView
    /// Where the scroll view lives while it isn't shown: its pane's view.
    let home: NSView?
    let hairline: NSColor
    /// Restyle triggers.
    let isDark: Bool
    let surface: Color

    static let containerIdentifier = NSUserInterfaceItemIdentifier("SAClaudeSettingsHostedTable")
    static let radius: CGFloat = 7

    final class Coordinator {
        let scrollView: NSScrollView
        weak var home: NSView?

        init(scrollView: NSScrollView, home: NSView?) {
            self.scrollView = scrollView
            self.home = home
        }

        func attach(to container: NSView) {
            guard scrollView.superview !== container else { return }
            scrollView.removeFromSuperview()
            // Its XIB size minimums (≥ 200 wide, ≥ 160/200 high) would fight the frame the row gives it.
            NSLayoutConstraint.deactivate(scrollView.constraints.filter {
                ($0.firstItem as? NSView) === scrollView && $0.secondItem == nil
            })
            scrollView.translatesAutoresizingMaskIntoConstraints = true
            scrollView.autoresizingMask = [.width, .height]
            scrollView.frame = container.bounds
            container.addSubview(scrollView)
        }

        func detach(from container: NSView) {
            guard scrollView.superview === container else { return }
            scrollView.removeFromSuperview()
            home?.addSubview(scrollView)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(scrollView: scrollView, home: home) }

    func makeNSView(context: Context) -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 160))
        container.identifier = Self.containerIdentifier
        container.wantsLayer = true
        container.layer?.cornerRadius = Self.radius
        container.layer?.masksToBounds = true
        container.layer?.borderWidth = 1
        context.coordinator.attach(to: container)
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        context.coordinator.attach(to: container)
        container.layer?.borderColor = hairline.cgColor
        scrollView.borderType = .noBorder
        SAClaudeWindowSkin.styleTable(table, SAClaudeSheetColours.current())
    }

    static func dismantleNSView(_ container: NSView, coordinator: Coordinator) {
        coordinator.detach(from: container)
    }
}

// MARK: - SSH program

/// The ssh binary: its path in a field look ("System default" while unset) and Change…, which runs the Network pane's
/// own chooser (-pickSSHClient:: the "Unsupported configuration!" warning with the path field and a file browser).
struct SAClaudeSettingsSSHProgramControl: View {
    @EnvironmentObject private var store: SAClaudeSettingsStore
    let row: SAClaudeSettingRow
    weak var host: SAClaudeSettingsWindowHost?

    static let key = "SSHClientPath"   // SPSSHClientPath

    var body: some View {
        let pane = host?.controller?.networkPreferencePane
        HStack(spacing: 6) {
            SAClaudeSettingsValueField(value: store[string: Self.key],
                                       placeholder: localized("ClaudeSettings.sshProgram.systemDefault"),
                                       accessibilityName: localized(row.nameKey))
            Button(localized("ClaudeSettings.sshProgram.change")) { pane?.pickSSHClient(nil) }
                .buttonStyle(SAClaudeSettingsPillButtonStyle())
                .disabled(pane == nil)
        }
        .fixedSize()
    }
}

// MARK: - SSH config and known hosts

/// SSH config file / Known hosts file: the menu the Network pane builds in its chooser ("Sequel Ace default", for known
/// hosts "Use known hosts from ssh config (ADVANCED)", every granted file, "Other file..."), the item it would select
/// for the stored key (`SAClaudeSettingsRules.sshFileSelection`), and choosing runs the pane's chooser action — which
/// writes the same string keys (ssh_config / known_hosts, and SSHConfigContainsUserKnownHostsFile), opens the file
/// panel for "Other file..." and makes its ADVANCED checks. The menu is rebuilt when the granted files change.
struct SAClaudeSettingsSSHFilePill: View {
    @EnvironmentObject private var store: SAClaudeSettingsStore
    let row: SAClaudeSettingRow
    let knownHosts: Bool
    weak var host: SAClaudeSettingsWindowHost?

    @State private var titles: [String?] = []
    /// Bumped after a choice: the pop-up is rebuilt on the stored value (a cancelled "Other file..." panel leaves the
    /// key as it was, which the pop-up would otherwise not be told about).
    @State private var generation = 0

    static let configKey = "ssh_config"                           // SPSSHConfigFile
    static let knownHostsKey = "known_hosts"                      // SPSSHUsualKnownHostsFile
    static let defaultKnownHostsKey = ".keys/ssh_known_hosts_strict"   // SPSSHDefaultKnownHostsFile, read as a key

    private var pane: SPNetworkPreferencePane? { host?.controller?.networkPreferencePane }

    var body: some View {
        let stored = store.defaults.string(forKey: knownHosts ? Self.knownHostsKey : Self.configKey)
        let defaultValue = knownHosts ? store.defaults.string(forKey: Self.defaultKnownHostsKey)
                                      : Bundle.main.path(forResource: Self.configKey, ofType: "")
        let selection = SAClaudeSettingsRules.sshFileSelection(
            titles: titles, knownHosts: knownHosts, stored: stored, defaultValue: defaultValue,
            advancedTitle: NSLocalizedString("Use known hosts from ssh config (ADVANCED)",
                                             comment: "Use known hosts from ssh config (ADVANCED)"))
        let (items, selected) = Self.menu(titles: titles, selection: selection)
        SAClaudePopUpPill(items: items, selectedIndex: selected, accessibilityLabel: localized(row.nameKey)) { index in
            guard index < titles.count, let pane else { return }
            pane.chooseSSHFileMenuItem(at: index, knownHosts: knownHosts)
            reload()
            generation += 1
        }
        .id(generation)
        .fixedSize()
        .disabled(pane == nil)
        .onAppear(perform: reload)
        // A file granted or revoked anywhere (the list below, "Other file...", the MCP export folder, a connection).
        .onReceive(NotificationCenter.default.publisher(for: .SPBookmarksChanged).receive(on: DispatchQueue.main)) { _ in
            reload()
        }
    }

    static func menu(titles: [String?], selection: SAClaudeSettingsRules.SSHFileSelection) -> ([SAClaudePopUpItem], Int) {
        var items = titles.map { $0.map { SAClaudePopUpItem($0) } ?? .separator }
        switch selection {
        case .index(let index):
            return (items, index)
        case .missing(let path):
            items += [.separator, SAClaudePopUpItem(path, isEnabled: false)]
            return (items, items.count - 1)
        }
    }

    private func reload() {
        let fresh = (pane?.sshFileMenuTitles(forKnownHosts: knownHosts) ?? []).map { $0 as? String }
        if fresh != titles { titles = fresh }
    }
}

// MARK: - SSL cipher order

/// SSL cipher order: "Edit list" discloses the Network pane's cipher table (drag to reorder, below "Disabled Cipher
/// Suites" to disable — the pane writes SSLCipherList on each drop) and Reset (-resetCipherList:, enabled while the
/// list is customised, as the XIB bound it).
struct SAClaudeSettingsCipherRow: View {
    @EnvironmentObject private var store: SAClaudeSettingsStore
    let context: SAClaudeSettingsRowContext
    @ObservedObject var disclosure: SAClaudeSettingsListDisclosure

    static let key = "SSLCipherList"   // SPSSLCipherListKey
    static let listHeight: CGFloat = 220

    var body: some View {
        let row = context.row
        let pane = context.controller?.networkPreferencePane
        let isOpen = disclosure.isOpen(row.id)
        VStack(alignment: .leading, spacing: 0) {
            context.standardRow {
                SAClaudeSettingsDisclosureButton(title: localized("ClaudeSettings.cipherOrder.editList"), isOpen: isOpen,
                                                 accessibilityName: localized(row.nameKey)) { disclosure.toggle(row.id) }
                    .disabled(pane == nil)
            }
            if isOpen, let pane, let table = pane.cipherTableView {
                SAClaudeSettingsDisclosedList(table: table, home: pane.view, height: Self.listHeight) {
                    Spacer(minLength: 0)
                    Button(localized("ClaudeSettings.cipherOrder.reset")) { pane.resetCipherList(nil) }
                        .buttonStyle(SAClaudeSettingsPillButtonStyle())
                        .disabled(store.defaults.object(forKey: Self.key) == nil)
                        .help(localized("ClaudeSettings.cipherOrder.resetHelp"))
                }
            }
        }
        .onReceive(context.model.$reveal.receive(on: DispatchQueue.main)) { disclosure.follow($0, rowID: row.id) }
    }
}

// MARK: - Accessible files

/// Tells the Settings window that the Files pane reloaded its list (SPFilePreferencePane -loadBookmarks, which runs
/// on showing the pane, after Add Files…, Revoke and a re-grant, and whenever the granted files change).
@objc(SAClaudeSettingsFileAccess)
final class SAClaudeSettingsFileAccess: NSObject {
    static let listDidReloadNotification = Notification.Name("SAClaudeSettingsFileListDidReload")

    @objc static func listDidReload() {
        NotificationCenter.default.post(name: listDidReloadNotification, object: nil)
    }
}

/// Files Sequel Ace can open: "N files" discloses the Files pane's list (stale entries red; double-click one to
/// re-grant it), then the stale hint while there are stale entries, Revoke Selected Files (enabled on a selection) and
/// Add Files… — the pane's own actions and open panel (with its "Show hidden files" accessory).
struct SAClaudeSettingsAccessibleFilesRow: View {
    @EnvironmentObject private var palette: SAClaudeSwiftUIPalette
    let context: SAClaudeSettingsRowContext
    @ObservedObject var disclosure: SAClaudeSettingsListDisclosure

    @State private var count = 0
    @State private var hasStale = false
    @State private var canRevoke = false

    static let listHeight: CGFloat = 170

    private var pane: SPFilePreferencePane? { context.controller?.filePreferencePane }

    var body: some View {
        let row = context.row
        let isOpen = disclosure.isOpen(row.id)
        VStack(alignment: .leading, spacing: 0) {
            context.standardRow {
                SAClaudeSettingsDisclosureButton(title: String(format: localized(SAClaudeSettingsRules.accessibleFilesCountKey(count)), count),
                                                 isOpen: isOpen, accessibilityName: localized(row.nameKey)) {
                    disclosure.toggle(row.id)
                }
                .disabled(pane == nil)
            }
            if isOpen, let pane, let table = pane.grantedFilesTableView {
                SAClaudeSettingsDisclosedList(table: table, home: pane.view, height: Self.listHeight) {
                    if hasStale {
                        Text(localized("ClaudeSettings.accessibleFiles.staleHint"))
                            .font(SAClaudeSettingsMetrics.descriptionFont)
                            .foregroundColor(palette.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Button(localized("ClaudeSettings.accessibleFiles.revoke")) { pane.revokeBookmark(nil) }
                        .buttonStyle(SAClaudeSettingsPillButtonStyle())
                        .disabled(!canRevoke)
                    Button(localized("ClaudeSettings.accessibleFiles.add")) { pane.addBookmark(nil) }
                        .buttonStyle(SAClaudeSettingsPillButtonStyle())
                }
            }
        }
        .onAppear(perform: refresh)
        .onReceive(context.model.$reveal.receive(on: DispatchQueue.main)) { disclosure.follow($0, rowID: row.id) }
        .onReceive(NotificationCenter.default.publisher(for: SAClaudeSettingsFileAccess.listDidReloadNotification)
                    .receive(on: DispatchQueue.main)) { _ in refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSTableView.selectionDidChangeNotification)) { note in
            if let table = pane?.grantedFilesTableView, note.object as? NSTableView === table { refresh() }
        }
    }

    private func refresh() {
        guard let pane else { return }
        let newCount = Int(pane.grantedFileCount)
        if count != newCount { count = newCount }
        if hasStale != pane.weHaveStaleBookmarks { hasStale = pane.weHaveStaleBookmarks }
        let selected = (pane.grantedFilesTableView?.selectedRowIndexes.count ?? 0) > 0
        if canRevoke != selected { canRevoke = selected }
    }
}

// MARK: - MCP server

/// The MCP rows' link to the MCP pane controller, and the status line's text.
@MainActor
final class SAClaudeSettingsMCPModel: ObservableObject {
    weak var host: SAClaudeSettingsWindowHost?
    @Published private(set) var status: SAClaudeSettingsRules.MCPStatus = .disabled
    @Published private(set) var statusText = ""

    static let enabledKey = "SPMCPServerEnabled"   // SPMCPServerEnabled
    static let portKey = "SPMCPServerPort"         // SPMCPServerPort

    var pane: SPMCPPreferencePane? { host?.controller?.mcpPreferencePane }

    /// Keeps `host` (the window's) for the rows that use this model.
    func attached(to host: SAClaudeSettingsWindowHost?) -> SAClaudeSettingsMCPModel {
        if let host, self.host !== host { self.host = host }
        return self
    }

    /// The server switch: on reads the key; set runs the pane's checkbox action (writes the key — SPAppController
    /// starts or stops the server — and refreshes the status now and 0.3 s later).
    var serverEnabled: Bool {
        get { host?.store.defaults.bool(forKey: Self.enabledKey) ?? UserDefaults.standard.bool(forKey: Self.enabledKey) }
        set {
            objectWillChange.send()
            if let pane {
                pane.setServerEnabled(newValue)
            } else {
                host?.store.write(newValue, forKey: Self.enabledKey)
            }
            refreshStatus()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.refreshStatus() }
        }
    }

    func refreshStatus() {
        guard let pane else { return }
        let newStatus = pane.status
        let newText = pane.statusText
        if status != newStatus { status = newStatus }
        if statusText != newText { statusText = newText }
    }

    /// The pane's port validation: accepted, saved (the server restarts on it if running); refused, its "Invalid Port"
    /// alert. Returns whether it was accepted.
    @discardableResult
    func applyPort(_ text: String) -> Bool {
        if let pane { return pane.applyPort(text: text) }
        guard let port = SAClaudeSettingsRules.mcpPort(fromText: text) else { return false }
        host?.store.write(port, forKey: Self.portKey)
        return true
    }
}

/// Let AI tools connect: the switch, then the pane's status line under it — disabled, running on its address, or not
/// running — following the server as it starts and stops (SPMCPServer posts runningStateDidChangeNotification) and
/// the enabled and port keys however they change.
struct SAClaudeSettingsMCPServerRow: View {
    @EnvironmentObject private var store: SAClaudeSettingsStore
    @EnvironmentObject private var palette: SAClaudeSwiftUIPalette
    let context: SAClaudeSettingsRowContext
    @ObservedObject var mcp: SAClaudeSettingsMCPModel

    var body: some View {
        let name = localized(context.row.nameKey)
        VStack(alignment: .leading, spacing: 0) {
            context.standardRow {
                Toggle(isOn: $mcp.serverEnabled) { Text(name) }
                    .toggleStyle(SAClaudeSwitchToggleStyle(showsLabel: false))
                    .accessibilityLabel(Text(name))
            }
            if !mcp.statusText.isEmpty {
                Text(mcp.statusText)
                    .font(SAClaudeSettingsMetrics.descriptionFont)
                    .foregroundColor(statusColour)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, SAClaudeSettingsMetrics.rowHorizontalPadding)
                    .padding(.top, -3)
                    .padding(.bottom, SAClaudeSettingsMetrics.rowVerticalPadding)
            }
        }
        .onAppear { mcp.refreshStatus() }
        .onReceive(NotificationCenter.default.publisher(for: SPMCPServer.runningStateDidChangeNotification)
                    .receive(on: DispatchQueue.main)) { _ in mcp.refreshStatus() }
        .onChange(of: store[bool: SAClaudeSettingsMCPModel.enabledKey]) { _ in mcp.refreshStatus() }
        .onChange(of: store[int: SAClaudeSettingsMCPModel.portKey]) { _ in mcp.refreshStatus() }
    }

    /// The pane's colours: green running, orange not running; disabled muted.
    private var statusColour: Color {
        switch mcp.status {
        case .disabled: return palette.muted
        case .running: return Color(nsColor: .systemGreen)
        case .stopped: return Color(nsColor: .systemOrange)
        }
    }
}

/// Port: a small Claude field. Return, leaving the field or a commit request (pane switch, window close) hand the
/// typed text to the pane's validation: an accepted port is saved — SPAppController restarts a running server on it —
/// and a refused one (not digits, outside 1024–65535) shows the pane's "Invalid Port" alert while the field goes back
/// to the current port. Escape restores it too. Shows the port in use (an unset or out-of-range value is 8765).
struct SAClaudeSettingsMCPPortField: View {
    @EnvironmentObject private var store: SAClaudeSettingsStore
    let row: SAClaudeSettingRow
    @ObservedObject var mcp: SAClaudeSettingsMCPModel

    @State private var text = ""
    @FocusState private var isFocused: Bool
    @Environment(\.claudeCommitRequests) private var commitRequests

    private var port: Int { SAClaudeSettingsRules.mcpEffectivePort(stored: store[int: SAClaudeSettingsMCPModel.portKey]) }

    var body: some View {
        SAClaudeFieldChrome(isFocused: isFocused, size: .form) {
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .font(SAClaudeSwiftUIMetrics.bodyFont.monospacedDigit())
                .focused($isFocused)
                .onSubmit(commit)
                .onExitCommand(perform: revert)
                .accessibilityLabel(Text(localized(row.nameKey)))
        }
        .frame(width: 64)
        .onAppear(perform: revert)
        .onChange(of: port) { _ in if !isFocused { revert() } }
        .onChange(of: isFocused) { focused in if !focused { commit() } }
        .onReceive(commitRequests) { if isFocused { commit() } }
    }

    private func revert() {
        text = String(port)
    }

    /// Unchanged text does nothing. An accepted port is written now (a commit request needs it before the view goes);
    /// a refused one's alert runs on the next turn, outside the focus change, with the field already reverted.
    func commit() {
        guard text != String(port) else { return }
        let typed = text
        if SAClaudeSettingsRules.mcpPort(fromText: typed) != nil {
            mcp.applyPort(typed)
            revert()
        } else {
            revert()
            DispatchQueue.main.async { mcp.applyPort(typed) }
        }
    }
}

/// Export folder: the folder in a field look (Downloads while none is chosen) and Choose… — the pane's panel, which
/// saves the folder and grants it (a bookmark: it shows in the accessible files and the SSH pills).
struct SAClaudeSettingsMCPExportFolderControl: View {
    @EnvironmentObject private var store: SAClaudeSettingsStore
    let row: SAClaudeSettingRow
    @ObservedObject var mcp: SAClaudeSettingsMCPModel

    static let key = "SPMCPExportPath"   // SPMCPExportPath

    var body: some View {
        let pane = mcp.pane
        let stored = store[string: Self.key]
        HStack(spacing: 6) {
            SAClaudeSettingsValueField(value: pane?.currentExportPath ?? stored, accessibilityName: localized(row.nameKey))
            Button(NSLocalizedString("Choose…", comment: "MCP pref: choose button")) { pane?.chooseExportPath(nil) }
                .buttonStyle(SAClaudeSettingsPillButtonStyle())
                .disabled(pane == nil)
        }
        .fixedSize()
    }
}

/// Address: the endpoint for the port in use (selectable) and Copy (the pane's -copyEndpoint:).
struct SAClaudeSettingsMCPAddressControl: View {
    @EnvironmentObject private var store: SAClaudeSettingsStore
    let row: SAClaudeSettingRow
    @ObservedObject var mcp: SAClaudeSettingsMCPModel

    var body: some View {
        let port = SAClaudeSettingsRules.mcpEffectivePort(stored: store[int: SAClaudeSettingsMCPModel.portKey])
        let address = SAClaudeSettingsRules.mcpEndpoint(port: port)
        HStack(spacing: 6) {
            SAClaudeSettingsValueField(value: address, accessibilityName: localized(row.nameKey), width: nil)
            Button(NSLocalizedString("Copy", comment: "MCP pref: copy endpoint button")) {
                if let pane = mcp.pane {
                    pane.copyEndpoint(nil)
                } else {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(address, forType: .string)
                }
            }
            .buttonStyle(SAClaudeSettingsPillButtonStyle())
        }
        .fixedSize()
    }
}
