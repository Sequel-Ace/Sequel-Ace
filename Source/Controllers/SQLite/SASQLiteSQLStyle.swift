import Foundation
import SQLite3

enum SASQLiteSQLStyle {
    enum Kind: Hashable {
        case keyword, string, identifier, number, parameter, lineComment, blockComment, whitespace, symbol, word
    }

    struct Token: Equatable {
        let kind: Kind
        let text: String
        let range: NSRange
    }

    static func tokens(in sql: String) -> [Token] {
        let units = Array(sql.utf16)
        let text = sql as NSString
        var position = 0
        var tokens: [Token] = []

        func at(_ offset: Int = 0) -> UInt16? {
            let index = position + offset
            return index < units.count ? units[index] : nil
        }

        func advance(while predicate: (UInt16) -> Bool) {
            while let unit = at(), predicate(unit) { position += 1 }
        }

        func quoted(_ quote: UInt16, doubled: Bool) {
            position += 1
            while let unit = at() {
                position += 1
                if unit == quote {
                    if doubled, at() == quote { position += 1 } else { return }
                }
            }
        }

        while let first = at() {
            let start = position
            var kind: Kind
            switch first {
            case 9...13, 32:
                advance { (9...13).contains($0) || $0 == 32 }
                kind = .whitespace
            case 45 where at(1) == 45:
                advance { $0 != 10 }
                kind = .lineComment
            case 47 where at(1) == 42:
                position += 2
                while let unit = at() {
                    position += 1
                    if unit == 42, at() == 47 {
                        position += 1
                        break
                    }
                }
                kind = .blockComment
            case 39:
                quoted(39, doubled: true)
                kind = .string
            case 34, 96:
                quoted(first, doubled: true)
                kind = .identifier
            case 91:
                quoted(93, doubled: false)
                kind = .identifier
            case 88 where at(1) == 39, 120 where at(1) == 39:
                position += 1
                quoted(39, doubled: true)
                kind = .string
            case 63:
                position += 1
                advance(while: isDigit)
                kind = .parameter
            case 36, 58, 64:
                position += 1
                let nameStart = position
                advance(while: isWord)
                if first == 36 {
                    while at() == 58, at(1) == 58 {
                        position += 2
                        advance(while: isWord)
                    }
                    if position > nameStart, at() == 40 {
                        position += 1
                        advance { $0 != 41 && !((9...13).contains($0) || $0 == 32) }
                        if at() == 41 { position += 1 }
                    }
                }
                kind = position > nameStart ? .parameter : .symbol
            default:
                if isDigit(first) || first == 46 && at(1).map(isDigit) == true {
                    if first == 48, at(1) == 120 || at(1) == 88 {
                        position += 2
                        advance { isDigit($0) || (65...70).contains($0) || (97...102).contains($0) || $0 == 95 }
                    } else {
                        advance { isDigit($0) || $0 == 95 }
                        if at() == 46 {
                            position += 1
                            advance { isDigit($0) || $0 == 95 }
                        }
                        if at() == 101 || at() == 69 {
                            let signOffset = at(1) == 43 || at(1) == 45 ? 2 : 1
                            if at(signOffset).map(isDigit) == true {
                                position += signOffset
                                advance { isDigit($0) || $0 == 95 }
                            }
                        }
                    }
                    // SQLite treats a number immediately followed by an identifier as an invalid token.
                    // Keep that token intact instead of formatting it into a different statement.
                    let numberEnd = position
                    advance(while: isWord)
                    kind = position == numberEnd ? .number : .word
                } else if isWord(first) {
                    advance(while: isWord)
                    kind = .word
                } else {
                    position += 1
                    kind = .symbol
                }
            }
            let range = NSRange(location: start, length: position - start)
            let value = text.substring(with: range)
            if kind == .word, value.utf8.allSatisfy({ $0 < 128 }),
               value.withCString({ sqlite3_keyword_check($0, Int32(value.utf8.count)) == 1 }) {
                kind = .keyword
            }
            tokens.append(Token(kind: kind, text: value, range: range))
        }
        return tokens
    }

    static func currentStatement(in sql: String, at position: Int, tokens: [Token]? = nil) -> NSRange? {
        let text = sql as NSString
        let tokens = tokens ?? Self.tokens(in: sql)
        var start = 0
        var previous: NSRange?
        for token in tokens where token.kind == .symbol && token.text == ";" {
            let end = NSMaxRange(token.range)
            let candidate = NSRange(location: start, length: end - start)
            if sqlite3_complete(text.substring(with: candidate)) == 1 {
                if position <= end { return candidate }
                previous = candidate
                start = end
            }
        }
        let remainder = NSRange(location: start, length: text.length - start)
        if !text.substring(with: remainder).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return remainder }
        return previous
    }

    static func format(_ sql: String) -> String {
        let tokens = tokens(in: sql)
        var output = ""
        var pendingSpace = ""
        var previous: Token?
        var depth = 0
        for token in tokens {
            if token.kind == .whitespace {
                pendingSpace += token.text
                continue
            }
            let value = token.kind == .keyword ? token.text.uppercased() : token.text
            let prior = previous?.text.uppercased()
            if token.kind == .symbol, token.text == ")" { depth = max(0, depth - 1) }

            if previous == nil {
                output += pendingSpace
            } else if previous?.kind == .lineComment || prior == ";" ||
                        (!pendingSpace.isEmpty && token.kind == .keyword && startsClause(value, after: prior)) {
                output += "\n" + String(repeating: "  ", count: min(depth, 20))
            } else if !pendingSpace.isEmpty {
                output += " "
            }
            output += value
            if token.kind == .symbol, token.text == "(" { depth += 1 }
            pendingSpace = ""
            previous = token
        }
        return output + pendingSpace
    }

    private static func startsClause(_ keyword: String, after previous: String?) -> Bool {
        guard previous != ".", previous != "(" else { return false }
        switch keyword {
        case "SELECT":
            return previous != "UNION" && previous != "ALL"
        case "UPDATE":
            return previous != "DO" && previous != "ON" && previous != "AFTER" && previous != "BEFORE"
        case "JOIN":
            return !["LEFT", "RIGHT", "FULL", "INNER", "OUTER", "CROSS", "NATURAL"].contains(previous)
        case "FROM", "WHERE", "GROUP", "HAVING", "ORDER", "LIMIT", "RETURNING",
             "VALUES", "SET", "UNION", "INTERSECT", "EXCEPT", "WINDOW",
             "LEFT", "RIGHT", "FULL", "INNER", "CROSS", "NATURAL":
            return true
        default:
            return false
        }
    }

    private static func isDigit(_ value: UInt16) -> Bool { (48...57).contains(value) }

    private static func isWord(_ value: UInt16) -> Bool {
        isDigit(value) || (65...90).contains(value) || (97...122).contains(value) ||
            value == 95 || value == 36 || value >= 128
    }
}
