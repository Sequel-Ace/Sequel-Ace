//
//  SAClaudeAppearanceChange.swift
//  Sequel Ace
//
//  The settings the Claude look reads (editor theme colours, accent, connection colour style, fonts and the few
//  feature settings Claude views show), and the check that tells a write to one of them apart from every other
//  defaults write: window frames, split positions and column widths are saved continuously, and every write posts
//  `UserDefaults.didChangeNotification`, which carries no key. The app runs the check from one defaults observer
//  and posts `SAClaudeAppearanceChange.didChangeNotification` ("SAClaudeAppearanceDidChange"); Claude views observe
//  that instead (`SAClaudeAppearanceMonitor`).
//  Shared with the Unit Tests target.
//

import Foundation

enum SAClaudeAppearanceChange {

    /// Posted on the main thread when a watched setting's value changed. `userInfo[changedKeysKey]` holds the
    /// changed keys as a `Set<String>`. Post it only through `post(changed:to:)`, which owns the main-thread
    /// guarantee: Claude views and stylers touch AppKit straight from their observers.
    static let didChangeNotification = Notification.Name("SAClaudeAppearanceDidChange")
    static let changedKeysKey = "changedKeys"

    /// Posts `didChangeNotification` for `changed` on `center`: right away on the main thread, else on the next
    /// main-queue turn (a defaults write may happen on any thread).
    static func post(changed: Set<String>, to center: NotificationCenter = .default) {
        let deliver = {
            center.post(name: didChangeNotification, object: nil, userInfo: [changedKeysKey: changed])
        }
        if Thread.isMainThread { deliver() } else { DispatchQueue.main.async(execute: deliver) }
    }

    /// Every colour the editor theme loader writes.
    static let themeKeys: [String] = [
        SAEditorThemeLoader.backgroundColourKey, SAEditorThemeLoader.textColourKey, SAEditorThemeLoader.caretColourKey,
        SAEditorThemeLoader.highlightColourKey, SAEditorThemeLoader.selectionColourKey, SAEditorThemeLoader.commentColourKey,
        SAEditorThemeLoader.quoteColourKey, SAEditorThemeLoader.keywordColourKey, SAEditorThemeLoader.backtickColourKey,
        SAEditorThemeLoader.numericColourKey, SAEditorThemeLoader.variableColourKey,
    ]

    /// The settings the observing views read. A view that reads another setting must add it here, or it stops
    /// following that setting live.
    static let watchedKeys: [String] = themeKeys + [
        SAClaudeAccent.defaultsKey,
        // "Show the connection colour as" and the switch it replaced (SAConnectionColourStyle).
        "ClaudeConnectionColourStyle", "DisplayConnectionColorInTitlebar",
        // The General (results / console) font and the query editor font. Keep in sync with SPConstants.m.
        "fontSettings", "CustomQueryEditorFont",
        // The Script Console's own look (SAScriptConsoleAppearance).
        SAScriptConsoleAppearance.useCustomKey, SAScriptConsoleAppearance.customFontKey,
        SAScriptConsoleAppearance.customTextColorKey, SAScriptConsoleAppearance.customBackgroundColorKey,
        // The query bar Copy button's default action.
        SAClaudeQueryCopyAction.defaultsKey,
        // The Query Console's "logging is disabled" note (SPConsoleEnableLogging), which its toolbar lays out.
        "ConsoleEnableLogging",
    ] + SAClaudeEditorOption.allCases.compactMap(\.defaultsKey)

    /// The stored values of `keys` (absent keys are left out).
    static func snapshot(of defaults: UserDefaults, keys: [String] = watchedKeys) -> [String: NSObject] {
        var values: [String: NSObject] = [:]
        for key in keys {
            if let value = defaults.object(forKey: key) { values[key] = value as AnyObject as? NSObject }
        }
        return values
    }

    /// The keys whose value differs between two snapshots, including keys set or removed.
    static func changedKeys(from old: [String: NSObject], to new: [String: NSObject]) -> Set<String> {
        var changed = Set<String>()
        for key in Set(old.keys).union(new.keys) where !(old[key]?.isEqual(new[key]) ?? (new[key] == nil)) {
            changed.insert(key)
        }
        return changed
    }

    /// Remembers the watched values of one defaults object and reports what changed since the last check.
    /// Any thread.
    final class Tracker {
        private let defaults: UserDefaults
        private let keys: [String]
        private let lock = NSLock()
        private var last: [String: NSObject]

        init(defaults: UserDefaults, keys: [String] = SAClaudeAppearanceChange.watchedKeys) {
            self.defaults = defaults
            self.keys = keys
            last = SAClaudeAppearanceChange.snapshot(of: defaults, keys: keys)
        }

        /// Re-reads the watched values; returns the keys that changed since the previous call (empty for none).
        /// The defaults are read outside the lock (a read never runs under it, whatever Foundation does inside one);
        /// two racing writers can then swap their snapshots out of order, which costs a spurious extra post at most,
        /// never a missed change.
        func update() -> Set<String> {
            record(SAClaudeAppearanceChange.snapshot(of: defaults, keys: keys))
        }

        /// Diffs `current` against the stored snapshot and stores it; returns the changed keys.
        func record(_ current: [String: NSObject]) -> Set<String> {
            lock.lock()
            defer { lock.unlock() }
            let changed = SAClaudeAppearanceChange.changedKeys(from: last, to: current)
            last = current
            return changed
        }

        /// `update()`, then, when something changed, `beforePosting` (on the calling thread) and
        /// `didChangeNotification` on `center`: right away on the main thread, else on the next main-queue turn.
        func check(postingTo center: NotificationCenter, beforePosting: ((Set<String>) -> Void)? = nil) {
            let changed = update()
            guard !changed.isEmpty else { return }
            beforePosting?(changed)
            SAClaudeAppearanceChange.post(changed: changed, to: center)
        }
    }
}
