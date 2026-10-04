//
//  SANotificationCenter.swift
//  Sequel Ace
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//
//  More info at <https://github.com/Sequel-Ace/Sequel-Ace>
//

import Foundation
import UserNotifications

/// Posts user notifications ("Connected", "Query Finished", …) via the
/// UserNotifications framework, replacing the deprecated `NSUserNotification`
/// pattern used across the app.
///
/// Parity notes with the legacy behavior:
/// - No `UNUserNotificationCenterDelegate` is installed, so notifications are
///   not presented while Sequel Ace is frontmost — same as the legacy center
///   without a delegate.
/// - Unlike `NSUserNotification`, the system requires user authorization; it
///   is requested lazily on the first post, so the permission prompt appears
///   in context (typically right after the first successful connection). If
///   the user declines, posts become silent no-ops.
@objc final class SANotificationCenter: NSObject {

    @objc static let shared = SANotificationCenter()

    /// Posts a banner + default sound notification. Safe to call from any
    /// thread. `body` may be nil for title-only notifications.
    @objc(postNotificationWithTitle:body:)
    func postNotification(title: String, body: String?) {
        // UNUserNotificationCenter needs a real app bundle; guard so code
        // paths exercised from test runners don't trap.
        guard Bundle.main.bundleIdentifier != nil else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        if let body, !body.isEmpty {
            content.body = body
        }
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)

        // Deliver from the authorization completion: on the very first call
        // this prompts and completes only after the user decides, so the
        // triggering notification is delivered (not silently dropped) when
        // permission is granted. On every later call it completes immediately
        // with the stored status — the system never re-prompts.
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            center.add(request)
        }
    }
}
