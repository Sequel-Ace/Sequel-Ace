//
//  SPCustomQuery+Explain.swift
//  Sequel Ace
//
//  Swift extension implementing the "Explain Current Query" action and the
//  SELECT/WITH classifier used by the destructive-SQL safe list and the menu
//  validation in SPCustomQuery.m. Implements upstream issue #2291.
//

import AppKit

extension SPCustomQuery {

    // MARK: - Classifier

    /// Returns `true` when the supplied query is a single SELECT or WITH
    /// statement that can be passed to MySQL's EXPLAIN. Strips MySQL comments
    /// (`--`, `#`, `/* */`), unwraps a leading parenthesised group so
    /// `(SELECT ...)` passes while `(EXPLAIN ...)` or `(UPDATE ...)` is
    /// rejected, then enforces a non-identifier boundary after SELECT/WITH so
    /// `SELECTOR_TABLE` or `WITHOUT VALIDATION` do not match while `SELECT(1)`
    /// or `SELECT/*c*/1` do.
    @objc(isQueryExplainable:)
    public static func isQueryExplainable(_ query: String?) -> Bool {
        guard let query = query, !query.isEmpty else { return false }

        // Replace comments with a single space so `SELECT/*c*/1` doesn't
        // collapse to `SELECT1` and fail the keyword boundary check below.
        let stripped = Self.stripSQLComments(query)
        var trimmed = stripped.trimmingCharacters(in: .whitespacesAndNewlines)

        // Unwrap leading parentheses so `(SELECT ...)` passes while
        // `(EXPLAIN ...)` / `(UPDATE ...)` is rejected.
        while trimmed.hasPrefix("(") {
            trimmed = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !trimmed.isEmpty else { return false }

        let upper = trimmed.uppercased()

        // Identifier characters block keyword boundary; anything else
        // (whitespace, punctuation like `(`, end-of-string) is treated as a
        // valid token end so `SELECT(1)` matches.
        var identifierSet = CharacterSet.alphanumerics
        identifierSet.insert(charactersIn: "_")

        for prefix in ["SELECT", "WITH"] {
            guard upper.hasPrefix(prefix) else { continue }
            // Bare `SELECT` / `WITH` with nothing after the keyword is not
            // valid SQL; reject so the manual Explain path surfaces the
            // localized unsupported-statement message instead of forwarding
            // `EXPLAIN SELECT` to the server and getting a syntax error.
            if upper.count == prefix.count { return false }
            let boundaryIndex = upper.index(upper.startIndex, offsetBy: prefix.count)
            let boundaryScalar = upper.unicodeScalars[boundaryIndex.samePosition(in: upper.unicodeScalars)!]
            if !identifierSet.contains(boundaryScalar) { return true }
        }
        return false
    }

    /// Replace every MySQL comment with a single space. Comments are replaced
    /// (not removed) so adjacent tokens stay separated, e.g. `SELECT/*c*/1`
    /// becomes `SELECT 1` rather than `SELECT1`.
    private static func stripSQLComments(_ source: String) -> String {
        var result = source
        let opts: NSString.CompareOptions = [.regularExpression]
        result = result.replacingOccurrences(of: "--[^\n]*", with: " ", options: opts)
        result = result.replacingOccurrences(of: "#[^\n]*", with: " ", options: opts)
        result = result.replacingOccurrences(of: "/\\*(.|\n)*?\\*/", with: " ", options: opts)
        return result
    }

    // MARK: - IBAction

    /// Run EXPLAIN on the current query (or the selected text). Triggered by
    /// the Query editor's "Explain Current Query" menu item / pulldown action.
    /// The EXPLAIN output replaces the Result table just like any other query
    /// result.
    @IBAction
    @objc(runExplainQueryAction:)
    public func runExplainQueryAction(_ sender: Any?) {
        if tableDocumentInstance?.isWorking() == true { return }
        if NSApp.currentEvent?.type == .keyUp { return }

        guard let editor = textView else {
            NSSound.beep()
            return
        }

        let editorString = editor.string as NSString
        let selectedRange = editor.selectedRange()

        let queryToExplain: String?
        if selectedRange.length == 0 {
            let range = currentQueryRange
            if range.length == 0 || editorString.length < range.length {
                NSSound.beep()
                NSLog("runExplainQueryAction: no query under caret")
                return
            }
            let raw = editorString.safeSubstring(with: range) ?? ""
            queryToExplain = SPSQLParser.normaliseQuery(forExecution: raw)
        } else {
            // Selected text may contain multiple statements separated by ';' —
            // EXPLAIN does not support multi-statement input, so split delimiter-
            // aware and reject when >1 non-empty. Comment-only fragments are
            // ignored so `SELECT 1; -- foo` counts as a single statement.
            let selectionText = editorString.safeSubstring(with: selectedRange) ?? ""
            let parser = SPSQLParser(string: selectionText)
            parser.setDelimiterSupport(true)
            let semicolon = UInt16(UnicodeScalar(";").value)
            let parts = (parser.splitString(byCharacter: semicolon) as? [String]) ?? []

            var nonEmpty: [String] = []
            for part in parts {
                let probe = Self.stripSQLComments(part)
                if probe.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
                nonEmpty.append(part.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            if nonEmpty.count != 1 {
                reportUnsupportedExplain()
                return
            }
            queryToExplain = SPSQLParser.normaliseQuery(forExecution: nonEmpty[0])
        }

        guard let query = queryToExplain, SPCustomQuery.isQueryExplainable(query) else {
            reportUnsupportedExplain()
            return
        }

        isDesc = false
        sortColumn = nil
        sortCount?.removeAllObjects()
        reloadingExistingResult = false
        clearResultViewDetailsToRestore()

        performQueries(["EXPLAIN \(query)"], withCallback: nil)
    }

    private func reportUnsupportedExplain() {
        NSSound.beep()
        errorTextTitle?.stringValue = NSLocalizedString("Query Status", comment: "Query Status")
        let message = NSLocalizedString("EXPLAIN is only supported for a single SELECT or WITH statement.", comment: "EXPLAIN unsupported statement message")
        if let target = errorText as? NSObject {
            target.setValue(message, forKey: "string")
        }
    }
}
