//
//  NSAlertExtension.swift
//  Sequel Ace
//
//  Created by Jakub Kaspar on 05.07.2020.
//  Copyright © 2020 Sequel-Ace. All rights reserved.
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

	/// Creates an alert with primary colored button (also accepts "Enter" key) and cancel button (also accepts escape key), main title and informative subtitle message, and showsSuppressionButton
	/// - Parameters:
	///   - title: String for title of the alert
	///   - message: String for informative message
	///   - suppression: Bool for showsSuppressionButton
	///   - primaryButtonTitle: String for main confirm button
	///   - primaryButtonHandler: Optional block that's invoked when user hits primary button or Enter
	///   - cancelButtonHandler: Optional block that's invoked when user hits cancel button or Escape
	/// - Returns: Nothing
	static func createDefaultAlertWithSuppression(title: String,
												  message: String,
												  suppression: Bool,
												  primaryButtonTitle: String,
												  primaryButtonHandler: (() -> ())? = nil,
												  cancelButtonHandler: (() -> ())? = nil) {
		let alert = NSAlert()
		alert.messageText = title
		alert.informativeText = message
		alert.showsSuppressionButton = suppression
		// Order of buttons matters! first button has "firstButtonReturn" return value from runModal()
		alert.addButton(withTitle: primaryButtonTitle)
		alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "cancel button"))
		
		if alert.runModal() == .alertFirstButtonReturn {
			primaryButtonHandler?()
		} else {
			cancelButtonHandler?()
		}
		
		// if they check the box, set the bool
		if let suppressionButton = alert.suppressionButton,
		   suppressionButton.state == .on {
			UserDefaults.standard.set(true, forKey: SPQuerySaveAlertSuppression)
		}
	}
	
	/// Creates an alert with primary colored OK button that triggers callback
	/// - Parameters:
	///   - title: String for title of the alert
	///   - message: tring for informative message
	///   - callback: Optional block that's invoked when user hits OK button
	static func createWarningAlert(title: String,
								   message: String,
								   callback: (() -> ())? = nil) {
		let alert = NSAlert()
		alert.alertStyle = .critical
		alert.messageText = title
		alert.informativeText = message
		alert.addButton(withTitle: NSLocalizedString("OK", comment: "OK button"))
		alert.runModal()
		callback?()
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
