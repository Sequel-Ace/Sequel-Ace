//
//  SAClaudeSheetStyler.swift
//  Sequel Ace
//
//  Restyles every sheet, NSAlert and listed auxiliary window in the Claude
//  look as it opens: the theme surface and a matching light/dark appearance,
//  Claude buttons, checkboxes, radios, pills and fields, theme-coloured
//  labels, hairline separators and titled boxes, quiet tables and themed text
//  views. Which windows: `SAClaudeSheetTargeting`; which control gets which
//  look: `SAClaudeSheetRules`. Controls are restyled in place (cell / class
//  swaps without stored properties, colours, a field's layer): wording,
//  frames, bindings, targets and actions stay as the XIB or the code made
//  them. Each restyled window keeps an `SAClaudeWindowSkin`, which recolours
//  it when the editor theme, the accent or the appearance changes, and walks
//  it again whenever it becomes key, so views added since are styled too.
//  App target only.
//

import AppKit

@objc(SAClaudeSheetStyler) final class SAClaudeSheetStyler: NSObject {

    private static var observers: [NSObjectProtocol] = []

    /// Starts watching windows app-wide and styling the app's alert helpers' alerts (once; call at launch).
    @objc static func start() {
        guard observers.isEmpty else { return }
        // NSAlert's helper factories (NSAlertExtension.swift) style their alert before it shows, so it never flashes native.
        SAAlertPresentation.willPresent = { styleAlert($0) }
        let centre = NotificationCenter.default
        // No observer queue: windows post these on main, and a queue would only add a hop.
        observers.append(centre.addObserver(forName: NSWindow.willBeginSheetNotification, object: nil, queue: nil) { note in
            onMain {
                guard let parent = note.object as? NSWindow else { return }
                if let sheet = parent.attachedSheet { consider(sheet) }
                // AppKit may attach the sheet only after posting; catch it next turn (or when it becomes key).
                DispatchQueue.main.async { [weak parent] in
                    if let sheet = parent?.attachedSheet { consider(sheet) }
                }
            }
        })
        observers.append(centre.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: nil) { note in
            onMain {
                if let window = note.object as? NSWindow { consider(window) }
            }
        })
    }

    /// Styles `alert`'s window before it is shown: its first button primary (unless destructive), the others
    /// secondary, its texts, suppression checkbox and accessory view. Lays the alert out. Call right before
    /// `runModal()` / `beginSheetModal(for:)`.
    @objc(styleAlert:) static func styleAlert(_ alert: NSAlert) {
        // The buttons first: once the alert has laid itself out its stack view observes them, and the class of
        // an observed object must not change (see `SAClaudeWindowSkin.mayChangeClass(of:)`).
        for button in alert.buttons { SAClaudeWindowSkin.styleButton(button, alert: alert) }
        if alert.showsSuppressionButton, let suppression = alert.suppressionButton {
            SAClaudeWindowSkin.styleButton(suppression, alert: alert)
        }
        alert.layout()
        skinAlert(alert)
    }

    private static func onMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
    }

    private static func skinAlert(_ alert: NSAlert) {
        let window = alert.window
        if let skin = SAClaudeWindowSkin.skin(for: window) {
            skin.alert = alert
            skin.refresh(force: true)
        } else {
            SAClaudeWindowSkin.attach(to: window, alert: alert)
        }
    }

    // MARK: - Targets

    /// Restyles `window` if it is a target: already skinned windows are walked again with the current colours.
    static func consider(_ window: NSWindow) {
        if let skin = SAClaudeWindowSkin.skin(for: window) {
            skin.refresh(force: true)
            return
        }
        let alert = (window.delegate as? NSAlert).flatMap { $0.window === window ? $0 : nil }
        var facts = SAClaudeSheetTargeting.Facts()
        facts.isAlertWindow = alert != nil
        facts.isSavePanel = window is NSSavePanel
        facts.isPlainOrAppWindowClass = isPlainOrAppClass(visibleClass(of: window))
        facts.hasSheetParent = window.sheetParent != nil
        facts.ownerClasses = [window.windowController as AnyObject?, window.delegate as AnyObject?]
            .compactMap { $0 }
            .map { NSStringFromClass(visibleClass(of: $0)) }

        switch SAClaudeSheetTargeting.decision(for: facts) {
        case .alert:
            if let alert { skinAlert(alert) }
        case .accessoryOnly:
            guard let accessory = (window as? NSSavePanel)?.accessoryView else { return }
            if let skin = SAClaudeWindowSkin.skin(for: accessory) {
                skin.refresh(force: true)
            } else {
                SAClaudeWindowSkin.attach(toAccessory: accessory, in: window)
            }
        case .window:
            SAClaudeWindowSkin.attach(to: window, alert: nil)
        case .skip:
            break
        }
    }

    /// The object's class as its code sees it: KVO's runtime subclasses are skipped.
    static func visibleClass(of object: AnyObject) -> AnyClass {
        var cls: AnyClass = object_getClass(object) ?? NSObject.self
        while NSStringFromClass(cls).hasPrefix("NSKVONotifying_"), let superclass = class_getSuperclass(cls) {
            cls = superclass
        }
        return cls
    }

    /// NSWindow, NSPanel or a window class of the app itself (not a system panel, popover or other private window).
    private static func isPlainOrAppClass(_ cls: AnyClass) -> Bool {
        cls == NSWindow.self || cls == NSPanel.self || Bundle(for: cls) == Bundle.main
    }
}

// MARK: - Window skin

/// The Claude look of one window (or of one open / save panel's accessory view): applies it, keeps it in step
/// with the theme, the accent and the appearance, and shows the accent outline on the field being edited.
/// Retained by the window (or the accessory view) it styles; marks it as styled.
final class SAClaudeWindowSkin: NSObject {

    private static var associationKey: UInt8 = 0
    private static let surfaceIdentifier = NSUserInterfaceItemIdentifier("SAClaudeSheetSurface")

    private weak var window: NSWindow?
    /// Set for an accessory skin: only this subtree is styled; the panel itself stays native.
    private weak var accessory: NSView?
    /// The alert whose window this is; its buttons get the alert roles.
    weak var alert: NSAlert?

    private var applied: (theme: SAClaudeThemeColours, accent: NSColor)?
    private var colours: SAClaudeSheetColours?
    private let fields = NSHashTable<NSTextField>.weakObjects()

    private var observations: [NSKeyValueObservation] = []

    /// Every live skin, for the shared theme check.
    private static let skins = NSHashTable<SAClaudeWindowSkin>.weakObjects()
    private static var defaultsObserver: NSObjectProtocol?
    private static var themeCheckPending = false
    private static var lastTheme: SAClaudeThemeColours?

    // MARK: Attaching

    static func skin(for object: NSObject) -> SAClaudeWindowSkin? {
        objc_getAssociatedObject(object, &associationKey) as? SAClaudeWindowSkin
    }

    @discardableResult
    static func attach(to window: NSWindow, alert: NSAlert?) -> SAClaudeWindowSkin {
        if let existing = skin(for: window) { return existing }
        let skin = SAClaudeWindowSkin()
        skin.window = window
        skin.alert = alert
        objc_setAssociatedObject(window, &associationKey, skin, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        skin.observe()
        // Preferences swaps its whole content view per pane.
        skin.observations.append(window.observe(\.contentView) { [weak skin] _, _ in
            DispatchQueue.main.async { skin?.refresh(force: true) }
        })
        skin.refresh(force: true)
        return skin
    }

    @discardableResult
    static func attach(toAccessory accessory: NSView, in window: NSWindow) -> SAClaudeWindowSkin {
        if let existing = skin(for: accessory) { return existing }
        let skin = SAClaudeWindowSkin()
        skin.window = window
        skin.accessory = accessory
        objc_setAssociatedObject(accessory, &associationKey, skin, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        skin.observe()
        skin.refresh(force: true)
        return skin
    }

    private func observe() {
        Self.skins.add(self)
        Self.observeDefaults()
        SAClaudeAccent.observe(self) { $0.refresh(force: true) }
        // Dynamic fallback colours (no theme saved yet) resolve differently in light and dark.
        observations.append(NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            DispatchQueue.main.async { self?.refresh(force: true) }
        })
        if let window {
            observations.append(window.observe(\.firstResponder) { [weak self] _, _ in
                DispatchQueue.main.async { self?.updateFocus() }
            })
        }
    }

    /// One observer for all skins: any defaults write may be a theme change.
    private static func observeDefaults() {
        guard defaultsObserver == nil else { return }
        // No `queue: .main`: a defaults write on a background thread must not wait for the main queue.
        defaultsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: nil) { _ in
            DispatchQueue.main.async { scheduleThemeCheck() }
        }
    }

    /// One theme check on the next main-queue turn, however many defaults writes ask for it before then (window
    /// frames and split positions are saved continuously); skins restyle only when the theme changed.
    private static func scheduleThemeCheck() {
        guard !themeCheckPending else { return }
        themeCheckPending = true
        DispatchQueue.main.async {
            themeCheckPending = false
            var theme: SAClaudeThemeColours?
            NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
                theme = SAClaudeThemeColours.from(defaults: .standard)
            }
            guard theme != lastTheme else { return }
            lastTheme = theme
            skins.allObjects.forEach { $0.refresh(force: false) }
        }
    }

    // MARK: Refreshing

    /// Restyles everything when the theme or the accent changed (always, when `force`).
    func refresh(force: Bool) {
        guard let root = accessory ?? window?.contentView else { return }
        let colours = SAClaudeSheetColours.current()
        // The Claude cells read these at draw time.
        SAClaudeFilterBarStyler.currentPalette = colours.palette
        SAClaudeFilterBarStyler.currentThemeText = colours.theme.text
        let accent = SAClaudeAccent.accent
        if !force, let applied, applied.theme == colours.theme, applied.accent == accent { return }
        applied = (colours.theme, accent)
        self.colours = colours

        applyChrome(colours, root: root)
        style(root, colours)
        updateFocus()
        SAClaudeAccent.redisplay(root)
    }

    /// The appearance from the theme's lightness and the theme surface behind everything.
    private func applyChrome(_ colours: SAClaudeSheetColours, root: NSView) {
        let appearanceName: NSAppearance.Name = colours.isDark ? .darkAqua : .aqua
        if accessory != nil {
            if root.appearance?.name != appearanceName { root.appearance = NSAppearance(named: appearanceName) }
        } else if let window {
            if window.appearance?.name != appearanceName { window.appearance = NSAppearance(named: appearanceName) }
            if window.backgroundColor != colours.surface { window.backgroundColor = colours.surface }
        }
        let surface: SAClaudeEditorBarBackgroundView
        if let existing = root.subviews.first(where: { $0.identifier == Self.surfaceIdentifier }) as? SAClaudeEditorBarBackgroundView {
            surface = existing
        } else {
            surface = SAClaudeEditorBarBackgroundView(frame: root.bounds)
            surface.identifier = Self.surfaceIdentifier
            surface.autoresizingMask = [.width, .height]
            root.addSubview(surface, positioned: .below, relativeTo: nil)
        }
        if surface.frame != root.bounds { surface.frame = root.bounds }
        surface.fillColour = colours.surface
    }

    // MARK: Walking

    /// Styles `view` and, unless it is a control (whose subviews are AppKit's own), everything inside it.
    private func style(_ view: NSView, _ colours: SAClaudeSheetColours) {
        if view.identifier == Self.surfaceIdentifier { return }
        // SwiftUI content (Settings' Claude colours section, AppKit's own hosting views) styles itself.
        if String(describing: type(of: view)).contains("HostingView") { return }
        switch view {
        case let popUp as NSPopUpButton:
            stylePopUp(popUp)
        case let button as NSButton:
            Self.styleButton(button, alert: alert)
        case let field as NSTextField:
            styleTextField(field, colours)
        case let box as NSBox:
            styleBox(box)
            view.subviews.forEach { style($0, colours) }
        case let table as NSTableView:
            styleTable(table, colours)
        case let textView as NSTextView:
            styleTextView(textView, colours)
        case let tabView as NSTabView:
            // Every tab, including those not on screen now.
            for item in tabView.tabViewItems {
                if let itemView = item.view { style(itemView, colours) }
            }
        case is NSControl:
            // Steppers, sliders, segmented controls, colour wells, matrices, image views, …: unchanged.
            break
        default:
            view.subviews.forEach { style($0, colours) }
        }
    }

    // MARK: Buttons

    /// Gives `button` its Claude look; `alert` is the alert whose window it is in, for the alert button roles.
    static func styleButton(_ button: NSButton, alert: NSAlert?) {
        guard let cell = button.cell as? NSButtonCell else { return }
        var d = SAClaudeControlDescriptor(kind: .button)
        d.buttonType = buttonType(of: cell)
        d.bezelStyle = button.bezelStyle
        d.title = button.title
        d.keyEquivalent = button.keyEquivalent
        d.isDestructive = button.hasDestructiveAction
        if let index = alert?.buttons.firstIndex(where: { $0 === button }) {
            d.isAlertButton = true
            d.alertButtonIndex = index
        }
        let style = SAClaudeSheetRules.style(for: d)
        switch style {
        case .primaryButton, .secondaryButton:
            // A borderless titled push button (a link-like text button) keeps its native look.
            guard button.isBordered || d.isAlertButton else { return }
            let primary = style == .primaryButton
            // An observed button (an alert shown without the helpers: its stack view observes its buttons) stays native.
            guard mayChangeClass(of: button), mayChangeClass(of: cell) else { return }
            if !SAClaudeFilterCells.switchSheetButton(button, toPrimary: primary) {
                let cellClass: AnyClass = primary ? SAClaudeSheetPrimaryButtonCell.self : SAClaudeSheetSecondaryButtonCell.self
                guard SAClaudeFilterCells.install(cellClass, on: button) else { return }
            }
            if !primary { SAClaudeSheetHoverTracker.attach(to: button) }
        case .checkbox, .radio:
            guard mayChangeClass(of: button), mayChangeClass(of: cell) else { return }
            SAClaudeFilterCells.install(style == .checkbox ? SAClaudeCheckboxCell.self : SAClaudeRadioCell.self, on: button)
        default:
            break
        }
    }

    /// Whether the styler may swap `object`'s class: always for an object already in a Claude class (nothing is
    /// swapped again), otherwise only while nothing observes it. KVO finds an observance by the observed object's
    /// class, so after a swap the observer's removal (an NSStackView dropping its arranged buttons) throws.
    static func mayChangeClass(of object: NSObject) -> Bool {
        NSStringFromClass(type(of: object)).hasPrefix("SAClaude") || object.observationInfo == nil
    }

    /// `.switch` for a checkbox, `.radio` for a radio button (by the cell's accessibility role and its
    /// contents-drawn state, so a toggle push button is not mistaken for one), else `.momentaryPushIn`.
    private static func buttonType(of cell: NSButtonCell) -> NSButton.ButtonType {
        if cell is SAClaudeCheckboxCell { return .switch }
        if cell is SAClaudeRadioCell { return .radio }
        guard cell.showsStateBy == .contentsCellMask, cell.highlightsBy == .contentsCellMask else { return .momentaryPushIn }
        switch cell.accessibilityRole() {
        case NSAccessibility.Role.checkBox?: return .switch
        case NSAccessibility.Role.radioButton?: return .radio
        default: return .momentaryPushIn
        }
    }

    /// A bordered pop-up showing a title becomes a pill; borderless and image-only ones (gear menus) stay native,
    /// as the pill cell draws titles, not images.
    private func stylePopUp(_ popUp: NSPopUpButton) {
        guard SAClaudeSheetRules.style(for: SAClaudeControlDescriptor(kind: .popUp)) == .pill,
              Self.mayChangeClass(of: popUp), let cell = popUp.cell, Self.mayChangeClass(of: cell) else { return }
        let installed = popUp.cell is SAClaudePillPopUpButtonCell
        let title = popUp.pullsDown ? (popUp.item(at: 0)?.title ?? "") : (popUp.titleOfSelectedItem ?? popUp.title)
        guard installed || (popUp.isBordered && !title.isEmpty) else { return }
        SAClaudeFilterCells.installPill(on: popUp)
    }

    // MARK: Text fields

    private func styleTextField(_ field: NSTextField, _ colours: SAClaudeSheetColours) {
        var d = SAClaudeControlDescriptor(kind: .textField)
        d.isEditable = field.isEditable
        d.isBezeledOrBordered = field.isBezeled || field.isBordered || fields.contains(field)
        d.fontSize = field.font?.pointSize ?? NSFont.systemFontSize
        switch SAClaudeSheetRules.style(for: d) {
        case .field: styleField(field, colours)
        case .label: styleLabel(field, muted: false, colours)
        case .mutedLabel: styleLabel(field, muted: true, colours)
        default: break
        }
    }

    /// The Claude field: no bezel, a rounded field fill and hairline on its layer (the accent while edited), the
    /// text centred in the XIB frame by a cell that knows it has no bezel. Combo and token fields stay native
    /// (their button / tokens are drawn by AppKit's own views), as does any field whose cell is not a plain one.
    private func styleField(_ field: NSTextField, _ colours: SAClaudeSheetColours) {
        if field is NSComboBox || field is NSTokenField { return }
        if !fields.contains(field) {
            // Auto layout sizes a bezel-less field to its text: only restyle one whose height is pinned.
            if !field.translatesAutoresizingMaskIntoConstraints,
               !field.constraints.contains(where: { $0.firstAttribute == .height && $0.secondItem == nil }) {
                return
            }
            guard Self.installFieldCell(on: field) else { return }
            field.isBezeled = false
            field.isBordered = false
            field.drawsBackground = false
            field.focusRingType = .none
            field.wantsLayer = true
            fields.add(field)
        }
        guard let layer = field.layer else { return }
        layer.cornerRadius = SAClaudeSheetColours.fieldRadius
        layer.borderWidth = 1
        field.effectiveAppearance.performAsCurrentDrawingAppearance {
            layer.backgroundColor = colours.fieldFill.cgColor
        }
        updateBorder(of: field, colours)
        field.needsDisplay = true
    }

    /// Swaps the field's cell for the centring one of its kind; true when it is (now) one of them.
    private static func installFieldCell(on field: NSTextField) -> Bool {
        guard let cell = field.cell else { return false }
        if cell is SAClaudeSheetFieldCell || cell is SAClaudeSheetSecureFieldCell || cell is SAClaudeSheetSearchFieldCell { return true }
        guard mayChangeClass(of: cell) else { return false }
        let cellClass: AnyClass = type(of: cell)
        if cellClass == NSTextFieldCell.self {
            object_setClass(cell, SAClaudeSheetFieldCell.self)
        } else if cellClass == NSSecureTextFieldCell.self {
            object_setClass(cell, SAClaudeSheetSecureFieldCell.self)
        } else if cellClass == NSSearchFieldCell.self {
            object_setClass(cell, SAClaudeSheetSearchFieldCell.self)
        } else {
            return false
        }
        return true
    }

    private func updateBorder(of field: NSTextField, _ colours: SAClaudeSheetColours) {
        let colour = field.currentEditor() != nil ? SAClaudeStatusChrome.clay : colours.palette.hairline
        field.effectiveAppearance.performAsCurrentDrawingAppearance {
            field.layer?.borderColor = colour.cgColor
        }
    }

    /// The accent outline on the field being edited (its field editor is the window's first responder).
    private func updateFocus() {
        guard let colours else { return }
        for field in fields.allObjects { updateBorder(of: field, colours) }
    }

    /// Static text in the theme's text colour (muted when small). Colours the code chose (warnings, links) are kept.
    private func styleLabel(_ label: NSTextField, muted: Bool, _ colours: SAClaudeSheetColours) {
        let current = label.textColor
        guard SAClaudeSheetColours.isDefaultText(current), !Self.hasLinks(label) else { return }
        let wantsMuted = muted || SAClaudeSheetColours.isMutedDefault(current)
        let colour = wantsMuted ? colours.muted : colours.theme.text
        SAClaudeSheetColours.noteApplied(colour, muted: wantsMuted)
        if label.textColor != colour { label.textColor = colour }
    }

    private static func hasLinks(_ label: NSTextField) -> Bool {
        let text = label.attributedStringValue
        var found = false
        text.enumerateAttribute(.link, in: NSRange(location: 0, length: text.length)) { value, _, stop in
            if value != nil { found = true; stop.pointee = true }
        }
        return found
    }

    // MARK: Boxes

    /// A separator becomes a hairline; a titled primary box a hairline card under an SF Pro 11
    /// muted title. Both by an isa swap to a drawing subclass, so the box's frame and content stay as they are.
    private func styleBox(_ box: NSBox) {
        var d = SAClaudeControlDescriptor(kind: .box)
        d.isSeparatorBox = box.boxType == .separator
        // `.secondary` is a deprecated alias of `.primary` (the same value).
        let titled = box.boxType == .primary && box.titlePosition != .noTitle
        d.boxTitle = titled ? box.title : ""
        let style = SAClaudeSheetRules.style(for: d)
        let current: AnyClass = type(of: box)
        if current == SAClaudeSheetSeparatorBox.self || current == SAClaudeSheetTitledBox.self {
            box.needsDisplay = true
            return
        }
        guard current == NSBox.self, Self.mayChangeClass(of: box) else { return }
        switch style {
        case .separator: object_setClass(box, SAClaudeSheetSeparatorBox.self)
        case .titledBox: object_setClass(box, SAClaudeSheetTitledBox.self)
        default: return
        }
        box.needsDisplay = true
    }

    // MARK: Tables

    /// The quiet grid look: theme background without alternating rows, hairline grid lines, the Claude header.
    /// Tables already in the Claude look, source lists and colours the code chose are left alone.
    private func styleTable(_ table: NSTableView, _ colours: SAClaudeSheetColours) {
        if table is SAClaudeCopyTable || table is SAClaudeTableView { return }
        // The XIBs' older tables are source lists by their (deprecated) highlight style, raw value 1.
        let isSourceList = table.style == .sourceList || table.selectionHighlightStyle.rawValue == 1
        if !isSourceList {
            if SAClaudeSheetColours.isDefaultBackground(table.backgroundColor) {
                SAClaudeSheetColours.noteAppliedBackground(colours.theme.background)
                table.backgroundColor = colours.theme.background
            }
            if let scrollView = table.enclosingScrollView, SAClaudeSheetColours.isDefaultBackground(scrollView.backgroundColor) {
                scrollView.backgroundColor = colours.theme.background
            }
            if table.usesAlternatingRowBackgroundColors { table.usesAlternatingRowBackgroundColors = false }
        }
        table.gridColor = colours.palette.hairline
        if let header = table.headerView, type(of: header) == NSTableHeaderView.self {
            let claudeHeader = SAClaudeTableHeaderView(frame: header.frame)
            claudeHeader.menu = header.menu
            table.headerView = claudeHeader
        }
        (table.headerView as? SAClaudeTableHeaderView)?.palette = colours.gridPalette
        table.needsDisplay = true
        table.headerView?.needsDisplay = true
    }

    // MARK: Text views

    /// Text views that colour themselves from the editor settings.
    private static let selfThemedTextViewClasses: [AnyClass] = ["SPTextView", "SPBundleCommandTextView"].compactMap(NSClassFromString)

    /// Plain-text views take the editor theme's colours (and font, when they are plain NSTextViews); rich text
    /// and the app's own syntax-coloured editors are left alone.
    private func styleTextView(_ textView: NSTextView, _ colours: SAClaudeSheetColours) {
        if Self.selfThemedTextViewClasses.contains(where: { textView.isKind(of: $0) }) || textView.isRichText { return }
        if textView.drawsBackground, SAClaudeSheetColours.isDefaultBackground(textView.backgroundColor) {
            SAClaudeSheetColours.noteAppliedBackground(colours.theme.background)
            textView.backgroundColor = colours.theme.background
            if let scrollView = textView.enclosingScrollView, SAClaudeSheetColours.isDefaultBackground(scrollView.backgroundColor) {
                scrollView.backgroundColor = colours.theme.background
            }
        }
        if SAClaudeSheetColours.isDefaultText(textView.textColor) {
            SAClaudeSheetColours.noteApplied(colours.theme.text, muted: false)
            textView.textColor = colours.theme.text
        }
        textView.insertionPointColor = colours.theme.caret
        if type(of: textView) == NSTextView.self {
            let font = SAClaudeCompletionStyler.editorFont()
            if textView.font != font { textView.font = font }
        }
    }
}

// MARK: - Colours

/// The colours one restyle uses, resolved for the app's appearance from the editor theme.
struct SAClaudeSheetColours {
    static let fieldRadius: CGFloat = 7

    let theme: SAClaudeThemeColours
    let palette: SAClaudeEditorChrome.Palette
    let gridPalette: SAClaudeGridChrome.Palette
    let surface: NSColor
    let fieldFill: NSColor
    let muted: NSColor
    let isDark: Bool

    static func current() -> SAClaudeSheetColours {
        var result: SAClaudeSheetColours?
        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
            let theme = SAClaudeThemeColours.from(defaults: .standard)
            let palette = SAClaudeEditorChrome.palette(text: theme.text, background: theme.background)
            let surface = SAClaudeStatusChrome.popupSurface(theme: theme)
            result = SAClaudeSheetColours(theme: theme, palette: palette, gridPalette: SAClaudeGridChrome.palette(from: .standard),
                                          surface: surface, fieldFill: SAClaudeFilterChrome.fieldFill(text: theme.text, background: surface),
                                          muted: palette.icon, isDark: SAClaudeGridChrome.isDark(theme.background))
        }
        // performAsCurrentDrawingAppearance runs its block synchronously.
        return result!
    }

    // Colours applied before count as "nobody chose one", so a theme change recolours them.
    private static var appliedText: [NSColor] = []
    private static var appliedMuted: [NSColor] = []
    private static var appliedBackgrounds: [NSColor] = []

    static func noteApplied(_ colour: NSColor, muted: Bool) {
        if muted {
            if !appliedMuted.contains(colour) { appliedMuted.append(colour) }
        } else if !appliedText.contains(colour) {
            appliedText.append(colour)
        }
    }

    static func noteAppliedBackground(_ colour: NSColor) {
        if !appliedBackgrounds.contains(colour) { appliedBackgrounds.append(colour) }
    }

    /// The system text colours a control has when nobody chose one, or a colour this styler applied.
    static func isDefaultText(_ colour: NSColor?) -> Bool {
        guard let colour else { return true }
        return colour == .controlTextColor || colour == .labelColor || colour == .textColor
            || isMutedDefault(colour) || appliedText.contains(colour)
    }

    /// The system's secondary text colours, or a muted colour this styler applied: kept muted.
    static func isMutedDefault(_ colour: NSColor?) -> Bool {
        guard let colour else { return false }
        return colour == .secondaryLabelColor || colour == .tertiaryLabelColor || colour == .disabledControlTextColor
            || appliedMuted.contains(colour)
    }

    static func isDefaultBackground(_ colour: NSColor) -> Bool {
        colour == .controlBackgroundColor || colour == .textBackgroundColor || colour == .windowBackgroundColor
            || colour == .underPageBackgroundColor || appliedBackgrounds.contains(colour)
    }
}

// MARK: - Cells and boxes

/// Where a bezel-less sheet field puts its text: inset from the rounded outline and centred on one line (a field
/// taller than two lines keeps its text at the top).
private enum SheetFieldText {
    static let horizontalInset: CGFloat = 6
    static let multiLineTopInset: CGFloat = 3

    static func rect(_ rect: NSRect, font: NSFont?) -> NSRect {
        var text = rect.insetBy(dx: horizontalInset, dy: 0)
        let line = ceil(NSLayoutManager().defaultLineHeight(for: font ?? .systemFont(ofSize: NSFont.systemFontSize)))
        let spare = text.height - line
        if spare >= line {
            text = text.insetBy(dx: 0, dy: multiLineTopInset)
        } else if spare > 0 {
            text.origin.y += (spare / 2).rounded(.down)
            text.size.height = line
        }
        return text
    }
}

/// A plain sheet field's cell once its bezel is off (installed with `object_setClass`, no stored properties).
@objc(SAClaudeSheetFieldCell) final class SAClaudeSheetFieldCell: NSTextFieldCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        let drawingRect = super.drawingRect(forBounds: rect)
        return isBezeled || isBordered ? drawingRect : SheetFieldText.rect(drawingRect, font: font)
    }

    // AppKit places the field editor exactly where it is told to, not by -drawingRectForBounds:.
    override func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, event: NSEvent?) {
        super.edit(withFrame: drawingRect(forBounds: rect), in: controlView, editor: textObj, delegate: delegate, event: event)
    }

    override func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, start selStart: Int, length selLength: Int) {
        super.select(withFrame: drawingRect(forBounds: rect), in: controlView, editor: textObj, delegate: delegate, start: selStart, length: selLength)
    }
}

/// The secure twin of `SAClaudeSheetFieldCell`.
@objc(SAClaudeSheetSecureFieldCell) final class SAClaudeSheetSecureFieldCell: NSSecureTextFieldCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        let drawingRect = super.drawingRect(forBounds: rect)
        return isBezeled || isBordered ? drawingRect : SheetFieldText.rect(drawingRect, font: font)
    }

    override func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, event: NSEvent?) {
        super.edit(withFrame: drawingRect(forBounds: rect), in: controlView, editor: textObj, delegate: delegate, event: event)
    }

    override func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, start selStart: Int, length selLength: Int) {
        super.select(withFrame: drawingRect(forBounds: rect), in: controlView, editor: textObj, delegate: delegate, start: selStart, length: selLength)
    }
}

/// The Claude search field cell (magnifier, text, cancel button laid out by the cell) with its text centred on
/// one line, as a sheet's search field keeps its XIB height.
@objc(SAClaudeSheetSearchFieldCell) final class SAClaudeSheetSearchFieldCell: SAClaudeSearchFieldCell {
    override func searchTextRect(forBounds rect: NSRect) -> NSRect {
        var text = super.searchTextRect(forBounds: rect)
        let line = ceil(NSLayoutManager().defaultLineHeight(for: font ?? .systemFont(ofSize: NSFont.systemFontSize)))
        let spare = text.height - line
        if spare > 0 {
            text.origin.y += (spare / 2).rounded(.down)
            text.size.height = line
        }
        return text
    }
}

/// A separator drawn as a 1pt hairline along its long axis (installed with `object_setClass`; on macOS 26 and
/// later this also drops the private view NSBox draws its line with).
@objc(SAClaudeSheetSeparatorBox) final class SAClaudeSheetSeparatorBox: NSBox {
    override var wantsUpdateLayer: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let line = bounds.width >= bounds.height
            ? NSRect(x: bounds.minX, y: (bounds.midY - 0.5).rounded(.down), width: bounds.width, height: 1)
            : NSRect(x: (bounds.midX - 0.5).rounded(.down), y: bounds.minY, width: 1, height: bounds.height)
        SAClaudeFilterBarStyler.currentPalette.hairline.setFill()
        line.intersection(dirtyRect).fill()
    }
}

/// A titled box drawn as a hairline card (radius 9) under its title in SF Pro 11, muted. Installed with
/// `object_setClass`; NSBox keeps its border, title and content rects, only the drawing is Claude's.
@objc(SAClaudeSheetTitledBox) final class SAClaudeSheetTitledBox: NSBox {
    private static let radius: CGFloat = 9

    override var wantsUpdateLayer: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let palette = SAClaudeFilterBarStyler.currentPalette
        let card = NSBezierPath(roundedRect: borderRect.insetBy(dx: 0.5, dy: 0.5), xRadius: Self.radius - 0.5, yRadius: Self.radius - 0.5)
        card.lineWidth = 1
        palette.hairline.setStroke()
        card.stroke()

        guard titlePosition != .noTitle, !title.isEmpty else { return }
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: palette.icon]
        let string = NSAttributedString(string: title, attributes: attributes)
        let size = string.size()
        let titleArea = titleRect
        let origin = NSPoint(x: titleArea.minX, y: (titleArea.midY - size.height / 2).rounded())
        // The title sits on the card's top edge: clear the line behind it.
        if titleArea.intersects(borderRect), let surface = window?.backgroundColor {
            surface.setFill()
            NSRect(x: origin.x - 3, y: titleArea.minY, width: size.width + 6, height: titleArea.height).fill()
        }
        string.draw(at: origin)
    }
}

// MARK: - Hover

/// Redraws a sheet's secondary button when the mouse enters or leaves it; the cell draws the hover fill itself
/// (inside its outline, which is smaller than a classic XIB frame). Retained by the button.
private final class SAClaudeSheetHoverTracker: NSObject {
    private static var associationKey: UInt8 = 0
    private weak var view: NSView?

    static func attach(to view: NSView) {
        guard objc_getAssociatedObject(view, &associationKey) == nil else { return }
        let tracker = SAClaudeSheetHoverTracker()
        tracker.view = view
        view.addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                                            owner: tracker, userInfo: nil))
        objc_setAssociatedObject(view, &associationKey, tracker, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    // The tracking area sends its owner `mouseEntered:` / `mouseExited:`; spelled out for a plain NSObject.
    @objc(mouseEntered:) func mouseEntered(with event: NSEvent) { view?.needsDisplay = true }
    @objc(mouseExited:) func mouseExited(with event: NSEvent) { view?.needsDisplay = true }
}
