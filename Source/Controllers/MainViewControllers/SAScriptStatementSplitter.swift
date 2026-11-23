//
//  SAScriptStatementSplitter.swift
//  Sequel Ace
//
//  Splits the text of a "Run All as Script" run into executable statements.
//  App-target only: it uses the project's Objective-C SPSQLParser, so it is
//  kept apart from SAScriptRunner, which also builds in the Unit Tests target.
//

import Foundation

enum SAScriptStatementSplitter {

    /// Split `sql` into executable statements, honouring `DELIMITER`
    /// commands, quoted strings and comments the same way Run All does.
    static func statements(in sql: String) -> [SAScriptStatement] {
        let text = sql as NSString
        let parser = SPSQLParser(string: sql)
        parser.setDelimiterSupport(true)
        let semicolon = UInt16(UnicodeScalar(";").value)
        let ranges = (parser.splitStringIntoRanges(byCharacter: semicolon) as? [NSValue]) ?? []

        // Carry the previous statement's (offset, line) forward so line numbers
        // cost one pass over the text rather than one pass per statement. Each
        // carried offset is a non-whitespace character, so never inside a CRLF.
        var lastOffset = 0
        var lastLine = 1
        return ranges.compactMap { value in
            let range = NSIntersectionRange(value.rangeValue, NSRange(location: 0, length: text.length))
            let raw = text.substring(with: range)
            guard !SAScriptStatementLocator.isEmptyStatement(raw) else { return nil }
            let start = SAScriptStatementLocator.firstNonWhitespaceOffset(in: range, of: text)
            let line = SAScriptStatementLocator.lineNumber(ofOffset: start, in: text, from: lastOffset, startLine: lastLine)
            lastOffset = start
            lastLine = line
            let normalised = SPSQLParser.normaliseQuery(forExecution: raw)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return SAScriptStatement(text: normalised, line: line)
        }
    }
}
