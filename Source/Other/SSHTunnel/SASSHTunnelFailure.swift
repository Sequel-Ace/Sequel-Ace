//
//  SASSHTunnelFailure.swift
//  Sequel Ace
//

/// Carries the user-facing SSH error and OpenSSH output together across the
/// connection-service boundary so callers can classify and present failures.
struct SASSHTunnelFailure {
    let message: String
    let debugMessages: String

    var errorDetail: String? {
        debugMessages.isEmpty ? nil : debugMessages
    }
}
