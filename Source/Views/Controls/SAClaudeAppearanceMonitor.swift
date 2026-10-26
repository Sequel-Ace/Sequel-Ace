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
    ///
    /// The main-thread contract holds even for a notification posted off the main thread (everything the app posts
    /// goes through `post(changed:to:)`, which already hops; a direct `NotificationCenter.post` from a worker
    /// would not): such a delivery is handed to the next main-queue turn, so `block` may touch AppKit. On the main
    /// thread `block` runs synchronously inside the post, as before.
    static func addObserver(_ block: @escaping (Set<String>) -> Void) -> NSObjectProtocol {
        _ = monitor
        return addObserver(on: .default, block)
    }

    /// `addObserver(_:)` on another centre, which is what the Unit Tests observe. Does not start the monitor.
    static func addObserver(on center: NotificationCenter, _ block: @escaping (Set<String>) -> Void) -> NSObjectProtocol {
        // No `queue: .main`: that would make a poster on another thread wait for the main queue.
        center.addObserver(forName: didChangeNotification, object: nil, queue: nil) { note in
            let keys = note.userInfo?[changedKeysKey] as? Set<String> ?? []
            if Thread.isMainThread { block(keys) } else { DispatchQueue.main.async { block(keys) } }
        }
    }

    /// The notifications as a Combine publisher. Delivered on the thread of the poster, which is the main thread
    /// for everything the app posts (`post(changed:to:)`); a subscriber that must not depend on that routes
    /// through `.receive(on:)` or a `debounce` on `DispatchQueue.main`, as the Script Console does.
    static func publisher() -> NotificationCenter.Publisher {
        _ = monitor
        return NotificationCenter.default.publisher(for: didChangeNotification)
    }
}
