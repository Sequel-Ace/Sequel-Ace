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

    private let condition = NSCondition()
    private var questionIsOpen = false
    private var answersGiven: UInt = 0
    private var lastAnswer = 0

    /// The answer to the question, asked by this thread or shared with the one already asking.
    ///
    /// Never call this on the thread the question is put to the user on - the main thread - since
    /// it may wait for an answer that only that thread can produce.
    /// - Parameter ask: Puts the question to the user and returns the answer.
    /// - Returns: The answer to the question that was open when this was called, or to a new one.
    @objc(decisionAskingWith:)
    public func decision(askingWith ask: () -> Int) -> Int {
        condition.lock()
        if questionIsOpen {
            let answersBefore = answersGiven
            while questionIsOpen && answersGiven == answersBefore {
                condition.wait()
            }
            let sharedAnswer = lastAnswer
            condition.unlock()
            return sharedAnswer
        }
        questionIsOpen = true
        condition.unlock()

        let answer = ask()

        condition.lock()
        lastAnswer = answer
        questionIsOpen = false
        answersGiven += 1
        condition.broadcast()
        condition.unlock()

        return answer
    }
}
