//
//  SASSHTunnelPromptCoordinator.swift
//  Sequel Ace
//
//  Created by the Sequel Ace team on September 2, 2026.
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
//  More info at <https://github.com/Sequel-Ace/Sequel-Ace>

import Foundation

/// The teardown side of the SSH tunnel's askpass prompts (SSH tunnel IPC
/// plan, Step 1): decides, on the main thread, whether a prompt may be
/// shown and how a prompt already in flight is failed closed when the
/// tunnel goes away. `SPSSHTunnel` keeps only the AppKit-facing pieces —
/// the sheets, their modal sessions and the ivars they answer into — and
/// hands this object a closure that performs the actual dismissal.
///
/// The timing it guards against: a prompt request takes the answer lock on
/// the main thread, then queues a worker that shows the sheet; teardown can
/// arrive between those two moments, when there is no sheet to dismiss but
/// a sheet is about to appear. So teardown either dismisses the presented
/// sheet, or — if the answer lock is held with nothing presented — latches
/// a cancellation the worker consumes instead of presenting. A worker also
/// refuses to present once ssh has exited: nobody would read the answer.
///
/// Compiled into the app and the Unit Tests target (pure Foundation).
@objc final class SASSHTunnelPromptCoordinator: NSObject {

    typealias Dismisser = () -> Void

    private let answerLock: NSLock
    private let runOnMain: (@escaping () -> Void) -> Void

    // Main-thread state.
    private var dismisser: Dismisser?
    private var teardownRequested = false
    private var invalidated = false

    /// `answerLock` is the tunnel's answer-available lock: taken on the main
    /// thread when a prompt starts, released when it is answered or dismissed.
    @objc(initWithAnswerLock:)
    convenience init(answerLock: NSLock) {
        self.init(answerLock: answerLock, runOnMain: { DispatchQueue.main.async(execute: $0) })
    }

    init(answerLock: NSLock, runOnMain: @escaping (@escaping () -> Void) -> Void) {
        self.answerLock = answerLock
        self.runOnMain = runOnMain
    }

    // MARK: - Worker side (main thread)

    /// Called by a prompt's worker before it shows anything. False when
    /// teardown asked for cancellation first, or when ssh is no longer
    /// running; consumes the latch either way.
    @objc(shouldPresentPromptWhileSSHRunning:)
    func shouldPresentPrompt(whileSSHRunning sshRunning: Bool) -> Bool {
        let tornDown = teardownRequested || !sshRunning
        teardownRequested = false
        return !tornDown
    }

    /// Called right before the sheet's modal session starts, with the
    /// closure that ends it (end sheet, abort modal, release the answer
    /// lock with a "no"/nil answer).
    @objc(promptDidPresentWithDismisser:)
    func promptDidPresent(dismisser: @escaping Dismisser) {
        self.dismisser = dismisser
    }

    /// The user answered or cancelled the sheet themselves.
    @objc func promptDidClose() {
        dismisser = nil
    }

    /// A new connection attempt: nothing from the previous one may linger.
    @objc func reset() {
        teardownRequested = false
    }

    /// From the tunnel's dealloc, before it disconnects: no prompt can be in
    /// flight then, and no work capturing the tunnel may be dispatched.
    @objc func invalidate() {
        invalidated = true
    }

    @objc var isPresenting: Bool { dismisser != nil }

    // MARK: - Teardown side (any thread)

    /// Fails any prompt closed: dismisses a presented sheet, or latches the
    /// cancellation for a prompt that has started but not yet presented. A
    /// no-op when nothing is in flight, so it is safe to call from every
    /// teardown path.
    @objc func cancelPendingPrompt() {
        if invalidated { return }
        runOnMain { [self] in
            if let dismisser {
                self.dismisser = nil
                dismisser()
                return
            }
            // A prompt in flight holds the answer lock (taken on the main
            // thread); a free lock means nothing to cancel.
            if answerLock.try() {
                answerLock.unlock()
                return
            }
            teardownRequested = true
        }
    }
}
