//
//  VaultRoleFilter.swift
//  Sequel Ace
//
//  Fuzzy ordering for the Vault role dropdown: case-insensitive subsequence
//  matches first (best score first, then alphabetical), a separator row, then
//  the remaining roles alphabetically.
//

import Foundation

@objcMembers final class VaultRoleFilter: NSObject {

    /// Non-selectable visual separator placed between fuzzy matches and the rest.
    static let separator = "──────────"

    /// Whether `query` matches `candidate` as a case-insensitive subsequence.
    static func matches(query: String, candidate: String) -> Bool {
        return score(query: query, candidate: candidate) != nil
    }

    /// Subsequence score (higher = better), or nil when `query` is not a
    /// subsequence of `candidate`. Word-boundary and consecutive-character
    /// matches score higher so the closest matches rank first.
    static func score(query: String, candidate: String) -> NSNumber? {
        let q: [Character] = Array(query.lowercased())
        if q.isEmpty { return 0 }
        let c: [Character] = Array(candidate.lowercased())
        var qi = 0
        var total = 0
        var prevMatchIndex = -2
        let boundaries: Set<Character> = [" ", "-", "_", "/", "."]
        for ci in 0..<c.count {
            if qi >= q.count { break }
            if c[ci] == q[qi] {
                var s = 1
                let isBoundary = (ci == 0) || boundaries.contains(c[ci - 1])
                if isBoundary { s += 10 }
                if ci == prevMatchIndex + 1 { s += 5 }
                total += s
                prevMatchIndex = ci
                qi += 1
            }
        }
        return qi == q.count ? NSNumber(value: total) : nil
    }

    /// Ordered dropdown list: fuzzy matches first (best score, then alphabetical),
    /// then `separator`, then the remaining roles alphabetically. An empty query
    /// returns all roles alphabetically (no separator); if nothing matches, all
    /// roles alphabetically; if everything matches, no separator.
    static func orderedRoles(_ roles: [String], query: String) -> [String] {
        let alpha: (String, String) -> Bool = { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let sortedAll = roles.sorted(by: alpha)
        if trimmed.isEmpty { return sortedAll }

        var matched: [(role: String, score: Int)] = []
        var rest: [String] = []
        for role in sortedAll {
            if let s = score(query: trimmed, candidate: role) {
                matched.append((role, s.intValue))
            } else {
                rest.append(role)
            }
        }
        let matchedRoles = matched
            .sorted { $0.score != $1.score ? $0.score > $1.score : alpha($0.role, $1.role) }
            .map { $0.role }
        if matchedRoles.isEmpty { return sortedAll }
        if rest.isEmpty { return matchedRoles }
        return matchedRoles + [separator] + rest
    }
}
