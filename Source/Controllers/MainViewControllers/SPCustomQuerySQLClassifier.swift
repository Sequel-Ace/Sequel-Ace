//
//  SPCustomQuerySQLClassifier.swift
//  Sequel Ace
//
//  SQL prefix classifiers shared by the custom query warning gate and the
//  "Explain Current Query" action.
//

import Foundation

enum SPCustomQuerySQLClassifier {

    private static let mutatingExplainAnalyzeStatements: Set<String> = [
        "UPDATE",
        "DELETE",
        "INSERT",
        "REPLACE"
    ]

    private static var identifierSet: CharacterSet {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "_")
        return set
    }

    static func isQueryExplainable(_ query: String?) -> Bool {
        guard let query = query, !query.isEmpty else { return false }

        var trimmed = stripSQLComments(query).trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasPrefix("(") {
            trimmed = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !trimmed.isEmpty else { return false }

        let upper = trimmed.uppercased()
        return ["SELECT", "WITH"].contains { hasLeadingSQLKeyword($0, in: upper, allowBare: false) }
    }

    static func isQuerySafeWithoutDestructiveWarning(_ query: String?) -> Bool {
        guard let query = query, !query.isEmpty else { return false }

        var trimmed = stripSQLComments(query).trimmingCharacters(in: .whitespacesAndNewlines)
        // Unwrap leading parentheses so `(SELECT ...)` is treated the same as
        // `SELECT ...`, matching isQueryExplainable's behaviour.
        while trimmed.hasPrefix("(") {
            trimmed = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !trimmed.isEmpty else { return false }

        let upper = trimmed.uppercased()
        if hasLeadingSQLKeyword("SHOW", in: upper) { return true }
        if hasLeadingSQLKeyword("SELECT", in: upper) { return true }

        for explainAlias in ["EXPLAIN", "DESCRIBE", "DESC"] {
            if hasLeadingSQLKeyword(explainAlias, in: upper) {
                return isExplainAliasSafeWithoutWarning(upper, alias: explainAlias)
            }
        }

        return false
    }

    /// Replace every MySQL comment with a single space. Comments are replaced
    /// so adjacent tokens stay separated, e.g. `SELECT/*c*/1` becomes
    /// `SELECT 1` rather than `SELECT1`. The `--` form follows MySQL's rule
    /// that the second dash must be followed by whitespace/control to count
    /// as a comment, so `SELECT--1` is left intact as double negation.
    static func stripSQLComments(_ source: String) -> String {
        var result = source
        let opts: NSString.CompareOptions = [.regularExpression]
        result = result.replacingOccurrences(of: "--[\\s][^\n]*", with: " ", options: opts)
        result = result.replacingOccurrences(of: "#[^\n]*", with: " ", options: opts)
        result = result.replacingOccurrences(of: "/\\*(.|\n)*?\\*/", with: " ", options: opts)
        return result
    }

    private static func hasLeadingSQLKeyword(_ keyword: String, in upper: String, allowBare: Bool = true) -> Bool {
        guard upper.hasPrefix(keyword) else { return false }
        if upper.count == keyword.count { return allowBare }

        let boundaryIndex = upper.index(upper.startIndex, offsetBy: keyword.count)
        guard let scalarIndex = boundaryIndex.samePosition(in: upper.unicodeScalars) else { return false }
        return !identifierSet.contains(upper.unicodeScalars[scalarIndex])
    }

    private static func isExplainAliasSafeWithoutWarning(_ upper: String, alias: String) -> Bool {
        let tokens = sqlTokens(from: upper)
        guard tokens.first == alias else { return false }

        var index = 1
        skipExplainModifiers(in: tokens, from: &index)

        guard index < tokens.count, tokens[index] == "ANALYZE" else {
            return true
        }

        index += 1
        skipExplainModifiers(in: tokens, from: &index)
        guard index < tokens.count else { return false }

        // `WITH` can introduce UPDATE/DELETE in MySQL CTE syntax; parsing past
        // the CTE list to find the outer verb requires a real SQL parser, so
        // conservatively require the destructive warning for any
        // `EXPLAIN ANALYZE WITH ...` (the read-only CTE SELECT false positive
        // is acceptable; silently running UPDATE/DELETE without warning is not).
        if tokens[index] == "WITH" { return false }

        return !mutatingExplainAnalyzeStatements.contains(tokens[index])
    }

    private static func sqlTokens(from upper: String) -> [String] {
        upper
            .replacingOccurrences(of: "=", with: " = ")
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
    }

    private static func skipExplainModifiers(in tokens: [String], from index: inout Int) {
        // `sqlTokens` already wraps every `=` with whitespace, so `FORMAT=JSON`
        // is always tokenized as `[FORMAT, =, JSON]`. The `FORMAT` case below
        // handles both `FORMAT JSON` and `FORMAT = JSON`.
        while index < tokens.count {
            switch tokens[index] {
            case "EXTENDED", "PARTITIONS":
                index += 1
            case "FORMAT":
                index += 1
                if index < tokens.count, tokens[index] == "=" {
                    index += 1
                }
                if index < tokens.count {
                    index += 1
                }
            default:
                return
            }
        }
    }
}
