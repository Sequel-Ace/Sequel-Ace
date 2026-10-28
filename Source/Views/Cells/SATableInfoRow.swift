//
//  SATableInfoRow.swift
//  Sequel Ace
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import Foundation

/// A row of the Table information pane split into its label and its value.
///
/// The pane's rows come from localized formats such as "rows: %@", whose
/// separator differs by language: ": " in English, " : " in French and a
/// full-width "：" in Chinese.
struct SATableInfoRow: Equatable {

    let label: String
    let value: String

    /// Splits `text` at its first colon, ASCII or full-width, so a value that
    /// contains colons itself (a time, a definer with a port) stays whole.
    /// The label's first letter is capitalized for `locale`.
    ///
    /// Returns nil when `text` has no separator, or nothing on either side of
    /// it, so the row is shown as it is.
    static func split(_ text: String, locale: Locale = .current) -> SATableInfoRow? {
        guard let separator = text.firstIndex(where: { $0 == ":" || $0 == "\u{FF1A}" }) else {
            return nil
        }

        let label = text[..<separator].trimmingCharacters(in: .whitespacesAndNewlines)
        let value = text[text.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty, !value.isEmpty else {
            return nil
        }

        return SATableInfoRow(label: label.prefix(1).uppercased(with: locale) + label.dropFirst(), value: value)
    }
}
