//
//  SASSHTunnelFailure.swift
//  Sequel Ace
//

import Foundation

/// Carries the user-facing SSH error and OpenSSH output together across the
/// connection-service boundary so callers can classify and present failures.
struct SASSHTunnelFailure {
    let message: String
    let debugMessages: String

    var errorDetail: String? {
        debugMessages.isEmpty ? nil : debugMessages
    }
}

/// Coordinates the stderr-drain boundary for an SSH failure. OpenSSH output is
/// preferred through pipe EOF, with a bounded fallback for custom binaries or
/// descendants that retain the inherited stderr writer.
@objc final class SASSHStderrDrainCoordinator: NSObject {
    private static let defaultTimeout: TimeInterval = 5

    private let timeout: TimeInterval
    private let stateLock = NSLock()
    private var reachedEOF = false
    private var diagnosticsReady = true

    override convenience init() {
        self.init(timeout: Self.defaultTimeout)
    }

    init(timeout: TimeInterval) {
        self.timeout = timeout
        super.init()
    }

    @objc var failureDiagnosticsReady: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return diagnosticsReady
    }

    /// Atomically begins an attempt only after the prior diagnostics lifecycle
    /// has completed, preventing stale drain callbacks from reaching a new pipe.
    @objc func beginAttemptIfReady() -> Bool {
        stateLock.lock()
        guard diagnosticsReady else {
            stateLock.unlock()
            return false
        }
        reachedEOF = false
        diagnosticsReady = false
        stateLock.unlock()
        return true
    }

    @objc func finishWithoutStandardErrorPipe() {
        stateLock.lock()
        diagnosticsReady = true
        stateLock.unlock()
    }

    /// Returns whether the one-shot file-handle notification should be re-armed.
    @objc(recordStandardErrorReadWithByteCount:)
    func recordStandardErrorRead(byteCount: Int) -> Bool {
        stateLock.lock()
        if byteCount == 0 {
            reachedEOF = true
        }
        stateLock.unlock()
        return byteCount > 0
    }

    /// Drains the current thread's run loop until stderr reaches EOF or the
    /// bounded fallback expires. Returns whether EOF was observed.
    @objc func finishAfterStandardErrorDrain() -> Bool {
        let deadline = Date(timeIntervalSinceNow: timeout)

        while !hasReachedEOF && deadline.timeIntervalSinceNow > 0 {
            RunLoop.current.run(mode: .default, before: deadline)
        }

        stateLock.lock()
        diagnosticsReady = true
        let didReachEOF = reachedEOF
        stateLock.unlock()
        return didReachEOF
    }

    private var hasReachedEOF: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return reachedEOF
    }
}
