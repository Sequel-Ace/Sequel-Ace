//
//  SAClaudeQueryRunAction.swift
//  Sequel Ace
//
//  The Query tab's Run split button remembers the last run action: after Run
//  current, Run all or Run all as script (from the button's card, its menu or
//  a shortcut) the button's main half shows that action and ⌘R runs it, until
//  another one is picked, across launches. Switch Default sets the button to
//  the other of Run current / Run all. Shared with the unit tests.
//

import Foundation

/// What a run menu item or the Run button runs.
@objc enum SAClaudeQueryRunAction: Int {
    /// The query at the caret, or the selected text (the title follows the context).
    case current = 0
    /// Every query in the editor.
    case all = 1
    /// Every statement as a script, printed in the script console.
    case script = 2
}

/// Where the Run button's remembered action lives, and how the run menu's items map onto it.
///
/// The run menu has fixed shortcuts: its primary item (⌘R, and the button's main half) runs the remembered action;
/// its secondary item (⌥⌘R) the other of Run current / Run all; the script item (⇧⌥⌘R) always the script. While the
/// script is remembered, a tertiary item (no shortcut) offers the Run current / Run all the button showed before.
@objc final class SAClaudeQueryRunDefault: NSObject {

    /// Keep in sync with SPQueryPrimaryControlRunsAll in SPConstants.m: the Run current / Run all half of the state,
    /// as before (Switch Default and existing settings keep working).
    @objc static let runsAllKey = "QueryPrimaryControlRunsAll"
    /// Whether the remembered action is the script (over `runsAllKey`).
    @objc static let runsScriptKey = "ClaudeQueryPrimaryRunsScript"

    /// The remembered action: what ⌘R and the button's main half run.
    @objc(primaryActionIn:)
    static func primaryAction(in defaults: UserDefaults) -> SAClaudeQueryRunAction {
        if defaults.bool(forKey: runsScriptKey) { return .script }
        return defaults.bool(forKey: runsAllKey) ? .all : .current
    }

    /// What ⌥⌘R runs: the other of Run current / Run all.
    @objc(secondaryActionIn:)
    static func secondaryAction(in defaults: UserDefaults) -> SAClaudeQueryRunAction {
        defaults.bool(forKey: runsAllKey) ? .current : .all
    }

    /// What the tertiary item runs while the script is remembered: the Run current / Run all the button showed
    /// before it.
    @objc(tertiaryActionIn:)
    static func tertiaryAction(in defaults: UserDefaults) -> SAClaudeQueryRunAction {
        defaults.bool(forKey: runsAllKey) ? .all : .current
    }

    /// Whether the tertiary item shows: only while the script is remembered (otherwise the primary and secondary
    /// items already offer both of Run current / Run all).
    @objc(showsTertiaryIn:)
    static func showsTertiary(in defaults: UserDefaults) -> Bool {
        primaryAction(in: defaults) == .script
    }

    /// Whether running a run item makes its action the button's: a pick from the Run card or the menu does; a key
    /// equivalent (⌥⌘R) runs the other of Run current / Run all once, as it always did, without moving the button -
    /// otherwise repeated presses would alternate between the two. (⌘R runs what the button already shows, and
    /// ⇧⌥⌘R is the script's own shortcut, which does remember.)
    @objc(remembersRunTriggeredByKeyEquivalent:)
    static func remembersRun(triggeredByKeyEquivalent: Bool) -> Bool {
        !triggeredByKeyEquivalent
    }

    /// Remembers `action` as the button's: it was just run.
    @objc(rememberAction:in:)
    static func remember(_ action: SAClaudeQueryRunAction, in defaults: UserDefaults) {
        switch action {
        case .script:
            setIfChanged(true, runsScriptKey, in: defaults)
        case .current, .all:
            setIfChanged(false, runsScriptKey, in: defaults)
            setIfChanged(action == .all, runsAllKey, in: defaults)
        }
    }

    /// Switch Default: the button runs the other of Run current / Run all (from the script, the other of the one it
    /// showed before the script).
    @objc(switchDefaultIn:)
    static func switchDefault(in defaults: UserDefaults) {
        let runsAll = defaults.bool(forKey: runsAllKey)
        setIfChanged(false, runsScriptKey, in: defaults)
        defaults.set(!runsAll, forKey: runsAllKey)
    }

    /// The button's label while the script is remembered (Run current / Run all keep SPCustomQuery's labels).
    @objc static var scriptButtonTitle: String {
        NSLocalizedString("ClaudeRunButtonScript", value: "Run as script", comment: "Query editor Run button title while it runs all statements as a script (keep short)")
    }

    private static func setIfChanged(_ value: Bool, _ key: String, in defaults: UserDefaults) {
        guard defaults.object(forKey: key) == nil || defaults.bool(forKey: key) != value else { return }
        defaults.set(value, forKey: key)
    }
}
