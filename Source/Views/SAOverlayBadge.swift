//
//  SAOverlayBadge.swift
//  Sequel Ace
//
//  Created by Sequel Ace on September 17, 2026.
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import AppKit

/// A translucent badge pinned over the bottom edge of a scroll view.
///
/// The tables list shows its type-ahead search string in one; the query
/// editor shows the vim mode and the sequence being typed in one. It floats
/// above the scroll view rather than inside it, so it stays put while the
/// content scrolls, and it passes clicks through to whatever is underneath.
@objc(SAOverlayBadge) final class SAOverlayBadge: NSObject {

    private let symbolName: String
    private var overlay: NSVisualEffectView?
    private var label: NSTextField?
    private var icon: NSImageView?
    private var hideTimer: Timer?
    /// Guards the fade-out completion handler against a badge that was shown
    /// again while the animation was still running.
    private var visibilityGeneration = 0

    @objc init(symbolName: String) {
        self.symbolName = symbolName
        super.init()
    }

    deinit {
        hideTimer?.invalidate()
    }

    var isVisible: Bool {
        guard let overlay else { return false }
        return !overlay.isHidden
    }

    /// The badge's frame in screen coordinates, for anchoring an input
    /// method's candidate window to it.
    var screenFrame: NSRect? {
        guard let overlay, !overlay.isHidden, let host = overlay.superview else { return nil }
        let rectInWindow = host.convert(overlay.frame, to: nil)
        return host.window?.convertToScreen(rectInWindow) ?? rectInWindow
    }

    /// Shows `text` over `scrollView`, optionally fading out after a pause.
    /// Passing no interval leaves the badge up until it is hidden explicitly.
    func show(_ text: String,
              tint: NSColor = .labelColor,
              symbolName: String? = nil,
              over scrollView: NSScrollView?,
              hideAfter interval: TimeInterval? = nil) {
        guard let overlay = ensureOverlay(over: scrollView), let label else {
            return
        }

        visibilityGeneration += 1

        label.stringValue = text
        label.textColor = tint
        if let symbolName {
            icon?.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        }

        overlay.isHidden = false
        overlay.alphaValue = 1

        hideTimer?.invalidate()
        hideTimer = nil
        if let interval {
            hideTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
                self?.hide()
            }
        }
    }

    func hide() {
        guard let overlay, !overlay.isHidden else {
            return
        }

        let generation = visibilityGeneration

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            overlay.animator().alphaValue = 0
        }, completionHandler: { [weak self, weak overlay] in
            guard let self, self.visibilityGeneration == generation else {
                return
            }
            overlay?.isHidden = true
        })
    }

    func cancelPendingHide() {
        hideTimer?.invalidate()
        hideTimer = nil
    }

    /// Tears the badge down, for example when the view leaves its window.
    func remove() {
        hideTimer?.invalidate()
        hideTimer = nil
        visibilityGeneration += 1
        overlay?.removeFromSuperview()
        overlay = nil
        label = nil
        icon = nil
    }

    /// Builds the badge lazily and pins it over the bottom edge of the scroll
    /// view, so it stays put while the content scrolls.
    private func ensureOverlay(over scrollView: NSScrollView?) -> NSVisualEffectView? {
        if let overlay {
            return overlay
        }

        guard let scrollView, let host = scrollView.superview else {
            return nil
        }

        let badge = SAClickThroughVisualEffectView()
        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.material = .hudWindow
        badge.blendingMode = .withinWindow
        badge.state = .active
        badge.wantsLayer = true
        badge.layer?.cornerRadius = 6
        badge.layer?.masksToBounds = true
        badge.alphaValue = 0
        badge.isHidden = true

        let symbol = NSImageView()
        symbol.translatesAutoresizingMaskIntoConstraints = false
        symbol.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        symbol.contentTintColor = .secondaryLabelColor

        let text = NSTextField(labelWithString: "")
        text.translatesAutoresizingMaskIntoConstraints = false
        text.font = .systemFont(ofSize: NSFont.systemFontSize(for: .small), weight: .medium)
        text.lineBreakMode = .byTruncatingHead

        badge.addSubview(symbol)
        badge.addSubview(text)
        host.addSubview(badge, positioned: .above, relativeTo: scrollView)

        NSLayoutConstraint.activate([
            symbol.leadingAnchor.constraint(equalTo: badge.leadingAnchor, constant: 8),
            symbol.centerYAnchor.constraint(equalTo: badge.centerYAnchor),
            text.leadingAnchor.constraint(equalTo: symbol.trailingAnchor, constant: 4),
            text.trailingAnchor.constraint(equalTo: badge.trailingAnchor, constant: -8),
            text.centerYAnchor.constraint(equalTo: badge.centerYAnchor),
            badge.heightAnchor.constraint(equalToConstant: 22),
            badge.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            badge.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -8),
            badge.widthAnchor.constraint(lessThanOrEqualTo: scrollView.widthAnchor, constant: -16)
        ])

        overlay = badge
        label = text
        icon = symbol

        return badge
    }
}

/// The badge is purely informational; without this override the visual-effect
/// view would swallow clicks meant for the rows or text beneath it.
@objc private final class SAClickThroughVisualEffectView: NSVisualEffectView {

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}
