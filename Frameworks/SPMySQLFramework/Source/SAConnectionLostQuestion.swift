//
//  SAConnectionLostQuestion.swift
//  SPMySQLFramework
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//
//  More info at <https://github.com/Sequel-Ace/Sequel-Ace>
//

import Foundation

/// What a connection has to do for the question about a lost connection to be put to the user.
///
/// Three steps that only the connection can take: two of them have to happen on the main thread,
/// which is where AppKit may be asked anything and where the question is shown.
@objc(SAConnectionLostQuestionHost)
public protocol SAConnectionLostQuestionHost {

    /// Whether the application is showing something modal. Has to be answered from the main
    /// thread, which is the only one allowed to ask AppKit.
    @objc func aModalWindowIsShowingOnTheMainThread() -> Bool

    /// Puts the question to the delegate on the main thread and keeps the answer, returning once
    /// it has been given.
    @objc func askTheDelegateOnTheMainThread()

    /// The answer that was kept, read under the lock that guards it.
    @objc func theAnswerThatWasKept() -> Int
}

/// Puts one question about a lost connection to the user, from whichever thread finds out.
///
/// The thread that asks is not the thread that answers: the question is a sheet on the document's
/// window, so it is shown on the main thread, while the connection is usually lost on a worker.
/// This decides who asks, who waits, and how long to hold off while something else is modal; the
/// connection only carries out the steps.
@objc(SAConnectionLostQuestion)
public final class SAConnectionLostQuestion: NSObject {

    /// How many times to look for another modal window before asking anyway.
    ///
    /// A question that never comes is worse than one that comes while something else is open, so
    /// the wait ends after these looks - five seconds' worth, at the interval below.
    @objc public static let modalWindowChecks = 50

    /// How long to wait between those looks, in seconds.
    @objc public static let modalWindowCheckInterval: TimeInterval = 0.1

    /// The answer to the question about a lost connection.
    ///
    /// On the main thread the question is asked without waiting: that thread produces every
    /// answer, so waiting for one would wait for itself. It still goes through the gate, so a
    /// worker that loses the connection while the question is open shares the answer rather than
    /// queueing a dialog behind it, and a question that is already open is not asked a second
    /// time.
    ///
    /// From any other thread the question goes to the main thread and the gate shares one answer
    /// among everything that lost the connection together. The hand-off runs through the main
    /// thread's run loop rather than its queue - the work that led here can itself have been
    /// started from a block on that queue, and a queue runs one block at a time, so waiting for
    /// that block to finish would mean waiting for something that is waiting for this answer.
    /// That is the host's business; what is decided here is that it happens at all.
    /// - Parameters:
    ///   - gate: Lets one question be asked at a time and shares its answer.
    ///   - isMainThread: Whether this is running on the thread the question is shown on.
    ///   - host: Carries out the steps only the connection can take.
    /// - Returns: The answer to the question that was open, or to a new one.
    @objc(decisionThroughGate:isMainThread:host:)
    public static func decision(throughGate gate: SAConnectionLostDecisionGate,
                                isMainThread: Bool,
                                host: SAConnectionLostQuestionHost) -> Int {
        if isMainThread {
            return gate.decisionAskingHere(with: {
                host.askTheDelegateOnTheMainThread()
                return host.theAnswerThatWasKept()
            })
        }

        return gate.decision(askingWith: {
            waitWhileSomethingElseIsModal(host: host)
            host.askTheDelegateOnTheMainThread()
            return host.theAnswerThatWasKept()
        })
    }

    /// Holds off while another modal window is up, so the question does not stack on it, and
    /// gives up waiting after ``modalWindowChecks`` looks.
    /// - Parameter host: Answers whether something modal is showing.
    private static func waitWhileSomethingElseIsModal(host: SAConnectionLostQuestionHost) {
        for _ in 0..<modalWindowChecks {
            if !host.aModalWindowIsShowingOnTheMainThread() {
                return
            }
            Thread.sleep(forTimeInterval: modalWindowCheckInterval)
        }
    }
}
