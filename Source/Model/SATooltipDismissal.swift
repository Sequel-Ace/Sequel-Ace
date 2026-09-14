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

/// Owns the lifecycle of the shared tooltip window's content: the dismissal
/// monitor of the visible tooltip, how a new tooltip takes over the window,
/// whether a fade-out may continue, and which web-view callbacks still apply.
/// `SPTooltip` performs the window operations; the decisions live here.
@objc public final class SATooltipLifecycle: NSObject {
    private var dismissalMonitor: SATooltipDismissalMonitor?
    private var tooltipCount = 0

    /// Whether a dismissal monitor is currently attached.
    @objc public var isMonitoring: Bool {
        dismissalMonitor != nil
    }

    /// Prepares the shared window for a new tooltip and returns whether the
    /// caller must hide the window (and stop a running fade-out) before the
    /// new content loads.
    ///
    /// The previous tooltip may be visible and watched, fading out, or its web
    /// view may still be loading. Whatever is on screen has to go at once:
    /// the new content is measured in a window temporarily sized to most of
    /// the screen, which would flash up at that size if the window stayed
    /// visible (reproducible by holding a key equivalent that shows a
    /// tooltip), a visible tooltip would otherwise show a blank page until
    /// the new content loads, and a later fade tick would see a second
    /// tooltip, hide the window and drop the fresh content. None of these
    /// states ever reach `tooltipDidClose()`, so the count is reset to the new
    /// tooltip instead of balancing the individual cases, and the previous
    /// dismissal monitor is detached.
    ///
    /// - Parameters:
    ///   - isVisible: Whether the shared window is currently on screen.
    ///   - isFading: Whether the previous tooltip's fade-out is running.
    /// - Returns: `true` when the caller must hide the window and stop the fade.
    @objc(prepareForNewTooltipWhileVisible:fading:)
    public func prepareForNewTooltip(isVisible: Bool, isFading: Bool) -> Bool {
        detachDismissalMonitor()
        tooltipCount = 1
        return isVisible || isFading
    }

    /// Starts watching for the user activity that dismisses the visible
    /// tooltip, replacing any previous monitor.
    ///
    /// - Parameters:
    ///   - keyWindow: The key window at show time, if any.
    ///   - onClose: Called once when the tooltip should close; the monitor is
    ///     already detached at that point.
    @objc(beginDismissalMonitoringWithKeyWindow:onClose:)
    public func beginDismissalMonitoring(keyWindow: NSWindow?, onClose: @escaping () -> Void) {
        detachDismissalMonitor()
        dismissalMonitor = SATooltipDismissalMonitor(keyWindow: keyWindow) { [weak self] in
            self?.detachDismissalMonitor()
            onClose()
        }
    }

    /// Stops the dismissal monitor (idempotent) and lets go of it - the single
    /// teardown spot shared by replacement, close and the monitor's own close
    /// callback.
    @objc public func detachDismissalMonitor() {
        dismissalMonitor?.stop()
        dismissalMonitor = nil
    }

    /// Whether a fade-out tick may keep fading: the tooltip is still partly
    /// visible and no newer tooltip has taken over the window.
    ///
    /// - Parameter alpha: The alpha value the tick would apply.
    /// - Returns: `false` when the caller must hide and close the window.
    @objc(fadeMayContinueWithAlpha:)
    public func fadeMayContinue(alpha: CGFloat) -> Bool {
        alpha > 0 && tooltipCount == 1
    }

    /// Records that a tooltip finished closing.
    @objc public func tooltipDidClose() {
        tooltipCount = max(0, tooltipCount - 1)
    }

    /// Whether work started for a web view still concerns the current content.
    /// A newer tooltip can replace the web view before a navigation callback
    /// arrives, or while the size measurement waits for its JavaScript results
    /// in a nested run loop (holding a key equivalent that shows a tooltip does
    /// this). Such stale work must not touch the shared window: applying the
    /// old measurement and ordering the window front would show the new,
    /// still loading content, whose own measurement then runs in a visible,
    /// screen-sized window.
    ///
    /// - Parameters:
    ///   - webView: The web view the callback or measurement belongs to.
    ///   - currentWebView: The web view currently showing the tooltip.
    /// - Returns: `true` when the work belongs to the current content.
    @objc(isCurrentWebView:currentWebView:)
    public static func isCurrent(webView: AnyObject?, currentWebView: AnyObject?) -> Bool {
        webView === currentWebView
    }

    /// Whether a failed load should close the tooltip. A navigation superseded
    /// by one the page itself started (possible in HTML tooltips with
    /// JavaScript enabled) reports `NSURLErrorCancelled` while the replacement
    /// is still loading, so there is nothing to close; any other failure leaves
    /// an empty status-level window without a dismissal monitor and must close
    /// it.
    ///
    /// - Parameter error: The navigation error.
    /// - Returns: `true` when the caller must order the tooltip out.
    @objc(shouldCloseAfterNavigationFailure:)
    public static func shouldCloseAfterNavigationFailure(_ error: Error) -> Bool {
        let nsError = error as NSError
        return !(nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled)
    }
}
