//
//  SATooltipDismissal.swift
//  Sequel Ace
//
//  Created by Sequel-Ace contributors on 2026.09.09.
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import AppKit

/// Decides when a tooltip closes in response to user activity. Pure logic,
/// extracted from SPTooltip's former nested event loop so it is testable.
@objc public final class SATooltipDismissalPolicy: NSObject {
    /// Mouse movement within this period after opening never closes the
    /// tooltip (parity with the old loop's grace period).
    static let ignorePeriod: TimeInterval = 0.05
    /// The pointer must travel this far from its anchor before the tooltip
    /// closes.
    static let moveThreshold: CGFloat = 10

    /// Whether an event of this type closes the tooltip immediately.
    static func closesImmediately(_ type: NSEvent.EventType) -> Bool {
        switch type {
        case .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel:
            return true
        default:
            return false
        }
    }

    /// Evaluates a mouse-moved event: within the grace period nothing
    /// happens; the first movement afterwards only anchors the position;
    /// later movements close once they leave a 10 pt radius around the
    /// anchor. Returns the close decision and the (possibly newly set)
    /// anchor.
    static func evaluateMouseMove(openedAt: Date, now: Date, anchor: NSPoint?, location: NSPoint) -> (close: Bool, anchor: NSPoint?) {
        guard now.timeIntervalSince(openedAt) >= ignorePeriod else {
            return (false, anchor)
        }
        guard let anchor else {
            return (false, location)
        }
        let dx = anchor.x - location.x
        let dy = anchor.y - location.y
        return ((dx * dx + dy * dy).squareRoot() > moveThreshold, anchor)
    }
}

/// Watches for the user activity that dismisses a tooltip - the replacement
/// for SPTooltip's nested `nextEventMatchingMask:` loop, which pumped every
/// application event itself while a tooltip was visible and thereby delayed
/// normal event delivery (measured while profiling the content filter).
/// Local event monitors leave dispatch untouched: the closing event still
/// reaches its original target.
@objc public final class SATooltipDismissalMonitor: NSObject {
    private var eventMonitor: Any?
    private var observers: [NSObjectProtocol] = []
    private weak var watchedWindow: NSWindow?
    private var restoreAcceptsMouseMoved = false
    private var onClose: (() -> Void)?
    private let openedAt = Date()
    private var mouseAnchor: NSPoint?

    /// Starts watching immediately. `keyWindow` (if any) is switched to
    /// accept mouse-moved events for the tooltip's lifetime and closes the
    /// tooltip when it resigns key - both mirroring the old loop.
    @objc public init(keyWindow: NSWindow?, onClose: @escaping () -> Void) {
        self.onClose = onClose
        self.watchedWindow = keyWindow
        super.init()

        if let keyWindow {
            restoreAcceptsMouseMoved = keyWindow.acceptsMouseMovedEvents
            keyWindow.acceptsMouseMovedEvents = true
            observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: keyWindow, queue: .main) { [weak self] _ in
                self?.close()
            })
        } else {
            // No key window at show time: the old loop's "key window changed"
            // check also closed on the nil -> some-window transition, so a
            // window becoming key dismisses the tooltip as well.
            observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] _ in
                self?.close()
            })
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.close()
        })
        let mask: NSEvent.EventTypeMask = [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel, .mouseMoved]
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    /// Routes one monitored event through the dismissal policy.
    private func handle(_ event: NSEvent) {
        if SATooltipDismissalPolicy.closesImmediately(event.type) {
            close()
            return
        }
        if event.type == .mouseMoved {
            let verdict = SATooltipDismissalPolicy.evaluateMouseMove(openedAt: openedAt, now: Date(), anchor: mouseAnchor, location: NSEvent.mouseLocation)
            mouseAnchor = verdict.anchor
            if verdict.close {
                close()
            }
        }
    }

    /// Tears down and fires the close handler exactly once.
    private func close() {
        guard let handler = onClose else { return }
        stop()
        handler()
    }

    /// Detaches all monitoring without firing the close handler - used when a
    /// new tooltip replaces the current one in the shared window.
    @objc public func stop() {
        onClose = nil
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
        eventMonitor = nil
        observers.forEach(NotificationCenter.default.removeObserver(_:))
        observers.removeAll()
        if let watchedWindow {
            watchedWindow.acceptsMouseMovedEvents = restoreAcceptsMouseMoved
        }
        watchedWindow = nil
    }

    deinit {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
        observers.forEach(NotificationCenter.default.removeObserver(_:))
    }
}
