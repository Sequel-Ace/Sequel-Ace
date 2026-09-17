//
//  SAConnectionCheckSheet.swift
//  Sequel Ace
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import AppKit
import SwiftUI

/// What the sheet of one wait shows.
enum SAConnectionWaitSheetState: Equatable {
    /// No sheet: the wait is over and about to return, it has stepped aside for a question, or a
    /// wait further in holds its window.
    case hidden
    /// The sheet counts the seconds and offers to stop.
    case waiting
    /// The wait is over, but the operation that waited cannot carry on before a wait further in
    /// ends. The sheet stays, with nothing left to press, so that nothing else starts in its window
    /// on top of that operation.
    case finishing
}

/// A wait, as far as deciding what its sheet shows is concerned.
struct SAConnectionWaitSheetInput {
    /// The window the wait belongs to, if it has one.
    let window: ObjectIdentifier?
    /// Whether the wait has stepped aside for another sheet on its window.
    let isSuspended: Bool
    /// Whether the work finished or the waiting was ended.
    let hasEnded: Bool
}

/// What the wait sheet says. The wait's event loop keeps it up to date.
final class SAConnectionCheckSheetModel: ObservableObject {
    /// The line under the title: how long the server has been silent, or why the sheet stays.
    @Published var detail = ""
    /// Whether the wait is over and the sheet only holds its window, with nothing left to press.
    @Published var isFinishing = false
    /// Stops the wait; called by the button.
    let stop: () -> Void

    /// Creates the model for one sheet.
    /// - Parameter stop: What the button does.
    init(stop: @escaping () -> Void) {
        self.stop = stop
    }
}

/// The content of the wait sheet.
struct SAConnectionCheckSheetView: View {
    /// What the sheet shows, and what its button does.
    @ObservedObject var model: SAConnectionCheckSheetModel

    /// The title, the detail line, a progress bar and the button to stop waiting.
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: NSLocalizedString("Waiting for the server…", comment: "connection wait sheet title"))
                .bold()
            // Two lines are kept free, so that a longer translation does not push the button out
            // of a sheet that was sized before the text arrived.
            Text(verbatim: model.detail)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2, reservesSpace: true)
            ProgressView()
                .progressViewStyle(.linear)
            HStack {
                Spacer()
                Button(NSLocalizedString("Stop Waiting", comment: "connection wait sheet cancel button"), action: model.stop)
                    .keyboardShortcut(.cancelAction)
                    .disabled(model.isFinishing)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}

/// The sheet window of one wait, hosting its SwiftUI content.
@objc final class SAConnectionCheckSheetWindowController: NSWindowController {

    /// Builds the sheet window around the content for a model.
    /// - Parameter model: What the sheet shows.
    convenience init(model: SAConnectionCheckSheetModel) {
        let hostingController = NSHostingController(rootView: SAConnectionCheckSheetView(model: model))
        let window = NSWindow(contentViewController: hostingController)
        window.styleMask = [.titled]
        window.isReleasedWhenClosed = false
        self.init(window: window)
    }
}

/// The wait a window shows while its connection is busy with something that takes seconds.
///
/// Connection work used to run on the main thread, which left the window unable to draw and the
/// system drawing its own waiting cursor over the application. The work now runs on a thread of
/// its own, and the waiting happens here: an event loop that keeps the window answering, a word
/// about what is being waited for, and a button that ends the wait.
///
/// The loop takes events out of the queue and delivers them itself. Turning a bare run loop keeps
/// the window drawing but leaves its events sitting in the queue, so the sheet would appear and
/// then ignore every click on it. It deliberately does not run a modal session either: that would
/// hold every other window of the application still as well, while only this document's window
/// has anything to wait for - and the sheet on it already keeps that one window from being used.
///
/// Because other windows keep working, one of them can start a wait of its own while this one is
/// still going, and that wait's loop runs inside this one's until it ends. Every loop therefore looks
/// after every wait that is going on, and the button stops the work there and then instead of when
/// the loops have unwound back to it. A wait that is over but still buried keeps its window
/// blocked until its own loop gets to return.
@objc(SAConnectionCheckSheet)
final class SAConnectionCheckSheet: NSObject {

    /// How long the loop sleeps between rounds of events, in microseconds.
    private static let eventLoopPause: useconds_t = 3_000

    /// The waits going on, innermost last. Only the main thread touches this.
    private static var activeWaits: [SAConnectionCheckSheet] = []

    private var sheetController: SAConnectionCheckSheetWindowController?
    private var sheetModel: SAConnectionCheckSheetModel?
    private var startDate: Date?
    private weak var presentingWindow: NSWindow?
    private weak var documentWindow: NSWindow?
    private var waitWasEnded = false
    private var isSuspended = false
    private var isFinished: (() -> Bool)?
    private var cancelHandler: (() -> Void)?

    /// Waits for connection work while keeping the window answering, and shows what it is waiting for.
    /// - Parameters:
    ///   - window: The window the work belongs to.
    ///   - isFinished: Reports whether the work has finished; asked repeatedly until it says yes.
    ///   - cancelHandler: Called once if the user ends the wait - as soon as they do, and always
    ///     before this method returns.
    @objc(waitInWindow:untilFinished:whenCancelled:)
    func wait(in window: NSWindow?, untilFinished isFinished: @escaping () -> Bool, whenCancelled cancelHandler: (() -> Void)?) {
        // The connection asks for the wait on the thread that handed its work over, which is always
        // the main thread; the work itself runs elsewhere.
        assert(Thread.isMainThread, "A connection wait runs on the main thread")
        guard !isFinished() else {
            return
        }

        waitWasEnded = false
        isSuspended = false

        // The time is counted from the start of this wait, even when its sheet can only be shown later.
        startDate = Date()
        documentWindow = window
        self.isFinished = isFinished
        self.cancelHandler = cancelHandler
        Self.activeWaits.append(self)
        defer {
            Self.activeWaits.removeAll { $0 === self }
            self.isFinished = nil
            self.cancelHandler = nil
        }

        Self.refreshActiveWaits()
        while !hasEnded {
            Self.deliverPendingEvents()
            Self.refreshActiveWaits()
            usleep(Self.eventLoopPause)
        }

        dismissSheet()
    }

    /// When the current wait started; the sheet counts the time from there.
    var waitStartDate: Date? {
        return startDate
    }

    /// Brings the sheet of every wait that is going on up to date.
    private static func refreshActiveWaits() {
        let waits = activeWaits
        let states = sheetStates(for: waits.map {
            SAConnectionWaitSheetInput(window: $0.documentWindow.map(ObjectIdentifier.init),
                                       isSuspended: $0.isSuspended,
                                       hasEnded: $0.hasEnded)
        })

        // Sheets come down first, so that a window they leave free can take the next one.
        for (wait, state) in zip(waits, states) where state == .hidden {
            wait.dismissSheet()
        }
        for (wait, state) in zip(waits, states) where state != .hidden {
            if wait.sheetController == nil {
                wait.present(on: wait.documentWindow)
            }
            if state == .finishing {
                wait.showFinishing()
            } else {
                wait.updateElapsedTime()
            }
        }
    }

    /// Decides what the sheets of the waits going on show.
    ///
    /// Only the innermost wait's loop is running; the others return once it has. A window shows one
    /// of these sheets at a time - the one of its innermost wait that has not stepped aside.
    /// - Parameter waits: The waits, outermost first.
    /// - Returns: What each wait's sheet shows, in the same order.
    static func sheetStates(for waits: [SAConnectionWaitSheetInput]) -> [SAConnectionWaitSheetState] {
        // Whether a wait would show a sheet if its window were its own.
        let wantsSheet = { (index: Int) -> Bool in
            let wait = waits[index]
            return !wait.isSuspended && !(wait.hasEnded && index == waits.count - 1)
        }

        // Whether a wait further in belongs to the same window, and counts as holding it.
        let heldFurtherIn = { (index: Int, counts: (Int) -> Bool) -> Bool in
            guard let window = waits[index].window else {
                return false
            }
            return waits.indices.contains { $0 > index && waits[$0].window == window && counts($0) }
        }

        return waits.indices.map { index in
            guard wantsSheet(index) else {
                return .hidden
            }
            if !waits[index].hasEnded {
                return heldFurtherIn(index, wantsSheet) ? .hidden : .waiting
            }

            // An ended wait says it waits for another window only when that is so. Beneath a wait
            // of its own window, that wait - or the code that ran it - has the window.
            return heldFurtherIn(index, { !waits[$0].isSuspended }) ? .hidden : .finishing
        }
    }

    /// Whether the wait is over, because the work finished or the waiting was ended.
    private var hasEnded: Bool {
        return waitWasEnded || (isFinished?() ?? true)
    }

    /// Gives the window up so another sheet can use it, and keeps waiting meanwhile.
    ///
    /// A window holds one sheet at a time. A question the connection has to ask - whether to
    /// reconnect, say - is more important than a note about waiting, so the note steps aside
    /// rather than leaving both unanswerable.
    /// - Parameter window: The window the other sheet is for; every wait on it steps aside.
    @objc(suspendWaitsInWindow:)
    static func suspendWaits(in window: NSWindow?) {
        for wait in activeWaits where wait.documentWindow === window {
            wait.isSuspended = true
            wait.dismissSheet()
        }
    }

    /// Takes the window back after that other sheet is gone.
    /// - Parameter window: The window the other sheet was for.
    @objc(resumeWaitsInWindow:)
    static func resumeWaits(in window: NSWindow?) {
        for wait in activeWaits where wait.documentWindow === window {
            wait.isSuspended = false
        }
    }

    /// Builds the sheet and puts it on the window.
    /// - Parameter window: The window to show it on, if it can still show one.
    private func present(on window: NSWindow?) {
        guard let window, window.isVisible, window.attachedSheet == nil, sheetController == nil else {
            return
        }

        let model = SAConnectionCheckSheetModel { [weak self] in
            self?.cancelButtonPressed()
        }
        sheetModel = model
        updateElapsedTime()

        let controller = SAConnectionCheckSheetWindowController(model: model)
        guard let sheet = controller.window else {
            sheetModel = nil
            return
        }

        sheetController = controller
        presentingWindow = window

        window.beginSheet(sheet, completionHandler: nil)
    }

    /// Takes the sheet down again.
    private func dismissSheet() {
        if let sheet = sheetController?.window, let presentingWindow {
            presentingWindow.endSheet(sheet)
            sheet.orderOut(nil)
        }
        sheetController = nil
        sheetModel = nil
        presentingWindow = nil
    }

    /// Says that the wait is over and the window is only held until another window's wait ends.
    private func showFinishing() {
        guard let sheetModel, !sheetModel.isFinishing else {
            return
        }
        sheetModel.isFinishing = true
        sheetModel.detail = NSLocalizedString(
            "Continues once the other window has finished waiting.",
            comment: "connection wait sheet note while a finished wait is held up by another window's wait"
        )
    }

    /// Takes the events that have arrived out of the queue and delivers them, without waiting for more.
    ///
    /// An event can run a wait of its own and return only once that wait is over. The sheets are
    /// brought up to date after every event, so the next one finds them as they should be.
    private static func deliverPendingEvents() {
        while let event = NSApp.nextEvent(matching: .any, until: Date(), inMode: .default, dequeue: true) {
            NSApp.sendEvent(event)
            refreshActiveWaits()
        }
    }

    /// Says how long the wait has lasted, so it is clear that something is still happening.
    private func updateElapsedTime() {
        guard let startDate, let sheetModel, !sheetModel.isFinishing else {
            return
        }

        // The loop comes by every few milliseconds; the sheet only changes once a second.
        let seconds = Int(Date().timeIntervalSince(startDate))
        let detail = String(
            format: NSLocalizedString("The server has not answered for %ld seconds.", comment: "connection wait sheet elapsed time, %ld is a number of seconds"),
            seconds
        )
        if sheetModel.detail != detail {
            sheetModel.detail = detail
        }
    }

    /// Ends the wait when the button is pressed, which is the user asking for the work to stop.
    ///
    /// The work is asked to stop right here. This wait's loop may be running beneath another one
    /// and only get to look at its state again once that one is over.
    @objc func cancelButtonPressed() {
        // A wait that is already over has nothing left to stop, even if its button was still shown.
        guard !hasEnded else {
            return
        }
        waitWasEnded = true

        let handler = cancelHandler
        cancelHandler = nil
        handler?()
    }
}
