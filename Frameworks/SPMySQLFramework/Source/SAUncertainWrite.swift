//
//  SAUncertainWrite.swift
//  SPMySQLFramework
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//
//  More info at <https://github.com/Sequel-Ace/Sequel-Ace>
//

import Foundation

/// What becomes of a statement whose connection went away while it was running.
///
/// A statement that lost its connection before anything was sent did not happen, and one whose
/// session had a transaction open, or autocommit off, is rolled back by the server - both are
/// known outcomes, and the connection already reports them. The one in between is not: a single
/// statement sent under autocommit, whose reply never came. The server may have carried it out
/// and committed it, or never seen it, and nothing on this side can tell which.
///
/// Two things follow. Such a statement must not be sent again - the connection retries a failed
/// statement once, which would run an `UPDATE` twice as readily as not at all - and it must not
/// be reported as though nothing happened.
@objc(SAUncertainWrite)
public final class SAUncertainWrite: NSObject {

    /// Whether what became of a statement is unknown, rather than known.
    ///
    /// - Parameters:
    ///   - statementReachedTheServer: Whether the statement was handed to the server at all. A
    ///     statement stopped before that - no usable session, the connection already gone -
    ///     certainly did not run.
    ///   - changesData: Whether the statement can change data. A read that is sent twice costs
    ///     nothing, and is the reason retrying exists.
    ///   - errorIsConnectionLoss: Whether the statement failed because the connection went away,
    ///     rather than because the server refused it. A server that answered said what happened.
    ///   - sessionRollsItBack: Whether losing the session takes the statement's work with it,
    ///     which the server does for a transaction that was open or autocommit that was off.
    ///   - statementMayCommit: Whether the statement can commit a transaction. What the session
    ///     last reported describes the statement before this one, so for a `COMMIT`, or for the
    ///     data-definition statements the server commits around, those flags settle nothing: they
    ///     would still show the transaction open that the statement may just have committed.
    /// - Returns: Whether the outcome is unknown.
    @objc(outcomeIsUnknownForStatementThatReachedTheServer:changesData:errorIsConnectionLoss:sessionRollsItBack:statementMayCommit:)
    public static func outcomeIsUnknown(statementReachedTheServer: Bool,
                                        changesData: Bool,
                                        errorIsConnectionLoss: Bool,
                                        sessionRollsItBack: Bool,
                                        statementMayCommit: Bool) -> Bool {
        guard statementReachedTheServer, errorIsConnectionLoss else {
            return false
        }
        // A statement that can commit is unknown whenever its reply is lost. Nothing on this side
        // speaks for it: the flags describe the statement before it, and the work it may have
        // committed is not the session's to roll back any more.
        if statementMayCommit {
            return true
        }
        return changesData && !sessionRollsItBack
    }
}
