//
//  SAVimKeyParser.swift
//  Sequel Ace
//
//  Created by Sequel Ace on September 17, 2026.
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import Foundation

/// The modes the query editor's vim layer can be in.
enum SAVimMode: Equatable {
    case normal
    case insert
    case visual
    case visualLine

    var isVisual: Bool {
        self == .visual || self == .visualLine
    }
}

/// Where `i I a A o O` put the caret before insert mode starts.
enum SAVimInsertPlacement: Equatable {
    case beforeCursor
    case firstNonBlank
    case afterCursor
    case endOfLine
    case openBelow
    case openAbove
}

enum SAVimOperator: Equatable {
    case delete
    case change
    case yank
    case shiftRight
    case shiftLeft
}

/// A cursor movement. Whether a motion is linewise, or charwise inclusive or
/// exclusive, is decided by SAVimTextEngine — the parser only reports which
/// motion was typed.
enum SAVimMotion: Equatable {
    case charLeft
    case charRight
    case lineUp
    case lineDown
    case wordForward(big: Bool)
    case wordBackward(big: Bool)
    case wordEnd(big: Bool)
    case lineStart
    case firstNonBlank
    case lineEnd
    case nextLineFirstNonBlank
    case previousLineFirstNonBlank
    case fileStart
    case fileEnd
    case goToLine(Int)
    case findChar(Character, forward: Bool, till: Bool)
    case paragraphForward
    case paragraphBackward
    case matchingBracket
}

enum SAVimTextObject: Equatable {
    case word(big: Bool, around: Bool)
    case quoted(Character, around: Bool)
    case bracketed(open: Character, around: Bool)
}

/// What an operator applies to.
enum SAVimTarget: Equatable {
    case motion(SAVimMotion)
    case textObject(SAVimTextObject)
    /// The doubled form: `dd`, `yy`, `cc`, `>>`, `<<`.
    case wholeLines
}

/// A complete, ready-to-run vim command. Everything the parser can produce is
/// a value — the view executes it, so replaying one (the `.` command) is just
/// running the same value again.
enum SAVimCommand: Equatable {
    case move(SAVimMotion, count: Int)
    case operate(SAVimOperator, SAVimTarget, count: Int)
    /// An operator typed in visual mode: it applies to the live selection.
    case operateSelection(SAVimOperator)
    /// A text object typed in visual mode: it becomes the selection.
    case selectTextObject(SAVimTextObject)
    case enterInsert(SAVimInsertPlacement, count: Int)
    case enterVisual(line: Bool)
    case exitToNormal
    case deleteChar(forward: Bool, count: Int)
    case substituteChar(count: Int)
    case replaceChar(Character, count: Int)
    case paste(after: Bool, count: Int)
    case joinLines(count: Int)
    case toggleCase(count: Int)
    case undo(count: Int)
    case redo(count: Int)
    case repeatLastChange(count: Int)
    case search(pattern: String, forward: Bool)
    case repeatSearch(reverse: Bool, count: Int)
    /// A key vim answers but this layer does not (`:` and friends).
    case unsupported(String)
}

enum SAVimParseResult: Equatable {
    /// The sequence is incomplete; `display` is what the mode badge should show.
    case pending(display: String)
    case command(SAVimCommand)
    /// The sequence was abandoned on purpose (Escape, empty search). No beep.
    case cancelled
    /// The sequence cannot be completed. The caller beeps.
    case rejected
    /// Not a vim key — the text view should handle it as it normally would.
    case passthrough
}

/// One key press, reduced to what the parser needs.
struct SAVimKeyStroke: Equatable {
    let character: Character?
    let keyCode: UInt16
    let control: Bool
    let option: Bool
    let command: Bool
    let shift: Bool

    static let escapeKeyCode: UInt16 = 53
    static let returnKeyCode: UInt16 = 36
    static let keypadEnterKeyCode: UInt16 = 76
    static let backspaceKeyCode: UInt16 = 51
    static let tabKeyCode: UInt16 = 48
    static let forwardDeleteKeyCode: UInt16 = 117

    /// Keys that keep moving the caret or scrolling the way they always have:
    /// arrows, page up/down, home/end, help and the function keys.
    static let navigationKeyCodes: Set<UInt16> = [
        114, 115, 116, 119, 121, 123, 124, 125, 126,
        96, 97, 98, 99, 100, 101, 103, 109, 111, 118, 120, 122
    ]

    init(character: Character?,
         keyCode: UInt16,
         control: Bool = false,
         option: Bool = false,
         command: Bool = false,
         shift: Bool = false) {
        self.character = character
        self.keyCode = keyCode
        self.control = control
        self.option = option
        self.command = command
        self.shift = shift
    }

    /// Builds a stroke from what an NSEvent reports.
    ///
    /// Vim is defined in terms of the character a key produces, not the key's
    /// position, so the character the layout yields wins: on a Turkish Q or F
    /// layout `d` is still `d`, and `$` is whatever key prints `$`. Only when
    /// the layout produces no ASCII at all — Cyrillic, Greek, kana — does the
    /// US position of the key stand in, so normal mode keeps working without
    /// switching input sources.
    init(characters: String?, keyCode: UInt16, control: Bool = false, option: Bool = false, command: Bool = false, shift: Bool = false) {
        var resolved: Character?
        if let first = characters?.first, first.isASCII, !first.isControlCharacter {
            resolved = first
        } else if let fallback = SAVimKeyStroke.usLayoutCharacter(keyCode: keyCode, shift: shift) {
            resolved = fallback
        }
        self.init(character: resolved, keyCode: keyCode, control: control, option: option, command: command, shift: shift)
    }

    var isEscape: Bool {
        // ⌃ESC belongs to the editor's fuzzy completion, so only a plain
        // Escape leaves insert mode. Ctrl-[ is vim's other way of doing it,
        // and AppKit reports that as the "[" key with the control flag set,
        // not as keyCode 53.
        (keyCode == SAVimKeyStroke.escapeKeyCode && !control) || (control && character == "[")
    }

    var isReturn: Bool {
        keyCode == SAVimKeyStroke.returnKeyCode || keyCode == SAVimKeyStroke.keypadEnterKeyCode
    }

    var isBackspace: Bool {
        keyCode == SAVimKeyStroke.backspaceKeyCode
    }

    private static let unshiftedKeyCodes: [UInt16: Character] = [
        0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x", 8: "c", 9: "v",
        11: "b", 12: "q", 13: "w", 14: "e", 15: "r", 16: "y", 17: "t",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7",
        27: "-", 28: "8", 29: "0", 30: "]", 31: "o", 32: "u", 33: "[", 34: "i", 35: "p",
        37: "l", 38: "j", 39: "'", 40: "k", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "n",
        46: "m", 47: ".", 50: "`"
    ]

    private static let shiftedKeyCodes: [UInt16: Character] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
        18: "!", 19: "@", 20: "#", 21: "$", 22: "^", 23: "%", 24: "+", 25: "(", 26: "&",
        27: "_", 28: "*", 29: ")", 30: "}", 31: "O", 32: "U", 33: "{", 34: "I", 35: "P",
        37: "L", 38: "J", 39: "\"", 40: "K", 41: ":", 42: "|", 43: "<", 44: "?", 45: "N",
        46: "M", 47: ">", 50: "~"
    ]

    static func usLayoutCharacter(keyCode: UInt16, shift: Bool) -> Character? {
        shift ? shiftedKeyCodes[keyCode] : unshiftedKeyCodes[keyCode]
    }
}

private extension Character {
    var isControlCharacter: Bool {
        guard let scalar = unicodeScalars.first, unicodeScalars.count == 1 else { return false }
        return scalar.value < 0x20 || scalar.value == 0x7F
    }
}

/// Turns key presses into vim commands.
///
/// Pure state machine: no AppKit, no text buffer, no project types — it knows
/// only which keys have been typed and which mode they leave the editor in, so
/// every sequence can be unit tested (see SAVimKeyParserTests). Applying a
/// command to text is SAVimTextEngine's job.
final class SAVimKeyParser {

    private(set) var mode: SAVimMode = .normal

    /// What the badge should show for the sequence being typed ("d2", "/nam").
    private(set) var pendingDisplay: String = ""

    private var count: Int?
    private var pendingOperator: SAVimOperator?
    private var operatorCount: Int?
    private var awaiting: Awaiting?
    private var lastFind: (character: Character, forward: Bool, till: Bool)?
    private var search: (pattern: String, forward: Bool)?

    private enum Awaiting: Equatable {
        /// `f F t T` want the character to search for.
        case findChar(forward: Bool, till: Bool)
        /// `r` wants the replacement character.
        case replaceChar
        /// `i` or `a` in operator-pending or visual mode wants the object.
        case textObject(around: Bool)
        /// `g` wants its second key.
        case gPrefix
    }

    /// True while a sequence is half-typed, so the caller knows Escape has
    /// something to cancel.
    var hasPendingSequence: Bool {
        count != nil || pendingOperator != nil || operatorCount != nil || awaiting != nil || search != nil
    }

    // MARK: - Mode

    /// Forces the mode from outside: the view calls this when it enters insert
    /// mode on its own (a `c` operator) or when the preference is switched off.
    func setMode(_ newMode: SAVimMode) {
        mode = newMode
        resetSequence()
    }

    func reset() {
        mode = .normal
        resetSequence()
    }

    private func resetSequence() {
        count = nil
        pendingOperator = nil
        operatorCount = nil
        awaiting = nil
        search = nil
        pendingDisplay = ""
    }

    // MARK: - Input

    func handle(_ stroke: SAVimKeyStroke) -> SAVimParseResult {
        // Command-key events are always app shortcuts (run query, font size).
        if stroke.command {
            return .passthrough
        }

        if stroke.isEscape {
            return handleEscape()
        }

        if mode == .insert {
            // Insert mode is plain editing: autopair, auto-indent, completion
            // and input methods all keep working because nothing is consumed.
            return .passthrough
        }

        if search != nil {
            return handleSearchKey(stroke)
        }

        if stroke.option {
            return .passthrough
        }

        if let awaiting {
            return handleAwaited(awaiting, stroke)
        }

        guard let character = stroke.character else {
            return handleKeyWithoutCharacter(stroke)
        }

        if stroke.control {
            switch character {
            case "r":
                return complete(.redo(count: takeCount()))
            default:
                return .passthrough
            }
        }

        return handleNormalOrVisual(character)
    }

    /// Return, Tab, Backspace and forward delete carry no character, and in
    /// normal mode they must not reach the text view — there they would insert
    /// a line break, expand a tab trigger or delete text, none of which normal
    /// mode is allowed to do.
    private func handleKeyWithoutCharacter(_ stroke: SAVimKeyStroke) -> SAVimParseResult {
        // ⌃↵ and the numeric keypad's Enter are how a query gets run.
        if stroke.control || stroke.option || stroke.keyCode == SAVimKeyStroke.keypadEnterKeyCode {
            return .passthrough
        }

        switch stroke.keyCode {
        case SAVimKeyStroke.returnKeyCode:
            return motion(.nextLineFirstNonBlank)
        case SAVimKeyStroke.backspaceKeyCode:
            return motion(.charLeft)
        case SAVimKeyStroke.forwardDeleteKeyCode:
            return edit(.deleteChar(forward: true, count: takeCount()))
        default:
            if SAVimKeyStroke.navigationKeyCodes.contains(stroke.keyCode) {
                // Arrows and page keys keep moving the caret as they always have.
                return .passthrough
            }
            resetSequence()
            return .rejected
        }
    }

    private func handleEscape() -> SAVimParseResult {
        if search != nil || hasPendingSequence {
            resetSequence()
            return .cancelled
        }

        switch mode {
        case .insert, .visual, .visualLine:
            mode = .normal
            resetSequence()
            return .command(.exitToNormal)
        case .normal:
            return .command(.exitToNormal)
        }
    }

    // MARK: - Normal and visual mode

    private func handleNormalOrVisual(_ character: Character) -> SAVimParseResult {
        if let digit = character.wholeNumberValue, digit >= 0, digit <= 9 {
            // "0" is a motion unless it continues a count already being typed.
            if digit != 0 || activeCount != nil {
                appendCountDigit(digit)
                return pendingResult(character)
            }
        }

        switch character {
        // Motions
        case "h": return motion(.charLeft)
        case "l", " ": return motion(.charRight)
        case "j": return motion(.lineDown)
        case "k": return motion(.lineUp)
        case "w": return motion(.wordForward(big: false))
        case "W": return motion(.wordForward(big: true))
        case "b": return motion(.wordBackward(big: false))
        case "B": return motion(.wordBackward(big: true))
        case "e": return motion(.wordEnd(big: false))
        case "E": return motion(.wordEnd(big: true))
        case "0": return motion(.lineStart)
        case "^": return motion(.firstNonBlank)
        case "$": return motion(.lineEnd)
        case "+": return motion(.nextLineFirstNonBlank)
        case "-": return motion(.previousLineFirstNonBlank)
        case "{": return motion(.paragraphBackward)
        case "}": return motion(.paragraphForward)
        case "%": return motion(.matchingBracket)
        case "G":
            if let line = activeCount {
                clearCounts()
                return motion(.goToLine(line), explicitCount: 1)
            }
            return motion(.fileEnd)

        // Multi-key prefixes
        case "g":
            awaiting = .gPrefix
            return pendingResult(character)
        case "f", "F", "t", "T":
            awaiting = .findChar(forward: character == "f" || character == "t",
                                 till: character == "t" || character == "T")
            return pendingResult(character)
        case ";", ",":
            guard let last = lastFind else { return .rejected }
            let reverse = character == ","
            return motion(.findChar(last.character,
                                    forward: reverse ? !last.forward : last.forward,
                                    till: last.till))

        // `i` and `a` start a text object after an operator or in visual mode,
        // and enter insert mode otherwise.
        case "i", "a":
            if pendingOperator != nil || mode.isVisual {
                awaiting = .textObject(around: character == "a")
                return pendingResult(character)
            }
            return enterInsert(character == "i" ? .beforeCursor : .afterCursor)

        // Insert mode entry
        case "I": return enterInsert(.firstNonBlank)
        case "A": return enterInsert(.endOfLine)
        case "o": return enterInsert(.openBelow)
        case "O": return enterInsert(.openAbove)

        // Visual mode
        case "v":
            guard pendingOperator == nil else { return .rejected }
            return toggleVisual(line: false)
        case "V":
            guard pendingOperator == nil else { return .rejected }
            return toggleVisual(line: true)

        // Operators
        case "d": return applyOperator(.delete, doubledBy: "d")
        case "c": return applyOperator(.change, doubledBy: "c")
        case "y": return applyOperator(.yank, doubledBy: "y")
        case ">": return applyOperator(.shiftRight, doubledBy: ">")
        case "<": return applyOperator(.shiftLeft, doubledBy: "<")

        // Operator shorthands
        case "D": return shorthand(.delete, .motion(.lineEnd))
        case "C": return shorthand(.change, .motion(.lineEnd))
        case "Y": return shorthand(.yank, .wholeLines)
        case "S": return shorthand(.change, .wholeLines)

        // Single-key edits
        case "x": return edit(.deleteChar(forward: true, count: takeCount()))
        case "X": return edit(.deleteChar(forward: false, count: takeCount()))
        case "s": return edit(.substituteChar(count: takeCount()))
        case "p": return edit(.paste(after: true, count: takeCount()))
        case "P": return edit(.paste(after: false, count: takeCount()))
        case "J": return edit(.joinLines(count: takeCount()))
        case "~": return edit(.toggleCase(count: takeCount()))
        case "r":
            guard pendingOperator == nil else { return .rejected }
            awaiting = .replaceChar
            return pendingResult(character)

        // Undo, redo, repeat
        case "u":
            guard pendingOperator == nil else { return .rejected }
            return complete(.undo(count: takeCount()))
        case ".":
            guard pendingOperator == nil else { return .rejected }
            return complete(.repeatLastChange(count: takeCount()))

        // Search
        case "/", "?":
            guard pendingOperator == nil else { return .rejected }
            clearCounts()
            search = (pattern: "", forward: character == "/")
            pendingDisplay = String(character)
            return .pending(display: pendingDisplay)
        case "n": return complete(.repeatSearch(reverse: false, count: takeCount()))
        case "N": return complete(.repeatSearch(reverse: true, count: takeCount()))

        case ":":
            resetSequence()
            return .command(.unsupported(":"))

        default:
            resetSequence()
            return .rejected
        }
    }

    // MARK: - Awaited second keys

    private func handleAwaited(_ awaiting: Awaiting, _ stroke: SAVimKeyStroke) -> SAVimParseResult {
        guard let character = stroke.character, !stroke.control else {
            resetSequence()
            return .rejected
        }

        switch awaiting {
        case .findChar(let forward, let till):
            lastFind = (character: character, forward: forward, till: till)
            self.awaiting = nil
            return motion(.findChar(character, forward: forward, till: till))

        case .replaceChar:
            self.awaiting = nil
            return edit(.replaceChar(character, count: takeCount()))

        case .textObject(let around):
            self.awaiting = nil
            guard let object = SAVimKeyParser.textObject(for: character, around: around) else {
                resetSequence()
                return .rejected
            }
            if let pendingOperator {
                return finishOperator(pendingOperator, .textObject(object))
            }
            resetSequence()
            return .command(.selectTextObject(object))

        case .gPrefix:
            self.awaiting = nil
            switch character {
            case "g":
                return motion(.fileStart)
            default:
                resetSequence()
                return .rejected
            }
        }
    }

    static func textObject(for character: Character, around: Bool) -> SAVimTextObject? {
        switch character {
        case "w": return .word(big: false, around: around)
        case "W": return .word(big: true, around: around)
        case "\"": return .quoted("\"", around: around)
        case "'": return .quoted("'", around: around)
        case "`": return .quoted("`", around: around)
        case "(", ")", "b": return .bracketed(open: "(", around: around)
        case "{", "}", "B": return .bracketed(open: "{", around: around)
        case "[", "]": return .bracketed(open: "[", around: around)
        default: return nil
        }
    }

    // MARK: - Search entry

    private func handleSearchKey(_ stroke: SAVimKeyStroke) -> SAVimParseResult {
        guard var entry = search else { return .rejected }

        if stroke.isReturn {
            resetSequence()
            guard !entry.pattern.isEmpty else { return .cancelled }
            return .command(.search(pattern: entry.pattern, forward: entry.forward))
        }

        if stroke.isBackspace {
            guard !entry.pattern.isEmpty else {
                resetSequence()
                return .cancelled
            }
            entry.pattern.removeLast()
            search = entry
            pendingDisplay = (entry.forward ? "/" : "?") + entry.pattern
            return .pending(display: pendingDisplay)
        }

        guard let character = stroke.character, !stroke.control else {
            return .pending(display: pendingDisplay)
        }

        entry.pattern.append(character)
        search = entry
        pendingDisplay = (entry.forward ? "/" : "?") + entry.pattern
        return .pending(display: pendingDisplay)
    }

    // MARK: - Building commands

    private var activeCount: Int? {
        pendingOperator == nil ? count : operatorCount
    }

    /// An upper bound on any count. Holding a digit down must not overflow the
    /// multiplication below, and `10000p` must not try to build a string of a
    /// size no one asked for.
    static let maximumCount = 10_000

    private func appendCountDigit(_ digit: Int) {
        if pendingOperator == nil {
            count = min((count ?? 0) * 10 + digit, SAVimKeyParser.maximumCount)
        } else {
            operatorCount = min((operatorCount ?? 0) * 10 + digit, SAVimKeyParser.maximumCount)
        }
    }

    private func clearCounts() {
        count = nil
        operatorCount = nil
    }

    /// The count a standalone command uses, consuming it.
    private func takeCount() -> Int {
        let value = min(max(count ?? 1, 1), SAVimKeyParser.maximumCount)
        clearCounts()
        return value
    }

    /// vim multiplies the two counts: `2d3w` deletes six words.
    private func takeOperatorCount() -> Int {
        let value = min(max(count ?? 1, 1) * max(operatorCount ?? 1, 1), SAVimKeyParser.maximumCount)
        clearCounts()
        return value
    }

    private func pendingResult(_ character: Character) -> SAVimParseResult {
        pendingDisplay.append(character)
        return .pending(display: pendingDisplay)
    }

    private func motion(_ motion: SAVimMotion, explicitCount: Int? = nil) -> SAVimParseResult {
        if let pendingOperator {
            return finishOperator(pendingOperator, .motion(motion), explicitCount: explicitCount)
        }
        let resolved = explicitCount ?? takeCount()
        clearCounts()
        resetSequence()
        return .command(.move(motion, count: resolved))
    }

    private func edit(_ command: SAVimCommand) -> SAVimParseResult {
        guard pendingOperator == nil else {
            resetSequence()
            return .rejected
        }
        if mode.isVisual, case .deleteChar = command {
            return visualOperator(.delete)
        }
        if mode.isVisual, case .substituteChar = command {
            return visualOperator(.change)
        }
        return complete(command)
    }

    private func complete(_ command: SAVimCommand) -> SAVimParseResult {
        resetSequence()
        return .command(command)
    }

    private func enterInsert(_ placement: SAVimInsertPlacement) -> SAVimParseResult {
        guard pendingOperator == nil, !mode.isVisual else {
            resetSequence()
            return .rejected
        }
        let repeats = takeCount()
        mode = .insert
        resetSequence()
        return .command(.enterInsert(placement, count: repeats))
    }

    private func toggleVisual(line: Bool) -> SAVimParseResult {
        let target: SAVimMode = line ? .visualLine : .visual
        if mode == target {
            mode = .normal
            resetSequence()
            return .command(.exitToNormal)
        }
        mode = target
        resetSequence()
        return .command(.enterVisual(line: line))
    }

    private func applyOperator(_ op: SAVimOperator, doubledBy character: Character) -> SAVimParseResult {
        if mode.isVisual {
            return visualOperator(op)
        }
        if let pending = pendingOperator {
            // `dd`, `yy`, `>>` … — the doubled key means "this many lines".
            guard pending == op else {
                resetSequence()
                return .rejected
            }
            return finishOperator(op, .wholeLines)
        }
        pendingOperator = op
        return pendingResult(character)
    }

    private func visualOperator(_ op: SAVimOperator) -> SAVimParseResult {
        mode = (op == .change) ? .insert : .normal
        resetSequence()
        return .command(.operateSelection(op))
    }

    private func shorthand(_ op: SAVimOperator, _ target: SAVimTarget) -> SAVimParseResult {
        guard pendingOperator == nil else {
            resetSequence()
            return .rejected
        }
        if mode.isVisual {
            return visualOperator(op)
        }
        let resolved = takeCount()
        if op == .change {
            mode = .insert
        }
        resetSequence()
        return .command(.operate(op, target, count: resolved))
    }

    private func finishOperator(_ op: SAVimOperator, _ target: SAVimTarget, explicitCount: Int? = nil) -> SAVimParseResult {
        let resolved = explicitCount ?? takeOperatorCount()
        if op == .change {
            mode = .insert
        }
        resetSequence()
        return .command(.operate(op, target, count: resolved))
    }
}
