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

@objc enum SASSHAttemptRequestDisposition: Int {
    case start
    case queued
    case ignored
}

/// Coordinates the stderr-drain boundary for an SSH failure. OpenSSH output is
/// preferred through pipe EOF, with a bounded fallback for custom binaries or
/// descendants that retain the inherited stderr writer.
@objc final class SASSHStderrDrainCoordinator: NSObject {
    private enum Phase {
        case ready
        case running
        case draining
        case completing
    }

    private static let defaultTimeout: TimeInterval = 5

    private let timeout: TimeInterval
    private let stateLock = NSLock()
    private var reachedEOF = false
    private var phase = Phase.ready
    private var pendingAttempt = false

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
        return phase == .ready || phase == .completing
    }

    @objc var connectionAttemptPending: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return pendingAttempt
    }

    /// Atomically starts an idle tunnel, coalesces requests made while failure
    /// diagnostics drain, and ignores duplicate requests while SSH is running.
    @objc func requestAttempt() -> SASSHAttemptRequestDisposition {
        stateLock.lock()
        defer { stateLock.unlock() }

        switch phase {
        case .ready:
            reachedEOF = false
            phase = .running
            return .start
        case .running:
            return .ignored
        case .draining, .completing:
            pendingAttempt = true
            return .queued
        }
    }

    /// Marks the point after which an idle-state reconnect request must be
    /// retained until the current stderr pipe is finished.
    @objc func beginStandardErrorDrain() {
        stateLock.lock()
        if phase == .running {
            phase = .draining
        }
        stateLock.unlock()
    }

    @objc func finishWithoutStandardErrorPipe() {
        stateLock.lock()
        phase = .ready
        pendingAttempt = false
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
    /// bounded fallback expires. The coordinator remains in a completing phase
    /// so a reconnect cannot clear diagnostics before the delegate snapshots them.
    @objc func finishAfterStandardErrorDrain() -> Bool {
        let deadline = Date(timeIntervalSinceNow: timeout)

        while !hasReachedEOF && deadline.timeIntervalSinceNow > 0 {
            RunLoop.current.run(mode: .default, before: deadline)
        }

        stateLock.lock()
        let didReachEOF = reachedEOF
        phase = .completing
        stateLock.unlock()

        return didReachEOF
    }

    /// Ends the snapshot boundary and atomically reserves a queued reconnect.
    @objc func completeDrainNotificationAndReservePendingAttempt() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }

        guard phase == .completing else { return false }

        let shouldStartPendingAttempt = pendingAttempt
        pendingAttempt = false
        if shouldStartPendingAttempt {
            reachedEOF = false
            phase = .running
        } else {
            phase = .ready
        }
        return shouldStartPendingAttempt
    }

    private var hasReachedEOF: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return reachedEOF
    }
}
