//
//  SPMCPPreferencePane.swift
//  Sequel Ace
//
//  Created for Sequel Ace by contributors.
//  See https://github.com/Sequel-Ace/Sequel-Ace/issues/2314
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

import AppKit

private let kMCPDefaultPort = 8765
private let kMCPMinPort     = 1024
private let kMCPMaxPort     = 65535

/// Preference pane for the built-in MCP (Model Context Protocol) server.
/// Lets users enable/disable the server and configure its port, read-only
/// mode and the default export folder.
@objc(SPMCPPreferencePane)
final class SPMCPPreferencePane: SPPreferencePane, SPPreferencePaneProtocol, NSTextFieldDelegate {

    // Always fetch the live standard defaults. Caching it (let defaults = .standard)
    // captures a stale instance when the pane is constructed at app-launch time and
    // the standard defaults are later replaced, breaking reads/writes.
    private var defaults: UserDefaults { UserDefaults.standard }

    private var enableCheckbox: NSButton!
    private var readOnlyCheckbox: NSButton!
    private var portField: NSTextField!
    private var statusLabel: NSTextField!
    private var exportPathField: NSTextField!
    private var endpointField: NSTextField!

    // MARK: - View lifecycle

    override func loadView() {
        let viewW: CGFloat = 564.0
        let viewH: CGFloat = 254.0
        let root = NSView(frame: NSRect(x: 0, y: 0, width: viewW, height: viewH))
        root.autoresizingMask = [.width, .height]

        // Frame-based panes report a fittingSize of 0, which makes the preferences
        // window fall back to its minimum height. Give the view an explicit height
        // so the window sizes to this pane's content, like the Auto Layout panes do.
        let heightC = NSLayoutConstraint(item: root, attribute: .height, relatedBy: .equal,
                                         toItem: nil, attribute: .notAnAttribute,
                                         multiplier: 1.0, constant: viewH)
        heightC.priority = .defaultHigh
        root.addConstraint(heightC)

        // Two-column layout (matching the other preference panes): right-aligned
        // labels in a left column, controls in a right column, all pinned to the top.
        let ctrlMask: NSView.AutoresizingMask  = [.width, .minYMargin]
        let labelMask: NSView.AutoresizingMask = [.minYMargin]

        let labelX: CGFloat   = 20.0
        let labelW: CGFloat   = 130.0
        let controlX: CGFloat = labelX + labelW + 12.0
        let controlW: CGFloat = viewW - 20.0 - controlX
        let chooseW: CGFloat  = 100.0
        var y: CGFloat        = 218.0

        // Server: enable, status, read-only
        let serverLabel = makeLabel(NSLocalizedString("Server:", comment: "MCP pref: server row label"),
                                    x: labelX, y: y, width: labelW)
        serverLabel.autoresizingMask = labelMask
        root.addSubview(serverLabel)

        enableCheckbox = NSButton(checkboxWithTitle: NSLocalizedString("Enable MCP Server (localhost only)",
                                                                       comment: "MCP pref: enable checkbox"),
                                  target: self, action: #selector(toggleMCPServer(_:)))
        enableCheckbox.frame = NSRect(x: controlX, y: y, width: controlW, height: 20)
        enableCheckbox.autoresizingMask = ctrlMask
        enableCheckbox.state = defaults.bool(forKey: SPMCPServerEnabled) ? .on : .off
        root.addSubview(enableCheckbox)
        y -= 20

        statusLabel = makeSmallLabel("", x: controlX, y: y, width: controlW)
        statusLabel.autoresizingMask = ctrlMask
        root.addSubview(statusLabel)
        y -= 24

        readOnlyCheckbox = NSButton(checkboxWithTitle: NSLocalizedString("Read-only mode (reject queries that modify data)",
                                                                         comment: "MCP pref: read-only checkbox"),
                                    target: self, action: #selector(toggleReadOnly(_:)))
        readOnlyCheckbox.frame = NSRect(x: controlX, y: y, width: controlW, height: 20)
        readOnlyCheckbox.autoresizingMask = ctrlMask
        readOnlyCheckbox.state = defaults.bool(forKey: SPMCPReadOnly) ? .on : .off
        root.addSubview(readOnlyCheckbox)
        y -= 34

        // Port
        let portLabel = makeLabel(NSLocalizedString("Port:", comment: "MCP pref: port label"),
                                  x: labelX, y: y + 2, width: labelW)
        portLabel.autoresizingMask = labelMask
        root.addSubview(portLabel)

        portField = NSTextField(frame: NSRect(x: controlX, y: y, width: 80, height: 22))
        portField.delegate = self
        portField.target = self
        portField.action = #selector(updatePort(_:))
        portField.stringValue = "\(currentPort)"
        portField.placeholderString = "8765"
        portField.autoresizingMask = labelMask
        root.addSubview(portField)
        y -= 22

        let portHint = makeSmallLabel(NSLocalizedString("Default: 8765. Any unprivileged port (1024–65535) may be used.",
                                                        comment: "MCP pref: port hint"),
                                      x: controlX, y: y, width: controlW)
        portHint.autoresizingMask = ctrlMask
        root.addSubview(portHint)
        y -= 30

        // Export folder
        let exportLabel = makeLabel(NSLocalizedString("Export folder:", comment: "MCP pref: export row label"),
                                    x: labelX, y: y + 2, width: labelW)
        exportLabel.autoresizingMask = labelMask
        root.addSubview(exportLabel)

        exportPathField = NSTextField(frame: NSRect(x: controlX, y: y, width: controlW - chooseW - 8, height: 22))
        exportPathField.isEditable = false
        exportPathField.isBezeled = true
        exportPathField.bezelStyle = .squareBezel
        exportPathField.stringValue = currentExportPath
        exportPathField.autoresizingMask = ctrlMask
        root.addSubview(exportPathField)

        let exportButton = NSButton(title: NSLocalizedString("Choose…", comment: "MCP pref: choose button"),
                                    target: self, action: #selector(chooseExportPath(_:)))
        exportButton.frame = NSRect(x: controlX + controlW - chooseW, y: y - 1, width: chooseW, height: 24)
        exportButton.autoresizingMask = [.minXMargin, .minYMargin]
        root.addSubview(exportButton)
        y -= 34

        // Endpoint (the one value every MCP client needs)
        let endpointLabel = makeLabel(NSLocalizedString("Endpoint:", comment: "MCP pref: endpoint row label"),
                                      x: labelX, y: y + 2, width: labelW)
        endpointLabel.autoresizingMask = labelMask
        root.addSubview(endpointLabel)

        endpointField = NSTextField(frame: NSRect(x: controlX, y: y, width: controlW - chooseW - 8, height: 22))
        endpointField.isEditable = false
        endpointField.isSelectable = true
        endpointField.isBezeled = true
        endpointField.bezelStyle = .squareBezel
        endpointField.font = NSFont.userFixedPitchFont(ofSize: NSFont.smallSystemFontSize)
        endpointField.stringValue = endpointURLString
        endpointField.autoresizingMask = ctrlMask
        root.addSubview(endpointField)

        let copyButton = NSButton(title: NSLocalizedString("Copy", comment: "MCP pref: copy endpoint button"),
                                  target: self, action: #selector(copyEndpoint(_:)))
        copyButton.frame = NSRect(x: controlX + controlW - chooseW, y: y - 1, width: chooseW, height: 24)
        copyButton.autoresizingMask = [.minXMargin, .minYMargin]
        root.addSubview(copyButton)
        y -= 24

        let endpointHint = makeSmallLabel(NSLocalizedString("Add this URL to any MCP client (Claude, Cursor, Cline, VS Code). This is the Streamable HTTP endpoint; SSE-only clients should use /sse instead of /mcp.",
                                                            comment: "MCP pref: endpoint hint"),
                                          x: controlX, y: y - 28, width: controlW)
        endpointHint.frame = NSRect(x: controlX, y: y - 28, width: controlW, height: 46)
        endpointHint.autoresizingMask = ctrlMask
        root.addSubview(endpointHint)

        refreshStatus()
        view = root
    }

    // MARK: - SPPreferencePaneProtocol

    func preferencePaneView() -> NSView {
        return view
    }

    func preferencePaneIcon() -> NSImage {
        if #available(macOS 11.0, *),
           let icon = NSImage(systemSymbolName: "point.3.connected.trianglepath.dotted", accessibilityDescription: nil) {
            return icon
        }
        return NSImage(named: NSImage.networkName) ?? NSImage()
    }

    func preferencePaneName() -> String {
        return NSLocalizedString("MCP Server", comment: "MCP preference pane name")
    }

    func preferencePaneIdentifier() -> String {
        return SPPreferenceToolbarMCP
    }

    func preferencePaneToolTip() -> String {
        return NSLocalizedString("MCP Server Preferences", comment: "MCP preference pane tooltip")
    }

    override func preferencePaneWillBeShown() {
        // SPPreferenceController calls this before -preferencePaneView, so the view
        // (and its outlets) may not exist yet. Touch the view to trigger lazy
        // loadView first; otherwise refreshStatus() would force-unwrap a nil outlet
        // and trap. (loadViewIfNeeded() is macOS 14+, so reference the view directly.)
        if !isViewLoaded { _ = view }
        refreshStatus()
        refreshEndpoint()
    }

    // MARK: - Actions

    /// Toggle the MCP server enabled state.
    @objc func toggleMCPServer(_ sender: Any?) {
        let enabled = enableCheckbox.state == .on
        defaults.set(enabled, forKey: SPMCPServerEnabled)

        // Reflect the enabled/disabled text right away (it does not depend on the
        // server having started). SPAppController observes the defaults change and
        // starts/stops the server asynchronously, so refresh again shortly after to
        // pick up the running state.
        refreshStatus()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.refreshStatus()
        }
    }

    /// Toggle read-only enforcement.
    @objc func toggleReadOnly(_ sender: Any?) {
        defaults.set(readOnlyCheckbox.state == .on, forKey: SPMCPReadOnly)
    }

    /// Validate and save a new port number.
    @objc func updatePort(_ sender: NSTextField) {
        let digits = sender.stringValue.replacingOccurrences(of: " ", with: "")
        // Reject non-numeric input (integerValue would silently accept e.g. "8765abc").
        let allDigits = !digits.isEmpty &&
            digits.rangeOfCharacter(from: CharacterSet.decimalDigits.inverted) == nil
        let port = Int(digits) ?? 0
        if !allDigits || port < kMCPMinPort || port > kMCPMaxPort {
            let alert = NSAlert()
            alert.messageText = NSLocalizedString("Invalid Port", comment: "MCP pref: invalid port alert")
            alert.informativeText = String(format: NSLocalizedString("Port must be between %ld and %ld.",
                                                                     comment: "MCP pref: port range"),
                                           kMCPMinPort, kMCPMaxPort)
            alert.runModal()
            sender.stringValue = "\(currentPort)"
            return
        }

        defaults.set(port, forKey: SPMCPServerPort)
        refreshEndpoint()

        // Persisting the new port posts NSUserDefaultsDidChangeNotification, which
        // SPAppController observes and uses to restart the server on the new port if
        // it is running. We just refresh the status label after it has had time to
        // rebind.
        if defaults.bool(forKey: SPMCPServerEnabled) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.refreshStatus()
            }
        }
    }

    /// Open a panel to choose the default export directory.
    @objc func chooseExportPath(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = NSLocalizedString("Choose", comment: "MCP pref: open panel prompt")
        panel.message = NSLocalizedString("Choose the default folder for MCP query exports.",
                                          comment: "MCP pref: open panel message")

        if let current = defaults.string(forKey: SPMCPExportPath), !current.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: current)
        }

        let apply: (NSApplication.ModalResponse) -> Void = { [weak self] result in
            if result == .OK, let url = panel.url {
                self?.defaults.set(url.path, forKey: SPMCPExportPath)
                self?.exportPathField.stringValue = url.path
                // Persist a security-scoped bookmark so a sandboxed build can still
                // write to a custom folder (one outside the default Downloads
                // entitlement) after relaunch, when the open-panel grant is gone.
                _ = SecureBookmarkManager.sharedInstance.addBookmarkFor(
                    url: url,
                    options: URL.BookmarkCreationOptions.withSecurityScope.rawValue,
                    isForStaleBookmark: false,
                    isForKnownHostsFile: false)
            }
        }
        // Present as a sheet when attached to a window, otherwise fall back to a
        // modal panel so this never force-unwraps a nil window.
        if let window = view.window {
            panel.beginSheetModal(for: window, completionHandler: apply)
        } else {
            apply(panel.runModal())
        }
    }

    @objc func copyEndpoint(_ sender: Any?) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(endpointURLString, forType: .string)
    }

    // MARK: - Private helpers

    private func refreshStatus() {
        let running = SPMCPServer.shared.isRunning
        let enabled = defaults.bool(forKey: SPMCPServerEnabled)

        if !enabled {
            statusLabel.stringValue = NSLocalizedString("MCP server is disabled.", comment: "MCP pref: status disabled")
            statusLabel.textColor = .secondaryLabelColor
        } else if running {
            statusLabel.stringValue = String(format: NSLocalizedString("MCP server is running on http://127.0.0.1:%ld/mcp",
                                                                       comment: "MCP pref: status running"),
                                             currentPort)
            statusLabel.textColor = .systemGreen
        } else {
            statusLabel.stringValue = NSLocalizedString("MCP server is not running.", comment: "MCP pref: status stopped")
            statusLabel.textColor = .systemOrange
        }
    }

    private func refreshEndpoint() {
        endpointField.stringValue = endpointURLString
    }

    private var endpointURLString: String {
        return "http://127.0.0.1:\(currentPort)/mcp"
    }

    private var currentPort: Int {
        let p = defaults.integer(forKey: SPMCPServerPort)
        return (p >= kMCPMinPort && p <= kMCPMaxPort) ? p : kMCPDefaultPort
    }

    private var currentExportPath: String {
        if let path = defaults.string(forKey: SPMCPExportPath), !path.isEmpty { return path }
        return NSSearchPathForDirectoriesInDomains(.downloadsDirectory, .userDomainMask, true).first
            ?? NSTemporaryDirectory()
    }

    // MARK: - Label factory helpers

    private func makeLabel(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat) -> NSTextField {
        let tf = NSTextField(labelWithString: text)
        tf.frame = NSRect(x: x, y: y, width: width, height: 18)
        tf.alignment = .right
        return tf
    }

    private func makeSmallLabel(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat) -> NSTextField {
        let tf = NSTextField(wrappingLabelWithString: text)
        tf.frame = NSRect(x: x, y: y, width: width, height: 16)
        tf.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        tf.textColor = .secondaryLabelColor
        return tf
    }
}
