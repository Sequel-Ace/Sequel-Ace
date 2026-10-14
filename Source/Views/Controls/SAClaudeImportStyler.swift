//
//  SAClaudeImportStyler.swift
//  Sequel Ace
//
//  The entry point of the Claude look of the Import flow. `SAClaudeSheetStyler.consider` offers it every window it
//  styles (and every open panel whose accessory it styles); it claims those of an `SPDataImport`, found through the
//  window's controls (their target) or the open panel's delegate, as SPDataImport.m carries no hook. Once per
//  importer it styles the progress and errors sheets (`SAClaudeProgressSheetStyler`, kept in step with the editor
//  theme, the accent and the appearance); the open panel's options strip and the Import from Clipboard sheet go to
//  `SAClaudeImportAccessoryStyler`. App target only.
//

import AppKit

enum SAClaudeImportStyler {

    private static let importerClassName = "SPDataImport"

    /// Claims `window` when it belongs to an importer: the importer's progress and errors sheets are styled (once).
    /// Called by `SAClaudeSheetStyler.consider` after the generic skin, each time a window is considered.
    static func claim(_ window: NSWindow) {
        // The field mapper's Global values sheet is not an importer's: `SAClaudeImportOptionsStyler` polishes it at attach.
        guard let importer = importer(for: window) else { return }
        SAClaudeImportSheets.attach(to: importer)
        // The options strip: the open panel's accessory, or inside the Import from Clipboard sheet.
        if window is NSSavePanel || window === SAClaudeExportStyler.outlet(importer, "importFromClipboardSheet") as NSWindow? {
            SAClaudeImportAccessoryStyler.attach(importer: importer)?.claim(window)
        }
    }

    /// The SPDataImport instance a window belongs to: a control in it whose target's class name is "SPDataImport",
    /// or an NSSavePanel (the open panel) whose delegate is one.
    static func importer(for window: NSWindow) -> NSObject? {
        if let panel = window as? NSSavePanel { return asImporter(panel.delegate) }
        guard let contentView = window.contentView else { return nil }
        return importer(in: contentView)
    }

    private static func importer(in view: NSView) -> NSObject? {
        if let control = view as? NSControl, let importer = asImporter(control.target) { return importer }
        for subview in view.subviews {
            if let importer = importer(in: subview) { return importer }
        }
        return nil
    }

    private static func asImporter(_ object: AnyObject?) -> NSObject? {
        guard let object = object as? NSObject,
              NSStringFromClass(SAClaudeSheetStyler.visibleClass(of: object)) == importerClassName else { return nil }
        return object
    }
}

// MARK: - Progress and errors sheets

/// One importer's progress and errors sheets: the shared styler and its colours. Retained by the importer.
private final class SAClaudeImportSheets {

    private static var associationKey: UInt8 = 0

    /// Every live instance (one per open document), for the shared theme check.
    private static let instances = NSHashTable<SAClaudeImportSheets>.weakObjects()
    private static var defaultsObserver: NSObjectProtocol?
    private static var themeCheckPending = false
    private static var lastTheme: SAClaudeThemeColours?

    private let styler: SAClaudeProgressSheetStyler
    /// The sheet whose appearance the colours are resolved in (the skin gives it the theme's light / dark).
    private weak var appearanceWindow: NSWindow?
    private var palette: SAClaudeEditorChrome.Palette?
    private var appearanceObservation: NSKeyValueObservation?

    /// Styles `importer`'s progress and errors sheets the first time; afterwards re-checks their colours (a sheet
    /// skinned since may resolve them in another appearance). Does nothing when neither sheet has its outlets.
    static func attach(to importer: NSObject) {
        if let existing = objc_getAssociatedObject(importer, &associationKey) as? SAClaudeImportSheets {
            existing.refresh(force: false)
            return
        }
        let progress = SAClaudeProgressSheetStyler.Outlets(importer, title: "singleProgressTitle",
                                                           status: "singleProgressText", indicator: "singleProgressBar")
        let errors = SAClaudeProgressSheetStyler.ErrorOutlets(importer, window: "errorsSheet", textView: "errorsView")
        guard let styler = SAClaudeProgressSheetStyler(progress: progress, errors: errors) else { return }
        let progressSheet: NSWindow? = SAClaudeExportStyler.outlet(importer, "singleProgressSheet")
        let sheets = SAClaudeImportSheets(styler: styler, appearanceWindow: progressSheet ?? errors?.window)
        objc_setAssociatedObject(importer, &associationKey, sheets, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        sheets.observe()
        sheets.refresh(force: true)
    }

    private init(styler: SAClaudeProgressSheetStyler, appearanceWindow: NSWindow?) {
        self.styler = styler
        self.appearanceWindow = appearanceWindow
    }

    deinit {
        appearanceObservation?.invalidate()
    }

    private func observe() {
        Self.instances.add(self)
        Self.observeDefaults()
        appearanceObservation = appearanceWindow?.observe(\.effectiveAppearance) { [weak self] _, _ in
            Self.onMain { self?.refresh(force: true) }
        }
        // The bar draws the accent.
        SAClaudeAccent.observe(self) { $0.refresh(force: true) }
    }

    /// Re-derives the palette when the editor theme changed (always, when `force`) and recolours the sheets.
    private func refresh(force: Bool) {
        var palette: SAClaudeEditorChrome.Palette?
        (appearanceWindow?.effectiveAppearance ?? NSApp.effectiveAppearance).performAsCurrentDrawingAppearance {
            palette = SAClaudeEditorChrome.palette(from: .standard)
        }
        guard let palette, force || palette != self.palette else { return }
        self.palette = palette
        styler.recolour(palette: palette)
    }

    private static func onMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
    }

    /// One observer for every importer: any defaults write may be a theme change.
    private static func observeDefaults() {
        guard defaultsObserver == nil else { return }
        // No `queue: .main`: a defaults write on a background thread must not wait for the main queue.
        defaultsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil,
                                                                  queue: nil) { _ in
            DispatchQueue.main.async { scheduleThemeCheck() }
        }
    }

    /// One theme check per main-queue turn, however many defaults writes ask for it (window frames are saved
    /// continuously), shared by all importers: they refresh only when the theme changed (as `SAClaudeWindowSkin`'s).
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
            instances.allObjects.forEach { $0.refresh(force: false) }
        }
    }
}
