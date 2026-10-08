//
//  SAScriptStatementLocator.swift
//  Sequel Ace
//
//  Pure helpers used by SAScriptStatementSplitter to report mysql-style
//  "at line N" positions and to skip statements that are only comments.
//  Kept free of project ObjC types so it can live in the Unit Tests target.
//

import Foundation

enum SAScriptStatementLocator {

    /// 1-based line number of `offset` in `text`. `\n`, `\r\n` and a lone
    /// `\r` each count as one line break. Offsets past the end are clamped.
    static func lineNumber(ofOffset offset: Int, in text: NSString) -> Int {
        let end = min(max(offset, 0), text.length)
        var line = 1
        var index = 0
        while index < end {
            let character = text.character(at: index)
            if character == 0x0A {
                line += 1
            } else if character == 0x0D {
                line += 1
                if index + 1 < end && text.character(at: index + 1) == 0x0A {
                    index += 1
                }
            }
            index += 1
        }
        return line
    }

    /// Offset of the first non-whitespace, non-newline character in `range`,
    /// or `range.location` when the range is blank.
    static func firstNonWhitespaceOffset(in range: NSRange, of text: NSString) -> Int {
        let nonWhitespace = CharacterSet.whitespacesAndNewlines.inverted
        let found = text.rangeOfCharacter(from: nonWhitespace, options: [], range: range)
        return found.location == NSNotFound ? range.location : found.location
    }

    /// `true` when the statement has nothing left to run once comments and
    /// whitespace are removed (mysql skips such input silently).
    static func isEmptyStatement(_ statement: String) -> Bool {
        SPCustomQuerySQLClassifier.stripSQLComments(statement)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }
}
