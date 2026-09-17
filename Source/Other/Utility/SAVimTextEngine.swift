//
//  SAVimTextEngine.swift
//  Sequel Ace
//
//  Created by Sequel Ace on September 17, 2026.
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import Foundation

/// How far an operator reaches when it is applied to a motion.
///
/// This distinction is what makes `dj` delete two whole lines while `dw`
/// deletes up to but not including the next word, and `d$` deletes through the
/// last character of the line. Without it every operator would be charwise and
/// subtly wrong.
enum SAVimMotionKind: Equatable {
    case exclusive
    case inclusive
    case linewise
}

/// Text put in the unnamed register by a yank or a delete.
struct SAVimRegister: Equatable {
    var text: String
    var isLinewise: Bool
}

/// A single contiguous text replacement. Every command this engine produces
/// fits in one, which is also what keeps one vim command equal to one undo step.
struct SAVimEdit: Equatable {
    var range: NSRange
    var text: String
}

/// What the text view should do to carry out a command.
struct SAVimOutcome: Equatable {
    var edit: SAVimEdit?
    /// Caret position in post-edit coordinates.
    var caret: Int?
    /// Selection to install (visual mode).
    var selection: NSRange?
    var register: SAVimRegister?
    var mode: SAVimMode?
    /// Lines to re-indent through the text view's own shift commands, which
    /// already honour the soft-indent and tab-width preferences.
    var shiftLines: SAVimShift?
    /// The column `j`/`k` try to return to.
    var desiredColumn: Int?
    /// Where a newly started visual selection is anchored.
    var visualAnchor: Int?
    var beep: Bool = false

    static let ignored = SAVimOutcome()
    static let failed = SAVimOutcome(beep: true)
}

struct SAVimShift: Equatable {
    var range: NSRange
    var right: Bool
    var count: Int
}

/// Everything the engine needs to know about the editor's current state.
struct SAVimContext {
    var text: NSString
    var caret: Int
    var selection: NSRange
    var mode: SAVimMode
    var register: SAVimRegister?
    var lastSearch: (pattern: String, forward: Bool)?
    var desiredColumn: Int?
    /// Where the visual selection was started. The caret is its other end, so
    /// a selection extended leftwards keeps the same anchor as one extended
    /// rightwards.
    var visualAnchor: Int

    init(text: NSString,
         caret: Int,
         selection: NSRange? = nil,
         mode: SAVimMode = .normal,
         register: SAVimRegister? = nil,
         lastSearch: (pattern: String, forward: Bool)? = nil,
         desiredColumn: Int? = nil,
         visualAnchor: Int? = nil) {
        self.text = text
        self.caret = caret
        self.selection = selection ?? NSRange(location: caret, length: 0)
        self.mode = mode
        self.register = register
        self.lastSearch = lastSearch
        self.desiredColumn = desiredColumn
        self.visualAnchor = visualAnchor ?? selection?.location ?? caret
    }
}

/// Applies vim commands to a text buffer.
///
/// Pure: it is handed a string, a caret and a command, and answers with the
/// single replacement plus caret/selection that carry the command out. It never
/// touches AppKit, so `dw` at the end of a line or `3j` through a soft-wrapped
/// line can be asserted in a unit test instead of being clicked through.
/// All offsets are UTF-16, matching NSTextView's NSRange semantics.
enum SAVimTextEngine {

    /// An upper bound on the text one command may generate. The count is
    /// already capped, but the register it repeats is not.
    static let maximumGeneratedLength = 1_000_000

    // MARK: - Entry point

    static func run(_ command: SAVimCommand, context: SAVimContext) -> SAVimOutcome {
        switch command {
        case .move(let motion, let count):
            return runMove(motion, count: count, context: context)

        case .operate(let op, let target, let count):
            return runOperator(op, target: target, count: count, context: context)

        case .operateSelection(let op):
            return runSelectionOperator(op, context: context)

        case .selectTextObject(let object):
            guard let range = textObjectRange(object, context: context) else { return .failed }
            return SAVimOutcome(caret: NSMaxRange(range) - 1, selection: range, visualAnchor: range.location)

        case .enterInsert(let placement, _):
            return runEnterInsert(placement, context: context)

        case .enterVisual(let line):
            let range = line ? lineRange(at: context.caret, in: context.text) : NSRange(location: context.caret, length: 1)
            return SAVimOutcome(caret: context.caret,
                                selection: clampRange(range, in: context.text),
                                mode: line ? .visualLine : .visual,
                                visualAnchor: context.caret)

        case .exitToNormal:
            return SAVimOutcome(caret: clampToNormal(context.caret, in: context.text),
                                selection: NSRange(location: clampToNormal(context.caret, in: context.text), length: 0),
                                mode: .normal)

        case .deleteChar(let forward, let count):
            return runDeleteChar(forward: forward, count: count, context: context)

        case .substituteChar(let count):
            var outcome = runDeleteChar(forward: true, count: count, context: context)
            guard outcome.edit != nil else { return .failed }
            outcome.mode = .insert
            outcome.caret = outcome.edit?.range.location
            return outcome

        case .replaceChar(let character, let count):
            return runReplaceChar(character, count: count, context: context)

        case .paste(let after, let count):
            return runPaste(after: after, count: count, context: context)

        case .joinLines(let count):
            return runJoin(count: count, context: context)

        case .toggleCase(let count):
            return runToggleCase(count: count, context: context)

        case .search(let pattern, let forward):
            return runSearch(pattern: pattern, forward: forward, from: context.caret, context: context)

        case .repeatSearch(let reverse, let count):
            guard let last = context.lastSearch else { return .failed }
            var outcome = SAVimOutcome.failed
            var origin = context.caret
            for _ in 0..<max(count, 1) {
                outcome = runSearch(pattern: last.pattern,
                                    forward: reverse ? !last.forward : last.forward,
                                    from: origin,
                                    context: context)
                guard let caret = outcome.caret else { return .failed }
                origin = caret
            }
            return outcome

        case .undo, .redo, .repeatLastChange, .unsupported:
            // Handled by the text view: they need the undo manager or the
            // recorded keystrokes of the last change, not the buffer.
            return .ignored
        }
    }

    // MARK: - Movement

    private static func runMove(_ motion: SAVimMotion, count: Int, context: SAVimContext) -> SAVimOutcome {
        guard let resolved = destination(for: motion, count: count, context: context) else {
            return .failed
        }

        if context.mode.isVisual {
            let anchor = context.visualAnchor
            let head = resolved.location
            let range = visualRange(anchor: anchor, head: head, linewise: context.mode == .visualLine, in: context.text)
            // `caret` is the moving end of the selection, which is where the
            // next motion starts from — without it `vww` would keep
            // recomputing the first word.
            return SAVimOutcome(caret: head, selection: range, desiredColumn: resolved.desiredColumn)
        }

        let caret = clampToNormal(resolved.location, in: context.text)
        return SAVimOutcome(caret: caret,
                            selection: NSRange(location: caret, length: 0),
                            desiredColumn: resolved.desiredColumn)
    }

    /// Where a motion lands, and how an operator should treat the span.
    static func destination(for motion: SAVimMotion, count: Int, context: SAVimContext) -> (location: Int, kind: SAVimMotionKind, desiredColumn: Int?)? {
        let text = context.text
        let caret = min(context.caret, text.length)
        let repeats = max(count, 1)

        switch motion {
        case .charLeft:
            let start = lineStart(at: caret, in: text)
            return (max(start, caret - repeats), .exclusive, nil)

        case .charRight:
            let end = lineContentEnd(at: caret, in: text)
            return (min(end, caret + repeats), .exclusive, nil)

        case .lineUp, .lineDown:
            let column = context.desiredColumn ?? (caret - lineStart(at: caret, in: text))
            var lineStartLocation = lineStart(at: caret, in: text)
            for _ in 0..<repeats {
                if case .lineUp = motion {
                    guard lineStartLocation > 0 else { break }
                    lineStartLocation = lineStart(at: lineStartLocation - 1, in: text)
                } else {
                    let next = NSMaxRange(lineRange(at: lineStartLocation, in: text))
                    guard next < text.length else { break }
                    lineStartLocation = next
                }
            }
            let contentEnd = lineContentEnd(at: lineStartLocation, in: text)
            let target = min(lineStartLocation + column, contentEnd)
            return (target, .linewise, column)

        case .wordForward(let big):
            var location = caret
            for _ in 0..<repeats {
                location = nextWordStart(from: location, big: big, in: text)
            }
            return (location, .exclusive, nil)

        case .wordBackward(let big):
            var location = caret
            for _ in 0..<repeats {
                location = previousWordStart(from: location, big: big, in: text)
            }
            return (location, .exclusive, nil)

        case .wordEnd(let big):
            var location = caret
            for _ in 0..<repeats {
                location = nextWordEnd(from: location, big: big, in: text)
            }
            return (location, .inclusive, nil)

        case .lineStart:
            return (lineStart(at: caret, in: text), .exclusive, nil)

        case .firstNonBlank:
            return (firstNonBlank(at: caret, in: text), .exclusive, nil)

        case .lineEnd:
            var location = caret
            for _ in 1..<repeats {
                let next = NSMaxRange(lineRange(at: location, in: text))
                guard next < text.length else { break }
                location = next
            }
            // `$` lands on the line's last character, not on the line break,
            // so that `d$` deletes through it without swallowing the newline.
            let start = lineStart(at: location, in: text)
            let contentEnd = lineContentEnd(at: location, in: text)
            guard contentEnd > start else { return (start, .inclusive, nil) }
            return (text.rangeOfComposedCharacterSequence(at: contentEnd - 1).location, .inclusive, nil)

        case .nextLineFirstNonBlank, .previousLineFirstNonBlank:
            // `<CR>`/`+` and `-`: whole lines, landing on the first non-blank.
            var location = lineStart(at: caret, in: text)
            for _ in 0..<repeats {
                if case .previousLineFirstNonBlank = motion {
                    guard location > 0 else { break }
                    location = lineStart(at: location - 1, in: text)
                } else {
                    let next = NSMaxRange(lineRange(at: location, in: text))
                    guard next < text.length else { break }
                    location = next
                }
            }
            return (firstNonBlank(at: location, in: text), .linewise, nil)

        case .fileStart:
            return (firstNonBlank(at: 0, in: text), .linewise, nil)

        case .fileEnd:
            let last = lineStart(at: max(text.length - 1, 0), in: text)
            return (firstNonBlank(at: last, in: text), .linewise, nil)

        case .goToLine(let number):
            guard let start = startOfLine(number: number, in: text) else { return nil }
            return (firstNonBlank(at: start, in: text), .linewise, nil)

        case .findChar(let character, let forward, let till):
            guard let location = findCharacter(character, forward: forward, till: till, count: repeats, from: caret, in: text) else {
                return nil
            }
            return (location, forward ? .inclusive : .exclusive, nil)

        case .paragraphForward:
            return (paragraphBoundary(from: caret, forward: true, count: repeats, in: text), .exclusive, nil)

        case .paragraphBackward:
            return (paragraphBoundary(from: caret, forward: false, count: repeats, in: text), .exclusive, nil)

        case .matchingBracket:
            guard let location = matchingBracket(from: caret, in: text) else { return nil }
            return (location, .inclusive, nil)
        }
    }

    // MARK: - Operators

    private static func runOperator(_ op: SAVimOperator, target: SAVimTarget, count: Int, context: SAVimContext) -> SAVimOutcome {
        guard let (range, linewise) = operatorRange(target, count: count, context: context) else {
            return .failed
        }
        return apply(op, to: range, linewise: linewise, context: context)
    }

    private static func runSelectionOperator(_ op: SAVimOperator, context: SAVimContext) -> SAVimOutcome {
        let linewise = context.mode == .visualLine
        let range = linewise ? lineSpan(covering: context.selection, in: context.text) : context.selection
        guard range.length > 0 else { return .failed }
        return apply(op, to: range, linewise: linewise, context: context)
    }

    /// The span an operator covers, and whether it is linewise.
    static func operatorRange(_ target: SAVimTarget, count: Int, context: SAVimContext) -> (NSRange, Bool)? {
        let text = context.text
        let caret = min(context.caret, text.length)

        switch target {
        case .wholeLines:
            var end = lineRange(at: caret, in: text)
            for _ in 1..<max(count, 1) {
                guard NSMaxRange(end) < text.length else { break }
                end = lineRange(at: NSMaxRange(end), in: text)
            }
            let start = lineStart(at: caret, in: text)
            return (NSRange(location: start, length: NSMaxRange(end) - start), true)

        case .textObject(let object):
            guard let range = textObjectRange(object, context: context) else { return nil }
            return (range, false)

        case .motion(let motion):
            guard let resolved = destination(for: motion, count: count, context: context) else { return nil }

            if resolved.kind == .linewise {
                // Both ends are caret positions, not an exclusive range: when
                // the motion lands exactly on a line's first character (`<CR>`,
                // `2G`, `gg`), that line still has to be part of the span.
                let start = lineStart(at: min(caret, resolved.location), in: text)
                let end = NSMaxRange(lineRange(at: max(caret, resolved.location), in: text))
                return (NSRange(location: start, length: max(0, end - start)), true)
            }

            var start = min(caret, resolved.location)
            var end = max(caret, resolved.location)

            // vim's "one past the end of the line" rule: `dw` on the last word
            // of a line stops at the line break instead of swallowing it.
            if case .wordForward = motion {
                let contentEnd = lineContentEnd(at: caret, in: text)
                if end > contentEnd, caret < contentEnd {
                    end = contentEnd
                }
            }

            if resolved.kind == .inclusive, end < text.length {
                end = NSMaxRange(text.rangeOfComposedCharacterSequence(at: end))
            }

            start = max(0, min(start, text.length))
            end = max(start, min(end, text.length))
            return (NSRange(location: start, length: end - start), false)
        }
    }

    private static func apply(_ op: SAVimOperator, to range: NSRange, linewise: Bool, context: SAVimContext) -> SAVimOutcome {
        let text = context.text
        let clamped = clampRange(range, in: text)

        switch op {
        case .yank:
            let register = SAVimRegister(text: text.substring(with: clamped), isLinewise: linewise)
            let caret = linewise ? firstNonBlank(at: clamped.location, in: text) : clamped.location
            return SAVimOutcome(caret: caret,
                                selection: NSRange(location: caret, length: 0),
                                register: register,
                                mode: context.mode.isVisual ? .normal : nil)

        case .delete:
            let register = SAVimRegister(text: text.substring(with: clamped), isLinewise: linewise)
            let caret = linewise
                ? firstNonBlankAfterLineDeletion(at: clamped.location, removing: clamped, in: text)
                : clamped.location
            return SAVimOutcome(edit: SAVimEdit(range: clamped, text: ""),
                                caret: caret,
                                selection: NSRange(location: caret, length: 0),
                                register: register,
                                mode: context.mode.isVisual ? .normal : nil)

        case .change:
            let register = SAVimRegister(text: text.substring(with: clamped), isLinewise: linewise)
            if linewise {
                // `cc` empties the lines but keeps one line to type on, with
                // the original indentation, like vim with autoindent.
                let indent = indentString(ofLineAt: clamped.location, in: text)
                let keepsTrailingNewline = NSMaxRange(clamped) < text.length || text.length == 0
                let replacement = indent + (keepsTrailingNewline ? "\n" : "")
                return SAVimOutcome(edit: SAVimEdit(range: clamped, text: replacement),
                                    caret: clamped.location + (indent as NSString).length,
                                    register: register,
                                    mode: .insert)
            }
            return SAVimOutcome(edit: SAVimEdit(range: clamped, text: ""),
                                caret: clamped.location,
                                register: register,
                                mode: .insert)

        case .shiftRight, .shiftLeft:
            let span = linewise ? clamped : lineSpan(covering: clamped, in: text)
            let caret = firstNonBlank(at: span.location, in: text)
            return SAVimOutcome(caret: caret,
                                selection: NSRange(location: caret, length: 0),
                                mode: context.mode.isVisual ? .normal : nil,
                                shiftLines: SAVimShift(range: span, right: op == .shiftRight, count: 1))
        }
    }

    // MARK: - Single-key edits

    private static func runEnterInsert(_ placement: SAVimInsertPlacement, context: SAVimContext) -> SAVimOutcome {
        let text = context.text
        let caret = min(context.caret, text.length)

        switch placement {
        case .beforeCursor:
            return SAVimOutcome(caret: caret, mode: .insert)

        case .firstNonBlank:
            return SAVimOutcome(caret: firstNonBlank(at: caret, in: text), mode: .insert)

        case .afterCursor:
            let end = lineContentEnd(at: caret, in: text)
            let target = caret < end ? NSMaxRange(text.rangeOfComposedCharacterSequence(at: caret)) : end
            return SAVimOutcome(caret: min(target, end), mode: .insert)

        case .endOfLine:
            return SAVimOutcome(caret: lineContentEnd(at: caret, in: text), mode: .insert)

        case .openBelow:
            let indent = indentString(ofLineAt: caret, in: text)
            let end = lineContentEnd(at: caret, in: text)
            let inserted = "\n" + indent
            return SAVimOutcome(edit: SAVimEdit(range: NSRange(location: end, length: 0), text: inserted),
                                caret: end + (inserted as NSString).length,
                                mode: .insert)

        case .openAbove:
            let indent = indentString(ofLineAt: caret, in: text)
            let start = lineStart(at: caret, in: text)
            let inserted = indent + "\n"
            return SAVimOutcome(edit: SAVimEdit(range: NSRange(location: start, length: 0), text: inserted),
                                caret: start + (indent as NSString).length,
                                mode: .insert)
        }
    }

    private static func runDeleteChar(forward: Bool, count: Int, context: SAVimContext) -> SAVimOutcome {
        let text = context.text
        let caret = min(context.caret, text.length)
        let repeats = max(count, 1)

        if forward {
            let end = lineContentEnd(at: caret, in: text)
            var location = caret
            for _ in 0..<repeats where location < end {
                location = NSMaxRange(text.rangeOfComposedCharacterSequence(at: location))
            }
            guard location > caret else { return .failed }
            let range = NSRange(location: caret, length: location - caret)
            // The caret is re-clamped against the post-edit text by the caller,
            // which is the only place the shortened line actually exists.
            return SAVimOutcome(edit: SAVimEdit(range: range, text: ""),
                                caret: caret,
                                selection: NSRange(location: caret, length: 0),
                                register: SAVimRegister(text: text.substring(with: range), isLinewise: false))
        }

        let start = lineStart(at: caret, in: text)
        var location = caret
        for _ in 0..<repeats where location > start {
            location = text.rangeOfComposedCharacterSequence(at: location - 1).location
        }
        guard location < caret else { return .failed }
        let range = NSRange(location: location, length: caret - location)
        return SAVimOutcome(edit: SAVimEdit(range: range, text: ""),
                            caret: location,
                            selection: NSRange(location: location, length: 0),
                            register: SAVimRegister(text: text.substring(with: range), isLinewise: false))
    }

    private static func runReplaceChar(_ character: Character, count: Int, context: SAVimContext) -> SAVimOutcome {
        let text = context.text
        let caret = min(context.caret, text.length)
        let end = lineContentEnd(at: caret, in: text)
        let repeats = max(count, 1)

        var location = caret
        var replaced = 0
        while replaced < repeats, location < end {
            location = NSMaxRange(text.rangeOfComposedCharacterSequence(at: location))
            replaced += 1
        }
        // vim refuses the whole command when the line is too short.
        guard replaced == repeats, location > caret else { return .failed }

        let range = NSRange(location: caret, length: location - caret)
        let replacement = String(repeating: String(character), count: repeats)
        let caretAfter = caret + (replacement as NSString).length - 1
        return SAVimOutcome(edit: SAVimEdit(range: range, text: replacement),
                            caret: max(caret, caretAfter),
                            selection: NSRange(location: max(caret, caretAfter), length: 0))
    }

    private static func runPaste(after: Bool, count: Int, context: SAVimContext) -> SAVimOutcome {
        guard let register = context.register, !register.text.isEmpty else { return .failed }
        let text = context.text
        let caret = min(context.caret, text.length)
        let repeats = max(count, 1)

        guard (register.text as NSString).length * repeats <= maximumGeneratedLength else {
            return .failed
        }

        if register.isLinewise {
            var payload = register.text
            if !payload.hasSuffix("\n") {
                payload += "\n"
            }
            let body = String(repeating: payload, count: repeats)
            let location = after ? NSMaxRange(lineRange(at: caret, in: text)) : lineStart(at: caret, in: text)

            // Pasting below the last line, which has no trailing newline.
            if after, location >= text.length, text.length > 0, !text.hasSuffix("\n") {
                let inserted = "\n" + String(body.dropLast())
                return SAVimOutcome(edit: SAVimEdit(range: NSRange(location: text.length, length: 0), text: inserted),
                                    caret: firstNonBlankOffset(in: String(body.dropLast())) + text.length + 1,
                                    selection: nil)
            }

            let caretAfter = location + firstNonBlankOffset(in: body)
            return SAVimOutcome(edit: SAVimEdit(range: NSRange(location: location, length: 0), text: body),
                                caret: caretAfter,
                                selection: NSRange(location: caretAfter, length: 0))
        }

        let body = String(repeating: register.text, count: repeats)
        let end = lineContentEnd(at: caret, in: text)
        let location = (after && caret < end)
            ? NSMaxRange(text.rangeOfComposedCharacterSequence(at: caret))
            : caret
        let caretAfter = location + (body as NSString).length - 1
        return SAVimOutcome(edit: SAVimEdit(range: NSRange(location: location, length: 0), text: body),
                            caret: max(location, caretAfter),
                            selection: NSRange(location: max(location, caretAfter), length: 0))
    }

    private static func runJoin(count: Int, context: SAVimContext) -> SAVimOutcome {
        let text = context.text
        let caret = min(context.caret, text.length)
        // `J` and `2J` both join one line; `3J` joins two.
        let joins = max(count - 1, 1)

        let start = lineStart(at: caret, in: text)
        var joined = text.substring(with: NSRange(location: start, length: lineContentEnd(at: caret, in: text) - start))
        var end = NSMaxRange(lineRange(at: caret, in: text))
        var caretOffset = 0
        var performed = 0

        while performed < joins, end < text.length {
            let nextLine = lineRange(at: end, in: text)
            let contentEnd = lineContentEnd(at: nextLine.location, in: text)
            let raw = text.substring(with: NSRange(location: nextLine.location, length: contentEnd - nextLine.location))
            // vim drops the next line's indentation and separates with one space.
            let trimmed = String(raw.drop(while: { $0 == " " || $0 == "\t" }))

            caretOffset = (joined as NSString).length
            if joined.isEmpty || joined.hasSuffix(" ") || trimmed.isEmpty {
                joined += trimmed
            } else {
                joined += " " + trimmed
            }
            end = NSMaxRange(nextLine)
            performed += 1
        }

        guard performed > 0 else { return .failed }

        let hadTrailingNewline = end > 0 && end <= text.length && isNewline(text.character(at: end - 1))
        let replacement = joined + (hadTrailingNewline ? "\n" : "")
        let caretAfter = start + caretOffset
        return SAVimOutcome(edit: SAVimEdit(range: NSRange(location: start, length: end - start), text: replacement),
                            caret: caretAfter,
                            selection: NSRange(location: caretAfter, length: 0))
    }

    private static func runToggleCase(count: Int, context: SAVimContext) -> SAVimOutcome {
        let text = context.text
        let caret = min(context.caret, text.length)
        let end = lineContentEnd(at: caret, in: text)
        var location = caret
        for _ in 0..<max(count, 1) where location < end {
            location = NSMaxRange(text.rangeOfComposedCharacterSequence(at: location))
        }
        guard location > caret else { return .failed }

        let range = NSRange(location: caret, length: location - caret)
        let source = text.substring(with: range)
        // Some characters case-map to more than one character — "ß" uppercases
        // to "SS", "ﬁ" to "FI". Character(_:) would trap on those, and vim
        // leaves them alone anyway, so anything that is not a one-for-one swap
        // stays as it is.
        let flipped = String(source.map { character -> Character in
            let mapped = character.isUppercase ? character.lowercased()
                       : character.isLowercase ? character.uppercased()
                       : String(character)
            return mapped.count == 1 ? Character(mapped) : character
        })
        // A case mapping can change the text's length ("İ" lowercases to i plus
        // a combining dot), so the caret is given in post-edit coordinates and
        // the caller clamps it against the new text.
        let caretAfter = range.location + (flipped as NSString).length
        return SAVimOutcome(edit: SAVimEdit(range: range, text: flipped),
                            caret: caretAfter,
                            selection: NSRange(location: caretAfter, length: 0))
    }

    private static func runSearch(pattern: String, forward: Bool, from origin: Int, context: SAVimContext) -> SAVimOutcome {
        let text = context.text
        guard !pattern.isEmpty, text.length > 0 else { return .failed }

        let options: NSString.CompareOptions = forward ? [.literal] : [.literal, .backwards]

        if forward {
            let start = min(origin + 1, text.length)
            let tail = NSRange(location: start, length: text.length - start)
            var found = text.range(of: pattern, options: options, range: tail)
            if found.location == NSNotFound {
                // vim wraps around the end of the buffer.
                found = text.range(of: pattern, options: options, range: NSRange(location: 0, length: text.length))
            }
            guard found.location != NSNotFound else { return .failed }
            return SAVimOutcome(caret: found.location, selection: NSRange(location: found.location, length: 0))
        }

        // A backward search looks for the last match that *starts* before the
        // caret; searching only [0, caret) would miss the match the caret is
        // standing in the middle of.
        let patternLength = (pattern as NSString).length
        var found = NSRange(location: NSNotFound, length: 0)
        if origin > 0 {
            let limit = min(text.length, origin - 1 + patternLength)
            found = text.range(of: pattern, options: options, range: NSRange(location: 0, length: limit))
        }
        if found.location == NSNotFound {
            found = text.range(of: pattern, options: options, range: NSRange(location: 0, length: text.length))
        }
        guard found.location != NSNotFound else { return .failed }
        return SAVimOutcome(caret: found.location, selection: NSRange(location: found.location, length: 0))
    }
}

// MARK: - Buffer helpers

extension SAVimTextEngine {

    /// The line containing `location`, including its newline.
    static func lineRange(at location: Int, in text: NSString) -> NSRange {
        guard text.length > 0 else { return NSRange(location: 0, length: 0) }
        return text.lineRange(for: NSRange(location: min(location, text.length - 1), length: 0))
    }

    static func lineStart(at location: Int, in text: NSString) -> Int {
        lineRange(at: location, in: text).location
    }

    /// The end of the line's text, before the newline.
    static func lineContentEnd(at location: Int, in text: NSString) -> Int {
        guard text.length > 0 else { return 0 }
        let range = lineRange(at: location, in: text)
        var end = NSMaxRange(range)
        if end > range.location, text.character(at: end - 1) == 0x0A {
            end -= 1
        }
        if end > range.location, text.character(at: end - 1) == 0x0D {
            end -= 1
        }
        return end
    }

    static func firstNonBlank(at location: Int, in text: NSString) -> Int {
        let start = lineStart(at: location, in: text)
        let end = lineContentEnd(at: location, in: text)
        var index = start
        while index < end, isBlank(text.character(at: index)) {
            index += 1
        }
        return index
    }

    static func firstNonBlankOffset(in string: String) -> Int {
        let text = string as NSString
        var index = 0
        while index < text.length, isBlank(text.character(at: index)) {
            index += 1
        }
        return index
    }

    static func indentString(ofLineAt location: Int, in text: NSString) -> String {
        let start = lineStart(at: location, in: text)
        let end = firstNonBlank(at: location, in: text)
        guard end > start else { return "" }
        return text.substring(with: NSRange(location: start, length: end - start))
    }

    /// The start of a 1-based line number, or nil when the buffer is shorter.
    static func startOfLine(number: Int, in text: NSString) -> Int? {
        guard number >= 1 else { return nil }
        var index = 0
        var line = 1
        while line < number {
            let range = lineRange(at: index, in: text)
            let next = NSMaxRange(range)
            guard next < text.length else { return nil }
            index = next
            line += 1
        }
        return lineStart(at: index, in: text)
    }

    /// Grows a range to whole lines, newline included.
    static func lineSpan(covering range: NSRange, in text: NSString) -> NSRange {
        guard text.length > 0 else { return NSRange(location: 0, length: 0) }
        let start = lineStart(at: min(range.location, text.length - 1), in: text)
        let lastCharacter = max(range.location, NSMaxRange(range) > range.location ? NSMaxRange(range) - 1 : range.location)
        let end = NSMaxRange(lineRange(at: min(lastCharacter, text.length - 1), in: text))
        return NSRange(location: start, length: end - start)
    }

    static func clampRange(_ range: NSRange, in text: NSString) -> NSRange {
        let location = max(0, min(range.location, text.length))
        let length = max(0, min(range.length, text.length - location))
        return NSRange(location: location, length: length)
    }

    /// In normal mode the caret sits *on* a character, never past the last one
    /// of the line, which is where a line break would be.
    static func clampToNormal(_ location: Int, in text: NSString) -> Int {
        guard text.length > 0 else { return 0 }
        let bounded = max(0, min(location, text.length))
        let start = lineStart(at: bounded, in: text)
        let end = lineContentEnd(at: bounded, in: text)
        guard end > start, bounded >= end else {
            return max(start, min(bounded, end))
        }
        return text.rangeOfComposedCharacterSequence(at: end - 1).location
    }

    static func visualRange(anchor: Int, head: Int, linewise: Bool, in text: NSString) -> NSRange {
        let low = min(anchor, head)
        let high = max(anchor, head)
        if linewise {
            // Anchor and head are caret positions: when the head sits on the
            // first character of a line, that line is still selected.
            let start = lineStart(at: low, in: text)
            let end = NSMaxRange(lineRange(at: high, in: text))
            return NSRange(location: start, length: max(0, end - start))
        }
        let end = high < text.length ? NSMaxRange(text.rangeOfComposedCharacterSequence(at: high)) : text.length
        return NSRange(location: low, length: max(0, end - low))
    }

    static func firstNonBlankAfterLineDeletion(at location: Int, removing range: NSRange, in text: NSString) -> Int {
        let after = NSMaxRange(range)
        if after < text.length {
            return range.location + (firstNonBlank(at: after, in: text) - after)
        }
        guard range.location > 0 else { return 0 }
        return firstNonBlank(at: lineStart(at: range.location - 1, in: text), in: text)
    }

    static func isBlank(_ character: unichar) -> Bool {
        character == 0x20 || character == 0x09
    }

    static func isNewline(_ character: unichar) -> Bool {
        character == 0x0A || character == 0x0D
    }
}

// MARK: - Word motions

extension SAVimTextEngine {

    enum CharacterClass: Equatable {
        case whitespace
        case word
        case punctuation
    }

    static func characterClass(at index: Int, big: Bool, in text: NSString) -> CharacterClass {
        guard index >= 0, index < text.length else { return .whitespace }
        let character = text.character(at: index)
        if isBlank(character) || isNewline(character) {
            return .whitespace
        }
        if big {
            return .word
        }
        guard let scalar = Unicode.Scalar(character) else { return .word }
        if CharacterSet.alphanumerics.contains(scalar) || character == 0x5F {
            return .word
        }
        return .punctuation
    }

    static func nextWordStart(from location: Int, big: Bool, in text: NSString) -> Int {
        var index = min(location, text.length)
        guard index < text.length else { return text.length }

        let startClass = characterClass(at: index, big: big, in: text)
        if startClass != .whitespace {
            while index < text.length, characterClass(at: index, big: big, in: text) == startClass {
                index += 1
            }
        }
        while index < text.length, characterClass(at: index, big: big, in: text) == .whitespace {
            index += 1
        }
        return index
    }

    static func previousWordStart(from location: Int, big: Bool, in text: NSString) -> Int {
        var index = min(location, text.length)
        guard index > 0 else { return 0 }

        index -= 1
        while index > 0, characterClass(at: index, big: big, in: text) == .whitespace {
            index -= 1
        }
        guard characterClass(at: index, big: big, in: text) != .whitespace else { return index }

        let runClass = characterClass(at: index, big: big, in: text)
        while index > 0, characterClass(at: index - 1, big: big, in: text) == runClass {
            index -= 1
        }
        return index
    }

    static func nextWordEnd(from location: Int, big: Bool, in text: NSString) -> Int {
        var index = min(location, text.length)
        guard index < text.length else { return text.length }

        index += 1
        while index < text.length, characterClass(at: index, big: big, in: text) == .whitespace {
            index += 1
        }
        guard index < text.length else { return max(0, text.length - 1) }

        let runClass = characterClass(at: index, big: big, in: text)
        while index + 1 < text.length, characterClass(at: index + 1, big: big, in: text) == runClass {
            index += 1
        }
        return index
    }
}

// MARK: - Character, paragraph and bracket search

extension SAVimTextEngine {

    static func findCharacter(_ character: Character, forward: Bool, till: Bool, count: Int, from location: Int, in text: NSString) -> Int? {
        let needle = String(character) as NSString
        guard needle.length == 1 else { return nil }
        let target = needle.character(at: 0)

        let start = lineStart(at: location, in: text)
        let end = lineContentEnd(at: location, in: text)

        var index = location
        var found = 0
        while found < count {
            if forward {
                index += 1
                while index < end, text.character(at: index) != target {
                    index += 1
                }
                guard index < end else { return nil }
            } else {
                index -= 1
                while index >= start, text.character(at: index) != target {
                    index -= 1
                }
                guard index >= start else { return nil }
            }
            found += 1
        }

        if till {
            index += forward ? -1 : 1
        }
        return index
    }

    static func paragraphBoundary(from location: Int, forward: Bool, count: Int, in text: NSString) -> Int {
        var index = location
        for _ in 0..<max(count, 1) {
            index = singleParagraphBoundary(from: index, forward: forward, in: text)
        }
        return index
    }

    private static func singleParagraphBoundary(from location: Int, forward: Bool, in text: NSString) -> Int {
        guard text.length > 0 else { return 0 }
        var line = lineRange(at: location, in: text)

        while true {
            if forward {
                let next = NSMaxRange(line)
                guard next < text.length else { return text.length }
                line = lineRange(at: next, in: text)
            } else {
                guard line.location > 0 else { return 0 }
                line = lineRange(at: line.location - 1, in: text)
            }
            if isBlankLine(line, in: text) {
                return line.location
            }
        }
    }

    static func isBlankLine(_ range: NSRange, in text: NSString) -> Bool {
        var index = range.location
        let end = NSMaxRange(range)
        while index < end {
            let character = text.character(at: index)
            if !isBlank(character), !isNewline(character) {
                return false
            }
            index += 1
        }
        return true
    }

    private static let bracketPairs: [unichar: (partner: unichar, forward: Bool)] = [
        0x28: (0x29, true), 0x29: (0x28, false),     // ( )
        0x5B: (0x5D, true), 0x5D: (0x5B, false),     // [ ]
        0x7B: (0x7D, true), 0x7D: (0x7B, false)      // { }
    ]

    static func matchingBracket(from location: Int, in text: NSString) -> Int? {
        let end = lineContentEnd(at: location, in: text)
        var index = min(location, text.length)

        while index < end, bracketPairs[text.character(at: index)] == nil {
            index += 1
        }
        guard index < end, let pair = bracketPairs[text.character(at: index)] else { return nil }
        return matchBracket(at: index, opening: text.character(at: index), closing: pair.partner, forward: pair.forward, in: text)
    }

    static func matchBracket(at index: Int, opening: unichar, closing: unichar, forward: Bool, in text: NSString) -> Int? {
        var depth = 0
        var cursor = index

        while cursor >= 0, cursor < text.length {
            let character = text.character(at: cursor)
            if character == opening {
                depth += 1
            } else if character == closing {
                depth -= 1
                if depth == 0 {
                    return cursor
                }
            }
            cursor += forward ? 1 : -1
        }
        return nil
    }
}

// MARK: - Text objects

extension SAVimTextEngine {

    static func textObjectRange(_ object: SAVimTextObject, context: SAVimContext) -> NSRange? {
        let text = context.text
        let caret = min(context.caret, max(text.length - 1, 0))
        guard text.length > 0 else { return nil }

        switch object {
        case .word(let big, let around):
            return wordObjectRange(at: caret, big: big, around: around, in: text)

        case .quoted(let quote, let around):
            return quotedObjectRange(at: caret, quote: quote, around: around, in: text)

        case .bracketed(let open, let around):
            return bracketedObjectRange(at: caret, open: open, around: around, in: text)
        }
    }

    private static func wordObjectRange(at caret: Int, big: Bool, around: Bool, in text: NSString) -> NSRange? {
        let runClass = characterClass(at: caret, big: big, in: text)
        var start = caret
        var end = caret

        while start > 0, characterClass(at: start - 1, big: big, in: text) == runClass, !isNewline(text.character(at: start - 1)) {
            start -= 1
        }
        while end + 1 < text.length, characterClass(at: end + 1, big: big, in: text) == runClass, !isNewline(text.character(at: end + 1)) {
            end += 1
        }
        var range = NSRange(location: start, length: end - start + 1)

        guard around else { return range }

        // `aw` takes the trailing whitespace, or the leading whitespace when
        // the word is the last one on its line.
        var trailing = NSMaxRange(range)
        while trailing < text.length, characterClass(at: trailing, big: big, in: text) == .whitespace, !isNewline(text.character(at: trailing)) {
            trailing += 1
        }
        if trailing > NSMaxRange(range) {
            range.length = trailing - range.location
            return range
        }

        var leading = range.location
        while leading > 0, characterClass(at: leading - 1, big: big, in: text) == .whitespace, !isNewline(text.character(at: leading - 1)) {
            leading -= 1
        }
        range = NSRange(location: leading, length: NSMaxRange(range) - leading)
        return range
    }

    private static func quotedObjectRange(at caret: Int, quote: Character, around: Bool, in text: NSString) -> NSRange? {
        let needle = String(quote) as NSString
        guard needle.length == 1 else { return nil }
        let target = needle.character(at: 0)

        let start = lineStart(at: caret, in: text)
        let end = lineContentEnd(at: caret, in: text)

        // Walk the line's quotes in pairs so the caret's own pair is found
        // whether it sits inside the string or on a quote.
        var index = start
        var openIndex: Int?
        while index < end {
            if text.character(at: index) == target, index == start || text.character(at: index - 1) != 0x5C {
                if let open = openIndex {
                    if caret >= open, caret <= index {
                        return around
                            ? NSRange(location: open, length: index - open + 1)
                            : NSRange(location: open + 1, length: index - open - 1)
                    }
                    openIndex = nil
                } else {
                    openIndex = index
                }
            }
            index += 1
        }
        return nil
    }

    private static func bracketedObjectRange(at caret: Int, open: Character, around: Bool, in text: NSString) -> NSRange? {
        let openString = String(open) as NSString
        guard openString.length == 1 else { return nil }
        let opening = openString.character(at: 0)
        guard let closing = bracketPairs[opening]?.partner else { return nil }

        var openIndex: Int?
        var depth = 0
        var index = caret
        while index >= 0 {
            let character = text.character(at: index)
            if character == closing, index != caret {
                depth += 1
            } else if character == opening {
                if depth == 0 {
                    openIndex = index
                    break
                }
                depth -= 1
            }
            index -= 1
        }
        guard let start = openIndex else { return nil }
        guard let end = matchBracket(at: start, opening: opening, closing: closing, forward: true, in: text) else { return nil }

        if around {
            return NSRange(location: start, length: end - start + 1)
        }
        return NSRange(location: start + 1, length: max(0, end - start - 1))
    }
}
