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

    /// Replace ordinary MySQL comments with a single space while preserving
    /// executable comment bodies. With server context, version and MariaDB
    /// gates are applied before preserving a body. Comments are replaced so
    /// adjacent tokens stay separated, e.g. `SELECT/*c*/1` becomes `SELECT 1`.
    /// The `--` form follows MySQL's whitespace/control rule, and comment
    /// markers inside strings or quoted identifiers are preserved.
    static func stripSQLComments(
        _ source: String,
        serverVersion: Int? = nil,
        serverIsMariaDB: Bool = false
    ) -> String {
        let characters: [Character] = source.map { $0 }
        var result = ""
        var index = 0
        var quote: Character?

        while index < characters.count {
            let character = characters[index]

            if let activeQuote = quote {
                result.append(character)

                if character == "\\", activeQuote != "`", activeQuote != "]", index + 1 < characters.count {
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

            if serverIsMariaDB, character == "[" {
                quote = "]"
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
                var executableContentStart: Int?
                var isMariaDBOnlyComment = false
                if index + 2 < characters.count, characters[index + 2] == "!" {
                    executableContentStart = index + 3
                } else if index + 3 < characters.count,
                          (characters[index + 2] == "M" || characters[index + 2] == "m"),
                          characters[index + 3] == "!" {
                    executableContentStart = index + 4
                    isMariaDBOnlyComment = true
                }

                var closingIndex = index + 2
                while closingIndex + 1 < characters.count,
                      !(characters[closingIndex] == "*" && characters[closingIndex + 1] == "/") {
                    closingIndex += 1
                }
                let hasClosingMarker = closingIndex + 1 < characters.count
                let contentEnd = hasClosingMarker ? closingIndex : characters.count

                result.append(" ")
                if var contentStart = executableContentStart {
                    let versionStart = contentStart
                    while contentStart < contentEnd, isASCIIDigit(characters[contentStart]) {
                        contentStart += 1
                    }
                    let hasVersionGate = contentStart > versionStart
                    let requiredVersion = hasVersionGate
                        ? Int(String(characters[versionStart..<contentStart]))
                        : nil
                    if shouldPreserveExecutableComment(
                        requiredVersion: requiredVersion,
                        hasVersionGate: hasVersionGate,
                        isMariaDBOnlyComment: isMariaDBOnlyComment,
                        serverVersion: serverVersion,
                        serverIsMariaDB: serverIsMariaDB
                    ), contentStart < contentEnd {
                        result.append(stripSQLComments(
                            String(characters[contentStart..<contentEnd]),
                            serverVersion: serverVersion,
                            serverIsMariaDB: serverIsMariaDB
                        ))
                    }
                    result.append(" ")
                }

                index = hasClosingMarker ? closingIndex + 2 : characters.count
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

    private static func isASCIIDigit(_ character: Character) -> Bool {
        character.unicodeScalars.count == 1 && character.unicodeScalars.allSatisfy { (48...57).contains($0.value) }
    }

    private static func shouldPreserveExecutableComment(
        requiredVersion: Int?,
        hasVersionGate: Bool,
        isMariaDBOnlyComment: Bool,
        serverVersion: Int?,
        serverIsMariaDB: Bool
    ) -> Bool {
        // Without connection context, inspect every executable body so safety
        // classification remains conservative.
        guard let serverVersion else { return true }
        if isMariaDBOnlyComment && !serverIsMariaDB { return false }
        if hasVersionGate && requiredVersion == nil { return false }
        if let requiredVersion, requiredVersion > serverVersion { return false }

        // MariaDB intentionally ignores MySQL 5.7+ version-gated comments in
        // this range; /*M! ... */ remains available for MariaDB-specific SQL.
        if serverIsMariaDB,
           !isMariaDBOnlyComment,
           let requiredVersion,
           (50_700...99_999).contains(requiredVersion) {
            return false
        }
        return true
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

    private static let identifierPattern = #"(`(?:``|[^`])*`|"(?:""|[^"])*"|\[(?:\]\]|[^\]])*\]|[^\s;]+)"#
    private static let useRegex = makeRegex(
        pattern: "(?is)^\\s*USE\\s+\(identifierPattern)\\s*;?\\s*$"
    )
    private static let dropDatabaseRegex = makeRegex(
        pattern: "(?is)^\\s*DROP\\s+(?:DATABASE|SCHEMA)\\s+(?:IF\\s+EXISTS\\s+)?\(identifierPattern)\\s*;?\\s*$"
    )

    @objc(databaseNameChangedFrom:to:)
    static func databaseNameChanged(from currentDatabase: String?, to updatedDatabase: String?) -> Bool {
        currentDatabase != updatedDatabase
    }

    @objc(databaseNameAfterSuccessfulQuery:currentDatabase:databaseNamesAreCaseSensitive:serverVersion:serverIsMariaDB:)
    static func databaseName(
        afterSuccessfulQuery query: String,
        currentDatabase: String?,
        databaseNamesAreCaseSensitive: Bool,
        serverVersion: Int,
        serverIsMariaDB: Bool
    ) -> String? {
        let queryWithoutComments = SPCustomQuerySQLClassifier.stripSQLComments(
            query,
            serverVersion: serverVersion,
            serverIsMariaDB: serverIsMariaDB
        )

        if let selectedDatabase = databaseName(matchedBy: useRegex, in: queryWithoutComments) {
            return selectedDatabase
        }

        if let droppedDatabase = databaseName(matchedBy: dropDatabaseRegex, in: queryWithoutComments),
           let currentDatabase {
            let namesMatch = droppedDatabase == currentDatabase
                || (!databaseNamesAreCaseSensitive && droppedDatabase.caseInsensitiveCompare(currentDatabase) == .orderedSame)
            if namesMatch {
                return nil
            }
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
        guard identifier.count >= 2 else { return identifier }

        if identifier.hasPrefix("`"), identifier.hasSuffix("`") {
            return String(identifier.dropFirst().dropLast()).replacingOccurrences(of: "``", with: "`")
        }

        if identifier.hasPrefix("\""), identifier.hasSuffix("\"") {
            return String(identifier.dropFirst().dropLast()).replacingOccurrences(of: "\"\"", with: "\"")
        }

        if identifier.hasPrefix("["), identifier.hasSuffix("]") {
            return String(identifier.dropFirst().dropLast()).replacingOccurrences(of: "]]", with: "]")
        }

        return identifier
    }

    private static func makeRegex(pattern: String) -> NSRegularExpression {
        do {
            return try NSRegularExpression(pattern: pattern)
        } catch {
            preconditionFailure("Invalid SQL database-context regular expression '\(pattern)': \(error)")
        }
    }
}
