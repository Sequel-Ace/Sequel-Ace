//
//  SATablesListView.swift
//  Sequel Ace
//
//  Created by Sequel Ace on July 27, 2026.
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import AppKit

/// The tables & views sidebar list. Replaces AppKit's built-in type select
/// with fuzzy type-ahead: keystrokes within 300 ms of each other accumulate
/// into one search string ("me" jumps to "mesajlar"), a longer pause starts a
/// new search. Matching is prefix first, then substring, then in-order
/// character subsequence — see SATypeAheadMatcher.
@objc(SATablesListView) final class SATablesListView: SPTableView {

    private let typeAhead = SATypeAheadMatcher(resetInterval: 0.3)

    private var feedbackOverlay: NSVisualEffectView?
    private var feedbackLabel: NSTextField?
    private var feedbackHideTimer: Timer?

    override func awakeFromNib() {
        super.awakeFromNib()
        // The type-ahead below replaces the built-in single-letter type select.
        allowsTypeSelect = false
    }

    override func keyDown(with event: NSEvent) {
        // Escape cancels an in-progress search (keyCode 53, as in SPTableView),
        // then keeps its default behaviour via super.
        if event.keyCode == 53 {
            cancelTypeAhead()
        }
        else if handleTypeAhead(event) {
            return
        }
        super.keyDown(with: event)
    }

    private func cancelTypeAhead() {
        typeAhead.reset()
        feedbackHideTimer?.invalidate()
        hideSearchFeedback()
    }

    /// Returns true if the event was consumed as part of a type-ahead search.
    private func handleTypeAhead(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.isDisjoint(with: [.command, .control, .function]),
              let characters = event.characters,
              !characters.isEmpty,
              characters.unicodeScalars.allSatisfy({ isSearchableScalar($0) })
        else {
            return false
        }

        // A leading space should keep its default behaviour; mid-search it is
        // part of the name being typed.
        if characters == " " && !typeAhead.isActive(atTime: event.timestamp) {
            return false
        }

        let row = typeAhead.bestMatch(appending: characters, candidates: selectableRowTitles(), atTime: event.timestamp)

        if row != NSNotFound {
            selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            scrollRowToVisible(row)
        }

        showSearchFeedback(typeAhead.currentSearchString, matched: row != NSNotFound)

        // Consume the keystroke even without a match so a longer search
        // string can't fall through to other key handling.
        return true
    }

    // MARK: - Search feedback overlay

    /// Shows the accumulated search string in a translucent badge pinned to
    /// the bottom of the list; it fades out shortly after typing stops. An
    /// unmatched search string is shown in red.
    private func showSearchFeedback(_ text: String, matched: Bool) {
        guard let overlay = ensureFeedbackOverlay(), let label = feedbackLabel else { return }

        label.stringValue = text
        label.textColor = matched ? .labelColor : .systemRed

        overlay.isHidden = false
        overlay.alphaValue = 1

        feedbackHideTimer?.invalidate()
        feedbackHideTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: false) { [weak self] _ in
            self?.hideSearchFeedback()
        }
    }

    private func hideSearchFeedback() {
        guard let overlay = feedbackOverlay, !overlay.isHidden else { return }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            overlay.animator().alphaValue = 0
        }, completionHandler: {
            overlay.isHidden = true
        })
    }

    /// Builds the badge lazily and pins it over the bottom edge of the
    /// enclosing scroll view, so it stays put while the list scrolls.
    private func ensureFeedbackOverlay() -> NSVisualEffectView? {
        if let feedbackOverlay { return feedbackOverlay }

        guard let scrollView = enclosingScrollView, let host = scrollView.superview else { return nil }

        let overlay = NSVisualEffectView()
        overlay.translatesAutoresizingMaskIntoConstraints = false
        overlay.material = .hudWindow
        overlay.blendingMode = .withinWindow
        overlay.state = .active
        overlay.wantsLayer = true
        overlay.layer?.cornerRadius = 6
        overlay.layer?.masksToBounds = true
        overlay.alphaValue = 0
        overlay.isHidden = true

        let icon = NSImageView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)
        icon.contentTintColor = .secondaryLabelColor

        let label = NSTextField(labelWithString: "")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: NSFont.systemFontSize(for: .small), weight: .medium)
        label.lineBreakMode = .byTruncatingHead

        overlay.addSubview(icon)
        overlay.addSubview(label)
        host.addSubview(overlay, positioned: .above, relativeTo: scrollView)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: overlay.leadingAnchor, constant: 8),
            icon.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: overlay.trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),
            overlay.heightAnchor.constraint(equalToConstant: 22),
            overlay.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            overlay.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -8),
            overlay.widthAnchor.constraint(lessThanOrEqualTo: scrollView.widthAnchor, constant: -16)
        ])

        feedbackOverlay = overlay
        feedbackLabel = label

        return overlay
    }

    private func isSearchableScalar(_ scalar: Unicode.Scalar) -> Bool {
        // Control characters (return, escape, tab, delete, …) and function
        // keys (arrows, F-keys — U+F700 range) keep their default behaviour.
        if scalar.value < 0x20 || scalar.value == 0x7F { return false }
        if (0xF700...0xF8FF).contains(scalar.value) { return false }
        return true
    }

    /// Row titles indexed by row; rows that must not be selected (group
    /// headers, placeholders) are represented as empty strings, which never
    /// match a non-empty search string.
    private func selectableRowTitles() -> [String] {
        guard let dataSource, let delegate else { return [] }
        let column = tableColumns.first

        return (0..<numberOfRows).map { row in
            guard delegate.tableView?(self, shouldSelectRow: row) ?? true,
                  let title = dataSource.tableView?(self, objectValueFor: column, row: row) as? String
            else {
                return ""
            }
            return title
        }
    }
}
