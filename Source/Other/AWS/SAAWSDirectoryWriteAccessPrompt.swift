//
//  SAAWSDirectoryWriteAccessPrompt.swift
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

import AppKit
import OSLog

/// Asks the user to re-select the `.aws` folder with write access when a console
/// sign-in (`aws login`) profile needs it to renew its cached credentials.
@objc final class SAAWSDirectoryWriteAccessPrompt: NSObject {

    private static let log = OSLog(subsystem: "com.sequel-ace.sequel-ace", category: "AWSDirectoryBookmark")

    private static var declinedThisSession = false

    /// Shows an open panel on the `.aws` folder when `profileName` uses console sign-in and
    /// the folder is read-only; does nothing off the main thread or after the user declined.
    @objc(requestWriteAccessIfNeededForProfile:)
    static func requestWriteAccessIfNeeded(forProfile profileName: String?) {
        guard Thread.isMainThread, !declinedThisSession else { return }

        let trimmedProfile = profileName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let profile = try? AWSCredentials(profile: trimmedProfile.isEmpty ? "default" : trimmedProfile),
              AWSLoginCredentialsProvider.needsWriteAccessGrant(for: profile) else {
            return
        }

        let bookmarkManager = AWSDirectoryBookmarkManager.shared

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.showsHiddenFiles = true
        panel.directoryURL = bookmarkManager.authorizedAWSDirectoryURL
            ?? URL(fileURLWithPath: AWSDirectoryBookmarkManager.awsDirectoryPath, isDirectory: true)
        panel.message = NSLocalizedString("Allow Sequel Ace to update your .aws folder so it can renew your AWS console sign-in (aws login) credentials automatically.",
                                          comment: "AWS directory write access panel message")
        panel.prompt = NSLocalizedString("Allow", comment: "AWS directory write access panel button")

        guard panel.runModal() == .OK,
              let url = panel.url,
              bookmarkManager.isAWSDirectoryURL(url) else {
            declinedThisSession = true
            return
        }

        if !bookmarkManager.replaceAWSDirectoryBookmark(with: url) {
            log.error("Could not replace the AWS directory bookmark with a writable one", privacy: .visible)
        }
    }
}
