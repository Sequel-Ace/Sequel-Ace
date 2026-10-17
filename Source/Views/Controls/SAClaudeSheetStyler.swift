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
//  Alerts are styled as they are presented (SAClaudeAlertPresentationHook);
//  the cells and boxes installed live in SAClaudeSheetCells.swift.
//  App target only.
//

import AppKit

@objc(SAClaudeSheetStyler) final class SAClaudeSheetStyler: NSObject {

    private static var observers: [NSObjectProtocol] = []
    private static var alertStyledKey: UInt8 = 0

    /// Starts watching windows app-wide and styling every alert before it is shown (once; call at launch).
    @objc static func start() {
        guard observers.isEmpty else { return }
        // Every NSAlert is styled as it is presented (`runModal` / `beginSheetModal`); should that hook be
        // unavailable, at least the helper factories in NSAlertExtension.swift style theirs.
        if !SAClaudeAlertPresentationHook.install() {
            SAAlertPresentation.willPresent = { styleAlert($0) }
        }
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

    /// `styleAlert(_:presentedOn:)` for an alert with no known parent window (`runModal`, the helper factories).
    @objc(styleAlert:) static func styleAlert(_ alert: NSAlert) {
        styleAlert(alert, presentedOn: nil)
    }

    /// Styles `alert`'s window before it is shown: its first button primary, the others secondary, its texts,
    /// suppression checkbox and accessory view. Lays the alert out, then lays the Claude alert card out in its window
    /// (`SAClaudeAlertCardStyler`; the destructive button turns red once the card is in). `parent` is the window a
    /// sheet is presented on. Called as the alert is presented; once per alert (a second call, from a helper and the
    /// presentation hook both, does nothing; the window's skin restyles it and the card is put back whenever it
    /// becomes key).
    @objc(styleAlert:presentedOnWindow:) static func styleAlert(_ alert: NSAlert, presentedOn parent: NSWindow?) {
        guard objc_getAssociatedObject(alert, &alertStyledKey) == nil else { return }
        objc_setAssociatedObject(alert, &alertStyledKey, true, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        let card = SAClaudeAlertCardStyler.prepare(alert, presentedOn: parent)
        // The buttons first: once the alert has laid itself out its stack view observes them, and the class of
        // an observed object must not change (`SAClaudeClassSwap`). Buttons a caller's own `layout()` already
        // put in the stack view stay native.
        for button in alert.buttons { SAClaudeWindowSkin.styleButton(button, alert: alert) }
        if alert.showsSuppressionButton, let suppression = alert.suppressionButton {
            SAClaudeWindowSkin.styleButton(suppression, alert: alert)
        }
        alert.layout()
        skinAlert(alert)
        if card { SAClaudeAlertCardStyler.attach(alert) }
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

    /// Restyles `window` if it is a target: already skinned windows are walked again with the current colours. Every
    /// window styled (and every open panel whose accessory is) is then offered to the Import flow's styler, which
    /// claims its own; windows are also offered to the table/database sheets' form (`SAClaudeFormSheetStyler`).
    static func consider(_ window: NSWindow) {
        if let skin = SAClaudeWindowSkin.skin(for: window) {
            skin.refresh(force: true)
            SAClaudeAlertCardStyler.claim(window)
            SAClaudeImportStyler.claim(window)
            SAClaudeFormSheetStyler.claim(window)
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
            SAClaudeAlertCardStyler.claim(window)
        case .accessoryOnly:
            guard let accessory = (window as? NSSavePanel)?.accessoryView else { return }
            if let skin = SAClaudeWindowSkin.skin(for: accessory) {
                // An accessory view can be shown again in another panel: follow that panel's focus.
                skin.observeFocus(in: window)
                skin.refresh(force: true)
            } else {
                SAClaudeWindowSkin.attach(toAccessory: accessory, in: window)
            }
            SAClaudeImportStyler.claim(window)
        case .window:
            SAClaudeWindowSkin.attach(to: window, alert: nil)
            SAClaudeImportStyler.claim(window)
            SAClaudeFormSheetStyler.claim(window)
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

    private var applied: SAClaudeThemeColours?
    private var colours: SAClaudeSheetColours?
    private let fields = NSHashTable<NSTextField>.weakObjects()

    private var observations: [NSKeyValueObservation] = []
    private var focusObservation: NSKeyValueObservation?
    private weak var focusWindow: NSWindow?

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
        // The accent is read at draw time by the cells; only the fields' outlines hold it.
        SAClaudeAccent.observe(self) { $0.accentChanged() }
        // Dynamic fallback colours (no theme saved yet) resolve differently in light and dark.
        observations.append(NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            DispatchQueue.main.async { self?.refresh(force: true) }
        })
        if let window { observeFocus(in: window) }
    }

    /// Follows `window`'s first responder for the fields' accent outline (once per window).
    func observeFocus(in window: NSWindow) {
        guard window !== focusWindow || focusObservation == nil else { return }
        self.window = window
        focusWindow = window
        focusObservation = window.observe(\.firstResponder) { [weak self] _, _ in
            DispatchQueue.main.async { self?.updateFocus() }
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

    private var root: NSView? { accessory ?? window?.contentView }

    /// The accent changed: the accent outline of the field being edited, and a redraw of everything else.
    private func accentChanged() {
        updateFocus()
        if let root { SAClaudeAccent.redisplay(root) }
    }

    /// Restyles everything when the theme changed (always, when `force`).
    func refresh(force: Bool) {
        guard let root else { return }
        // An accessory keeps the theme's colours even in a system panel of the other lightness: the Claude cells
        // read the colours below at draw time, app-wide, so one window can't have colours of its own.
        let colours = SAClaudeSheetColours.current()
        // The Claude cells read these at draw time.
        SAClaudeFilterBarStyler.currentPalette = colours.palette
        SAClaudeFilterBarStyler.currentThemeText = colours.theme.text
        SAClaudeSheetColours.currentSurface = colours.surface
        if !force, let applied, applied == colours.theme { return }
        applied = colours.theme
        self.colours = colours

        applyChrome(colours, root: root)
        style(root, colours)
        updateFocus()
        SAClaudeAccent.redisplay(root)
    }

    /// The appearance from the colours' lightness (the theme's; a save panel's own for its accessory) and the
    /// surface behind everything.
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
        if let alert, let index = alert.buttons.firstIndex(where: { $0 === button }) {
            d.isAlertButton = true
            d.alertButtonIndex = index
            d.alertHasReturnButton = alert.buttons.contains { $0.keyEquivalent == "\r" }
        }
        // A forced-destructive push button (the alert card's red ones: the default filled, other delete-type ones a red
        // dashed outline) keeps its red look at every walk, whatever the rules say. Only a push button: a checkbox or radio
        // flagged by mistake keeps its own look.
        if let look = SAClaudeSheetButtonRole.destructiveLook(button), d.buttonType == .momentaryPushIn {
            guard button.isBordered || d.isAlertButton else { return }
            if !SAClaudeFilterCells.switchSheetButton(button, to: look) {
                guard SAClaudeFilterCells.install(SAClaudeFilterCells.sheetCellClass(for: look), on: button) else { return }
            }
            return
        }
        var style = SAClaudeSheetRules.style(for: d)
        // A bespoke styler may give a push button a role the rules don't (`SAClaudeSheetButtonRole`).
        if let forcedPrimary = SAClaudeSheetButtonRole.forced(button) { style = forcedPrimary ? .primaryButton : .secondaryButton }
        switch style {
        case .primaryButton, .secondaryButton:
            // A borderless titled push button (a link-like text button) keeps its native look.
            guard button.isBordered || d.isAlertButton else { return }
            let primary = style == .primaryButton
            // `SAClaudeFilterCells` leaves an observed button native (`SAClaudeClassSwap`).
            if !SAClaudeFilterCells.switchSheetButton(button, toPrimary: primary) {
                let cellClass: AnyClass = primary ? SAClaudeSheetPrimaryButtonCell.self : SAClaudeSheetSecondaryButtonCell.self
                guard SAClaudeFilterCells.install(cellClass, on: button) else { return }
            }
            if !primary { SAClaudeSheetHoverTracker.attach(to: button) }
        case .checkbox, .radio:
            SAClaudeFilterCells.install(style == .checkbox ? SAClaudeCheckboxCell.self : SAClaudeRadioCell.self, on: button)
        default:
            break
        }
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

    /// A pop-up showing a title becomes a pill; image-only and icon-sized ones (gear and action menus) and ones
    /// with nothing to show stay native, as the pill cell draws titles, not images.
    private func stylePopUp(_ popUp: NSPopUpButton) {
        let item = popUp.pullsDown ? popUp.item(at: 0) : popUp.selectedItem
        let title = item?.title ?? popUp.title
        let image = item?.image ?? popUp.image
        var d = SAClaudeControlDescriptor(kind: .popUp)
        d.title = title
        d.isImageOnly = popUp.imagePosition == .imageOnly || (image != nil && title.isEmpty) || (!popUp.isBordered && image != nil)
            || (!(popUp.cell is SAClaudePillPopUpButtonCell) && Self.isIconSized(popUp, title: title))
        guard SAClaudeSheetRules.style(for: d) == .pill else { return }
        let installed = popUp.cell is SAClaudePillPopUpButtonCell
        guard installed || (popUp.isBordered && !title.isEmpty) else { return }
        SAClaudeFilterCells.installPill(on: popUp)
    }

    /// A pull-down too narrow for its title in the pill (the Export sheet's 41pt settings menu, titled "S"): AppKit
    /// shows it as an icon-like button, which the pill would turn into a truncated title.
    private static func isIconSized(_ popUp: NSPopUpButton, title: String) -> Bool {
        guard popUp.pullsDown else { return false }
        let titleArea = SAClaudeFilterChrome.pillTitleRect(in: SAClaudeFilterChrome.controlFrame(in: popUp.bounds)).width
        let titleWidth = ceil(NSAttributedString(string: title, attributes: [.font: NSFont.systemFont(ofSize: 12)]).size().width)
        return titleArea < titleWidth + SAClaudeFilterChrome.pillPadding
    }

    // MARK: Text fields

    private func styleTextField(_ field: NSTextField, _ colours: SAClaudeSheetColours) {
        var d = SAClaudeControlDescriptor(kind: .textField)
        let styledAsField = fields.contains(field)
        // A bezeled read-only box (the Export sheet's path) shows a value like a field and gets the field look.
        d.isEditable = field.isEditable || field.isBezeled || styledAsField
        d.isBezeledOrBordered = field.isBezeled || field.isBordered || styledAsField
        d.fontSize = field.font?.pointSize ?? NSFont.systemFontSize
        switch SAClaudeSheetRules.style(for: d) {
        case .field: styleField(field, colours)
        case .label: styleLabel(field, muted: false, colours)
        case .mutedLabel: styleLabel(field, muted: true, colours)
        default: break
        }
    }

    /// The Claude field: no bezel, a rounded field fill and hairline on its layer (the accent while edited), the
    /// text centred in the XIB frame by a cell that knows it has no bezel. A combo box gets the same look from its
    /// layer and properties alone, as the connection panel's do (no cell or class swap; its arrow stays AppKit's).
    /// A token field likewise, its tokens staying AppKit's. Any other field whose cell is not a plain one stays native.
    private func styleField(_ field: NSTextField, _ colours: SAClaudeSheetColours) {
        if !fields.contains(field) {
            // Auto layout sizes a bezel-less field to its text: only restyle one whose height is pinned.
            if !field.translatesAutoresizingMaskIntoConstraints,
               !field.constraints.contains(where: { $0.firstAttribute == .height && $0.secondItem == nil }) {
                return
            }
            if let comboBox = field as? NSComboBox {
                comboBox.isButtonBordered = false
            } else if field is NSTokenField {
                // No cell swap: the token cell lays its tokens out itself.
            } else if !Self.installFieldCell(on: field) {
                return
            }
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
        guard SAClaudeClassSwap.mayChangeClass(of: cell) else { return false }
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
        let marked = SAClaudeStyledMark.tone(of: label)
        guard marked != nil || !Self.hasLinks(label),
              let tone = SAClaudeRecolouring.labelTone(marked: marked, applied: SAClaudeStyledMark.applied(of: label),
                                                       current: label.textColor, isSmall: muted) else { return }
        let colour = tone == .muted ? colours.muted : colours.theme.text
        if label.textColor != colour { label.textColor = colour }
        SAClaudeStyledMark.setTone(tone, applied: label.textColor ?? colour, on: label)
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
        guard current == NSBox.self, SAClaudeClassSwap.mayChangeClass(of: box) else { return }
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
            SAClaudeStyledMark.colourBackground(of: table, colours.theme.background)
            if let scrollView = table.enclosingScrollView { SAClaudeStyledMark.colourBackground(of: scrollView, colours.theme.background) }
            if table.usesAlternatingRowBackgroundColors { table.usesAlternatingRowBackgroundColors = false }
        }
        Self.installCheckboxCells(in: table)
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

    /// A cell-based column of checkboxes (the Export sheet's table list) draws Claude checkboxes: its data cell, an
    /// exact NSButtonCell of the switch type, becomes an `SAClaudeCheckboxCell` in place, so its state, target,
    /// action and the table's own `objectValue` / click handling stay AppKit's.
    private static func installCheckboxCells(in table: NSTableView) {
        for column in table.tableColumns {
            guard let cell = column.dataCell as? NSButtonCell, type(of: cell) == NSButtonCell.self,
                  buttonType(of: cell) == .switch, SAClaudeClassSwap.mayChangeClass(of: cell) else { continue }
            object_setClass(cell, SAClaudeCheckboxCell.self)
        }
    }

    // MARK: Text views

    /// Text views that colour themselves from the editor settings.
    private static let selfThemedTextViewClasses: [AnyClass] = ["SPTextView", "SPBundleCommandTextView"].compactMap(NSClassFromString)

    /// Every text view gets the theme caret. Plain or editable ones also take the theme background and (where
    /// nobody chose one) text colour; rich read-only text keeps its own colours on its own background. The app's
    /// syntax-coloured editors already carry the theme's colours, so their text is left to them; the editor font
    /// only goes to plain NSTextViews.
    private func styleTextView(_ textView: NSTextView, _ colours: SAClaudeSheetColours) {
        textView.insertionPointColor = colours.theme.caret
        guard !textView.isRichText || textView.isEditable else { return }
        let background = colours.theme.background
        if textView.backgroundColor != background { textView.backgroundColor = background }
        if let scrollView = textView.enclosingScrollView { SAClaudeStyledMark.colourBackground(of: scrollView, background) }
        if Self.selfThemedTextViewClasses.contains(where: { textView.isKind(of: $0) }) { return }
        if SAClaudeRecolouring.ownsText(applied: SAClaudeStyledMark.applied(of: textView), current: textView.textColor) {
            if textView.textColor != colours.theme.text { textView.textColor = colours.theme.text }
            SAClaudeStyledMark.setTone(.text, applied: textView.textColor ?? colours.theme.text, on: textView)
        }
        if !textView.isRichText, type(of: textView) == NSTextView.self {
            let font = SAClaudeCompletionStyler.editorFont()
            if textView.font != font { textView.font = font }
        }
    }
}

// MARK: - Colours

/// The colours one restyle uses, resolved for the app's appearance from the editor theme.
struct SAClaudeSheetColours {
    static let fieldRadius: CGFloat = 7
    /// The theme surface of the last restyle; the titled box reads it at draw time.
    static var currentSurface: NSColor = .windowBackgroundColor

    let theme: SAClaudeThemeColours
    let palette: SAClaudeEditorChrome.Palette
    let gridPalette: SAClaudeGridChrome.Palette
    let surface: NSColor
    let fieldFill: NSColor
    let muted: NSColor
    let isDark: Bool

    /// The theme's colours, resolved for the app's appearance.
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
}

// MARK: - Styled marks

/// Marks a view the styler coloured, with the tone and the colour it gave it, so a later restyle recolours it while it
/// still shows that colour (a view off-screen during a theme change, such as another Preferences pane, keeps the old
/// colour until it is styled again) and leaves it once its code chose a colour. The decisions are
/// `SAClaudeRecolouring`'s.
enum SAClaudeStyledMark {
    private static var toneKey: UInt8 = 0
    private static var appliedKey: UInt8 = 0
    private static var backgroundKey: UInt8 = 0

    static func tone(of view: NSView) -> SAClaudeRecolouring.Tone? {
        (objc_getAssociatedObject(view, &toneKey) as? String).flatMap(SAClaudeRecolouring.Tone.init(rawValue:))
    }

    /// The text colour the styler last gave the view.
    static func applied(of view: NSView) -> NSColor? { objc_getAssociatedObject(view, &appliedKey) as? NSColor }

    static func setTone(_ tone: SAClaudeRecolouring.Tone, applied: NSColor, on view: NSView) {
        if self.tone(of: view) != tone { objc_setAssociatedObject(view, &toneKey, tone.rawValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
        objc_setAssociatedObject(view, &appliedKey, applied, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    /// Gives a table's or scroll view's background `colour` if it is the styler's to colour.
    static func colourBackground(of view: NSView, _ colour: NSColor) {
        let applied = objc_getAssociatedObject(view, &backgroundKey) as? NSColor
        let current: NSColor
        switch view {
        case let table as NSTableView: current = table.backgroundColor
        case let scrollView as NSScrollView: current = scrollView.backgroundColor
        default: return
        }
        guard SAClaudeRecolouring.ownsBackground(applied: applied, current: current) else { return }
        if current != colour {
            if let table = view as? NSTableView { table.backgroundColor = colour }
            if let scrollView = view as? NSScrollView { scrollView.backgroundColor = colour }
        }
        let now = (view as? NSTableView)?.backgroundColor ?? (view as? NSScrollView)?.backgroundColor ?? colour
        objc_setAssociatedObject(view, &backgroundKey, now, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
}

// MARK: - Forced button roles

/// A push button whose sheet role a bespoke styler chose: the field editor's read-only Close is the primary though it
/// answers Escape, and the BIT editor's textured buttons get roles at all. Read by `SAClaudeWindowSkin.styleButton`,
/// so the role survives every later walk of the window.
enum SAClaudeSheetButtonRole {
    private static var key: UInt8 = 0

    static func force(_ button: NSButton, primary: Bool) {
        objc_setAssociatedObject(button, &key, primary, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    static func forced(_ button: NSButton) -> Bool? {
        objc_getAssociatedObject(button, &key) as? Bool
    }

    private static var destructiveKey: UInt8 = 0

    /// Gives `button` a red destructive look at every later walk of the window (the alert card's destructive buttons):
    /// filled red (`secondary` false, the default button) or the red dashed outline (`secondary` true, another delete-type one).
    /// Call `SAClaudeWindowSkin.styleButton` afterwards to apply it now.
    static func forceDestructive(_ button: NSButton, secondary: Bool = false) {
        objc_setAssociatedObject(button, &destructiveKey, secondary, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    /// `.destructive` or `.destructiveSecondary` for a button given a destructive look, else nil.
    static func destructiveLook(_ button: NSButton) -> SAClaudeSheetButtonLook? {
        guard let secondary = objc_getAssociatedObject(button, &destructiveKey) as? Bool else { return nil }
        return secondary ? .destructiveSecondary : .destructive
    }
}
