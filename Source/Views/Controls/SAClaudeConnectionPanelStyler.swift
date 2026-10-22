//
//  SAClaudeConnectionPanelStyler.swift
//  Sequel Ace
//
//  Turns the classic connection form (ConnectionView.xib) into the Claude connection panel: the details container
//  becomes a rounded card with a header (colour dot, name, subtitle) and type tabs, each type's fields sit in
//  titled sections in two columns, the rarely used settings fold under "Advanced", and the buttons share one action
//  row. Every control is the XIB's own object, restyled and repositioned; targets, actions, bindings, menus and
//  delegates are untouched. The one structural change: Add / Save / Test move out of the edit-buttons box into the
//  card (the box's visibility is mirrored onto them).
//
//  Controls are found per type tab by binding key path, outlet or known class, never by label text, and
//  classified by `SAClaudeConnectionClassifier`; a type with an unknown or missing control keeps its XIB layout
//  (styled only). Frames come from `SAClaudeConnectionPanelLayout` and are applied when the controller resizes the
//  form (its `-resizeTabViewToConnectionType:animating:` ends in `panelDidResize(in:)`), when Advanced is toggled
//  and when the scroll view changes width. Colours follow the editor theme and the light/dark appearance.
//  App target only.
//

import AppKit

// MARK: - Panel pieces

/// The Advanced disclosure row: a chevron and the "Advanced" title; clicking (or Space) toggles it.
private final class SAClaudeAdvancedDisclosure: NSControl {
    var isOpen = false {
        didSet { if oldValue != isOpen { needsDisplay = true; NSAccessibility.post(element: self, notification: .valueChanged) } }
    }
    /// Shown dimmed and not clickable while a non-default advanced value keeps the section open.
    var isLocked = false { didSet { needsDisplay = true } }
    var titleColour: NSColor = .secondaryLabelColor { didSet { needsDisplay = true } }
    var onToggle: (() -> Void)?

    private let title = NSLocalizedString("ClaudeConnectionAdvanced", value: "Advanced",
                                          comment: "connection panel : title of the fold holding the less used connection settings")
    private static let font = NSFont.systemFont(ofSize: 11)

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let chevronSize: CGFloat = 8
        let centre = NSPoint(x: bounds.minX + chevronSize / 2 + 1, y: bounds.midY)
        let chevron = NSBezierPath()
        if isOpen {
            chevron.move(to: NSPoint(x: centre.x - 3.5, y: centre.y + 1.75))
            chevron.line(to: NSPoint(x: centre.x, y: centre.y - 1.75))
            chevron.line(to: NSPoint(x: centre.x + 3.5, y: centre.y + 1.75))
        } else {
            chevron.move(to: NSPoint(x: centre.x - 1.75, y: centre.y + 3.5))
            chevron.line(to: NSPoint(x: centre.x + 1.75, y: centre.y))
            chevron.line(to: NSPoint(x: centre.x - 1.75, y: centre.y - 3.5))
        }
        chevron.lineWidth = 1.4
        chevron.lineCapStyle = .round
        chevron.lineJoinStyle = .round
        titleColour.withAlphaComponent(isLocked ? 0.45 : 1).setStroke()
        chevron.stroke()

        let string = NSAttributedString(string: title, attributes: [.font: Self.font, .foregroundColor: titleColour])
        let height = ceil(string.size().height)
        string.draw(at: NSPoint(x: bounds.minX + chevronSize + 8, y: (bounds.midY - height / 2).rounded()))
    }

    override var acceptsFirstResponder: Bool { !isLocked }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard !isLocked else { return }
        onToggle?()
    }

    override func keyDown(with event: NSEvent) {
        if !isLocked, event.charactersIgnoringModifiers == " " || event.specialKey == .carriageReturn {
            onToggle?()
        } else {
            super.keyDown(with: event)
        }
    }

    override var focusRingMaskBounds: NSRect { bounds }
    override func drawFocusRingMask() { NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill() }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .disclosureTriangle }
    override func accessibilityLabel() -> String? { title }
    override func accessibilityValue() -> Any? { NSNumber(value: isOpen) }
    override func accessibilityPerformPress() -> Bool {
        guard !isLocked else { return false }
        onToggle?()
        return true
    }
}

/// The header's colour dot: the favourite's colour, or a hairline ring when it has none.
private final class SAClaudeColourDot: NSView {
    var colour: NSColor? { didSet { needsDisplay = true } }
    var ringColour: NSColor = .separatorColor { didSet { needsDisplay = true } }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(ovalIn: bounds.insetBy(dx: 0.5, dy: 0.5))
        if let colour {
            colour.setFill()
            path.fill()
        } else {
            ringColour.setStroke()
            path.lineWidth = 1
            path.stroke()
        }
    }
}

/// A field's outline: the rounded field fill and a hairline (clay while the field is edited), behind the field.
/// A click in its margin focuses the field it frames (whichever of a secure field and its plain twin is shown).
private final class SAClaudeFieldOutline: NSView {
    var fill: NSColor = .clear { didSet { needsDisplay = true } }
    var stroke: NSColor = .clear { didSet { needsDisplay = true } }
    var radius: CGFloat = 7 { didSet { needsDisplay = true } }
    /// The field (and its plain twin) this outline frames; never retains anything that retains the outline.
    var fields: [NSTextField] = []

    private var target: NSTextField? {
        fields.first { !$0.isHidden && $0.isEnabled && $0.isEditable }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, frame.contains(point), target != nil else { return nil }
        return self
    }

    override func mouseDown(with event: NSEvent) {
        guard let field = target, let window else { return }
        if field.currentEditor() == nil { window.makeFirstResponder(field) }
        // Caret at the end, as a click past the text would put it.
        if let editor = field.currentEditor() {
            editor.selectedRange = NSRange(location: (editor.string as NSString).length, length: 0)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
        fill.setFill()
        path.fill()
        stroke.setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

/// One classified row of a type's form: its control and everything that moves with it.
private final class SAClaudePanelRow {
    enum Condition { case always, ssl, awsAuthorised, awsUnauthorised, sshPassword, sshKey }

    let id: String
    let kind: SAClaudeConnectionRowKind
    let section: SAClaudeConnectionSection
    let order: Int
    let condition: Condition
    let control: NSView
    var label: NSTextField?
    /// "Get public key", beside "Require SSL".
    var secondary: NSButton?
    /// A file / key picker or the Vault Refresh button, at the row's right.
    var accessory: NSButton?
    var spinner: NSProgressIndicator?

    init(id: String, kind: SAClaudeConnectionRowKind, section: SAClaudeConnectionSection, order: Int,
         condition: Condition, control: NSView) {
        self.id = id
        self.kind = kind
        self.section = section
        self.order = order
        self.condition = condition
        self.control = control
    }

    var spec: SAClaudeConnectionRowSpec {
        SAClaudeConnectionRowSpec(id: id, label: label?.stringValue, kind: kind, section: section)
    }
}

/// A secure field's eye button and the plain field it swaps in (both made by the controller).
private struct SAClaudeRevealPair {
    let eye: NSButton
    let twin: NSTextField
}

/// Everything found in one type tab.
private final class SAClaudePanelForm {
    let type: SAClaudeConnectionType
    let itemView: NSView
    let formContainer: NSView
    let sslContainer: NSView?
    var rows: [SAClaudePanelRow] = []
    var canLayOut = false

    var labels: [NSTextField] = []
    var notes: [NSTextField] = []
    var fields: [NSTextField] = []
    var popUps: [NSPopUpButton] = []
    var checkboxes: [NSButton] = []
    var ghostButtons: [NSButton] = []
    var pickerButtons: [NSButton] = []
    var reveal: [ObjectIdentifier: SAClaudeRevealPair] = [:]
    /// The type's own Name field, moved into the panel header (laid-out types only).
    var nameField: NSTextField?
    let colourLabel = NSTextField(labelWithString: NSLocalizedString("ClaudeConnectionColour", value: "Colour",
                                                                     comment: "connection panel : label of the favourite colour row"))

    init(type: SAClaudeConnectionType, itemView: NSView, formContainer: NSView, sslContainer: NSView?) {
        self.type = type
        self.itemView = itemView
        self.formContainer = formContainer
        self.sslContainer = sslContainer
    }
}

// MARK: - Styler

@objc(SAClaudeConnectionPanelStyler) final class SAClaudeConnectionPanelStyler: NSObject {

    private typealias Layout = SAClaudeConnectionPanelLayout

    private static var associationKey: UInt8 = 0
    private static let advancedOpenKey = "ClaudeConnectionAdvancedOpen"
    private static let maximumWidth: CGFloat = 960
    private static let sideMargin: CGFloat = 48
    private static let minimumWidth: CGFloat = 320
    private static let fieldHeight: CGFloat = 24
    private static let fieldInset: CGFloat = 6
    private static let fieldRadius: CGFloat = 7
    private static let eyeSize: CGFloat = 18
    private static let pickerSize: CGFloat = 24
    private static let accessoryGap: CGFloat = 4
    private static let checkboxHeight: CGFloat = 18
    private static let colourSelectorMinimumWidth: CGFloat =
        SAFavoriteColourSelectorLayout.minimumWidth(colourCount: SAVividColour.allCases.count)
    private static let colourSelectorMaximumWidth: CGFloat = 247
    private static let colourSelectorHeight: CGFloat = 22
    private static let connectHeight: CGFloat = 28
    private static let connectMinimumWidth: CGFloat = 96
    private static let ghostHeight: CGFloat = 28
    private static let ghostPadding: CGFloat = 10
    private static let secondaryPadding: CGFloat = 12
    private static let actionGap: CGFloat = 8
    private static let dotSize: CGFloat = 10
    /// Share of the header the type tabs may take.
    private static let tabsShare: CGFloat = 0.62

    private static let labelFont = NSFont.systemFont(ofSize: 12)
    private static let fieldFont = NSFont.systemFont(ofSize: 12)
    private static let noteFont = NSFont.systemFont(ofSize: 11)
    private static let titleFont = NSFont.systemFont(ofSize: 11)
    private static let nameFont = NSFont.systemFont(ofSize: 15, weight: .medium)
    private static let subtitleFont = NSFont.systemFont(ofSize: 12)
    private static let ghostFont = NSFont.systemFont(ofSize: 12)

    private weak var controller: SPConnectionController?
    private weak var container: NSView?
    private weak var scrollView: NSScrollView?
    private weak var tabView: NSTabView?
    private weak var connectButton: NSButton?
    private weak var helpButton: NSButton?
    private weak var progressIndicator: NSProgressIndicator?
    private weak var progressText: NSTextField?
    /// Strong: observed with KVO.
    private var editButtonsView: NSView?
    /// Add to favourites, Save changes, Test — in action-row order.
    private var editButtons: [NSButton] = []
    private var forms: [SAClaudePanelForm] = []

    private let card = SAClaudeTableInfoCardView()
    private let dot = SAClaudeColourDot()
    /// The header title of a type that keeps its XIB form (laid-out types show their Name field there instead).
    private let nameLabel = NSTextField(labelWithString: "")
    /// Starts editing the name.
    private let pencilButton = NSButton(frame: .zero)
    /// The primary for a favourite with unsaved edits: saves, then connects only if the save went through.
    private let saveAndConnectButton = NSButton(title: "", target: nil, action: nil)
    /// Its secondary: the Connect button's own action, without saving.
    private let connectWithoutSavingButton = NSButton(title: "", target: nil, action: nil)
    /// The Connect button's XIB key equivalent (Return); it moves to whichever button is primary.
    private var primaryKeyEquivalent = "\r"
    private var layoutPending = false
    private var actionUpdatePending = false
    private static let pencilSize: CGFloat = 16
    private static let namePlaceholder = NSLocalizedString("ClaudeConnectionNewFavourite", value: "New favourite",
                                                           comment: "connection panel : placeholder of the connection name in the header")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let typeTabs = SAClaudeConnectionTypeTabs()
    private let disclosure = SAClaudeAdvancedDisclosure()
    private var sectionTitles: [SAClaudeConnectionSection: NSTextField] = [:]
    /// The outline behind each text field and combo box (a field's plain twin shares its secure field's).
    private var fieldFrames: [ObjectIdentifier: SAClaudeFieldOutline] = [:]
    /// The key / file pickers' own images (normal, alternate), tinted from these on every theme change.
    private var pickerImages: [ObjectIdentifier: (image: NSImage?, alternate: NSImage?)] = [:]

    /// Advanced was opened for the selected favourite (or by a value turned on while editing); cleared only when
    /// another favourite is selected, so turning a value off never folds the section away mid-edit.
    private var advancedAutoOpened = false
    private var lastFavourite: ObjectIdentifier?
    private var favouriteSeen = false
    private var laidOutAdvancedOpen: Bool?
    private var advancedLayoutPending = false

    private var theme: (palette: SAClaudeEditorChrome.Palette, text: NSColor, fieldFill: NSColor, cardFill: NSColor)?
    private var lastFrames: Layout.Frames?
    private var lastWidth: CGFloat = 0

    private var defaultsObserver: NSObjectProtocol?
    private var scrollFrameObserver: NSObjectProtocol?

    // MARK: Page (set by `SAClaudeConnectionPageStyler` when the connection page owns the layout)

    /// The page's column width; `nil` uses `min(scroll view width − 48, 960)`.
    var columnWidth: CGFloat?
    /// Called after each layout instead of the controller's `scrollViewFrameChanged:` centring: the page places
    /// the card.
    var onLayout: (() -> Void)?
    /// The page's controls before the panel in the key-view loop (search, cards): the loop runs through them and
    /// the panel, and closes on the first.
    var leadingKeyViews: () -> [NSView] = { [] }
    private var observations: [NSKeyValueObservation] = []
    private var windowObservation: NSKeyValueObservation?
    private var firstResponderObservation: NSKeyValueObservation?
    private weak var observedWindow: NSWindow?

    // MARK: - Hooks

    /// Restyles the connection form in `container` and lays it out as the Claude panel. Once per container (a second
    /// call is a no-op); the container retains the styler.
    ///
    /// - Parameter formContainers: the TCP/IP, Socket, SSH, AWS IAM and Vault form containers, in tab order.
    @objc(attachToController:container:scrollView:formContainers:connectButton:helpButton:progressIndicator:progressText:editButtonsView:awsAuthorizeInfoLabel:)
    static func attach(controller: SPConnectionController, container: NSView, scrollView: NSScrollView, formContainers: [NSView],
                       connectButton: NSButton?, helpButton: NSButton?, progressIndicator: NSProgressIndicator?,
                       progressText: NSTextField?, editButtonsView: NSView?, awsAuthorizeInfoLabel: NSTextField?) {
        guard objc_getAssociatedObject(container, &associationKey) == nil,
              let tabView = container.subviews.compactMap({ $0 as? NSTabView }).first,
              formContainers.count == 5, tabView.numberOfTabViewItems == 5,
              formContainers.enumerated().allSatisfy({ $1.superview != nil && $1.superview === tabView.tabViewItem(at: $0).view })
        else {
            debugLog("the connection form doesn't have the expected tab structure; left unstyled")
            return
        }
        let styler = SAClaudeConnectionPanelStyler()
        objc_setAssociatedObject(container, &associationKey, styler, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        styler.controller = controller
        styler.container = container
        styler.scrollView = scrollView
        styler.tabView = tabView
        styler.connectButton = connectButton
        styler.helpButton = helpButton
        styler.progressIndicator = progressIndicator
        styler.progressText = progressText
        styler.editButtonsView = editButtonsView

        // Everything is found from the XIB frames, before anything moves.
        styler.forms = formContainers.enumerated().compactMap { index, formContainer in
            SAClaudeConnectionType(rawValue: index).flatMap { discover(type: $0, formContainer: formContainer, awsInfoLabel: awsAuthorizeInfoLabel) }
        }
        styler.buildViews()
        styler.refresh(force: true)
        styler.observe()
        styler.layOut()
        styler.chainKeyViews()
    }

    /// The end of the controller's `-resizeTabViewToConnectionType:animating:`: the panel takes over the frames.
    @objc(panelDidResizeIn:)
    static func panelDidResize(in container: NSView) {
        styler(for: container)?.layOut()
    }

    /// After the controller's `-updateFavoriteNextKeyView`: re-chains the visible controls in visual order.
    @objc(keyViewsDidChangeIn:)
    static func keyViewsDidChange(in container: NSView) {
        styler(for: container)?.chainKeyViews()
    }

    static func styler(for container: NSView) -> SAClaudeConnectionPanelStyler? {
        objc_getAssociatedObject(container, &associationKey) as? SAClaudeConnectionPanelStyler
    }

    private static func debugLog(_ message: @autoclosure () -> String) {
        #if DEBUG
        NSLog("Claude connection panel: %@", message())
        #endif
    }

    deinit {
        if let defaultsObserver { NotificationCenter.default.removeObserver(defaultsObserver) }
        if let scrollFrameObserver { NotificationCenter.default.removeObserver(scrollFrameObserver) }
        observations.forEach { $0.invalidate() }
        windowObservation?.invalidate()
        firstResponderObservation?.invalidate()
    }

    // MARK: - Finding the form

    private static func keyPath(of view: NSView, _ binding: NSBindingName) -> String? {
        view.infoForBinding(binding)?[.observedKeyPath] as? String
    }

    /// The key path a control edits: its `value` binding, or a pop-up's `selectedValue`.
    private static func valueKeyPath(of view: NSView) -> String? {
        keyPath(of: view, .value) ?? keyPath(of: view, .selectedValue)
    }

    /// A label is shown and hidden with its control: both carry the same `hidden` binding (key path and transformer).
    private static func hiddenSignature(of view: NSView) -> String {
        guard let info = view.infoForBinding(.hidden) else { return "" }
        let options = info[.options] as? [NSBindingOption: Any]
        return "\(info[.observedKeyPath] as? String ?? "")|\(options?[.valueTransformerName] as? String ?? "")"
    }

    private static func action(of control: NSControl) -> String? {
        control.action.map(NSStringFromSelector)
    }

    private static func sectionRank(_ section: SAClaudeConnectionSection) -> Int {
        switch section {
        case .header: return -1
        case .server: return 0
        case .signIn: return 1
        case .sshTunnel: return 2
        case .vault: return 3
        case .advanced: return 4
        }
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private static func discover(type: SAClaudeConnectionType, formContainer: NSView, awsInfoLabel: NSTextField?) -> SAClaudePanelForm? {
        guard let itemView = formContainer.superview else { return nil }
        let sslContainer = itemView.subviews.first { $0 !== formContainer && keyPath(of: $0, .hidden) == "useSSL" }
        let form = SAClaudePanelForm(type: type, itemView: itemView, formContainer: formContainer, sslContainer: sslContainer)
        let views = ([formContainer] + (sslContainer.map { [$0] } ?? [])).flatMap(\.subviews)
        var unknown: [String] = []

        // The controller's eye buttons and plain twins (bound to the same key path, made at the field's frame).
        let eyes = views.compactMap { $0 as? NSButton }.filter { NSStringFromClass(Swift.type(of: $0)) == "SPPasswordRevealButton" }
        var revealViews = Set(eyes.map { ObjectIdentifier($0) })
        for secure in views.compactMap({ $0 as? NSSecureTextField }) {
            guard let key = valueKeyPath(of: secure) else { continue }
            let twin = views.first { candidate in
                guard let plain = candidate as? NSTextField, !(plain is NSSecureTextField), plain.superview === secure.superview else { return false }
                return plain.frame == secure.frame && valueKeyPath(of: plain) == key
            } as? NSTextField
            let eye = eyes.first { $0.superview === secure.superview && secure.frame.contains(NSPoint(x: $0.frame.midX, y: $0.frame.midY)) }
            if let twin, let eye {
                form.reveal[ObjectIdentifier(secure)] = SAClaudeRevealPair(eye: eye, twin: twin)
                revealViews.insert(ObjectIdentifier(twin))
            }
        }
        if form.reveal.count != eyes.count { unknown.append("password reveal button") }

        var keyed: [String: NSView] = [:]
        var pickers: [String: NSButton] = [:]
        var colour: NSView?
        var timeZone: NSPopUpButton?
        var awsAuthorize: NSButton?
        var vaultRefresh: NSButton?
        var vaultSpinner: NSProgressIndicator?
        var awsInfo: NSTextField?

        func addKeyed(_ key: String, _ view: NSView) {
            if keyed[key] != nil { unknown.append("second \(key)") }
            keyed[key] = view
        }

        for view in views where !revealViews.contains(ObjectIdentifier(view)) {
            if let popUp = view as? NSPopUpButton {
                form.popUps.append(popUp)
                if action(of: popUp) == "didChangeSelectedTimeZone:" {
                    timeZone = popUp
                } else if let key = valueKeyPath(of: popUp) {
                    addKeyed(key, popUp)
                } else {
                    unknown.append("pop-up without a binding")
                }
            } else if let button = view as? NSButton {
                if let key = valueKeyPath(of: button) {
                    if key.hasSuffix("Enabled") {
                        // A file / SSH key picker: its state says whether the path field next to it is in use.
                        pickers[String(key.dropLast("Enabled".count))] = button
                        form.pickerButtons.append(button)
                    } else {
                        addKeyed(key, button)
                        form.checkboxes.append(button)
                    }
                } else if action(of: button) == "authorizeAWSDirectory:" {
                    awsAuthorize = button
                    form.ghostButtons.append(button)
                } else if action(of: button) == "refreshVaultRoles:" {
                    vaultRefresh = button
                    form.ghostButtons.append(button)
                } else {
                    unknown.append("button \(action(of: button) ?? "without an action")")
                }
            } else if let field = view as? NSTextField {
                if let key = valueKeyPath(of: field) {
                    addKeyed(key, field)
                    form.fields.append(field)
                } else if let awsInfoLabel, field === awsInfoLabel {
                    awsInfo = field
                    form.notes.append(field)
                } else if !field.isEditable {
                    form.labels.append(field)
                } else {
                    unknown.append("text field without a binding")
                }
            } else if NSStringFromClass(Swift.type(of: view)) == "SPColorSelectorView" {
                if colour != nil { unknown.append("second colour selector") }
                colour = view
            } else if let spinner = view as? NSProgressIndicator {
                if vaultSpinner != nil { unknown.append("second progress indicator") }
                vaultSpinner = spinner
            } else {
                unknown.append(String(describing: Swift.type(of: view)))
            }
        }
        // The plain twins are styled like their fields.
        form.fields += form.reveal.values.map(\.twin)

        // Classification.
        for key in keyed.keys.sorted() where SAClaudeConnectionClassifier.placement(keyPath: key, type: type) == nil {
            unknown.append(key)
        }
        let missing = SAClaudeConnectionClassifier.requiredKeyPaths(for: type).subtracting(keyed.keys)
        if !missing.isEmpty { unknown.append("missing \(missing.sorted().joined(separator: ", "))") }

        func placement(_ key: String) -> (section: SAClaudeConnectionSection, order: Int)? {
            SAClaudeConnectionClassifier.placement(keyPath: key, type: type)
        }

        var rows: [SAClaudePanelRow] = []
        for (key, view) in keyed where key != "requestServerPublicKey" {
            guard let place = placement(key) else { continue }
            var kind: SAClaudeConnectionRowKind = view is NSButton ? .checkbox : .field
            var condition: SAClaudePanelRow.Condition = .always
            var accessory: NSButton?
            switch key {
            case "useSSL":
                kind = .checkboxPair
            case "sslKeyFileLocation", "sslCertificateFileLocation", "sslCACertFileLocation":
                kind = .fileRow
                condition = .ssl
                accessory = pickers[key]
            case "sshPassword":
                kind = .fileRow
                condition = .sshPassword
                accessory = pickers["sshKeyLocation"]
            case "sshKeyLocation":
                kind = .fileRow
                condition = .sshKey
                accessory = pickers["sshKeyLocation"]
            case "awsProfile", "awsRegion":
                condition = .awsAuthorised
            case "vaultCredentialsRole":
                kind = .comboWithButton
                accessory = vaultRefresh
            default:
                break
            }
            let row = SAClaudePanelRow(id: key, kind: kind, section: place.section, order: place.order, condition: condition, control: view)
            row.accessory = accessory
            if key == "useSSL" { row.secondary = keyed["requestServerPublicKey"] as? NSButton }
            if key == "vaultCredentialsRole" { row.spinner = vaultSpinner }
            rows.append(row)
        }
        if let colour, let place = placement("colour") {
            rows.append(SAClaudePanelRow(id: "colour", kind: .colour, section: place.section, order: place.order, condition: .always, control: colour))
        }
        if let timeZone, let place = placement("timeZone") {
            rows.append(SAClaudePanelRow(id: "timeZone", kind: .field, section: place.section, order: place.order, condition: .always, control: timeZone))
        }
        if let awsAuthorize, let place = placement("awsProfile") {
            rows.append(SAClaudePanelRow(id: "awsAuthorise", kind: .button, section: place.section, order: place.order,
                                         condition: .awsUnauthorised, control: awsAuthorize))
        }
        if let awsInfo, let place = placement("awsRegion") {
            rows.append(SAClaudePanelRow(id: "awsNote", kind: .note(height: 30), section: place.section, order: place.order,
                                         condition: .awsUnauthorised, control: awsInfo))
        }
        // Accessories that belong to no row (a picker whose field is missing, Refresh without the role combo).
        let placedAccessories = Set(rows.compactMap(\.accessory).map { ObjectIdentifier($0) })
        for button in form.pickerButtons + [vaultRefresh].compactMap({ $0 }) where !placedAccessories.contains(ObjectIdentifier(button)) {
            unknown.append("unplaced \(action(of: button) ?? "button")")
        }

        // Labels: the static text left of each control, on its row, shown and hidden with it (XIB frames).
        var paired = Set<ObjectIdentifier>()
        for row in rows {
            switch row.kind {
            case .checkbox, .checkboxPair, .note: continue
            default: break
            }
            let candidates = form.labels.filter {
                $0.superview === row.control.superview && hiddenSignature(of: $0) == hiddenSignature(of: row.control)
            }
            if let index = SAClaudeTableInfoLayout.labelIndex(for: row.control.frame, among: candidates.map(\.frame)) {
                row.label = candidates[index]
                paired.insert(ObjectIdentifier(candidates[index]))
            }
        }
        let leftover = form.labels.filter { !paired.contains(ObjectIdentifier($0)) }
        if type == .awsIAM, leftover.count == 1, let note = leftover.first, let place = placement("awsSSLNote") {
            // The "SSL/TLS … enabled automatically" note: the only AWS text that labels no control.
            form.labels.removeAll { $0 === note }
            form.notes.append(note)
            rows.append(SAClaudePanelRow(id: "awsSSLNote", kind: .note(height: 30), section: place.section, order: place.order,
                                         condition: .always, control: note))
        } else if !leftover.isEmpty {
            unknown.append("\(leftover.count) unpaired label(s)")
        }
        if let colourRow = rows.first(where: { $0.id == "colour" }) { colourRow.label = form.colourLabel }

        form.rows = rows.sorted {
            (sectionRank($0.section), $0.order, $0.id) < (sectionRank($1.section), $1.order, $1.id)
        }
        form.canLayOut = unknown.isEmpty
        if !unknown.isEmpty {
            debugLog("\(type) keeps its XIB layout: \(unknown.joined(separator: "; "))")
        }
        return form
    }

    // MARK: - Building

    private func buildViews() {
        guard let container, let tabView else { return }
        tabView.tabViewType = .noTabsNoBorder
        tabView.drawsBackground = false

        card.radius = Layout.radius
        card.frame = container.bounds
        card.autoresizingMask = [.width, .height]
        container.addSubview(card, positioned: .below, relativeTo: nil)

        for label in [nameLabel, subtitleLabel] {
            label.lineBreakMode = .byTruncatingTail
            label.autoresizingMask = []
            container.addSubview(label)
        }
        nameLabel.font = Self.nameFont
        subtitleLabel.font = Self.subtitleFont
        container.addSubview(dot)

        typeTabs.titles = tabView.tabViewItems.map(\.label)
        typeTabs.onSelect = { [weak self] index in
            guard let tabView = self?.tabView, index < tabView.numberOfTabViewItems else { return }
            tabView.selectTabViewItem(at: index)
        }
        container.addSubview(typeTabs)

        let titles: [(SAClaudeConnectionSection, String)] = [
            (.server, NSLocalizedString("ClaudeConnectionSectionServer", value: "Server", comment: "connection panel : section title")),
            (.signIn, NSLocalizedString("ClaudeConnectionSectionSignIn", value: "Sign in", comment: "connection panel : section title")),
            (.sshTunnel, NSLocalizedString("ClaudeConnectionSectionSSHTunnel", value: "SSH tunnel", comment: "connection panel : section title")),
            (.vault, NSLocalizedString("ClaudeConnectionSectionVault", value: "Vault", comment: "connection panel : section title")),
        ]
        for (section, text) in titles {
            let title = NSTextField(labelWithString: text)
            title.font = Self.titleFont
            title.lineBreakMode = .byTruncatingTail
            title.isHidden = true
            container.addSubview(title)
            sectionTitles[section] = title
        }

        disclosure.onToggle = { [weak self] in self?.toggleAdvanced() }
        container.addSubview(disclosure)

        // The name is the panel's title: each laid-out type's own Name field moves into the header (its XIB label
        // hides); only the selected type's shows.
        for form in forms where form.canLayOut {
            guard let row = form.rows.first(where: { $0.section == .header }), let field = row.control as? NSTextField else { continue }
            row.label?.isHidden = true
            field.removeFromSuperview()
            field.autoresizingMask = []
            container.addSubview(field)
            form.nameField = field
        }
        SAClaudeFilterCells.installCellDrawing(on: pencilButton)
        pencilButton.isBordered = false
        pencilButton.bezelStyle = .regularSquare
        pencilButton.imagePosition = .imageOnly
        pencilButton.title = ""
        pencilButton.target = self
        pencilButton.action = #selector(beginEditingName)
        let editName = NSLocalizedString("ClaudeConnectionEditName", value: "Edit name",
                                         comment: "connection panel : pencil button that starts editing the connection name")
        pencilButton.toolTip = editName
        pencilButton.setAccessibilityLabel(editName)
        container.addSubview(pencilButton)
        SAClaudeHoverHighlighter.attach(to: pencilButton)

        for form in forms {
            for label in form.labels {
                label.stringValue = Self.sentenceCase(label.stringValue)
            }
            if form.canLayOut, let colourRow = form.rows.first(where: { $0.id == "colour" }), let superview = colourRow.control.superview {
                superview.addSubview(form.colourLabel)
                form.labels.append(form.colourLabel)
            }
            for field in form.fields {
                frameView(for: field, in: form)
            }
            for note in form.notes {
                note.cell?.wraps = true
                note.lineBreakMode = .byWordWrapping
            }
        }

        // Add / Save / Test join the card's action row; the edit-buttons box keeps only its visibility (mirrored).
        if let editButtonsView {
            let buttons = editButtonsView.subviews.compactMap { $0 as? NSButton }
            let order = ["addFavoriteUsingCurrentDetails:", "saveFavorite:", "initiateConnection:"]
            editButtons = order.compactMap { name in buttons.first { Self.action(of: $0) == name } }
            for button in editButtons {
                button.removeFromSuperview()
                button.autoresizingMask = []
                button.isHidden = editButtonsView.isHidden
                container.addSubview(button)
            }
            if let add = editButtons.first(where: { Self.action(of: $0) == "addFavoriteUsingCurrentDetails:" }) {
                add.title = NSLocalizedString("ClaudeConnectionAddToFavourites", value: "Add to favourites",
                                              comment: "connection panel : button saving the current details as a new favourite")
            }
            if let test = editButtons.first(where: { Self.action(of: $0) == "initiateConnection:" }) {
                test.title = NSLocalizedString("ClaudeConnectionTest", value: "Test",
                                               comment: "connection panel : button testing the connection details")
            }
            // The action row's primary and secondary for a favourite with unsaved edits.
            saveAndConnectButton.title = NSLocalizedString("ClaudeConnectionSaveAndConnect", value: "Save and connect",
                                                           comment: "connection panel : primary button saving the favourite's edits, then connecting")
            saveAndConnectButton.target = self
            saveAndConnectButton.action = #selector(saveAndConnect(_:))
            connectWithoutSavingButton.title = NSLocalizedString("ClaudeConnectionConnectWithoutSaving", value: "Connect without saving",
                                                                 comment: "connection panel : button connecting with the edited details, leaving the favourite unsaved")
            connectWithoutSavingButton.target = controller
            connectWithoutSavingButton.action = #selector(SPConnectionController.initiateConnection(_:))
            for button in [saveAndConnectButton, connectWithoutSavingButton] {
                button.bezelStyle = .regularSquare
                button.autoresizingMask = []
                button.isHidden = true
                container.addSubview(button)
            }
            // The box slides and fades in when editing starts; with no size it can't cover the action row.
            editButtonsView.autoresizingMask = []
            editButtonsView.setFrameSize(.zero)
        }

        // Class swaps first: the hover highlighters observe the buttons with KVO.
        for form in forms {
            form.popUps.forEach { SAClaudeFilterCells.installPill(on: $0) }
            form.checkboxes.forEach { SAClaudeFilterCells.install(SAClaudeCheckboxCell.self, on: $0) }
        }
        for button in pickerButtons {
            pickerImages[ObjectIdentifier(button)] = (button.image, button.alternateImage)
        }
        for button in ghostButtons + pickerButtons {
            SAClaudeFilterCells.installCellDrawing(on: button)
            button.isBordered = false
            SAClaudeHoverHighlighter.attach(to: button)
        }
        if let connectButton, SAClaudeFilterCells.install(SAClaudeFullHeightAccentButtonCell.self, on: connectButton) {
            connectButton.isBordered = false
        }
        if let connectButton, !connectButton.keyEquivalent.isEmpty { primaryKeyEquivalent = connectButton.keyEquivalent }
        if SAClaudeFilterCells.install(SAClaudeFullHeightAccentButtonCell.self, on: saveAndConnectButton) {
            saveAndConnectButton.isBordered = false
        }
        // Real bordered secondary buttons (with the hover fill behind them).
        for button in secondaryButtons {
            SAClaudeFilterCells.install(SAClaudeSecondaryButtonCell.self, on: button)
            button.isBordered = false
            SAClaudeHoverHighlighter.attach(to: button)
        }
        if let helpButton {
            helpButton.bezelStyle = .regularSquare
            helpButton.imagePosition = .noImage
            helpButton.title = "?"
        }
        // Labels bound to an enabled state (AWS profile / region) keep their disabled dimming.
        for label in forms.flatMap(\.labels) where Self.keyPath(of: label, .enabled) != nil {
            observations.append(label.observe(\.isEnabled) { [weak self] label, _ in
                self?.onMain { $0.styleLabelColour(label) }
            })
        }
        // Their titles follow the enabled state (a borderless cell with a coloured title doesn't dim it).
        for button in ghostButtons {
            observations.append(button.observe(\.isEnabled) { [weak self] _, _ in self?.onMain { $0.styleGhostTitles() } })
        }
    }

    /// The ghost buttons: help, AWS Authorize and Vault Refresh.
    private var ghostButtons: [NSButton] {
        [helpButton].compactMap { $0 } + forms.flatMap(\.ghostButtons)
    }

    /// The action row's bordered secondaries: Add to favourites, Save changes, Test, Connect without saving.
    private var secondaryButtons: [NSButton] {
        editButtons + [connectWithoutSavingButton]
    }

    private func editButton(_ action: String) -> NSButton? {
        editButtons.first { Self.action(of: $0) == action }
    }

    private var pickerButtons: [NSButton] {
        forms.flatMap(\.pickerButtons)
    }

    @discardableResult
    private func frameView(for field: NSTextField, in form: SAClaudePanelForm) -> SAClaudeFieldOutline? {
        guard let superview = field.superview else { return nil }
        // A plain twin shares its secure field's outline.
        if let secure = form.reveal.first(where: { $0.value.twin === field })?.key, let shared = fieldFrames[secure] {
            fieldFrames[ObjectIdentifier(field)] = shared
            if !shared.fields.contains(where: { $0 === field }) { shared.fields.append(field) }
            return shared
        }
        if let existing = fieldFrames[ObjectIdentifier(field)] { return existing }
        let frameView = SAClaudeFieldOutline()
        frameView.radius = Self.fieldRadius
        frameView.fields = [field]
        frameView.frame = field.frame
        frameView.autoresizingMask = field.autoresizingMask
        superview.addSubview(frameView, positioned: .below, relativeTo: field)
        fieldFrames[ObjectIdentifier(field)] = frameView
        if let pair = form.reveal[ObjectIdentifier(field)] {
            fieldFrames[ObjectIdentifier(pair.twin)] = frameView
            frameView.fields.append(pair.twin)
        }
        return frameView
    }

    /// "Time Zone:" → "Time zone": no trailing colon, later words lower-cased unless they are acronyms or names
    /// with inner capitals (SSH, MySQL, OIDC, CA).
    static func sentenceCase(_ text: String) -> String {
        var trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.hasSuffix(":") { trimmed.removeLast() }
        let words = trimmed.split(separator: " ", omittingEmptySubsequences: false)
        return words.enumerated().map { index, word -> String in
            guard index > 0, let first = word.first, first.isUppercase,
                  !word.dropFirst().contains(where: { $0.isUppercase }) else { return String(word) }
            return first.lowercased() + word.dropFirst()
        }.joined(separator: " ")
    }

    // MARK: - Observing

    private func observe() {
        guard let controller, let container else { return }
        // No `queue: .main`: a defaults write on a background thread posts synchronously there, and an observer
        // queue makes the writer wait for the main queue (a deadlock while main waits on that writer).
        defaultsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: nil) { [weak self] _ in
            self?.onMain { $0.refresh(force: false) }
        }
        observations.append(container.observe(\.effectiveAppearance) { [weak self] _, _ in
            self?.onMain { $0.refresh(force: true) }
        })
        // The Connect button, checkboxes and the focused field's outline are drawn in the accent.
        SAClaudeAccent.observe(self) { styler in
            styler.updateFocus()
            if let container = styler.container { SAClaudeAccent.redisplay(container) }
        }
        if let scrollView {
            scrollView.postsFrameChangedNotifications = true
            scrollFrameObserver = NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: scrollView, queue: nil) { [weak self] _ in
                self?.onMain { styler in
                    if styler.panelWidth() != styler.lastWidth { styler.layOut() }
                }
            }
        }
        let header: [NSKeyValueObservation] = [
            controller.observe(\.name) { [weak self] _, _ in self?.onMain { $0.updateHeader() } },
            controller.observe(\.host) { [weak self] _, _ in self?.onMain { $0.updateHeader() } },
            controller.observe(\.port) { [weak self] _, _ in self?.onMain { $0.updateHeader() } },
            controller.observe(\.socket) { [weak self] _, _ in self?.onMain { $0.updateHeader() } },
            controller.observe(\.sshHost) { [weak self] _, _ in self?.onMain { $0.updateHeader() } },
            controller.observe(\.type) { [weak self] _, _ in self?.onMain { $0.updateHeader() } },
            controller.observe(\.colorIndex) { [weak self] _, _ in self?.onMain { $0.updateHeader() } },
        ]
        observations += header
        // The SSH password and key share a row: the eye button and a revealed twin follow which one shows. Laid out
        // on the next turn, after the bindings have shown / hidden the two fields.
        observations.append(controller.observe(\.sshKeyLocationEnabled) { [weak self] _, _ in
            self?.onMain { $0.setNeedsLayoutSoon() }
        })
        // AWS authorisation: the controller swaps Authorize + note for profile + region without resizing the form
        // (`updateAWSAuthorizationUI` after the bookmark is added), so the panel follows the Authorize button.
        for button in forms.flatMap(\.ghostButtons) where Self.action(of: button) == "authorizeAWSDirectory:" {
            observations.append(button.observe(\.isHidden) { [weak self] _, _ in self?.onMain { $0.setNeedsLayoutSoon() } })
        }
        // Connecting: Connect turns into Cancel (and back); the primary follows on the next turn, once the
        // controller's state has settled.
        if let connectButton {
            observations.append(connectButton.observe(\.title) { [weak self] _, _ in self?.onMain { $0.scheduleActionUpdate() } })
            observations.append(connectButton.observe(\.isEnabled) { [weak self] _, _ in self?.onMain { $0.scheduleActionUpdate() } })
        }
        // Advanced: the disclosure's lock and open state follow the values live (the time zone pop-up's action sets
        // `timeZoneMode`).
        let advanced: [NSKeyValueObservation] = [
            controller.observe(\.useSSL) { [weak self] _, _ in self?.onMain { $0.advancedValuesChanged() } },
            controller.observe(\.allowDataLocalInfile) { [weak self] _, _ in self?.onMain { $0.advancedValuesChanged() } },
            controller.observe(\.enableClearTextPlugin) { [weak self] _, _ in self?.onMain { $0.advancedValuesChanged() } },
            controller.observe(\.requestServerPublicKey) { [weak self] _, _ in self?.onMain { $0.advancedValuesChanged() } },
            controller.observe(\.timeZoneMode) { [weak self] _, _ in self?.onMain { $0.advancedValuesChanged() } },
            controller.observe(\.sslKeyFileLocation) { [weak self] _, _ in self?.onMain { $0.advancedValuesChanged() } },
            controller.observe(\.sslCertificateFileLocation) { [weak self] _, _ in self?.onMain { $0.advancedValuesChanged() } },
            controller.observe(\.sslCACertFileLocation) { [weak self] _, _ in self?.onMain { $0.advancedValuesChanged() } },
        ]
        observations += advanced
        if let editButtonsView {
            observations.append(editButtonsView.observe(\.isHidden) { [weak self] _, _ in self?.onMain { $0.updateActionButtons() } })
        }
        windowObservation = container.observe(\.window) { [weak self] _, _ in
            self?.onMain { $0.observeFirstResponder() }
        }
        observeFirstResponder()
    }

    private func onMain(_ work: @escaping (SAClaudeConnectionPanelStyler) -> Void) {
        if Thread.isMainThread {
            work(self)
        } else {
            DispatchQueue.main.async { [weak self] in
                if let self { work(self) }
            }
        }
    }

    /// Follows the first responder of the container's current window, for the fields' clay focus outline.
    private func observeFirstResponder() {
        guard let container, container.window !== observedWindow else { return }
        firstResponderObservation = nil
        observedWindow = container.window
        updateFocus()
        guard let window = container.window else { return }
        firstResponderObservation = window.observe(\.firstResponder) { [weak self] _, _ in
            self?.onMain { $0.updateFocus() }
        }
    }

    /// One layout on the next main-queue turn, however many changes ask for it before then.
    private func setNeedsLayoutSoon() {
        guard !layoutPending else { return }
        layoutPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.layoutPending = false
            self.layOut()
        }
    }

    private func scheduleActionUpdate() {
        guard !actionUpdatePending else { return }
        actionUpdatePending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.actionUpdatePending = false
            self.updateActionButtons()
        }
    }

    // MARK: - Action row

    /// Which buttons the action row shows, and which is primary (clay, Return):
    /// - a favourite with unsaved edits (the controller's edit-buttons box shown): Save and connect; secondaries
    ///   Connect without saving, Save changes, Add to favourites, Test;
    /// - a favourite without edits: Connect only;
    /// - Quick connect: Connect; secondaries Add to favourites, Test;
    /// - while connecting: Connect (now Cancel) is the primary; Save and connect / Connect without saving hide.
    private func updateActionButtons() {
        guard let controller, let connectButton else { return }
        let connecting = controller.isConnecting || connectButton.action.map(NSStringFromSelector) == "cancelConnection:"
        let favourite = controller.selectedFavorite() != nil
        let editing = !(editButtonsView?.isHidden ?? true)
        let saveFirst = favourite && editing && !connecting
        func show(_ button: NSButton?, _ shown: Bool) {
            if let button, button.isHidden == shown { button.isHidden = !shown }
        }
        show(connectButton, !saveFirst)
        show(saveAndConnectButton, saveFirst)
        show(connectWithoutSavingButton, saveFirst)
        show(editButton("saveFavorite:"), favourite && editing)
        show(editButton("addFavoriteUsingCurrentDetails:"), editing || !favourite)
        show(editButton("initiateConnection:"), editing || !favourite)
        // The controller disables Connect while Vault roles refresh (and while connecting); the two new buttons follow.
        let canConnect = connectButton.isEnabled && !connecting
        if saveAndConnectButton.isEnabled != canConnect { saveAndConnectButton.isEnabled = canConnect }
        if connectWithoutSavingButton.isEnabled != canConnect { connectWithoutSavingButton.isEnabled = canConnect }

        let primary: NSButton = saveFirst ? saveAndConnectButton : connectButton
        for button in [connectButton, saveAndConnectButton] {
            let key = button === primary ? primaryKeyEquivalent : ""
            if button.keyEquivalent != key { button.keyEquivalent = key }
        }
        layOutActionRow()
    }

    /// Saves the favourite's edits, then connects — only when the save went through: a successful save ends the
    /// controller's editing state; a failed one (an alert about missing details) returns with the edits still open.
    @objc private func saveAndConnect(_ sender: Any?) {
        guard let controller, !controller.isConnecting, controller.selectedFavorite() != nil else { return }
        controller.saveFavorite(sender)
        guard !controller.isEditingConnection else { return }
        controller.initiateConnection(connectButton)
    }

    // MARK: - Colours

    /// Re-derives the colours when the editor theme changed (or always, when `force`) and restyles everything.
    private func refresh(force: Bool) {
        guard let container else { return }
        var resolved: (SAClaudeEditorChrome.Palette, NSColor, NSColor, NSColor)?
        container.effectiveAppearance.performAsCurrentDrawingAppearance {
            let palette = SAClaudeEditorChrome.palette(from: .standard)
            let text = SAClaudeThemeColours.from(defaults: .standard).text
            resolved = (palette, text, SAClaudeFilterChrome.fieldFill(text: text, background: palette.background),
                        SAClaudeFilterChrome.cardFill(text: text, background: palette.background))
        }
        guard let (palette, text, fieldFill, cardFill) = resolved else { return }
        // The pill and checkbox cells read these at draw time.
        SAClaudeFilterBarStyler.currentPalette = palette
        SAClaudeFilterBarStyler.currentThemeText = text
        guard force || palette != theme?.palette || text != theme?.text else { return }
        theme = (palette, text, fieldFill, cardFill)

        card.fill = cardFill
        card.stroke = palette.hairline
        subtitleLabel.textColor = palette.icon
        pencilButton.image = SAClaudeGlyphs.image(.editMode, tint: palette.icon)
        SAClaudeHoverHighlighter.setFillColour(palette.hover, for: pencilButton)
        dot.ringColour = SAClaudeFilterChrome.dropStroke(text: text, background: cardFill)
        for title in sectionTitles.values { title.textColor = palette.icon }
        disclosure.titleColour = palette.icon
        typeTabs.colours = SAClaudeConnectionTypeTabs.Colours(
            selectedFill: fieldFill, selectedStroke: SAClaudeFilterChrome.dropStroke(text: text, background: cardFill),
            hoverFill: palette.hover, text: text, mutedText: palette.icon)

        for form in forms {
            for label in form.labels {
                label.font = Self.labelFont
                styleLabelColour(label)
                label.alignment = .right
                label.lineBreakMode = .byTruncatingTail
                label.drawsBackground = false
            }
            for note in form.notes {
                note.font = Self.noteFont
                note.textColor = palette.icon
                note.alignment = .left
                note.drawsBackground = false
            }
            // Placeholders ("optional", "3306") drew as bright as values: the fields draw them muted themselves.
            for field in form.fields {
                styleField(field, text: text)
                // The name field has its own placeholder cell (below).
                if field !== form.nameField { SAClaudeMutedPlaceholderCell.install(on: field) }
            }
            if let nameField = form.nameField {
                // The title: SF Pro 15 medium in the theme's text colour; "New favourite" while empty.
                nameField.font = Self.nameFont
                // The XIB's `name` binding re-applies its null placeholder ("optional") on every update, so the cell
                // ignores placeholders set on it and always shows this one.
                if let cell = nameField.cell, type(of: cell) == NSTextFieldCell.self {
                    object_setClass(cell, SAClaudeNamePlaceholderCell.self)
                }
                SAClaudeNamePlaceholderCell.placeholder = NSAttributedString(string: Self.namePlaceholder, attributes: [
                    .font: Self.nameFont, .foregroundColor: palette.icon,
                ])
                (nameField.cell as? SAClaudeNamePlaceholderCell)?.applyPlaceholder()
                nameField.needsDisplay = true
                nameField.lineBreakMode = .byTruncatingTail
            }
            for popUp in form.popUps {
                SAClaudeFilterCells.installPill(on: popUp)
                popUp.needsDisplay = true
            }
            for checkbox in form.checkboxes {
                SAClaudeFilterCells.install(SAClaudeCheckboxCell.self, on: checkbox)
                checkbox.needsDisplay = true
            }
            for pair in form.reveal.values {
                pair.eye.contentTintColor = palette.icon
            }
        }
        for frameView in fieldFrames.values where frameView.fill != fieldFill {
            frameView.fill = fieldFill
        }
        for button in ghostButtons + pickerButtons {
            SAClaudeHoverHighlighter.setFillColour(palette.hover, for: button)
            button.needsDisplay = true
        }
        // The key / file pickers' glyphs in the theme's colours: muted, and the text colour once a file is chosen.
        for button in pickerButtons {
            guard let originals = pickerImages[ObjectIdentifier(button)] else { continue }
            button.image = originals.image.map { Self.tinted($0, palette.icon) }
            button.alternateImage = originals.alternate.map { Self.tinted($0, palette.buttonText) }
        }
        for button in secondaryButtons + [saveAndConnectButton] {
            SAClaudeHoverHighlighter.setFillColour(palette.hover, for: button)
            button.needsDisplay = true
        }
        styleGhostTitles()
        if let progressText {
            progressText.font = Self.labelFont
            progressText.textColor = palette.icon
        }
        connectButton?.needsDisplay = true
        updateHeader()
        updateFocus()
        container.needsDisplay = true
    }

    /// The muted label colour, dimmed further while the label is disabled (the AWS labels follow authorisation).
    private func styleLabelColour(_ label: NSTextField) {
        let palette = theme?.palette ?? SAClaudeFilterBarStyler.currentPalette
        let colour = label.isEnabled ? palette.icon : palette.icon.withAlphaComponent(0.45)
        if label.textColor != colour { label.textColor = colour }
    }

    /// `image` filled with `colour` wherever it is opaque.
    private static func tinted(_ image: NSImage, _ colour: NSColor) -> NSImage {
        let tinted = NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            colour.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        tinted.accessibilityDescription = image.accessibilityDescription
        return tinted
    }

    /// A text field or combo box without its bezel: the theme's text colour on the outline view behind it.
    private func styleField(_ field: NSTextField, text: NSColor) {
        field.isBezeled = false
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = Self.fieldFont
        field.textColor = text
        if let comboBox = field as? NSComboBox { comboBox.isButtonBordered = false }
        field.needsDisplay = true
    }

    private func styleGhostTitles() {
        guard let theme else { return }
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        for button in ghostButtons {
            let colour = button.isEnabled ? theme.palette.buttonText : theme.palette.buttonText.withAlphaComponent(0.4)
            let attributed = NSAttributedString(string: button.title, attributes: [
                .font: Self.ghostFont, .foregroundColor: colour, .paragraphStyle: style,
            ])
            if button.attributedTitle != attributed { button.attributedTitle = attributed }
        }
    }

    /// Clay outline on the field being edited (its field editor is the window's first responder), else the hairline.
    private func updateFocus() {
        guard let theme else { return }
        var editing = Set<ObjectIdentifier>()
        for form in forms {
            for field in form.fields where field.currentEditor() != nil {
                if let frameView = fieldFrames[ObjectIdentifier(field)] { editing.insert(ObjectIdentifier(frameView)) }
            }
        }
        for frameView in fieldFrames.values {
            let stroke = editing.contains(ObjectIdentifier(frameView)) ? SAClaudeStatusChrome.clay : theme.palette.hairline
            if frameView.stroke != stroke { frameView.stroke = stroke }
        }
        // The header's name shows the field look only while it is edited (and widens to its cap meanwhile).
        for form in forms {
            guard let nameField = form.nameField, let outline = fieldFrames[ObjectIdentifier(nameField)] else { continue }
            let hidden = nameField.isHidden || !editing.contains(ObjectIdentifier(outline))
            if outline.isHidden != hidden { outline.isHidden = hidden }
        }
        if let frames = lastFrames { layOutHeader(frames) }
    }

    private var currentForm: SAClaudePanelForm? {
        guard let controller else { return nil }
        return forms.first { $0.type.rawValue == controller.type }
    }

    /// The pencil (and Rename): edit the name, all of it selected. A type that keeps its XIB form edits its own
    /// Name field there.
    @objc func beginEditingName() {
        guard let form = currentForm,
              let field = form.nameField ?? form.rows.first(where: { $0.section == .header })?.control as? NSTextField,
              !field.isHiddenOrHasHiddenAncestor, let window = field.window else { return }
        if window.makeFirstResponder(field) {
            // Not `selectText(_:)`: on a field that is already editing it ends that edit first.
            field.currentEditor()?.selectAll(nil)
            field.scrollToVisible(field.bounds)
        }
    }

    // MARK: - Header

    private func updateHeader() {
        guard let controller else { return }
        let type = SAClaudeConnectionType(rawValue: controller.type) ?? .tcpip
        let name = controller.name ?? ""
        nameLabel.stringValue = name.isEmpty ? Self.namePlaceholder : name
        if let theme {
            nameLabel.textColor = name.isEmpty ? theme.palette.icon : theme.text
        }
        subtitleLabel.stringValue = SAClaudeConnectionSummary.subtitle(
            type: type, host: controller.host ?? "", port: controller.port ?? "", socket: controller.socket ?? "",
            sshHost: controller.sshHost ?? "")
        let colours = SPFavoriteColorSupport.sharedInstance().userColorList ?? []
        dot.colour = colours.indices.contains(controller.colorIndex) ? colours[controller.colorIndex] : nil
        if typeTabs.selectedIndex != type.rawValue { typeTabs.selectedIndex = type.rawValue }
        if let frames = lastFrames { layOutHeader(frames) }
    }

    // MARK: - Advanced

    /// Counts only what the selected type's Advanced section shows: the SSL files only while Require SSL is on, and
    /// on AWS IAM (SSL forced, no plugin options) none of the SSL / plugin values — a saved value there could
    /// otherwise lock the fold open with nothing to turn off.
    private var advancedHasNonDefault: Bool {
        guard let controller else { return false }
        let aws = controller.type == SAClaudeConnectionType.awsIAM.rawValue
        let ssl = !aws && controller.useSSL != 0
        let state = SAClaudeConnectionAdvancedState(
            useSSL: ssl, allowDataLocalInfile: controller.allowDataLocalInfile != 0,
            enableClearTextPlugin: !aws && controller.enableClearTextPlugin != 0,
            requestServerPublicKey: !aws && controller.requestServerPublicKey != 0,
            timeZoneIsServerDefault: controller.timeZoneMode == .useServerTZ,
            sslFiles: ssl ? [controller.sslKeyFileLocation, controller.sslCertificateFileLocation, controller.sslCACertFileLocation] : [])
        return SAClaudeConnectionAdvanced.hasNonDefault(state)
    }

    private var advancedOpen: Bool {
        advancedAutoOpened || UserDefaults.standard.bool(forKey: Self.advancedOpenKey)
    }

    /// A newly selected favourite (or Quick connect) opens Advanced exactly when it has a non-default value.
    private func syncFavouriteSelection() {
        let identity = controller?.selectedFavoriteNode().map { ObjectIdentifier($0) }
        guard !favouriteSeen || identity != lastFavourite else { return }
        favouriteSeen = true
        lastFavourite = identity
        advancedAutoOpened = advancedHasNonDefault
    }

    /// An advanced value changed: turning one on opens the fold (it then stays open for this favourite); the
    /// disclosure's lock follows at once, the layout on the next turn (a favourite load changes several values).
    private func advancedValuesChanged() {
        let nonDefault = advancedHasNonDefault
        if nonDefault { advancedAutoOpened = true }
        disclosure.isLocked = nonDefault
        guard advancedOpen != laidOutAdvancedOpen, !advancedLayoutPending else { return }
        advancedLayoutPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.advancedLayoutPending = false
            if self.advancedOpen != self.laidOutAdvancedOpen { self.layOut() }
        }
    }

    /// Only while no advanced value is on (the fold can't close over one); the choice is remembered.
    private func toggleAdvanced() {
        guard !advancedHasNonDefault else { return }
        let open = !advancedOpen
        UserDefaults.standard.set(open, forKey: Self.advancedOpenKey)
        if !open { advancedAutoOpened = false }
        layOut()
    }

    // MARK: - Layout

    private func panelWidth() -> CGFloat {
        if let columnWidth { return max(Self.minimumWidth, columnWidth.rounded(.down)) }
        let available = (scrollView?.frame.width ?? 0) - Self.sideMargin
        return max(Self.minimumWidth, min(available, Self.maximumWidth)).rounded(.down)
    }

    private func isVisible(_ row: SAClaudePanelRow) -> Bool {
        guard let controller else { return false }
        switch row.condition {
        case .always: return true
        case .ssl: return controller.useSSL != 0
        case .awsAuthorised: return controller.isAWSDirectoryAuthorized()
        case .awsUnauthorised: return !controller.isAWSDirectoryAuthorized()
        case .sshPassword: return controller.sshKeyLocationEnabled == 0
        case .sshKey: return controller.sshKeyLocationEnabled != 0
        }
    }

    /// Sets `frame` (on whole points) only when it changed, and stops the view autoresizing: the panel owns it.
    private static func place(_ view: NSView, _ frame: NSRect) {
        let aligned = NSRect(x: frame.minX.rounded(), y: frame.minY.rounded(), width: frame.width.rounded(), height: frame.height.rounded())
        if view.frame != aligned { view.frame = aligned }
        if !view.autoresizingMask.isEmpty { view.autoresizingMask = [] }
    }

    private static func centred(height: CGFloat, in rect: NSRect) -> CGFloat {
        (rect.midY - height / 2).rounded(.down)
    }

    private static func textHeight(_ field: NSTextField) -> CGFloat {
        ceil(field.cell?.cellSize.height ?? field.fittingSize.height)
    }

    private static func fittingWidth(_ control: NSControl) -> CGFloat {
        ceil(control.cell?.cellSize.width ?? control.fittingSize.width)
    }

    private static func ghostWidth(_ button: NSButton) -> CGFloat {
        ceil(NSAttributedString(string: button.title, attributes: [.font: ghostFont]).size().width) + 2 * ghostPadding
    }

    /// The card's size from the panel's last layout (the container's own frame can briefly be the controller's while
    /// it resizes the form); `nil` before the first layout.
    var laidOutSize: NSSize? {
        lastFrames.map { NSSize(width: lastWidth, height: $0.height) }
    }

    /// Lays the panel out for the selected type, then lets the page (or the controller) place it.
    func layOut() {
        guard let controller, let container, let tabView,
              let form = forms.first(where: { $0.type.rawValue == controller.type }) else { return }
        syncFavouriteSelection()
        let width = panelWidth()
        lastWidth = width
        let tabsWidth = min(typeTabs.preferredWidth, ((width - 2 * Layout.padding) * Self.tabsShare).rounded(.down))
        let open = advancedOpen
        laidOutAdvancedOpen = open

        let frames: Layout.Frames
        if form.canLayOut {
            let rows = form.rows.filter(isVisible).map(\.spec)
            frames = Layout.frames(type: form.type, rows: rows, width: width, advancedOpen: open, tabsWidth: tabsWidth)
        } else {
            frames = fallbackFrames(for: form, width: width, tabsWidth: tabsWidth)
        }
        lastFrames = frames

        // The card: its width is the panel's; the controller's centring places it vertically.
        var containerFrame = container.frame
        containerFrame.size = NSSize(width: width, height: frames.height)
        if let documentWidth = container.superview?.bounds.width, documentWidth > 0 {
            containerFrame.origin.x = ((documentWidth - width) / 2).rounded(.down)
        }
        if container.frame != containerFrame {
            // The controller may have just started an animated resize of the container towards its XIB height; a
            // zero-duration animation of the same property replaces it, so it ends at this frame.
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                context.allowsImplicitAnimation = false
                container.animator().frame = containerFrame
            }
            if container.frame != containerFrame { container.frame = containerFrame }
        }
        Self.place(card, container.bounds)
        card.autoresizingMask = [.width, .height]

        layOutHeader(frames)

        // The tab view holds the rows: from under the header to above the action row.
        let tabTop = frames.header.minY - Layout.headerGap / 2
        let tabBottom = frames.actionRow.maxY + Layout.actionGap / 2
        Self.place(tabView, NSRect(x: 0, y: tabBottom, width: width, height: max(0, tabTop - tabBottom)))
        if let itemView = tabView.selectedTabViewItem?.view, itemView.frame != tabView.contentRect {
            itemView.frame = tabView.contentRect
        }

        if form.canLayOut {
            layOutRows(of: form, frames: frames, open: open)
        } else {
            layOutXIBForm(form)
        }
        for (section, title) in sectionTitles {
            if let rect = frames.sectionTitles[section], form.canLayOut {
                let height = Self.textHeight(title)
                Self.place(title, NSRect(x: rect.minX, y: Self.centred(height: height, in: rect), width: rect.width, height: height))
                if title.isHidden { title.isHidden = false }
            } else if !title.isHidden {
                title.isHidden = true
            }
        }
        Self.place(disclosure, frames.disclosure)
        disclosure.isHidden = !form.canLayOut
        disclosure.isOpen = open
        disclosure.isLocked = advancedHasNonDefault
        updateActionButtons()
        updateFocus()

        if let onLayout {
            onLayout()
        } else {
            // The controller centres the card in its scroll view (and sizes the document view).
            let recentre = NSSelectorFromString("scrollViewFrameChanged:")
            if controller.responds(to: recentre) { controller.perform(recentre, with: nil) }
        }
        chainKeyViews()
    }

    private func layOutHeader(_ frames: Layout.Frames) {
        let header = frames.header
        let nameHeight = Self.textHeight(nameLabel)
        let subtitleHeight = Self.textHeight(subtitleLabel)
        // Room on the left for the editing outline (6pt outside the text) clear of the dot.
        let textX = header.minX + Self.dotSize + 12
        let textWidth = max(0, header.maxX - 12 - textX)
        // Name on top, the subtitle on the line below it: 19 + 15pt, so the pair reaches 2pt into the header gap
        // rather than overlapping.
        let nameY = header.maxY - nameHeight
        /// The subtitle's top: under the name, or under the name's outline while it is edited (the header grows).
        var subtitleTop = nameY
        let current = currentForm
        for form in forms {
            guard let nameField = form.nameField else { continue }
            let hidden = form !== current
            if nameField.isHidden != hidden { nameField.isHidden = hidden }
        }
        if let nameField = current?.nameField {
            nameLabel.isHidden = true
            // Sized to its text (or the placeholder), capped before the pencil and the tabs; the cap while editing.
            let editing = nameField.currentEditor() != nil
            let cap = max(0, textWidth - Self.pencilSize - 6)
            let text = nameField.stringValue.isEmpty ? Self.namePlaceholder : nameField.stringValue
            let natural = ceil(NSAttributedString(string: text, attributes: [.font: Self.nameFont]).size().width) + 6
            let width = editing ? cap : min(natural, cap)
            let fieldHeight = Self.textHeight(nameField)
            let fieldRect = NSRect(x: textX, y: header.maxY - fieldHeight, width: width, height: fieldHeight)
            Self.place(nameField, fieldRect)
            if let outline = fieldFrames[ObjectIdentifier(nameField)] {
                let outlineRect = NSRect(x: fieldRect.minX - Self.fieldInset, y: Self.centred(height: Self.fieldHeight, in: fieldRect),
                                         width: fieldRect.width + 2 * Self.fieldInset, height: Self.fieldHeight)
                Self.place(outline, outlineRect)
                if editing { subtitleTop = min(subtitleTop, outlineRect.minY - 2) }
            }
            Self.place(pencilButton, NSRect(x: fieldRect.maxX + 4, y: Self.centred(height: Self.pencilSize, in: fieldRect),
                                            width: Self.pencilSize, height: Self.pencilSize))
            if pencilButton.isHidden != editing { pencilButton.isHidden = editing }
        } else {
            nameLabel.isHidden = false
            pencilButton.isHidden = true
            Self.place(nameLabel, NSRect(x: textX, y: nameY, width: textWidth, height: nameHeight))
        }
        Self.place(subtitleLabel, NSRect(x: textX, y: subtitleTop - subtitleHeight, width: textWidth, height: subtitleHeight))
        Self.place(dot, NSRect(x: header.minX, y: (nameY + nameHeight / 2 - Self.dotSize / 2).rounded(),
                               width: Self.dotSize, height: Self.dotSize))
        Self.place(typeTabs, frames.tabs)
    }

    /// Header, tabs and action row around a type that keeps its XIB form (with its SSL details while shown).
    private func fallbackFrames(for form: SAClaudePanelForm, width: CGFloat, tabsWidth: CGFloat) -> Layout.Frames {
        var formHeight = form.formContainer.frame.height
        if let ssl = form.sslContainer, !ssl.isHidden { formHeight += ssl.frame.height }
        let height = Layout.padding + Layout.headerHeight + Layout.headerGap + formHeight + Layout.actionGap
            + Layout.actionRowHeight + Layout.padding
        let contentWidth = width - 2 * Layout.padding
        let headerY = height - Layout.padding - Layout.headerHeight
        return Layout.Frames(
            header: NSRect(x: Layout.padding, y: headerY, width: max(0, contentWidth - tabsWidth), height: Layout.headerHeight),
            tabs: NSRect(x: width - Layout.padding - tabsWidth, y: headerY, width: tabsWidth, height: Layout.headerHeight),
            sectionTitles: [:], rows: [],
            disclosure: .zero,
            actionRow: NSRect(x: Layout.padding, y: Layout.padding, width: contentWidth, height: Layout.actionRowHeight),
            height: height)
    }

    /// The XIB form, centred under the header with its SSL details below it.
    private func layOutXIBForm(_ form: SAClaudePanelForm) {
        let bounds = form.itemView.bounds
        let formFrame = form.formContainer.frame
        let x = ((bounds.width - formFrame.width) / 2).rounded(.down)
        let top = bounds.maxY
        let placed = NSRect(x: x, y: top - formFrame.height, width: formFrame.width, height: formFrame.height)
        if form.formContainer.frame != placed { form.formContainer.frame = placed }
        if let ssl = form.sslContainer {
            let sslFrame = NSRect(x: x, y: placed.minY - ssl.frame.height, width: ssl.frame.width, height: ssl.frame.height)
            if ssl.frame != sslFrame { ssl.frame = sslFrame }
        }
        // Outlines follow their fields where the XIB put them.
        for field in form.fields {
            if let frameView = fieldFrames[ObjectIdentifier(field)], form.reveal.values.allSatisfy({ $0.twin !== field }) {
                Self.place(frameView, field.frame)
            }
        }
    }

    private func layOutRows(of form: SAClaudePanelForm, frames: Layout.Frames, open: Bool) {
        guard let container else { return }
        Self.place(form.formContainer, form.itemView.bounds)
        form.formContainer.autoresizingMask = [.width, .height]

        let rowFrames = Dictionary(frames.rows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        // The SSL details container covers just its rows, so it never sits over (and swallows clicks for) the others.
        if let ssl = form.sslContainer {
            let sslRects = form.rows.filter { $0.condition == .ssl }.compactMap { rowFrames[$0.id] }.map { frame in
                frame.label.map { $0.union(frame.control) } ?? frame.control
            }
            let union = sslRects.dropFirst().reduce(sslRects.first ?? .zero) { $0.union($1) }
            let rect = union.isEmpty ? .zero : form.itemView.convert(union.insetBy(dx: -4, dy: -4), from: container)
            Self.place(ssl, rect)
        }

        for row in form.rows {
            // The SSH password and key share one slot; the hidden one keeps the shown one's frame.
            var frame = rowFrames[row.id]
            if frame == nil, row.condition == .sshPassword { frame = rowFrames["sshKeyLocation"] }
            if frame == nil, row.condition == .sshKey { frame = rowFrames["sshPassword"] }
            if row.section == .advanced {
                for view in views(of: row, in: form) where view.isHidden == open {
                    view.isHidden = !open
                }
            }
            if let secure = row.control as? NSSecureTextField, let pair = form.reveal[ObjectIdentifier(secure)] {
                let shown = rowFrames[row.id] != nil
                if pair.eye.isHidden == shown { pair.eye.isHidden = !shown }
                if row.condition == .sshPassword {
                    // A revealed plain twin must not sit over the SSH key field; when the password returns, the
                    // eye's state decides which of the two shows (the binding has just un-hidden the secure one).
                    let revealed = pair.eye.state == .on
                    let twinHidden = !(shown && revealed)
                    if pair.twin.isHidden != twinHidden { pair.twin.isHidden = twinHidden }
                    if shown, secure.isHidden != revealed { secure.isHidden = revealed }
                }
            }
            guard let frame, let superview = row.control.superview else { continue }
            if let label = row.label {
                if let labelRect = frame.label {
                    let rect = superview.convert(labelRect, from: container)
                    let height = Self.textHeight(label)
                    Self.place(label, NSRect(x: rect.minX, y: Self.centred(height: height, in: rect), width: rect.width, height: height))
                }
            }
            place(row, in: superview.convert(frame.control, from: container), form: form)
        }
    }

    /// Every view a row shows (hidden together while Advanced is closed).
    private func views(of row: SAClaudePanelRow, in form: SAClaudePanelForm) -> [NSView] {
        var views: [NSView] = [row.control]
        views += [row.label, row.secondary, row.accessory, row.spinner].compactMap { $0 }
        if let field = row.control as? NSTextField, let frameView = fieldFrames[ObjectIdentifier(field)] { views.append(frameView) }
        return views
    }

    /// Puts a row's control (and its picker, eye button, twin, outline) into `rect`, the row's value column.
    private func place(_ row: SAClaudePanelRow, in rect: NSRect, form: SAClaudePanelForm) {
        var valueRect = rect
        if let accessory = row.accessory {
            switch row.kind {
            case .comboWithButton:
                var right = rect.maxX
                if let spinner = row.spinner {
                    let size: CGFloat = 16
                    Self.place(spinner, NSRect(x: right - size, y: Self.centred(height: size, in: rect), width: size, height: size))
                    right -= size + Self.accessoryGap
                }
                let width = Self.ghostWidth(accessory)
                Self.place(accessory, NSRect(x: right - width, y: Self.centred(height: Self.fieldHeight, in: rect),
                                             width: width, height: Self.fieldHeight))
                valueRect.size.width = max(0, right - width - Self.accessoryGap - rect.minX)
            default:
                Self.place(accessory, NSRect(x: rect.maxX - Self.pickerSize, y: Self.centred(height: Self.pickerSize, in: rect),
                                             width: Self.pickerSize, height: Self.pickerSize))
                valueRect.size.width = max(0, rect.width - Self.pickerSize - Self.accessoryGap)
            }
        }

        switch row.kind {
        case .checkbox:
            Self.place(row.control, NSRect(x: rect.minX, y: Self.centred(height: Self.checkboxHeight, in: rect),
                                           width: rect.width, height: Self.checkboxHeight))
        case .checkboxPair:
            guard let checkbox = row.control as? NSControl else { return }
            let width = min(Self.fittingWidth(checkbox), rect.width)
            let y = Self.centred(height: Self.checkboxHeight, in: rect)
            Self.place(checkbox, NSRect(x: rect.minX, y: y, width: width, height: Self.checkboxHeight))
            if let secondary = row.secondary {
                let x = rect.minX + width + 16
                Self.place(secondary, NSRect(x: x, y: y, width: max(0, min(Self.fittingWidth(secondary), rect.maxX - x)),
                                             height: Self.checkboxHeight))
            }
        case .colour:
            let width = max(Self.colourSelectorMinimumWidth, min(rect.width, Self.colourSelectorMaximumWidth))
            Self.place(row.control, NSRect(x: rect.minX, y: Self.centred(height: Self.colourSelectorHeight, in: rect),
                                           width: width, height: Self.colourSelectorHeight))
        case .note:
            Self.place(row.control, rect)
        case .button:
            guard let button = row.control as? NSButton else { return }
            Self.place(button, NSRect(x: rect.minX, y: Self.centred(height: Self.fieldHeight, in: rect),
                                      width: min(rect.width, Self.ghostWidth(button)), height: Self.fieldHeight))
        case .field, .fileRow, .comboWithButton:
            placeField(row.control, in: valueRect, form: form)
        }
    }

    /// A field-look control in `rect`: pop-ups as pills; text fields and combo boxes inside their outline.
    private func placeField(_ control: NSView, in rect: NSRect, form: SAClaudePanelForm) {
        let outline = NSRect(x: rect.minX, y: Self.centred(height: Self.fieldHeight, in: rect), width: rect.width, height: Self.fieldHeight)
        if control is NSPopUpButton {
            Self.place(control, outline)
            return
        }
        guard let field = control as? NSTextField else {
            Self.place(control, outline)
            return
        }
        if let frameView = fieldFrames[ObjectIdentifier(field)] { Self.place(frameView, outline) }
        if field is NSComboBox {
            Self.place(field, outline.insetBy(dx: 2, dy: 0))
            return
        }
        var text = outline.insetBy(dx: Self.fieldInset, dy: 0)
        if let pair = form.reveal[ObjectIdentifier(field)] {
            text.size.width = max(0, text.width - Self.eyeSize - 2)
            Self.place(pair.eye, NSRect(x: outline.maxX - 4 - Self.eyeSize, y: Self.centred(height: Self.eyeSize, in: outline),
                                        width: Self.eyeSize, height: Self.eyeSize))
        }
        let height = Self.textHeight(field)
        let fieldRect = NSRect(x: text.minX, y: Self.centred(height: height, in: outline), width: text.width, height: height)
        Self.place(field, fieldRect)
        if let pair = form.reveal[ObjectIdentifier(field)] { Self.place(pair.twin, fieldRect) }
    }

    /// Help (or the spinner and progress text while connecting) on the left; Add / Save / Test and Connect on the right.
    private func layOutActionRow() {
        guard let frames = lastFrames else { return }
        let row = frames.actionRow
        var right = row.maxX
        // The primary on the right (Connect, or Save and connect for a favourite with edits; one is hidden).
        let primaryFont = NSFont.systemFont(ofSize: 12, weight: .medium)
        func titleWidth(_ title: String) -> CGFloat {
            ceil(NSAttributedString(string: title, attributes: [.font: primaryFont]).size().width)
        }
        var primaryWidth: CGFloat = 0
        if let connectButton, !connectButton.isHidden {
            let fit = [connectButton.title, NSLocalizedString("Cancel", comment: "cancel button")].map(titleWidth).max() ?? 0
            primaryWidth = max(Self.connectMinimumWidth, fit + 2 * SAClaudeFilterChrome.pillPadding + 8)
            Self.place(connectButton, NSRect(x: right - primaryWidth, y: Self.centred(height: Self.connectHeight, in: row),
                                             width: primaryWidth, height: Self.connectHeight))
        }
        if !saveAndConnectButton.isHidden {
            primaryWidth = max(Self.connectMinimumWidth, titleWidth(saveAndConnectButton.title) + 2 * SAClaudeFilterChrome.pillPadding + 8)
            Self.place(saveAndConnectButton, NSRect(x: right - primaryWidth, y: Self.centred(height: Self.connectHeight, in: row),
                                                    width: primaryWidth, height: Self.connectHeight))
        }
        if primaryWidth > 0 { right -= primaryWidth + Self.actionGap }
        // Secondaries leftwards from the primary: Connect without saving, Save changes, Add to favourites, Test.
        let secondaries = [connectWithoutSavingButton, editButton("saveFavorite:"), editButton("addFavoriteUsingCurrentDetails:"),
                           editButton("initiateConnection:")].compactMap { $0 }
        for button in secondaries {
            let width = titleWidth(button.title) + 2 * Self.secondaryPadding
            Self.place(button, NSRect(x: right - width, y: Self.centred(height: Self.ghostHeight, in: row), width: width, height: Self.ghostHeight))
            if !button.isHidden { right -= width + Self.actionGap }
        }
        if let helpButton {
            Self.place(helpButton, NSRect(x: row.minX, y: Self.centred(height: Self.fieldHeight, in: row),
                                          width: Self.fieldHeight, height: Self.fieldHeight))
        }
        var textX = row.minX
        if let progressIndicator {
            let size: CGFloat = 16
            Self.place(progressIndicator, NSRect(x: row.minX + 4, y: Self.centred(height: size, in: row), width: size, height: size))
            textX = row.minX + 4 + size + 6
        }
        if let progressText {
            let height = Self.textHeight(progressText)
            Self.place(progressText, NSRect(x: textX, y: Self.centred(height: height, in: row), width: max(0, right - textX), height: height))
        }
    }

    // MARK: - Key view loop

    /// (Page search → cards →) name → tabs → left column → right column → Advanced (when open) → the action row
    /// (Test, Add to favourites, Save changes, Connect without saving, then the primary), for a laid-out type; the
    /// last leads back to the first. A type that keeps its XIB form only gets the page's controls linked to its
    /// first control (its own XIB chain carries on from there).
    func chainKeyViews() {
        guard let controller, let container, let frames = lastFrames,
              let form = forms.first(where: { $0.type.rawValue == controller.type }) else { return }
        guard form.canLayOut else {
            let first = form.rows.first(where: { $0.section == .header })?.control
                ?? form.formContainer.subviews.first { $0 is NSControl && $0.canBecomeKeyView }
            Self.link(leadingKeyViews() + [first].compactMap { $0 }, closing: false)
            return
        }
        let rowFrames = Dictionary(frames.rows.map { ($0.id, $0.control) }, uniquingKeysWith: { first, _ in first })
        let middle = container.bounds.midX
        func controls(of row: SAClaudePanelRow) -> [NSView] {
            var views: [NSView] = [row.control]
            if let pair = (row.control as? NSSecureTextField).flatMap({ form.reveal[ObjectIdentifier($0)] }) { views.append(pair.twin) }
            views += [row.secondary, row.accessory].compactMap { $0 }
            return views.filter { $0 is NSControl }
        }
        let shown = form.rows.filter { rowFrames[$0.id] != nil }
        let columns = shown.filter { $0.section != .advanced }.sorted { a, b in
            let ra = rowFrames[a.id]!, rb = rowFrames[b.id]!
            let leftA = ra.minX < middle, leftB = rb.minX < middle
            if leftA != leftB { return leftA }
            return ra.maxY > rb.maxY
        }
        var chain: [NSView] = leadingKeyViews() + [form.nameField, typeTabs].compactMap { $0 }
        chain += columns.flatMap(controls)
        chain.append(disclosure)
        chain += shown.filter { $0.section == .advanced }.flatMap(controls)
        chain += [editButton("initiateConnection:"), editButton("addFavoriteUsingCurrentDetails:"), editButton("saveFavorite:")].compactMap { $0 }
        chain += [connectWithoutSavingButton, saveAndConnectButton]
        if let connectButton { chain.append(connectButton) }
        // The loop closes on the first (the outline's own next key view stays the controller's).
        Self.link(chain, closing: true)
    }

    /// Links each view to the next (and, when `closing`, the last to the first). A link is set again when the next
    /// view's `previousKeyView` points elsewhere, as after the controller re-pointed a field's previous view at the
    /// hidden outline (`updateFavoriteNextKeyView`), so Shift-Tab walks the same chain back.
    private static func link(_ chain: [NSView], closing: Bool) {
        var pairs = Array(zip(chain, chain.dropFirst()))
        if closing, let first = chain.first, let last = chain.last, last !== first { pairs.append((last, first)) }
        for (view, next) in pairs where view.nextKeyView !== next || next.previousKeyView !== view {
            // Re-setting the same next view may not touch its previous view: clear first.
            if view.nextKeyView === next { view.nextKeyView = nil }
            view.nextKeyView = next
        }
    }
}

/// A connection field whose placeholder never reads as a value: AppKit drew "optional" (Database) and "3306" (Port), the
/// bindings' placeholders, as bright as values. The cell draws its placeholder through `SAClaudeFieldPlaceholder`, as the
/// sheets' fields do. Installed with `object_setClass` over a plain NSTextFieldCell (no stored properties).
private final class SAClaudeMutedPlaceholderCell: NSTextFieldCell {
    /// Swaps `field`'s cell for this one when it is a plain text field cell that may change class.
    static func install(on field: NSTextField) {
        guard let cell = field.cell else { return }
        if !(cell is SAClaudeMutedPlaceholderCell) {
            guard Swift.type(of: cell) == NSTextFieldCell.self, SAClaudeClassSwap.mayChangeClass(of: cell) else { return }
            object_setClass(cell, SAClaudeMutedPlaceholderCell.self)
        }
        field.needsDisplay = true
    }

    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        if !SAClaudeFieldPlaceholder.draw(self, withFrame: cellFrame, in: controlView) {
            super.drawInterior(withFrame: cellFrame, in: controlView)
        }
    }
}

/// The header name field's cell: always shows "New favourite" while the name is empty. The XIB's `name` binding sets
/// its null placeholder ("optional") on every update; this cell ignores placeholders set on it. No stored properties
/// (the class is swapped onto the XIB's cell); the placeholder is shared, recoloured on each theme refresh.
private final class SAClaudeNamePlaceholderCell: NSTextFieldCell {
    static var placeholder = NSAttributedString()
    /// Outside callers (the binding) can't change the placeholder…
    override var placeholderString: String? {
        get { nil }
        set { }
    }
    override var placeholderAttributedString: NSAttributedString? {
        get { Self.placeholder }
        set { }
    }
    /// …but AppKit draws from the cell's stored placeholder (still the XIB's "optional"), so store ours there.
    func applyPlaceholder() {
        super.placeholderString = nil
        super.placeholderAttributedString = Self.placeholder
    }
}
