//
//  SAClaudeFieldEditorStyler.swift
//  Sequel Ace
//
//  The Claude field editor sheet (SPFieldEditorController's editSheet; the controller file is never edited): the
//  shared form's header (the column as title, the table and type as context), a 40pt toolbar strip on top of a
//  rounded editor surface (the Text / Image / Hex / JSON switcher left; Open, Save and Quick Look as ghost icons
//  right), the visible content view filling the surface, and the footer (the "Edit all fields in pop-up sheet"
//  checkbox and the spinner left; Cancel + OK, or the read-only Close as the single primary, right). The XIB is Auto
//  Layout: its constraints between the views placed here are switched off once and frames set from
//  `SAClaudeFormLayout.editorFrames`. The window's content minimum is raised (never lowered) to what the layout
//  needs, so the strip and the editor keep their height at the controller's 390×150 / 650×200 minimum. Claimed by
//  `SAClaudeFormSheetStyler` through window identity; shares the form engine's header, apply coalescer, observers
//  and surface insertion. App target only.
//

import AppKit

final class SAClaudeFieldEditorStyler: NSObject {

    private typealias Layout = SAClaudeFormLayout

    private static var associationKey: UInt8 = 0
    private static let openSymbol = "folder"
    private static let saveSymbol = "square.and.arrow.down"
    private static let editInSheetKeyPath = "values.EditInSheetEnabled"
    private static let spinnerSize: CGFloat = 16
    /// The editor's height under the strip at the window's minimum (two lines of text, a strip of an image).
    private static let minimumEditorHeight: CGFloat = 40

    private struct Outlets {
        /// The window retains the styler (associated). Weak, not unowned: the frame observer can fire while the window
        /// is being torn down, and that must be a no-op, not a trap.
        weak var window: NSWindow?
        let contentView: NSView
        let fieldName: NSTextField
        let segments: NSSegmentedControl
        let quickLook: NSPopUpButton
        let open: NSButton
        let save: NSButton
        let ok: NSButton
        let cancel: NSButton
        let close: NSButton
        let progress: NSProgressIndicator
        let editInSheet: NSButton
        /// Text, hex, JSON scroll views and the image view: one is visible at a time.
        let contentViews: [NSView]
        let separators: [NSBox]

        init?(_ c: NSObject, window: NSWindow) {
            func outlet<T>(_ key: String) -> T? { SAClaudeFormRecipes.outlet(c, key) }
            guard let contentView = window.contentView, !contentView.isFlipped,
                  let fieldName: NSTextField = outlet("editSheetFieldName"),
                  let segments: NSSegmentedControl = outlet("editSheetSegmentControl"),
                  let quickLook: NSPopUpButton = outlet("editSheetQuickLookButton"),
                  let open: NSButton = outlet("editSheetOpenButton"),
                  let ok: NSButton = outlet("editSheetOkButton"),
                  let cancel: NSButton = outlet("editSheetCancelButton"),
                  let close: NSButton = outlet("editSheetIsNotEditableCancelButton"),
                  let progress: NSProgressIndicator = outlet("editSheetProgressBar"),
                  let text: NSView = outlet("editTextScrollView"),
                  let hex: NSView = outlet("hexTextScrollView"),
                  let json: NSView = outlet("jsonTextScrollView"),
                  let image: NSView = outlet("editImage"),
                  let save = SAClaudeFormFind.button(in: contentView, action: "saveEditSheet:"),
                  let editInSheet = contentView.subviews.compactMap({ $0 as? NSButton }).first(where: {
                      ($0.infoForBinding(.value)?[.observedKeyPath] as? String) == SAClaudeFieldEditorStyler.editInSheetKeyPath
                  })
            else { return nil }
            let placed: [NSView] = [fieldName, segments, quickLook, open, save, ok, cancel, close, progress, editInSheet, text, hex, json, image]
            guard placed.allSatisfy({ $0.superview === contentView }) else { return nil }
            self.window = window
            self.contentView = contentView
            self.fieldName = fieldName
            self.segments = segments
            self.quickLook = quickLook
            self.open = open
            self.save = save
            self.ok = ok
            self.cancel = cancel
            self.close = close
            self.progress = progress
            self.editInSheet = editInSheet
            contentViews = [text, hex, json, image]
            separators = contentView.subviews.compactMap { $0 as? NSBox }.filter { $0.boxType == .separator }
        }

        /// Every XIB view of the sheet: placed by frame, or hidden (the label, the segmented control, the separators).
        var all: [NSView] {
            ([fieldName, segments, quickLook, open, save, ok, cancel, close, progress, editInSheet] as [NSView]) + contentViews + (separators as [NSView])
        }

        /// Replaced by the form: hidden at every apply.
        var replaced: [NSView] { ([fieldName, segments] as [NSView]) + (separators as [NSView]) }
    }

    private let outlets: Outlets
    private weak var controller: NSObject?
    private weak var document: SPDatabaseDocument?

    private let header: SAClaudeFormHeader
    private let surface = SAClaudeFormSurfaceView()
    private let switcher = SAClaudeConnectionTypeTabs()

    private lazy var coalescer = SAClaudeFormApplyCoalescer { [weak self] in self?.apply() }
    private var observers: SAClaudeFormObservers?
    private var observations: [NSKeyValueObservation] = []
    /// The content minimum the controller set (from its `minSize`) before the sheet began.
    private var controllerMinimum = NSSize.zero

    static func styler(for window: NSWindow) -> SAClaudeFieldEditorStyler? {
        objc_getAssociatedObject(window, &associationKey) as? SAClaudeFieldEditorStyler
    }

    /// Restyles `match`'s edit sheet (once); nil, the sheet untouched, when an expected control is missing.
    @discardableResult
    static func attach(_ match: SAClaudeFormMatch) -> SAClaudeFieldEditorStyler? {
        if let existing = styler(for: match.window) { return existing }
        guard let outlets = Outlets(match.owner, window: match.window) else { return nil }
        let styler = SAClaudeFieldEditorStyler(outlets: outlets, controller: match.owner, document: match.document)
        objc_setAssociatedObject(match.window, &associationKey, styler, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        styler.build()
        styler.apply()
        return styler
    }

    private init(outlets: Outlets, controller: NSObject, document: SPDatabaseDocument?) {
        self.outlets = outlets
        self.controller = controller
        self.document = document
        header = SAClaudeFormHeader(in: outlets.contentView)
        super.init()
    }

    deinit {
        observations.forEach { $0.invalidate() }
    }

    // MARK: Building

    private func build() {
        let o = outlets
        guard let window = o.window else { return }
        controllerMinimum = window.contentRect(forFrameRect: NSRect(origin: .zero, size: window.minSize)).size

        // Frames from now on. The XIB's layout is resolved once (every view gets its laid-out size), then its
        // constraints are switched off: those between the sheet's own views and the content view, and each of those
        // views' own width/height. Views added by the skin or the form (autoresizing) are not touched.
        o.contentView.layoutSubtreeIfNeeded()
        let own = Set(o.all.map { ObjectIdentifier($0) } + [ObjectIdentifier(o.contentView)])
        func isOwn(_ item: AnyObject?) -> Bool { item.map { own.contains(ObjectIdentifier($0)) } ?? true }
        NSLayoutConstraint.deactivate(o.contentView.constraints.filter { isOwn($0.firstItem) && isOwn($0.secondItem) })
        for view in o.all {
            NSLayoutConstraint.deactivate(view.constraints.filter { $0.firstItem === view && $0.secondItem == nil })
            view.translatesAutoresizingMaskIntoConstraints = true
        }
        for view in o.replaced where !view.isHidden { view.isHidden = true }

        surface.identifier = NSUserInterfaceItemIdentifier(SAClaudeFormSheet.identifierPrefix + "Surface")
        surface.stripAtTop = true
        SAClaudeFormSheet.insertSurface(surface, in: o.contentView)
        o.contentView.addSubview(switcher)

        // The switcher drives the hidden segmented control, which stays the source of truth.
        switcher.accessibilityGroupLabel = SAClaudeFormStrings.displayMode
        switcher.onSelect = { [weak segments = o.segments] index in
            guard let segments, index < segments.segmentCount, segments.isEnabled(forSegment: index) else { return }
            segments.selectedSegment = index
            if let action = segments.action { NSApp.sendAction(action, to: segments.target, from: segments) }
        }
        SAClaudeFormChrome.makeGhostIcon(o.open, image: NSImage(systemSymbolName: Self.openSymbol, accessibilityDescription: SAClaudeFormStrings.openFile),
                                         toolTip: SAClaudeFormStrings.openFile)
        SAClaudeFormChrome.makeGhostIcon(o.save, image: NSImage(systemSymbolName: Self.saveSymbol, accessibilityDescription: SAClaudeFormStrings.saveFile),
                                         toolTip: SAClaudeFormStrings.saveFile)
        // Its own template image (the menu's first item) and tooltip.
        SAClaudeFormChrome.makeGhostIcon(o.quickLook, image: nil, toolTip: nil)
        for case let scrollView as NSScrollView in o.contentViews where scrollView.borderType != .noBorder { scrollView.borderType = .noBorder }
        o.progress.controlSize = .small
        o.progress.setFrameSize(NSSize(width: Self.spinnerSize, height: Self.spinnerSize))
        SAClaudeFormChrome.force(o.close, primary: true)
        chainKeyViews()
        observe()
    }

    /// The switcher joins the key loop, in visual order and closed: switcher, the content views (only the visible one
    /// can take focus; hidden ones are skipped), the strip's icons, the footer. Set once: the views are the sheet's own.
    private func chainKeyViews() {
        let o = outlets
        let content: [NSView] = o.contentViews.map { ($0 as? NSScrollView)?.documentView ?? $0 }
        let chain: [NSView] = [switcher] + content + [o.open, o.save, o.quickLook, o.editInSheet, o.cancel, o.ok, o.close]
        var pairs = Array(zip(chain, chain.dropFirst()))
        pairs.append((chain[chain.count - 1], chain[0]))
        for (view, next) in pairs where view.nextKeyView !== next || next.previousKeyView !== view {
            // Re-setting the same next view may not touch its previous view: clear first.
            if view.nextKeyView === next { view.nextKeyView = nil }
            view.nextKeyView = next
        }
    }

    private func observe() {
        let o = outlets
        guard let window = o.window else { return }
        observers = SAClaudeFormObservers(window: window, contentView: o.contentView,
                                          onFrameChange: { [weak self] in self?.apply() },
                                          onThemeChange: { [weak self] in self?.setNeedsApply() })
        // What the controller shows or selects after the sheet began (the JSON segment, an image, read-only Close).
        for view in o.contentViews + ([o.ok, o.cancel, o.close, o.open, o.save, o.quickLook] as [NSView]) {
            observations.append(view.observe(\.isHidden) { [weak self] _, _ in SAClaudeFormSheet.onMain { self?.setNeedsApply() } })
        }
        observations.append(o.segments.observe(\.selectedSegment) { [weak self] _, _ in SAClaudeFormSheet.onMain { self?.setNeedsApply() } })
    }

    private func setNeedsApply() {
        coalescer.setNeedsApply()
    }

    // MARK: Applying

    /// Re-lays the sheet out from its current state; called at every claim (begin, become key), on resize, on the
    /// controller's mode and visibility changes and on theme changes. Idempotent.
    func apply() {
        let o = outlets
        guard o.window != nil, o.contentView.bounds.width > 0, o.contentView.bounds.height > 0 else { return }
        coalescer.perform { applyNow() }
    }

    private func applyNow() {
        let o = outlets
        guard o.window != nil else { return }
        let colours = SAClaudeSheetColours.current()

        // Header.
        let text = SAClaudeFormContext.fieldEditorHeader(label: o.fieldName.stringValue, editor: controller, document: document)
        let hasContext = header.update(title: text.title, context: text.context, colours: colours)
        for view in o.replaced where !view.isHidden { view.isHidden = true }

        // The switcher follows the segmented control.
        let count = o.segments.segmentCount
        let titles = (0..<count).map { o.segments.label(forSegment: $0) ?? "" }
        let toolTips = (0..<count).map { o.segments.toolTip(forSegment: $0) }
        if switcher.toolTips != toolTips { switcher.toolTips = toolTips }
        if switcher.titles != titles { switcher.titles = titles }
        let enabled = (0..<count).map { o.segments.isEnabled(forSegment: $0) }
        if switcher.enabledSegments != enabled { switcher.enabledSegments = enabled }
        if o.segments.selectedSegment >= 0, switcher.selectedIndex != o.segments.selectedSegment { switcher.selectedIndex = o.segments.selectedSegment }
        recolour(colours)

        // Layout.
        let icons: [NSButton] = [o.open, o.save, o.quickLook].filter { !$0.isHidden }
        let trailing: [NSButton] = o.close.isHidden ? [o.cancel, o.ok] : [o.close]
        let leading: [NSView] = [o.editInSheet, o.progress]
        var spec = Layout.EditorSpec(size: .zero, hasContext: hasContext,
                                     switcherWidth: count > 0 ? ceil(switcher.preferredWidth) : 0,
                                     iconCount: icons.count,
                                     footerLeading: leading.map(SAClaudeFormSheet.footerItem),
                                     footerTrailing: trailing.map(SAClaudeFormSheet.footerItem))
        keepMinimum(Self.minimumContentSize(spec))
        spec.size = o.contentView.bounds.size
        let f = Layout.editorFrames(spec)

        header.place(title: f.title, context: f.context)
        surface.stripHeight = f.strip?.height ?? 0
        SAClaudeFormSheet.place(surface, f.surface)
        for view in o.contentViews { SAClaudeFormSheet.place(view, f.content) }
        if let switcherFrame = f.switcher {
            if switcher.isHidden { switcher.isHidden = false }
            SAClaudeFormSheet.place(switcher, switcherFrame)
        } else if !switcher.isHidden {
            switcher.isHidden = true
        }
        for (button, frame) in zip(icons, f.icons) { SAClaudeFormSheet.place(button, frame) }
        for (view, frame) in zip(leading, f.footerLeading) { SAClaudeFormSheet.place(view, frame) }
        for (view, frame) in zip(trailing, f.footerTrailing) { SAClaudeFormSheet.place(view, frame) }
        surface.needsDisplay = true
    }

    /// The smallest content size the layout fits: the footer's and the strip's widths; the header, a full strip,
    /// `minimumEditorHeight` of editor and the footer in height.
    private static func minimumContentSize(_ s: Layout.EditorSpec) -> NSSize {
        let hasStrip = s.switcherWidth > 0 || s.iconCount > 0
        var stripWidth = 2 * Layout.sideMargin + 2 * Layout.stripPadding + s.switcherWidth
        if s.iconCount > 0 {
            stripWidth += CGFloat(s.iconCount) * Layout.iconButtonSize + CGFloat(s.iconCount - 1) * Layout.iconButtonGap
            if s.switcherWidth > 0 { stripWidth += Layout.stripPadding }
        }
        let footerWidth = Layout.footerWidth(leading: s.footerLeading, trailing: s.footerTrailing)
        // Under the strip and its 1pt hairline (or the surface's inset), down to the surface's bottom inset.
        let surface = (hasStrip ? Layout.stripHeight + 1 : Layout.blockInset) + minimumEditorHeight + Layout.blockInset
        let height = Layout.topMargin + Layout.titleHeight + (s.hasContext ? Layout.contextGap + Layout.contextHeight : 0) + Layout.headerGap
            + surface + Layout.footerGap + Layout.footerHeight + Layout.bottomMargin
        return NSSize(width: ceil(max(footerWidth, stripWidth)), height: ceil(height))
    }

    /// Raises the window's content minimum to `needed` (keeping the controller's where it is larger) and, should the
    /// sheet be smaller (a frame saved before), grows it to that once, its top edge kept.
    private func keepMinimum(_ needed: NSSize) {
        let o = outlets
        guard let window = o.window else { return }
        let minimum = NSSize(width: max(controllerMinimum.width, needed.width), height: max(controllerMinimum.height, needed.height))
        if window.contentMinSize != minimum { window.contentMinSize = minimum }
        let current = o.contentView.bounds.size
        guard current.width < minimum.width || current.height < minimum.height else { return }
        let size = NSSize(width: max(current.width, minimum.width), height: max(current.height, minimum.height))
        let old = window.frame
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        frame.origin = NSPoint(x: (old.midX - frame.width / 2).rounded(), y: old.maxY - frame.height)
        window.setFrame(frame, display: window.isVisible)
    }

    private func recolour(_ colours: SAClaudeSheetColours) {
        let o = outlets
        switcher.colours = SAClaudeConnectionTypeTabs.Colours(selectedFill: colours.fieldFill, selectedStroke: colours.palette.hairline,
                                                              hoverFill: colours.palette.hover, text: colours.theme.text, mutedText: colours.muted)
        for button in [o.open, o.save, o.quickLook] as [NSButton] {
            if button.contentTintColor != colours.muted { button.contentTintColor = colours.muted }
            SAClaudeHoverHighlighter.setFillColour(colours.palette.hover, for: button)
        }
    }
}
