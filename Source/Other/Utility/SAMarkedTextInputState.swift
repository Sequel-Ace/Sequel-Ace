//
//  SAMarkedTextInputState.swift
//  Sequel Ace
//
//  Created by Sequel Ace on August 24, 2026.
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import AppKit

/// The transient text storage an `NSTextInputClient` needs while an input
/// method is composing text for type-ahead search.
///
/// AppKit expresses editing keys such as Delete and Left Arrow as commands
/// against the client's marked text. An isolated field editor supplies the
/// standard Unicode-aware command behaviour without sending those commands to
/// the tables view or putting the unfinished text into the search.
final class SAMarkedTextInputState {

    private(set) var text = ""
    private(set) var selectedRange = NSRange(location: 0, length: 0)

    private lazy var commandEditor: NSTextView = {
        let editor = NSTextView(frame: .zero)
        editor.isFieldEditor = true
        editor.isRichText = false
        return editor
    }()

    var hasMarkedText: Bool {
        !text.isEmpty
    }

    var markedRange: NSRange {
        hasMarkedText
            ? NSRange(location: 0, length: text.utf16.count)
            : NSRange(location: NSNotFound, length: 0)
    }

    /// Replaces the range supplied by the input method and records its
    /// selection, whose location is relative to the inserted string.
    func setMarkedText(_ string: String, selectedRange: NSRange, replacementRange: NSRange) {
        let oldLength = text.utf16.count
        let rangeToReplace: NSRange

        if replacementRange.location == NSNotFound {
            rangeToReplace = hasMarkedText
                ? NSRange(location: 0, length: oldLength)
                : Self.clamp(self.selectedRange, toLength: oldLength)
        }
        else {
            rangeToReplace = Self.clamp(replacementRange, toLength: oldLength)
        }

        let mutableText = NSMutableString(string: text)
        mutableText.replaceCharacters(in: rangeToReplace, with: string)
        text = mutableText as String

        let relativeSelection = Self.clamp(selectedRange, toLength: string.utf16.count)
        self.selectedRange = NSRange(
            location: rangeToReplace.location + relativeSelection.location,
            length: relativeSelection.length
        )
    }

    /// Executes a standard key-binding command against the marked text.
    /// Returns false when no composition exists or when the command belongs to
    /// the ordinary responder rather than the composition buffer.
    @discardableResult
    func performCommand(_ selector: Selector) -> Bool {
        // Escape arrives as cancelOperation:. Let the real table responder
        // cancel its type-ahead state and preserve its usual Escape behaviour.
        guard hasMarkedText, selector != #selector(NSResponder.cancelOperation(_:)) else {
            return false
        }

        commandEditor.string = text
        commandEditor.setSelectedRange(Self.clamp(selectedRange, toLength: text.utf16.count))
        commandEditor.doCommand(by: selector)

        text = commandEditor.string
        selectedRange = Self.clamp(commandEditor.selectedRange(), toLength: text.utf16.count)
        return true
    }

    func clear() {
        text = ""
        selectedRange = NSRange(location: 0, length: 0)
    }

    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        guard range.location != NSNotFound, range.location <= text.utf16.count else {
            actualRange?.pointee = NSRange(location: NSNotFound, length: 0)
            return nil
        }

        let actual = Self.clamp(range, toLength: text.utf16.count)
        actualRange?.pointee = actual
        return NSAttributedString(string: (text as NSString).substring(with: actual))
    }

    private static func clamp(_ range: NSRange, toLength length: Int) -> NSRange {
        guard range.location != NSNotFound else {
            return NSRange(location: length, length: 0)
        }

        let location = min(range.location, length)
        let rangeLength = min(range.length, length - location)
        return NSRange(location: location, length: rangeLength)
    }
}
