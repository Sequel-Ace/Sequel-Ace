//
//  SAClaudeMenuCardPopUpButton.swift
//  Sequel Ace
//
//  A plain XIB pull-down (the query editor bar's History and Favorites) swapped to this class so that whatever
//  opens its menu opens the Claude card instead: a click, Space/Return/↓, VoiceOver's press and show menu, and
//  performClick: (which the button's own ⌥⌘Y / ⌥⌘F key equivalent goes through). The menu stays attached and is
//  the source of truth; when the card refuses it, the native menu opens as before. No stored properties (installed
//  with object_setClass); the adapter is an associated object. App target only.
//

import AppKit

@objc(SAClaudeMenuCardPopUpButton) final class SAClaudeMenuCardPopUpButton: NSPopUpButton {

    private static var adapterKey: UInt8 = 0

    /// Swaps `button` (a plain NSPopUpButton) to this class with `adapter`. Refused — the native menu stays — when the
    /// button is a subclass or something observes it by KVO (`SAClaudeClassSwap`); install before attaching observers.
    @discardableResult
    static func install(on button: NSPopUpButton, adapter: SAClaudeMenuCardAdapter) -> Bool {
        if let swapped = button as? SAClaudeMenuCardPopUpButton {
            swapped.adapter = adapter
            return true
        }
        guard object_getClass(button) == NSPopUpButton.self, SAClaudeClassSwap.mayChangeClass(of: button) else {
            #if DEBUG
            NSLog("SAClaudeMenuCard: not swapping %@ (class %@, observed %@)", button, NSStringFromClass(object_getClass(button) ?? NSObject.self),
                  button.observationInfo == nil ? "no" : "yes")
            #endif
            return false
        }
        objc_setAssociatedObject(button, &adapterKey, adapter, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        object_setClass(button, SAClaudeMenuCardPopUpButton.self)
        return true
    }

    private var adapter: SAClaudeMenuCardAdapter? {
        get { objc_getAssociatedObject(self, &Self.adapterKey) as? SAClaudeMenuCardAdapter }
        set { objc_setAssociatedObject(self, &Self.adapterKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    private func showCard() -> Bool {
        guard isEnabled, let menu, let adapter else { return false }
        return SAClaudeMenuCardPresenter.shared.show(menu: menu, from: self, adapter: adapter)
    }

    override func mouseDown(with event: NSEvent) {
        if !showCard() { super.mouseDown(with: event) }
    }

    // The pull-down's only job is to open: Space, Return and ↓ (and VoiceOver's press) open the card too.
    override func keyDown(with event: NSEvent) {
        let opensCard = event.modifierFlags.intersection([.command, .control, .option]).isEmpty
            && [49, 36, 76, 125].contains(event.keyCode)  // Space, Return, keypad Enter, ↓
        if !(opensCard && showCard()) { super.keyDown(with: event) }
    }

    override func accessibilityPerformPress() -> Bool {
        showCard() || super.accessibilityPerformPress()
    }

    override func accessibilityPerformShowMenu() -> Bool {
        showCard() || super.accessibilityPerformShowMenu()
    }

    /// The button's key equivalent (⌥⌘Y History, ⌥⌘F Favorites) arrives here through -performKeyEquivalent:.
    override func performClick(_ sender: Any?) {
        if !showCard() { super.performClick(sender) }
    }
}
