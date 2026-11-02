//
//  SAFieldPickerButton.swift
//  Sequel Ace
//
//  A searchable column display value for NSRuleEditor. It sends the same
//  represented node and target/action as the old menu item, so the controller
//  still owns replacing the criterion and preserving operators and arguments.
//

import AppKit
import SwiftUI

@objc public final class SAFieldPickerButton: NSPopUpButton, NSPopoverDelegate {
    private(set) var pickerPopover: NSPopover?
    private var dismissingEventTimestamp: TimeInterval?
    private var ruleEditorEnabledObservation: NSKeyValueObservation?

    @objc public var representedObject: Any? { selectedItem?.representedObject }

    @objc(initWithNames:nodes:selectedName:)
    public init(names: [String], nodes: [Any], selectedName: String) {
        super.init(frame: .zero, pullsDown: false)
        for (name, node) in zip(names, nodes) {
            addItem(withTitle: name)
            lastItem?.representedObject = ["node": node]
        }
        selectItem(withTitle: selectedName)
        controlSize = .small
        let titleFont = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        font = titleFont
        // Avoid AppKit's SwiftUI-backed menu measurement during rule layout.
        // Only the selected title is displayed; measuring that text directly
        // keeps sizing independent of the number of columns in the menu.
        let titleWidth = (selectedName as NSString).size(withAttributes: [.font: titleFont]).width
        setFrameSize(NSSize(width: min(max(ceil(titleWidth) + 32, 80), 220), height: 22))
        cell?.lineBreakMode = .byTruncatingMiddle
        toolTip = selectedName
        setAccessibilityLabel(NSLocalizedString("Filter Field", comment: "content filter : field selector accessibility label"))
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    public override var isEnabled: Bool {
        didSet {
            if !isEnabled { pickerPopover?.close() }
        }
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { pickerPopover?.close() }
    }

    public override func mouseDown(with event: NSEvent) {
        guard canChooseField else { return }
        if dismissingEventTimestamp == event.timestamp {
            dismissingEventTimestamp = nil
            return
        }
        togglePicker()
    }

    public override func performClick(_ sender: Any?) {
        guard canChooseField else { return }
        togglePicker()
    }

    public override func accessibilityPerformPress() -> Bool {
        guard canChooseField else { return false }
        togglePicker()
        return true
    }

    public override func keyDown(with event: NSEvent) {
        guard canChooseField else { return }
        switch event.charactersIgnoringModifiers {
        case " ", "\r", "\n", "\u{f700}", "\u{f701}":
            togglePicker()
        default:
            super.keyDown(with: event)
        }
    }

    private var canChooseField: Bool {
        isEnabled && (enclosingRuleEditor?.isEnabled ?? true)
    }

    private var enclosingRuleEditor: NSRuleEditor? {
        var ancestor = superview
        while let view = ancestor {
            if let editor = view as? NSRuleEditor { return editor }
            ancestor = view.superview
        }
        return nil
    }

    /// Shared picker behavior, fed directly from this control's column nodes.
    /// Unlike a database popup, item zero is a field, not a placeholder.
    func makePickerModel() -> SADatabasePickerModel {
        let model = SADatabasePickerModel(
            entries: itemArray.map { SADatabasePickerEntry(name: $0.title, section: 0) },
            commands: [], currentDatabase: titleOfSelectedItem, clearsSearchOnCancel: false)
        model.onChooseDatabase = { [weak self] name in
            guard let self, self.canChooseField, let item = self.item(withTitle: name) else { return }
            self.pickerPopover?.close()
            self.select(item)
            self.toolTip = name
            self.sendAction(self.action, to: self.target)
        }
        model.onCancel = { [weak self] in self?.pickerPopover?.close() }
        return model
    }

    private func togglePicker() {
        if let popover = pickerPopover, popover.isShown {
            popover.close()
            return
        }
        guard window != nil else { return }
        let model = makePickerModel()
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        let controller = NSHostingController(rootView: SADatabasePickerView(
            model: model,
            searchPlaceholder: NSLocalizedString("Search Fields", comment: "content filter : field selector search placeholder"),
            noMatchesTitle: NSLocalizedString("No Matching Fields", comment: "content filter : no fields match the search")))
        controller.sizingOptions = .preferredContentSize
        popover.contentViewController = controller
        pickerPopover = popover
        // The editor does not propagate its enabled state to embedded controls.
        // Observe only while presented; the selection guard also covers pending callbacks.
        ruleEditorEnabledObservation = enclosingRuleEditor?.observe(\.isEnabled, options: [.new]) { [weak self] editor, _ in
            if !editor.isEnabled { self?.pickerPopover?.close() }
        }
        highlight(true)
        popover.show(relativeTo: bounds, of: self, preferredEdge: isFlipped ? .maxY : .minY)
    }

    public func popoverDidClose(_ notification: Notification) {
        ruleEditorEnabledObservation = nil
        highlight(false)
        if let event = NSApp.currentEvent, event.type == .leftMouseDown,
           event.window === window,
           bounds.contains(convert(event.locationInWindow, from: nil)) {
            dismissingEventTimestamp = event.timestamp
        }
        pickerPopover = nil
    }
}
