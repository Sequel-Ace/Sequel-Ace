//
//  SAClaudeFormSheetStyler.swift
//  Sequel Ace
//
//  The shared Claude form of the table and database sheets (spec 2026-10-15-claude-table-sheets-design.md).
//  `SAClaudeFormSheetStyler.claim(_:)` is offered every window the generic sheet skin styles; it recognises a sheet
//  by identity against its owner's outlets — the owner reached from the parent window's `SPWindowController` and its
//  sub-controllers by KVC, no ObjC hooks — and attaches an `SAClaudeFormSheet`, which lays the sheet's own XIB views
//  out from a recipe (`SAClaudeFormRecipes.swift`) with `SAClaudeFormLayout`: title and context line, right-aligned
//  labels beside the controls, sections, full-width blocks and the footer. Only decorative views are added (title,
//  context, labels the XIB lacks, section titles, block surfaces). Re-applied each time the sheet begins or becomes
//  key, on resize and when the theme changes; idempotent. A recipe that can't find a control leaves the sheet in the
//  generic skin, untouched. The header, the apply coalescer, the observers and the surface insertion are shared with
//  the field editor's styler. App target only.
//

import AppKit

// MARK: - Claiming

enum SAClaudeFormSheetStyler {

    /// Set on a window that is no form sheet (a sheet no owner recognises) or whose recipe is incomplete: it is not
    /// looked at again.
    private static var declinedKey: UInt8 = 0

    /// Called by `SAClaudeSheetStyler.consider` after the generic skin, each time a window is considered.
    static func claim(_ window: NSWindow) {
        if let editor = SAClaudeFieldEditorStyler.styler(for: window) {
            editor.apply()
            return
        }
        if let sheet = SAClaudeFormSheet.sheet(for: window) {
            sheet.apply()
            return
        }
        guard objc_getAssociatedObject(window, &declinedKey) == nil else { return }
        guard let match = SAClaudeFormOwners.match(window) else {
            // A sheet's owner doesn't change: remember the miss so its view tree isn't walked again at every
            // become-key. A window that isn't (yet) a sheet costs nothing to check and stays a candidate.
            if window.sheetParent != nil { decline(window) }
            return
        }
        if attach(match) { return }
        decline(window)
        #if DEBUG
        NSLog("SAClaudeFormSheetStyler: no complete recipe for the %@ sheet; it keeps the generic look", match.kind.rawValue)
        #endif
    }

    private static func decline(_ window: NSWindow) {
        objc_setAssociatedObject(window, &declinedKey, true, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    /// Attaches the form for `match`; false when its recipe is missing or incomplete (nothing was changed then).
    private static func attach(_ match: SAClaudeFormMatch) -> Bool {
        if match.kind == .fieldEditor { return SAClaudeFieldEditorStyler.attach(match) != nil }
        guard let recipe = SAClaudeFormRecipes.recipe(for: match),
              let sheet = SAClaudeFormSheet.attach(window: match.window, recipe: recipe) else { return false }
        sheet.apply()
        return true
    }
}

// MARK: - Owners

enum SAClaudeFormKind: String {
    case newDatabase, alterDatabase, duplicateDatabase, renameDatabase, password, createSyntax
    case newTable, duplicateTable, addKey, resetAutoIncrement, newIndex, newRelation, trigger
    case goToDatabase, fieldEditor, bitEditor
}

struct SAClaudeFormMatch {
    let kind: SAClaudeFormKind
    let window: NSWindow
    /// The object whose outlets describe the sheet: the document, a sub-controller or the window's controller.
    let owner: NSObject
    /// The connection's document, for the context line (nil when it can't be found).
    let document: SPDatabaseDocument?
}

enum SAClaudeFormOwners {

    static func className(of object: AnyObject) -> String {
        SAClaudeSheetTargeting.unqualified(NSStringFromClass(SAClaudeSheetStyler.visibleClass(of: object)))
    }

    static func document(of window: NSWindow) -> SPDatabaseDocument? {
        (window.windowController as? SPWindowController)?.databaseDocument
    }

    static func match(_ window: NSWindow) -> SAClaudeFormMatch? {
        // Go to Database is an app-modal window, not a sheet.
        if let controller = window.windowController, className(of: controller) == "SPGotoDatabaseController" {
            return SAClaudeFormMatch(kind: .goToDatabase, window: window, owner: controller, document: document(owningGoTo: controller))
        }
        guard let parent = window.sheetParent else { return nil }
        let doc = document(of: parent)

        if let editor = fieldEditorController(of: window) {
            if (SAClaudeFormRecipes.outlet(editor, "editSheet") as NSWindow?) === window {
                return SAClaudeFormMatch(kind: .fieldEditor, window: window, owner: editor, document: doc)
            }
            if (SAClaudeFormRecipes.outlet(editor, "bitSheet") as NSWindow?) === window {
                return SAClaudeFormMatch(kind: .bitEditor, window: window, owner: editor, document: doc)
            }
            return nil
        }
        guard let doc else { return nil }

        func owned(_ owner: NSObject?, _ sheets: [(String, SAClaudeFormKind)]) -> SAClaudeFormMatch? {
            guard let owner else { return nil }
            for (key, kind) in sheets where (SAClaudeFormRecipes.outlet(owner, key) as NSWindow?) === window {
                return SAClaudeFormMatch(kind: kind, window: window, owner: owner, document: doc)
            }
            return nil
        }
        if let m = owned(doc, [("databaseSheet", .newDatabase), ("databaseAlterSheet", .alterDatabase), ("databaseCopySheet", .duplicateDatabase),
                               ("databaseRenameSheet", .renameDatabase), ("inputTextWindow", .password),
                               ("createTableSyntaxWindow", .createSyntax)]) { return m }
        if let m = owned(SAClaudeFormRecipes.outlet(doc, "tablesListInstance"), [("tableSheet", .newTable), ("copyTableSheet", .duplicateTable)]) { return m }
        let structure: NSObject? = SAClaudeFormRecipes.outlet(doc, "tableSourceInstance")
        if let m = owned(structure, [("keySheet", .addKey), ("resetAutoIncrementSheet", .resetAutoIncrement)]) { return m }
        if let indexes: NSWindowController = SAClaudeFormRecipes.outlet(structure, "indexesController"), indexes.window === window {
            return SAClaudeFormMatch(kind: .newIndex, window: window, owner: indexes, document: doc)
        }
        if let m = owned(SAClaudeFormRecipes.outlet(doc, "tableRelationsInstance"), [("addRelationPanel", .newRelation)]) { return m }
        if let m = owned(SAClaudeFormRecipes.outlet(doc, "tableTriggersInstance"), [("addTriggerPanel", .trigger)]) { return m }
        return nil
    }

    /// The open document whose Go to Database controller this is. The dialog is app-modal and has no parent window,
    /// but the document that opened it stays the main window: only the main window's (else the frontmost connection
    /// window's) controller is asked — it shows a connection, so its document exists — never every window
    /// controller's lazily created `databaseDocument`.
    /// The controller is verified by identity; nil when none matches.
    static func document(owningGoTo controller: NSObject) -> SPDatabaseDocument? {
        var candidates: [NSWindow] = []
        if let main = NSApp.mainWindow { candidates.append(main) }
        candidates += NSApp.windows.filter { $0.isMainWindow && !candidates.contains($0) }
        // Should the dialog itself be the main window: the frontmost connection window.
        if let front = NSApp.orderedWindows.first(where: { $0.isVisible && $0.windowController is SPWindowController }), !candidates.contains(front) {
            candidates.append(front)
        }
        for window in candidates {
            guard let doc = document(of: window) else { continue }
            if (SAClaudeFormRecipes.outlet(doc, "gotoDatabaseController") as NSObject?) === controller { return doc }
        }
        return nil
    }

    /// The field editor controller of a sheet: its window controller (the edit sheet), or the target of one of its
    /// controls (the BIT sheet has no window controller).
    private static func fieldEditorController(of window: NSWindow) -> NSObject? {
        if let controller = window.windowController, className(of: controller) == "SPFieldEditorController" { return controller }
        guard let contentView = window.contentView else { return nil }
        return target(ofClass: "SPFieldEditorController", in: contentView)
    }

    private static func target(ofClass name: String, in view: NSView) -> NSObject? {
        if let control = view as? NSControl, let target = control.target as? NSObject, className(of: target) == name { return target }
        for subview in view.subviews {
            if let found = target(ofClass: name, in: subview) { return found }
        }
        return nil
    }
}

// MARK: - Content

/// A row's label: the XIB's own (restyled), or one the form adds where the XIB has none.
enum SAClaudeFormLabel {
    case existing(NSTextField)
    case text(String)
}

enum SAClaudeFormItem {
    case row(SAClaudeFormLabel, NSView, SAClaudeFormLayout.ControlKind)
    /// In the control column, no label (checkbox rows).
    case control(NSView, SAClaudeFormLayout.ControlKind)
    /// Spanning the label and control columns.
    case wide(NSView, SAClaudeFormLayout.ControlKind)
    /// Several views placed by the recipe in the item's rect (`controlX`: the control column's left edge).
    case custom(views: [NSView], height: CGFloat, wide: Bool, place: (_ rect: NSRect, _ controlX: CGFloat) -> Void)
    case section(String)
    /// A section-like row: the disclosure triangle and its title button (the index sheet's Advanced).
    case disclosure(triangle: NSButton, label: NSButton)
    /// A full-width block around a scroll view; `strip` buttons sit in a 24pt strip at its bottom, drawn as glyphs.
    case block(NSScrollView, minHeight: CGFloat, grows: Bool, strip: [(NSButton, SAClaudeGlyph)])
}

/// The form as a sheet is now; built by its recipe at every apply.
struct SAClaudeFormContent {
    var title: String
    var context: String?
    var items: [SAClaudeFormItem]
    /// Extra actions, spinners, checkboxes at the footer's left, left to right.
    var footerLeading: [NSView] = []
    /// Left to right; the last is the primary (Return) button.
    var footerTrailing: [NSButton]
    /// XIB views the form replaces (prompt labels, boxes, separators): hidden at every apply.
    var hidden: [NSView] = []
    /// Views kept in the hierarchy but given an empty frame (the index sheet's emptied Advanced view).
    var collapsed: [NSView] = []
    /// Off-screen key-equivalent buttons: kept beyond the sheet's right edge.
    var offscreen: [NSView] = []
    /// The narrowest control column the form needs (the BIT sheet's operator row: 276pt).
    var minimumControlWidth: CGFloat = SAClaudeFormLayout.minimumControlWidth

    /// Every XIB view the form places (labels it adopts included).
    var allViews: [NSView] {
        var views: [NSView] = []
        for item in items {
            switch item {
            case .row(let label, let control, _):
                if case .existing(let existing) = label { views.append(existing) }
                views.append(control)
            case .control(let view, _), .wide(let view, _): views.append(view)
            case .custom(let custom, _, _, _): views += custom
            case .section: break
            case .disclosure(let triangle, let label): views += [triangle, label]
            case .block(let scrollView, _, _, let strip): views.append(scrollView); views += strip.map(\.0)
            }
        }
        return views + footerLeading + footerTrailing
    }

    /// Every XIB view the form names: placed, hidden, collapsed or kept off-screen.
    var namedViews: [NSView] { allViews + hidden + collapsed + offscreen }
}

protocol SAClaudeFormRecipe: AnyObject {
    /// Re-parents views out of the boxes the form replaces (once, before the first layout). Re-parenting only: it
    /// runs after every view the recipe names was found in the sheet; styling belongs in `didAttach`.
    func install(in contentView: NSView)
    /// Starts observing whatever re-lays the form out, and any one-time styling (once, after attaching).
    func didAttach(_ sheet: SAClaudeFormSheet)
    /// The form as the sheet is now.
    func content() -> SAClaudeFormContent
}

/// A recipe from closures: the sheet's views are found once (by the factory) and the content read at each apply.
final class SAClaudeSimpleFormRecipe: SAClaudeFormRecipe {
    private let installer: ((NSView) -> Void)?
    private let attacher: ((SAClaudeFormSheet) -> NSKeyValueObservation?)?
    private let builder: () -> SAClaudeFormContent
    private var observation: NSKeyValueObservation?

    init(install: ((NSView) -> Void)? = nil, didAttach: ((SAClaudeFormSheet) -> NSKeyValueObservation?)? = nil,
         content: @escaping () -> SAClaudeFormContent) {
        installer = install
        attacher = didAttach
        builder = content
    }

    deinit { observation?.invalidate() }

    func install(in contentView: NSView) { installer?(contentView) }
    func didAttach(_ sheet: SAClaudeFormSheet) { observation = attacher?(sheet) }
    func content() -> SAClaudeFormContent { builder() }
}

// MARK: - Shared pieces (the form engine and the field editor's styler)

/// One `apply` at a time, and one on the next main-queue turn however many ask for it.
final class SAClaudeFormApplyCoalescer {
    private(set) var isApplying = false
    private var pending = false
    private let apply: () -> Void

    /// `apply` is the owner's apply (capture the owner weakly).
    init(_ apply: @escaping () -> Void) { self.apply = apply }

    /// Runs `body` unless an apply is already running (a frame change it causes re-enters).
    func perform(_ body: () -> Void) {
        guard !isApplying else { return }
        isApplying = true
        defer { isApplying = false }
        body()
    }

    /// One apply on the next main-queue turn.
    func setNeedsApply() {
        guard !pending else { return }
        pending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.pending = false
            self.apply()
        }
    }
}

/// What re-lays a form out: its content view's frame changes (now), and theme or appearance changes (coalesced).
/// Stops observing when released.
final class SAClaudeFormObservers {
    private var frameObserver: NSObjectProtocol?
    private var appearanceObservation: NSKeyValueObservation?

    init(window: NSWindow, contentView: NSView, onFrameChange: @escaping () -> Void, onThemeChange: @escaping () -> Void) {
        contentView.postsFrameChangedNotifications = true
        frameObserver = NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: contentView, queue: nil) { _ in
            SAClaudeFormSheet.onMain(onFrameChange)
        }
        // Labels are recoloured by the skin (their tones are marked); glyphs, hover fills and surfaces by the apply.
        SAClaudeThemeWatcher.observe(self) { _ in onThemeChange() }
        appearanceObservation = window.observe(\.effectiveAppearance) { _, _ in
            SAClaudeFormSheet.onMain(onThemeChange)
        }
    }

    deinit {
        if let frameObserver { NotificationCenter.default.removeObserver(frameObserver) }
        appearanceObservation?.invalidate()
    }
}

/// A form's title (SF Pro 15 medium, theme text) and context line (SF Pro 12 muted, hidden when empty, its text as
/// tooltip): two labels created once in the content view.
final class SAClaudeFormHeader {
    let titleLabel = SAClaudeFormSheet.makeLabel(font: SAClaudeFormSheet.titleFont, identifier: SAClaudeFormSheet.identifierPrefix + "Title")
    let contextLabel = SAClaudeFormSheet.makeLabel(font: SAClaudeFormSheet.contextFont, identifier: SAClaudeFormSheet.identifierPrefix + "Context")

    init(in contentView: NSView) {
        for label in [titleLabel, contextLabel] { contentView.addSubview(label) }
    }

    /// Sets the texts and colours; true when the context line shows.
    @discardableResult
    func update(title: String, context: String?, colours: SAClaudeSheetColours) -> Bool {
        SAClaudeFormSheet.setText(titleLabel, title)
        let context = context?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        SAClaudeFormSheet.setText(contextLabel, context)
        if contextLabel.isHidden != context.isEmpty { contextLabel.isHidden = context.isEmpty }
        let tip: String? = context.isEmpty ? nil : context
        if contextLabel.toolTip != tip { contextLabel.toolTip = tip }
        SAClaudeFormSheet.tone(titleLabel, .text, colours)
        SAClaudeFormSheet.tone(contextLabel, .muted, colours)
        return !context.isEmpty
    }

    func place(title: NSRect, context: NSRect?) {
        SAClaudeFormSheet.place(titleLabel, title)
        if let context { SAClaudeFormSheet.place(contextLabel, context) }
    }
}

// MARK: - Engine

/// One claimed sheet: lays its views out from its recipe and keeps the decorative views. Retained by the window.
final class SAClaudeFormSheet: NSObject {

    private typealias Layout = SAClaudeFormLayout

    private static var associationKey: UInt8 = 0
    static let titleFont = NSFont.systemFont(ofSize: 15, weight: .medium)
    static let contextFont = NSFont.systemFont(ofSize: 12)
    static let labelFont = NSFont.systemFont(ofSize: 12)
    static let sectionFont = NSFont.systemFont(ofSize: 11, weight: .medium)
    /// Identifies the views the form adds.
    static let identifierPrefix = "SAClaudeForm"
    /// The generic skin's surface view (`SAClaudeWindowSkin`), which the form's surfaces sit just above.
    static let skinSurfaceIdentifier = "SAClaudeSheetSurface"
    private static let stripButtonSize: CGFloat = 20
    private static let stripButtonGap: CGFloat = 4
    private static let disclosureSize: CGFloat = 13
    private static let disclosureGap: CGFloat = 4

    /// An item resolved to the views it places.
    private enum Placed {
        case row(NSTextField, NSView, Layout.ControlKind)
        case control(NSView, Layout.ControlKind)
        case wide(NSView, Layout.ControlKind)
        case custom([NSView], (NSRect, CGFloat) -> Void)
        case section(NSTextField)
        case disclosure(NSButton, NSButton)
        case block(NSScrollView, SAClaudeFormSurfaceView, [NSButton])
    }

    /// The window retains this object (associated). Weak, not unowned: the frame observer can fire while the window is
    /// being torn down (this object is released after `-[NSWindow dealloc]`), and that must be a no-op, not a trap.
    private(set) weak var window: NSWindow?
    let contentView: NSView
    private let recipe: SAClaudeFormRecipe

    private let header: SAClaudeFormHeader
    /// Labels the form added, by "row:<text>" / "section:<text>".
    private var createdLabels: [String: NSTextField] = [:]
    /// Block surfaces, by their scroll view.
    private var surfaces: [ObjectIdentifier: SAClaudeFormSurfaceView] = [:]
    /// XIB labels already restyled, with the tooltip they came with.
    private var adoptedTooltips: [ObjectIdentifier: String?] = [:]

    private lazy var coalescer = SAClaudeFormApplyCoalescer { [weak self] in self?.apply() }
    private var observers: SAClaudeFormObservers?

    /// Set by `ownHeight()`: the form keeps the sheet's height itself.
    private var ownsHeight = false
    /// With `ownsHeight`: the height the user dragged in above the natural one; dropped at every begin.
    private var extraHeight: CGFloat = 0
    private var beginObserver: NSObjectProtocol?

    static func sheet(for window: NSWindow) -> SAClaudeFormSheet? {
        objc_getAssociatedObject(window, &associationKey) as? SAClaudeFormSheet
    }

    /// Installs `recipe` on `window` (once). Every view the recipe names must be in the sheet before anything is
    /// changed; nil (the sheet untouched) when one isn't.
    static func attach(window: NSWindow, recipe: SAClaudeFormRecipe) -> SAClaudeFormSheet? {
        if let existing = sheet(for: window) { return existing }
        guard let contentView = window.contentView, !contentView.isFlipped else { return nil }
        // Check first, change after: a view outside the sheet means the recipe was built for another XIB.
        let content = recipe.content()
        let placed = content.allViews
        guard !placed.isEmpty,
              content.namedViews.allSatisfy({ $0 !== contentView && $0.isDescendant(of: contentView) }) else { return nil }
        recipe.install(in: contentView)
        // Whatever the recipe left inside a box is lifted out too: every placed view is the content view's.
        SAClaudeFormFind.reparent(placed.filter { $0.superview !== contentView }, into: contentView)
        let sheet = SAClaudeFormSheet(window: window, contentView: contentView, recipe: recipe)
        objc_setAssociatedObject(window, &associationKey, sheet, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        sheet.observers = SAClaudeFormObservers(window: window, contentView: contentView,
                                                onFrameChange: { [weak sheet] in sheet?.frameDidChange() },
                                                onThemeChange: { [weak sheet] in sheet?.setNeedsApply() })
        recipe.didAttach(sheet)
        return sheet
    }

    private init(window: NSWindow, contentView: NSView, recipe: SAClaudeFormRecipe) {
        self.window = window
        self.contentView = contentView
        self.recipe = recipe
        header = SAClaudeFormHeader(in: contentView)
        super.init()
    }

    deinit {
        if let beginObserver { NotificationCenter.default.removeObserver(beginObserver) }
    }

    static func onMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
    }

    /// One `apply` on the next main-queue turn, however many ask for it.
    func setNeedsApply() {
        coalescer.setNeedsApply()
    }

    /// For a sheet whose controller animates its own height (the index sheet's Advanced fold, and again at close):
    /// the form owns the height from now on — the natural height for the current content plus whatever the user
    /// drags in (live resize only) — and frame changes outside a live resize are applied once on the next turn, so
    /// the controller's animation runs to its end and the form re-fits after it instead of fighting each frame. The
    /// dragged-in height is dropped each time the sheet begins. Other sheets keep applying at every frame change.
    func ownHeight() {
        guard !ownsHeight else { return }
        ownsHeight = true
        beginObserver = NotificationCenter.default.addObserver(forName: NSWindow.willBeginSheetNotification, object: nil, queue: nil) { [weak self] note in
            guard let parent = note.object as? NSWindow else { return }
            SAClaudeFormSheet.onMain { self?.sheetMayBegin(on: parent) }
        }
    }

    /// A sheet begins on `parent`: if it is this one, back to its natural height. AppKit may attach the sheet only
    /// after posting (as `SAClaudeSheetStyler` notes), so this checks now and on the next turn.
    private func sheetMayBegin(on parent: NSWindow) {
        let check = { [weak self, weak parent] in
            guard let self, let parent, parent.attachedSheet === self.window else { return }
            self.extraHeight = 0
            self.apply()
        }
        check()
        DispatchQueue.main.async(execute: check)
    }

    /// The content view's frame changed: applied now (a live resize stays smooth) unless the form owns the height
    /// and the user isn't resizing — then once on the next turn, after whatever resized the sheet has finished.
    private func frameDidChange() {
        guard let window else { return }
        if ownsHeight && !window.inLiveResize { setNeedsApply() } else { apply() }
    }

    // MARK: Applying

    func apply() {
        guard window != nil, contentView.bounds.width > 0, contentView.bounds.height > 0 else { return }
        coalescer.perform { applyNow() }
    }

    private func applyNow() {
        guard let window else { return }
        let content = recipe.content()
        let colours = SAClaudeSheetColours.current()
        var used = Set(content.namedViews.map { ObjectIdentifier($0) })

        let hasContext = header.update(title: content.title, context: content.context, colours: colours)

        // Items.
        var placed: [Placed] = []
        var items: [Layout.Item] = []
        var shownLabels = Set<String>()
        var shownSurfaces = Set<ObjectIdentifier>()
        for item in content.items {
            switch item {
            case .row(let source, let control, let kind):
                let label: NSTextField
                switch source {
                case .existing(let existing):
                    label = adopt(existing)
                case .text(let text):
                    label = created("row:" + text, text: text, font: Self.labelFont, alignment: .right)
                    shownLabels.insert("row:" + text)
                }
                Self.tone(label, .muted, colours)
                used.insert(ObjectIdentifier(label))
                placed.append(.row(label, control, kind))
                items.append(.row(labelWidth: Self.textWidth(label), control: kind))
            case .control(let control, let kind):
                placed.append(.control(control, kind))
                items.append(.control(kind))
            case .wide(let view, let kind):
                placed.append(.wide(view, kind))
                items.append(.wide(kind))
            case .custom(let views, let height, let wide, let place):
                placed.append(.custom(views, place))
                items.append(wide ? .wide(.custom(height: height)) : .control(.custom(height: height)))
            case .section(let text):
                let label = created("section:" + text, text: text, font: Self.sectionFont, alignment: .left)
                shownLabels.insert("section:" + text)
                Self.tone(label, .muted, colours)
                placed.append(.section(label))
                items.append(.section)
            case .disclosure(let triangle, let label):
                Self.styleDisclosureLabel(label, colours)
                placed.append(.disclosure(triangle, label))
                items.append(.section)
            case .block(let scrollView, let minHeight, let grows, let strip):
                let surface = self.surface(for: scrollView)
                shownSurfaces.insert(ObjectIdentifier(scrollView))
                surface.stripHeight = strip.isEmpty ? 0 : Layout.blockStripHeight
                surface.stripAtTop = false
                surface.needsDisplay = true
                for (button, glyph) in strip { Self.styleGlyphButton(button, glyph, colours) }
                placed.append(.block(scrollView, surface, strip.map(\.0)))
                items.append(.block(minHeight: minHeight, grows: grows, stripHeight: strip.isEmpty ? 0 : Layout.blockStripHeight))
            }
        }
        for (key, label) in createdLabels {
            let hidden = !shownLabels.contains(key)
            if label.isHidden != hidden { label.isHidden = hidden }
        }
        for (key, surface) in surfaces {
            let hidden = !shownSurfaces.contains(key)
            if surface.isHidden != hidden { surface.isHidden = hidden }
        }

        // The views the form replaces.
        for view in content.hidden where !view.isHidden { view.isHidden = true }
        hideReplacedStatics(keeping: used)

        // Layout.
        let spec = Layout.Spec(items: items, hasContext: hasContext,
                               footerLeading: content.footerLeading.map(Self.footerItem),
                               footerTrailing: content.footerTrailing.map(Self.footerItem),
                               currentSize: contentView.bounds.size,
                               resizable: window.styleMask.contains(.resizable),
                               minimumControlWidth: content.minimumControlWidth)
        var f = Layout.frames(spec)
        if ownsHeight { f = ownedHeightFrames(spec, f, window: window) }
        resizeWindow(to: f, window: window)

        header.place(title: f.title, context: f.context)
        for (entry, frame) in zip(placed, f.items) { place(entry, frame, f) }
        for (view, frame) in zip(content.footerLeading, f.footerLeading) { Self.place(view, frame) }
        for (view, frame) in zip(content.footerTrailing, f.footerTrailing) { Self.place(view, frame) }
        for view in content.collapsed { Self.place(view, .zero) }
        for view in content.offscreen {
            Self.place(view, NSRect(origin: NSPoint(x: f.size.width + 40, y: view.frame.minY), size: view.frame.size))
        }
        chainKeyViews(placed, footer: content.footerLeading + content.footerTrailing)
    }

    // MARK: Views

    /// A XIB row label restyled once (colon dropped, SF Pro 12, right-aligned, truncating); shown.
    private func adopt(_ label: NSTextField) -> NSTextField {
        let key = ObjectIdentifier(label)
        if adoptedTooltips.index(forKey: key) == nil {
            adoptedTooltips[key] = .some(label.toolTip)
            label.stringValue = SAClaudeFormText.rowLabel(label.stringValue)
            label.font = Self.labelFont
            label.alignment = .right
            label.lineBreakMode = .byTruncatingTail
        }
        if label.isHidden { label.isHidden = false }
        return label
    }

    /// The label the form added for `key`, created once.
    private func created(_ key: String, text: String, font: NSFont, alignment: NSTextAlignment) -> NSTextField {
        if let label = createdLabels[key] { return label }
        let label = Self.makeLabel(font: font, identifier: Self.identifierPrefix + "Label")
        label.stringValue = text
        label.alignment = alignment
        contentView.addSubview(label)
        createdLabels[key] = label
        return label
    }

    /// The block surface behind `scrollView`, created once.
    private func surface(for scrollView: NSScrollView) -> SAClaudeFormSurfaceView {
        let key = ObjectIdentifier(scrollView)
        if let existing = surfaces[key] { return existing }
        let surface = SAClaudeFormSurfaceView()
        surface.identifier = NSUserInterfaceItemIdentifier(Self.identifierPrefix + "Surface")
        Self.insertSurface(surface, in: contentView)
        scrollView.borderType = .noBorder
        surfaces[key] = surface
        return surface
    }

    /// Adds `surface` to `contentView` just above the generic skin's surface, below every control.
    static func insertSurface(_ surface: NSView, in contentView: NSView) {
        let skinSurface = contentView.subviews.first { $0.identifier?.rawValue == skinSurfaceIdentifier }
        contentView.addSubview(surface, positioned: skinSurface == nil ? .below : .above, relativeTo: skinSurface)
    }

    /// Hides the static labels and separators directly in the content view that the form doesn't use (old prompts,
    /// "Source:" labels, separator lines). The form's own views are kept.
    private func hideReplacedStatics(keeping used: Set<ObjectIdentifier>) {
        for view in contentView.subviews where !used.contains(ObjectIdentifier(view)) {
            if view.identifier?.rawValue.hasPrefix(Self.identifierPrefix) == true { continue }
            let isStaticText = (view as? NSTextField).map { !$0.isEditable } ?? false
            let isSeparator = (view as? NSBox)?.boxType == .separator
            if isStaticText || isSeparator, !view.isHidden { view.isHidden = true }
        }
    }

    /// With `ownsHeight`: a live resize sets the dragged-in height; any other height (a controller's resize) gives
    /// way to the natural height plus the dragged-in one — so a fold changes the height by exactly its rows.
    private func ownedHeightFrames(_ spec: Layout.Spec, _ f: Layout.Frames, window: NSWindow) -> Layout.Frames {
        guard f.heightIsFlexible else { return f }
        let natural = f.minimumSize.height
        if window.inLiveResize {
            extraHeight = max(0, f.size.height - natural)
            return f
        }
        let height = natural + extraHeight
        guard f.size.height != height else { return f }
        var held = spec
        held.currentSize.height = height
        return Layout.frames(held)
    }

    private func resizeWindow(to f: Layout.Frames, window: NSWindow) {
        if window.styleMask.contains(.resizable) {
            if window.contentMinSize != f.minimumSize { window.contentMinSize = f.minimumSize }
            let maxHeight = f.heightIsFlexible ? CGFloat.greatestFiniteMagnitude : f.minimumSize.height
            let maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: maxHeight)
            if window.contentMaxSize != maxSize { window.contentMaxSize = maxSize }
        }
        guard contentView.bounds.size != f.size else { return }
        let old = window.frame
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: f.size))
        frame.origin = NSPoint(x: (old.midX - frame.width / 2).rounded(), y: old.maxY - frame.height)
        window.setFrame(frame, display: window.isVisible)
    }

    private func place(_ entry: Placed, _ frame: Layout.ItemFrame, _ f: Layout.Frames) {
        switch entry {
        case .row(let label, let control, let kind):
            if let labelFrame = frame.label { Self.place(label, labelFrame) }
            // A truncated label shows its full text as a tooltip; otherwise the XIB's own tooltip, if any.
            let truncated = f.truncatesLabels && Self.textWidth(label) > f.labelColumnWidth
            let original = adoptedTooltips[ObjectIdentifier(label)] ?? nil
            let tip = truncated ? label.stringValue : original
            if label.toolTip != tip { label.toolTip = tip }
            Self.placeControl(control, kind, frame.control)
        case .control(let control, let kind):
            Self.placeControl(control, kind, frame.control)
        case .wide(let view, let kind):
            Self.placeControl(view, kind, frame.control)
        case .custom(let views, let placeViews):
            for view in views where !view.autoresizingMask.isEmpty { view.autoresizingMask = [] }
            placeViews(frame.control, Layout.sideMargin + f.labelColumnWidth + Layout.labelGap)
        case .section(let label):
            Self.place(label, frame.control)
        case .disclosure(let triangle, let label):
            let r = frame.control
            Self.place(triangle, NSRect(x: r.minX, y: (r.midY - Self.disclosureSize / 2).rounded(.down),
                                        width: Self.disclosureSize, height: Self.disclosureSize))
            let x = r.minX + Self.disclosureSize + Self.disclosureGap
            Self.place(label, NSRect(x: x, y: r.minY, width: max(0, r.maxX - x), height: r.height))
        case .block(let scrollView, let surface, let strip):
            if let surfaceFrame = frame.surface { Self.place(surface, surfaceFrame) }
            Self.place(scrollView, frame.control)
            if let stripFrame = frame.strip {
                var x = stripFrame.minX + Self.stripButtonGap
                for button in strip {
                    Self.place(button, NSRect(x: x, y: (stripFrame.midY - Self.stripButtonSize / 2).rounded(.down),
                                              width: Self.stripButtonSize, height: Self.stripButtonSize))
                    x += Self.stripButtonSize + Self.stripButtonGap
                }
            }
        }
    }

    /// Visual order: the rows' controls, the blocks and their strips, the footer; closed into a loop.
    private func chainKeyViews(_ placed: [Placed], footer: [NSView]) {
        func takesFocus(_ view: NSView) -> Bool { (view as? NSTextField).map { $0.isEditable } ?? (view is NSControl) }
        var chain: [NSView] = []
        for entry in placed {
            switch entry {
            case .row(_, let control, _), .control(let control, _), .wide(let control, _): chain.append(control)
            case .custom(let views, _): chain += views.filter(takesFocus)
            case .disclosure(let triangle, _): chain.append(triangle)
            case .block(let scrollView, _, let strip): chain.append(scrollView.documentView ?? scrollView); chain += strip
            case .section: break
            }
        }
        chain += footer.filter { $0 is NSButton }
        chain = chain.filter { !$0.isHidden }
        guard chain.count > 1 else { return }
        var pairs = Array(zip(chain, chain.dropFirst()))
        pairs.append((chain[chain.count - 1], chain[0]))
        for (view, next) in pairs where view.nextKeyView !== next || next.previousKeyView !== view {
            // Re-setting the same next view may not touch its previous view: clear first.
            if view.nextKeyView === next { view.nextKeyView = nil }
            view.nextKeyView = next
        }
    }

    // MARK: Helpers (shared with the field editor's styler)

    static func makeLabel(font: NSFont, identifier: String) -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.font = font
        label.lineBreakMode = .byTruncatingTail
        label.identifier = NSUserInterfaceItemIdentifier(identifier)
        return label
    }

    static func setText(_ label: NSTextField, _ text: String) {
        if label.stringValue != text { label.stringValue = text }
    }

    /// Colours a label and marks the tone, so the generic skin keeps it in that tone at every later restyle.
    static func tone(_ label: NSTextField, _ tone: SAClaudeRecolouring.Tone, _ colours: SAClaudeSheetColours) {
        let colour = tone == .muted ? colours.muted : colours.theme.text
        if label.textColor != colour { label.textColor = colour }
        SAClaudeStyledMark.setTone(tone, applied: colour, on: label)
    }

    /// A label's one-line text width plus the text cell's 2pt insets.
    static func textWidth(_ label: NSTextField) -> CGFloat {
        ceil(label.attributedStringValue.size().width) + 4
    }

    static func place(_ view: NSView, _ frame: NSRect) {
        let aligned = NSRect(x: frame.minX.rounded(), y: frame.minY.rounded(), width: frame.width.rounded(), height: frame.height.rounded())
        if view.frame != aligned { view.frame = aligned }
        if !view.autoresizingMask.isEmpty { view.autoresizingMask = [] }
    }

    /// A checkbox keeps its cell's width at the row's left; everything else fills its frame.
    private static func placeControl(_ view: NSView, _ kind: Layout.ControlKind, _ frame: NSRect) {
        guard kind == .checkbox, let control = view as? NSControl, let cellWidth = control.cell?.cellSize.width else {
            place(view, frame)
            return
        }
        place(view, NSRect(x: frame.minX, y: frame.minY, width: min(ceil(cellWidth), frame.width), height: frame.height))
    }

    /// A footer view's size: a bordered push button keeps its XIB frame (with its classic bezel margin), a borderless
    /// button or another control its cell's width, anything else its frame.
    static func footerItem(_ view: NSView) -> SAClaudeFormLayout.FooterItem {
        if let button = view as? NSButton, !(button is NSPopUpButton) {
            if button.isBordered, button.cell?.accessibilityRole() != .checkBox {
                return Layout.FooterItem(width: button.frame.width, height: button.frame.height,
                                         inset: SAClaudeSheetButtonGeometry.metrics(for: button.controlSize).classicSideMargin)
            }
            let width = button.cell.map { ceil($0.cellSize.width) } ?? button.frame.width
            return Layout.FooterItem(width: width, height: button.frame.height)
        }
        if let control = view as? NSControl, let size = control.cell?.cellSize {
            return Layout.FooterItem(width: ceil(size.width), height: ceil(size.height))
        }
        return Layout.FooterItem(width: view.frame.width, height: view.frame.height)
    }

    private static func styleDisclosureLabel(_ label: NSButton, _ colours: SAClaudeSheetColours) {
        SAClaudeFormChrome.makePlain(label)
        let title = NSAttributedString(string: label.title, attributes: [.font: sectionFont, .foregroundColor: colours.muted])
        if label.attributedTitle != title { label.attributedTitle = title }
        if label.alignment != .left { label.alignment = .left }
    }

    private static func styleGlyphButton(_ button: NSButton, _ glyph: SAClaudeGlyph, _ colours: SAClaudeSheetColours) {
        SAClaudeFormChrome.makePlain(button)
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleNone
        let image = SAClaudeGlyphs.image(glyph, tint: colours.muted)
        button.image = image
        button.alternateImage = image
        SAClaudeHoverHighlighter.attach(to: button)
        SAClaudeHoverHighlighter.setFillColour(colours.palette.hover, for: button)
    }
}

// MARK: - Block surface

/// A full-width block's rounded surface (the editor theme's background, the drop stroke as outline), optionally with
/// a strip at its bottom (the index sheet's +/−) or top (the field editor's toolbar) in the card fill under a divider
/// in the same stroke.
/// Reads its colours at draw time; the generic skin redisplays the window on theme and accent changes.
final class SAClaudeFormSurfaceView: NSView {
    var stripHeight: CGFloat = 0 { didSet { if stripHeight != oldValue { needsDisplay = true } } }
    var stripAtTop = false { didSet { if stripAtTop != oldValue { needsDisplay = true } } }

    override var isFlipped: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let palette = SAClaudeFilterBarStyler.currentPalette
        // The drop stroke, like the chips and checkboxes: the 8% hairline vanishes in dark mode.
        let edge = SAClaudeFilterChrome.dropStroke(text: SAClaudeFilterBarStyler.currentThemeText, background: palette.background)
        let radius = SAClaudeFormLayout.blockRadius
        let outline = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: radius - 0.5, yRadius: radius - 0.5)
        palette.background.setFill()
        outline.fill()
        if stripHeight > 0 {
            let height = min(stripHeight, bounds.height)
            let strip = stripAtTop ? NSRect(x: 0, y: bounds.maxY - height, width: bounds.width, height: height)
                                   : NSRect(x: 0, y: 0, width: bounds.width, height: height)
            NSGraphicsContext.saveGraphicsState()
            outline.addClip()
            SAClaudeFilterChrome.cardFill(text: SAClaudeFilterBarStyler.currentThemeText, background: palette.background).setFill()
            strip.fill()
            edge.setFill()
            NSRect(x: 0, y: stripAtTop ? strip.minY - 1 : strip.maxY, width: bounds.width, height: 1).fill()
            NSGraphicsContext.restoreGraphicsState()
        }
        outline.lineWidth = 1
        edge.setStroke()
        outline.stroke()
    }
}

// MARK: - Finding XIB views

enum SAClaudeFormFind {

    /// The static label left of `control` in its superview, by XIB frames: the one overlapping it most vertically,
    /// then the nearest. Call before anything is moved.
    static func label(beside control: NSView) -> NSTextField? {
        guard let container = control.superview else { return nil }
        let target = control.frame
        var best: (label: NSTextField, overlap: CGFloat)?
        for case let label as NSTextField in container.subviews where label !== control && !label.isEditable && !label.isHidden {
            guard label.frame.maxX <= target.minX + 4 else { continue }
            let overlap = min(label.frame.maxY, target.maxY) - max(label.frame.minY, target.minY)
            guard overlap > 0 else { continue }
            if let current = best, current.overlap > overlap || (current.overlap == overlap && current.label.frame.maxX >= label.frame.maxX) { continue }
            best = (label, overlap)
        }
        return best?.label
    }

    /// A button directly in `view` answering `keyEquivalent` ("\r" Return, "\u{1b}" Escape) inside its bounds
    /// (off-screen key-equivalent dummies are skipped).
    static func button(in view: NSView, keyEquivalent: String) -> NSButton? {
        view.subviews.lazy.compactMap { $0 as? NSButton }.first {
            !($0 is NSPopUpButton) && $0.keyEquivalent == keyEquivalent && view.bounds.intersects($0.frame)
        }
    }

    /// The first button directly in `view` that sends `action` ("closeSheet:").
    static func button(in view: NSView, action: String) -> NSButton? {
        buttons(in: view, action: action).first
    }

    static func buttons(in view: NSView, action: String) -> [NSButton] {
        let selector = NSSelectorFromString(action)
        return view.subviews.compactMap { $0 as? NSButton }.filter { $0.action == selector }
    }

    /// The nearest box enclosing `view`.
    static func box(around view: NSView) -> NSBox? {
        var current = view.superview
        while let candidate = current {
            if let box = candidate as? NSBox { return box }
            current = candidate.superview
        }
        return nil
    }

    /// Moves `views` into `container` (their frames are the form's to set).
    static func reparent(_ views: [NSView], into container: NSView) {
        for view in views where view.superview !== container {
            view.removeFromSuperview()
            container.addSubview(view)
        }
    }
}

// MARK: - Button chrome

enum SAClaudeFormChrome {

    /// A borderless button drawn natively (an image, an attributed title): undoes the sheet skin's push-button cell if
    /// it installed one, so the skin's later walks leave the button alone (they skip borderless buttons).
    static func makePlain(_ button: NSButton) {
        if let cell = button.cell, cell is SAClaudeSheetPrimaryButtonCell || cell is SAClaudeSheetSecondaryButtonCell,
           SAClaudeClassSwap.mayChangeClass(of: cell) {
            object_setClass(cell, NSButtonCell.self)
        }
        if button.isBordered { button.isBordered = false }
        button.needsDisplay = true
    }

    /// Gives `button` the primary or secondary sheet look whatever the rules say, now and at every later walk.
    static func force(_ button: NSButton, primary: Bool) {
        SAClaudeSheetButtonRole.force(button, primary: primary)
        SAClaudeWindowSkin.styleButton(button, alert: nil)
    }

    /// A 28pt ghost icon button: borderless, its image only (a template, tinted by the styler), hover fill, tooltip.
    static func makeGhostIcon(_ button: NSButton, image: NSImage?, toolTip: String?) {
        makePlain(button)
        if let image {
            image.isTemplate = true
            button.image = image
            button.alternateImage = nil
        }
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        if let toolTip { button.toolTip = toolTip }
        SAClaudeHoverHighlighter.attach(to: button)
    }
}
