//
//  SPWindowController.swift
//  Sequel Ace
//
//  Created by Jakub Kašpar on 24.01.2021.
//  Copyright © 2020-2022 Sequel-Ace. All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person
//  obtaining a copy of this software and associated documentation
//  files (the "Software"), to deal in the Software without
//  restriction, including without limitation the rights to use,
//  copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the
//  Software is furnished to do so, subject to the following
//  conditions:
//
//  The above copyright notice and this permission notice shall be
//  included in all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
//  EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
//  OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
//  NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
//  HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
//  WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
//  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
//  OTHER DEALINGS IN THE SOFTWARE.
//
//  More info at <https://github.com/Sequel-Ace/Sequel-Ace>

import Cocoa
import SnapKit

@objc final class SPWindowController: NSWindowController {

    @objc lazy var databaseDocument: SPDatabaseDocument = SPDatabaseDocument(windowController: self)

    @objc let uniqueID: UUID = UUID()

    /// Autosave name shared by all main windows: the frame the user saw last wins.
    private static let frameAutosaveName = "MainWindow"

    override func awakeFromNib() {
        super.awakeFromNib()

        if let window = window  {
            window.collectionBehavior = [window.collectionBehavior, .fullScreenPrimary]
        }

        setupFramePersistence()
        setupAppearance()
        observeTitlebarTintPreference()
        observeTabSelection()
        window?.toolbarStyle = .unified
    }

    /// The favourite colour of the connection in this tab, or `nil` when it has
    /// none or the tab is not connected. Kept so the title bar can be repainted
    /// when the preference is toggled, without waiting for a title update.
    private var favoriteColor: NSColor?

    /// Holds the preference observer for the window's lifetime; the token
    /// unregisters it on deinit.
    private var titlebarTintSubscription: NotificationToken?

    /// Key-window observers that keep the tab accessory's selected style current;
    /// the tokens unregister them on deinit.
    private var tabSelectionSubscriptions: [NotificationToken] = []

    /// Observes `selectedWindow` of the tab group this window is in. The group
    /// object changes when tabs are merged or moved out, so it is re-made then.
    private var tabGroupObservation: NSKeyValueObservation?
    private weak var observedTabGroup: NSWindowTabGroup?

    // MARK: - Accessory
    private lazy var tabAccessoryView: SPWindowTabAccessory = SPWindowTabAccessory()

    /// Opaque backing for the content area. The tinted title bar (see
    /// `applyTitlebarTint`) is painted by the window's own background, which also
    /// shows through anywhere the document view doesn't draw - split view gaps,
    /// the frame or two before subviews catch up with a live resize. This keeps
    /// the connection colour in the window top instead of leaking below it.
    /// `NSBox` resolves its fill colour at draw time, so it follows light/dark.
    private lazy var contentBackground: NSBox = {
        let box = NSBox()
        box.boxType = .custom
        box.titlePosition = .noTitle
        box.borderWidth = 0
        box.fillColor = .windowBackgroundColor
        return box
    }()

    deinit {
        print("Deinit called")
    }
}

// MARK: - Private API

private extension SPWindowController {
    /// The main window nib carries `frameAutosaveName="MainWindow"`, but `NSWindowController`
    /// applies its own (empty) `windowFrameAutosaveName` to the window it loads, so the nib
    /// value never takes effect: closing the last window and opening a new one (⌘W → ⌘N/⌘T)
    /// dropped the user's window size and position (#1307). Restore the saved frame explicitly
    /// and claim the autosave name so subsequent moves/resizes are persisted again.
    ///
    /// Only one live window can own an autosave name at a time, so with several windows open
    /// the claim is best-effort. Every window additionally saves its frame when it is moved,
    /// resized, or closed (see the `NSWindowDelegate` methods below), so the most recently
    /// manipulated window always defines the frame the next new window opens with - no
    /// ownership handover is needed when the claiming window closes first.
    func setupFramePersistence() {
        shouldCascadeWindows = false
        windowFrameAutosaveName = Self.frameAutosaveName
        window?.setFrameUsingName(Self.frameAutosaveName)
    }

    /// Put the document's view into the window and hook up the tab accessory.
    ///
    /// The opaque `contentBackground` goes in first so it sits *below* the
    /// document view: it is the backstop for the tinted window background (see
    /// `applyTitlebarTint`), not part of the document's own chrome.
    func setupAppearance() {
        databaseDocument.updateWindowTitle(self)

        if let contentView = window?.contentView {
            contentBackground.frame = contentView.bounds
            contentBackground.autoresizingMask = [.width, .height]
            contentView.addSubview(contentBackground)
        }

        window?.contentView?.addSubview(databaseDocument.databaseView())
        databaseDocument.databaseView().frame = window?.contentView?.frame ?? NSRect(x: 0, y: 0, width: 800, height: 400)

        if #available(macOS 10.13, *) {
            window?.tab.accessoryView = tabAccessoryView
        }
        // AppKit re-hosts every tab's accessory in the selected window's tab bar
        // whenever the group's selection or membership changes (merge, move a tab
        // out, drag between windows). Deferred so the group's state has settled.
        tabAccessoryView.onMoveToWindow = { [weak self] in
            DispatchQueue.main.async { self?.updateTabSelection() }
        }
    }

    /// Paint the whole window top - title bar, unified toolbar and the native
    /// tab bar - in the favourite colour of the connection this tab holds, or
    /// restore the stock title bar when there is no colour (#1856).
    ///
    /// `SAWindowTitlebarTint` decides what the chrome should look like; this
    /// only applies it. Every tab is its own `NSWindow`, so the colour follows
    /// whichever tab is selected without any extra bookkeeping.
    func applyTitlebarTint(_ color: NSColor?) {
        guard let window = window else {
            return
        }

        let tint = SAWindowTitlebarTint(
            favoriteColor: color,
            isEnabled: UserDefaults.standard.bool(forKey: SPDisplayConnectionColorInTitlebar)
        )

        // Every defaults change wakes the observer below, so skip the work -
        // and the redraw it triggers - unless the chrome actually differs.
        guard window.titlebarAppearsTransparent != tint.titlebarAppearsTransparent
                || window.backgroundColor != tint.backgroundColor
                || window.titlebarSeparatorStyle != tint.separatorStyle else {
            return
        }

        window.titlebarAppearsTransparent = tint.titlebarAppearsTransparent
        window.backgroundColor = tint.backgroundColor
        window.titlebarSeparatorStyle = tint.separatorStyle
    }

    /// Repaint the title bar when the preference is toggled, so turning the
    /// colour on or off reaches open windows immediately rather than at the
    /// next title update.
    func observeTitlebarTintPreference() {
        titlebarTintSubscription = NotificationCenter.default.observe(
            name: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else {
                return
            }
            self.applyTitlebarTint(self.favoriteColor)
        }
    }

    /// Restyle the tab content when this window gains or loses key status, when its
    /// accessory is re-hosted (see `setupAppearance`) and when its tab group's
    /// `selectedWindow` changes. Each refresh covers the whole group, because a
    /// merge or a tab moving out changes the selection of tabs that never become
    /// or resign key themselves.
    func observeTabSelection() {
        guard let window = window else {
            return
        }
        tabSelectionSubscriptions = [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification].map { name in
            NotificationCenter.default.observe(name: name, object: window, queue: .main) { [weak self] _ in
                self?.updateTabSelection()
            }
        }
        updateTabSelection()
    }

    /// Restyle every tab in this window's tab group.
    func updateTabSelection() {
        guard let window = window else {
            return
        }
        for tab in window.tabGroup?.windows ?? [window] {
            (tab.windowController as? SPWindowController)?.applyTabSelection()
        }
    }

    /// The group's selected tab stays selected while another app or window is key.
    func applyTabSelection() {
        guard let window = window else {
            return
        }
        observeTabGroup(window.tabGroup)
        let selected = window.tabGroup.map { $0.selectedWindow === window } ?? window.isKeyWindow
        tabAccessoryView.setSelected(selected)
    }

    /// Follows `group`'s selection (KVO compliant per NSWindowTabGroup.h); a no-op
    /// while it is already the observed group.
    func observeTabGroup(_ group: NSWindowTabGroup?) {
        guard group !== observedTabGroup || (group != nil && tabGroupObservation == nil) else {
            return
        }
        observedTabGroup = group
        tabGroupObservation = group?.observe(\.selectedWindow) { [weak self] _, _ in
            DispatchQueue.main.async { self?.updateTabSelection() }
        }
    }
}

// MARK: - Public API

@objc extension SPWindowController {
    func updateWindow(title: String, tabTitle: String) {
        window?.title = title
        if #available(macOS 10.13, *) {
            window?.tab.title = tabTitle
            // The window title is the full path; the tab shows only its tail.
            window?.tab.toolTip = title
        }

        tabAccessoryView.setTitle(title: tabTitle)
        tabAccessoryView.setToolTipPath(title)
    }

    func updateWindow(title: String, tabTitle: String, subtitle: String) {
        updateWindow(title: title, tabTitle: tabTitle)
        if window?.subtitle != subtitle { window?.subtitle = subtitle }
    }

    /// Reflect the connection this tab holds in the window chrome: the colour
    /// dot on the tab accessory, the SSL padlock, and the title bar tint.
    ///
    /// The single funnel for all three, called from
    /// `-[SPDatabaseDocument updateWindowTitle:]`. A `nil` colour means "no
    /// favourite colour, or not connected" and clears the dot and the tint.
    func updateWindowAccessory(color: NSColor?, isSSL: Bool) {
        favoriteColor = color
        tabAccessoryView.update(color: color, isSSL: isSSL)
        applyTitlebarTint(color)
    }
}

extension SPWindowController: NSWindowDelegate {
    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        if !databaseDocument.parentTabShouldClose() {
            return false
        }

        if let appDelegate = NSApp.delegate as? SPAppController{
            appDelegate.setSpfSessionDocData(nil)
        }
        return true
    }

    func windowWillClose(_ notification: Notification) {
        // Persist this window's frame as the shared last-used frame even when it never owned
        // the exclusive autosave name (only one live window can): the most recently closed
        // window wins, so the next new window restores the frame the user saw last (#1307).
        window?.saveFrame(usingName: Self.frameAutosaveName)

        // Tell listeners that this database document is being closed - fixes retain cycles and allows cleanup
        NotificationCenter.default.post(name: NSNotification.Name.SPDocumentWillClose, object: databaseDocument)
    }

    // AppKit only auto-persists moves and resizes for the single window that owns the
    // autosave name, so windows that lost the claim would leave stale frame data behind
    // if a new window opened while they were still alive. Save explicitly from every
    // window so the last-manipulated frame is always the one a new window restores.
    func windowDidMove(_ notification: Notification) {
        window?.saveFrame(usingName: Self.frameAutosaveName)
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        window?.saveFrame(usingName: Self.frameAutosaveName)
    }

    func windowDidResize(_ notification: Notification) {
        // Covers non-live frame changes (zoom, programmatic setFrame) that never fire
        // windowDidEndLiveResize. Skipped mid-drag: live resizes save once at the end.
        guard let window = window, !window.inLiveResize else { return }
        window.saveFrame(usingName: Self.frameAutosaveName)
    }
}
