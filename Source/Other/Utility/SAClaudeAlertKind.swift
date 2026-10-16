import Foundation

/// How the Claude alert card presents an alert. Decided from the alert's own text and buttons only
/// (never from `alertStyle`, the suppression checkbox or the accessory — those do not change the kind).
enum SAClaudeAlertKind: String, CaseIterable, Equatable {
    case error, destructive, warning, question, info

    static func classify(_ facts: SAClaudeAlertFacts) -> SAClaudeAlertClassification {
        SAClaudeAlertClassifier.classify(facts)
    }
}

struct SAClaudeAlertFacts: Equatable {
    var title: String
    var message: String
    /// `alert.buttons` order (index 0 = first = rightmost); [] = NSAlert's implicit OK.
    var buttonTitles: [String]
    /// Built by `+alertWithError:` (directly or via presentError:).
    var isFromError = false
}

struct SAClaudeAlertClassification: Equatable {
    var kind: SAClaudeAlertKind
    /// Destructive only: the buttons that turn red, ascending (every delete-type button, never a Cancel-type one; with
    /// no delete-type button, at most one fallback). Empty = nothing turns red.
    var destructiveButtonIndices: [Int] = []
}

struct SAClaudeAlertMessageParts: Equatable {
    var explanation: String
    /// The server's text for the "MySQL said" block; nil = no block.
    var serverText: String?
}

enum SAClaudeAlertMessageSplit {
    private static let marker = "MySQL said:"

    static func split(title: String, message: String) -> SAClaudeAlertMessageParts {
        let ws = CharacterSet.whitespacesAndNewlines

        // The whole message is the server's text.
        let leadingTrimmed = String(message.drop(while: { $0.unicodeScalars.allSatisfy { ws.contains($0) } }))
        let isMySQLErrorTitle = title.trimmingCharacters(in: ws).caseInsensitiveCompare("MySQL Error") == .orderedSame
        if isMySQLErrorTitle || leadingTrimmed.lowercased().hasPrefix("[error in query") {
            let server = message.trimmingCharacters(in: ws)
            return SAClaudeAlertMessageParts(explanation: "", serverText: server.isEmpty ? nil : server)
        }

        guard let range = message.range(of: marker, options: .caseInsensitive) else {
            return SAClaudeAlertMessageParts(explanation: message, serverText: nil)
        }
        let server = message[range.upperBound...].trimmingCharacters(in: ws)
        if server.isEmpty {
            return SAClaudeAlertMessageParts(explanation: message, serverText: nil)
        }
        let explanation = message[..<range.lowerBound].replacingOccurrences(of: "\\s+\\z", with: "", options: .regularExpression)
        return SAClaudeAlertMessageParts(explanation: explanation, serverText: server)
    }
}

/// The rules behind `SAClaudeAlertKind.classify`, in order, first match wins:
/// 1. Destructive — a destructive-sounding question or data-loss wording (two or more buttons), or a non-Cancel
///    delete-type button (unless a strong failure signal says the alert reports an error). Every delete-type button
///    turns red.
/// 2. Error — strong failure signals; weak ones only with a single OK/Close-type button.
/// 3. Question — two or more buttons.
/// 4. Info — a single OK/Close-type button, an info word, no warning word, nothing negated or missing.
/// 5. Warning — everything else (never Info by default).
private enum SAClaudeAlertClassifier {
    private static func regex(_ pattern: String) -> NSRegularExpression {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: pattern, options: [])
    }

    // Quoted names are removed before the word rules. Curly quotes are detected before they are normalised.
    private static let curlyQuoted = [regex("“[^”\\n]+”"), regex("‘[^’\\n]+’")]
    private static let straightQuoted = [
        regex("(?<![\\p{L}\\p{N}])'[^'\\n]+'(?![\\p{L}\\p{N}])"),
        regex("\"[^\"\\n]+\""),
        regex("`[^`\\n]+`")
    ]

    private static let destructiveButton = regex("^(delete|remove|drop|truncate|kill|clear|empty|shutdown|shut down|discard|force delete|reset|overwrite)(?![\\p{L}])")
    /// "Don't Save", "Do Not Save", "Don't …": the button that gives the changes up, which is the red one of a data-loss
    /// prompt (its "Save" sibling is the safe choice).
    private static let declineButton = regex("^(don'?t|do not)(?![\\p{L}])")
    private static let saveButton = regex("^(save|keep)(?![\\p{L}])")
    private static let destructiveTitle = regex("^(delete|drop|truncate|remove|kill)\\b")
    // Tuned against the call sites: overwrite (SPDataImport.m:318, SPExportController.m:2044), "will be lost"
    // (SPUserManager.m:983, SPDataImport.m:603), "without saving" (SPEditorPreferencePane.m:786). "was lost" is not data loss.
    private static let dataLoss = regex("(cannot be undone|can't be undone|\\bpermanently\\b|\\b(lose|loss of)\\b[^.!?]*\\bdata\\b|\\boverwrit(e|es|ing|ten)\\b|\\bbe (?:[a-z]+ )?lost\\b|\\bwithout saving\\b)")
    /// A title that states a failure ("Cannot Access SSH Config File", "Unable to …", "Failed to …"): a strong failure signal.
    private static let failureTitle = regex("^(cannot|can't|can not|unable|couldn't|could not|failed)(?![\\p{L}])")
    private static let cannotBeUndone = regex("\\b(cannot|can't) be undone\\b")
    private static let mysqlSaid = regex("\\bmysql said\\b")
    // "exception": SABundleHTMLOutputWindowController.swift:195 (JavaScript Exception).
    private static let strongFailure = regex("\\b(mysql said|errors?|exceptions?|failed|failure|couldn't|could not|unable to)\\b")
    private static let strongFailureWithoutServer = regex("\\b(errors?|exceptions?|failed|failure|couldn't|could not|unable to)\\b")
    private static let weakFailure = regex("(\\b(cannot|can't)\\b(?! be undone)|\\b(invalid|not found|denied|must|empty|insufficient)\\b)")
    // "checksums": SPDatabaseDocument.m:1990 ("Checksums of selected items" with the results table).
    private static let infoWord = regex("\\b(success|successful|successfully|finished|completed|done|flushed|saved|exported|imported|updated|is up to date|running the latest|copied|checksums?|result of|results of|information)\\b")
    // A negated or missing outcome is never good news (SPTableContent.m:1522: "did not match ... information was read").
    private static let negation = regex("(\\b(not|never|no longer|unavailable|missing)\\b|n't\\b)")
    private static let warningWord = regex("\\b(warning|partial|partially|may|might|deprecated|limited|not supported)\\b")

    private static func matches(_ expression: NSRegularExpression, _ text: String) -> Bool {
        expression.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)) != nil
    }

    private static func removing(_ expressions: [NSRegularExpression], from text: String) -> String {
        var result = text
        for expression in expressions {
            result = expression.stringByReplacingMatches(in: result, options: [], range: NSRange(result.startIndex..., in: result), withTemplate: " ")
        }
        return result
    }

    /// Lower-cased matching text without quoted names; typographic quotes normalised.
    private static func matchingText(_ text: String) -> String {
        var result = removing(curlyQuoted, from: text)
        result = result.replacingOccurrences(of: "’", with: "'").replacingOccurrences(of: "“", with: "\"").replacingOccurrences(of: "”", with: "\"")
        result = removing(straightQuoted, from: result)
        return result.lowercased()
    }

    private static func isCancel(_ title: String) -> Bool {
        var t = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for suffix in ["…", "..."] where t.hasSuffix(suffix) {
            t = String(t.dropLast(suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            break
        }
        return t == "cancel"
    }

    private static func isAcknowledge(_ title: String) -> Bool {
        ["ok", "close", "done", "dismiss"].contains(title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    static func classify(_ facts: SAClaudeAlertFacts) -> SAClaudeAlertClassification {
        let buttons = facts.buttonTitles.isEmpty ? ["OK"] : facts.buttonTitles
        let parts = SAClaudeAlertMessageSplit.split(title: facts.title, message: facts.message)

        var text = matchingText(facts.title + "\n" + facts.message)
        if matches(mysqlSaid, text) {
            // The explanation before "MySQL said" states success (CHECK TABLE passed): judge the alert by that alone.
            let explanationText = matchingText(facts.title + "\n" + parts.explanation)
            if matches(infoWord, explanationText),
               !matches(strongFailureWithoutServer, explanationText),
               !matches(weakFailure, explanationText) {
                text = explanationText
            }
        }

        let firstNonCancel = buttons.firstIndex { !isCancel($0) }

        // 1a. A destructive question or data-loss wording, with a choice to make.
        if buttons.count >= 2, let firstNonCancel {
            let title = matchingText(facts.title).trimmingCharacters(in: .whitespacesAndNewlines)
            let questionTitle = matches(destructiveTitle, title) && title.contains("?")
            if questionTitle || matches(dataLoss, text) {
                func normalised(_ index: Int) -> String {
                    buttons[index].trimmingCharacters(in: .whitespacesAndNewlines).lowercased().replacingOccurrences(of: "’", with: "'")
                }
                let candidates = buttons.indices.filter { !isCancel(buttons[$0]) }
                // Every delete-type button; else one "Don't Save" / "Discard"-style button; else the first button that is
                // not Cancel, but never a "Save" / "Keep" (the safe choice): then no button turns red.
                var red = candidates.filter { matches(destructiveButton, normalised($0)) }
                if red.isEmpty {
                    red = (candidates.first { matches(declineButton, normalised($0)) }
                        ?? candidates.first { !matches(saveButton, normalised($0)) }).map { [$0] } ?? []
                }
                return SAClaudeAlertClassification(kind: .destructive, destructiveButtonIndices: red)
            }
        }

        // 2a. A strong failure signal beats a destructive-sounding button title.
        let titleText = matchingText(facts.title).trimmingCharacters(in: .whitespacesAndNewlines)
        let titleStatesFailure = matches(failureTitle, titleText) && !matches(cannotBeUndone, text)
        let isStrongFailure = facts.isFromError || titleStatesFailure || matches(strongFailure, text)
        if isStrongFailure {
            return SAClaudeAlertClassification(kind: .error)
        }

        // 1b. Non-Cancel delete-type buttons.
        if buttons.count >= 2 {
            let red = buttons.indices.filter { !isCancel(buttons[$0]) && matches(destructiveButton, buttons[$0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) }
            if !red.isEmpty {
                return SAClaudeAlertClassification(kind: .destructive, destructiveButtonIndices: red)
            }
        }

        let singleAcknowledge = buttons.count == 1 && isAcknowledge(buttons[0])

        // 2b. Weak failure words, only on a plain acknowledgement.
        if singleAcknowledge && matches(weakFailure, text) {
            return SAClaudeAlertClassification(kind: .error)
        }
        // 3.
        if buttons.count >= 2 {
            return SAClaudeAlertClassification(kind: .question)
        }
        // 4.
        if singleAcknowledge && matches(infoWord, text) && !matches(warningWord, text) && !matches(negation, text) {
            return SAClaudeAlertClassification(kind: .info)
        }
        // 5.
        return SAClaudeAlertClassification(kind: .warning)
    }
}

/// Which alerts get the Claude card. A SwiftUI `.alert` is an ordinary `NSAlert` presented on a window that hosts a
/// SwiftUI view, so it keeps today's skin; so does an alert that is not exactly an `NSAlert` or whose buttons
/// target something other than the alert.
enum SAClaudeAlertEligibility {

    struct Facts: Equatable {
        /// `NSStringFromClass` of the visible class (KVO subclasses skipped).
        var alertClassName: String
        /// One entry per button; nil = no target.
        var buttonTargetClassNames: [String?]
        /// `String(describing:)` of the class of the first SwiftUI hosting view in the presenting window's view tree,
        /// else of its content view; nil when the alert is not presented on a window.
        var presentingContentClassName: String?
    }

    static func isEligible(_ facts: Facts) -> Bool {
        guard facts.alertClassName == "NSAlert" else { return false }
        guard facts.buttonTargetClassNames.allSatisfy({ $0 == "NSAlert" }) else { return false }
        if let presenter = facts.presentingContentClassName, isHostingViewClassName(presenter) { return false }
        return true
    }

    /// `String(describing: type(of: view))` of a SwiftUI hosting view (`NSHostingView<Root>`, `_NSHostingView<Root>`).
    static func isHostingViewClassName(_ name: String) -> Bool {
        name.hasPrefix("NSHostingView") || name.hasPrefix("_NSHostingView")
    }
}
