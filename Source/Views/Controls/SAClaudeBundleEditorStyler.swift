//
//  SAClaudeBundleEditorStyler.swift
//  Sequel Ace
//
//  The Bundle Editor in the Claude look (spec 2026-10-18-claude-utility-windows-design.md, section D):
//
//  - The bundles list as a Claude sidebar (its top row a muted section header, as the main sidebar's), its add, remove and
//    gear buttons as glyph buttons over a hairline, the divider a hairline.
//  - The bundle's settings as a tidy two-column form (SAClaudeBundleEditorLayout): label + control rows, level across the
//    columns (Bundle Scope | Trigger, Menu Label | Menu Category, Shortcut | Tooltip, Input | Or / And, Output); the six
//    pop-ups are Claude pills, the fields Claude fields, the shortcut recorder drawn on a Claude field in the theme's text
//    colour (`SAClaudeShortcutRecorderControl`).
//  - The command editor framed by a rounded hairline; the summary and Bundle Info on top; Disable Bundle, the help "?" (a
//    ghost icon), Cancel and Save (the accent primary) at the bottom.
//  - Its Undelete sheet's list in the Claude grid look; its Meta Info sheet's description framed.
//
//  The XIB is not edited: the views are re-laid out in place whenever the right pane changes size, so every binding,
//  outlet, hidden state (the controller shows Or or And as the input needs) and key loop entry stays the controller's.
//  The "Shortcut" label and the recorder's field are the only views added. Claimed by identity (the controller's window and outlets) whenever the
//  generic skin considers the window. App target only.
//

import AppKit

@MainActor
@objc(SAClaudeBundleEditorStyler) final class SAClaudeBundleEditorStyler: NSObject {

    private typealias Layout = SAClaudeBundleEditorLayout

    enum Strings {
        static var shortcut: String { NSLocalizedString("ClaudeBundleEditorShortcutLabel", value: "Shortcut:", comment: "bundle editor : label of the keyboard shortcut recorder in the bundle form") }
        static var addBundle: String { NSLocalizedString("ClaudeBundleEditorAdd", value: "Add bundle", comment: "bundle editor : tooltip and accessibility name of the add button under the bundles list") }
        static var removeBundle: String { NSLocalizedString("ClaudeBundleEditorRemove", value: "Remove bundle", comment: "bundle editor : tooltip and accessibility name of the remove button under the bundles list") }
        static var actions: String { NSLocalizedString("ClaudeBundleEditorActions", value: "Bundle actions", comment: "bundle editor : tooltip and accessibility name of the gear menu under the bundles list (Duplicate, Export, Reveal…)") }
        static var bundlesHeader: String { NSLocalizedString("ClaudeBundleEditorBundlesHeader", value: "Bundles", comment: "bundle editor : the section header over the bundles list (the list's root row), in title case like the other utility windows' list headers") }
    }

    struct Outlets {
        let split: NSSplitView
        let sidebarPane: NSView
        let rightPane: NSView
        let outline: NSOutlineView
        let outlineScroll: NSScrollView
        let add: NSButton
        let remove: NSButton
        let gear: NSPopUpButton
        let summary: NSTextField
        let info: NSButton
        /// Label + control, top to bottom: Bundle Scope, Menu Label, Shortcut, Input, Output.
        let left: [(label: NSTextField, control: NSView)]
        /// Trigger, Menu Category, Tooltip.
        let right: [(label: NSTextField, control: NSView)]
        /// The fourth right-hand row: "Or" + the input fallback, "And" + the blob option (one pair shows at a time).
        let alternatives: [(label: NSTextField, control: NSView)]
        let recorder: NSControl
        let commandLabel: NSTextField
        let commandScroll: NSScrollView
        let disable: NSButton
        let help: NSButton
        let cancel: NSButton
        let save: NSButton
    }

    private static var associationKey: UInt8 = 0

    private weak var window: NSWindow?
    private let o: Outlets
    private let recorderField = SAClaudeRecorderFieldView()
    private var isLayingOut = false
    private var frameObserver: NSObjectProtocol?
    private var appearanceObservation: NSKeyValueObservation?

    private init(window: NSWindow, outlets: Outlets) {
        self.window = window
        self.o = outlets
        super.init()
    }

    deinit {
        if let frameObserver { NotificationCenter.default.removeObserver(frameObserver) }
    }

    // MARK: Claiming

    /// Claims the Bundle Editor's window (or styles its Undelete / Meta Info sheet); a claimed window is laid out again.
    static func claim(_ window: NSWindow?) {
        guard let window else { return }
        if let styler = objc_getAssociatedObject(window, &associationKey) as? SAClaudeBundleEditorStyler {
            styler.apply()
            return
        }
        if styleSheet(window) { return }
        guard let controller = window.windowController, controller.window === window,
              SAClaudeFormOwners.className(of: controller) == "SPBundleEditorController",
              let outlets = findOutlets(controller, window: window) else { return }
        let styler = SAClaudeBundleEditorStyler(window: window, outlets: outlets)
        objc_setAssociatedObject(window, &associationKey, styler, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        styler.build()
        styler.apply()
    }

    private static func outlet<T>(_ controller: NSObject, _ key: String) -> T? {
        SAClaudeFormRecipes.outlet(controller, key)
    }

    private static func findOutlets(_ controller: NSObject, window: NSWindow) -> Outlets? {
        guard let split: NSSplitView = outlet(controller, "splitView"), split.window === window, split.subviews.count == 2,
              let outline: NSOutlineView = outlet(controller, "commandsOutlineView"),
              let add: NSButton = outlet(controller, "addButton"), let remove: NSButton = outlet(controller, "removeButton"),
              let help: NSButton = outlet(controller, "helpButton"), let save: NSButton = outlet(controller, "saveButton"),
              let cancel: NSButton = outlet(controller, "cancelButton"), let info: NSButton = outlet(controller, "displayMetaInfoButton"),
              let summary: NSTextField = outlet(controller, "metaInfoSummary"),
              let scope: NSPopUpButton = outlet(controller, "scopePopupButton"), let trigger: NSPopUpButton = outlet(controller, "triggerPopupButton"),
              let input: NSPopUpButton = outlet(controller, "inputPopupButton"), let fallback: NSPopUpButton = outlet(controller, "inputFallbackPopupButton"),
              let blob: NSPopUpButton = outlet(controller, "withBlobPopupButton"), let output: NSPopUpButton = outlet(controller, "outputPopupButton"),
              let name: NSTextField = outlet(controller, "nameTextField"), let category: NSTextField = outlet(controller, "categoryTextField"),
              let tooltip: NSTextField = outlet(controller, "tooltipTextField"), let recorder: NSControl = outlet(controller, "keyEquivalentField"),
              let fallbackLabel: NSTextField = outlet(controller, "fallbackLabelField"), let blobLabel: NSTextField = outlet(controller, "withBlobLabelField"),
              let commandLabel: NSTextField = outlet(controller, "commandLabelField"), let commandScroll: NSScrollView = outlet(controller, "commandScrollView"),
              let disable: NSButton = outlet(controller, "disabledCheckbox") else { return nil }
        let sidebarPane = split.subviews[0]
        let rightPane = split.subviews[1]
        let formViews: [NSView] = [help, save, cancel, info, summary, scope, trigger, input, fallback, blob, output, name, category, tooltip,
                                   recorder, fallbackLabel, blobLabel, commandLabel, commandScroll, disable]
        guard let outlineScroll = outline.enclosingScrollView, outlineScroll.superview === sidebarPane,
              add.superview === sidebarPane, remove.superview === sidebarPane,
              let gear = sidebarPane.subviews.compactMap({ $0 as? NSPopUpButton }).first(where: { $0.pullsDown }),
              formViews.allSatisfy({ $0.superview === rightPane }),
              // The static labels beside the controls, by the XIB's frames (before anything moves).
              let scopeLabel = SAClaudeFormFind.label(beside: scope), let triggerLabel = SAClaudeFormFind.label(beside: trigger),
              let nameLabel = SAClaudeFormFind.label(beside: name), let categoryLabel = SAClaudeFormFind.label(beside: category),
              let tooltipLabel = SAClaudeFormFind.label(beside: tooltip), let inputLabel = SAClaudeFormFind.label(beside: input),
              let outputLabel = SAClaudeFormFind.label(beside: output) else { return nil }
        let shortcutLabel = NSTextField(labelWithString: Strings.shortcut)
        shortcutLabel.font = scopeLabel.font
        shortcutLabel.controlSize = scopeLabel.controlSize
        rightPane.addSubview(shortcutLabel)
        return Outlets(split: split, sidebarPane: sidebarPane, rightPane: rightPane, outline: outline, outlineScroll: outlineScroll,
                       add: add, remove: remove, gear: gear, summary: summary, info: info,
                       left: [(scopeLabel, scope), (nameLabel, name), (shortcutLabel, recorder), (inputLabel, input), (outputLabel, output)],
                       right: [(triggerLabel, trigger), (categoryLabel, category), (tooltipLabel, tooltip)],
                       alternatives: [(fallbackLabel, fallback), (blobLabel, blob)],
                       recorder: recorder, commandLabel: commandLabel, commandScroll: commandScroll, disable: disable, help: help,
                       cancel: cancel, save: save)
    }

    // MARK: Building

    private func build() {
        SAClaudeUtilitySidebar.adopt(o.outline) { state in
            state.groupRowsAsHeaders = true
            // The root row ("BUNDLES") in title case, as the other lists' headers ("Favorites", "Accounts").
            state.headerTitle = { table, row, title in
                (table as? NSOutlineView)?.level(forRow: row) == 0 ? Strings.bundlesHeader : title
            }
        }
        SAClaudeUtilityChrome.styleSidebarPane(o.sidebarPane, list: o.outlineScroll,
                                               bar: [(o.add, .add, Strings.addBundle), (o.remove, .remove, Strings.removeBundle),
                                                     (o.gear, .actions, Strings.actions)],
                                               split: o.split)
        for (label, _) in o.left + o.right + o.alternatives {
            label.alignment = .right
            label.lineBreakMode = .byTruncatingTail
        }
        // The summary sits right before Bundle Info, in the right column's spare row.
        o.summary.alignment = .right
        o.summary.lineBreakMode = .byTruncatingTail
        SAClaudeUtilityChrome.makeRegular(o.info)
        SAClaudeFormChrome.force(o.info, primary: false)
        SAClaudeFormChrome.force(o.save, primary: true)
        SAClaudeFormChrome.force(o.cancel, primary: false)
        SAClaudeUtilityChrome.makeRegular(o.save)
        SAClaudeUtilityChrome.makeRegular(o.cancel)
        SAClaudeUtilityChrome.styleHelpButton(o.help, label: SAClaudeManagerSheetStyler.Strings.help)
        if SAClaudeShortcutRecorderControl.adopt(o.recorder) {
            recorderField.recorder = o.recorder
            o.rightPane.addSubview(recorderField, positioned: .below, relativeTo: o.recorder)
        }
        // The two option pop-ups may be hidden (and empty) at the generic skin's walk: pills from the start.
        for case let popUp as NSPopUpButton in (o.left + o.right + o.alternatives).map(\.control) where !(popUp.cell is SAClaudePillPopUpButtonCell) {
            SAClaudeFilterCells.installPill(on: popUp)
        }
        // The command editor (SPBundleCommandTextView) draws the theme background the sheet skin gives it; its text and
        // caret in the theme's colours too.
        if let text = o.commandScroll.documentView as? NSTextView {
            let colours = SAClaudeSheetColours.current()
            text.textColor = colours.theme.text
            text.insertionPointColor = colours.theme.caret
        }

        SAClaudeThemeWatcher.observe(self) { styler in
            MainActor.assumeIsolated { styler.recolour() }
        }
        appearanceObservation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.recolour() } }
        }
        o.rightPane.postsFrameChangedNotifications = true
        frameObserver = NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: o.rightPane, queue: nil) { [weak self] _ in
            MainActor.assumeIsolated { self?.layout() }
        }
    }

    // MARK: Applying

    private func apply() {
        // The bound fields' placeholders ("optional", the XIB's hints) in the muted placeholder colour, never a value's.
        // Again at each apply: the sheet skin may give the fields its own cell after the claim.
        for field in [o.left[1].control, o.right[1].control, o.right[2].control].compactMap({ $0 as? NSTextField }) {
            SAClaudeSheetPlaceholderFieldCell.install(on: field)
        }
        layout()
        recolour()
    }

    /// ShortcutRecorder's SRMaxHeight.
    private static let recorderMaxHeight: CGFloat = 22

    private static func labelWidth(_ label: NSTextField) -> CGFloat {
        ceil(label.cell?.cellSize.width ?? label.frame.width)
    }

    private func layout() {
        guard !isLayingOut else { return }
        isLayingOut = true
        defer { isLayingOut = false }
        let place = SAClaudeUtilityChrome.place
        let inset = SAClaudeSheetButtonGeometry.metrics(for: .regular).classicSideMargin
        let labelHeight = max(16, ceil(o.left[0].label.cell?.cellSize.height ?? 16))
        let measures = Layout.Measures(leftLabelWidth: o.left.map { Self.labelWidth($0.label) }.max() ?? 0,
                                       rightLabelWidth: (o.right + o.alternatives).map { Self.labelWidth($0.label) }.max() ?? 0,
                                       leftRows: o.left.count, rightRows: o.right.count + 1, labelHeight: labelHeight,
                                       infoWidth: SAClaudeUtilityChrome.pushButtonWidth(o.info),
                                       cancelWidth: SAClaudeUtilityChrome.pushButtonWidth(o.cancel),
                                       saveWidth: SAClaudeUtilityChrome.pushButtonWidth(o.save),
                                       disableWidth: o.disable.cell?.cellSize.width ?? o.disable.frame.width, buttonInset: inset)
        let frames = Layout.frames(in: o.rightPane.bounds, measures)
        place(o.summary, frames.summary)
        place(o.info, frames.info)
        for (views, row) in zip(o.left, frames.left) {
            place(views.label, row.label)
            if views.control === o.recorder {
                // ShortcutRecorder keeps itself at most 22pt tall: centred on its field.
                place(recorderField, row.control)
                let height = min(row.control.height, Self.recorderMaxHeight)
                place(o.recorder, NSRect(x: row.control.minX + 2, y: (row.control.midY - height / 2).rounded(),
                                         width: max(0, row.control.width - 4), height: height))
                // Its text is centred on the field, in the labels' size.
                SAClaudeUtilityChrome.alignBaseline(of: views.label, to: recorderField)
            } else {
                place(views.control, row.control)
                SAClaudeUtilityChrome.alignBaseline(of: views.label, to: views.control)
            }
        }
        let rightViews = o.right.map { [$0] } + [o.alternatives]
        for (pairs, row) in zip(rightViews, frames.right) {
            for views in pairs {
                place(views.label, row.label)
                place(views.control, row.control)
                SAClaudeUtilityChrome.alignBaseline(of: views.label, to: views.control)
            }
        }
        place(o.commandLabel, frames.commandLabel)
        place(o.commandScroll, frames.command)
        place(o.disable, frames.disable)
        place(o.help, frames.help)
        place(o.cancel, frames.cancel)
        place(o.save, frames.save)
        frameCommand()
    }


    private func frameCommand(_ colours: SAClaudeSheetColours = .current()) {
        SAClaudeUtilityChrome.frameList(o.commandScroll, hairline: colours.palette.hairline)
    }

    private func recolour() {
        let colours = SAClaudeSheetColours.current()
        SAClaudeUtilityChrome.recolourGhostIcons([o.help], colours)
        o.recorder.needsDisplay = true
        recorderField.needsDisplay = true
        // The added Shortcut label in the colour the sheet skin gives the form's other labels.
        if let shortcutLabel = o.left.first(where: { $0.control === o.recorder })?.label, let colour = o.left.first?.label.textColor,
           shortcutLabel.textColor != colour {
            shortcutLabel.textColor = colour
        }
        if let text = o.commandScroll.documentView as? NSTextView, text.textColor != colours.theme.text {
            text.textColor = colours.theme.text
            text.insertionPointColor = colours.theme.caret
        }
        frameCommand(colours)
        o.outline.needsDisplay = true
        o.split.needsDisplay = true
    }

    // MARK: Sheets

    /// The Undelete sheet's list in the Claude grid look. Its class can only be swapped before AppKit first lays the sheet
    /// out (a portal view then observes the list's layer by KVO, `SAClaudeClassSwap`), which happens on the first run loop
    /// turn after the nib loads, shown or not: called by the controller as it wakes from its nib, and again (a no-op) as
    /// the sheet begins.
    @objc(prepareUndeleteList:) static func prepareUndeleteList(_ table: NSTableView?) {
        if let table { styleUndeleteList(table) }
    }

    @discardableResult
    private static func styleUndeleteList(_ table: NSTableView) -> SAClaudeUtilityGridTableView? {
        guard let grid = SAClaudeUtilityGridTableView.adopt(table) else { return nil }
        if grid.style != .plain { grid.style = .plain }
        grid.state?.cellPadding = 8
        return grid
    }

    /// The Undelete sheet (its list in the Claude grid look, framed) and the Meta Info sheet (its description framed). True
    /// when `window` is one of them.
    private static func styleSheet(_ window: NSWindow) -> Bool {
        guard let parent = window.sheetParent, let controller = parent.windowController,
              SAClaudeFormOwners.className(of: controller) == "SPBundleEditorController",
              let contentView = window.contentView else { return false }
        if let undelete: NSWindow = outlet(controller, "undeleteSheet"), undelete === window {
            if let table: NSTableView = outlet(controller, "undeleteTableView"), let grid = styleUndeleteList(table) {
                grid.sizeLastColumnToFit()
                if let scrollView = grid.enclosingScrollView, scrollView.superview === contentView {
                    SAClaudeUtilityChrome.frameListOnceShown(scrollView)
                }
            }
            return true
        }
        if let meta: NSWindow = outlet(controller, "metaInfoSheet"), meta === window {
            if let text: NSTextView = outlet(controller, "descriptionTextView"), let scrollView = text.enclosingScrollView {
                text.textContainerInset = NSSize(width: 4, height: 4)
                SAClaudeUtilityChrome.frameListOnceShown(scrollView)
            }
            return true
        }
        return false
    }

}

/// The Claude field behind the Bundle Editor's shortcut recorder (which ShortcutRecorder keeps at most 22pt tall): the
/// field's fill and rounded hairline across the form row, the accent while the recorder has the keyboard focus (it
/// records). Never takes clicks.
@objc(SAClaudeRecorderFieldView) final class SAClaudeRecorderFieldView: NSView {
    weak var recorder: NSControl?

    override func draw(_ dirtyRect: NSRect) {
        let colours = SAClaudeSheetColours.current()
        let radius = SAClaudeSheetColours.fieldRadius
        let field = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: radius - 0.5, yRadius: radius - 0.5)
        colours.fieldFill.setFill()
        field.fill()
        let focused = recorder.map { $0.window?.firstResponder === $0 } ?? false
        (focused ? SAClaudeStatusChrome.clay : colours.palette.hairline).setStroke()
        field.lineWidth = 1
        field.stroke()
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// The Bundle Editor's shortcut recorder (`SRRecorderControl`, installed with `object_setClass`, no stored properties) on
/// its Claude field (`SAClaudeRecorderFieldView`): ShortcutRecorder draws a fixed white capsule; its drawing is rendered
/// off screen in the light appearance and only its ink (what is darker than the capsule's fill in each row) is drawn, in
/// the theme's text colour (muted while disabled), so its layout, hit areas, states and animation stay its own.
@objc(SAClaudeShortcutRecorderControl) final class SAClaudeShortcutRecorderControl: SRRecorderControl {

    /// Swaps an exact SRRecorderControl for this class; false when it can't (another class, or observed by KVO).
    @discardableResult
    static func adopt(_ control: NSControl) -> Bool {
        if control is SAClaudeShortcutRecorderControl { return true }
        guard type(of: control) == SRRecorderControl.self, SAClaudeClassSwap.mayChangeClass(of: control) else { return false }
        object_setClass(control, SAClaudeShortcutRecorderControl.self)
        control.needsDisplay = true
        return true
    }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        fieldView?.needsDisplay = true
        return became
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        fieldView?.needsDisplay = true
        return resigned
    }

    private var fieldView: SAClaudeRecorderFieldView? {
        superview?.subviews.lazy.compactMap { $0 as? SAClaudeRecorderFieldView }.first { $0.recorder === self }
    }

    override func draw(_ dirtyRect: NSRect) {
        let colours = SAClaudeSheetColours.current()
        let tint = isEnabled ? colours.theme.text : colours.muted
        guard let ink = Self.ink(of: self), let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        // The mask's first row is its top.
        if isFlipped {
            context.translateBy(x: 0, y: bounds.height)
            context.scaleBy(x: 1, y: -1)
        }
        context.clip(to: bounds, mask: ink)
        context.setFillColor(tint.cgColor)
        context.fill(bounds)
        context.restoreGState()
    }

    /// The recorder's own drawing reduced to a mask of its ink: rendered in the light appearance at the backing scale, each
    /// pixel's alpha is how much darker it is than the brightest pixel of its row (the capsule's fill), the capsule's
    /// outline (the outermost 2pt) left out.
    private static func ink(of control: NSControl) -> CGImage? {
        guard let cell = control.cell else { return nil }
        let scale = control.window?.backingScaleFactor ?? 2
        let width = Int(control.bounds.width * scale), height = Int(control.bounds.height * scale)
        guard width > 0, height > 0,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: width * 4, bitsPerPixel: 32),
              let bitmap = NSGraphicsContext(bitmapImageRep: rep), let pixels = rep.bitmapData else { return nil }
        let cg = bitmap.cgContext
        cg.scaleBy(x: scale, y: scale)
        if control.isFlipped {
            cg.translateBy(x: 0, y: control.bounds.height)
            cg.scaleBy(x: 1, y: -1)
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: control.isFlipped)
        NSAppearance(named: .aqua)?.performAsCurrentDrawingAppearance {
            cell.draw(withFrame: control.bounds, in: control)
        }
        NSGraphicsContext.current?.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        var mask = [UInt8](repeating: 0, count: width * height)
        let edge = Int(2 * scale)
        for y in edge..<max(edge, height - edge) {
            var brightest: CGFloat = 0
            var luminance = [CGFloat](repeating: 0, count: width)
            for x in 0..<width {
                let p = pixels + (y * width + x) * 4
                let alpha = CGFloat(p[3]) / 255
                guard alpha > 0 else { continue }
                // Premultiplied: undo it for the luminance.
                let lum = (0.299 * CGFloat(p[0]) + 0.587 * CGFloat(p[1]) + 0.114 * CGFloat(p[2])) / 255 / alpha
                luminance[x] = lum
                brightest = max(brightest, lum)
            }
            guard brightest > 0.2 else { continue }
            let inset = max(edge, (height / 2) / 2)
            for x in inset..<max(inset, width - inset) {
                let p = pixels + (y * width + x) * 4
                guard p[3] > 0 else { continue }
                let ink = max(0, min(1, (brightest - luminance[x]) / brightest)) * CGFloat(p[3]) / 255
                mask[y * width + x] = UInt8((ink * 255).rounded())
            }
        }
        // A grey image clips as an alpha mask: white (the ink) paints.
        guard let provider = CGDataProvider(data: Data(mask) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
                       space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}
