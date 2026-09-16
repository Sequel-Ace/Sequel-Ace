//
//  SAMainRunLoop.swift
//  Sequel Ace
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import Foundation

/// Runs work on the main thread and waits for it, by way of the main run loop.
///
/// Connection work runs on a thread of its own while the main thread waits for it, and that wait
/// can itself be inside a block on the main queue - a queue that runs one block at a time and so
/// never gets to another one until the wait ends. `DispatchQueue.main.sync` from the connection's
/// thread would then wait for a wait that is waiting for it.
///
/// The main run loop keeps turning during that wait, and a run loop block does not depend on the
/// main queue being free. Anything a connection needs from the main thread goes this way.
enum SAMainRunLoop {

    /// Runs a block on the main thread and returns once it has finished.
    /// - Parameter block: The work to do on the main thread.
    static func runAndWait(_ block: @escaping () -> Void) {
        if Thread.isMainThread {
            block()
            return
        }

        let finished = DispatchSemaphore(value: 0)
        RunLoop.main.perform(inModes: [.common]) {
            block()
            finished.signal()
        }

        // A block handed to a run loop does not wake it; a run loop that is asleep would only
        // notice the block the next time something else woke it.
        CFRunLoopWakeUp(CFRunLoopGetMain())
        finished.wait()
    }
}
