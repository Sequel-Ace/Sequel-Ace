//
//  SAStatementCompletion.swift
//  SPMySQLFramework
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import Foundation

/// What became of one statement between its send and its report: whether the server carried it
/// out, and whether a stop that landed meanwhile is what the statement's caller is told.
///
/// A stop that lands once the statement has been carried out undoes nothing, and a statement
/// reported cancelled would be tried again - a write applied twice - so it is not reported as a
/// stop. The server carried a statement out when it answered the send without an error - unless it
/// could not deliver the result whole, or the stop had landed before the result's rows were stored:
/// a result set undoes nothing, so nothing is tried twice, and a run of statements stopped on the
/// report runs no further. The connection notes the native events here as they happen and asks at
/// the end; the MySQL calls themselves stay with it.
@objc(SAStatementCompletion)
public final class SAStatementCompletion: NSObject {

    /// Whether the server carried the statement out, as far as the connection knows so far.
    @objc public private(set) var wasCarriedOut = false

    /// Whether the statement was sent to the server - or at least may have reached it: a stop that
    /// lands after this is not described as a statement that certainly did not run.
    @objc public private(set) var wasSent = false

    /// The statement is being sent to the server.
    @objc public func noteSendAttempted() {
        wasSent = true
    }

    /// Whether a stop had landed by the time a buffered result's rows were stored.
    private var theStopLandedBeforeTheRowsWereStored = false

    /// The server answered the send without an error: the statement was carried out.
    @objc public func noteSendAnswered() {
        wasCarriedOut = true
    }

    /// A buffered result's rows have been stored - the only kind that is, and the moment a stop
    /// that landed before it still counts.
    /// - Parameter stopLanded: Whether a stop had landed by then.
    @objc(noteRowsStoredWithStopLanded:)
    public func noteRowsStored(stopLanded: Bool) {
        theStopLandedBeforeTheRowsWereStored = stopLanded
    }

    /// The result was retrieved, with the error the server reported for it, if any: a result the
    /// server could not deliver whole was not carried out, whatever the send said, nor was a
    /// statement whose stop had landed before its rows were stored.
    /// - Parameter errorID: The server's error for the result, or 0.
    @objc(noteResultRetrievedWithErrorID:)
    public func noteResultRetrieved(errorID: UInt) {
        if errorID != 0 || theStopLandedBeforeTheRowsWereStored {
            wasCarriedOut = false
        }
    }

    /// Whether the statement is reported cancelled: a stop that landed counts, unless the statement
    /// had been carried out by then.
    /// - Parameter stopLanded: Whether a stop has landed on the statement's query.
    @objc(isReportedCancelledWithStopLanded:)
    public func isReportedCancelled(stopLanded: Bool) -> Bool {
        !wasCarriedOut && stopLanded
    }
}
