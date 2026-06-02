//
//  SATaskController.swift
//  Sequel Ace
//
//  Created as part of the modernization effort (Phase A2).
//
//  Owns the document-wide task *progress UI*: the borderless progress
//  window, the spinning/determinate indicator, the description and
//  query-duration labels, the cancel button, and the fade-in / query-time
//  timers. Lifted out of SPDatabaseDocument, which previously carried all
//  of this inline alongside its working-level bookkeeping.
//
//  The document keeps the working-level counter (`_isWorkingLevel`) and the
//  surrounding orchestration (task start/end notifications, toolbar
//  validation, database-list selectability) because those gate behaviour
//  across the whole document, not just the progress UI. SPDatabaseDocument's
//  SATaskManaging methods are thin trampolines that drive this controller
//  for the UI while still managing that document-wide state themselves.
//
//  The view tree is loaded from ProgressIndicatorLayer.xib with this
//  controller as File's Owner; the five outlets below mirror the
//  connections that used to point at SPDatabaseDocument.
//

import AppKit

/// Hooks the task controller needs back from its host document — things it
/// cannot own because they belong to the document's wider lifecycle.
@objc protocol SATaskControllerDelegate: AnyObject {

    /// The window the progress panel should be centred over / parented to.
    func taskParentWindow() -> NSWindow?

    /// Invoked when the user clicks the cancel button. The document cancels
    /// the running query (directly, or via the database-structure connection
    /// for speed). The per-task cancellation callback is invoked separately
    /// by the controller after this returns.
    func taskControllerDidRequestCancellation()
}

@objc final class SATaskController: NSObject {

    @objc weak var delegate: SATaskControllerDelegate?

    // MARK: - Outlets (ProgressIndicatorLayer.xib, File's Owner = self)

    @IBOutlet private var taskProgressLayer: NSBox!
    @IBOutlet private var taskProgressIndicator: YRKSpinningProgressIndicator!
    @IBOutlet private var taskDescriptionText: NSTextField!
    @IBOutlet private var taskDurationTime: NSTextField!
    @IBOutlet private var taskCancelButton: NSButton!

    // MARK: - Progress UI state

    /// The borderless child window that hosts the progress layer. Created
    /// lazily (on first use, after the nib has loaded its outlets) so the
    /// property is a plain non-optional rather than an implicitly unwrapped one.
    private lazy var taskProgressWindow: NSWindow = {
        let window = NSWindow(contentRect: taskProgressLayer.bounds,
                              styleMask: .borderless,
                              backing: .buffered,
                              defer: false)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.alphaValue = 0.0
        // Retains the layer (and its subviews / outlets) for the controller's lifetime.
        window.contentView = taskProgressLayer
        return window
    }()

    private var taskDisplayIsIndeterminate = true
    private var taskProgressValue: CGFloat = 0
    private var taskDisplayLastValue: CGFloat = 0
    private var taskProgressValueDisplayInterval: CGFloat = 1
    private var taskDrawTimer: Timer?
    private var queryExecutionTimer: Timer?
    private var taskFadeInStartDate: Date?
    private var queryStartDate: Date?

    // MARK: - Cancellation state

    private var taskCanBeCancelled = false
    private var taskCancellationCallbackObject: NSObject?
    private var taskCancellationCallbackSelector: Selector?

    // MARK: - Setup

    @objc override init() {
        super.init()

        var topLevelObjects: NSArray?
        guard Bundle.main.loadNibNamed("ProgressIndicatorLayer", owner: self, topLevelObjects: &topLevelObjects),
              taskProgressLayer != nil,
              taskProgressIndicator != nil else {
            // The nib ships in the app bundle; a failure here means a broken
            // build, so fail loudly rather than limping on with nil outlets.
            fatalError("SATaskController: failed to load ProgressIndicatorLayer.xib or connect its outlets")
        }

        // Set up the progress indicator - change indicator color and shadow.
        // (The child window itself is created lazily; see `taskProgressWindow`.)
        taskProgressIndicator.setForeColor(.white)
        let progressIndicatorShadow = NSShadow()
        progressIndicatorShadow.shadowOffset = NSSize(width: 1.0, height: -1.0)
        progressIndicatorShadow.shadowBlurRadius = 1.0
        progressIndicatorShadow.shadowColor = NSColor(calibratedWhite: 0.0, alpha: 0.75)
        taskProgressIndicator.shadow = progressIndicatorShadow
    }

    // MARK: - Task lifecycle (driven by SPDatabaseDocument)

    /// Prepare the progress UI for a newly started task. `isFirstLevel` is
    /// true when the working level just moved from 0 to 1.
    @objc(beginTaskIsFirstLevel:)
    func beginTask(isFirstLevel: Bool) {

        // Reset the progress indicator if necessary
        if isFirstLevel || !taskDisplayIsIndeterminate {
            taskDisplayIsIndeterminate = true
            taskProgressIndicator.setIndeterminate(true)
            taskProgressIndicator.startAnimation(self)
            taskDisplayLastValue = 0
        }

        // If the working level just moved to start a task, set up the interface
        if isFirstLevel {
            taskCancelButton.isHidden = true

            // Schedule appearance of the task window in the near future, using a frame timer.
            taskFadeInStartDate = Date()
            queryStartDate = Date()
            taskDrawTimer = Timer.scheduledTimer(timeInterval: 1.0 / 30.0,
                                                 target: self,
                                                 selector: #selector(fadeInTaskProgressWindow(_:)),
                                                 userInfo: nil,
                                                 repeats: true)
            queryExecutionTimer = Timer.scheduledTimer(timeInterval: 1.0,
                                                       target: self,
                                                       selector: #selector(showQueryExecutionTime),
                                                       userInfo: nil,
                                                       repeats: true)
        }
    }

    /// Tear down the progress UI once all tasks have ended (working level
    /// back at 0).
    @objc func endTaskDisplay() {

        // Cancel the draw timer if it exists
        taskDrawTimer?.invalidate()

        if let queryExecutionTimer = queryExecutionTimer {
            queryStartDate = Date()
            showQueryExecutionTime()
            queryExecutionTimer.invalidate()
        }

        // Hide the task interface and reset to indeterminate
        if taskDisplayIsIndeterminate {
            taskProgressIndicator.stopAnimation(self)
        }
        taskProgressWindow.alphaValue = 0.0
        taskProgressWindow.orderOut(self)
        taskDisplayIsIndeterminate = true
        taskProgressIndicator.setIndeterminate(true)
    }

    // MARK: - Description & progress

    /// Updates the task description shown to the user.
    @objc(setTaskDescription:)
    func setTaskDescription(_ description: String) {
        taskDescriptionText.attributedStringValue = attributedString(description)
    }

    /// Sets the task percentage progress - the first call to this automatically
    /// switches the progress display to determinate.
    /// Can be called from background threads - forwards to main thread as appropriate.
    @objc(setTaskPercentage:)
    func setTaskPercentage(_ taskPercentage: CGFloat) {

        // If the task display is currently indeterminate, set it to determinate on the main thread.
        if taskDisplayIsIndeterminate {
            if !Thread.isMainThread {
                DispatchQueue.main.async { self.setTaskPercentage(taskPercentage) }
                return
            }

            taskDisplayIsIndeterminate = false
            taskProgressIndicator.stopAnimation(self)
            taskProgressIndicator.setDoubleValue(0.5)
        }

        // Check the supplied progress. Compare it to the display interval - how often
        // the interface is updated - and update the interface if the value has changed enough.
        taskProgressValue = taskPercentage
        if taskProgressValue >= taskDisplayLastValue + taskProgressValueDisplayInterval
            || taskProgressValue <= taskDisplayLastValue - taskProgressValueDisplayInterval {
            let value = Double(taskProgressValue)
            if Thread.isMainThread {
                taskProgressIndicator.setDoubleValue(value)
            } else {
                DispatchQueue.main.async { [weak self] in
                    self?.taskProgressIndicator.setDoubleValue(value)
                }
            }
            taskDisplayLastValue = taskProgressValue
        }
    }

    /// Sets the task progress indicator back to indeterminate (also performed
    /// automatically whenever a new task is started).
    /// This can optionally be called with afterDelay set, in which case the
    /// indeterminate switch will be made after a short pause to minimise
    /// flicker for short actions. Should be called on the main thread.
    @objc(setTaskProgressToIndeterminateAfterDelay:)
    func setTaskProgressToIndeterminate(afterDelay: Bool) {
        if afterDelay {
            perform(#selector(makeProgressIndeterminate), with: nil, afterDelay: 0.5)
            return
        }
        makeProgressIndeterminate()
    }

    @objc private func makeProgressIndeterminate() {
        if taskDisplayIsIndeterminate { return }
        // Cancel any delayed switch scheduled by setTaskProgressToIndeterminate(afterDelay:).
        // (The original ObjC cancelled against the indicator, but the delayed
        // perform is scheduled on self — so it never actually cancelled. Target
        // self + the matching selector so the pending call is really dropped.)
        NSObject.cancelPreviousPerformRequests(withTarget: self,
                                               selector: #selector(makeProgressIndeterminate),
                                               object: nil)
        taskDisplayIsIndeterminate = true
        taskProgressIndicator.setIndeterminate(true)
        taskProgressIndicator.startAnimation(self)
        taskDisplayLastValue = 0
    }

    /// Support pausing and restarting the task progress indicator.
    /// Only works while the indicator is in indeterminate mode.
    @objc(setTaskIndicatorShouldAnimate:)
    func setTaskIndicatorShouldAnimate(_ shouldAnimate: Bool) {
        let selector = shouldAnimate
            ? #selector(YRKSpinningProgressIndicator.startAnimation(_:))
            : #selector(YRKSpinningProgressIndicator.stopAnimation(_:))
        taskProgressIndicator.performSelector(onMainThread: selector, with: self, waitUntilDone: false)
    }

    // MARK: - Cancellation

    /// Allow a task to be cancelled, enabling the button with a supplied title
    /// and optionally supplying a callback object and function.
    /// The caller (document) guarantees a task is active before calling.
    ///
    /// - Important: `callbackFunction` must be a selector that takes no
    ///   arguments and returns void (e.g. `@objc func myCallback()`). It is
    ///   invoked via `perform(_:)` from `cancelTask(_:)`; a selector with
    ///   parameters or a return value is undefined behaviour.
    @objc(enableTaskCancellationWithTitle:callbackObject:callbackFunction:)
    func enableTaskCancellation(withTitle buttonTitle: String, callbackObject: NSObject?, callbackFunction: Selector?) {
        if let callbackObject = callbackObject, let callbackFunction = callbackFunction {
            taskCancellationCallbackObject = callbackObject
            taskCancellationCallbackSelector = callbackFunction
        }
        taskCanBeCancelled = true

        let colorTitle = NSAttributedString(string: buttonTitle,
                                            attributes: [.foregroundColor: NSColor.white])
        taskCancelButton.attributedTitle = colorTitle
        taskCancelButton.isEnabled = true
        taskCancelButton.isHidden = false
    }

    /// Disable task cancellation. Called automatically at the end of a task.
    /// The caller (document) guarantees a task is active before calling.
    @objc func disableTaskCancellation() {
        taskCanBeCancelled = false
        taskCancellationCallbackObject = nil
        taskCancellationCallbackSelector = nil
        taskCancelButton.isHidden = true
    }

    /// Action sent by the cancel button when it's active.
    @IBAction private func cancelTask(_ sender: Any?) {
        if !taskCanBeCancelled { return }

        taskCancelButton.isEnabled = false

        // The document cancels the running query (using the database-structure
        // connection where available, for speed - no connection overhead).
        delegate?.taskControllerDidRequestCancellation()

        // The callback selector is documented (on enableTaskCancellation) to be
        // a no-argument, void-returning method; guard against a non-responding
        // object rather than crashing.
        if let callbackObject = taskCancellationCallbackObject,
           let callbackSelector = taskCancellationCallbackSelector,
           callbackObject.responds(to: callbackSelector) {
            callbackObject.perform(callbackSelector)
        }
    }

    // MARK: - Query-execution timer

    /// Reset the query-execution timer's start date (e.g. after a
    /// connection-lost dialog is dismissed).
    @objc func resetQueryTimer() {
        queryStartDate = Date()
    }

    /// Show query execution time on the progress window.
    @objc func showQueryExecutionTime() {
        guard let queryStartDate = queryStartDate else { return }
        let timeSinceQueryStarted = Date().timeIntervalSince(queryStartDate)
        let queryRunningTime = DateComponentsFormatter.hourMinSecFormatter.string(from: timeSinceQueryStarted) ?? ""
        taskDurationTime.attributedStringValue = attributedString(queryRunningTime)
    }

    // MARK: - Window placement & teardown

    /// Reposition the task window within the parent window.
    @objc func centerInParentWindow() {
        guard let mainWindow = delegate?.taskParentWindow() else { return }
        let mainWindowRect = mainWindow.frame
        let taskWindowRect = taskProgressWindow.frame

        var newBottomLeftPoint = NSPoint.zero
        newBottomLeftPoint.x = (mainWindowRect.origin.x + mainWindowRect.size.width / 2 - taskWindowRect.size.width / 2).rounded()
        newBottomLeftPoint.y = (mainWindowRect.origin.y + mainWindowRect.size.height / 2 - taskWindowRect.size.height / 2).rounded()

        taskProgressWindow.setFrameOrigin(newBottomLeftPoint)
    }

    /// Tear down the progress window and timers on document close.
    @objc func shutDown() {
        taskProgressWindow.close()
        taskDrawTimer?.invalidate()
        queryExecutionTimer?.invalidate()
    }

    /// Show the task progress window, after a small delay to minimise flicker.
    @objc private func fadeInTaskProgressWindow(_ theTimer: Timer) {
        guard let taskFadeInStartDate = taskFadeInStartDate else { return }
        let timeSinceFadeInStart = Date().timeIntervalSince(taskFadeInStartDate)

        // Keep the window hidden for the first ~0.5 secs
        if timeSinceFadeInStart < 0.5 { return }

        if taskProgressWindow.parent == nil {
            delegate?.taskParentWindow()?.addChildWindow(taskProgressWindow, ordered: .above)
        }

        var alphaValue = taskProgressWindow.alphaValue

        // If the task progress window is still hidden, center it before revealing it
        if alphaValue == 0 { centerInParentWindow() }

        // Fade in the task window over 0.6 seconds
        alphaValue = CGFloat((timeSinceFadeInStart - 0.5) / 0.6)
        if alphaValue > 1.0 { alphaValue = 1.0 }
        taskProgressWindow.alphaValue = alphaValue

        // If the window has been fully faded in, clean up the timer.
        if alphaValue == 1.0 {
            taskDrawTimer?.invalidate()
        }
    }

    // MARK: - Helpers

    /// Builds the bold, shadowed attributed string used for both the task
    /// description and the query-duration labels.
    private func attributedString(_ string: String) -> NSAttributedString {
        let textShadow = NSShadow()
        textShadow.shadowColor = NSColor(calibratedWhite: 0.0, alpha: 0.75)
        textShadow.shadowOffset = NSSize(width: 1.0, height: -1.0)
        textShadow.shadowBlurRadius = 3.0

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 13.0),
            .shadow: textShadow
        ]
        return NSAttributedString(string: string, attributes: attributes)
    }
}
