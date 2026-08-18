//
//  SAKeyboardShortcut.swift
//  Sequel Ace
//
//  Created as part of the modernization effort.
//  Exact keyboard chord matching for hand-rolled key event handling.
//

import AppKit

/// An exact keyboard chord — a character plus the precise set of modifiers that must be held.
///
/// Code that inspects key events by hand (local `NSEvent` monitors, `keyDown:` overrides) runs
/// ahead of the main menu's key equivalent dispatch, so a matcher that merely asks "is ⌘ among
/// the modifiers" also swallows ⌃⌘, ⌥⌘ and ⇧⌘ variants of the same character before the menu
/// items bound to them ever see the event. This type compares the whole chord instead.
@objc final class SAKeyboardShortcut: NSObject {

    /// The modifiers that distinguish one shortcut from another.
    ///
    /// Caps Lock, Fn and the numeric pad flag are deliberately excluded: they ride along on
    /// ordinary key presses without changing which shortcut the user meant.
    static let significantModifiers: NSEvent.ModifierFlags = [.command, .control, .option, .shift]

    /// The unmodified character, compared case-insensitively.
    let character: String

    /// The exact set of significant modifiers that must be held — no more, no less.
    let modifiers: NSEvent.ModifierFlags

    init(character: String, modifiers: NSEvent.ModifierFlags) {
        self.character = character
        self.modifiers = modifiers.intersection(Self.significantModifiers)
        super.init()
    }

    /// ⌘F, with no other modifier held.
    @objc static let commandF = SAKeyboardShortcut(character: "f", modifiers: .command)

    /// Whether `event` is exactly this chord.
    @objc(matchesEvent:)
    func matches(_ event: NSEvent) -> Bool {
        matches(modifierFlags: event.modifierFlags, charactersIgnoringModifiers: event.charactersIgnoringModifiers)
    }

    /// Whether the given key event components are exactly this chord.
    ///
    /// A `nil` or empty `charactersIgnoringModifiers` never matches: some key events carry no
    /// character at all, and treating those as a match would consume unrelated events.
    @objc(matchesModifierFlags:charactersIgnoringModifiers:)
    func matches(modifierFlags: NSEvent.ModifierFlags, charactersIgnoringModifiers: String?) -> Bool {
        guard let characters = charactersIgnoringModifiers, !characters.isEmpty else { return false }
        guard modifierFlags.intersection(Self.significantModifiers) == modifiers else { return false }
        return characters.compare(character, options: .caseInsensitive) == .orderedSame
    }
}
