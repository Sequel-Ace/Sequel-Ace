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
///
/// Text entry is routed through the view's input context (NSTextInputClient
/// below), so input methods such as Japanese or Chinese compose as usual and
/// the search only ever sees the text they commit.
@objc(SATablesListView) final class SATablesListView: SPTableView, NSTextInputClient {

    private static let typeAheadResetInterval: TimeInterval = 0.3

    private let typeAhead = SATypeAheadMatcher(resetInterval: SATablesListView.typeAheadResetInterval)

    // Selecting a row starts loading its table, so the selection is only
    // committed once the sequence settles (see commitPendingSelection). The
    // matched title is kept alongside the row because the list can reload
    // while the search settles.
    private var pendingSelection: (row: Int, title: String)?
    private var pendingSelectionTimer: Timer?

    // Text an input method is still composing; it is displayed but not
    // searched until the input method commits it via insertText/unmarkText.
    private var markedText = ""
    // Set while a key event is being offered to the input context, so the
    // client callbacks below know they are answering that event.
    private var routedInputEvent: NSEvent?
    private var routedInputWasConsumed = false
    private var routedInputCallbackReceived = false
    private var isDiscardingComposition = false
    // Whether the last searched string matched a row, so the badge can be
    // restored after a composition ends without a commit.
    private var lastSearchMatched = false

    private var feedbackOverlay: NSVisualEffectView?
    private var feedbackLabel: NSTextField?
    private var feedbackHideTimer: Timer?
    // Bumped on every show so a fade-out finishing late can tell its hide is
    // stale and must not conceal feedback that was re-shown mid-animation.
    private var feedbackVisibilityGeneration = 0

    override func awakeFromNib() {
        super.awakeFromNib()
        // The type-ahead below replaces the built-in single-letter type select.
        allowsTypeSelect = false
    }

    override func keyDown(with event: NSEvent) {
        if routeThroughInputContext(event) {
            return
        }

        // Escape cancels an in-progress search (keyCode 53, as in SPTableView),
        // then keeps its default behaviour via super.
        if event.keyCode == 53 {
            cancelTypeAhead()
        }
        else {
            // Any other key acts on what the user just searched for, so the
            // pending match is committed before the event is forwarded —
            // otherwise Return would start renaming the row that was selected
            // before the search, and the delayed commit would then interrupt
            // that edit.
            resolveTypeAhead()
        }

        super.keyDown(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        // A click picks its own row; a pending match must not load a table on
        // top of it once the timer fires.
        cancelTypeAhead()
        super.mouseDown(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        cancelTypeAhead()
        super.rightMouseDown(with: event)
    }

    override func resignFirstResponder() -> Bool {
        // Focus moved elsewhere (a click outside the list, tabbing away): the
        // search is over and must not act after the fact.
        cancelTypeAhead()
        return super.resignFirstResponder()
    }

    private func cancelTypeAhead() {
        typeAhead.reset()
        discardComposition()
        suspendPendingCommit()
        pendingSelection = nil
        feedbackHideTimer?.invalidate()
        hideSearchFeedback()
    }

    /// Ends the current search immediately, committing the row it matched.
    private func resolveTypeAhead() {
        suspendPendingCommit()
        commitPendingSelection()

        typeAhead.reset()
        discardComposition()
        feedbackHideTimer?.invalidate()
        hideSearchFeedback()
    }

    /// Holds back the deferred selection without forgetting it — used while an
    /// input method composes, which can easily outlast the settle interval.
    private func suspendPendingCommit() {
        pendingSelectionTimer?.invalidate()
        pendingSelectionTimer = nil
    }

    /// (Re)starts the settle timer for the row the search currently matches.
    private func schedulePendingCommit() {
        suspendPendingCommit()

        guard pendingSelection != nil else {
            return
        }

        // Selecting a row synchronously starts loading its table, and while
        // that load runs no row is selectable — an immediate selection would
        // block the characters still to come from refining the match.
        // Deferring the commit until the sequence settles also loads only the
        // final match instead of every intermediate one.
        pendingSelectionTimer = Timer.scheduledTimer(withTimeInterval: Self.typeAheadResetInterval, repeats: false) { [weak self] _ in
            self?.commitPendingSelection()
        }
    }

    /// Throws away any half-composed input method text, so it cannot be
    /// committed into a search that has already ended.
    private func discardComposition() {
        guard hasMarkedText() else {
            return
        }

        // Some input methods answer this by committing what they had, which
        // would restart the search that is being cancelled here.
        isDiscardingComposition = true
        inputContext?.discardMarkedText()
        isDiscardingComposition = false

        markedText = ""
    }

    /// Offers a text-entry keystroke to the input context first, so an input
    /// method can compose it; composed text comes back through
    /// `insertText(_:replacementRange:)`. Returns true if the event was
    /// consumed, either by the input method or by the search.
    private func routeThroughInputContext(_ event: NSEvent) -> Bool {
        // While a composition is in progress every key belongs to the input
        // method, including the ones the search would otherwise ignore.
        guard hasMarkedText() || isTextEntry(event) else {
            return false
        }

        guard let inputContext else {
            return performTypeAhead(event.characters ?? "", atTime: event.timestamp)
        }

        routedInputEvent = event
        routedInputWasConsumed = false
        routedInputCallbackReceived = false
        let handledByTextInput = inputContext.handleEvent(event)
        routedInputEvent = nil

        // When a client callback ran, its own verdict decides — a keystroke the
        // search declined (a leading space, say) still has to reach the table.
        // Otherwise the text input system swallowed the event on its own, as it
        // does for the keys an input source consumes silently, and forwarding it
        // would end the search that is still being typed.
        return routedInputCallbackReceived ? routedInputWasConsumed : handledByTextInput
    }

    /// Whether the event looks like plain text entry rather than a command.
    private func isTextEntry(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.isDisjoint(with: [.command, .control, .function]),
              let characters = event.characters,
              !characters.isEmpty
        else {
            return false
        }
        return characters.unicodeScalars.allSatisfy { isSearchableScalar($0) }
    }

    /// Extends the search with committed text and shows the new best match.
    /// Returns true if the text was consumed as part of a search. Either way
    /// the settle timer is left running for whatever is still pending, so a
    /// commit suspended during a composition is never stranded.
    @discardableResult
    private func performTypeAhead(_ characters: String, atTime time: TimeInterval) -> Bool {
        guard !characters.isEmpty,
              characters.unicodeScalars.allSatisfy({ isSearchableScalar($0) })
        else {
            schedulePendingCommit()
            return false
        }

        // A leading space should keep its default behaviour; mid-search it is
        // part of the name being typed.
        if characters == " " && !typeAhead.isActive(atTime: time) {
            schedulePendingCommit()
            return false
        }

        let titles = searchableRowTitles()
        let row = typeAhead.bestMatch(appending: characters, candidates: titles, atTime: time)

        if row != NSNotFound {
            pendingSelection = (row: row, title: titles[row])
            scrollRowToVisible(row)
        }
        else {
            // The refined search string matches nothing; the row an earlier
            // prefix matched is no longer what was asked for and must not be
            // committed once typing stops.
            pendingSelection = nil
        }

        schedulePendingCommit()

        lastSearchMatched = row != NSNotFound
        showSearchFeedback(typeAhead.currentSearchString, matched: lastSearchMatched)

        // Consume the keystroke even without a match so a longer search
        // string can't fall through to other key handling.
        return true
    }

    private func commitPendingSelection() {
        guard let pending = pendingSelection else {
            return
        }
        pendingSelection = nil

        // The list can be reloaded or reordered while the search settles, so
        // the matched name — not the row index it happened to have — is what
        // gets selected.
        let titles = searchableRowTitles()
        let row: Int
        if pending.row < titles.count, titles[pending.row] == pending.title {
            row = pending.row
        }
        else if let movedRow = titles.firstIndex(of: pending.title) {
            row = movedRow
        }
        else {
            return
        }

        // Pass the same delegate gates a user-initiated selection would:
        // selectionShouldChange(in:) rejects the change while the document is
        // running a task or has uncommitted edits, shouldSelectRow: rejects
        // individual rows.
        guard delegate?.selectionShouldChange?(in: self) ?? true,
              delegate?.tableView?(self, shouldSelectRow: row) ?? true
        else {
            return
        }

        selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        scrollRowToVisible(row)
    }

    // MARK: - NSTextInputClient

    /// Committed text — either a plain keystroke or the result of an input
    /// method composition — extends the search.
    func insertText(_ string: Any, replacementRange: NSRange) {
        markedText = ""
        noteInputCallback()

        guard !isDiscardingComposition else {
            return
        }

        let text = (string as? NSAttributedString)?.string ?? (string as? String) ?? ""
        let consumed = performTypeAhead(text, atTime: inputEventTime)

        if routedInputEvent != nil {
            routedInputWasConsumed = consumed
        }
    }

    // Satisfies NSTextInputClient's -doCommandBySelector:, which shares its
    // selector with NSResponder's.
    override func doCommand(by selector: Selector) {
        guard routedInputEvent != nil else {
            super.doCommand(by: selector)
            return
        }

        // The input method turned the keystroke into a command rather than
        // text. Nothing is consumed here, so keyDown forwards the original
        // event and the table keeps its normal handling for Return, arrows,
        // Tab, … — unless another callback already consumed the event.
        noteInputCallback()
    }

    /// Text still being composed is shown in the badge but not searched — the
    /// search only ever sees what the input method commits.
    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        let wasComposing = hasMarkedText()
        markedText = (string as? NSAttributedString)?.string ?? (string as? String) ?? ""
        noteInputCallback()

        if !markedText.isEmpty {
            // Composition in progress: appended to the badge but never marked
            // as unmatched, since it has not been searched for yet. It can
            // easily outlast the settle interval, so the row an earlier
            // character matched waits rather than loading its table midway.
            suspendPendingCommit()
            showSearchFeedback(typeAhead.currentSearchString + markedText, matched: true)
        }
        else if wasComposing {
            // Composition ended without a commit; resume the earlier match and
            // fall back to what has actually been searched. A commit instead
            // comes through insertText/unmarkText, which have already
            // rescheduled the commit and refreshed the badge by now.
            schedulePendingCommit()

            if typeAhead.currentSearchString.isEmpty {
                hideSearchFeedback()
            }
            else {
                showSearchFeedback(typeAhead.currentSearchString, matched: lastSearchMatched)
            }
        }

        // Only a call that started or ended a composition acted on the event.
        if routedInputEvent != nil, wasComposing || !markedText.isEmpty {
            routedInputWasConsumed = true
        }
    }

    /// Unmarking accepts the composed text — unlike discardMarkedText, which
    /// throws it away — so it is searched for here rather than dropped.
    func unmarkText() {
        let composedText = markedText
        markedText = ""
        noteInputCallback()

        guard !isDiscardingComposition, !composedText.isEmpty else {
            return
        }

        performTypeAhead(composedText, atTime: inputEventTime)

        if routedInputEvent != nil {
            routedInputWasConsumed = true
        }
    }

    /// Timestamp to attribute committed text to: the key event being routed,
    /// or now if the input method committed on its own (a click in its
    /// candidate window). NSEvent.timestamp uses the same clock.
    private var inputEventTime: TimeInterval {
        routedInputEvent?.timestamp ?? ProcessInfo.processInfo.systemUptime
    }

    private func noteInputCallback() {
        routedInputCallbackReceived = true
    }

    func selectedRange() -> NSRange {
        NSRange(location: markedText.utf16.count, length: 0)
    }

    func markedRange() -> NSRange {
        markedText.isEmpty ? NSRange(location: NSNotFound, length: 0) : NSRange(location: 0, length: markedText.utf16.count)
    }

    func hasMarkedText() -> Bool {
        !markedText.isEmpty
    }

    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        nil
    }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] {
        []
    }

    /// Anchors the input method's candidate window to the search badge, or to
    /// the bottom of the visible rows before the badge exists.
    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        actualRange?.pointee = range

        let rectInWindow: NSRect
        if let overlay = feedbackOverlay, !overlay.isHidden, let host = overlay.superview {
            rectInWindow = host.convert(overlay.frame, to: nil)
        }
        else {
            rectInWindow = convert(NSRect(x: visibleRect.minX, y: visibleRect.maxY, width: 1, height: 1), to: nil)
        }

        return window?.convertToScreen(rectInWindow) ?? rectInWindow
    }

    func characterIndex(for point: NSPoint) -> Int {
        NSNotFound
    }

    // MARK: - Search feedback overlay

    /// Shows the accumulated search string in a translucent badge pinned to
    /// the bottom of the list; it fades out shortly after typing stops. An
    /// unmatched search string is shown in red.
    private func showSearchFeedback(_ text: String, matched: Bool) {
        guard let overlay = ensureFeedbackOverlay(), let label = feedbackLabel else {
            return
        }

        feedbackVisibilityGeneration += 1

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
        guard let overlay = feedbackOverlay, !overlay.isHidden else {
            return
        }

        let visibilityGeneration = feedbackVisibilityGeneration

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            overlay.animator().alphaValue = 0
        }, completionHandler: { [weak self, weak overlay] in
            guard let self, self.feedbackVisibilityGeneration == visibilityGeneration else {
                return
            }
            overlay?.isHidden = true
        })
    }

    /// Builds the badge lazily and pins it over the bottom edge of the
    /// enclosing scroll view, so it stays put while the list scrolls.
    private func ensureFeedbackOverlay() -> NSVisualEffectView? {
        if let feedbackOverlay {
            return feedbackOverlay
        }

        guard let scrollView = enclosingScrollView, let host = scrollView.superview else {
            return nil
        }

        let overlay = SAClickThroughVisualEffectView()
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
        if scalar.value < 0x20 || scalar.value == 0x7F {
            return false
        }
        if (0xF700...0xF8FF).contains(scalar.value) {
            return false
        }
        return true
    }

    /// Row titles indexed by row; rows that can never hold a table (group
    /// headers, placeholders) are represented as empty strings, which never
    /// match a non-empty search string. Built from the stable group-row
    /// metadata rather than shouldSelectRow: the latter reports every row as
    /// unselectable while a load task runs, which would empty the candidate
    /// list mid-sequence.
    private func searchableRowTitles() -> [String] {
        guard let dataSource, let delegate else {
            return []
        }
        let column = tableColumns.first

        return (0..<numberOfRows).map { row in
            guard !(delegate.tableView?(self, isGroupRow: row) ?? false),
                  let title = dataSource.tableView?(self, objectValueFor: column, row: row) as? String
            else {
                return ""
            }
            return title
        }
    }
}

/// The search badge is purely informational; without this override the
/// visual-effect view would swallow clicks meant for the rows beneath it.
private final class SAClickThroughVisualEffectView: NSVisualEffectView {

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}
