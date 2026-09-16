//
//  SAConnectionCheckSheet.swift
//  Sequel Ace
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import AppKit

/// The wait a window shows while its connection is busy with something that takes seconds.
///
/// Connection work used to run on the main thread, which left the window unable to draw and the
/// system drawing its own waiting cursor over the application. The work now runs on a thread of
/// its own, and the waiting happens here: an event loop that keeps the window answering, a word
/// about what is being waited for, and a button that ends the wait.
///
/// The event loop is a modal session rather than a bare run loop. Turning a run loop keeps the
/// window drawing but leaves its events sitting in the queue, so the sheet would appear and then
/// ignore every click on it.
@objc(SAConnectionCheckSheet)
final class SAConnectionCheckSheet: NSObject {

    /// How long the loop sleeps between rounds of events, in microseconds.
    private static let eventLoopPause: useconds_t = 3_000

    private var sheetWindow: NSWindow?
    private var elapsedLabel: NSTextField?
    private var startDate: Date?
    private weak var presentingWindow: NSWindow?
    private weak var documentWindow: NSWindow?
    private var session: NSApplication.ModalSession?
    private var waitWasEnded = false
    private var waitWasCancelledByUser = false
    private var isSuspended = false

    /// Waits for connection work while keeping the window answering, and shows what it is waiting for.
    /// - Parameters:
    ///   - window: The window the work belongs to.
    ///   - isFinished: Reports whether the work has finished; asked repeatedly until it says yes.
    ///   - cancelHandler: Called if the user ends the wait, before this method returns.
    @objc(waitInWindow:untilFinished:whenCancelled:)
    func wait(in window: NSWindow?, untilFinished isFinished: @escaping () -> Bool, whenCancelled cancelHandler: (() -> Void)?) {
        guard !isFinished() else {
            return
        }

        waitWasEnded = false
        waitWasCancelledByUser = false
        isSuspended = false
        documentWindow = window
        present(on: window)

        while !isFinished() && !waitWasEnded {
            // Another sheet has taken the window for a question of its own. This wait gives the
            // window back for as long as that lasts, and asks for it again afterwards.
            if isSuspended {
                usleep(Self.eventLoopPause)
                continue
            }
            if sheetWindow == nil {
                present(on: documentWindow)
            }
            if let session {
                if NSApp.runModalSession(session) != .continue {
                    break
                }
            } else {
                // Nothing could be shown - no window, or none visible. The events still have to
                // be taken out of the queue and delivered, or the application stops answering
                // exactly as it did before any of this.
                while let event = NSApp.nextEvent(matching: .any, until: Date(), inMode: .default, dequeue: true) {
                    NSApp.sendEvent(event)
                }
            }
            updateElapsedTime()
            usleep(Self.eventLoopPause)
        }

        endSessionAndDismiss()

        if waitWasCancelledByUser {
            cancelHandler?()
        }
    }

    /// Ends the wait from outside, without counting as the user cancelling the work.
    @objc func endWait() {
        waitWasEnded = true
    }

    /// Gives the window up so another sheet can use it, and keeps waiting quietly meanwhile.
    ///
    /// A window holds one sheet at a time. A question the connection has to ask - whether to
    /// reconnect, say - is more important than a note about waiting, so the note steps aside
    /// rather than leaving both unanswerable.
    @objc func suspendForOtherSheet() {
        guard !isSuspended else {
            return
        }
        isSuspended = true
        endSessionAndDismiss()
    }

    /// Takes the window back after that other sheet is gone.
    @objc func resumeAfterOtherSheet() {
        isSuspended = false
    }

    /// Builds the sheet and puts it on the window.
    /// - Parameter window: The window to show it on, if it can still show one.
    private func present(on window: NSWindow?) {
        guard let window, window.isVisible, sheetWindow == nil else {
            return
        }

        let title = NSTextField(labelWithString: NSLocalizedString("Waiting for the server…", comment: "connection wait sheet title"))
        title.font = .boldSystemFont(ofSize: NSFont.systemFontSize)

        let elapsed = NSTextField(labelWithString: "")
        elapsed.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        elapsed.textColor = .secondaryLabelColor
        elapsedLabel = elapsed

        let progress = NSProgressIndicator()
        progress.style = .bar
        progress.isIndeterminate = true
        progress.startAnimation(nil)

        let cancelButton = NSButton(
            title: NSLocalizedString("Stop Waiting", comment: "connection wait sheet cancel button"),
            target: self,
            action: #selector(cancelButtonPressed)
        )
        cancelButton.keyEquivalent = "\u{1b}"

        let buttonRow = NSStackView(views: [NSView(), cancelButton])
        buttonRow.orientation = .horizontal

        let content = NSStackView(views: [title, elapsed, progress, buttonRow])
        content.orientation = .vertical
        content.alignment = .leading
        content.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        content.spacing = 12
        content.translatesAutoresizingMaskIntoConstraints = false

        let sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 150),
                             styleMask: [.titled],
                             backing: .buffered,
                             defer: true)
        sheet.contentView = content
        NSLayoutConstraint.activate([
            content.widthAnchor.constraint(equalToConstant: 380),
            progress.widthAnchor.constraint(equalToConstant: 340),
            buttonRow.widthAnchor.constraint(equalToConstant: 340)
        ])

        sheetWindow = sheet
        presentingWindow = window
        if startDate == nil {
            startDate = Date()
        }
        updateElapsedTime()

        window.beginSheet(sheet, completionHandler: nil)
        session = NSApp.beginModalSession(for: sheet)
    }

    /// Ends the event loop and takes the sheet down again.
    private func endSessionAndDismiss() {
        if let session {
            NSApp.endModalSession(session)
        }
        session = nil

        if let sheetWindow, let presentingWindow {
            presentingWindow.endSheet(sheetWindow)
            sheetWindow.orderOut(nil)
        }
        sheetWindow = nil
        presentingWindow = nil
        elapsedLabel = nil
    }

    /// Says how long the wait has lasted, so it is clear that something is still happening.
    private func updateElapsedTime() {
        guard let startDate, let elapsedLabel else {
            return
        }

        let seconds = Int(Date().timeIntervalSince(startDate))
        elapsedLabel.stringValue = String(
            format: NSLocalizedString("The server has not answered for %ld seconds.", comment: "connection wait sheet elapsed time, %ld is a number of seconds"),
            seconds
        )
    }

    /// Ends the wait when the button is pressed, which is the user asking for the work to stop.
    @objc private func cancelButtonPressed() {
        waitWasCancelledByUser = true
        waitWasEnded = true
    }
}
