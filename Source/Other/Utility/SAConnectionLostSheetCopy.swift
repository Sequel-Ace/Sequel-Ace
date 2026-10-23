//
//  SAConnectionLostSheetCopy.swift
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

/// Title and message shown by the connection lost sheet.
@objc final class SAConnectionLostSheetCopy: NSObject {

    @objc let title: String
    @objc let message: String

    init(title: String, message: String) {
        self.title = title
        self.message = message
        super.init()
    }

    // MARK: - Button Titles

    @objc static var reconnectButtonTitle: String {
        NSLocalizedString("Reconnect", comment: "Connection lost sheet: reconnect button")
    }

    @objc static var closeConnectionButtonTitle: String {
        NSLocalizedString("Close connection", comment: "Connection lost sheet: close connection button")
    }

    // MARK: - Copy

    /// Builds the sheet copy, naming the AWS CLI command that renews `awsProfile`'s session
    /// when a connection using AWS IAM authentication could not generate a new auth token.
    @objc(sheetCopyForAWSIAMTokenError:isAWSIAMConnection:awsProfile:)
    static func make(awsIAMTokenError error: NSError?, isAWSIAMConnection: Bool, awsProfile: String?) -> SAConnectionLostSheetCopy {
        guard isAWSIAMConnection, let error = error else {
            return SAConnectionLostSheetCopy(title: defaultTitle, message: defaultMessage)
        }

        if let command = awsSignInCommand(for: error as Error, profile: awsProfile) {
            return SAConnectionLostSheetCopy(title: awsSignInTitle,
                                             message: String(format: awsSignInMessageFormat, command))
        }

        let description = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)

        return SAConnectionLostSheetCopy(title: awsSignInTitle,
                                         message: String(format: awsTokenFailureMessageFormat,
                                                         description.isEmpty ? unknownErrorDescription : description))
    }

    /// Returns the AWS CLI command that renews `profile`'s session for this error, or nil
    /// when the error is not a lapsed session. An empty profile means the `default` profile.
    static func awsSignInCommand(for error: Error, profile: String?) -> String? {
        switch signInKind(for: error) {
        case .consoleSignIn:
            return SAAWSSignInCommand.login(profile: profile)
        case .identityCenter:
            return SAAWSSignInCommand.ssoLogin(profile: profile)
        case nil:
            return nil
        }
    }

    private enum SignInKind {
        case consoleSignIn
        case identityCenter
    }

    private static func signInKind(for error: Error) -> SignInKind? {
        if let loginError = error as? AWSLoginAuthError {
            return isLapsed(loginError) ? .consoleSignIn : nil
        }

        if let ssoError = error as? AWSSSOClientError {
            return isLapsed(ssoError) ? .identityCenter : nil
        }

        // An error carried through Objective-C can arrive as a plain NSError, which
        // keeps the originating type only in its domain.
        let bridged = error as NSError

        if bridged.domain.hasSuffix("AWSLoginAuthError"), let loginError = AWSLoginAuthError(rawValue: bridged.code) {
            return isLapsed(loginError) ? .consoleSignIn : nil
        }

        if bridged.domain.hasSuffix("AWSSSOClientError"), let ssoError = AWSSSOClientError(rawValue: bridged.code) {
            return isLapsed(ssoError) ? .identityCenter : nil
        }

        return nil
    }

    private static func isLapsed(_ error: AWSLoginAuthError) -> Bool {
        switch error {
        case .sessionExpired, .cacheNotFound:
            return true
        case .invalidProfile, .invalidCacheContents:
            return false
        }
    }

    private static func isLapsed(_ error: AWSSSOClientError) -> Bool {
        switch error {
        case .tokenExpired, .tokenNotFound:
            return true
        case .invalidProfile, .networkFailure, .invalidResponse, .accessDenied, .requestTimeout:
            return false
        }
    }

    // MARK: - Strings

    static var defaultTitle: String {
        NSLocalizedString("Connection Lost", comment: "Connection lost sheet: default title")
    }

    static var defaultMessage: String {
        NSLocalizedString("Sequel Ace appears to have lost the connection to the server, or the server has stopped responding.",
                          comment: "Connection lost sheet: default message")
    }

    static var awsSignInTitle: String {
        NSLocalizedString("AWS Sign-In Required", comment: "Connection lost sheet: title when the AWS session has lapsed")
    }

    static var awsSignInMessageFormat: String {
        NSLocalizedString("Sequel Ace lost the connection to the server and cannot reconnect until you sign in to AWS again.\n\nIn Terminal, run `%@`, then click Reconnect.",
                          comment: "Connection lost sheet: message when the AWS session has lapsed; %@ is an AWS CLI command")
    }

    static var awsTokenFailureMessageFormat: String {
        NSLocalizedString("Sequel Ace lost the connection to the server and could not create a new RDS IAM authentication token:\n%@\n\nFix the AWS credentials, then click Reconnect.",
                          comment: "Connection lost sheet: message when an AWS IAM token could not be generated; %@ is the AWS error description")
    }

    static var unknownErrorDescription: String {
        NSLocalizedString("Unknown AWS IAM error", comment: "Connection lost sheet: fallback AWS error description")
    }
}
