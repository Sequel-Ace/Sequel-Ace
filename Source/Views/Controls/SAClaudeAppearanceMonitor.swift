//
//  SAClaudeAppearanceMonitor.swift
//  Sequel Ace
//
//  The app's one `UserDefaults.didChangeNotification` observer for the Claude look: it compares the watched
//  settings (`SAClaudeAppearanceChange.watchedKeys`) with their last values and posts
//  `SAClaudeAppearanceChange.didChangeNotification` only when one changed. Claude views observe that, so a window
//  frame or split position save no longer runs a handler in every view of every open tab. Shared with the Unit
//  Tests target (SPRuleFilterDropBox observes it).
//

import Foundation

extension SAClaudeAppearanceChange {

    /// Started by the first observer.
    private static let monitor: NSObjectProtocol = {
        let tracker = Tracker(defaults: .standard)
        // No `queue: .main`: a defaults write on a background thread must not wait for the main queue.
        return NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: nil) { _ in
            tracker.check(postingTo: .default) { changed in
                // Before any view redraws: the accent's cache may not have seen this write yet.
                if changed.contains(SAClaudeAccent.defaultsKey) { SAClaudeAccent.invalidateCache() }
            }
        }
    }()

    /// Calls `block` on the main thread with the changed keys whenever a watched setting changes. Remove the
    /// returned observer from `NotificationCenter.default` when done.
    static func addObserver(_ block: @escaping (Set<String>) -> Void) -> NSObjectProtocol {
        _ = monitor
        return NotificationCenter.default.addObserver(forName: didChangeNotification, object: nil, queue: nil) { note in
            block(note.userInfo?[changedKeysKey] as? Set<String> ?? [])
        }
    }

    /// The notifications as a Combine publisher (main thread).
    static func publisher() -> NotificationCenter.Publisher {
        _ = monitor
        return NotificationCenter.default.publisher(for: didChangeNotification)
    }
}
