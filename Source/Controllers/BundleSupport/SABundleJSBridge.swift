//
//  SABundleJSBridge.swift
//  Sequel Ace
//
//  Created as part of the WebView to WKWebView migration.
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import Foundation
import WebKit

/// Recreates the legacy WebView `window.system` JavaScript API for bundle HTML output
/// on top of WKWebView.
///
/// Value-returning calls (`run`, `getShellEnvironmentForName`) keep their synchronous
/// semantics by tunnelling through `window.prompt()`: the injected user script encodes
/// the call as JSON in the prompt's default text, and the WKUIDelegate answers it via
/// `handlePrompt(_:defaultText:)`. Fire-and-forget calls post to the `system` script
/// message handler instead. The owning controller supplies behavior through `Actions`.
final class SABundleJSBridge {

    /// Marker passed as the `prompt()` message so genuine `window.prompt()` calls
    /// can be told apart from bridge traffic.
    static let promptSentinel = "__sequel_ace_system__"

    /// Name under which the fire-and-forget handler is registered
    /// (`window.webkit.messageHandlers.system`).
    static let messageHandlerName = "system"

    struct Actions {
        /// Mirrors legacy `window.system.run('cmd' | ['cmd', 'uuid'])`; returns the command output.
        var run: (_ command: String, _ uuid: String?) -> String = { _, _ in "" }
        var shellEnvironment: (_ name: String) -> String? = { _ in nil }
        var insertText: (String) -> Void = { _ in }
        var setText: (String) -> Void = { _ in }
        var setSelectedTextRange: (String) -> Void = { _ in }
        var makeWindowKey: () -> Void = {}
        var closeWindow: () -> Void = {}
        var suppressExceptionAlert: () -> Void = {}
        /// Replaces the legacy script-debug-delegate exception alerts, fed by `window.onerror`.
        var reportJSError: (_ message: String, _ source: String, _ line: Int) -> Void = { _, _, _ in }
    }

    var actions = Actions()

    // MARK: - Injected script

    static var userScriptSource: String {
        """
        (function() {
            'use strict';
            if (window.system) { return; }
            // Capture the native implementations at document start, before page scripts
            // run — an override of window.prompt by page JS must not hijack the bridge.
            var nativePrompt = window.prompt.bind(window);
            var nativeMessageHandler = window.webkit.messageHandlers.\(messageHandlerName);
            function normalized(value) {
                return (value === undefined || value === null) ? null : String(value);
            }
            function syncCall(fn, args) {
                var result = nativePrompt('\(promptSentinel)', JSON.stringify({ fn: fn, args: args }));
                return result === null ? '' : result;
            }
            function asyncCall(fn, args) {
                nativeMessageHandler.postMessage({ fn: fn, args: args });
            }
            window.system = {
                run: function(call) {
                    var args = Array.isArray(call) ? Array.prototype.map.call(call, normalized) : [normalized(call)];
                    return syncCall('run', args);
                },
                getShellEnvironmentForName: function(name) {
                    return syncCall('getShellEnvironmentForName', [normalized(name)]);
                },
                insertText: function(text) { asyncCall('insertText', [normalized(text)]); },
                setText: function(text) { asyncCall('setText', [normalized(text)]); },
                setSelectedTextRange: function(range) { asyncCall('setSelectedTextRange', [normalized(range)]); },
                makeHTMLOutputWindowKeyWindow: function() { asyncCall('makeHTMLOutputWindowKeyWindow', []); },
                closeHTMLOutputWindow: function() { asyncCall('closeHTMLOutputWindow', []); },
                suppressExceptionAlert: function() { asyncCall('suppressExceptionAlert', []); }
            };
            window.onerror = function(message, source, line) {
                asyncCall('reportError', [normalized(message) || '', normalized(source) || '', line || 0]);
                return false;
            };
        })();
        """
    }

    static func makeUserScript() -> WKUserScript {
        // Legacy WebView exposed window.system to every frame, not just the main one.
        WKUserScript(source: userScriptSource, injectionTime: .atDocumentStart, forMainFrameOnly: false)
    }

    // MARK: - Synchronous channel (prompt tunnel)

    /// Answers a WKUIDelegate text-input panel request when it carries bridge traffic.
    /// Returns nil for genuine `window.prompt()` calls so the caller can show real UI.
    func handlePrompt(_ prompt: String, defaultText: String?) -> String? {
        guard prompt == Self.promptSentinel else { return nil }
        guard let call = Self.decodeCall(defaultText) else { return "" }

        switch call.fn {
        case "run":
            guard let command = call.string(at: 0) else { return "" }
            return actions.run(command, call.string(at: 1))
        case "getShellEnvironmentForName":
            guard let name = call.string(at: 0) else { return "" }
            return actions.shellEnvironment(name) ?? ""
        default:
            return ""
        }
    }

    // MARK: - Fire-and-forget channel (script messages)

    func handleMessage(_ body: Any) {
        guard let dictionary = body as? [String: Any],
              let fn = dictionary["fn"] as? String else { return }
        let call = Call(fn: fn, args: dictionary["args"] as? [Any] ?? [])

        switch call.fn {
        case "insertText":
            actions.insertText(call.string(at: 0) ?? "")
        case "setText":
            actions.setText(call.string(at: 0) ?? "")
        case "setSelectedTextRange":
            actions.setSelectedTextRange(call.string(at: 0) ?? "")
        case "makeHTMLOutputWindowKeyWindow":
            actions.makeWindowKey()
        case "closeHTMLOutputWindow":
            actions.closeWindow()
        case "suppressExceptionAlert":
            actions.suppressExceptionAlert()
        case "reportError":
            actions.reportJSError(call.string(at: 0) ?? "", call.string(at: 1) ?? "", call.int(at: 2))
        default:
            break
        }
    }

    // MARK: - Payload decoding

    private struct Call {
        let fn: String
        let args: [Any]

        func string(at index: Int) -> String? {
            guard args.indices.contains(index) else { return nil }
            return args[index] as? String
        }

        func int(at index: Int) -> Int {
            guard args.indices.contains(index) else { return 0 }
            return (args[index] as? NSNumber)?.intValue ?? 0
        }
    }

    private static func decodeCall(_ json: String?) -> Call? {
        guard let data = json?.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let fn = object["fn"] as? String else { return nil }
        return Call(fn: fn, args: object["args"] as? [Any] ?? [])
    }
}

/// WKUserContentController retains its message handlers; this proxy keeps the bridge
/// (and through it the owning window controller) out of that retain cycle.
final class SAWeakScriptMessageHandler: NSObject, WKScriptMessageHandler {

    private weak var bridge: SABundleJSBridge?

    init(_ bridge: SABundleJSBridge) {
        self.bridge = bridge
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        bridge?.handleMessage(message.body)
    }
}
