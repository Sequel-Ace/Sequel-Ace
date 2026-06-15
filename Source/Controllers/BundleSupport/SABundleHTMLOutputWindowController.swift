//
//  SABundleHTMLOutputWindowController.swift
//  Sequel Ace
//
//  Created as part of the WebView to WKWebView migration.
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import SwiftUI
import WebKit
import Combine
import UniformTypeIdentifiers

/// WKWebView-based replacement for the legacy SPBundleHTMLOutputController:
/// the window bundles display their HTML output in. Hosts a SwiftUI SAWebView
/// and recreates the legacy `window.system` JavaScript API via SABundleJSBridge.
@objc(SABundleHTMLOutputWindowController)
final class SABundleHTMLOutputWindowController: NSWindowController, NSWindowDelegate {

    @objc var windowUUID: String = ""
    @objc var docUUID: String = ""
    @objc var suppressExceptionAlerting: Bool = false

    /// Optional hook invoked when the window is about to close. Lets a caller attach
    /// close-time behavior (e.g. recording that a one-time help window has been shown)
    /// without this generic controller needing to know the specifics.
    @objc var windowWillCloseHandler: (() -> Void)?

    private let model = SAWebViewModel()
    private let bridge = SABundleJSBridge()
    private var titleSubscription: AnyCancellable?

    // Saves the window's frame when a caller supplies a temporary one, so it can be
    // restored when the window closes.
    private var restoreFrame = false
    private var origFrame: NSRect = .zero

    // MARK: - Init

    @objc convenience init() {
        self.init(externalConfiguration: nil)
    }

    /// Pass a configuration only for child windows created via WebKit's
    /// createWebViewWith callback, which must use the configuration it supplies.
    init(externalConfiguration: WKWebViewConfiguration?) {
        let window = NSWindow(
            contentRect: NSRect(x: 196, y: 240, width: 480, height: 270),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 50, height: 50)

        super.init(window: window)

        model.bridge = bridge
        configureBridgeActions()
        configureModelHooks()

        window.contentView = NSHostingView(
            rootView: SABundleHTMLOutputView(model: model, externalConfiguration: externalConfiguration)
        )
        window.setFrameAutosaveName("SPBundleHTMLOutputWindow")
        window.delegate = self

        titleSubscription = model.$pageTitle
            .receive(on: DispatchQueue.main)
            .sink { [weak self] title in
                self?.window?.title = title
            }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported; use init()")
    }

    // MARK: - Legacy ObjC API (display content)

    @objc(displayHTMLContent:withOptions:)
    func displayHTMLContent(_ content: String, withOptions displayOptions: [AnyHashable: Any]?) {
        window?.orderFront(nil)
        applyDisplayOptions(displayOptions)
        model.loadHTMLString(content)
    }

    @objc(displayURLString:withOptions:)
    func displayURLString(_ urlString: String, withOptions displayOptions: [AnyHashable: Any]?) {
        window?.makeKeyAndOrderFront(nil)
        applyDisplayOptions(displayOptions)
        if let url = URL(string: urlString) {
            model.load(URLRequest(url: url))
        }
    }

    /// Applies an optional temporary window frame. When a caller passes a "frame"
    /// dictionary, the window resizes to it and restores its previous frame on close.
    private func applyDisplayOptions(_ displayOptions: [AnyHashable: Any]?) {
        guard let window = window,
              let frameDict = displayOptions?["frame"] as? [AnyHashable: Any] else { return }

        origFrame = window.frame
        restoreFrame = true

        let newFrame = NSRect(
            x: (frameDict["x"] as? NSNumber)?.doubleValue ?? 0,
            y: (frameDict["y"] as? NSNumber)?.doubleValue ?? 0,
            width: (frameDict["w"] as? NSNumber)?.doubleValue ?? 0,
            height: (frameDict["h"] as? NSNumber)?.doubleValue ?? 0
        )
        window.setFrame(newFrame, display: true)
    }

    // MARK: - Window delegate

    func windowWillClose(_ notification: Notification) {
        if restoreFrame {
            window?.setFrame(origFrame, display: true)
            restoreFrame = false
        }

        windowWillCloseHandler?()

        model.loadHTMLString("<html></html>")
        model.webView?.configuration.userContentController
            .removeScriptMessageHandler(forName: SABundleJSBridge.messageHandlerName)

        windowUUID = ""
        docUUID = ""

        SPBundleManager.shared().removeHTMLOutputController(self)
    }

    // MARK: - Bridge wiring (window.system)

    private func configureBridgeActions() {
        bridge.actions.run = { [weak self] command, uuid in
            self?.runBashCommand(command, jsUUID: uuid) ?? ""
        }

        bridge.actions.shellEnvironment = { name in
            Self.appShellEnvironment()[name]
        }

        bridge.actions.insertText = { text in
            guard let textView = NSApp.keyWindow?.firstResponder as? NSTextView else {
                NSSound.beep()
                return
            }
            textView.textStorage?.append(NSAttributedString(string: text))
        }

        bridge.actions.setText = { text in
            guard let textView = NSApp.keyWindow?.firstResponder as? NSTextView else {
                NSSound.beep()
                return
            }
            textView.setSelectedRange(NSRange(location: 0, length: (textView.string as NSString).length))
            textView.insertText(text, replacementRange: textView.selectedRange())
        }

        bridge.actions.setSelectedTextRange = { rangeString in
            guard let textView = NSApp.keyWindow?.firstResponder as? NSTextView else {
                NSSound.beep()
                return
            }
            let range = NSIntersectionRange(
                NSRangeFromString(rangeString),
                NSRange(location: 0, length: (textView.string as NSString).length)
            )
            if range.location != NSNotFound {
                textView.setSelectedRange(range)
            }
        }

        bridge.actions.makeWindowKey = { [weak self] in
            self?.window?.makeKeyAndOrderFront(nil)
        }

        bridge.actions.closeWindow = { [weak self] in
            self?.window?.close()
        }

        bridge.actions.suppressExceptionAlert = { [weak self] in
            self?.suppressExceptionAlerting = true
        }

        bridge.actions.reportJSError = { [weak self] message, source, line in
            let text = "Exception:\nline = \(line)\nmessage = \(message)\nsource = \(source)"
            if self?.suppressExceptionAlerting == true {
                NSLog("%@", text)
                return
            }
            NSAlert.createWarningAlert(
                title: NSLocalizedString("JavaScript Exception", comment: "javascript exception"),
                message: text
            )
        }
    }

    private static func appShellEnvironment() -> [String: String] {
        let environment = (NSApp.delegate as? SPAppController)?.shellEnvironment(forDocument: nil)
        return (environment as? [String: String]) ?? [:]
    }

    /// Ports the legacy `window.system.run('cmd' | ['cmd', 'uuid'])` implementation.
    private func runBashCommand(_ command: String, jsUUID: String?) -> String {
        let uuid = jsUUID ?? (docUUID.isEmpty ? nil : docUUID)

        do {
            if let uuid = uuid {
                var environment: [String: Any] = Self.appShellEnvironment()
                environment[SPBundleShellVariableProcessID] = uuid
                environment[SPBundleShellVariableQueryFile] = (SPURLSchemeQueryInputPathHeader as NSString).expandingTildeInPath + uuid
                environment[SPBundleShellVariableQueryResultFile] = (SPURLSchemeQueryResultPathHeader as NSString).expandingTildeInPath + uuid
                environment[SPBundleShellVariableQueryResultStatusFile] = (SPURLSchemeQueryResultStatusPathHeader as NSString).expandingTildeInPath + uuid
                environment[SPBundleShellVariableQueryResultMetaFile] = (SPURLSchemeQueryResultMetaPathHeader as NSString).expandingTildeInPath + uuid

                let contextInfo: [String: Any] = [
                    "name": "JavaScript",
                    "scope": NSLocalizedString("General", comment: "general menu item label"),
                    SPBundleFileInternalexecutionUUID: uuid,
                ]

                return try SPBundleCommandRunner.runBashCommand(
                    command,
                    withEnvironment: environment,
                    atCurrentDirectoryPath: nil,
                    callerInstance: NSApp.delegate,
                    contextInfo: contextInfo
                )
            }

            return try SPBundleCommandRunner.runBashCommand(command, withEnvironment: nil, atCurrentDirectoryPath: nil)
        } catch {
            NSAlert.createWarningAlert(
                title: NSLocalizedString("Error while executing JavaScript BASH command", comment: "error while executing javascript bash command"),
                message: error.localizedDescription
            )
            return ""
        }
    }

    // MARK: - Web view hooks

    private func configureModelHooks() {
        model.onSequelaceURL = { url in
            (NSApp.delegate as? SPAppController)?.handleEvent(with: url)
        }

        // Legacy opened a sibling output window for requested new windows. We cancel
        // WebKit's window (return nil) and load the request in a fresh sibling
        // controller instead. The WebKit-supplied configuration is deliberately NOT
        // used: it shares the opener's user content controller, which would cross-wire
        // the child's window.system handler to the opener's window. Because no web view
        // is returned, the two windows have no script connection and don't need to
        // share a web process. Trade-off: JS window.open() gets no handle back.
        model.onCreateWebView = { _, request in
            guard let url = request.url else {
                return nil
            }
            let controller = SABundleHTMLOutputWindowController()
            controller.displayURLString(url.absoluteString, withOptions: nil)
            SPBundleManager.shared().addHTMLOutputController(controller)
            return nil
        }

        model.contextMenuItems = { [weak self] in
            guard let self = self else { return [] }

            let viewSource = NSMenuItem(
                title: NSLocalizedString("View Source", comment: "view html source code menu item title"),
                action: #selector(Self.showSourceCode),
                keyEquivalent: ""
            )
            viewSource.target = self

            let savePage = NSMenuItem(
                title: NSLocalizedString("Save Page As…", comment: "save page as menu item title"),
                action: #selector(Self.saveDocument(_:)),
                keyEquivalent: ""
            )
            savePage.target = self

            let printPage = NSMenuItem(
                title: NSLocalizedString("Print Page…", comment: "print page menu item title"),
                action: #selector(Self.printDocument(_:)),
                keyEquivalent: ""
            )
            printPage.target = self

            return [viewSource, savePage, printPage]
        }

        model.handleKeyDown = { [weak self] event in
            self?.handleKeyDown(event) ?? false
        }
    }

    /// Ports the legacy keyDown: zoom and history shortcuts.
    private func handleKeyDown(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command) else { return false }

        switch event.charactersIgnoringModifiers {
        case "+", "=": // increase text size; ⌘+, ⌘=, and ⌘ numpad +
            model.makeTextLarger()
            return true
        case "-": // decrease text size; ⌘- and numpad -
            model.makeTextSmaller()
            return true
        case "0": // return the text size to the default size
            model.makeTextStandardSize()
            return true
        default:
            break
        }

        switch event.keyCode {
        case 123: // ⌘← go back, falling back to the initially loaded HTML
            if model.canGoBack {
                model.goBack()
            } else {
                model.reloadInitialHTMLString()
            }
            return true
        case 124: // ⌘→ go forward
            model.goForward()
            return true
        default:
            return false
        }
    }

    // MARK: - Document actions (context menu)

    @objc func showSourceCode() {
        model.fetchOuterHTML { sourceCode in
            guard let sourceCode = sourceCode else { return }

            let controller = SABundleHTMLOutputWindowController()
            let escaped = (sourceCode as NSString).htmlEscape() ?? ""
            controller.displayHTMLContent("<pre>\(escaped)</pre>", withOptions: nil)
            SPBundleManager.shared().addHTMLOutputController(controller)
        }
    }

    @objc func saveDocument(_ sender: Any?) {
        guard let window = window else { return }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = "output"
        panel.allowedContentTypes = [.html]
        panel.isExtensionHidden = false
        panel.allowsOtherFileTypes = true
        panel.canSelectHiddenExtension = true
        panel.canCreateDirectories = true

        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }

            self?.model.fetchOuterHTML { sourceCode in
                guard let sourceCode = sourceCode else { return }
                do {
                    try sourceCode.write(to: url, atomically: true, encoding: .utf8)
                } catch {
                    NSAlert.createWarningAlert(
                        title: NSLocalizedString("Error", comment: "error"),
                        message: error.localizedDescription
                    )
                }
            }
        }
    }

    @objc func printDocument(_ sender: Any?) {
        guard let webView = model.webView, let window = window,
              let printInfo = NSPrintInfo.shared.copy() as? NSPrintInfo else {
            return
        }

        // Margin and pagination setup ported from SPPrintUtility — applied to a copy
        // so the shared print info isn't mutated for the rest of the app.

        let paperSize = printInfo.paperSize
        let printableRect = printInfo.imageablePageBounds

        let marginL = printableRect.origin.x
        let marginR = paperSize.width - (printableRect.origin.x + printableRect.size.width)
        let marginB = printableRect.origin.y
        let marginT = paperSize.height - (printableRect.origin.y + printableRect.size.height)

        // Make sure margins are symmetric and positive
        let marginLR = max(0, max(marginL, marginR))
        let marginTB = max(0, max(marginT, marginB))

        printInfo.leftMargin = marginLR
        printInfo.rightMargin = marginLR
        printInfo.topMargin = marginTB
        printInfo.bottomMargin = marginTB

        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .automatic
        printInfo.isVerticallyCentered = false

        // The legacy print accessory toggled WebPreferences.shouldPrintBackgrounds;
        // WKWebView only exposes this from macOS 13.3.
        if #available(macOS 13.3, *) {
            webView.configuration.preferences.shouldPrintBackgrounds = UserDefaults.standard.bool(forKey: SPPrintBackground)
        }

        let operation = webView.printOperation(with: printInfo)

        // WKWebView's print operation view starts with a zero frame; without
        // sizing it the preview and output are blank.
        operation.view?.frame = NSRect(origin: .zero, size: webView.frame.size)

        operation.printPanel.options.formUnion([.showsOrientation, .showsScaling, .showsPaperSize])

        operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
    }
}
