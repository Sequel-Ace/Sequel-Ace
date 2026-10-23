//
//  SATableLoadStop.swift
//  Sequel Ace
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//
//  More info at <https://github.com/Sequel-Ace/Sequel-Ace>
//

import Foundation

/// What is left of a table load the user asked to stop.
///
/// Loading a table runs through several stages, each of which asks the server for something, and
/// the Stop button ends the whole load rather than only the query that is running. Two different
/// things follow from a press, and they are not the same question:
///
/// - the stages still to come do not run, and
/// - the views that read the table's information are left with nothing, so the next switch to one
///   of them loads the table again.
///
/// The second only holds if a stage was actually prevented. The button stays live until the task
/// ends, which is a moment after the last stage has run, so a press can arrive when there is
/// nothing left to stop; reading that as a stopped load costs an unnecessary reload of a table
/// that is sitting there fully loaded. What matters is therefore not whether Stop was pressed but
/// whether it prevented anything, and this keeps the two apart.
@objc(SATableLoadStop)
public final class SATableLoadStop: NSObject {

    private let lock = NSLock()
    private var stopWasRequested = false
    private var aStageDidNotRun = false

    /// Starts a load, forgetting what the one before it left behind.
    @objc public func loadIsStarting() {
        lock.lock()
        defer { lock.unlock() }
        stopWasRequested = false
        aStageDidNotRun = false
    }

    /// Records that the user pressed Stop.
    ///
    /// Pressing it again while the load is already stopping changes nothing: the load is already
    /// going to skip whatever is left.
    @objc public func stopWasAskedFor() {
        lock.lock()
        defer { lock.unlock() }
        stopWasRequested = true
    }

    /// Whether the load should go on to its next stage, recording a stage that does not run.
    ///
    /// Asked once per stage, in the order the stages run. Reading it is what makes a press count:
    /// a press that arrives when no stage is left to ask is a press that prevented nothing.
    /// - Returns: Whether to run the stage.
    @objc public func shouldRunNextStage() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if stopWasRequested {
            aStageDidNotRun = true
            return false
        }
        return true
    }

    /// Records how a stage that was let through ended.
    ///
    /// A press that arrives after a stage's gate said yes cuts that stage off inside its own
    /// query, and no gate after it reads the press - the last stage has none. The table then looks
    /// fully loaded while the work of that stage never finished, so the next switch to a view that
    /// needs it would not load it again. A stage that completed records nothing, which is what
    /// keeps a press arriving after the last stage from costing a reload.
    /// - Parameter stageCompleted: Whether the stage finished its work.
    @objc(noteStageEndedHavingCompleted:)
    public func noteStageEnded(havingCompleted stageCompleted: Bool) {
        lock.lock()
        defer { lock.unlock() }
        if !stageCompleted {
            aStageDidNotRun = true
        }
    }

    /// Whether the user asked to stop, whether or not anything was left to stop.
    ///
    /// For the parts of the load that only tidy up - putting the Stop button back, refreshing a
    /// window that is already open - where the question is what the user asked for rather than
    /// what became of the table.
    @objc public var stopWasAsked: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopWasRequested
    }

    /// Whether the load left the table's information unloaded.
    ///
    /// The one the views go by: a load that ran all its stages leaves nothing to load again, even
    /// if Stop was pressed as it finished.
    @objc public var aStageWasLeftUndone: Bool {
        lock.lock()
        defer { lock.unlock() }
        return aStageDidNotRun
    }
}
