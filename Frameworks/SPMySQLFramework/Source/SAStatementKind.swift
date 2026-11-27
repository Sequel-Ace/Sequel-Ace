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

    /// Whether the statement may change data on the server.
    /// - Parameter statement: The statement's text.
    /// - Returns: False only for a statement led by a keyword that only reads.
    @objc(statementMayWrite:)
    public static func statementMayWrite(_ statement: String) -> Bool {
        guard let keyword = leadingKeyword(of: statement) else {
            return true
        }
        return !readOnlyKeywords.contains(keyword)
    }

    /// The first word of the statement past whitespace, comments and opening parentheses, in upper
    /// case, or nil when there is none.
    /// - Parameter statement: The statement's text.
    static func leadingKeyword(of statement: String) -> String? {
        let scalars = Array(statement.unicodeScalars)
        var index = 0
        func at(_ offset: Int) -> Unicode.Scalar? { index + offset < scalars.count ? scalars[index + offset] : nil }
        while index < scalars.count {
            let scalar = scalars[index]
            if scalar.properties.isWhitespace || scalar == "(" {
                index += 1
            } else if scalar == "#" || (scalar == "-" && at(1) == "-") {
                while index < scalars.count, scalars[index] != "\n" { index += 1 }
            } else if scalar == "/", at(1) == "*" {
                index += 2
                while index < scalars.count, !(scalars[index] == "*" && at(1) == "/") { index += 1 }
                index += 2
            } else {
                break
            }
        }
        var word = ""
        while index < scalars.count, scalars[index].properties.isAlphabetic {
            word.unicodeScalars.append(scalars[index])
            index += 1
        }
        return word.isEmpty ? nil : word.uppercased()
    }
}
