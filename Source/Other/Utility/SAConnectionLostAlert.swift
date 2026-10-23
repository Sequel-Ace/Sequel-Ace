//
//  SAConnectionLostAlert.swift
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

/// Presents the connection lost sheet and reports whether to reconnect.
@objc final class SAConnectionLostAlert: NSObject {

    /// Runs the sheet in a nested modal loop, returning true when Reconnect was chosen.
    @objc(runModalForWindow:copy:)
    static func runModal(for window: NSWindow, copy: SAConnectionLostSheetCopy) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = copy.title
        alert.informativeText = copy.message
        alert.addButton(withTitle: SAConnectionLostSheetCopy.reconnectButtonTitle)
        alert.addButton(withTitle: SAConnectionLostSheetCopy.closeConnectionButtonTitle)
        alert.buttons.last?.keyEquivalent = "\u{1b}"

        alert.beginSheetModal(for: window) { response in
            NSApp.stopModal(withCode: response)
        }

        return NSApp.runModal(for: alert.window) == .alertFirstButtonReturn
    }
}
