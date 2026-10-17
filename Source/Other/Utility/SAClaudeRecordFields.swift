//
//  SAClaudeRecordFields.swift
//  Sequel Ace
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//
//  Pure logic behind the Claude-look Record View panel: how a field is
//  displayed (NULL chip, not-loaded, pretty JSON, display cap), search
//  matching and highlight ranges, the long-value collapse decision, row
//  stepping and per-row panel state. No AppKit/SwiftUI, no project ObjC
//  types, so it compiles into the Unit Tests target.
//

import Foundation

/// What the panel shows for a field's value.
enum SAClaudeRecordDisplayValue: Equatable {
    /// SQL NULL - drawn as a chip, never as text.
    case null
    /// A BLOB/TEXT value not loaded yet - drawn as "(not loaded)".
    case notLoaded
    /// The text to show (possibly pretty-printed JSON, possibly capped).
    case text(String)
}

/// Where a search query hits a field, as UTF-16 ranges (NSRange) into the
/// field name and into the displayed value text.
struct SAClaudeRecordMatch: Equatable {
    var nameRanges: [NSRange]
    var valueRanges: [NSRange]
}

/// Per-row view state that survives a refresh of the same row (edit commit,
/// reload) but not a move to another row.
struct SAClaudeRecordPanelState: Equatable {
    var rowKey: String
    var expandedFieldIDs: Set<Int>
}

enum SAClaudeRecordFields {
    /// A value taller than this many lines is collapsed behind "Show all N lines".
    static let collapsedLineLimit = 6
    /// Values are cut to this many characters for display; copy/edit use the full value.
    static let displayCharacterCap = 100_000

    private static let maxJSONDepth = 256

    // MARK: - Display value

    static func displayValue(_ field: SARecordField) -> SAClaudeRecordDisplayValue {
        if field.isNull {
            return .null
        }
        if field.notLoaded {
            return .notLoaded
        }
        var text = field.value
        if field.type.caseInsensitiveCompare("JSON") == .orderedSame, let pretty = prettyJSON(text) {
            text = pretty
        }
        return .text(capped(text))
    }

    private static func capped(_ text: String) -> String {
        // prefix(cap + 1) keeps this O(cap) however large the value is.
        let head = text.prefix(displayCharacterCap + 1)
        guard head.count > displayCharacterCap else {
            return text
        }
        return String(head.prefix(displayCharacterCap)) + "…"
    }

    // MARK: - JSON

    /// Pretty-prints a JSON object or array with a 2-space indent, keeping keys
    /// in source order (JSONSerialization does not guarantee that) and number
    /// and string tokens exactly as written. Returns nil when `text` isn't a
    /// well-formed JSON object or array.
    static func prettyJSON(_ text: String) -> String? {
        var printer = JSONPrinter(bytes: Array(text.utf8))
        return printer.run()
    }

    private struct JSONPrinter {
        let bytes: [UInt8]
        var position = 0
        var output: [UInt8] = []

        init(bytes: [UInt8]) {
            self.bytes = bytes
            output.reserveCapacity(bytes.count + bytes.count / 4)
        }

        mutating func run() -> String? {
            skipWhitespace()
            guard position < bytes.count, bytes[position] == UInt8(ascii: "{") || bytes[position] == UInt8(ascii: "[") else {
                return nil
            }
            guard value(depth: 0) else {
                return nil
            }
            skipWhitespace()
            guard position == bytes.count else {
                return nil
            }
            return String(bytes: output, encoding: .utf8)
        }

        private mutating func skipWhitespace() {
            while position < bytes.count {
                switch bytes[position] {
                case 0x20, 0x09, 0x0A, 0x0D: position += 1
                default: return
                }
            }
        }

        private mutating func newline(_ depth: Int) {
            output.append(0x0A)
            output.append(contentsOf: repeatElement(0x20, count: depth * 2))
        }

        private mutating func value(depth: Int) -> Bool {
            guard depth <= SAClaudeRecordFields.maxJSONDepth, position < bytes.count else {
                return false
            }
            switch bytes[position] {
            case UInt8(ascii: "{"): return container(open: UInt8(ascii: "{"), close: UInt8(ascii: "}"), depth: depth)
            case UInt8(ascii: "["): return container(open: UInt8(ascii: "["), close: UInt8(ascii: "]"), depth: depth)
            case UInt8(ascii: "\""): return string()
            case UInt8(ascii: "t"): return literal("true")
            case UInt8(ascii: "f"): return literal("false")
            case UInt8(ascii: "n"): return literal("null")
            default: return number()
            }
        }

        private mutating func container(open: UInt8, close: UInt8, depth: Int) -> Bool {
            let isObject = open == UInt8(ascii: "{")
            position += 1
            output.append(open)
            skipWhitespace()
            guard position < bytes.count else { return false }
            if bytes[position] == close {
                position += 1
                output.append(close)
                return true
            }
            while true {
                newline(depth + 1)
                skipWhitespace()
                if isObject {
                    guard position < bytes.count, bytes[position] == UInt8(ascii: "\""), string() else { return false }
                    skipWhitespace()
                    guard position < bytes.count, bytes[position] == UInt8(ascii: ":") else { return false }
                    position += 1
                    output.append(UInt8(ascii: ":"))
                    output.append(0x20)
                    skipWhitespace()
                }
                guard value(depth: depth + 1) else { return false }
                skipWhitespace()
                guard position < bytes.count else { return false }
                if bytes[position] == UInt8(ascii: ",") {
                    position += 1
                    output.append(UInt8(ascii: ","))
                    continue
                }
                guard bytes[position] == close else { return false }
                position += 1
                newline(depth)
                output.append(close)
                return true
            }
        }

        private mutating func string() -> Bool {
            let start = position
            position += 1
            while position < bytes.count {
                let byte = bytes[position]
                if byte == UInt8(ascii: "\"") {
                    position += 1
                    output.append(contentsOf: bytes[start..<position])
                    return true
                }
                if byte < 0x20 {
                    return false
                }
                if byte == UInt8(ascii: "\\") {
                    position += 1
                    guard position < bytes.count else { return false }
                    switch bytes[position] {
                    case UInt8(ascii: "\""), UInt8(ascii: "\\"), UInt8(ascii: "/"), UInt8(ascii: "b"),
                         UInt8(ascii: "f"), UInt8(ascii: "n"), UInt8(ascii: "r"), UInt8(ascii: "t"):
                        position += 1
                    case UInt8(ascii: "u"):
                        guard position + 4 < bytes.count,
                              bytes[(position + 1)...(position + 4)].allSatisfy(Self.isHexDigit) else { return false }
                        position += 5
                    default:
                        return false
                    }
                } else {
                    position += 1
                }
            }
            return false
        }

        private static func isHexDigit(_ byte: UInt8) -> Bool {
            (0x30...0x39).contains(byte) || (0x41...0x46).contains(byte) || (0x61...0x66).contains(byte)
        }

        private mutating func literal(_ word: StaticString) -> Bool {
            let count = word.utf8CodeUnitCount
            guard position + count <= bytes.count else { return false }
            let matches = word.withUTF8Buffer { buffer in
                (0..<count).allSatisfy { bytes[position + $0] == buffer[$0] }
            }
            guard matches else { return false }
            output.append(contentsOf: bytes[position..<(position + count)])
            position += count
            return true
        }

        private mutating func number() -> Bool {
            let start = position
            func digits() -> Bool {
                let first = position
                while position < bytes.count, (0x30...0x39).contains(bytes[position]) { position += 1 }
                return position > first
            }
            if position < bytes.count, bytes[position] == UInt8(ascii: "-") { position += 1 }
            guard position < bytes.count else { return false }
            if bytes[position] == UInt8(ascii: "0") {
                position += 1
            } else if !digits() {
                return false
            }
            if position < bytes.count, bytes[position] == UInt8(ascii: ".") {
                position += 1
                guard digits() else { return false }
            }
            if position < bytes.count, bytes[position] == UInt8(ascii: "e") || bytes[position] == UInt8(ascii: "E") {
                position += 1
                if position < bytes.count, bytes[position] == UInt8(ascii: "+") || bytes[position] == UInt8(ascii: "-") {
                    position += 1
                }
                guard digits() else { return false }
            }
            output.append(contentsOf: bytes[start..<position])
            return true
        }
    }

    // MARK: - Search

    /// Case- and diacritic-insensitive match of `query` against the field name
    /// and the displayed value. An empty (trimmed) query matches every field
    /// with no ranges. NULL is searchable as "NULL"; a not-loaded value matches
    /// nothing. Returns nil when neither name nor value matches.
    static func match(_ field: SARecordField, display: SAClaudeRecordDisplayValue, query: String) -> SAClaudeRecordMatch? {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else {
            return SAClaudeRecordMatch(nameRanges: [], valueRanges: [])
        }
        let nameRanges = ranges(of: needle, in: field.name)
        let valueRanges: [NSRange]
        switch display {
        case .null: valueRanges = ranges(of: needle, in: "NULL")
        case .notLoaded: valueRanges = []
        case .text(let text): valueRanges = ranges(of: needle, in: text)
        }
        guard !nameRanges.isEmpty || !valueRanges.isEmpty else {
            return nil
        }
        return SAClaudeRecordMatch(nameRanges: nameRanges, valueRanges: valueRanges)
    }

    private static func ranges(of needle: String, in haystack: String) -> [NSRange] {
        let text = haystack as NSString
        var found: [NSRange] = []
        var searchRange = NSRange(location: 0, length: text.length)
        while searchRange.length > 0 {
            let hit = text.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive], range: searchRange)
            guard hit.location != NSNotFound, hit.length > 0 else {
                break
            }
            found.append(hit)
            let next = hit.location + hit.length
            searchRange = NSRange(location: next, length: text.length - next)
        }
        return found
    }

    /// The fields to show for a search: those that match, plus the field being
    /// edited wherever it sits, in original order.
    static func visibleFields(_ fields: [SARecordField], query: String, editingFieldID: Int?) -> [SARecordField] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return fields
        }
        return fields.filter { field in
            field.id == editingFieldID
                || match(field, display: displayValue(field), query: query) != nil
        }
    }

    static func matchCountText(_ count: Int) -> String {
        if count == 1 {
            return NSLocalizedString("ClaudeRecordMatchOne", value: "1 match", comment: "Record View: count shown in the search field when exactly one field matches")
        }
        let format = NSLocalizedString("ClaudeRecordMatchMany", value: "%d matches", comment: "Record View: count shown in the search field; %d is the number of matching fields")
        return String(format: format, count)
    }

    // MARK: - Collapse

    /// 0-based index of the line containing UTF-16 offset `location` (the
    /// number of newlines before it). Out-of-range offsets are clamped.
    static func lineIndex(of location: Int, in text: String) -> Int {
        let utf16 = text.utf16
        let end = utf16.index(utf16.startIndex, offsetBy: max(0, min(location, utf16.count)))
        var lines = 0
        for unit in utf16[utf16.startIndex..<end] where unit == 0x0A {
            lines += 1
        }
        return lines
    }

    static func isCollapsed(lineCount: Int, expanded: Bool, matchStartsBelowLimit: Bool) -> Bool {
        lineCount > collapsedLineLimit && !expanded && !matchStartsBelowLimit
    }

    // MARK: - Row stepping and state

    /// Whether the previous / next row buttons are enabled. `index` is the
    /// 0-based position of the shown row; never wraps.
    static func rowStep(index: Int, count: Int) -> (previous: Bool, next: Bool) {
        guard count > 0, index >= 0, index < count else {
            return (false, false)
        }
        return (index > 0, index < count - 1)
    }

    /// Expansions belong to a row: the same key keeps them, another row drops them.
    static func carry(_ state: SAClaudeRecordPanelState, toRowKey rowKey: String) -> SAClaudeRecordPanelState {
        state.rowKey == rowKey
            ? state
            : SAClaudeRecordPanelState(rowKey: rowKey, expandedFieldIDs: [])
    }
}
