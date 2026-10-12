//
//  SADatabasePopUpButton.swift
//  Sequel Ace
//
//  The toolbar's "choose database" popup. It is still a plain
//  NSPopUpButton to the rest of the app — SPDatabaseDocument and
//  SADatabaseListManager keep selecting and adding items exactly as
//  before, and the toolbar's overflow menu still uses the native menu —
//  but a click opens the searchable `SADatabasePickerView` in a popover
//  instead of the long menu.
//

import AppKit
import SwiftUI

/// Instantiated from DBView.xib by its module-qualified name, so no
/// explicit `@objc(...)` runtime name — that would stop the nib finding it.
final class SADatabasePopUpButton: NSPopUpButton, NSPopoverDelegate {

    private var pickerPopover: NSPopover?
    /// Timestamp of the click that dismissed the transient popover. That
    /// same mouse-down then reaches the button; without this it would
    /// immediately reopen the picker instead of toggling it closed.
    private var dismissingEventTimestamp: TimeInterval?

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        if let timestamp = dismissingEventTimestamp, timestamp == event.timestamp {
            dismissingEventTimestamp = nil
            return
        }
        togglePicker()
    }

    /// Keyboard activation (Space with full keyboard access).
    override func performClick(_ sender: Any?) {
        guard isEnabled else { return }
        togglePicker()
    }

    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        togglePicker()
        return true
    }

    private func togglePicker() {
        if let popover = pickerPopover, popover.isShown {
            popover.close()
        } else {
            showPicker()
        }
    }

    private func showPicker() {
        let currentDatabase = indexOfSelectedItem > 0 ? titleOfSelectedItem : nil
        let model = SADatabasePickerModel(menu: menu, currentDatabase: currentDatabase)

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self

        model.onChooseDatabase = { [weak self, weak popover] name in
            popover?.close()
            self?.chooseDatabase(named: name)
        }
        model.onCommand = { [weak self, weak popover] command in
            popover?.close()
            // Let the popover give key status back to the document window
            // first: the commands are nil-targeted and dispatch through its
            // responder chain, as they do from the menu.
            DispatchQueue.main.async {
                self?.performCommand(command)
            }
        }
        model.onCancel = { [weak popover] in
            popover?.close()
        }

        let hostingController = NSHostingController(rootView: SADatabasePickerView(model: model))
        hostingController.sizingOptions = .preferredContentSize
        popover.contentViewController = hostingController

        pickerPopover = popover
        highlight(true)
        popover.show(relativeTo: bounds, of: self, preferredEdge: isFlipped ? .maxY : .minY)
    }

    /// Same effect as picking the item from the menu: select it, then send
    /// the popup's action (`-[SPDatabaseDocument chooseDatabase:]`).
    private func chooseDatabase(named name: String) {
        // The menu may have been rebuilt while the picker was open.
        guard let item = item(withTitle: name), let index = menu?.index(of: item), index > 0 else { return }
        selectItem(at: index)
        sendAction(action, to: target)
    }

    private func performCommand(_ command: SADatabasePickerCommand) {
        guard let menu,
              let index = menu.items.firstIndex(where: {
                  $0.tag == SADatabaseListManager.commandMenuItemTag && $0.title == command.title
              }) else { return }
        menu.performActionForItem(at: index)
    }

    // MARK: NSPopoverDelegate

    func popoverDidClose(_ notification: Notification) {
        highlight(false)
        if let event = NSApp.currentEvent,
           event.type == .leftMouseDown,
           event.window === window,
           bounds.contains(convert(event.locationInWindow, from: nil)) {
            dismissingEventTimestamp = event.timestamp
        }
        pickerPopover = nil
    }
}
