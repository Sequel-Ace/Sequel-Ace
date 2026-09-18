//
//  SAQueryTextView.swift
//  Sequel Ace
//
//  Created by Sequel Ace on September 17, 2026.
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import AppKit

/// The SQL query editor, with an optional vim keybinding layer.
///
/// The layer is off unless the "Vim mode" preference is on, and when it is off
/// this class does nothing at all: every event goes straight to SPTextView, so
/// completion, snippet tab stops, auto-pairing and auto-indent behave exactly
/// as they always have. With it on, insert mode still forwards everything to
/// SPTextView — only normal and visual mode consume keys.
///
/// Keys are turned into commands by SAVimKeyParser and into text changes by
/// SAVimTextEngine, both of which are pure and unit tested; this class only
/// applies their answers to the text view.
@objc(SAQueryTextView) final class SAQueryTextView: SPTextView {

    private let parser = SAVimKeyParser()
    private let modeBadge = SAOverlayBadge(symbolName: "command")

    private var isVimModeEnabled = false
    private var preferenceSubscription: NotificationToken?

    /// The unnamed register: vim's single clipboard for yank, delete and put.
    private var register: SAVimRegister?
    private var lastSearch: (pattern: String, forward: Bool)?
    /// The column `j` and `k` try to return to across short lines.
    private var desiredColumn: Int?
    private var visualAnchor: Int = 0
    /// The moving end of a visual selection. Motions start from here, not from
    /// the selection's start, so extending a selection twice keeps going.
    private var visualHead: Int = 0

    /// The last change, replayed by `.`, together with whatever was typed in
    /// the insert session that followed it.
    private var lastChange: (command: SAVimCommand, insertedText: String)?
    private var insertSessionStart: Int?
    private var insertSessionCommand: SAVimCommand?
    private var insertSessionCount = 1
    /// The buffer's length when insert mode started, so the text the session
    /// actually inserted can be told apart from text the caret merely moved over.
    private var insertSessionTextLength = 0
    private var isReplayingChange = false

    private var insertUndoGroupIsOpen = false
    private var undoManagerGroupsByEvent = true

    // MARK: - Lifecycle

    override func awakeFromNib() {
        super.awakeFromNib()

        guard isQueryEditor else { return }

        applyVimModePreference()
        preferenceSubscription = NotificationCenter.default.observe(
            name: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Fires for any defaults change, so only act on a real transition.
            self?.applyVimModePreference()
        }
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        leaveInsertMode()
        modeBadge.remove()
        super.viewWillMove(toWindow: newWindow)
    }

    deinit {
        endInsertUndoGroup()
    }

    /// Only the query editor gets a vim mode; the same class must stay inert
    /// anywhere else it is ever instantiated.
    private var isQueryEditor: Bool {
        delegate is SPCustomQuery
    }

    private var isVimActive: Bool {
        isVimModeEnabled && isQueryEditor && isEditable
    }

    // MARK: - Preference

    private func applyVimModePreference() {
        let enabled = UserDefaults.standard.bool(forKey: SPCustomQueryVimMode)
        guard enabled != isVimModeEnabled else { return }

        isVimModeEnabled = enabled

        if enabled {
            parser.reset()
            visualAnchor = selectedRange().location
            visualHead = visualAnchor
            setSelectedRange(NSRange(location: normalisedCaret(selectedRange().location), length: 0))
        }
        else {
            // Leave the editor in a plain state: no half-typed command, no
            // block cursor, no badge.
            leaveInsertMode()
            parser.setMode(.insert)
            modeBadge.hide()
        }

        refreshBadge()
        refreshInsertionPoint()
    }

    // MARK: - Key handling

    override func keyDown(with event: NSEvent) {
        guard isVimActive else {
            super.keyDown(with: event)
            return
        }

        // The completion popup runs its own event loop and the snippet tab
        // stops own Tab, so the vim layer stands aside for both. Marked text
        // means an input method is mid-composition.
        if completionIsOpen || isSnippetMode() || hasMarkedText() {
            super.keyDown(with: event)
            return
        }

        let flags = event.modifierFlags
        let stroke = SAVimKeyStroke(characters: event.charactersIgnoringModifiers,
                                    keyCode: event.keyCode,
                                    control: flags.contains(.control),
                                    option: flags.contains(.option),
                                    command: flags.contains(.command),
                                    shift: flags.contains(.shift))

        switch parser.handle(stroke) {
        case .passthrough:
            super.keyDown(with: event)

        case .pending(let display):
            refreshBadge(pending: display)

        case .cancelled:
            refreshBadge()

        case .rejected:
            NSSound.beep()
            refreshBadge()

        case .command(let command):
            perform(command)
        }
    }

    // MARK: - Running commands

    private func perform(_ command: SAVimCommand) {
        switch command {
        case .undo(let count):
            leaveInsertMode()
            for _ in 0..<count where undoManager?.canUndo == true {
                undoManager?.undo()
            }
            setSelectedRange(NSRange(location: normalisedCaret(selectedRange().location), length: 0))
            refreshInsertionPoint()
            refreshBadge()

        case .redo(let count):
            for _ in 0..<count where undoManager?.canRedo == true {
                undoManager?.redo()
            }
            setSelectedRange(NSRange(location: normalisedCaret(selectedRange().location), length: 0))
            refreshInsertionPoint()
            refreshBadge()

        case .repeatLastChange(let count):
            replayLastChange(count: count)

        case .unsupported:
            NSSound.beep()
            refreshBadge(pending: NSLocalizedString("not supported",
                                                    comment: "Query editor : vim mode : badge text for a key this layer does not implement"))

        default:
            if case .exitToNormal = command {
                leaveInsertMode(applyingRepeat: true)
            }
            let outcome = SAVimTextEngine.run(command, context: makeContext())
            apply(outcome)

            // `n` and `N` repeat this pattern, whether or not it matched.
            if case .search(let pattern, let forward) = command {
                lastSearch = (pattern: pattern, forward: forward)
            }

            finishCommand(command, outcome: outcome)
        }
    }

    private func makeContext() -> SAVimContext {
        SAVimContext(text: string as NSString,
                     caret: parser.mode.isVisual ? visualHead : selectedRange().location,
                     selection: selectedRange(),
                     mode: parser.mode,
                     register: register,
                     lastSearch: lastSearch,
                     desiredColumn: desiredColumn,
                     visualAnchor: visualAnchor)
    }

    private func apply(_ outcome: SAVimOutcome) {
        if outcome.beep {
            NSSound.beep()
            refreshBadge()
            return
        }

        // A change operator's own edit belongs to the insert session it opens,
        // so that `cw` plus the text typed after it is a single undo step.
        if outcome.mode == .insert {
            beginInsertUndoGroup()
        }

        if let edit = outcome.edit {
            guard shouldChangeText(in: edit.range, replacementString: edit.text) else {
                // The delegate refused the edit, so the insert session this
                // command was about to open never happens — close its undo
                // group again rather than leaving grouping switched off, and
                // put the parser back in normal mode so the next key is read
                // as a command and not typed into the query.
                leaveInsertMode()
                parser.setMode(.normal)
                refreshInsertionPoint()
                refreshBadge()
                NSSound.beep()
                return
            }
            // One vim command is one undo step, never merged with the typing
            // around it.
            breakUndoCoalescing()
            textStorage?.replaceCharacters(in: edit.range, with: edit.text)
            didChangeText()
            breakUndoCoalescing()
        }

        if let shift = outcome.shiftLines {
            performShift(shift)
        }

        if let register = outcome.register {
            self.register = register
        }

        if let mode = outcome.mode {
            if mode != .insert {
                leaveInsertMode()
            }
            // The parser already knows the mode it put itself in; this keeps
            // the two agreed when the engine is the one deciding.
            parser.setMode(mode)
        }

        if let anchor = outcome.visualAnchor {
            visualAnchor = boundedCaret(anchor)
        }

        if parser.mode.isVisual, let selection = outcome.selection {
            setSelectedRange(clampedRange(selection))
            scrollRangeToVisible(clampedRange(selection))
            if let head = outcome.caret {
                visualHead = boundedCaret(head)
            }
        }
        else if let caret = outcome.caret {
            let location = parser.mode == .insert ? boundedCaret(caret) : normalisedCaret(caret)
            setSelectedRange(NSRange(location: location, length: 0))
            visualAnchor = location
            visualHead = location
            scrollRangeToVisible(NSRange(location: location, length: 0))
        }

        // Only vertical motions keep a desired column; anything else drops it.
        desiredColumn = outcome.desiredColumn

        refreshInsertionPoint()
        refreshBadge()
    }

    /// `>` and `<` go through the text view's own shift commands, which
    /// already honour the soft-indent and tab-width preferences.
    private func performShift(_ shift: SAVimShift) {
        let previousSelection = selectedRange()
        setSelectedRange(clampedRange(shift.range))

        for _ in 0..<max(shift.count, 1) {
            let changed = shift.right ? shiftSelectionRight() : shiftSelectionLeft()
            if !changed {
                NSSound.beep()
                break
            }
        }

        let restored = min(previousSelection.location, (string as NSString).length)
        setSelectedRange(NSRange(location: normalisedCaret(restored), length: 0))
    }

    private func finishCommand(_ command: SAVimCommand, outcome: SAVimOutcome?) {
        guard !isReplayingChange else { return }

        if command.startsAnInsertSession, parser.mode == .insert {
            insertSessionCommand = command
            insertSessionStart = selectedRange().location
            insertSessionCount = command.insertRepeatCount
            insertSessionTextLength = (string as NSString).length
        }
        else if command.isRepeatable, outcome?.beep != true {
            lastChange = (command: command, insertedText: "")
        }
    }

    // MARK: - Mode transitions

    /// Closes an insert session: the text typed during it is what `.` replays.
    /// Returns how many times the session's command asked to be repeated.
    /// `applyingRepeat` is set only when insert mode ends the way vim ends it,
    /// with Escape — losing focus or switching the preference off must not
    /// suddenly triple what was typed.
    @discardableResult
    private func leaveInsertMode(applyingRepeat: Bool = false) -> Int {
        defer { endInsertUndoGroup() }

        guard let start = insertSessionStart, let command = insertSessionCommand else { return 1 }
        let repeats = insertSessionCount
        let lengthAtStart = insertSessionTextLength
        insertSessionStart = nil
        insertSessionCommand = nil
        insertSessionCount = 1

        let text = string as NSString
        let caret = min(selectedRange().location, text.length)
        // Only a plain forward insertion is safe to replay: arrow keys and
        // deletes reach the text view untouched in insert mode, and the text
        // between the start and the caret would then be something the session
        // never typed.
        let typed = caret - start
        let grew = text.length - lengthAtStart
        let inserted = (typed > 0 && typed == grew)
            ? text.substring(with: NSRange(location: start, length: typed))
            : ""
        lastChange = (command: command, insertedText: inserted)

        // The extra copies a count asks for go in here, while the caret is
        // still the insert caret — normal mode pulls it back onto the last
        // character, and writing there would split the text. Being inside the
        // session's undo group also keeps `3Afoo` a single undo step.
        if applyingRepeat, repeats > 1, !inserted.isEmpty {
            let extra = repeatedInsertion(of: inserted, for: command, copies: repeats - 1)
            if !extra.isEmpty {
                insert(extra)
            }
        }

        // Nothing was typed, so there is nothing to repeat — and repeating an
        // empty session used to leave the editor in insert mode.
        return inserted.isEmpty ? 1 : max(repeats, 1)
    }

    private func replayLastChange(count: Int) {
        guard let change = lastChange else {
            NSSound.beep()
            return
        }

        isReplayingChange = true
        defer {
            isReplayingChange = false
            refreshInsertionPoint()
            refreshBadge()
        }

        // The recorded text is one copy of what was typed; a count like `3i`
        // asked for more.
        let payload = change.insertedText
            + repeatedInsertion(of: change.insertedText,
                                for: change.command,
                                copies: max(change.command.insertRepeatCount - 1, 0))

        for _ in 0..<max(count, 1) {
            let outcome = SAVimTextEngine.run(change.command, context: makeContext())
            if outcome.beep {
                NSSound.beep()
                return
            }
            apply(outcome)

            // Whatever happens next, the replay must not leave the editor in
            // insert mode with an undo group still open.
            if !payload.isEmpty {
                insert(payload)
            }
            parser.setMode(.normal)
            leaveInsertMode()
            setSelectedRange(NSRange(location: normalisedCaret(selectedRange().location), length: 0))
        }
    }

    /// Inserts literal text at the caret as one undo step, leaving the caret
    /// after it.
    private func insert(_ text: String) {
        let range = selectedRange()
        guard shouldChangeText(in: range, replacementString: text) else {
            NSSound.beep()
            return
        }
        breakUndoCoalescing()
        textStorage?.replaceCharacters(in: range, with: text)
        didChangeText()
        breakUndoCoalescing()
        setSelectedRange(NSRange(location: range.location + (text as NSString).length, length: 0))
    }

    /// The extra copies a count asks for. `i`, `a`, `I` and `A` simply repeat
    /// what was typed; `o` and `O` repeat the line they opened, indent included.
    private func repeatedInsertion(of text: String, for command: SAVimCommand, copies: Int) -> String {
        guard copies > 0, !text.isEmpty else { return "" }

        switch command {
        case .enterInsert(.openBelow, _), .enterInsert(.openAbove, _):
            let indent = SAVimTextEngine.indentString(ofLineAt: selectedRange().location, in: string as NSString)
            return String(repeating: "\n" + indent + text, count: copies)
        default:
            return String(repeating: text, count: copies)
        }
    }

    // MARK: - Undo grouping

    /// An insert session is one undo step, which means grouping across several
    /// events — the only way to do that is to take grouping off the event loop
    /// for the duration. Every path that leaves insert mode closes the group
    /// again, including losing focus and the window going away.
    private func beginInsertUndoGroup() {
        guard !insertUndoGroupIsOpen, let manager = undoManager else { return }

        breakUndoCoalescing()
        undoManagerGroupsByEvent = manager.groupsByEvent
        manager.groupsByEvent = false
        manager.beginUndoGrouping()
        insertUndoGroupIsOpen = true
    }

    private func endInsertUndoGroup() {
        guard insertUndoGroupIsOpen else { return }
        // Clear the flag first: if the undo manager has gone away there is
        // nothing left to close, and retrying would leave grouping switched
        // off for good.
        insertUndoGroupIsOpen = false

        guard let manager = undoManager else { return }

        breakUndoCoalescing()
        manager.endUndoGrouping()
        manager.groupsByEvent = undoManagerGroupsByEvent
    }

    override func resignFirstResponder() -> Bool {
        leaveInsertMode()
        modeBadge.hide()
        return super.resignFirstResponder()
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted {
            refreshBadge()
        }
        return accepted
    }

    // MARK: - Caret

    /// In normal and visual mode the caret sits on a character, never on the
    /// line break past the last one.
    private func normalisedCaret(_ location: Int) -> Int {
        guard isVimActive, parser.mode != .insert else { return boundedCaret(location) }
        return SAVimTextEngine.clampToNormal(location, in: string as NSString)
    }

    private func boundedCaret(_ location: Int) -> Int {
        max(0, min(location, (string as NSString).length))
    }

    private func clampedRange(_ range: NSRange) -> NSRange {
        let length = (string as NSString).length
        let location = max(0, min(range.location, length))
        return NSRange(location: location, length: max(0, min(range.length, length - location)))
    }

    private var wantsBlockCursor: Bool {
        isVimActive && parser.mode != .insert
    }

    /// Draws the block cursor of normal and visual mode. It is the insertion
    /// point widened to the character under it — not a one-character
    /// selection, which would switch off the active-query highlight and look
    /// like a real selection to the snippet machinery.
    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        guard wantsBlockCursor else {
            super.drawInsertionPoint(in: rect, color: color, turnedOn: flag)
            return
        }

        var blockRect = rect
        blockRect.size.width = blockCursorWidth
        super.drawInsertionPoint(in: blockRect, color: color, turnedOn: flag)
    }

    /// The insertion point is erased by redrawing its rect, so the widened
    /// rect has to be invalidated too or the block leaves a trail.
    override func setNeedsDisplay(_ rect: NSRect, avoidAdditionalLayout flag: Bool) {
        guard wantsBlockCursor else {
            super.setNeedsDisplay(rect, avoidAdditionalLayout: flag)
            return
        }

        // Deliberately the font-based width, not the measured one: this is
        // called with avoidAdditionalLayout, and measuring a glyph here would
        // force the layout the caller is asking us not to do.
        var widened = rect
        widened.size.width += blockCursorPadding
        super.setNeedsDisplay(widened, avoidAdditionalLayout: flag)
    }

    private var blockCursorPadding: CGFloat {
        max((font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)).maximumAdvancement.width, 2)
    }

    private var blockCursorWidth: CGFloat {
        let fallback = blockCursorPadding

        let text = string as NSString
        let caret = selectedRange().location
        guard caret < text.length,
              let layoutManager,
              let container = textContainer else {
            return fallback
        }

        let characterRange = text.rangeOfComposedCharacterSequence(at: caret)
        guard !SAVimTextEngine.isNewline(text.character(at: caret)) else { return fallback }

        let glyphRange = layoutManager.glyphRange(forCharacterRange: characterRange, actualCharacterRange: nil)
        let bounds = layoutManager.boundingRect(forGlyphRange: glyphRange, in: container)
        return bounds.width > 1 ? bounds.width : fallback
    }

    private func refreshInsertionPoint() {
        updateInsertionPointStateAndRestartTimer(true)
        needsDisplay = true
    }

    // MARK: - Mode badge

    private func refreshBadge(pending: String? = nil) {
        guard isVimActive else {
            modeBadge.hide()
            return
        }

        let sequence = pending ?? parser.pendingDisplay
        let text = sequence.isEmpty ? modeName : "\(modeName)  \(sequence)"
        modeBadge.show(text, over: enclosingScrollView)
    }

    private var modeName: String {
        switch parser.mode {
        case .normal:
            return NSLocalizedString("-- NORMAL --", comment: "Query editor : vim mode : normal mode badge")
        case .insert:
            return NSLocalizedString("-- INSERT --", comment: "Query editor : vim mode : insert mode badge")
        case .visual:
            return NSLocalizedString("-- VISUAL --", comment: "Query editor : vim mode : visual mode badge")
        case .visualLine:
            return NSLocalizedString("-- VISUAL LINE --", comment: "Query editor : vim mode : visual line mode badge")
        }
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)

        guard isVimActive, parser.mode != .insert else { return }

        let selection = selectedRange()
        if selection.length == 0, parser.mode.isVisual {
            parser.setMode(.normal)
        }
        else if selection.length > 0, !parser.mode.isVisual {
            parser.setMode(.visual)
        }
        visualAnchor = selection.location
        visualHead = selection.length > 0 ? max(selection.location, NSMaxRange(selection) - 1) : selection.location
        desiredColumn = nil
        refreshBadge()
        refreshInsertionPoint()
    }
}

private extension SAVimCommand {

    /// Commands that leave the editor in insert mode, so the text typed next
    /// belongs to the same change for the purposes of `.`.
    var startsAnInsertSession: Bool {
        switch self {
        case .enterInsert, .substituteChar:
            return true
        case .operate(let op, _, _):
            return op == .change
        case .operateSelection(let op):
            return op == .change
        default:
            return false
        }
    }

    /// How many times `3i` and friends ask for their insertion to be repeated.
    var insertRepeatCount: Int {
        switch self {
        case .enterInsert(_, let count):
            return count
        default:
            return 1
        }
    }

    /// Changes `.` can replay on their own.
    var isRepeatable: Bool {
        switch self {
        case .operate, .operateSelection, .deleteChar, .replaceChar, .paste, .joinLines, .toggleCase:
            return true
        default:
            return false
        }
    }
}
