//
//  SAConnectionAttemptSequence.swift
//  Sequel Ace
//
//  Copyright (c) 2026 Sequel-Ace. All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person
//  obtaining a copy of this software and associated documentation
//  files (the "Software"), to deal in the Software without
//  restriction, including without limitation the rights to use,
//  copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the
//  Software is furnished to do so, subject to the following
//  conditions:
//
//  The above copyright notice and this permission notice shall be
//  included in all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
//  EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
//  OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
//  NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
//  HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
//  WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
//  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
//  OTHER DEALINGS IN THE SOFTWARE.
//

import Foundation

/// The connection attempts of one connection window, newest first.
///
/// Starting an attempt supersedes the previous one: its in-flight connection is
/// cancelled, and any result still delivered for it, from the credential leg or
/// from the connection itself, is dropped. Use from the main queue only.
final class SAConnectionAttemptSequence {

    /// The identifier of the newest attempt.
    private(set) var currentAttemptID: UInt = 0

    private let cancelInFlightConnection: () -> Void

    /// Creates a sequence that calls `cancelInFlightConnection` whenever an attempt is superseded or cancelled.
    init(cancelInFlightConnection: @escaping () -> Void) {
        self.cancelInFlightConnection = cancelInFlightConnection
    }

    /// Starts a new attempt, cancelling the previous attempt's in-flight connection, and returns its identifier.
    func begin() -> UInt {
        currentAttemptID &+= 1
        cancelInFlightConnection()
        return currentAttemptID
    }

    /// Ends the current attempt without starting another, cancelling its in-flight connection.
    func cancel() {
        currentAttemptID &+= 1
        cancelInFlightConnection()
    }

    /// True while `attemptID` is the newest attempt.
    func isCurrent(_ attemptID: UInt) -> Bool {
        attemptID == currentAttemptID
    }

    /// `completion`, run only while `attemptID` is still the newest attempt when it is called.
    func deliver<Result>(to attemptID: UInt, _ completion: @escaping (Result) -> Void) -> (Result) -> Void {
        { [weak self] result in
            guard let self, self.isCurrent(attemptID) else { return }
            completion(result)
        }
    }
}
