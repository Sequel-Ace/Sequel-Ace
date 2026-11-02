//
//  SAMainRunLoop.swift
//  SPMySQLFramework
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//
//  More info at <https://github.com/Sequel-Ace/Sequel-Ace>
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
/// main queue being free. Anything connection work needs from the main thread - a tunnel told to
/// go, a dialog the application shows for it, an error it shows - goes this way.
@objc(SAMainRunLoop)
public final class SAMainRunLoop: NSObject {

    /// Runs a block on the main thread and returns once it has finished.
    /// - Parameter block: The work to do on the main thread.
    @objc(runAndWait:)
    public static func runAndWait(_ block: @escaping () -> Void) {
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
