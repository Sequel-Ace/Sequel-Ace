//
//  SATypeAheadMatcher.swift
//  Sequel Ace
//
//  Created by Sequel Ace on July 27, 2026.
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import Foundation

/// Incremental type-ahead search over a list of names.
///
/// Characters typed within `resetInterval` of the previous keystroke are
/// appended to the current search string; a longer pause starts a new search.
/// The accumulated string is matched fuzzily against the candidates, best
/// tier first: prefix match, then substring match, then in-order character
/// subsequence match ("msj" finds "mesajlar"). Within a tier the first
/// candidate in list order wins.
@objc final class SATypeAheadMatcher: NSObject {

    private let resetInterval: TimeInterval
    private var searchString = ""
    private var lastKeystrokeTime: TimeInterval = -.greatestFiniteMagnitude

    /// The search string accumulated so far (new keystrokes within
    /// `resetInterval` extend it).
    @objc var currentSearchString: String { searchString }

    @objc init(resetInterval: TimeInterval = 0.3) {
        self.resetInterval = resetInterval
    }

    /// Appends `characters` to the running search string — or starts a new
    /// one if more than `resetInterval` passed since the last keystroke — and
    /// returns the index of the best-matching candidate, or NSNotFound.
    ///
    /// `time` is the keystroke timestamp on any monotonic clock (e.g.
    /// NSEvent.timestamp); only differences between successive calls matter.
    @objc(bestMatchAppending:candidates:atTime:)
    func bestMatch(appending characters: String, candidates: [String], atTime time: TimeInterval) -> Int {
        if time - lastKeystrokeTime > resetInterval {
            searchString = ""
        }
        lastKeystrokeTime = time
        searchString += characters

        return Self.bestMatch(for: searchString, in: candidates)
    }

    /// Whether a search is in progress at `time`, i.e. the previous keystroke
    /// was recent enough that the next one extends the search string.
    @objc(isActiveAtTime:)
    func isActive(atTime time: TimeInterval) -> Bool {
        !searchString.isEmpty && time - lastKeystrokeTime <= resetInterval
    }

    /// Keeps the running search string from expiring while the sequence is
    /// held up outside the matcher — an input method composing, say, which can
    /// easily take longer than `resetInterval`. Does nothing when no search is
    /// running, so it can never resurrect one that was already reset.
    @objc(keepAliveAtTime:)
    func keepAlive(atTime time: TimeInterval) {
        guard !searchString.isEmpty else {
            return
        }
        lastKeystrokeTime = time
    }

    /// Forgets the accumulated search string immediately.
    @objc func reset() {
        searchString = ""
        lastKeystrokeTime = -.greatestFiniteMagnitude
    }

    /// Stateless fuzzy match of `pattern` against `candidates`; returns the
    /// index of the best match or NSNotFound.
    @objc(bestMatchForPattern:inCandidates:)
    static func bestMatch(for pattern: String, in candidates: [String]) -> Int {
        let foldedPattern = folded(pattern)
        guard !foldedPattern.isEmpty else {
            return NSNotFound
        }

        var substringMatch = NSNotFound
        var subsequenceMatch = NSNotFound

        for (index, candidate) in candidates.enumerated() {
            let foldedCandidate = folded(candidate)

            if foldedCandidate.hasPrefix(foldedPattern) {
                return index
            }
            if substringMatch == NSNotFound && foldedCandidate.contains(foldedPattern) {
                substringMatch = index
            }
            if substringMatch == NSNotFound && subsequenceMatch == NSNotFound
                && isSubsequence(foldedPattern, of: foldedCandidate) {
                subsequenceMatch = index
            }
        }

        return substringMatch != NSNotFound ? substringMatch : subsequenceMatch
    }

    private static func folded(_ string: String) -> String {
        string.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    private static func isSubsequence(_ pattern: String, of candidate: String) -> Bool {
        var patternIterator = pattern.makeIterator()
        var nextWanted = patternIterator.next()

        for character in candidate {
            guard let wanted = nextWanted else {
                return true
            }
            if character == wanted {
                nextWanted = patternIterator.next()
            }
        }

        return nextWanted == nil
    }
}
