//
//  SAClaudeSettingsValues.swift
//  Sequel Ace
//
//  What a Settings number field accepts and how it shows a value. Matches
//  the Preferences.xib number formatters it replaces (probed on the built
//  nib, 2026-10-18): non-numbers and values outside the row's range are
//  refused, never clamped, so the field keeps its old value; surrounding
//  spaces are ignored; whole-number fields refuse fractions (history, soft
//  indent, page size and the MCP port refused them; the timeout, tab width
//  and long-value fields stored a fraction their readers then truncated);
//  tenth-of-a-second fields round to the tenth they show (the "#.0"
//  formatter showed 1.55 as 1.6 but stored 1.55). Only digits and one "."
//  are a number: thousands separators (which only the lenient page-size
//  formatter took; the MCP port and the others refused "8,765"), exponents,
//  signs and a decimal comma are refused. Decimal point "." whatever the
//  locale, as the delay formatters fixed it.
//
//  Pure Swift (app + Unit Tests targets).
//

import Foundation

enum SAClaudeSettingsValues {

    /// The value `text` sets, or nil when the field must refuse it and keep its old value.
    /// A value outside `range` is refused before any rounding (as the formatters refused 0.05 and 5.04 for 0.1–5).
    /// A whole `step` (1) needs a whole number; a fractional step (0.1) rounds half-up to the nearest step.
    static func parse(_ text: String, range: ClosedRange<Double>, step: Double) -> Double? {
        let digits = text.trimmingCharacters(in: .whitespaces)
        let wholeStep = isWholeStep(step)
        guard digits.range(of: #"^([0-9]+(\.[0-9]*)?|\.[0-9]+)$"#, options: .regularExpression) != nil,
              let typed = Decimal(string: digits, locale: posix) else { return nil }
        guard typed >= decimal(range.lowerBound), typed <= decimal(range.upperBound) else { return nil }

        let stepDecimal = decimal(step)
        guard stepDecimal > 0 else { return double(typed) }
        var steps = typed / stepDecimal
        var rounded = Decimal()
        NSDecimalRound(&rounded, &steps, 0, .plain)
        if wholeStep, rounded != steps { return nil }
        let snapped = double(rounded * stepDecimal)
        return range.contains(snapped) ? snapped : nil
    }

    /// The value as the field shows it outside editing: the number, then the unit's suffix when it has one
    /// ("1.5 s", "1000").
    static func format(_ value: Double, unit: SAClaudeSettingUnit) -> String {
        guard let suffix = suffix(for: unit) else { return numberText(value) }
        return "\(numberText(value)) \(suffix)"
    }

    /// The number alone, as the field's editable text: no grouping (so it parses back as shown), up to three
    /// decimals (a legacy fractional value is shown rather than hidden), binary noise dropped.
    static func numberText(_ value: Double) -> String {
        numberFormatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    /// The unit shown inside the field after the number. Only seconds have one; rows, characters, spaces and
    /// queries are named in the row's description instead. "s" is the SI symbol, not translated.
    static func suffix(for unit: SAClaudeSettingUnit) -> String? {
        switch unit {
        case .seconds: return "s"
        case .none, .rows, .characters, .spaces, .queries: return nil
        }
    }

    /// What the field writes to its defaults key: an integer for a whole-step field (as the integer formatters
    /// produced), a double for a tenths field.
    static func storedValue(_ value: Double, step: Double) -> NSNumber {
        isWholeStep(step) ? NSNumber(value: Int(value.rounded())) : NSNumber(value: value)
    }

    static func isWholeStep(_ step: Double) -> Bool {
        step >= 1 && step.rounded() == step
    }

    // MARK: Private

    private static let posix = Locale(identifier: "en_US_POSIX")

    private static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = posix
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 3
        formatter.roundingMode = .halfUp
        return formatter
    }()

    /// A Double as the decimal its shortest description spells (0.1 is 0.1, not 0.1000000000000000055…).
    private static func decimal(_ value: Double) -> Decimal {
        Decimal(string: "\(value)", locale: posix) ?? Decimal(value)
    }

    /// The Double nearest the decimal (through its text, which converts correctly rounded; NSDecimalNumber's
    /// doubleValue can be an ulp off, so a parsed 1.6 would not == the literal 1.6).
    private static func double(_ value: Decimal) -> Double {
        Double(NSDecimalNumber(decimal: value).description(withLocale: posix)) ?? NSDecimalNumber(decimal: value).doubleValue
    }
}
