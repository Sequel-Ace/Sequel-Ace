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
    /// as a comment, so `SELECT--1` is left intact as double negation. Comment
    /// markers inside strings or quoted identifiers are preserved.
    static func stripSQLComments(_ source: String) -> String {
        let characters: [Character] = source.map { $0 }
        var result = ""
        var index = 0
        var quote: Character?

        while index < characters.count {
            let character = characters[index]

            if let activeQuote = quote {
                result.append(character)

                if character == "\\", activeQuote != "`", index + 1 < characters.count {
                    index += 1
                    result.append(characters[index])
                } else if character == activeQuote {
                    if index + 1 < characters.count, characters[index + 1] == activeQuote {
                        index += 1
                        result.append(characters[index])
                    } else {
                        quote = nil
                    }
                }

                index += 1
                continue
            }

            if character == "'" || character == "\"" || character == "`" {
                quote = character
                result.append(character)
                index += 1
                continue
            }

            if character == "#" {
                result.append(" ")
                index += 1
                while index < characters.count, characters[index] != "\n" {
                    index += 1
                }
                continue
            }

            if character == "-",
               index + 2 < characters.count,
               characters[index + 1] == "-",
               isMySQLCommentWhitespace(characters[index + 2]) {
                result.append(" ")
                index += 2
                while index < characters.count, characters[index] != "\n" {
                    index += 1
                }
                continue
            }

            if character == "/", index + 1 < characters.count, characters[index + 1] == "*" {
                result.append(" ")
                index += 2
                while index < characters.count {
                    if characters[index] == "*", index + 1 < characters.count, characters[index + 1] == "/" {
                        index += 2
                        break
                    }
                    index += 1
                }
                continue
            }

            result.append(character)
            index += 1
        }

        return result
    }

    private static func isMySQLCommentWhitespace(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { $0.value <= 0x20 }
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

@objc final class SASQLDatabaseContext: NSObject {

    private static let identifierPattern = "(`(?:``|[^`])*`|[^\\s;]+)"
    private static let useRegex = try! NSRegularExpression(
        pattern: "(?is)^\\s*USE\\s+\(identifierPattern)\\s*;?\\s*$"
    )
    private static let dropDatabaseRegex = try! NSRegularExpression(
        pattern: "(?is)^\\s*DROP\\s+(?:DATABASE|SCHEMA)\\s+(?:IF\\s+EXISTS\\s+)?\(identifierPattern)\\s*;?\\s*$"
    )

    @objc(databaseNameAfterSuccessfulQuery:currentDatabase:)
    static func databaseName(afterSuccessfulQuery query: String, currentDatabase: String?) -> String? {
        let queryWithoutComments = SPCustomQuerySQLClassifier.stripSQLComments(query)

        if let selectedDatabase = databaseName(matchedBy: useRegex, in: queryWithoutComments) {
            return selectedDatabase
        }

        if let droppedDatabase = databaseName(matchedBy: dropDatabaseRegex, in: queryWithoutComments),
           droppedDatabase == currentDatabase {
            return nil
        }

        return currentDatabase
    }

    private static func databaseName(matchedBy regex: NSRegularExpression, in query: String) -> String? {
        let range = NSRange(query.startIndex..<query.endIndex, in: query)
        guard let match = regex.firstMatch(in: query, range: range),
              let captureRange = Range(match.range(at: 1), in: query) else {
            return nil
        }

        let identifier = String(query[captureRange])
        guard identifier.hasPrefix("`"), identifier.hasSuffix("`"), identifier.count >= 2 else {
            return identifier
        }

        return String(identifier.dropFirst().dropLast()).replacingOccurrences(of: "``", with: "`")
    }
}
