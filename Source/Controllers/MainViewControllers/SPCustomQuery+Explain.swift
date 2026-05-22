//
//  SPCustomQuery+Explain.swift
//  Sequel Ace
//
//  Swift extension implementing the "Explain Current Query" action and the
//  SQL classifiers used by the destructive-SQL safe gate and the menu
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
        return SPCustomQuerySQLClassifier.isQueryExplainable(query)
    }

    /// Returns `true` when the destructive-SQL warning may be skipped for this query.
    @objc(isQuerySafeWithoutDestructiveWarning:)
    public static func isQuerySafeWithoutDestructiveWarning(_ query: String?) -> Bool {
        return SPCustomQuerySQLClassifier.isQuerySafeWithoutDestructiveWarning(query)
    }

    // MARK: - IBAction

    /// Run EXPLAIN on the current query (or the selected text). Triggered by
    /// the Query editor's "Explain Current Query" menu item / pulldown action.
    /// The EXPLAIN output replaces the Result table just like any other query
    /// result.
    @IBAction
    @objc(runExplainQueryAction:)
    public func runExplainQueryAction(_ sender: Any?) {
        // Prevent multiple runs by holding the keys down
        if tableDocumentInstance?.isWorking() == true { return }

        // Fixes bug in key equivalents (mirrors -runAllQueries: guard).
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
                let probe = SPCustomQuerySQLClassifier.stripSQLComments(part)
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

    /// Surface the localized "EXPLAIN is only supported for a single SELECT
    /// or WITH statement" message via the Query Status controls and emit a
    /// system beep, used as the failure path when the input is not
    /// EXPLAIN-eligible (non-SELECT/WITH or multi-statement selection).
    private func reportUnsupportedExplain() {
        NSSound.beep()
        errorTextTitle?.stringValue = NSLocalizedString("Query Status", comment: "Query Status")
        let message = NSLocalizedString("EXPLAIN is only supported for a single SELECT or WITH statement.", comment: "EXPLAIN unsupported statement message")
        // errorText is wired in DBView.xib as an NSTextView (NSText subclass);
        // mirrors the [errorText setString:...] pattern used throughout SPCustomQuery.m.
        (errorText as? NSText)?.string = message
    }
}
