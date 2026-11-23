//
//  SAClaudeUpdateProgressStyler.swift
//  Sequel Ace
//
//  The update download window (Check for Updates… ▸ Download; `ProgressWindowController` from
//  ProgressWindowController.storyboard) in the Claude look, on top of the generic sheet skin:
//
//  - The Claude progress bar over the indicator and the 13pt medium title, as Export and Import have them
//    (`SAClaudeProgressSheetStyler`, installed once).
//  - The subtitle (time remaining) and the byte count in the muted colour at 11pt. Their storyboard grey is a custom
//    colour, which the generic skin leaves alone, so it is set here on every claim and on every theme, accent and
//    appearance change.
//  - A transparent title bar with the title hidden (the close button stays), and Cancel the secondary button
//    (its Esc key equivalent is kept).
//
//  The window is claimed by identity: its controller is a `ProgressWindowController`. Only the look is set; the
//  download, its progress values and `GitHubReleaseManager` are untouched. App target only.
//

import AppKit

@MainActor
@objc(SAClaudeUpdateProgressStyler) final class SAClaudeUpdateProgressStyler: NSObject {

    private static var associationKey: UInt8 = 0

    private weak var window: NSWindow?
    private let subtitle: NSTextField
    private let bytes: NSTextField
    private let cancel: NSButton?
    private let progress: SAClaudeProgressSheetStyler
    private var appearanceObservation: NSKeyValueObservation?

    private init(window: NSWindow, subtitle: NSTextField, bytes: NSTextField, cancel: NSButton?, progress: SAClaudeProgressSheetStyler) {
        self.window = window
        self.subtitle = subtitle
        self.bytes = bytes
        self.cancel = cancel
        self.progress = progress
        super.init()
    }

    // MARK: Claiming

    /// Styles `window` when it is the update download window (again on every call: each step is idempotent).
    @objc(claimWindow:) static func claim(_ window: NSWindow?) {
        guard let window else { return }
        if let styler = objc_getAssociatedObject(window, &associationKey) as? SAClaudeUpdateProgressStyler {
            styler.apply()
            return
        }
        guard let controller = window.windowController, controller.window === window,
              SAClaudeFormOwners.className(of: controller) == "ProgressWindowController",
              let content = controller.contentViewController, let contentView = window.contentView,
              let title: NSTextField = SAClaudeFormRecipes.outlet(content, "theTitle"),
              let subtitle: NSTextField = SAClaudeFormRecipes.outlet(content, "subtitle"),
              let bytes: NSTextField = SAClaudeFormRecipes.outlet(content, "bytes"),
              let indicator: NSProgressIndicator = SAClaudeFormRecipes.outlet(content, "progressIndicator"),
              indicator.window === window else { return }
        let outlets = SAClaudeProgressSheetStyler.Outlets(title: title, status: subtitle, indicator: indicator)
        guard let progress = SAClaudeProgressSheetStyler(progress: outlets, errors: nil) else { return }
        let cancel = SAClaudeFormFind.button(in: contentView, action: "cancelAction:")
            ?? indicator.superview.flatMap { SAClaudeFormFind.button(in: $0, action: "cancelAction:") }
        let styler = SAClaudeUpdateProgressStyler(window: window, subtitle: subtitle, bytes: bytes, cancel: cancel, progress: progress)
        objc_setAssociatedObject(window, &associationKey, styler, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        styler.build()
        styler.apply()
    }

    /// Whether `window` was claimed here (the harness and tests).
    static func isClaimed(_ window: NSWindow) -> Bool {
        objc_getAssociatedObject(window, &associationKey) is SAClaudeUpdateProgressStyler
    }

    // MARK: Building

    private func build() {
        bytes.font = NSFont.systemFont(ofSize: 11)
        window?.titlebarAppearsTransparent = true
        window?.titleVisibility = .hidden
        SAClaudeThemeWatcher.observe(self) { styler in
            MainActor.assumeIsolated { styler.apply() }
        }
        SAClaudeAccent.observe(self) { styler in
            MainActor.assumeIsolated { styler.apply() }
        }
        appearanceObservation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.apply() } }
        }
    }

    /// The colours: the muted subtitle and byte count, the bar's track and accent, Cancel's secondary look.
    private func apply() {
        let colours = SAClaudeSheetColours.current()
        progress.recolour(palette: colours.palette)
        for label in [subtitle, bytes] where label.textColor != colours.muted { label.textColor = colours.muted }
        if let cancel { SAClaudeFormChrome.force(cancel, primary: false) }
    }
}
