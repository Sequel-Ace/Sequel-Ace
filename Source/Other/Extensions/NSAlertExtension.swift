//
//  NSAlertExtension.swift
//  Sequel Ace
//
//  Created by Jakub Kaspar on 05.07.2020.
//  Copyright © 2020-2022 Sequel-Ace. All rights reserved.
//

import AppKit

enum SABookmarkPathNormalizer {
    static func normalizedFilePath(forBookmarkPath bookmarkPath: String) -> String? {
        guard let filePath = filePath(forBookmarkPath: bookmarkPath) else {
            return nil
        }

        return URL(fileURLWithPath: filePath).standardizedFileURL.path
    }

    static func displayName(forBookmarkPath bookmarkPath: String) -> String {
        let displayPath = filePath(forBookmarkPath: bookmarkPath) ?? (bookmarkPath.removingPercentEncoding ?? bookmarkPath)
        let lastPathComponent = (displayPath as NSString).lastPathComponent
        return lastPathComponent.isEmpty ? displayPath : lastPathComponent
    }

    private static func filePath(forBookmarkPath bookmarkPath: String) -> String? {
        let fileSchemePrefix = "file://"

        if bookmarkPath.hasPrefix(fileSchemePrefix) {
            let encodedPath = String(bookmarkPath.dropFirst(fileSchemePrefix.count))
            guard encodedPath.hasPrefix("/") else {
                return nil
            }

            return encodedPath.removingPercentEncoding ?? encodedPath
        }

        let decodedBookmarkPath = bookmarkPath.removingPercentEncoding ?? bookmarkPath
        guard decodedBookmarkPath.hasPrefix("/") else {
            return nil
        }

        return decodedBookmarkPath
    }
}

@objc final class SABookmarkAlertContent: NSObject {
    @objc static func displayNames(forBookmarkPaths bookmarkPaths: [String]) -> [String] {
        return bookmarkPaths.map { displayName(forBookmarkPath: $0) }
    }

    @objc static func staleBookmarksMessage(count: Int) -> String {
        if count == 1 {
            return NSLocalizedString("Sequel Ace found 1 stale secure bookmark. You can continue launching now, or open Files preferences to refresh or revoke it.", comment: "single stale bookmark alert message")
        }

        let format = NSLocalizedString("Sequel Ace found %d stale secure bookmarks. You can continue launching now, or open Files preferences to refresh or revoke them.", comment: "multiple stale bookmarks alert message")
        return String.localizedStringWithFormat(format, count)
    }

    @objc static func missingBookmarksMessage(count: Int) -> String {
        if count == 1 {
            return NSLocalizedString("Sequel Ace found 1 missing secure bookmark. You can request access now, or cancel and update it later in Files preferences.", comment: "single missing bookmark alert message")
        }

        let format = NSLocalizedString("Sequel Ace found %d missing secure bookmarks. You can request access now, or cancel and update them later in Files preferences.", comment: "multiple missing bookmarks alert message")
        return String.localizedStringWithFormat(format, count)
    }

    private static func displayName(forBookmarkPath bookmarkPath: String) -> String {
        return SABookmarkPathNormalizer.displayName(forBookmarkPath: bookmarkPath)
    }
}

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
	@objc(createWarningAlertWithTitle:message:callback:)
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

	/// Creates an alert with a capped scrollable list above the supplied accessory view.
	/// Use this for long file lists so the alert buttons remain reachable on small displays.
	@objc(createScrollableListAccessoryAlertWithTitle:message:listItems:accessoryView:primaryButtonTitle:secondaryButtonTitle:primaryButtonHandler:secondaryButtonHandler:)
	static func createScrollableListAccessoryAlert(title: String,
												   message: String,
												   listItems: [String],
												   accessoryView: NSView,
												   primaryButtonTitle: String,
												   secondaryButtonTitle: String,
												   primaryButtonHandler: (() -> ())? = nil,
												   secondaryButtonHandler: (() -> ())? = nil) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = title
            alert.informativeText = message
            alert.accessoryView = scrollableListAccessoryView(listItems: listItems, helpView: accessoryView)
            alert.addButton(withTitle: primaryButtonTitle)
            alert.addButton(withTitle: secondaryButtonTitle)

            if alert.runModal() == .alertFirstButtonReturn {
                primaryButtonHandler?()
            } else {
                secondaryButtonHandler?()
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

    @nonobjc static func scrollableListAccessoryView(listItems: [String], helpView: NSView) -> NSView {
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 900, height: 700)
        let accessoryWidth = min(520, max(320, visibleFrame.width - 96))
        let maximumListHeight = min(220, max(96, visibleFrame.height * 0.28))
        let desiredListHeight = min(maximumListHeight, max(72, CGFloat(listItems.count) * 18 + 18))

        let listTextView = NSTextView()
        listTextView.string = listItems.joined(separator: "\n")
        listTextView.font = NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        listTextView.isEditable = false
        listTextView.isSelectable = true
        listTextView.drawsBackground = false
        listTextView.textContainerInset = NSSize(width: 8, height: 6)
        listTextView.textContainer?.lineFragmentPadding = 0
        listTextView.textContainer?.widthTracksTextView = true
        listTextView.isVerticallyResizable = true
        listTextView.isHorizontallyResizable = false
        listTextView.autoresizingMask = [.width]
        listTextView.frame = NSRect(x: 0, y: 0, width: accessoryWidth, height: desiredListHeight)
        listTextView.minSize = NSSize(width: 0, height: desiredListHeight)
        listTextView.maxSize = NSSize(width: accessoryWidth, height: CGFloat.greatestFiniteMagnitude)
        listTextView.textContainer?.containerSize = NSSize(width: accessoryWidth, height: CGFloat.greatestFiniteMagnitude)

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor.textBackgroundColor
        scrollView.documentView = listTextView
        scrollView.widthAnchor.constraint(equalToConstant: accessoryWidth).isActive = true
        scrollView.heightAnchor.constraint(equalToConstant: desiredListHeight).isActive = true

        let helpFittingSize = helpView.fittingSize
        let helpWidth = min(accessoryWidth, max(helpView.frame.width, helpFittingSize.width))
        let helpHeight = max(helpView.frame.height, helpFittingSize.height)

        helpView.removeFromSuperview()
        helpView.translatesAutoresizingMaskIntoConstraints = false
        helpView.constraints
            .filter { $0.identifier == "SABookmarkAlertHelpWidth" || $0.identifier == "SABookmarkAlertHelpHeight" }
            .forEach { helpView.removeConstraint($0) }

        if helpWidth > 0 {
            let helpWidthConstraint = helpView.widthAnchor.constraint(equalToConstant: helpWidth)
            helpWidthConstraint.identifier = "SABookmarkAlertHelpWidth"
            helpWidthConstraint.isActive = true
        }

        if helpHeight > 0 {
            let helpHeightConstraint = helpView.heightAnchor.constraint(equalToConstant: helpHeight)
            helpHeightConstraint.identifier = "SABookmarkAlertHelpHeight"
            helpHeightConstraint.isActive = true
        }

        let stackView = NSStackView(views: [scrollView, helpView])
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 10
        stackView.translatesAutoresizingMaskIntoConstraints = false

        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: accessoryWidth, height: desiredListHeight))
        containerView.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: containerView.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])

        containerView.layoutSubtreeIfNeeded()
        containerView.setFrameSize(containerView.fittingSize)
        return containerView
    }
}
