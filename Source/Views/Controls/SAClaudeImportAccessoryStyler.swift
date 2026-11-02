//
//  SAClaudeImportAccessoryStyler.swift
//  Sequel Ace
//
//  The Claude Import options strip and the Import from Clipboard sheet. The strip is the importer's `importView`
//  (the open panel's accessory, re-parented into the clipboard sheet by SPDataImport): a CSV · SQL switcher and the
//  encoding pop-up on top, then the CSV grid (first-line checkbox, four character fields) or the SQL error pop-up,
//  placed from `SAClaudeImportAccessoryLayout`. The XIB's constraints inside the strip are deactivated and its
//  static labels replaced; the format pop-up stays the model the switcher drives (`changeFormat:`), hidden. The
//  clipboard sheet gets a medium title, the preview in a hairline card in the editor font, and a strip sized to its
//  content. The generic skin keeps styling the controls (`SAClaudeWindowSkin`); this styler owns the frames. One
//  per importer, attached by `SAClaudeImportStyler.claim`; any missing outlet leaves the generic look.
//  App target only.
//

import AppKit

final class SAClaudeImportAccessoryStyler {

    private typealias Layout = SAClaudeImportAccessoryLayout

    private static var associationKey: UInt8 = 0

    private static let labelFont = NSFont.systemFont(ofSize: 12)
    private static let sheetTitleFont = NSFont.systemFont(ofSize: 15, weight: .medium)
    private static let cardRadius: CGFloat = 12
    /// The clipboard sheet's side margins (the preview card's; the strip brings its own).
    private static let sheetMargin: CGFloat = 16
    private static let previewTextInset = NSSize(width: 8, height: 8)
    /// The strip's minimum width: the CSV grid and the encoding row fit (and the clipboard sheet's 500pt minimum is
    /// wider).
    private static let minimumStripWidth: CGFloat = 460

    /// The importer's strip views, read once by KVC.
    private struct Outlets {
        let importView: NSView
        let tabView: NSTabView
        let csvView: NSView
        let sqlView: NSView
        let formatPopUp: NSPopUpButton
        let encodingPopUp: NSPopUpButton
        let firstLineSwitch: NSButton
        /// In the layout's order: fields terminated, fields enclosed, lines terminated, fields escaped.
        let csvFields: [NSTextField]
        let sqlErrorPopUp: NSPopUpButton

        init?(_ importer: NSObject) {
            func outlet<T>(_ key: String) -> T? { SAClaudeExportStyler.outlet(importer, key) }
            guard let importView: NSView = outlet("importView"), !importView.isFlipped,
                  let tabView: NSTabView = outlet("importTabView"), tabView.superview === importView,
                  let formatPopUp: NSPopUpButton = outlet("importFormatPopup"),
                  tabView.numberOfTabViewItems == 2, formatPopUp.numberOfItems == tabView.numberOfTabViewItems,
                  let csvView = tabView.tabViewItem(at: 0).view, let sqlView = tabView.tabViewItem(at: 1).view,
                  !csvView.isFlipped, !sqlView.isFlipped,
                  let encodingPopUp: NSPopUpButton = outlet("importEncodingPopup"), encodingPopUp.superview === importView,
                  let firstLineSwitch: NSButton = outlet("importFieldNamesSwitch"), firstLineSwitch.superview === csvView,
                  let terminated: NSTextField = outlet("importFieldsTerminatedField"),
                  let enclosed: NSTextField = outlet("importFieldsEnclosedField"),
                  let linesTerminated: NSTextField = outlet("importLinesTerminatedField"),
                  let escaped: NSTextField = outlet("importFieldsEscapedField"),
                  let sqlErrorPopUp: NSPopUpButton = outlet("importSQLErrorHandlingPopup"), sqlErrorPopUp.superview === sqlView
            else { return nil }
            let csvFields = [terminated, enclosed, linesTerminated, escaped]
            guard csvFields.allSatisfy({ $0.superview === csvView }) else { return nil }
            self.importView = importView
            self.tabView = tabView
            self.csvView = csvView
            self.sqlView = sqlView
            self.formatPopUp = formatPopUp
            self.encodingPopUp = encodingPopUp
            self.firstLineSwitch = firstLineSwitch
            self.csvFields = csvFields
            self.sqlErrorPopUp = sqlErrorPopUp
        }
    }

    /// The Import from Clipboard sheet: the window, its preview and the container the strip is moved into.
    private struct ClipboardOutlets {
        let sheet: NSWindow
        let textView: NSTextView
        let container: NSView

        init?(_ importer: NSObject) {
            guard let sheet: NSWindow = SAClaudeExportStyler.outlet(importer, "importFromClipboardSheet"),
                  let textView: NSTextView = SAClaudeExportStyler.outlet(importer, "importFromClipboardTextView"),
                  let container: NSView = SAClaudeExportStyler.outlet(importer, "importFromClipboardAccessoryView") else { return nil }
            self.sheet = sheet
            self.textView = textView
            self.container = container
        }
    }

    private let outlets: Outlets
    private let clipboard: ClipboardOutlets?

    // Added views.
    private let switcher = SAClaudeConnectionTypeTabs()
    private let encodingLabel = NSTextField(labelWithString: NSLocalizedString("ClaudeImportEncoding", value: "Encoding", comment: "import options: label of the file encoding pop-up"))
    private let csvLabels = [
        NSTextField(labelWithString: NSLocalizedString("ClaudeImportFieldsTerminated", value: "Fields terminated", comment: "import options: label of the CSV field separator field")),
        NSTextField(labelWithString: NSLocalizedString("ClaudeImportFieldsEnclosed", value: "Fields enclosed", comment: "import options: label of the CSV field enclosing character field")),
        NSTextField(labelWithString: NSLocalizedString("ClaudeImportLinesTerminated", value: "Lines terminated", comment: "import options: label of the CSV line terminator field")),
        NSTextField(labelWithString: NSLocalizedString("ClaudeImportFieldsEscaped", value: "Fields escaped", comment: "import options: label of the CSV escape character field")),
    ]
    private let sqlLabel = NSTextField(labelWithString: NSLocalizedString("ClaudeImportOnSQLError", value: "On SQL error", comment: "import options: label of the pop-up choosing what to do when a SQL statement fails"))
    private let previewCard = SAClaudeTableInfoCardView()

    private var clipboardStyled = false
    /// The clipboard box's height constraint, which sizes the container the strip fills there.
    private weak var clipboardBoxHeight: NSLayoutConstraint?
    /// `importView`'s minimum width and height, which the open panel reads (see `fitImportView`).
    private var minimumWidthConstraint: NSLayoutConstraint?
    private var heightConstraint: NSLayoutConstraint?
    private var isLayingOut = false
    private var layOutPending = false

    private var stripColours: (SAClaudeEditorChrome.Palette, NSColor, NSColor)?
    private var previewPalette: SAClaudeEditorChrome.Palette?

    private var frameObservers: [NSObjectProtocol] = []
    private var observations: [NSKeyValueObservation] = []

    // MARK: - Attaching

    /// Restyles and lays out `importer`'s (an `SPDataImport`) options strip, once; returns its styler. Nil (and the
    /// generic look) when an expected outlet or XIB view is missing.
    @discardableResult
    static func attach(importer: NSObject) -> SAClaudeImportAccessoryStyler? {
        if let existing = objc_getAssociatedObject(importer, &associationKey) as? SAClaudeImportAccessoryStyler { return existing }
        guard let outlets = Outlets(importer) else { return nil }
        let styler = SAClaudeImportAccessoryStyler(outlets: outlets, clipboard: ClipboardOutlets(importer))
        objc_setAssociatedObject(importer, &associationKey, styler, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        styler.build()
        return styler
    }

    /// `window` (the open panel or the clipboard sheet) is being shown or became key: the clipboard sheet is styled
    /// (once; its preview font each time, SPDataImport resets it at every show) and the strip laid out where it now is.
    func claim(_ window: NSWindow) {
        if let clipboard, window === clipboard.sheet {
            styleClipboardSheet()
            let font = SAClaudeCompletionStyler.editorFont()
            if clipboard.textView.font != font { clipboard.textView.font = font }
        }
        refresh(force: false)
        layOut()
    }

    private init(outlets: Outlets, clipboard: ClipboardOutlets?) {
        self.outlets = outlets
        self.clipboard = clipboard
    }

    deinit {
        for observer in frameObservers { NotificationCenter.default.removeObserver(observer) }
        observations.forEach { $0.invalidate() }
    }

    // MARK: - Building

    private func build() {
        let o = outlets
        releaseFromConstraints()
        let minimumWidth = o.importView.widthAnchor.constraint(greaterThanOrEqualToConstant: Self.minimumStripWidth)
        minimumWidth.identifier = "SAClaudeImportStripMinimumWidth"
        minimumWidth.isActive = true
        minimumWidthConstraint = minimumWidth
        o.tabView.tabViewType = .noTabsNoBorder
        o.tabView.drawsBackground = false
        // The XIB's labels ("Format:", "Encoding:", the CSV and SQL labels) and the format pop-up; the switcher and
        // the labels below take their places.
        for container in [o.importView, o.csvView, o.sqlView] {
            for case let label as NSTextField in container.subviews where !label.isEditable && !(label is NSComboBox) {
                label.isHidden = true
            }
        }
        o.formatPopUp.isHidden = true

        switcher.titles = o.formatPopUp.itemTitles
        switcher.accessibilityGroupLabel = NSLocalizedString("ClaudeImportFormatSwitcher", value: "Import format", comment: "import options: accessibility name of the CSV / SQL format switcher")
        switcher.onSelect = { [weak self, weak popUp = o.formatPopUp] index in
            guard let popUp, index < popUp.numberOfItems else { return }
            popUp.selectItem(at: index)
            if let action = popUp.action { NSApp.sendAction(action, to: popUp.target, from: popUp) }
            self?.layOut()
        }
        o.importView.addSubview(switcher)

        for label in [encodingLabel, sqlLabel] + csvLabels {
            label.font = Self.labelFont
            label.lineBreakMode = .byTruncatingTail
        }
        o.importView.addSubview(encodingLabel)
        for label in csvLabels { o.csvView.addSubview(label) }
        o.sqlView.addSubview(sqlLabel)
        // VoiceOver reads the new labels as the controls' titles (the XIB's are hidden).
        let titled: [(NSView, NSTextField)] = [(o.encodingPopUp, encodingLabel), (o.sqlErrorPopUp, sqlLabel)] + Array(zip(o.csvFields, csvLabels))
        for (control, label) in titled { control.setAccessibilityTitleUIElement(label) }

        refresh(force: true)
        layOut()
        observe()
    }

    /// Deactivates the XIB's constraints that place the strip's views (between its subviews, inside the two tab items,
    /// and the placed controls' own sizes), and hands the placed controls to their frames. The width an open panel
    /// may have pinned on the strip goes too (the strip's own minimum replaces it, see `fitImportView`).
    private func releaseFromConstraints() {
        let o = outlets
        let placed: [NSView] = [o.tabView, o.encodingPopUp, o.firstLineSwitch, o.sqlErrorPopUp] + o.csvFields
        var constraints = o.importView.constraints + o.csvView.constraints + o.sqlView.constraints
        // A control's own pinned width or height (the fields' 17pt, the SQL pop-up's 20pt) would fight its frame.
        for view in placed {
            constraints += view.constraints.filter { $0.priority == .required && ($0.firstItem === view || $0.secondItem === view) }
        }
        NSLayoutConstraint.deactivate(constraints.filter { !Self.isAutoresizing($0) })
        for view in placed where !view.translatesAutoresizingMaskIntoConstraints {
            view.translatesAutoresizingMaskIntoConstraints = true
        }
    }

    /// AppKit's constraints for a view's autoresizing mask (a private class).
    private static let autoresizingConstraintClass: AnyClass? = NSClassFromString("NSAutoresizingMaskLayoutConstraint")

    private static func isAutoresizing(_ constraint: NSLayoutConstraint) -> Bool {
        autoresizingConstraintClass.map { constraint.isKind(of: $0) } ?? false
    }

    private func observe() {
        let o = outlets
        // Each panel stretches the strip to its width; the clipboard sheet resizes its container.
        o.importView.postsFrameChangedNotifications = true
        frameObservers.append(NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: o.importView, queue: nil) { [weak self] _ in
            Self.onMain { self?.layOut() }
        })
        // The importer changes the format in code (`changeFormat:` from the saved format and from the panel's
        // selection). NSTabView posts no KVO for its selected item; its items' `tabState` does change.
        for item in o.tabView.tabViewItems {
            observations.append(item.observe(\.tabState, options: [.new]) { [weak self] _, _ in
                Self.onMain { self?.scheduleLayOut() }
            })
        }
        observations.append(o.importView.observe(\.effectiveAppearance) { [weak self] _, _ in
            Self.onMain { self?.refresh(force: true) }
        })
        if let clipboard {
            observations.append(clipboard.sheet.observe(\.effectiveAppearance) { [weak self] _, _ in
                Self.onMain { self?.refresh(force: true) }
            })
        }
        SAClaudeThemeWatcher.observe(self) { $0.refresh(force: false) }
        SAClaudeAccent.observe(self) { $0.refresh(force: true) }
    }

    private static func onMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
    }

    // MARK: - Clipboard sheet

    /// The title in SF Pro 15 medium, the preview in a hairline card (16pt from the sides), the strip's box drawn
    /// no more and as wide as the sheet (the strip has its own margins). Once; the buttons keep the generic skin.
    private func styleClipboardSheet() {
        guard !clipboardStyled, let clipboard, let contentView = clipboard.sheet.contentView,
              let scrollView = clipboard.textView.enclosingScrollView, scrollView.superview === contentView else { return }
        clipboardStyled = true

        // The title has no outlet: the topmost static text of the sheet.
        let title = contentView.subviews.compactMap { $0 as? NSTextField }
            .filter { !$0.isEditable && !$0.isHidden }.max { $0.frame.maxY < $1.frame.maxY }
        title?.font = Self.sheetTitleFont

        // The card draws the preview's background and outline: the scroll view and the text view draw none (their
        // square corners would cover the rounded ones).
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        clipboard.textView.drawsBackground = false
        clipboard.textView.textContainerInset = Self.previewTextInset
        Self.inset(scrollView, from: [.leading, .trailing], of: contentView, by: Self.sheetMargin)
        previewCard.radius = Self.cardRadius
        contentView.addSubview(previewCard, positioned: .below, relativeTo: scrollView)
        scrollView.postsFrameChangedNotifications = true
        frameObservers.append(NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: scrollView, queue: nil) { [weak self, weak scrollView] _ in
            Self.onMain {
                guard let self, let scrollView else { return }
                self.placePreviewCard(around: scrollView)
            }
        })

        if let box = clipboard.container.superview?.superview as? NSBox, let boxParent = box.superview {
            box.isTransparent = true
            box.contentViewMargins = .zero
            Self.inset(box, from: [.leading, .trailing], of: boxParent, by: 0)
            clipboardBoxHeight = box.constraints.first {
                $0.isActive && !Self.isAutoresizing($0) && $0.firstItem === box && $0.secondItem == nil
                    && $0.firstAttribute == .height && $0.relation == .equal
            }
        }
        contentView.layoutSubtreeIfNeeded()
        placePreviewCard(around: scrollView)
        refresh(force: true)
    }

    private func placePreviewCard(around scrollView: NSScrollView) {
        if previewCard.frame != scrollView.frame { previewCard.frame = scrollView.frame }
    }

    /// Sets the constraints pinning `view`'s `edges` to the same edges of `superview` to an inset of `inset`.
    private static func inset(_ view: NSView, from edges: [NSLayoutConstraint.Attribute], of superview: NSView, by inset: CGFloat) {
        for edge in edges {
            for constraint in superview.constraints where constraint.isActive && constraint.relation == .equal
                && constraint.firstAttribute == edge && constraint.secondAttribute == edge {
                let viewFirst = constraint.firstItem === view && constraint.secondItem === superview
                guard viewFirst || (constraint.firstItem === superview && constraint.secondItem === view) else { continue }
                // leading: view = superview + c (or superview = view − c); trailing the other way round.
                let constant = (edge == .leading) == viewFirst ? inset : -inset
                if constraint.constant != constant { constraint.constant = constant }
            }
        }
    }

    // MARK: - Colours

    /// Re-derives the colours when the editor theme changed (always, when `force`) and recolours the added views:
    /// the strip's in its own appearance (the skin gives it the theme's), the preview card in the sheet's.
    private func refresh(force: Bool) {
        var resolved: (SAClaudeEditorChrome.Palette, NSColor, NSColor)?
        outlets.importView.effectiveAppearance.performAsCurrentDrawingAppearance {
            let palette = SAClaudeEditorChrome.palette(from: .standard)
            let theme = SAClaudeThemeColours.from(defaults: .standard)
            resolved = (palette, theme.text, SAClaudeFilterChrome.cardFill(text: theme.text, background: SAClaudeStatusChrome.popupSurface(theme: theme)))
        }
        if let (palette, text, fill) = resolved,
           force || stripColours.map({ $0.0 != palette || $0.1 != text || $0.2 != fill }) ?? true {
            stripColours = (palette, text, fill)
            let muted = palette.icon
            for label in [encodingLabel, sqlLabel] + csvLabels where label.textColor != muted { label.textColor = muted }
            switcher.colours = SAClaudeConnectionTypeTabs.Colours(selectedFill: fill, selectedStroke: palette.hairline, hoverFill: palette.hover,
                                                                  text: text, mutedText: muted)
        }

        guard clipboardStyled, let clipboard else { return }
        var previewPalette: SAClaudeEditorChrome.Palette?
        clipboard.sheet.effectiveAppearance.performAsCurrentDrawingAppearance {
            previewPalette = SAClaudeEditorChrome.palette(from: .standard)
        }
        guard let previewPalette, force || previewPalette != self.previewPalette else { return }
        self.previewPalette = previewPalette
        previewCard.fill = previewPalette.background
        previewCard.stroke = previewPalette.hairline
        let font = SAClaudeCompletionStyler.editorFont()
        if clipboard.textView.font != font { clipboard.textView.font = font }
    }

    // MARK: - Layout

    /// One layout on the next main-queue turn, after the tab view finished switching items.
    private func scheduleLayOut() {
        guard !layOutPending else { return }
        layOutPending = true
        DispatchQueue.main.async { [weak self] in
            self?.layOutPending = false
            self?.layOut()
        }
    }

    /// Sizes the strip for the selected format (its height; the width is the panel's or the clipboard sheet's)
    /// and places the switcher, the encoding row and the selected format's controls.
    func layOut() {
        let o = outlets
        guard !isLayingOut else { return }
        isLayingOut = true
        defer { isLayingOut = false }

        // What the tab view shows (index 0 CSV, 1 SQL), not the pop-up: SPDataImport can select "SQL" in the pop-up
        // without `changeFormat:` (`startSQLImportProcessWithFile:`), and the strip must fit the item on screen.
        let index = o.tabView.selectedTabViewItem.map { o.tabView.indexOfTabViewItem($0) } ?? 0
        if index >= 0, switcher.selectedIndex != index { switcher.selectedIndex = index }
        let format: Layout.Format = index == 1 ? .sql : .csv
        chainKeyViews(format)
        let switcherWidth = ceil(switcher.preferredWidth)
        let labelWidth = ceil(encodingLabel.cell?.cellSize.width ?? 0)
        fitImportView(height: Layout.frames(width: o.importView.bounds.width, format: format, switcherWidth: switcherWidth,
                                            encodingLabelWidth: labelWidth).height)
        let width = o.importView.bounds.width
        guard width > 0 else { return }
        let f = Layout.frames(width: width, format: format, switcherWidth: switcherWidth, encodingLabelWidth: labelWidth)

        Self.place(switcher, f.formatSwitcher)
        Self.placeLabel(encodingLabel, f.encodingLabel)
        Self.place(o.encodingPopUp, f.encoding)
        // The tab view fills the strip below the switcher row; each item's view fills the tab view.
        Self.place(o.tabView, NSRect(x: 0, y: 0, width: width, height: max(0, f.formatSwitcher.minY)))
        let content = o.tabView.contentRect
        for item in o.tabView.tabViewItems {
            if let view = item.view, view.frame != content { view.frame = content }
        }
        // The layout's frames are the strip's: shift them into the items' views. Both formats' controls are placed
        // (each from its own frames; the tab view keeps its bottom edge), so the item shown next is already in place.
        let origin = o.tabView.convert(content, to: o.importView).origin
        func inItem(_ rect: NSRect) -> NSRect { rect.offsetBy(dx: -origin.x, dy: -origin.y) }
        let csv = format == .csv ? f : Layout.frames(width: width, format: .csv, switcherWidth: switcherWidth, encodingLabelWidth: labelWidth)
        let sql = format == .sql ? f : Layout.frames(width: width, format: .sql, switcherWidth: switcherWidth, encodingLabelWidth: labelWidth)
        Self.place(o.firstLineSwitch, inItem(csv.firstLine))
        for (index, field) in o.csvFields.enumerated() where csv.csvFields.indices.contains(index) {
            Self.placeLabel(csvLabels[index], inItem(csv.csvLabels[index]))
            Self.place(field, inItem(csv.csvFields[index]))
        }
        Self.placeLabel(sqlLabel, inItem(sql.sqlLabel))
        Self.place(o.sqlErrorPopUp, inItem(sql.sqlPopUp))
    }

    /// Tab order in the strip's visual order: switcher → encoding → first line → fields terminated → fields enclosed →
    /// lines terminated → fields escaped (CSV), or switcher → encoding → On SQL error (SQL). The last control leads
    /// nowhere, as the XIB's last one did (the window goes on from there).
    private func chainKeyViews(_ format: Layout.Format) {
        let o = outlets
        let chain: [NSView] = [switcher, o.encodingPopUp] + (format == .csv ? [o.firstLineSwitch] + o.csvFields : [o.sqlErrorPopUp])
        for (view, next) in zip(chain, chain.dropFirst()) where view.nextKeyView !== next || next.previousKeyView !== view {
            // Re-setting the same next view may not touch its previous view: clear first.
            if view.nextKeyView === next { view.nextKeyView = nil }
            view.nextKeyView = next
        }
        if let last = chain.last, last.nextKeyView != nil { last.nextKeyView = nil }
    }

    /// Gives the strip `height`: its frame and its height constraint. The open panel sizes an accessory that has
    /// constraints from its fitting size, and re-reads it as they change (one without any, from its frame when set,
    /// never again). Once the XIB's constraints are gone, the strip's own minimum width and this height are its
    /// fitting size: every panel shows the strip's height as the format changes, and stretches it to its own width
    /// (with a fitting width of 0 AppKit would pin the strip's first width instead, and log). The height is just
    /// below required: SPDataImport sets the strip's frame to the clipboard container's before the layout here
    /// follows. In the clipboard sheet the strip fills its container, whose box is resized to match.
    private func fitImportView(height: CGFloat) {
        let view = outlets.importView
        if let container = view.superview, container === clipboard?.container {
            // A minimum width an open panel left on the strip (its width then) the narrower sheet can't meet: here
            // the container gives the strip its width.
            NSLayoutConstraint.deactivate(view.constraints.filter {
                $0 !== minimumWidthConstraint && $0.isActive && $0.firstItem === view && $0.secondItem == nil && $0.firstAttribute == .width
            })
            let delta = height - container.bounds.height
            if delta != 0, let constraint = clipboardBoxHeight {
                constraint.constant += delta
                // The box follows at the sheet's next layout pass; the container now, so the strip and the layout
                // below agree with it.
                container.setFrameSize(NSSize(width: container.frame.width, height: height))
            }
            // Top-aligned should the container keep another height (no box constraint).
            let target = NSRect(x: 0, y: max(0, container.bounds.height - height), width: container.bounds.width, height: height)
            if view.frame != target { view.frame = target }
        } else if view.frame.height != height {
            view.setFrameSize(NSSize(width: view.frame.width, height: height))
        }
        if let heightConstraint {
            if heightConstraint.constant != height { heightConstraint.constant = height }
        } else {
            let constraint = view.heightAnchor.constraint(equalToConstant: height)
            constraint.identifier = "SAClaudeImportStripHeight"
            constraint.priority = NSLayoutConstraint.Priority(NSLayoutConstraint.Priority.required.rawValue - 1)
            constraint.isActive = true
            heightConstraint = constraint
        }
    }

    private static func place(_ view: NSView, _ frame: NSRect) {
        let aligned = NSRect(x: frame.minX.rounded(), y: frame.minY.rounded(), width: frame.width.rounded(), height: frame.height.rounded())
        if view.frame != aligned { view.frame = aligned }
        if !view.autoresizingMask.isEmpty { view.autoresizingMask = [] }
    }

    /// A one-line label at its text height, centred on `frame`'s row.
    private static func placeLabel(_ label: NSTextField, _ frame: NSRect) {
        let height = ceil(label.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)).height ?? frame.height)
        place(label, NSRect(x: frame.minX, y: (frame.midY - height / 2).rounded(.down), width: frame.width, height: height))
    }
}
