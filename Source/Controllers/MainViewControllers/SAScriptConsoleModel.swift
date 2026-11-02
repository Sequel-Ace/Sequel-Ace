//
//  SAScriptConsoleModel.swift
//  Sequel Ace
//
//  Output buffer for the "Run All as Script" console. The script runner
//  appends from its background thread; chunks are coalesced and delivered on
//  the main thread at most every `flushInterval`, so a large result set does
//  not flood the UI. The text is deliberately not published to SwiftUI: the
//  console's NSTextView subscribes to `appended` and appends only the delta.
//

import Combine
import Foundation

final class SAScriptConsoleModel {

    static let continueOnErrorDefaultsKey = "ScriptConsoleContinueOnError"

    /// Full output so far (main thread). Read by Copy All / Save Output….
    private(set) var text = ""

    /// Emits each flushed chunk on the main thread.
    let appended = PassthroughSubject<String, Never>()

    /// Emits when the console is cleared, on the main thread.
    let cleared = PassthroughSubject<Void, Never>()

    private let flushInterval: TimeInterval
    private let lock = NSLock()
    private var pending = ""
    private var flushScheduled = false

    /// Structured output for the statement-block console (main thread).
    private(set) var eventLog: [SAScriptConsoleEvent] = []
    /// Batches of events in arrival order, published with the text flush.
    let eventsAppended = PassthroughSubject<[SAScriptConsoleEvent], Never>()
    private var pendingEvents: [SAScriptConsoleEvent] = []

    init(flushInterval: TimeInterval = 0.1) {
        self.flushInterval = flushInterval
    }

    /// Queue `chunk` for display. Safe to call from any thread.
    func append(_ chunk: String) {
        guard !chunk.isEmpty else { return }
        lock.lock()
        pending += chunk
        let needsSchedule = !flushScheduled
        flushScheduled = true
        lock.unlock()

        if needsSchedule {
            DispatchQueue.main.asyncAfter(deadline: .now() + flushInterval) { [weak self] in
                self?.flush()
            }
        }
    }

    /// Queue a structured event. Any thread.
    func append(event: SAScriptConsoleEvent) {
        lock.lock()
        pendingEvents.append(event)
        let needsSchedule = !flushScheduled
        flushScheduled = true
        lock.unlock()
        if needsSchedule {
            DispatchQueue.main.asyncAfter(deadline: .now() + flushInterval) { [weak self] in self?.flush() }
        }
    }

    /// Move pending output into `text` and publish it. Main thread only.
    func flush() {
        lock.lock()
        let chunk = pending
        pending = ""
        let events = pendingEvents
        pendingEvents = []
        flushScheduled = false
        lock.unlock()

        if !chunk.isEmpty {
            text += chunk
            appended.send(chunk)
        }
        if !events.isEmpty {
            eventLog += events
            eventsAppended.send(events)
        }
    }

    /// Drop all output, including anything not yet flushed. Main thread only.
    func clear() {
        lock.lock()
        pending = ""
        pendingEvents = []
        lock.unlock()
        text = ""
        eventLog = []
        cleared.send()
    }
}
