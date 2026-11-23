//
//  SPWindowTabAccessory.swift
//  Sequel Ace
//
//  Created by Parker Erway on 10/26/21.
//  Copyright © 2020-2022 Sequel-Ace. All rights reserved.
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

/// The content of a native window tab: the favourite colour as a dot, the tab title and the SSL padlock,
/// centred as one group (`SAClaudeTabContentLayout`). AppKit still draws the tab itself (fill, close button);
/// this view only replaces its label.
///
/// The accessory is pinned across the tab (`viewDidMoveToSuperview`), which squeezes AppKit's own title label
/// to zero width, so `window.tab.title` stays set for the Window menu, the tab overview and accessibility
/// without being drawn twice.
final class SPWindowTabAccessory: NSView {
    // MARK: Initializers
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        addContentSubviews()
    }

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: 0, height: 0))
        addContentSubviews()
    }

    private func addContentSubviews() {
        addSubviews(colourDot, tabText, lockImageView)
        for view in [colourDot, tabText, lockImageView] {
            view.translatesAutoresizingMaskIntoConstraints = true
        }
        applySelectionStyle()
    }

    // MARK: State

    private var hasColour = false
    private var isSSL = false
    private var isSelected = false

    // MARK: Subviews

    private let colourDot = TabColourDot()

    private lazy var tabText: NSTextField = {
        let text = NSTextField(labelWithString: "")
        text.lineBreakMode = .byTruncatingTail
        text.maximumNumberOfLines = 1
        text.cell?.truncatesLastVisibleLine = true
        text.alignment = .natural
        return text
    }()

    private lazy var lockImageView: NSImageView = {
        let size = SAClaudeTabContentLayout.lockSize
        var image = NSImage(imageLiteralResourceName: "fallback_lock.fill")
        if let systemImage = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: size, weight: .regular)) {
            image = systemImage
        }
        image.isTemplate = true
        let imageView = NSImageView(image: image)
        imageView.imageScaling = .scaleProportionallyDown
        imageView.contentTintColor = SAClaudeStyle.textMuted
        imageView.toolTip = NSLocalizedString("Connection Secured via SSL", comment: "Connection Secured via SSL information text")
        imageView.isHidden = true
        return imageView
    }()

    // MARK: Setters

    /// The colour a tab shows for a connection's favourite colour: a favourite's `-tab` variant from the asset
    /// catalog when there is one, otherwise the colour itself.
    static func tabColour(for color: NSColor?) -> NSColor? {
        if let name = color?.colorNameComponentIfNamed, name.starts(with: "favorite") {
            return NSColor(named: name + "-tab") ?? color
        }
        return color
    }

    func update(color: NSColor?, isSSL: Bool) {
        let tabColor = Self.tabColour(for: color)

        colourDot.colour = tabColor
        hasColour = tabColor != nil
        self.isSSL = isSSL
        needsLayout = true
    }

    func setTitle(title: String) {
        guard tabText.stringValue != title else { return }
        tabText.stringValue = title
        needsLayout = true
    }

    /// The full path of the tab (the window title), shown when hovering the tab content.
    func setToolTipPath(_ path: String) {
        if toolTip != path { toolTip = path }
    }

    /// Whether this tab is the selected one of its group: medium primary text when selected, regular secondary otherwise.
    func setSelected(_ selected: Bool) {
        guard isSelected != selected else { return }
        isSelected = selected
        applySelectionStyle()
        needsLayout = true
    }

    private func applySelectionStyle() {
        tabText.font = .systemFont(ofSize: 12, weight: isSelected ? .medium : .regular)
        tabText.textColor = isSelected ? SAClaudeStyle.textPrimary : SAClaudeStyle.textSecondary
    }

    // MARK: Layout

    /// Frames the subviews only; the accessory's own size comes from its constraints to the tab.
    override func layout() {
        super.layout()
        let frames = SAClaudeTabContentLayout.frames(size: bounds.size,
                                                     titleWidth: tabText.cell?.cellSize.width ?? 0,
                                                     hasColour: hasColour,
                                                     isSSL: isSSL)
        colourDot.isHidden = frames.dot == nil
        if let dot = frames.dot { colourDot.frame = dot }
        tabText.frame = frames.title
        lockImageView.isHidden = frames.lock == nil
        if let lock = frames.lock { lockImageView.frame = lock }
    }

    // MARK: Callbacks

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        // The text and lock use dynamic colours AppKit resolves when drawing; the dot draws itself.
        colourDot.needsDisplay = true
        tabText.needsDisplay = true
        lockImageView.needsDisplay = true
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        if superview != nil {
            // Fill the tab's height so the content centres in it; 35pt clears the close button.
            self.snp.makeConstraints {
                $0.leading.equalToSuperview().offset(35)
                $0.trailing.equalToSuperview().offset(-35)
                $0.top.equalToSuperview()
                $0.bottom.equalToSuperview()
            }
        }
    }
}

/// The favourite colour as a filled circle; resolves the (possibly dynamic) colour when it draws.
private final class TabColourDot: NSView {
    var colour: NSColor? {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let colour else { return }
        colour.setFill()
        NSBezierPath(ovalIn: bounds).fill()
    }
}
