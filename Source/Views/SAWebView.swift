//
//  SAWebView.swift
//  Sequel Ace
//
//  Created as part of the XIB to SwiftUI migration.
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import SwiftUI
import WebKit

/// Owns the imperative side of `SAWebView`: loading, zoom, history, and the wiring
/// points the hosting controller configures (JS bridge, navigation hooks, menu items).
final class SAWebViewModel: NSObject, ObservableObject {

    @Published private(set) var pageTitle: String = ""

    /// HTML most recently loaded via `loadHTMLString(_:)`; reload re-displays it,
    /// matching the legacy controller's `initialHTMLSourceString` behavior.
    private(set) var initialHTMLString: String = ""

    private(set) weak var webView: WKWebView?
    private var titleObservation: NSKeyValueObservation?
    private var pendingLoad: Load?

    private enum Load {
        case html(String)
        case request(URLRequest)
    }

    // MARK: - Wiring points for the owning controller

    /// Supplies the `window.system` implementation; must be set before the view is created.
    var bridge: SABundleJSBridge?

    /// Invoked when a `sequelace://` link is clicked.
    var onSequelaceURL: ((URL) -> Void)?

    /// Invoked when web content asks for a new window. Implementations must return a
    /// web view created with the supplied configuration (WebKit requirement), or nil
    /// to suppress the window.
    var onCreateWebView: ((WKWebViewConfiguration, URLRequest) -> WKWebView?)?

    /// Extra context-menu items appended after WebKit's default ones.
    var contextMenuItems: (() -> [NSMenuItem])?

    /// First chance at key events; return true when handled.
    var handleKeyDown: ((NSEvent) -> Bool)?

    // MARK: - Loading

    func loadHTMLString(_ html: String) {
        initialHTMLString = html
        perform(.html(html))
    }

    func load(_ request: URLRequest) {
        perform(.request(request))
    }

    func reloadInitialHTMLString() {
        perform(.html(initialHTMLString))
    }

    private func perform(_ load: Load) {
        guard let webView = webView else {
            pendingLoad = load
            return
        }
        switch load {
        case .html(let html):
            webView.loadHTMLString(html, baseURL: nil)
        case .request(let request):
            webView.load(request)
        }
    }

    // MARK: - Zoom (replaces WebView's makeTextLarger/Smaller/StandardSize)

    private static let zoomStep: CGFloat = 1.2
    static let zoomRange: ClosedRange<CGFloat> = 0.25...5.0

    func makeTextLarger() { applyZoom((webView?.pageZoom ?? 1) * Self.zoomStep) }
    func makeTextSmaller() { applyZoom((webView?.pageZoom ?? 1) / Self.zoomStep) }
    func makeTextStandardSize() { applyZoom(1) }

    private func applyZoom(_ zoom: CGFloat) {
        webView?.pageZoom = min(max(zoom, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
    }

    // MARK: - History

    var canGoBack: Bool { webView?.canGoBack ?? false }

    func goBack() { webView?.goBack() }
    func goForward() { webView?.goForward() }

    // MARK: - Document access

    /// Fetches the current document's outer HTML (View Source / Save Page As).
    func fetchOuterHTML(completion: @escaping (String?) -> Void) {
        guard let webView = webView else {
            completion(nil)
            return
        }
        webView.evaluateJavaScript("document.getElementsByTagName('html')[0].outerHTML") { result, _ in
            completion(result as? String)
        }
    }

    // MARK: - Attachment

    fileprivate func attach(_ webView: WKWebView) {
        self.webView = webView
        titleObservation = webView.observe(\.title, options: [.initial, .new]) { [weak self] webView, _ in
            self?.pageTitle = webView.title ?? ""
        }
        if let pending = pendingLoad {
            pendingLoad = nil
            perform(pending)
        }
    }
}

/// SwiftUI wrapper around WKWebView, used by the bundle HTML output window and
/// intended for reuse by future help-viewer/tooltip migrations.
struct SAWebView: NSViewRepresentable {

    @ObservedObject var model: SAWebViewModel

    /// External configuration for child windows created via
    /// `webView(_:createWebViewWith:for:windowFeatures:)`, which must use the
    /// configuration WebKit supplies.
    var externalConfiguration: WKWebViewConfiguration?

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeNSView(context: Context) -> SAWKWebView {
        let configuration = externalConfiguration ?? SAWebView.makeConfiguration(bridge: model.bridge)
        let webView = SAWKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true

        let model = self.model
        webView.contextMenuItems = { model.contextMenuItems?() ?? [] }
        webView.keyDownHandler = { event in model.handleKeyDown?(event) ?? false }

        model.attach(webView)
        return webView
    }

    func updateNSView(_ nsView: SAWKWebView, context: Context) {
        // The imperative API on SAWebViewModel drives the view; nothing to sync here.
    }

    /// Builds a configuration matching the legacy BundleHTMLOutput.xib web preferences
    /// and installs the `window.system` bridge.
    static func makeConfiguration(bridge: SABundleJSBridge?) -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.preferences.minimumFontSize = 5
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        if let bridge = bridge {
            install(bridge, into: configuration.userContentController)
        }
        return configuration
    }

    /// Installs the bridge's user script and message handler; exposed separately so the
    /// child-window flow can add the bridge to a WebKit-supplied configuration.
    static func install(_ bridge: SABundleJSBridge, into userContentController: WKUserContentController) {
        userContentController.addUserScript(SABundleJSBridge.makeUserScript())
        userContentController.add(SAWeakScriptMessageHandler(bridge), name: SABundleJSBridge.messageHandlerName)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {

        private let model: SAWebViewModel

        init(model: SAWebViewModel) {
            self.model = model
        }

        // MARK: Navigation policy (ports the legacy policy delegate)

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            let isLinkClick = navigationAction.navigationType == .linkActivated

            // sequelace:// handler
            if isLinkClick && url.scheme == "sequelace" {
                model.onSequelaceURL?(url)
                decisionHandler(.cancel)
                return
            }

            // sp-reveal-file://a_file_path reveals the file in Finder
            if isLinkClick && url.scheme == "sp-reveal-file" {
                if let path = Self.filePath(from: navigationAction.request.mainDocumentURL ?? url, scheme: "sp-reveal-file") {
                    NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
                }
                decisionHandler(.cancel)
                return
            }

            // sp-open-file://a_file_path opens the file with the default application
            if isLinkClick && url.scheme == "sp-open-file" {
                if let path = Self.filePath(from: navigationAction.request.mainDocumentURL ?? url, scheme: "sp-open-file") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: path))
                }
                decisionHandler(.cancel)
                return
            }

            if navigationAction.navigationType == .reload && !model.initialHTMLString.isEmpty {
                decisionHandler(.cancel)
                model.reloadInitialHTMLString()
                return
            }

            decisionHandler(.allow)
        }

        /// Extracts "/a_file_path" from "scheme://a_file_path", mirroring the legacy
        /// substring behavior ("scheme:/" is stripped, keeping the second slash).
        private static func filePath(from url: URL, scheme: String) -> String? {
            let path = String(url.absoluteString.dropFirst("\(scheme):/".count))
            guard !path.isEmpty else { return nil }
            return path.removingPercentEncoding ?? path
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            NSLog("didFailProvisionalNavigation %@", error.localizedDescription)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            NSLog("didFailNavigation %@", error.localizedDescription)
        }

        // MARK: New windows

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            model.onCreateWebView?(configuration, navigationAction.request)
        }

        // MARK: JavaScript panels

        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            let alert = NSAlert()
            alert.messageText = "JavaScript"
            alert.informativeText = message
            alert.addButton(withTitle: NSLocalizedString("OK", comment: "OK button"))
            alert.runModal()
            completionHandler()
        }

        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
            let alert = NSAlert()
            alert.messageText = "JavaScript"
            alert.informativeText = message

            // Order of buttons matters! The first button has the firstButtonReturn return value.
            alert.addButton(withTitle: NSLocalizedString("OK", comment: "OK button"))
            alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "cancel button"))

            completionHandler(alert.runModal() == .alertFirstButtonReturn)
        }

        func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
            // window.system sync calls tunnel through prompt(); answer those without UI.
            if let bridge = model.bridge, let reply = bridge.handlePrompt(prompt, defaultText: defaultText) {
                completionHandler(reply)
                return
            }

            let alert = NSAlert()
            alert.messageText = "JavaScript"
            alert.informativeText = prompt

            let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 290, height: 24))
            input.stringValue = defaultText ?? ""
            alert.accessoryView = input

            alert.addButton(withTitle: NSLocalizedString("OK", comment: "OK button"))
            alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "cancel button"))

            completionHandler(alert.runModal() == .alertFirstButtonReturn ? input.stringValue : nil)
        }
    }
}

/// WKWebView subclass adding macOS behaviors WKWebView has no delegate hooks for:
/// appended context-menu items, pinch-to-zoom mapped to page zoom, and a key-event hook.
final class SAWKWebView: WKWebView {

    var contextMenuItems: (() -> [NSMenuItem])?
    var keyDownHandler: ((NSEvent) -> Bool)?

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        guard let items = contextMenuItems?(), !items.isEmpty else { return }

        menu.addItem(.separator())
        for item in items {
            menu.addItem(item)
        }
    }

    override func keyDown(with event: NSEvent) {
        if keyDownHandler?(event) == true {
            return
        }
        super.keyDown(with: event)
    }

    override func magnify(with event: NSEvent) {
        // Legacy WebView zoomed the text on pinch; mirror that with page zoom rather
        // than view magnification.
        let zoom = pageZoom * (1 + event.magnification)
        pageZoom = min(max(zoom, SAWebViewModel.zoomRange.lowerBound), SAWebViewModel.zoomRange.upperBound)
    }
}
