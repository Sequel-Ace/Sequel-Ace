//
//  SAClaudeAlertCardStyler.swift
//  Sequel Ace
//
//  The app's side of the Claude alert card: classifies the alert as it is presented (`prepare`), installs the card
//  once the alert has laid itself out and the generic skin has styled it (`attach`), keeps it in step with the theme,
//  the appearance and the accent, and puts it back whenever the alert window is considered again (`claim`).
//  Called from `SAClaudeSheetStyler.styleAlert(_:presentedOn:)` and `consider`. App target only.
//

import AppKit

/// Where an alert came from. `.app` unless it was built from an NSError (`+alertWithError:`, which `presentError:`
/// uses too); an NSError alert is an Error whatever its text says.
enum SAClaudeAlertOrigin: String {
    case app, error

    private static var key: UInt8 = 0

    static func origin(of alert: NSAlert) -> SAClaudeAlertOrigin {
        (objc_getAssociatedObject(alert, &key) as? String).flatMap(SAClaudeAlertOrigin.init(rawValue:)) ?? .app
    }

    static func markFromError(_ alert: NSAlert) {
        objc_setAssociatedObject(alert, &key, SAClaudeAlertOrigin.error.rawValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    static func isFromError(_ alert: NSAlert) -> Bool {
        origin(of: alert) == .error
    }
}

enum SAClaudeAlertCardStyler {

    private static var classificationKey: UInt8 = 0
    private static var appearanceObservationKey: UInt8 = 0

    /// The classification `prepare` stored on an alert.
    private final class StoredClassification: NSObject {
        let value: SAClaudeAlertClassification
        init(_ value: SAClaudeAlertClassification) { self.value = value }
    }

    /// Before the buttons are styled. False = no card for this alert (not eligible: a SwiftUI `.alert`, a subclass, a
    /// foreign button target); it keeps today's skin. `parent` is the window a sheet is presented on; `runModal` passes
    /// nil (SwiftUI alerts are sheets, so nothing is lost).
    static func prepare(_ alert: NSAlert, presentedOn parent: NSWindow?) -> Bool {
        let eligibility = SAClaudeAlertEligibility.Facts(
            alertClassName: visibleClassName(of: alert),
            buttonTargetClassNames: alert.buttons.map { button in (button.target as AnyObject?).map(visibleClassName(of:)) },
            presentingContentClassName: presentingContentClassName(of: parent))
        guard SAClaudeAlertEligibility.isEligible(eligibility) else {
            #if DEBUG
            NSLog("SAClaudeAlertCard: alert not eligible, keeping today's skin: \(eligibility)")
            #endif
            return false
        }
        let facts = SAClaudeAlertFacts(title: alert.messageText, message: alert.informativeText,
                                       buttonTitles: alert.buttons.map(\.title), isFromError: SAClaudeAlertOrigin.isFromError(alert))
        let classification = SAClaudeAlertKind.classify(facts)
        objc_setAssociatedObject(alert, &classificationKey, StoredClassification(classification), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return true
    }

    // MARK: - Eligibility facts

    /// `NSStringFromClass` of the object's class with KVO subclasses (`NSKVONotifying_…`) skipped.
    static func visibleClassName(of object: AnyObject) -> String {
        var cls: AnyClass? = object_getClass(object)
        while let current = cls, NSStringFromClass(current).hasPrefix("NSKVONotifying_"), let parent = class_getSuperclass(current) {
            cls = parent
        }
        return cls.map { NSStringFromClass($0) } ?? ""
    }

    /// The class name (`String(describing:)`, so KVO and mangling do not matter) of the first SwiftUI hosting view in
    /// the presenting window's view tree that is visible and fills the window's content; else of the content view.
    /// A hosting view that only fills part of the window (the record view overlay, the script console in a database
    /// window) does not make the window a SwiftUI one.
    static func presentingContentClassName(of window: NSWindow?) -> String? {
        guard let content = window?.contentView else { return nil }
        if let hosting = fullSizeHostingView(in: content, content: content) { return String(describing: type(of: hosting)) }
        return String(describing: type(of: content))
    }

    private static func fullSizeHostingView(in view: NSView, content: NSView) -> NSView? {
        if SAClaudeAlertEligibility.isHostingViewClassName(String(describing: type(of: view))),
           !view.isHiddenOrHasHiddenAncestor, coversMostOf(content, view) {
            return view
        }
        for subview in view.subviews {
            if let found = fullSizeHostingView(in: subview, content: content) { return found }
        }
        return nil
    }

    private static func coversMostOf(_ content: NSView, _ view: NSView) -> Bool {
        let frame = content.convert(view.bounds, from: view).intersection(content.bounds)
        guard content.bounds.width > 0, content.bounds.height > 0 else { return false }
        return frame.width >= content.bounds.width * 0.9 && frame.height >= content.bounds.height * 0.9
    }

    /// After `layout()` and the generic skin.
    static func attach(_ alert: NSAlert) {
        guard let classification = (objc_getAssociatedObject(alert, &classificationKey) as? StoredClassification)?.value else { return }
        let parts = SAClaudeAlertMessageSplit.split(title: alert.messageText, message: alert.informativeText)
        guard let card = SAClaudeAlertCard.install(on: alert, classification: classification, parts: parts, colours: currentColours()) else { return }
        markLabels(of: card)

        // Only once the card is in (a refused card leaves the alert exactly as today): the destructive button turns red.
        // Its cell is swapped in place; the card has taken the button out of NSAlert's stack view, which no longer
        // observes it (`SAClaudeClassSwap`).
        if classification.kind == .destructive, let index = classification.destructiveButtonIndex, alert.buttons.indices.contains(index) {
            let button = alert.buttons[index]
            SAClaudeSheetButtonRole.forceDestructive(button)
            SAClaudeWindowSkin.styleButton(button, alert: alert)
        }

        SAClaudeThemeWatcher.observe(card) { refresh($0) }
        SAClaudeAccent.observe(card) { card in
            refresh(card)
            SAClaudeAccent.redisplay(card.root)
        }
        let observation = alert.window.observe(\.effectiveAppearance) { [weak card] _, _ in
            DispatchQueue.main.async {
                if let card { refresh(card) }
            }
        }
        // The observation lives as long as the card.
        objc_setAssociatedObject(card, &appearanceObservationKey, observation, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    /// From `SAClaudeSheetStyler.consider` whenever an alert window is considered again (becomes key).
    static func claim(_ window: NSWindow) {
        guard let alert = (window.delegate as? NSAlert).flatMap({ $0.window === window ? $0 : nil }),
              let card = SAClaudeAlertCard.card(for: alert) else { return }
        card.verify()
        markLabels(of: card)
    }

    // MARK: - Colours

    /// The card's colours from the editor theme, as every Claude sheet's.
    private static func currentColours() -> SAClaudeAlertCardColours {
        let colours = SAClaudeSheetColours.current()
        return SAClaudeAlertCardColours(surface: colours.surface, text: colours.theme.text, secondaryText: colours.muted,
                                        hairline: colours.palette.hairline, blockFill: colours.theme.background)
    }

    private static func refresh(_ card: SAClaudeAlertCard) {
        card.apply(colours: currentColours())
        markLabels(of: card)
    }

    /// The card's labels carry the styled mark, so the window skin's walks recolour them with the tone the card gave
    /// them (and the skin's surface view stays below the card root, which draws the same surface).
    private static func markLabels(of card: SAClaudeAlertCard) {
        func mark(_ label: NSTextField?, _ tone: SAClaudeRecolouring.Tone) {
            guard let label, let colour = label.textColor else { return }
            SAClaudeStyledMark.setTone(tone, applied: colour, on: label)
        }
        mark(card.titleLabel, .text)
        mark(card.messageLabel, .muted)
        mark(card.serverBlock?.label, .muted)
        mark(card.serverBlock?.text, .text)
    }
}
