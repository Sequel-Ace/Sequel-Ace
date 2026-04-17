//
//  SATaskManaging.swift
//  Sequel Ace
//
//  Created as part of the modernization effort.
//  Defines a protocol for task/progress management, decoupling
//  sub-controllers from the concrete SPDatabaseDocument.
//

import AppKit

/// Protocol for managing long-running task state and progress indicators.
///
/// SPDatabaseDocument's sub-controllers (SPTableContent, SPCustomQuery, etc.)
/// currently call task methods directly on the document. This protocol
/// abstracts that dependency, enabling:
/// - Sub-controllers to accept any task manager (testable with mocks)
/// - Future SwiftUI views to show progress independently
/// - Decoupling from the monolithic document controller
@objc protocol SATaskManaging: AnyObject {

    /// Begins a new task, incrementing the working level.
    /// Shows the progress indicator after a brief delay.
    /// Can be called from any thread — dispatches to main if needed.
    @objc(startTaskWithDescription:)
    func startTask(withDescription description: String)

    /// Ends the current task, decrementing the working level.
    @objc func endTask()

    /// Updates the progress percentage (0-100).
    @objc(setTaskPercentage:)
    func setTaskPercentage(_ percentage: CGFloat)

    /// Switches the progress indicator back to indeterminate mode.
    @objc(setTaskProgressToIndeterminateAfterDelay:)
    func setTaskProgressToIndeterminate(afterDelay: Bool)

    /// Enables the cancel button with a title and optional callback.
    @objc(enableTaskCancellationWithTitle:callbackObject:callbackFunction:)
    func enableTaskCancellation(withTitle title: String, callbackObject: NSObject?, callbackFunction: Selector?)

    /// Disables task cancellation (called automatically on endTask).
    @objc func disableTaskCancellation()

    /// Returns true if any task is currently active.
    @objc func isWorking() -> Bool

    /// Controls whether the database list popup is selectable during tasks.
    @objc(setDatabaseListIsSelectable:)
    func setDatabaseListIsSelectable(_ selectable: Bool)

    /// Updates the task description text.
    @objc(setTaskDescription:)
    func setTaskDescription(_ description: String)
}
