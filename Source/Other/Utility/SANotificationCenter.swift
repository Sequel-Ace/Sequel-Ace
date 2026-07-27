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

    private var didRequestAuthorization = false

    /// Posts a banner + default sound notification. Safe to call from any
    /// thread. `body` may be nil for title-only notifications.
    @objc(postNotificationWithTitle:body:)
    func postNotification(title: String, body: String?) {
        // UNUserNotificationCenter needs a real app bundle; guard so code
        // paths exercised from test runners don't trap.
        guard Bundle.main.bundleIdentifier != nil else { return }

        DispatchQueue.main.async {
            let center = UNUserNotificationCenter.current()

            if !self.didRequestAuthorization {
                self.didRequestAuthorization = true
                center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
            }

            let content = UNMutableNotificationContent()
            content.title = title
            if let body, !body.isEmpty {
                content.body = body
            }
            content.sound = .default

            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }
}
