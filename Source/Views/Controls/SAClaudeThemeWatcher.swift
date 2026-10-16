//
//  SAClaudeThemeWatcher.swift
//  Sequel Ace
//
//  The coalesced editor-theme check the bespoke Claude stylers share (Export, Import): one UserDefaults observer for
//  the whole app, one theme check per main-queue turn however many defaults writes ask for it (window frames are
//  saved continuously), and the registered handlers called only when the theme colours changed. As
//  `SAClaudeWindowSkin`'s own check. App target only.
//

import AppKit

enum SAClaudeThemeWatcher {

    /// One registration: the owner, held weakly, and its handler.
    private final class Entry {
        weak var owner: AnyObject?
        let fire: () -> Void

        init(owner: AnyObject, fire: @escaping () -> Void) {
            self.owner = owner
            self.fire = fire
        }
    }

    // Main thread only.
    private static var entries: [Entry] = []
    private static var defaultsObserver: NSObjectProtocol?
    private static var checkPending = false
    private static var lastTheme: SAClaudeThemeColours?

    /// Calls `handler` with `owner` on the main thread whenever the editor theme's colours change, for as long as
    /// `owner` lives (it is held weakly; nothing to remove). Call on the main thread.
    static func observe<Owner: AnyObject>(_ owner: Owner, _ handler: @escaping (Owner) -> Void) {
        // A short-lived owner (a field editor per edit) would otherwise stay registered until the next theme change.
        entries.removeAll { $0.owner == nil }
        entries.append(Entry(owner: owner) { [weak owner] in
            if let owner { handler(owner) }
        })
        guard defaultsObserver == nil else { return }
        // No `queue: .main`: a defaults write on a background thread must not wait for the main queue.
        defaultsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: nil) { _ in
            DispatchQueue.main.async { scheduleCheck() }
        }
    }

    /// One theme check on the next main-queue turn; the handlers run only when the theme changed since the last one.
    private static func scheduleCheck() {
        guard !checkPending else { return }
        checkPending = true
        DispatchQueue.main.async {
            checkPending = false
            var theme: SAClaudeThemeColours?
            NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
                theme = SAClaudeThemeColours.from(defaults: .standard)
            }
            guard theme != lastTheme else { return }
            lastTheme = theme
            entries.removeAll { $0.owner == nil }
            // A handler may register another owner: run over a copy.
            for entry in entries { entry.fire() }
        }
    }
}
