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
        observeConnectionColourStyle()
        window?.toolbarStyle = .unified
    }

    override func windowDidLoad() {
        super.windowDidLoad()
        if let window = window {
            let tabBar = SAClaudeWindowTabBarController(window: window)
            tabBar.onVisibilityChange = { [weak self] _ in self?.applyConnectionColourChrome() }
            self.tabBar = tabBar
            // Only one of the bar and the overlay draws the line at a time.
            colourLine.attach(to: window)
            namePill.attach(to: window)
        }
        applyConnectionColourChrome()
        databaseListSubscription = NotificationCenter.default.observe(name: .SPDatabaseCreatedRemovedRenamed, object: nil) { [weak self] _ in
            guard let self, let document = self.databaseDocument as? SADatabaseSelectionDelegate else { return }
            SADatabaseListManager.clearSelectionIfDropped(delegate: document, isWorking: self.databaseDocument.isWorking())
        }
    }

    /// Clears the selection of a dropped database (see `SADatabaseListManager.clearSelectionIfDropped`).
    private var databaseListSubscription: NotificationToken?

    /// The Claude tab bar under the toolbar (in place of macOS's tab strip).
    private(set) var tabBar: SAClaudeWindowTabBarController?

    /// What this tab's chip shows: the tab title and whether the connection uses SSL.
    private(set) var tabBarTitle = ""
    private(set) var tabBarIsSSL = false

    /// The favourite colour of the connection in this tab, or `nil` when it has
    /// none or the tab is not connected. Kept so the chrome can be redone when
    /// the preference changes or the tab bar shows or hides, without waiting for
    /// a title update.
    private var favoriteColor: NSColor?

    /// Holds the preference observer for the window's lifetime; the token
    /// unregisters it on deinit.
    private var connectionColourSubscription: NotificationToken?

    /// The "Show the connection colour as" choice the chips were last built for.
    private var chipConnectionColourStyle = SAConnectionColourStyle.current(.standard)

    /// The connection's Underline line right under the toolbar while the tab
    /// bar is hidden (see `applyConnectionColourChrome`).
    private lazy var colourLine = SAConnectionColourLineOverlay()

    /// The window title in Name pill mode, in place of the native one's text
    /// (see `applyNamePill`). Installed in `windowDidLoad`.
    private lazy var namePill = SAConnectionNamePillAccessory()

    /// The window's subtitle (the MySQL version, when shown), kept for the name
    /// pill, which draws it itself while the native title is hidden.
    private var windowSubtitle = ""

    // MARK: - Accessory
    private lazy var tabAccessoryView: SPWindowTabAccessory = SPWindowTabAccessory()

    /// Opaque backing for the content area. The Claude bar colour of the title
    /// bar (see `applyConnectionColourChrome`) is painted by the window's own
    /// background, which also shows through anywhere the document view doesn't
    /// draw - split view gaps, the frame or two before subviews catch up with a
    /// live resize. This keeps the bar colour in the window top instead of
    /// leaking below it. `NSBox` resolves its fill colour at draw time, so it
    /// follows light/dark.
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
    /// document view: it is the backstop for the window background (see
    /// `applyConnectionColourChrome`), not part of the document's own chrome.
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
    }

    /// Show the connection colour of this tab the way "Show the connection
    /// colour as" asks: never a filled title bar, but the Underline line (in
    /// the tab bar while it shows, else an overlay along the top edge of the
    /// content, right under the toolbar) or, with Tab underline, the chips' lines (built by the tab bar).
    /// Neither line changes the title bar's height.
    ///
    /// `SAWindowTitlebarTint` decides what the chrome should look like; this
    /// only applies it. Every tab is its own `NSWindow`, so the colour follows
    /// whichever tab is selected without any extra bookkeeping.
    func applyConnectionColourChrome() {
        guard let window = window else {
            return
        }

        let tint = SAWindowTitlebarTint(
            style: SAConnectionColourStyle.current(.standard),
            favoriteColor: favoriteColor,
            tabBarVisible: tabBar?.isShowing ?? false
        )

        // Every Claude setting change wakes the observer below, so skip the work -
        // and the redraw it triggers - for what is already right.
        if window.titlebarAppearsTransparent != tint.titlebarAppearsTransparent {
            window.titlebarAppearsTransparent = tint.titlebarAppearsTransparent
        }
        if window.backgroundColor != tint.backgroundColor {
            window.backgroundColor = tint.backgroundColor
        }
        if window.titlebarSeparatorStyle != tint.separatorStyle {
            window.titlebarSeparatorStyle = tint.separatorStyle
        }

        // Before `windowDidLoad` there is neither; it applies the chrome again.
        guard let tabBar = tabBar else {
            return
        }
        colourLine.colour = tint.bottomLineInTabBar ? nil : tint.bottomLine
        tabBar.bottomLineColour = tint.bottomLineInTabBar ? tint.bottomLine : nil
        applyNamePill(showsNamePill: tint.showsNamePill)
    }

    /// Name pill mode: show the pill title (the connection's name in its colour,
    /// then "db/table", the subtitle under it) in place of the native title's
    /// text while the window has a colour and a connected title; otherwise the
    /// native title. The pill decides where it draws and sets `titleVisibility`
    /// to match (see `SAConnectionNamePillAccessory`): with the toolbar shown it
    /// draws over the native title, which keeps its room, so no toolbar item moves.
    /// `window.title` is always kept, for the Window menu and Mission Control.
    /// Neither changes the title bar's height.
    func applyNamePill(showsNamePill: Bool) {
        guard let window = window, tabBar != nil else {
            return
        }
        let parts = showsNamePill
            ? SAWindowTitleBuilder.namePillParts(windowTitle: window.title, tabTitle: tabBarTitle, connectionName: databaseDocument.name())
            : nil
        if let parts = parts, let colour = favoriteColor {
            namePill.show(parts: parts, subtitle: windowSubtitle, colour: colour, accessibilityTitle: window.title)
        } else {
            namePill.hide()
        }
    }

    /// `applyNamePill` for the current choice and colour, after a title change.
    func refreshNamePill() {
        let tint = SAWindowTitlebarTint(
            style: SAConnectionColourStyle.current(.standard),
            favoriteColor: favoriteColor,
            tabBarVisible: tabBar?.isShowing ?? false
        )
        applyNamePill(showsNamePill: tint.showsNamePill)
    }

    /// Redo the chrome when the choice changes, so it reaches open windows
    /// immediately rather than at the next title update; the chips are rebuilt
    /// too when the choice changes their lines.
    func observeConnectionColourStyle() {
        connectionColourSubscription = NotificationToken(token: SAClaudeAppearanceChange.addObserver { [weak self] _ in
            guard let self = self else {
                return
            }
            self.applyConnectionColourChrome()
            let style = SAConnectionColourStyle.current(.standard)
            if style != self.chipConnectionColourStyle {
                self.chipConnectionColourStyle = style
                self.tabBar?.refresh()
            }
        })
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
        tabBarTitle = tabTitle
        tabBarItemDidChange()
        refreshNamePill()
    }

    func updateWindow(title: String, tabTitle: String, subtitle: String) {
        windowSubtitle = subtitle
        updateWindow(title: title, tabTitle: tabTitle)
        if window?.subtitle != subtitle { window?.subtitle = subtitle }
    }

    /// Reflect the connection this tab holds in the window chrome: the colour
    /// dot on the tab accessory, the SSL padlock, and the connection colour
    /// (see `applyConnectionColourChrome`).
    ///
    /// The single funnel for all three, called from
    /// `-[SPDatabaseDocument updateWindowTitle:]`. A `nil` colour means "no
    /// favourite colour, or not connected" and clears the dot and the colour.
    func updateWindowAccessory(color: NSColor?, isSSL: Bool) {
        favoriteColor = color
        tabBarIsSSL = isSSL
        tabAccessoryView.update(color: color, isSSL: isSSL)
        applyConnectionColourChrome()
        tabBarItemDidChange()
    }

    /// The favourite colour of this tab's chip: the favourite's `-tab` colour, `nil` when there is none.
    var tabBarColour: NSColor? {
        SPWindowTabAccessory.tabColour(for: favoriteColor)
    }

    /// Called by the tab bar for every window of the group it rebuilds. The native tab content keeps its
    /// selected style, though macOS's strip is hidden; it shows again only if a future macOS stops hosting the strip
    /// the way the bar hides it.
    func tabBarSelectionDidChange(isSelected: Bool) {
        tabAccessoryView.setSelected(isSelected)
    }

    /// The title, colour or SSL state of this tab changed: rebuild the chips of its group.
    private func tabBarItemDidChange() {
        tabBar?.refresh()
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

        // ⌘W and the tab bar refuse a tab with a sheet up, but a direct -close (quit, scripted closes) doesn't:
        // a sheet left attached keeps this window and the sheet alive after the tab is gone. End it as cancelled.
        if let window {
            while let sheet = window.attachedSheet {
                window.endSheet(sheet, returnCode: .abort)
                sheet.orderOut(nil)
            }
        }

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
