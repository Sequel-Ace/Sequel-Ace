//
//  NSAlertExtension.swift
//  Sequel Ace
//
//  Created by Jakub Kaspar on 05.07.2020.
//  Copyright © 2020-2022 Sequel-Ace. All rights reserved.
//

import AppKit

@objc extension NSAlert {
	/// Creates an alert with primary colored button (also accepts "Enter" key) and cancel button (also accepts escape key), main title and informative subtitle message.
	/// - Parameters:
	///   - title: String for title of the alert
	///   - message: String for informative message
	///   - primaryButtonTitle: String for main confirm button
	///   - primaryButtonHandler: Optional block that's invoked when user hits primary button or Enter
	///   - cancelButtonHandler: Optional block that's invoked when user hits cancel button or Escape
	/// - Returns: Nothing
	static func createDefaultAlert(title: String,
								   message: String,
								   primaryButtonTitle: String,
								   primaryButtonHandler: (() -> ())? = nil,
								   cancelButtonHandler: (() -> ())? = nil) {

        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            // Order of buttons matters! first button has "firstButtonReturn" return value from runModal()
            alert.addButton(withTitle: primaryButtonTitle)
            alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "cancel button"))
            if alert.runModal() == .alertFirstButtonReturn {
                primaryButtonHandler?()
            } else {
                cancelButtonHandler?()
            }
        }
	}

	/// Creates an alert with primary colored button (also accepts "Enter" key) and cancel button (also accepts escape key), main title and informative subtitle message, and showsSuppressionButton
	/// - Parameters:
	///   - title: String for title of the alert
	///   - message: String for informative message
	///   - suppressionKey: String key to set in user defaults
	///   - primaryButtonTitle: String for main confirm button
	///   - primaryButtonHandler: Optional block that's invoked when user hits primary button or Enter
	///   - cancelButtonHandler: Optional block that's invoked when user hits cancel button or Escape
	/// - Returns: Nothing
	static func createDefaultAlertWithSuppression(title: String,
												  message: String,
                                                  suppressionKey: String? = nil,
												  primaryButtonTitle: String,
												  primaryButtonHandler: (() -> ())? = nil,
												  cancelButtonHandler: (() -> ())? = nil) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message

            if suppressionKey != nil {
                alert.showsSuppressionButton = true
            }
            // Order of buttons matters! first button has "firstButtonReturn" return value from runModal()
            alert.addButton(withTitle: primaryButtonTitle)
            alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "cancel button"))

            if alert.runModal() == .alertFirstButtonReturn {
                primaryButtonHandler?()
            } else {
                cancelButtonHandler?()
            }

            // if they check the box, set the bool
            if let suppressionButton = alert.suppressionButton, let suppressionKey = suppressionKey,
               suppressionButton.state == .on {
                UserDefaults.standard.set(true, forKey: suppressionKey)
            }
        }
	}

	/// Creates an alert with primary colored button (also accepts "Enter" key) and secondary colored button (also accepts escape key), main title and informative subtitle message.
	/// - Parameters:
	///   - title: String for title of the alert
	///   - message: String for informative message
	///   - primaryButtonTitle: String for main button
	///   - secondaryButtonTitle: String for secondary button
	///   - primaryButtonHandler: Optional block that's invoked when user hits primary button or Enter
	///   - secondaryButtonHandler: Optional block that's invoked when user hits cancel button or Escape
	/// - Returns: Nothing
	static func createAlert(title: String,
							message: String,
							primaryButtonTitle: String,
							secondaryButtonTitle: String,
							primaryButtonHandler: (() -> ())? = nil,
							secondaryButtonHandler: (() -> ())? = nil) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            // Order of buttons matters! first button has "firstButtonReturn" return value from runModal()
            alert.addButton(withTitle: primaryButtonTitle)
            alert.addButton(withTitle: secondaryButtonTitle)
            if alert.runModal() == .alertFirstButtonReturn {
                primaryButtonHandler?()
            } else {
                secondaryButtonHandler?()
            }
        }
	}


	/// Creates an alert with primary colored OK button that triggers callback
	/// - Parameters:
	///   - title: String for title of the alert
	///   - message: string for informative message
	///   - callback: Optional block that's invoked when user hits OK button
	static func createWarningAlert(title: String,
								   message: String,
								   callback: (() -> ())? = nil) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = title
            alert.informativeText = message
            alert.addButton(withTitle: NSLocalizedString("OK", comment: "OK button"))
            alert.runModal()
            callback?()
        }
	}

    /// Creates an informational alert with primary colored OK button that triggers callback
    /// - Parameters:
    ///   - title: String for title of the alert
    ///   - message: string for informative message
    ///   - callback: Optional block that's invoked when user hits OK button
    static func createInfoAlert(title: String,
                                   message: String,
                                   callback: (() -> ())? = nil) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = title
            alert.informativeText = message
            alert.addButton(withTitle: NSLocalizedString("OK", comment: "OK button"))
            alert.runModal()
            callback?()
        }
    }

	/// Creates an alert with primary colored button (also accepts "Enter" key) and cancel button (also accepts escape key), main title, informative subtitle message and accessory view.
	/// - Parameters:
	///   - title: String for title of the alert
	///   - message: String for informative message
	///   - accessoryView: NSView to be used as accessory view
	///   - primaryButtonTitle: String for main confirm button
	///   - primaryButtonHandler: Optional block that's invoked when user hits primary button or Enter
	///   - cancelButtonHandler: Optional block that's invoked when user hits cancel button or Escape
	/// - Returns: Nothing
	static func createAccessoryAlert(title: String,
									 message: String,
									 accessoryView: NSView,
									 primaryButtonTitle: String,
									 primaryButtonHandler: (() -> ())? = nil,
									 cancelButtonHandler: (() -> ())? = nil) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.accessoryView = accessoryView
            // Order of buttons matters! first button has "firstButtonReturn" return value from runModal()
            alert.addButton(withTitle: primaryButtonTitle)
            alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "cancel button"))
            if alert.runModal() == .alertFirstButtonReturn {
                primaryButtonHandler?()
            } else {
                cancelButtonHandler?()
            }
        }
	}

	/// Creates an alert with primary colored button (also accepts "Enter" key) and cancel button (also accepts escape key), main title, informative subtitle message and accessory view.
	/// - Parameters:
	///   - title: String for title of the alert
	///   - message: String for informative message
	///   - accessoryView: NSView to be used as accessory view
	///   - callback: Optional block that's invoked when user hits OK button
	/// - Returns: Nothing
	static func createAccessoryWarningAlert(title: String,
											message: String,
											accessoryView: NSView,
                                            callback: (() -> ())? = nil) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = title
            alert.informativeText = message
            alert.accessoryView = accessoryView
            alert.addButton(withTitle: NSLocalizedString("OK", comment: "OK button"))
            alert.runModal()
            callback?()
        }
	}
}
