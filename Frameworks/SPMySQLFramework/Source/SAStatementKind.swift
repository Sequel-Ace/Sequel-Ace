//
//  SAStatementKind.swift
//  SPMySQLFramework
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import Foundation

/// What kind of statement a text is, as far as the connection's reports need to know: whether it can
/// change data on the server. That decides how a stop that landed after the statement was sent is
/// described - a read that was stopped is simply cancelled; a write may have taken effect.
@objc(SAStatementKind)
public final class SAStatementKind: NSObject {

    /// The leading keywords of statements that only read. Anything else may write - also what is
    /// not known, and a common table expression, which can lead a write.
    private static let readOnlyKeywords: Set<String> = ["SELECT", "SHOW", "DESCRIBE", "DESC", "EXPLAIN", "HELP", "USE", "CHECKSUM", "TABLE", "VALUES", "HANDLER"]

    /// The names the server's own functions and the words of SQL go by before an opening parenthesis,
    /// which a reading statement may use without writing. Anything else before a parenthesis - a stored
    /// function, qualified or quoted or not - has effects the connection cannot know.
    private static let knownBeforeAParenthesis: Set<String> = [
        "ABS", "ACOS", "ADDDATE", "ADDTIME", "AES_DECRYPT", "AES_ENCRYPT", "AGAINST", "ALL", "AND", "ANY", "ANY_VALUE", "AS",
        "ASCII", "ASIN", "ATAN", "ATAN2", "AVG", "BENCHMARK", "BETWEEN", "BIN", "BINARY", "BIN_TO_UUID", "BIT_AND", "BIT_LENGTH",
        "BIT_OR", "BIT_XOR", "BY", "CASE", "CAST", "CEIL", "CEILING", "CHAR", "CHARACTER_LENGTH", "CHARSET", "CHAR_LENGTH", "COALESCE",
        "COERCIBILITY", "COLLATION", "COMPRESS", "CONCAT", "CONCAT_WS", "CONNECTION_ID", "CONV", "CONVERT", "CONVERT_TZ", "COS", "COT", "COUNT",
        "CRC32", "CUME_DIST", "CURDATE", "CURRENT_DATE", "CURRENT_ROLE", "CURRENT_TIME", "CURRENT_TIMESTAMP", "CURRENT_USER", "CURTIME", "DATABASE", "DATE", "DATEDIFF",
        "DATETIME", "DATE_ADD", "DATE_FORMAT", "DATE_SUB", "DAY", "DAYNAME", "DAYOFMONTH", "DAYOFWEEK", "DAYOFYEAR", "DEC", "DECIMAL", "DEFAULT",
        "DEGREES", "DENSE_RANK", "DISTINCT", "DIV", "DOUBLE", "ELSE", "ELT", "END", "EXCEPT", "EXISTS", "EXP", "EXPORT_SET",
        "EXTRACT", "FIELD", "FIND_IN_SET", "FIRST_VALUE", "FLOAT", "FLOOR", "FORMAT", "FOUND_ROWS", "FROM", "FROM_BASE64", "FROM_DAYS", "FROM_UNIXTIME",
        "GET_FORMAT", "GET_LOCK", "GREATEST", "GROUP", "GROUPING", "GROUP_CONCAT", "GTID_SUBSET", "GTID_SUBTRACT", "HAVING", "HEX", "HOUR", "ICU_VERSION",
        "IF", "IFNULL", "IN", "INDEX", "INET6_ATON", "INET6_NTOA", "INET_ATON", "INET_NTOA", "INSERT", "INSTR", "INT", "INTEGER",
        "INTERSECT", "INTERVAL", "INTO", "ISNULL", "IS_FREE_LOCK", "IS_IPV4", "IS_IPV4_COMPAT", "IS_IPV4_MAPPED", "IS_IPV6", "IS_USED_LOCK", "IS_UUID", "JOIN",
        "JSON", "JSON_ARRAY", "JSON_ARRAYAGG", "JSON_ARRAY_APPEND", "JSON_ARRAY_INSERT", "JSON_CONTAINS", "JSON_CONTAINS_PATH", "JSON_DEPTH", "JSON_EXTRACT", "JSON_INSERT", "JSON_KEYS", "JSON_LENGTH",
        "JSON_MERGE", "JSON_MERGE_PATCH", "JSON_MERGE_PRESERVE", "JSON_OBJECT", "JSON_OBJECTAGG", "JSON_OVERLAPS", "JSON_PRETTY", "JSON_QUOTE", "JSON_REMOVE", "JSON_REPLACE", "JSON_SCHEMA_VALID", "JSON_SCHEMA_VALIDATION_REPORT",
        "JSON_SEARCH", "JSON_SET", "JSON_STORAGE_FREE", "JSON_STORAGE_SIZE", "JSON_TABLE", "JSON_TYPE", "JSON_UNQUOTE", "JSON_VALID", "JSON_VALUE", "KEY", "LAG", "LAST_DAY",
        "LAST_INSERT_ID", "LAST_VALUE", "LATERAL", "LCASE", "LEAD", "LEAST", "LEFT", "LENGTH", "LIKE", "LIMIT", "LN", "LOAD_FILE",
        "LOCALTIME", "LOCALTIMESTAMP", "LOCATE", "LOG", "LOG10", "LOG2", "LOWER", "LPAD", "LTRIM", "MAKEDATE", "MAKETIME", "MAKE_SET",
        "MASTER_POS_WAIT", "MATCH", "MAX", "MD5", "MEMBER", "MICROSECOND", "MID", "MIN", "MINUTE", "MOD", "MONTH", "MONTHNAME",
        "NAME_CONST", "NCHAR", "NOT", "NOW", "NTH_VALUE", "NTILE", "NULLIF", "NUMERIC", "OCT", "OCTET_LENGTH", "ON", "OR",
        "ORD", "ORDER", "OVER", "PARTITION", "PERCENT_RANK", "PERIOD_ADD", "PERIOD_DIFF", "PI", "POSITION", "POW", "POWER", "QUARTER",
        "QUOTE", "RADIANS", "RAND", "RANDOM_BYTES", "RANGE", "RANK", "REAL", "RECURSIVE", "REGEXP", "REGEXP_INSTR", "REGEXP_LIKE", "REGEXP_REPLACE",
        "REGEXP_SUBSTR", "RELEASE_ALL_LOCKS", "RELEASE_LOCK", "REPEAT", "REPLACE", "REVERSE", "RIGHT", "RLIKE", "ROLES_GRAPHML", "ROUND", "ROW", "ROWS",
        "ROW_COUNT", "ROW_NUMBER", "RPAD", "RTRIM", "SCHEMA", "SECOND", "SEC_TO_TIME", "SELECT", "SESSION_USER", "SET", "SHA", "SHA1",
        "SHA2", "SIGN", "SIGNED", "SIN", "SLEEP", "SOME", "SOUNDEX", "SOURCE_POS_WAIT", "SPACE", "SQRT", "STATEMENT_DIGEST", "STATEMENT_DIGEST_TEXT",
        "STD", "STDDEV", "STDDEV_POP", "STDDEV_SAMP", "STRCMP", "STR_TO_DATE", "SUBDATE", "SUBSTR", "SUBSTRING", "SUBSTRING_INDEX", "SUBTIME", "SUM",
        "SYSDATE", "SYSTEM_USER", "TAN", "THEN", "TIME", "TIMEDIFF", "TIMESTAMP", "TIMESTAMPADD", "TIMESTAMPDIFF", "TIME_FORMAT", "TIME_TO_SEC", "TO_BASE64",
        "TO_DAYS", "TO_SECONDS", "TRIM", "TRUNCATE", "UCASE", "UNCOMPRESS", "UNCOMPRESSED_LENGTH", "UNHEX", "UNION", "UNIX_TIMESTAMP", "UNSIGNED", "UPPER",
        "USER", "USING", "UTC_DATE", "UTC_TIME", "UTC_TIMESTAMP", "UUID", "UUID_SHORT", "UUID_TO_BIN", "VALUE", "VALUES", "VARCHAR", "VARIANCE",
        "VAR_POP", "VAR_SAMP", "VERSION", "WAIT_FOR_EXECUTED_GTID_SET", "WEEK", "WEEKDAY", "WEEKOFYEAR", "WEIGHT_STRING", "WHEN", "WHERE", "WITH", "XOR",
        "YEAR", "YEARWEEK",
    ]

    /// Whether the statement may change data on the server.
    /// - Parameter statement: The statement's text.
    /// - Returns: False only for a statement led by a keyword that only reads and calling no function
    ///   the connection does not know - a stored function called from a `SELECT` can write, so a call
    ///   of unknown effect counts as one that may.
    @objc(statementMayWrite:)
    public static func statementMayWrite(_ statement: String) -> Bool {
        guard let keyword = leadingKeyword(of: statement) else {
            return true
        }
        return !readOnlyKeywords.contains(keyword) || callsAFunctionOfUnknownEffect(statement)
    }

    /// The first word of the statement past whitespace, comments and opening parentheses, in upper
    /// case, or nil when there is none.
    /// - Parameter statement: The statement's text.
    static func leadingKeyword(of statement: String) -> String? {
        var scanner = SAStatementScanner(statement)
        scanner.skipWhitespaceCommentsAndOpeningParentheses()
        let word = scanner.readName()
        return word.isEmpty ? nil : word.uppercased()
    }

    /// Whether the statement calls a function the connection does not know - a stored function, whose
    /// effects it cannot tell. Text in string literals and comments is not read as a call; a quoted or
    /// schema-qualified name before a parenthesis is a call of something the server did not define.
    /// - Parameter statement: The statement's text.
    static func callsAFunctionOfUnknownEffect(_ statement: String) -> Bool {
        var scanner = SAStatementScanner(statement)
        var name = ""
        var nameIsQuotedOrQualified = false
        while let scalar = scanner.current {
            if scalar == "'" || scalar == "\"" {
                scanner.skipStringLiteral()
                name = ""; nameIsQuotedOrQualified = false
            } else if scalar == "`" {
                scanner.skipQuotedIdentifier()
                name = "`"; nameIsQuotedOrQualified = true
            } else if scanner.atAComment {
                scanner.skipComment()
            } else if SAStatementScanner.isNamePart(scalar) {
                name = scanner.readName()
                if scanner.current == "." {
                    // Qualified: schema.function - nothing of the server's own is.
                    scanner.advance()
                    nameIsQuotedOrQualified = true
                }
            } else if scalar == "(" {
                if !name.isEmpty, nameIsQuotedOrQualified || !knownBeforeAParenthesis.contains(name.uppercased()) {
                    return true
                }
                scanner.advance()
                name = ""; nameIsQuotedOrQualified = false
            } else if scalar.properties.isWhitespace {
                scanner.advance()
            } else {
                scanner.advance()
                name = ""; nameIsQuotedOrQualified = false
            }
        }
        return false
    }
}

/// Reads a statement's text scalar by scalar, past the parts that are not SQL: string literals,
/// quoted identifiers and comments.
struct SAStatementScanner {
    private let scalars: [Unicode.Scalar]
    private var index = 0

    /// Scans this statement from its start.
    /// - Parameter statement: The statement's text.
    init(_ statement: String) {
        scalars = Array(statement.unicodeScalars)
    }

    /// The scalar under the scanner, or nil at the end.
    var current: Unicode.Scalar? { index < scalars.count ? scalars[index] : nil }

    /// The scalar after the one under the scanner, or nil.
    private var next: Unicode.Scalar? { index + 1 < scalars.count ? scalars[index + 1] : nil }

    /// Whether the scanner is at the start of a comment: `--`, `#`, or `/*`.
    var atAComment: Bool {
        current == "#" || (current == "-" && next == "-") || (current == "/" && next == "*")
    }

    /// Whether the scalar can be part of an unquoted name.
    /// - Parameter scalar: The scalar.
    static func isNamePart(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.isAlphabetic || ("0"..."9").contains(scalar) || scalar == "_" || scalar == "$"
    }

    /// Moves past the scalar under the scanner.
    mutating func advance() {
        index += 1
    }

    /// Reads an unquoted name from the scanner's position, or nothing when there is none.
    /// - Returns: The name, as written.
    mutating func readName() -> String {
        var name = ""
        while let scalar = current, Self.isNamePart(scalar) {
            name.unicodeScalars.append(scalar)
            index += 1
        }
        return name
    }

    /// Moves past a comment the scanner is at the start of.
    mutating func skipComment() {
        if current == "/" {
            index += 2
            while index < scalars.count, !(scalars[index] == "*" && next == "/") { index += 1 }
            index += 2
        } else {
            while let scalar = current, scalar != "\n" { index += 1 }
        }
    }

    /// Moves past a string literal the scanner is at the opening quote of, with doubled or escaped
    /// quotes inside it.
    mutating func skipStringLiteral() {
        guard let quote = current else { return }
        index += 1
        while let scalar = current {
            if scalar == "\\" { index += 2; continue }
            if scalar == quote {
                if next == quote { index += 2; continue }
                break
            }
            index += 1
        }
        index += 1
    }

    /// Moves past a quoted identifier the scanner is at the opening backtick of.
    mutating func skipQuotedIdentifier() {
        index += 1
        while let scalar = current, scalar != "`" { index += 1 }
        index += 1
    }

    /// Moves past whitespace, comments and opening parentheses, to where a statement's first word begins.
    mutating func skipWhitespaceCommentsAndOpeningParentheses() {
        while let scalar = current {
            if scalar.properties.isWhitespace || scalar == "(" {
                index += 1
            } else if atAComment {
                skipComment()
            } else {
                break
            }
        }
    }
}
