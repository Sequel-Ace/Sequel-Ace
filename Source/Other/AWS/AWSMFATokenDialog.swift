//
//  AWSMFATokenDialog.swift
//  Sequel Ace
//
//  Created for AWS IAM authentication support with MFA.
//  Copyright (c) 2024 Sequel-Ace. All rights reserved.
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

import AppKit
import OSLog

/// Dialog for prompting the user for their AWS MFA token code
@objc final class AWSMFATokenDialog: NSObject {

    private static let log = OSLog(subsystem: "com.sequel-ace.sequel-ace", category: "AWSMFADialog")

    /// Prompt the user for an MFA token code
    /// - Parameters:
    ///   - profileName: The AWS profile name requiring MFA
    ///   - mfaSerial: The MFA device serial number
    ///   - parentWindow: Optional parent window for the dialog
    /// - Returns: The entered MFA token code, or nil if cancelled
    @objc static func promptForMFAToken(
        profile profileName: String?,
        mfaSerial: String?,
        parentWindow: NSWindow?
    ) -> String? {
        var result: String?

        let showDialog = {
            result = self.showMFADialog(
                profileName: profileName ?? "default",
                mfaSerial: mfaSerial ?? "unknown"
            )
        }

        if Thread.isMainThread {
            showDialog()
        } else {
            DispatchQueue.main.sync {
                showDialog()
            }
        }

        return result
    }

    /// Show the MFA dialog and return the token (must be called on main thread)
    private static func showMFADialog(profileName: String, mfaSerial: String) -> String? {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString(
            "AWS MFA Authentication Required",
            comment: "MFA dialog title"
        )
        alert.informativeText = String(
            format: NSLocalizedString(
                "Profile: %@\nMFA Device: %@\n\nEnter your 6-digit MFA code from your authenticator app:",
                comment: "MFA dialog message"
            ),
            profileName,
            mfaSerial
        )
        alert.alertStyle = .informational

        // Create the accessory view with the text field
        let tokenField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        tokenField.placeholderString = "123456"
        tokenField.alignment = .center
        tokenField.font = NSFont.monospacedSystemFont(ofSize: 18, weight: .medium)

        alert.accessoryView = tokenField

        // Add buttons
        alert.addButton(withTitle: NSLocalizedString("Authenticate", comment: "MFA authenticate button"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "cancel button"))

        // Make the text field the first responder
        alert.window.initialFirstResponder = tokenField

        // Run the modal with retry loop (not recursion)
        while true {
            let response = alert.runModal()

            guard response == .alertFirstButtonReturn else {
                // User cancelled
                return nil
            }

            let token = tokenField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

            // Validate the token (should be 6 digits)
            if isValidMFAToken(token) {
                return token
            }

            // Invalid token - show error and let them retry
            showInvalidTokenAlert()
            tokenField.stringValue = ""
        }
    }

    /// Validate MFA token format (6 digits)
    private static func isValidMFAToken(_ token: String) -> Bool {
        guard token.count == 6 else { return false }
        return token.allSatisfy { $0.isNumber }
    }

    /// Show an alert for invalid MFA token
    private static func showInvalidTokenAlert() {
        let errorAlert = NSAlert()
        errorAlert.messageText = NSLocalizedString(
            "Invalid MFA Code",
            comment: "Invalid MFA code title"
        )
        errorAlert.informativeText = NSLocalizedString(
            "Please enter a valid 6-digit MFA code.",
            comment: "Invalid MFA code message"
        )
        errorAlert.alertStyle = .warning
        errorAlert.addButton(withTitle: NSLocalizedString("OK", comment: "OK button"))
        errorAlert.runModal()
    }
}
