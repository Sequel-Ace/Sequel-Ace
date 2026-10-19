//
//  SAClaudeSheetRules.swift
//  Sequel Ace
//
//  The pure mapping from a description of a control to the Claude style it is
//  given inside a sheet, alert or auxiliary window. The styler reads a real
//  control into an `SAClaudeControlDescriptor` and applies the returned
//  `SAClaudeControlStyle`; nothing here touches a view. Shared with the Unit
//  Tests target.
//

import AppKit

/// What the styler needs to know about a control to pick its style.
struct SAClaudeControlDescriptor: Equatable {
    enum Kind: Equatable { case button, textField, popUp, box, table, textView, other }

    var kind: Kind
    /// `.switch` (checkbox), `.radio`, `.momentaryPushIn` ...
    var buttonType: NSButton.ButtonType? = nil
    var bezelStyle: NSButton.BezelStyle? = nil
    var title: String = ""
    var keyEquivalent: String = ""
    /// The window's default button (its `defaultButtonCell`). AppKit blanks that button's key equivalent while its window
    /// is not key (`-[NSWindow resignKeyWindow]`) and puts Return back when it becomes key again, so a walk of a window
    /// that is not key reads "" for its Return button: this keeps it the primary all the same.
    var isDefaultButton = false
    var isAlertButton = false
    /// 0 = the alert's first button.
    var alertButtonIndex: Int? = nil
    /// Whether any of the alert's buttons answers Return: then that one is the primary, not necessarily the first.
    var alertHasReturnButton = false
    var isDestructive = false
    var isEditable = false
    var isBezeledOrBordered = false
    var fontSize: CGFloat = 13
    var isSeparatorBox = false
    var boxTitle: String = ""
    /// A pop-up or pull-down that shows an image and no title (a gear menu): the pill draws titles, not images.
    var isImageOnly = false
}

/// The Claude look a control is given.
enum SAClaudeControlStyle: Equatable {
    case primaryButton, secondaryButton, checkbox, radio, pill, field, label, mutedLabel
    case separator, titledBox, quietTable, editorTextView, unchanged
}

enum SAClaudeSheetRules {

    /// Labels at or below this size are drawn muted.
    static let mutedLabelMaxFontSize: CGFloat = 11

    static func style(for d: SAClaudeControlDescriptor) -> SAClaudeControlStyle {
        switch d.kind {
        case .button: return buttonStyle(for: d)
        case .textField:
            if d.isEditable { return d.isBezeledOrBordered ? .field : .unchanged }
            return d.fontSize <= mutedLabelMaxFontSize ? .mutedLabel : .label
        case .popUp: return d.isImageOnly ? .unchanged : .pill
        case .box:
            if d.isSeparatorBox { return .separator }
            return d.boxTitle.isEmpty ? .unchanged : .titledBox
        case .table: return .quietTable
        case .textView: return .editorTextView
        case .other: return .unchanged
        }
    }

    private static func buttonStyle(for d: SAClaudeControlDescriptor) -> SAClaudeControlStyle {
        if d.buttonType == .switch { return .checkbox }
        if d.buttonType == .radio { return .radio }
        if d.title.isEmpty || d.isDestructive { return .unchanged }
        if d.isAlertButton {
            // Primary: the alert button that answers Return, or its first button when none does.
            let isPrimary = d.alertHasReturnButton ? answersReturn(d) : d.alertButtonIndex == 0
            if isPrimary { return .primaryButton }
            return isPushLike(d.bezelStyle) ? .secondaryButton : .unchanged
        }
        // Primary: a push-family button that answers Return.
        if answersReturn(d) && isPushLike(d.bezelStyle) { return .primaryButton }
        return isPushLike(d.bezelStyle) ? .secondaryButton : .unchanged
    }

    /// Whether the button answers Return: its key equivalent, or (while its window is not key, when AppKit has blanked
    /// that key equivalent) its being the window's default button.
    static func answersReturn(_ d: SAClaudeControlDescriptor) -> Bool {
        d.keyEquivalent == "\r" || d.isDefaultButton
    }

    /// The push / rounded / regular-square family. On this SDK `.rounded` and `.regularSquare` are
    /// deprecated aliases of `.push` (1) and `.flexiblePush` (2), the same values, so one case each
    /// covers both spellings; going by raw value keeps the deprecated names out of the build.
    private static func isPushLike(_ bezel: NSButton.BezelStyle?) -> Bool {
        guard let bezel else { return false }
        return bezel == .push || bezel == .flexiblePush
    }
}

/// Where a restyled push button draws inside the frame it was given. XIB push buttons were laid out with the
/// classic bezel's transparent side margins inside their frames (6pt regular, 5pt small, 1pt mini), whatever
/// height the frame has, so neighbouring buttons and fields keep a visual gap; NSAlert lays its buttons out
/// edge to edge with its own spacing, so they have none. The Claude button is drawn at most `maximumHeight`
/// tall, centred vertically.
enum SAClaudeSheetButtonGeometry {

    struct Metrics: Equatable {
        /// The tallest the drawn button gets.
        let maximumHeight: CGFloat
        /// The classic bezel's side margin inside a XIB frame.
        let classicSideMargin: CGFloat
    }

    static func metrics(for controlSize: NSControl.ControlSize) -> Metrics {
        switch controlSize {
        case .small: return Metrics(maximumHeight: 22, classicSideMargin: 5)
        case .mini: return Metrics(maximumHeight: 18, classicSideMargin: 1)
        default: return Metrics(maximumHeight: 28, classicSideMargin: 6)
        }
    }

    /// `classicMargins`: the frame carries the classic side margins (every XIB push button; not NSAlert's).
    static func buttonRect(in frame: NSRect, controlSize: NSControl.ControlSize, classicMargins: Bool) -> NSRect {
        let metrics = metrics(for: controlSize)
        let height = min(frame.height, metrics.maximumHeight)
        let side = classicMargins ? metrics.classicSideMargin : 0
        let width = max(0, frame.width - side * 2)
        return NSRect(x: frame.minX + side, y: frame.minY + ((frame.height - height) / 2).rounded(.down), width: width, height: height)
    }
}

/// The private views AppKit draws a control with on macOS 26 and later (an NSButton's bezel, title and image views, a
/// pop-up's indicator, SwiftUI hosting views inside a control or an NSBox). A control the Claude skin makes draw through
/// its cell keeps the ones it had before the swap until AppKit happens to rebuild them (it does for a window's default
/// button whenever its key equivalent is blanked and restored, never for the others), and as subviews they draw on top of
/// the Claude cell: the skin hides them at every walk.
enum SAClaudeNativeDrawingViews {

    /// AppKit's own drawing views inside a button or pop-up, by class name.
    static let controlViewClasses: Set<String> = ["NSButtonBezelView", "NSButtonTextField", "NSButtonImageView", "NSPopUpIndicatorView"]

    /// Whether a subview of a control with this class name (`String(describing: type(of:))`) is AppKit's drawing of it.
    static func isControlDrawingView(className: String) -> Bool {
        controlViewClasses.contains(className) || isHostingView(className: className)
    }

    /// A SwiftUI hosting view (`_NSCoreHostingView<AppKitButton>`, `_NSCoreHostingView<AppKitBoxView>`, `NSHostingView<…>`).
    static func isHostingView(className: String) -> Bool {
        className.contains("HostingView")
    }

    /// Whether a direct subview of a Claude-drawn titled box or separator is AppKit's drawing of it: a hosting view, or the
    /// text field showing the box's title (the Claude box draws its title itself). The box's content view never is.
    static func isBoxDrawingView(className: String, isContentView: Bool, isTextField: Bool, text: String, boxTitle: String) -> Bool {
        if isContentView { return false }
        if isHostingView(className: className) { return true }
        return isTextField && !boxTitle.isEmpty && text == boxTitle
    }
}

/// Where a Claude titled box leaves a gap in its outline for the title (pure, so it is tested).
enum SAClaudeTitledBoxGeometry {
    /// Clear space either side of the title.
    static let titlePadding: CGFloat = 3

    /// The part of the outline the title covers, or nil when the title sits clear of the outline (above the card, as
    /// AppKit lays a titled box out on macOS 26+, even when its title rect overlaps the border rect by a point or two). The
    /// title is on the outline when the card's top or bottom edge runs through the middle half of the title's height.
    /// `titleOriginX` and `titleWidth` are where the title is drawn.
    static func titleGap(titleRect: NSRect, borderRect: NSRect, titleOriginX: CGFloat, titleWidth: CGFloat) -> NSRect? {
        guard titleWidth > 0, titleRect.maxX > borderRect.minX, titleRect.minX < borderRect.maxX else { return nil }
        let band = titleRect.height / 4
        let onEdge = [borderRect.minY, borderRect.maxY].contains { $0 > titleRect.minY + band && $0 < titleRect.maxY - band }
        guard onEdge else { return nil }
        return NSRect(x: titleOriginX - titlePadding, y: titleRect.minY, width: titleWidth + titlePadding * 2, height: titleRect.height)
    }
}

/// Which windows the sheet styler restyles, decided from facts about the window (pure, so it is tested).
enum SAClaudeSheetTargeting {

    /// Owners (window controller or delegate) of the auxiliary windows that are restyled even when they are not sheets.
    static let auxiliaryOwnerClasses: Set<String> = [
        "SPPreferenceController",          // Preferences
        "SPProcessListController",         // Process list
        "SPServerVariablesController",     // Server variables
        "SPQueryFavoriteManager",          // Query favourites manager
        "SPContentFilterManager",          // Content filter manager
        "SPNavigatorController",           // Navigator
        "SPBundleEditorController",        // Bundle editor
        "SPFieldEditorController",         // Field editor sheet
        "SPExportController",              // Export
        "SPDataImport",                    // Import (accessory and options)
        "SPFieldMapperController",         // Data migration (import field mapping)
        "SPUserManager",                   // User manager
        "SPGotoDatabaseController",        // Go to database
        "SPSSHTunnel",                     // SSH host question
        "SPFilterTableController",         // Advanced filter panel
        "ProgressWindowController",        // Update download window
    ]

    /// Owners whose windows are never restyled, sheet or not: the main document window, the Query Console and
    /// the experimental standalone connection window. That window is no longer opened from the menu (⇧⌘N now
    /// opens the main window's connection screen); it stays excluded so the sheet styler never walks its
    /// SwiftUI content.
    static let excludedOwnerClasses: Set<String> = ["SPWindowController", "SPQueryController", "SAConnectionWindowController"]

    enum Decision: Equatable {
        /// Restyle the whole window.
        case window
        /// Restyle it as an NSAlert's window (button roles from the alert).
        case alert
        /// An open / save panel: restyle only its accessory view.
        case accessoryOnly
        /// Leave it alone.
        case skip
    }

    struct Facts: Equatable {
        var isAlertWindow = false
        var isSavePanel = false
        /// NSWindow, NSPanel or a class of the app itself (not a system panel, popover or other AppKit-private window).
        var isPlainOrAppWindowClass = true
        var hasSheetParent = false
        /// The class names of the window's controller and delegate, as `NSStringFromClass` gives them (a Swift
        /// class without an `@objc` name comes module-qualified, "Sequel_Ace.SPWindowController").
        var ownerClasses: [String] = []
    }

    static func decision(for facts: Facts) -> Decision {
        if facts.isAlertWindow { return .alert }
        if facts.isSavePanel { return .accessoryOnly }
        guard facts.isPlainOrAppWindowClass else { return .skip }
        let owners = facts.ownerClasses.map(unqualified)
        if owners.contains(where: excludedOwnerClasses.contains) { return .skip }
        if facts.hasSheetParent { return .window }
        return owners.contains(where: auxiliaryOwnerClasses.contains) ? .window : .skip
    }

    /// A class name without its module prefix: "Sequel_Ace.SPWindowController" → "SPWindowController".
    static func unqualified(_ className: String) -> String {
        className.split(separator: ".").last.map(String.init) ?? className
    }
}

/// Which text and background colours the sheet styler sets. A view it has coloured is marked (by the styler, on the
/// view) with the tone and the colour it gave it. While the view still shows that colour it is the styler's and is
/// recoloured on every restyle (a view off-screen during a theme change keeps the old theme's colour until then);
/// once its code sets a colour of its own (a status label going green), the view is left alone. An unmarked view is
/// only coloured while it shows a system default colour; a colour its code chose is kept.
enum SAClaudeRecolouring {

    enum Tone: String, Equatable { case text, muted }

    /// The system text colours a control has when nobody chose one.
    static func isSystemText(_ colour: NSColor?) -> Bool {
        guard let colour else { return true }
        return colour == .controlTextColor || colour == .labelColor || colour == .textColor || isSystemSecondaryText(colour)
    }

    /// The system's secondary text colours: a label in one stays muted.
    static func isSystemSecondaryText(_ colour: NSColor?) -> Bool {
        guard let colour else { return false }
        return colour == .secondaryLabelColor || colour == .tertiaryLabelColor || colour == .disabledControlTextColor
    }

    /// The system backgrounds a table, text view or scroll view has when nobody chose one.
    static func isSystemBackground(_ colour: NSColor) -> Bool {
        colour == .controlBackgroundColor || colour == .textBackgroundColor || colour == .windowBackgroundColor
            || colour == .underPageBackgroundColor
    }

    /// Whether `current` is still the colour the styler last gave the view.
    static func stillApplied(_ applied: NSColor?, current: NSColor?) -> Bool {
        guard let applied, let current else { return false }
        return applied == current
    }

    /// The tone for a label: the one it was marked with while it still shows the styler's colour; else, for a system
    /// colour, muted when it is small or already secondary, text otherwise; nil (leave it) for a colour its code chose.
    static func labelTone(marked: Tone?, applied: NSColor?, current: NSColor?, isSmall: Bool) -> Tone? {
        if let marked, stillApplied(applied, current: current) { return marked }
        guard isSystemText(current) else { return nil }
        return isSmall || isSystemSecondaryText(current) ? .muted : .text
    }

    /// Whether a text view's text (or a view's background) is the styler's to colour.
    static func ownsText(applied: NSColor?, current: NSColor?) -> Bool {
        stillApplied(applied, current: current) || isSystemText(current)
    }
    static func ownsBackground(applied: NSColor?, current: NSColor) -> Bool {
        stillApplied(applied, current: current) || isSystemBackground(current)
    }
}
