//
//  SAAWSSignInCommand.swift
//  Sequel Ace
//
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

import Foundation

/// The AWS CLI commands that renew a profile's sign-in session, and the error
/// messages that name them.
enum SAAWSSignInCommand {

    /// `aws login` for `profile`, or for the `default` profile when `profile` is empty.
    static func login(profile: String?) -> String {
        "aws login --profile " + shellQuoted(profileName(profile))
    }

    /// `aws sso login` for `profile`, or for the `default` profile when `profile` is empty.
    static func ssoLogin(profile: String?) -> String {
        "aws sso login --profile " + shellQuoted(profileName(profile))
    }

    /// `value` quoted for a POSIX shell, or unchanged when it holds only characters a shell takes literally.
    static func shellQuoted(_ value: String) -> String {
        guard value.isEmpty || value.range(of: "[^A-Za-z0-9_@%+=:,./-]", options: .regularExpression) != nil else {
            return value
        }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// The command that renews the sign-in session behind `error` for `profile`, or nil when
    /// signing in again does not resolve `error`.
    static func command(for error: Error, profile: String?) -> String? {
        if let loginError = error as? AWSLoginAuthError {
            switch loginError {
            case .cacheNotFound, .sessionExpired, .invalidCacheContents:
                return login(profile: profile)
            case .invalidProfile:
                return nil
            }
        }

        if let refreshError = error as? SAAWSLoginRefreshError {
            switch refreshError {
            case .credentialsChanged, .grantRejected, .regionUnavailable, .writeAccessRequired, .invalidSigningKey, .cacheWriteFailed:
                return login(profile: profile)
            case .insufficientPermissions, .invalidResponse, .requestFailed:
                return nil
            }
        }

        if let ssoError = error as? AWSSSOClientError {
            switch ssoError {
            case .tokenNotFound, .tokenExpired:
                return ssoLogin(profile: profile)
            case .invalidProfile, .networkFailure, .invalidResponse, .accessDenied, .requestTimeout:
                return nil
            }
        }

        return nil
    }

    /// `error`'s description, followed by the command that renews the session for `profile` when there is one.
    static func message(for error: Error, profile: String?) -> String {
        let description = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let command = command(for: error, profile: profile) else {
            return description
        }

        let recovery = String(format: NSLocalizedString("Run `%@` in Terminal, then try again.",
                                                        comment: "AWS sign-in recovery; %@ is an AWS CLI command"),
                              command)
        guard !description.isEmpty else { return recovery }

        let sentence = description.hasSuffix(".") ? description : description + "."
        return sentence + " " + recovery
    }

    /// `error` as an NSError with the same domain and code, described by `message(for:profile:)`.
    static func presentableError(_ error: Error, profile: String?) -> NSError {
        let bridged = error as NSError
        var userInfo = bridged.userInfo
        userInfo[NSLocalizedDescriptionKey] = message(for: error, profile: profile)
        return NSError(domain: bridged.domain, code: bridged.code, userInfo: userInfo)
    }

    private static func profileName(_ profile: String?) -> String {
        let trimmed = profile?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "default" : trimmed
    }
}
