//
//  SAClaudeQueryInsertion.swift
//  Sequel Ace
//
//  Where a query picked from the History or Favorites menu goes in insert mode,
//  and the newlines around it, so it always sits on its own line. Shared with
//  the unit tests.
//

import Foundation

/// A query picked from the History or Favorites menu, ready to insert into the custom query editor (insert mode).
///
/// It replaces the selection, or goes at the end of the text when nothing is selected (a bare caret doesn't choose
/// the place). It always starts a line: a newline goes first unless it is at the start of the text or after a
/// newline. Text after it on the same line moves to the next line: a newline goes after it.
@objc(SAClaudeQueryInsertion) final class SAClaudeQueryInsertion: NSObject {
    /// The string to insert: the query with any newline it needs before and after it.
    @objc let text: String
    /// The range of the editor's text that `text` replaces, in UTF-16 units.
    @objc let range: NSRange
    /// Characters of `text` after the query (0 or 1, the added newline): the caret goes before them.
    @objc let trailingNewlineLength: Int

    private init(text: String, range: NSRange, trailingNewlineLength: Int) {
        self.text = text
        self.range = range
        self.trailingNewlineLength = trailingNewlineLength
    }

    @objc(insertionOfQuery:intoText:selectedRange:)
    static func insertion(of query: String, into text: String, selectedRange: NSRange) -> SAClaudeQueryInsertion {
        let editor = text as NSString
        let length = editor.length
        var range = NSRange(location: length, length: 0)
        if selectedRange.location != NSNotFound, selectedRange.length > 0, selectedRange.location < length {
            range = NSRange(location: selectedRange.location, length: min(selectedRange.length, length - selectedRange.location))
        }

        let picked = query as NSString
        guard picked.length > 0 else { return SAClaudeQueryInsertion(text: "", range: range, trailingNewlineLength: 0) }

        let newlines = CharacterSet.newlines as NSCharacterSet
        func isNewline(_ string: NSString, at index: Int) -> Bool { newlines.characterIsMember(string.character(at: index)) }

        let needsLeading = range.location > 0 && !isNewline(editor, at: range.location - 1) && !isNewline(picked, at: 0)
        let end = NSMaxRange(range)
        let needsTrailing = end < length && !isNewline(editor, at: end) && !isNewline(picked, at: picked.length - 1)

        let insert = (needsLeading ? "\n" : "") + query + (needsTrailing ? "\n" : "")
        return SAClaudeQueryInsertion(text: insert, range: range, trailingNewlineLength: needsTrailing ? 1 : 0)
    }
}
