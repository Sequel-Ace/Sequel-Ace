//
//  SAClaudeAlertPresentationHook.swift
//  Sequel Ace
//
//  Styles every NSAlert in the Claude look as it is presented, wherever the
//  app builds it (the NSAlert helpers and the direct uses in Swift and
//  Objective-C alike): `runModal` and `beginSheetModal(for:completionHandler:)`
//  are exchanged once for versions that call `SAClaudeSheetStyler.styleAlert`
//  first and then the original. The styling has to happen before the alert
//  lays itself out (see `SAClaudeClassSwap`), which an observer of the shown
//  window is too late for. App target only.
//

import AppKit

enum SAClaudeAlertPresentationHook {

    private static var installed = false

    /// Exchanges the presentation methods (once). Returns whether the hook is in place; false, and nothing
    /// changed, when either method is missing.
    @discardableResult
    static func install() -> Bool {
        if installed { return true }
        let pairs: [(Selector, Selector)] = [
            (#selector(NSAlert.runModal), #selector(NSAlert.saClaude_runModal)),
            (#selector(NSAlert.beginSheetModal(for:completionHandler:)), #selector(NSAlert.saClaude_beginSheetModal(for:completionHandler:))),
        ]
        var methods: [(Method, Method)] = []
        for (originalSelector, replacementSelector) in pairs {
            guard let original = class_getInstanceMethod(NSAlert.self, originalSelector),
                  let replacement = class_getInstanceMethod(NSAlert.self, replacementSelector) else { return false }
            methods.append((original, replacement))
        }
        for (original, replacement) in methods {
            method_exchangeImplementations(original, replacement)
        }
        installed = true
        return true
    }
}

extension NSAlert {

    /// After the exchange this runs as `runModal`; the inner call reaches the original.
    @objc(saClaude_runModal) dynamic func saClaude_runModal() -> NSApplication.ModalResponse {
        SAClaudeSheetStyler.styleAlert(self, presentedOn: nil)
        return saClaude_runModal()
    }

    /// After the exchange this runs as `beginSheetModal(for:completionHandler:)`; the inner call reaches the original.
    @objc(saClaude_beginSheetModalForWindow:completionHandler:)
    dynamic func saClaude_beginSheetModal(for window: NSWindow, completionHandler handler: ((NSApplication.ModalResponse) -> Void)?) {
        SAClaudeSheetStyler.styleAlert(self, presentedOn: window)
        saClaude_beginSheetModal(for: window, completionHandler: handler)
        // The original re-runs `-[NSAlert layout]`, which takes the alert's controls back out of the card: put it back
        // before the sheet becomes key.
        SAClaudeAlertCard.card(for: self)?.verify()
    }
}
