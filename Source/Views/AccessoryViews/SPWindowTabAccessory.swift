//
//  SPWindowTabAccessory.swift
//  Sequel Ace
//
//  Created by Parker Erway on 10/26/21.
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

final class SPWindowTabAccessory: NSView {
    // MARK: Initializers
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: 0, height: 0))
        addSubviews(tabAccessoryColorView, tabAccessoryViewImage, tabText)
        
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
    
    // MARK: Subviews
    
    private lazy var tabAccessoryColorView: NSView = {
        let colorView = NSView()
        colorView.wantsLayer = true
        return colorView
    }()
    
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
        imageView.toolTip = NSLocalizedString("Connection Secured via SSL", comment: "Connection Secured via SSL information text")
        imageView.isHidden = true
        return imageView
    }()
    
    // MARK: Setters
    
    func update(color: NSColor?, isSSL: Bool) {
        tabAccessoryColorView.layer?.backgroundColor = color?.cgColor
        tabAccessoryViewImage.isHidden = !isSSL
    }

    func setTitle(title: String) {
        tabText.stringValue = title
    }
    
    // MARK: Callbacks

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        if superview != nil {
            self.snp.makeConstraints {
                $0.leading.equalToSuperview().offset(35)
                $0.trailing.equalToSuperview().offset(-35)
                $0.top.equalToSuperview().offset(5)
                $0.bottom.equalToSuperview()
            }
        }
    }
}
