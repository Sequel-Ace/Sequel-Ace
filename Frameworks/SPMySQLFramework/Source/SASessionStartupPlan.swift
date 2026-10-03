//
//  SASessionStartupPlan.swift
//  SPMySQLFramework
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//
//  More info at <https://github.com/Sequel-Ace/Sequel-Ace>
//

import Foundation

/// What a new session needs before values are escaped for it.
///
/// Two things have to be settled once a session has started and reported its variables: that the
/// server will report later changes to the character set, and that the character set it is in is
/// one this framework can convert values for. Both are decided here, and the connection only runs
/// the statements that come back - it does not work out which ones are needed.
@objc(SASessionStartupPlan)
public final class SASessionStartupPlan: NSObject {

    /// The statements to run on the session, in order. Empty when nothing needs settling.
    @objc public let statements: [String]

    /// The character set the session is in once the statements have run.
    @objc public let characterSet: String

    /// The character set the session stays in if a statement fails.
    @objc public let characterSetWithoutStatements: String

    /// Whether the character set reported cannot be carried, so the session is being moved.
    @objc public let movesToAnotherCharacterSet: Bool

    private init(statements: [String],
                 characterSet: String,
                 characterSetWithoutStatements: String,
                 movesToAnotherCharacterSet: Bool) {
        self.statements = statements
        self.characterSet = characterSet
        self.characterSetWithoutStatements = characterSetWithoutStatements
        self.movesToAnotherCharacterSet = movesToAnotherCharacterSet
        super.init()
    }

    /// Works out what a session that has just reported these variables still needs.
    ///
    /// The tracking statement is left out behind ProxySQL: it does not know the variable, and
    /// setting one it does not track pins the connection to its current hostgroup, which breaks
    /// every later query that should route elsewhere - the trap already worked around for
    /// `information_schema_stats_expiry` (https://github.com/Sequel-Ace/Sequel-Ace/issues/2006).
    /// Logging the error afterwards does not undo the lock, so the statement must not be sent at
    /// all. That check costs a round trip, so `serverIsProxySQL` is only asked when a statement
    /// would otherwise be sent, which a server at its default never needs.
    /// - Parameters:
    ///   - reportedCharacterSet: The character set the session reports being in.
    ///   - trackingList: The session's `session_track_system_variables`, as reported.
    ///   - quote: Quotes a value for a statement, as the server expects it.
    ///   - serverIsProxySQL: Answers whether the connection is served by ProxySQL. Asked at most
    ///     once, and only when a tracking statement would be sent.
    /// - Returns: The statements to run and the character set they leave the session in.
    @objc(planForReportedCharacterSet:trackingList:quote:serverIsProxySQL:)
    public static func plan(forReportedCharacterSet reportedCharacterSet: String?,
                            trackingList: String?,
                            quote: (String) -> String,
                            serverIsProxySQL: () -> Bool) -> SASessionStartupPlan {
        var statements: [String] = []

        // Escaping follows what the session reports, and the client library only learns of a
        // SET NAMES through the server's session-state tracking. A server that does not list
        // character_set_client there leaves such a statement invisible, and values would go on
        // being escaped for the character set the connection last set itself.
        if let tracking = SASessionStateTracking.trackingListToSet(givenCurrentList: trackingList),
           !serverIsProxySQL() {
            statements.append("SET SESSION session_track_system_variables = \(quote(tracking))")
        }

        // A session can end up in a character set that was never asked for - a server default, or
        // an init_connect that runs SET NAMES - and this framework has no string encoding for
        // every one of them. Reading such a session's bytes as UTF-8 reinterprets them rather
        // than converting them, so the session is moved to one that can be carried. Nothing goes
        // out of reach: the server converts between a table's own character set and the
        // session's. A server too old to know the fallback keeps what it reported, which is why
        // the character set without the statements is carried alongside.
        let reported = reportedCharacterSet ?? ""
        if let carried = SAConnectionCharacterSets.carriableName(forCharacterSet: reported) {
            // In the spelling the encoding table is keyed by, which it matches case-sensitively.
            return SASessionStartupPlan(statements: statements,
                                        characterSet: carried,
                                        characterSetWithoutStatements: carried,
                                        movesToAnotherCharacterSet: false)
        }

        let fallback = SAConnectionCharacterSets.fallbackCharacterSet
        statements.append("SET NAMES \(quote(fallback))")
        return SASessionStartupPlan(statements: statements,
                                    characterSet: fallback,
                                    characterSetWithoutStatements: reported,
                                    movesToAnotherCharacterSet: true)
    }
}
