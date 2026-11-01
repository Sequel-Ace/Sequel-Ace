//
//  SASheetEnding.swift
//  Sequel Ace
//
//  Ends the sheets of a window that is closing. Shared with the Unit Tests target.
//

import AppKit

enum SASheetEnding {

    /// The response a sheet ended by the app gets. It is `.cancel`, what every Cancel button (tag 0) and an
    /// NSOpenPanel/NSSavePanel sheet give: handlers that test `if (returnCode)` or `returnCode ? completed :
    /// cancelled` (the table structure key sheet, the field mapper, the Open panel) read `.abort` as "proceed", and
    /// alert handlers that only recognise their Cancel button's own response proceed on it too.
    static let response = NSApplication.ModalResponse.cancel

    /// Ends every sheet of a closing window as cancelled: a pass over its sheets, newest first and a sheet's own
    /// sheets before it, repeated (at most three passes) while one is still attached, which covers a queued sheet
    /// presented when the one before it ended and one a completion handler began. Never spins.
    static func endAll(of window: NSWindow) {
        for _ in 0..<3 {
            guard window.attachedSheet != nil else { return }
            endPass(of: window)
        }
    }

    /// One pass. A sheet that a completion handler already ended (no parent any more) is skipped.
    private static func endPass(of window: NSWindow, depth: Int = 0) {
        guard depth < 4 else { return }
        for sheet in window.sheets.reversed() {
            endPass(of: sheet, depth: depth + 1)
            guard let parent = sheet.sheetParent else { continue }
            parent.endSheet(sheet, returnCode: response)
            sheet.orderOut(nil)
        }
    }
}
