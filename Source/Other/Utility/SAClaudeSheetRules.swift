//
//  SAClaudeSheetRules.swift
//  Sequel Ace
//
//  The pure mapping from a description of a control to the Claude style it is
//  given inside a sheet, alert or auxiliary window. The styler reads a real
//  control into an `SAClaudeControlDescriptor` and applies the returned
//  `SAClaudeControlStyle`; nothing here touches a view. Shared with the Unit
//  Tests target.
//

import AppKit

/// What the styler needs to know about a control to pick its style.
struct SAClaudeControlDescriptor: Equatable {
    enum Kind: Equatable { case button, textField, popUp, box, table, textView, other }

    var kind: Kind
    /// `.switch` (checkbox), `.radio`, `.momentaryPushIn` ...
    var buttonType: NSButton.ButtonType? = nil
    var bezelStyle: NSButton.BezelStyle? = nil
    var title: String = ""
    var keyEquivalent: String = ""
    var isAlertButton = false
    /// 0 = the alert's first (default) button.
    var alertButtonIndex: Int? = nil
    var isDestructive = false
    var isEditable = false
    var isBezeledOrBordered = false
    var fontSize: CGFloat = 13
    var isSeparatorBox = false
    var boxTitle: String = ""
}

/// The Claude look a control is given.
enum SAClaudeControlStyle: Equatable {
    case primaryButton, secondaryButton, checkbox, radio, pill, field, label, mutedLabel
    case separator, titledBox, quietTable, editorTextView, unchanged
}

enum SAClaudeSheetRules {

    /// Labels at or below this size are drawn muted.
    static let mutedLabelMaxFontSize: CGFloat = 11

    static func style(for d: SAClaudeControlDescriptor) -> SAClaudeControlStyle {
        switch d.kind {
        case .button: return buttonStyle(for: d)
        case .textField:
            if d.isEditable { return d.isBezeledOrBordered ? .field : .unchanged }
            return d.fontSize <= mutedLabelMaxFontSize ? .mutedLabel : .label
        case .popUp: return .pill
        case .box:
            if d.isSeparatorBox { return .separator }
            return d.boxTitle.isEmpty ? .unchanged : .titledBox
        case .table: return .quietTable
        case .textView: return .editorTextView
        case .other: return .unchanged
        }
    }

    private static func buttonStyle(for d: SAClaudeControlDescriptor) -> SAClaudeControlStyle {
        if d.buttonType == .switch { return .checkbox }
        if d.buttonType == .radio { return .radio }
        if d.title.isEmpty || d.isDestructive { return .unchanged }
        if d.alertButtonIndex == 0 || d.keyEquivalent == "\r" { return .primaryButton }
        return isPushLike(d.bezelStyle) ? .secondaryButton : .unchanged
    }

    /// The push / rounded / regular-square family. On this SDK `.rounded` and `.regularSquare` are
    /// deprecated aliases of `.push` (1) and `.flexiblePush` (2), the same values, so one case each
    /// covers both spellings; going by raw value keeps the deprecated names out of the build.
    private static func isPushLike(_ bezel: NSButton.BezelStyle?) -> Bool {
        guard let bezel else { return false }
        return bezel == .push || bezel == .flexiblePush
    }
}
