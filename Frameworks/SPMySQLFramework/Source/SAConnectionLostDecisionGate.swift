//
//  SAConnectionLostDecisionGate.swift
//  SPMySQLFramework
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//
//  More info at <https://github.com/Sequel-Ace/Sequel-Ace>
//

import Foundation

/// Lets one question about a lost connection be asked at a time.
///
/// A connection is lost for everything that uses it, so the threads that find out together would
/// each ask the user what to do - one dialog behind the other, all about the same thing. The first
/// thread asks; any thread that arrives while that question is open waits for the answer and uses
/// it. A thread that arrives after an answer was given asks again, because by then it is a new
/// loss rather than the same one.
@objc(SAConnectionLostDecisionGate)
public final class SAConnectionLostDecisionGate: NSObject {

    /// One question put to the user, and its answer once it has been given.
    ///
    /// Each thread that waits keeps hold of the question it joined, so a later question - asked
    /// before that thread gets to take its answer - cannot hand it the wrong one.
    private final class SAQuestion {
        var answer: Int?
        var waitingThreads = 0
    }

    private let condition = NSCondition()
    private var openQuestion: SAQuestion?

    /// The answer to the question, asked by this thread or shared with the one already asking.
    ///
    /// Never call this on the thread the question is put to the user on - the main thread - since
    /// it may wait for an answer that only that thread can produce.
    /// - Parameter ask: Puts the question to the user and returns the answer.
    /// - Returns: The answer to the question that was open when this was called, or to a new one.
    @objc(decisionAskingWith:)
    public func decision(askingWith ask: () -> Int) -> Int {
        condition.lock()
        if let question = openQuestion {
            question.waitingThreads += 1
            while true {
                if let sharedAnswer = question.answer {
                    question.waitingThreads -= 1
                    condition.unlock()
                    return sharedAnswer
                }
                condition.wait()
            }
        }
        let question = SAQuestion()
        openQuestion = question
        condition.unlock()

        // The question is published before it is asked, so the answer reaches the threads waiting
        // for it however this returns. Were the asking to end without one - a thread cancelled
        // while it waits for the main thread, say - the others would wait on a question nobody is
        // going to answer any more, and this connection would never ask again.
        var asked: Int?
        defer {
            condition.lock()
            question.answer = asked ?? SAConnectionLostDecisionGate.fallbackAnswer
            openQuestion = nil
            condition.broadcast()
            condition.unlock()
        }

        let answer = ask()
        asked = answer
        return answer
    }

    /// The answer to a question this thread asks itself, for the thread the question is put to
    /// the user on.
    ///
    /// That thread can never wait: it is the one that produces every answer, so waiting for one
    /// would wait for itself. It still goes through the gate, so a thread that arrives while its
    /// question is open shares that answer instead of queueing a second dialog behind it. And
    /// when a question is already open - a background thread asked, and the user is answering it
    /// on this very thread, which is how this can be reached at all - no second question is put;
    /// the fallback is returned rather than stacking one dialog on another.
    /// - Parameter ask: Puts the question to the user and returns the answer.
    /// - Returns: The answer given here, or the fallback when a question was already open.
    @objc(decisionAskingHereWith:)
    public func decisionAskingHere(with ask: () -> Int) -> Int {
        condition.lock()
        if openQuestion != nil {
            condition.unlock()
            return SAConnectionLostDecisionGate.fallbackAnswer
        }
        let question = SAQuestion()
        openQuestion = question
        condition.unlock()

        // Published before it is asked, for the same reason as in `decision(askingWith:)`:
        // whatever happens, the threads waiting on it are released.
        var asked: Int?
        defer {
            condition.lock()
            question.answer = asked ?? SAConnectionLostDecisionGate.fallbackAnswer
            openQuestion = nil
            condition.broadcast()
            condition.unlock()
        }

        let answer = ask()
        asked = answer
        return answer
    }

    /// The answer the waiting threads are given when the asking ended without one.
    ///
    /// It is the value `SPMySQLConnectionLostDisconnect` carries - the answer the connection used
    /// to start from before anybody was asked - which gives up the connection rather than keeping
    /// a thread waiting on a question that will not be answered.
    static let fallbackAnswer = 0

    /// How many threads are waiting for the answer to the question that is open now.
    var threadsWaitingForAnswer: Int {
        condition.lock()
        defer { condition.unlock() }
        return openQuestion?.waitingThreads ?? 0
    }
}
