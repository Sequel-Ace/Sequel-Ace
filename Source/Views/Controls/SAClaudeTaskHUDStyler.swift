//
//  SAClaudeTaskHUDStyler.swift
//  Sequel Ace
//
//  The Claude look of the loading overlay (the task HUD of ProgressIndicatorLayer.xib, owned by SATaskController):
//  a 360x72 card in the toolbar colour with a 14pt radius and a hairline, an accent ring in place of the YRK
//  spinner, the description (SF Pro 13 medium) over the elapsed time (SF Pro 11, muted, tabular digits), and the
//  cancel button as a bordered secondary button sized to its title. Frames come from `SAClaudeTaskHUDLayout`; the
//  XIB's constraints inside the card are deactivated and its views placed by frame. The YRK indicator stays alive
//  (the controller keeps driving it) at alpha 0; `SAClaudeTaskSpinnerView` reads its state. App target only.
//

import AppKit
import QuartzCore

final class SAClaudeTaskHUDStyler {

    private static let descriptionFont = NSFont.systemFont(ofSize: 13, weight: .medium)
    private static let durationFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
    private static let buttonFont = NSFont.systemFont(ofSize: 12, weight: .medium)
    private static let borderWidth: CGFloat = 1

    private static let truncatingTail: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        return style
    }()

    /// The card the calculator's frames are in (the XIB's inner box), or the views' own superview without it.
    private let card: NSView
    /// The view the card's subviews live in.
    private let content: NSView
    private let indicator: YRKSpinningProgressIndicator
    private let descriptionField: NSTextField
    private let durationField: NSTextField
    private let cancelButton: NSButton
    private let spinner: SAClaudeTaskSpinnerView
    private var resizeObserver: NSObjectProtocol?

    init(layer: NSBox, indicator: YRKSpinningProgressIndicator, description: NSTextField, duration: NSTextField,
         cancelButton: NSButton) {
        self.indicator = indicator
        descriptionField = description
        durationField = duration
        self.cancelButton = cancelButton
        spinner = SAClaudeTaskSpinnerView(indicator: indicator)

        // The outer box stays transparent; it just takes the card's size (before the controller's window is made from it).
        layer.contentViewMargins = .zero
        layer.setFrameSize(SAClaudeTaskHUDLayout.size)
        layer.contentView?.frame = layer.bounds
        let box = layer.contentView?.subviews.lazy.compactMap { $0 as? NSBox }.first
        if let box {
            Self.styleCard(box, in: layer.contentView?.bounds ?? layer.bounds)
        }
        card = (box as NSView?) ?? indicator.superview ?? layer
        content = box?.contentView ?? indicator.superview ?? layer

        let placed: [NSView] = [indicator, description, duration, cancelButton]
        Self.releaseFromConstraints(placed, in: content)

        indicator.alphaValue = 0
        content.addSubview(spinner)

        for field in [description, duration] {
            field.usesSingleLineMode = true
            field.maximumNumberOfLines = 1
            field.lineBreakMode = .byTruncatingTail
            field.cell?.wraps = false
            field.cell?.truncatesLastVisibleLine = true
            field.drawsBackground = false
        }
        description.font = Self.descriptionFont
        description.textColor = SAClaudeStyle.textPrimary
        duration.font = Self.durationFont
        duration.textColor = SAClaudeStyle.textMuted

        if SAClaudeFilterCells.install(SAClaudeTaskHUDButtonCell.self, on: cancelButton) {
            cancelButton.isBordered = false
        }
        cancelButton.font = Self.buttonFont

        // Replace the XIB's placeholder text with the zero time SATaskController writes when a task ends, so the
        // first task does not show the placeholder until the first one-second tick.
        duration.attributedStringValue = NSAttributedString(
            string: DateComponentsFormatter.hourMinSecFormatter.string(from: 0) ?? "", attributes: durationAttributes())

        layOut()
        SAClaudeAccent.observe(self) { $0.spinner.refreshColours() }
    }

    deinit {
        stopFollowing()
    }

    // MARK: - Text

    /// The attributes SATaskController uses for its two labels.
    func descriptionAttributes() -> [NSAttributedString.Key: Any] {
        [.font: Self.descriptionFont, .foregroundColor: SAClaudeStyle.textPrimary, .paragraphStyle: Self.truncatingTail]
    }

    func durationAttributes() -> [NSAttributedString.Key: Any] {
        [.font: Self.durationFont, .foregroundColor: SAClaudeStyle.textMuted, .paragraphStyle: Self.truncatingTail]
    }

    /// The cancel button's title attributes (the cell draws the title itself; these keep the measured width right).
    func cancelTitleAttributes() -> [NSAttributedString.Key: Any] {
        [.font: Self.buttonFont, .foregroundColor: SAClaudeStyle.textPrimary]
    }

    // MARK: - Layout

    /// Call after the cancel button's title or visibility changed.
    func layOut() {
        let buttonWidth: CGFloat? = cancelButton.isHidden ? nil : SAClaudeTaskHUDLayout.buttonWidth(
            titleWidth: NSAttributedString(string: cancelButton.title, attributes: [.font: Self.buttonFont]).size().width)
        let frames = SAClaudeTaskHUDLayout.frames(buttonWidth: buttonWidth)
        place(spinner, at: frames.spinner)
        place(indicator, at: frames.spinner)
        place(descriptionField, at: frames.description)
        place(durationField, at: frames.duration)
        if let button = frames.button { place(cancelButton, at: button) }
    }

    /// Puts `view` at `rect` of the card (the card's content view may sit inside its hairline).
    private func place(_ view: NSView, at rect: NSRect) {
        let frame = content.convert(rect, from: card)
        if view.frame != frame { view.frame = frame }
    }

    // MARK: - Spinner

    /// Call next to the controller's start / stop of the YRK indicator's animation.
    func setAnimating(_ animating: Bool) {
        spinner.setAnimating(animating)
    }

    /// Call after the YRK indicator's value or mode changed without a start / stop.
    func indicatorDidChange() {
        spinner.refresh()
    }

    // MARK: - Window

    /// Keep the HUD centred on `parent` while it resizes.
    func follow(parent: NSWindow, hud: NSWindow) {
        stopFollowing()
        hud.hasShadow = true
        resizeObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: parent,
                                                                queue: nil) { [weak parent, weak hud] _ in
            guard let parent, let hud, hud.alphaValue > 0 else { return }
            let origin = Self.centredOrigin(of: hud.frame.size, in: parent.frame)
            if hud.frame.origin != origin { hud.setFrameOrigin(origin) }
        }
    }

    /// Stops re-centring the HUD (document close).
    func stopFollowing() {
        if let resizeObserver { NotificationCenter.default.removeObserver(resizeObserver) }
        resizeObserver = nil
    }

    /// The origin that centres a window of `size` on `parentFrame` (as SATaskController's `centerInParentWindow`).
    private static func centredOrigin(of size: NSSize, in parentFrame: NSRect) -> NSPoint {
        NSPoint(x: (parentFrame.midX - size.width / 2).rounded(), y: (parentFrame.midY - size.height / 2).rounded())
    }

    // MARK: - Setup helpers

    private static func styleCard(_ box: NSBox, in bounds: NSRect) {
        box.boxType = .custom
        // The XIB's box has no border type, which hides a custom box's border; `borderType` itself is deprecated
        // API, so it is set through KVC, and only while AppKit still has it (KVC on a missing key raises).
        if box.responds(to: NSSelectorFromString("setBorderType:")) {
            box.setValue(NSBorderType.lineBorder.rawValue, forKey: "borderType")
        }
        box.isTransparent = false
        box.titlePosition = .noTitle
        box.cornerRadius = SAClaudeTaskHUDLayout.cornerRadius
        box.borderWidth = borderWidth
        box.borderColor = SAClaudeStyle.divider
        box.fillColor = SAClaudeStyle.toolbarBackground
        box.contentViewMargins = .zero
        box.frame = bounds
        // The box does not re-tile its content view when resized (its XIB turns autoresizing off).
        box.contentView?.frame = box.bounds.insetBy(dx: borderWidth, dy: borderWidth)
        box.needsDisplay = true
    }

    /// Deactivates the XIB's constraints that place `views` (between them and `container`, and their own fixed
    /// sizes) so they can be placed by frame.
    private static func releaseFromConstraints(_ views: [NSView], in container: NSView) {
        var constraints = container.constraints.filter { !isAutoresizing($0) }
        for view in views {
            constraints += view.constraints.filter { $0.firstItem === view && $0.secondItem == nil && !isAutoresizing($0) }
        }
        NSLayoutConstraint.deactivate(constraints)
        for view in views {
            view.translatesAutoresizingMaskIntoConstraints = true
            view.autoresizingMask = []
        }
    }

    /// AppKit's constraints for a view's autoresizing mask (a private class).
    private static let autoresizingConstraintClass: AnyClass? = NSClassFromString("NSAutoresizingMaskLayoutConstraint")

    private static func isAutoresizing(_ constraint: NSLayoutConstraint) -> Bool {
        autoresizingConstraintClass.map { constraint.isKind(of: $0) } ?? false
    }
}

// MARK: - Cancel button

/// The HUD's cancel button: the Claude secondary button (outline, pressed fill, SF Pro 12 medium title) in the app's
/// tokens rather than the editor theme's, so it reads on the toolbar-coloured card in either appearance.
@objc(SAClaudeTaskHUDButtonCell) final class SAClaudeTaskHUDButtonCell: NSButtonCell {

    private static let font = NSFont.systemFont(ofSize: 12, weight: .medium)

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        SAClaudeSecondaryButtonCell.drawSecondary(self, in: cellFrame, font: Self.font, hovered: false,
                                                  text: SAClaudeStyle.textPrimary,
                                                  background: SAClaudeStyle.toolbarBackground,
                                                  hover: SAClaudeStyle.hoverFill)
    }
}

// MARK: - Spinner

/// The HUD's spinner: a 2.5pt full-circle track in the divider colour and an accent arc with round caps. While the
/// YRK indicator is indeterminate and animating, a 90° arc rotates clockwise (a Core Animation rotation, no timer);
/// when determinate, the arc runs clockwise from 12 o'clock to the indicator's fraction. Colours follow the
/// appearance and the accent (`refreshColours`).
final class SAClaudeTaskSpinnerView: NSView {

    private static let lineWidth: CGFloat = 2.5
    private static let indeterminateArc: CGFloat = 0.25
    private static let revolutionDuration: CFTimeInterval = 0.9
    private static let spinKey = "SAClaudeTaskSpin"

    private let indicator: YRKSpinningProgressIndicator
    private let track = CAShapeLayer()
    private let arc = CAShapeLayer()
    private var isAnimating = false

    init(indicator: YRKSpinningProgressIndicator) {
        self.indicator = indicator
        super.init(frame: .zero)
        wantsLayer = true
        for shape in [track, arc] {
            shape.fillColor = nil
            shape.lineWidth = Self.lineWidth
            shape.lineCap = .round
            layer?.addSublayer(shape)
        }
        refreshColours()
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updatePaths()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshColours()
    }

    /// Mirrors the YRK indicator: it only animates while indeterminate.
    func setAnimating(_ animating: Bool) {
        isAnimating = animating && indicator.isIndeterminate()
        refresh()
    }

    /// Re-reads the YRK indicator's mode and value.
    func refresh() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        if indicator.isIndeterminate() {
            arc.strokeEnd = Self.indeterminateArc
            if isAnimating {
                if arc.animation(forKey: Self.spinKey) == nil { arc.add(Self.spinAnimation(), forKey: Self.spinKey) }
            } else {
                arc.removeAnimation(forKey: Self.spinKey)
            }
        } else {
            isAnimating = false
            arc.removeAnimation(forKey: Self.spinKey)
            arc.strokeEnd = SAClaudeTaskHUDLayout.ringFraction(value: indicator.doubleValue(), maximum: indicator.maxValue())
        }
    }

    /// Resolves the track and arc colours for the current appearance and accent.
    func refreshColours() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            track.strokeColor = SAClaudeStyle.divider.cgColor
            arc.strokeColor = SAClaudeAccent.accent.cgColor
        }
        CATransaction.commit()
    }

    /// A full circle from 12 o'clock, clockwise (the view is unflipped, so the arc's y runs up).
    private func updatePaths() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let size = bounds.size
        let radius = max(0, (min(size.width, size.height) - Self.lineWidth) / 2)
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        let path = CGMutablePath()
        path.addArc(center: centre, radius: radius, startAngle: .pi / 2, endAngle: .pi / 2 - 2 * .pi, clockwise: true)
        for shape in [track, arc] {
            // Rotation turns the arc about its layer's centre, so each layer spans the whole view.
            shape.frame = CGRect(origin: .zero, size: size)
            shape.path = path
        }
    }

    private static func spinAnimation() -> CABasicAnimation {
        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0
        spin.toValue = -2 * Double.pi
        spin.duration = revolutionDuration
        spin.repeatCount = .infinity
        spin.isRemovedOnCompletion = false
        return spin
    }
}
