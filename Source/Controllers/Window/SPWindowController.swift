//
//  SPWindowController.swift
//  Sequel Ace
//
//  Created by Jakub Kašpar on 24.01.2021.
//  Copyright © 2021 Sequel-Ace. All rights reserved.
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
//  More info at <https://github.com/Sequel-Ace/Sequel-Ace>

import Cocoa
import SnapKit

@objc final class SPWindowController: NSWindowController {

    @objc lazy var databaseDocument: SPDatabaseDocument = SPDatabaseDocument(windowController: self)

    override func awakeFromNib() {
        super.awakeFromNib()

        if let window = window  {
            window.collectionBehavior = [window.collectionBehavior, .fullScreenPrimary]
        }

        setupAppearance()
        setupConstraints()
    }

    // MARK: - Accessory

    private lazy var tabAccessoryView: NSView = NSView()
    private lazy var tabAccessoryColorView: NSView = NSView()
    private lazy var tabText: NSTextField = {
        let text = NSTextField()
        text.userActivity = .none
        text.backgroundColor = .clear
        text.isEditable = false
        text.isHidden = false
        text.alignment = .center
        text.isBordered = false
        text.textColor = .labelColor
        return text
    }()

    private lazy var tabAccessoryViewImage: NSImageView = {
        var image = NSImage(imageLiteralResourceName: "fallback_lock.fill")
        if #available(macOS 11, *), let systemImage = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: nil) {
            image = systemImage
        }
        let imageView = NSImageView(image: image)
        imageView.toolTip = NSLocalizedString("SSH Connected", comment: "Tooltip information text")
        imageView.isHidden = true
        return imageView
    }()

    private var tabAccessoryConstraintsSetup: Bool = false
}

// MARK: - Private API

private extension SPWindowController {
    func setupAppearance() {
        databaseDocument.updateWindowTitle(self)

        window?.contentView?.addSubview(databaseDocument.databaseView())
        databaseDocument.databaseView()?.frame = window?.contentView?.frame ?? NSRect(x: 0, y: 0, width: 800, height: 400)

        tabAccessoryView.addSubviews(tabAccessoryColorView, tabAccessoryViewImage, tabText)

        if #available(macOS 10.13, *) {
            window?.tab.accessoryView = tabAccessoryView
        }
    }

    func setupConstraints() {
        tabAccessoryColorView.snp.makeConstraints {
            $0.height.equalTo(5)
            $0.bottom.leading.trailing.equalToSuperview()
        }
        tabText.snp.makeConstraints {
            $0.bottom.equalTo(tabAccessoryColorView.snp.top)
            $0.leading.top.equalToSuperview()
            $0.trailing.equalTo(tabAccessoryViewImage.snp.leading)
        }

        tabAccessoryViewImage.snp.makeConstraints {
            $0.size.equalTo(20)
            $0.trailing.equalToSuperview()
            $0.centerY.equalToSuperview()
        }
    }
}

// MARK: - Public API

@objc extension SPWindowController {
    func updateWindow(title: String, tabTitle: String) {
        window?.title = title
        if #available(macOS 10.13, *) {
            window?.tab.title = tabTitle
        }
        if tabAccessoryView.superview != nil {
            tabText.stringValue = tabTitle
        }
    }

    func updateWindowAccessory(color: NSColor?, isSSL: Bool) {
        tabAccessoryColorView.layer?.backgroundColor = color?.cgColor
        tabAccessoryViewImage.isHidden = !isSSL

        if tabAccessoryView.superview != nil, !tabAccessoryConstraintsSetup {
            tabAccessoryConstraintsSetup = true
            tabAccessoryView.snp.makeConstraints {
                $0.leading.equalToSuperview().offset(35)
                $0.trailing.equalToSuperview().offset(-35)
                $0.top.equalToSuperview().offset(5)
                $0.bottom.equalToSuperview()
            }
        }
    }
}

extension SPWindowController: NSWindowDelegate {
    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        if !databaseDocument.parentTabShouldClose() {
            return false
        }

        if let appDelegate = NSApp.delegate as? SPAppController, appDelegate.sessionURL() != nil {
            appDelegate.setSessionURL(nil)
            appDelegate.setSpfSessionDocData(nil)
        }
        return true
    }
}
