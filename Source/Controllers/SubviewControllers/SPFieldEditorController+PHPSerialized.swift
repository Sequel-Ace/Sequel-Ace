//
//  SPFieldEditorController+PHPSerialized.swift
//  sequel-ace
//
//  Created by Codex on 2026-06-15.
//

import AppKit
import ObjectiveC

private enum PHPSerializedEditorAssociation {
    static var menuItem: UInt8 = 0
    static var sheet: UInt8 = 0
    static var outlineView: UInt8 = 0
    static var valueTextView: UInt8 = 0
    static var typePopup: UInt8 = 0
    static var selectionLabel: UInt8 = 0
    static var updateButton: UInt8 = 0
    static var addButton: UInt8 = 0
    static var deleteButton: UInt8 = 0
    static var rootEntry: UInt8 = 0
    static var selectedEntry: UInt8 = 0
    static var automaticallyOpened: UInt8 = 0
}

extension SPFieldEditorController: NSOutlineViewDataSource, NSOutlineViewDelegate {
    private var phpSerializedEditorMenuItem: NSMenuItem? {
        get { objc_getAssociatedObject(self, &PHPSerializedEditorAssociation.menuItem) as? NSMenuItem }
        set { objc_setAssociatedObject(self, &PHPSerializedEditorAssociation.menuItem, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    private var phpSerializedEditorSheet: NSPanel? {
        get { objc_getAssociatedObject(self, &PHPSerializedEditorAssociation.sheet) as? NSPanel }
        set { objc_setAssociatedObject(self, &PHPSerializedEditorAssociation.sheet, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    private var phpSerializedOutlineView: NSOutlineView? {
        get { objc_getAssociatedObject(self, &PHPSerializedEditorAssociation.outlineView) as? NSOutlineView }
        set { objc_setAssociatedObject(self, &PHPSerializedEditorAssociation.outlineView, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    private var phpSerializedValueTextView: NSTextView? {
        get { objc_getAssociatedObject(self, &PHPSerializedEditorAssociation.valueTextView) as? NSTextView }
        set { objc_setAssociatedObject(self, &PHPSerializedEditorAssociation.valueTextView, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    private var phpSerializedTypePopup: NSPopUpButton? {
        get { objc_getAssociatedObject(self, &PHPSerializedEditorAssociation.typePopup) as? NSPopUpButton }
        set { objc_setAssociatedObject(self, &PHPSerializedEditorAssociation.typePopup, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    private var phpSerializedSelectionLabel: NSTextField? {
        get { objc_getAssociatedObject(self, &PHPSerializedEditorAssociation.selectionLabel) as? NSTextField }
        set { objc_setAssociatedObject(self, &PHPSerializedEditorAssociation.selectionLabel, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    private var phpSerializedUpdateButton: NSButton? {
        get { objc_getAssociatedObject(self, &PHPSerializedEditorAssociation.updateButton) as? NSButton }
        set { objc_setAssociatedObject(self, &PHPSerializedEditorAssociation.updateButton, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    private var phpSerializedAddButton: NSButton? {
        get { objc_getAssociatedObject(self, &PHPSerializedEditorAssociation.addButton) as? NSButton }
        set { objc_setAssociatedObject(self, &PHPSerializedEditorAssociation.addButton, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    private var phpSerializedDeleteButton: NSButton? {
        get { objc_getAssociatedObject(self, &PHPSerializedEditorAssociation.deleteButton) as? NSButton }
        set { objc_setAssociatedObject(self, &PHPSerializedEditorAssociation.deleteButton, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    private var phpSerializedRootEntry: SAPHPSerializedEntry? {
        get { objc_getAssociatedObject(self, &PHPSerializedEditorAssociation.rootEntry) as? SAPHPSerializedEntry }
        set { objc_setAssociatedObject(self, &PHPSerializedEditorAssociation.rootEntry, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    private var phpSerializedSelectedEntry: SAPHPSerializedEntry? {
        get { objc_getAssociatedObject(self, &PHPSerializedEditorAssociation.selectedEntry) as? SAPHPSerializedEntry }
        set { objc_setAssociatedObject(self, &PHPSerializedEditorAssociation.selectedEntry, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    private var phpSerializedEditorAutomaticallyOpened: Bool {
        get { (objc_getAssociatedObject(self, &PHPSerializedEditorAssociation.automaticallyOpened) as? NSNumber)?.boolValue ?? false }
        set { objc_setAssociatedObject(self, &PHPSerializedEditorAssociation.automaticallyOpened, NSNumber(value: newValue), .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    private var phpSerializedEditTextView: NSTextView? {
        value(forKey: "editTextView") as? NSTextView
    }

    private var phpSerializedHexTextView: NSTextView? {
        value(forKey: "hexTextView") as? NSTextView
    }

    private var phpSerializedEditSheet: NSWindow? {
        value(forKey: "editSheet") as? NSWindow
    }

    private var phpSerializedEncoding: UInt {
        (value(forKey: "encoding") as? NSNumber)?.uintValue ?? String.Encoding.utf8.rawValue
    }

    private var phpSerializedIsEditable: Bool {
        (value(forKey: "isEditable") as? NSNumber)?.boolValue ?? false
    }

    private var phpSerializedIsJSON: Bool {
        (value(forKey: "isJSON") as? NSNumber)?.boolValue ?? false
    }

    private var phpSerializedIsGeometry: Bool {
        (value(forKey: "isGeometry") as? NSNumber)?.boolValue ?? false
    }

    private var currentPHPSerializedText: String {
        let text = phpSerializedEditTextView?.string ?? ""
        return text.isEmpty ? "" : text
    }

    @objc(setupPHPSerializedEditorMenuItemInMenu:)
    func setupPHPSerializedEditorMenuItem(in menu: NSMenu) {
        menu.addItem(.separator())

        let menuItem = NSMenuItem(
            title: NSLocalizedString("Edit PHP Serialized Data as Tree", comment: "PHP serialized data editor menu item"),
            action: #selector(openPHPSerializedEditor(_:)),
            keyEquivalent: ""
        )
        menuItem.target = self
        menuItem.isEnabled = false

        phpSerializedEditorMenuItem = menuItem
        menu.addItem(menuItem)
    }

    @objc(resetPHPSerializedEditorState)
    func resetPHPSerializedEditorState() {
        phpSerializedRootEntry = nil
        phpSerializedSelectedEntry = nil
        phpSerializedEditorAutomaticallyOpened = false
        phpSerializedEditorMenuItem?.isEnabled = false
    }

    private func setPHPSerializedSheetEditData(_ value: String) {
        setValue(value, forKey: "sheetEditData")
    }

    private func setPHPSerializedEditTextViewWasChanged(_ changed: Bool) {
        setValue(changed, forKey: "editTextViewWasChanged")
    }

    private func showPHPSerializedTooltip(_ message: String) {
        SPTooltip.show(with: message)
    }

    private func phpSerializedEditorFont() -> NSFont? {
        let selector = NSSelectorFromString("selectFont")
        guard responds(to: selector), let font = perform(selector)?.takeUnretainedValue() as? NSFont else {
            return NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        }

        return font
    }

    private func populatePHPSerializedEditorFromCurrentText(showingError showError: Bool) -> Bool {
        var errorMessage: NSString?
        guard let rootValue = SAPHPSerializedParser.parseString(currentPHPSerializedText, encoding: phpSerializedEncoding, errorMessage: &errorMessage) else {
            if showError {
                showPHPSerializedTooltip(errorMessage as String? ?? NSLocalizedString("The current field does not contain valid PHP serialized data.", comment: "PHP serialized editor invalid tooltip"))
            }
            return false
        }

        let rootEntry = SAPHPSerializedEntry()
        rootEntry.key = "root"
        rootEntry.keyIsInteger = false
        rootEntry.value = rootValue

        assignPHPSerializedParent(for: rootEntry)
        phpSerializedRootEntry = rootEntry
        phpSerializedSelectedEntry = rootEntry
        return true
    }

    private func assignPHPSerializedParent(for entry: SAPHPSerializedEntry) {
        for case let child as SAPHPSerializedEntry in entry.value.children {
            child.parent = entry
            assignPHPSerializedParent(for: child)
        }
    }

    @objc(refreshPHPSerializedEditorAvailability)
    func refreshPHPSerializedEditorAvailability() {
        var errorMessage: NSString?
        let value = SAPHPSerializedParser.parseString(currentPHPSerializedText, encoding: phpSerializedEncoding, errorMessage: &errorMessage)
        phpSerializedEditorMenuItem?.isEnabled = value != nil && phpSerializedIsEditable && !phpSerializedIsJSON && !phpSerializedIsGeometry
    }

    @objc(openPHPSerializedEditorIfCurrentTextIsStructured)
    func openPHPSerializedEditorIfCurrentTextIsStructured() {
        guard !phpSerializedEditorAutomaticallyOpened,
              phpSerializedEditorMenuItem?.isEnabled == true
        else {
            return
        }

        var errorMessage: NSString?
        guard let value = SAPHPSerializedParser.parseString(currentPHPSerializedText, encoding: phpSerializedEncoding, errorMessage: &errorMessage),
              value.isContainer() || value.type == .customSerialized
        else {
            return
        }

        phpSerializedEditorAutomaticallyOpened = true
        openPHPSerializedEditor(self)
    }

    @objc(openPHPSerializedEditor:)
    func openPHPSerializedEditor(_ sender: Any?) {
        guard populatePHPSerializedEditorFromCurrentText(showingError: true) else {
            return
        }

        buildPHPSerializedEditorSheetIfNeeded()
        phpSerializedOutlineView?.reloadData()
        phpSerializedOutlineView?.expandItem(phpSerializedRootEntry, expandChildren: true)
        phpSerializedOutlineView?.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        if let rootEntry = phpSerializedRootEntry {
            updatePHPSerializedInspector(for: rootEntry)
        }

        guard phpSerializedEditorSheet?.isSheet != true,
              let editSheet = phpSerializedEditSheet,
              let editorSheet = phpSerializedEditorSheet
        else {
            return
        }

        editSheet.beginSheet(editorSheet, completionHandler: nil)
    }

    private func buildPHPSerializedEditorSheetIfNeeded() {
        guard phpSerializedEditorSheet == nil else {
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 520),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = NSLocalizedString("PHP Serialized Data", comment: "PHP serialized editor sheet title")
        panel.minSize = NSSize(width: 650, height: 420)
        phpSerializedEditorSheet = panel

        guard let contentView = panel.contentView else {
            return
        }

        let outlineScrollView = NSScrollView(frame: .zero)
        outlineScrollView.translatesAutoresizingMaskIntoConstraints = false
        outlineScrollView.hasVerticalScroller = true
        outlineScrollView.hasHorizontalScroller = true
        outlineScrollView.borderType = .bezelBorder

        let outlineView = NSOutlineView(frame: .zero)
        let keyColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("key"))
        keyColumn.title = NSLocalizedString("Key", comment: "PHP serialized editor key column")
        keyColumn.width = 170
        let typeColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("type"))
        typeColumn.title = NSLocalizedString("Type", comment: "PHP serialized editor type column")
        typeColumn.width = 130
        let valueColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("value"))
        valueColumn.title = NSLocalizedString("Value", comment: "PHP serialized editor value column")
        valueColumn.width = 260

        outlineView.addTableColumn(keyColumn)
        outlineView.addTableColumn(typeColumn)
        outlineView.addTableColumn(valueColumn)
        outlineView.outlineTableColumn = keyColumn
        outlineView.delegate = self
        outlineView.dataSource = self
        outlineView.usesAlternatingRowBackgroundColors = true
        outlineView.allowsColumnResizing = true
        outlineView.allowsMultipleSelection = false
        outlineScrollView.documentView = outlineView
        phpSerializedOutlineView = outlineView

        let inspectorView = NSView(frame: .zero)
        inspectorView.translatesAutoresizingMaskIntoConstraints = false

        let selectionLabel = NSTextField(wrappingLabelWithString: "")
        selectionLabel.translatesAutoresizingMaskIntoConstraints = false
        phpSerializedSelectionLabel = selectionLabel

        let typePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        typePopup.translatesAutoresizingMaskIntoConstraints = false
        typePopup.addItems(withTitles: [
            NSLocalizedString("String", comment: "PHP serialized editor string type"),
            NSLocalizedString("Integer", comment: "PHP serialized editor integer type"),
            NSLocalizedString("Float", comment: "PHP serialized editor float type"),
            NSLocalizedString("Boolean", comment: "PHP serialized editor boolean type"),
            NSLocalizedString("Array", comment: "PHP serialized editor array type"),
            NSLocalizedString("Null", comment: "PHP serialized editor null type")
        ])
        phpSerializedTypePopup = typePopup

        let valueScrollView = NSScrollView(frame: .zero)
        valueScrollView.translatesAutoresizingMaskIntoConstraints = false
        valueScrollView.hasVerticalScroller = true
        valueScrollView.borderType = .bezelBorder

        let valueTextView = NSTextView(frame: .zero)
        valueTextView.isRichText = false
        valueTextView.usesFindBar = true
        valueTextView.isAutomaticDashSubstitutionEnabled = false
        valueTextView.isAutomaticQuoteSubstitutionEnabled = false
        valueTextView.font = phpSerializedEditorFont()
        valueScrollView.documentView = valueTextView
        phpSerializedValueTextView = valueTextView

        let updateButton = NSButton(
            title: NSLocalizedString("Update Selected", comment: "PHP serialized editor update selected button"),
            target: self,
            action: #selector(updatePHPSerializedSelectedValue(_:))
        )
        updateButton.translatesAutoresizingMaskIntoConstraints = false
        phpSerializedUpdateButton = updateButton

        let addButton = NSButton(
            title: NSLocalizedString("Add Child", comment: "PHP serialized editor add child button"),
            target: self,
            action: #selector(addPHPSerializedChild(_:))
        )
        addButton.translatesAutoresizingMaskIntoConstraints = false
        phpSerializedAddButton = addButton

        let deleteButton = NSButton(
            title: NSLocalizedString("Delete", comment: "PHP serialized editor delete button"),
            target: self,
            action: #selector(deletePHPSerializedEntry(_:))
        )
        deleteButton.translatesAutoresizingMaskIntoConstraints = false
        phpSerializedDeleteButton = deleteButton

        let cancelButton = NSButton(
            title: NSLocalizedString("Cancel", comment: "cancel button"),
            target: self,
            action: #selector(cancelPHPSerializedEditor(_:))
        )
        cancelButton.translatesAutoresizingMaskIntoConstraints = false

        let applyButton = NSButton(
            title: NSLocalizedString("Apply to Field", comment: "PHP serialized editor apply button"),
            target: self,
            action: #selector(applyPHPSerializedEditor(_:))
        )
        applyButton.translatesAutoresizingMaskIntoConstraints = false
        applyButton.keyEquivalent = "\r"

        contentView.addSubview(outlineScrollView)
        contentView.addSubview(inspectorView)
        contentView.addSubview(addButton)
        contentView.addSubview(deleteButton)
        contentView.addSubview(cancelButton)
        contentView.addSubview(applyButton)

        inspectorView.addSubview(selectionLabel)
        inspectorView.addSubview(typePopup)
        inspectorView.addSubview(valueScrollView)
        inspectorView.addSubview(updateButton)

        NSLayoutConstraint.activate([
            outlineScrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 14),
            outlineScrollView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
            outlineScrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -58),
            outlineScrollView.widthAnchor.constraint(equalToConstant: 470),

            inspectorView.leadingAnchor.constraint(equalTo: outlineScrollView.trailingAnchor, constant: 12),
            inspectorView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14),
            inspectorView.topAnchor.constraint(equalTo: outlineScrollView.topAnchor),
            inspectorView.bottomAnchor.constraint(equalTo: outlineScrollView.bottomAnchor),

            selectionLabel.leadingAnchor.constraint(equalTo: inspectorView.leadingAnchor),
            selectionLabel.trailingAnchor.constraint(equalTo: inspectorView.trailingAnchor),
            selectionLabel.topAnchor.constraint(equalTo: inspectorView.topAnchor),

            typePopup.leadingAnchor.constraint(equalTo: inspectorView.leadingAnchor),
            typePopup.topAnchor.constraint(equalTo: selectionLabel.bottomAnchor, constant: 12),
            typePopup.widthAnchor.constraint(equalToConstant: 160),

            valueScrollView.leadingAnchor.constraint(equalTo: inspectorView.leadingAnchor),
            valueScrollView.trailingAnchor.constraint(equalTo: inspectorView.trailingAnchor),
            valueScrollView.topAnchor.constraint(equalTo: typePopup.bottomAnchor, constant: 10),
            valueScrollView.bottomAnchor.constraint(equalTo: updateButton.topAnchor, constant: -10),

            updateButton.trailingAnchor.constraint(equalTo: inspectorView.trailingAnchor),
            updateButton.bottomAnchor.constraint(equalTo: inspectorView.bottomAnchor),

            addButton.leadingAnchor.constraint(equalTo: outlineScrollView.leadingAnchor),
            addButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -14),
            deleteButton.leadingAnchor.constraint(equalTo: addButton.trailingAnchor, constant: 8),
            deleteButton.centerYAnchor.constraint(equalTo: addButton.centerYAnchor),

            applyButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14),
            applyButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -14),
            cancelButton.trailingAnchor.constraint(equalTo: applyButton.leadingAnchor, constant: -8),
            cancelButton.centerYAnchor.constraint(equalTo: applyButton.centerYAnchor)
        ])
    }

    private func keyLabel(for entry: SAPHPSerializedEntry) -> String {
        if entry === phpSerializedRootEntry {
            return "root"
        }
        if entry.keyIsInteger {
            return "[\(String(describing: entry.key ?? ""))]"
        }

        return entry.key.map { String(describing: $0) } ?? ""
    }

    private func updatePHPSerializedInspector(for entry: SAPHPSerializedEntry) {
        phpSerializedSelectedEntry = entry
        let value = entry.value!
        phpSerializedSelectionLabel?.stringValue = "\(keyLabel(for: entry))  \(value.typeLabel())"

        let canEditScalar = value.isScalarEditable()
        let canEditStructure = phpSerializedIsEditable && !(phpSerializedRootEntry?.value.containsReference() ?? true)
        phpSerializedTypePopup?.isEnabled = canEditScalar && phpSerializedIsEditable
        phpSerializedValueTextView?.isEditable = canEditScalar && phpSerializedIsEditable
        phpSerializedUpdateButton?.isEnabled = canEditScalar && phpSerializedIsEditable
        phpSerializedAddButton?.isEnabled = value.isContainer() && canEditStructure
        phpSerializedDeleteButton?.isEnabled = entry !== phpSerializedRootEntry && canEditStructure

        switch value.type {
        case .string:
            phpSerializedTypePopup?.selectItem(withTitle: NSLocalizedString("String", comment: "PHP serialized editor string type"))
        case .integer:
            phpSerializedTypePopup?.selectItem(withTitle: NSLocalizedString("Integer", comment: "PHP serialized editor integer type"))
        case .double:
            phpSerializedTypePopup?.selectItem(withTitle: NSLocalizedString("Float", comment: "PHP serialized editor float type"))
        case .boolean:
            phpSerializedTypePopup?.selectItem(withTitle: NSLocalizedString("Boolean", comment: "PHP serialized editor boolean type"))
        case .array:
            phpSerializedTypePopup?.selectItem(withTitle: NSLocalizedString("Array", comment: "PHP serialized editor array type"))
        case .null:
            phpSerializedTypePopup?.selectItem(withTitle: NSLocalizedString("Null", comment: "PHP serialized editor null type"))
        default:
            phpSerializedTypePopup?.selectItem(at: 0)
        }

        if canEditScalar || value.type == .customSerialized || value.type == .enum || value.type == .reference {
            phpSerializedValueTextView?.string = value.displayValue()
        } else {
            phpSerializedValueTextView?.string = NSLocalizedString("Select a scalar value to edit it. Arrays and objects can be expanded in the tree.", comment: "PHP serialized editor container inspector text")
        }
    }

    private func commitPHPSerializedSelectedValue(showingError showError: Bool) -> Bool {
        guard let entry = phpSerializedSelectedEntry,
              entry.value.isScalarEditable()
        else {
            return true
        }

        let selectedType = phpSerializedTypePopup?.selectedItem?.title ?? ""
        let rawValue = phpSerializedValueTextView?.string ?? ""

        if selectedType == NSLocalizedString("String", comment: "PHP serialized editor string type") {
            entry.value.type = .string
            entry.value.scalarValue = rawValue
        } else if selectedType == NSLocalizedString("Integer", comment: "PHP serialized editor integer type") {
            guard let trimmedValue = SAPHPSerializedValue.normalizedIntegerString(fromEditedString: rawValue) else {
                if showError {
                    showPHPSerializedTooltip(NSLocalizedString("Integer values may only contain digits and an optional leading minus sign.", comment: "PHP serialized editor integer validation error"))
                }
                return false
            }
            entry.value.type = .integer
            entry.value.scalarValue = trimmedValue
        } else if selectedType == NSLocalizedString("Float", comment: "PHP serialized editor float type") {
            let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedValue.isEmpty else {
                if showError {
                    showPHPSerializedTooltip(NSLocalizedString("Float values cannot be empty.", comment: "PHP serialized editor float validation error"))
                }
                return false
            }
            guard SAPHPSerializedValue.isValidPHPFloatString(trimmedValue) else {
                if showError {
                    showPHPSerializedTooltip(NSLocalizedString("Float values must be a valid number, INF, -INF, or NAN.", comment: "PHP serialized editor float validation error"))
                }
                return false
            }
            entry.value.type = .double
            entry.value.scalarValue = trimmedValue
        } else if selectedType == NSLocalizedString("Boolean", comment: "PHP serialized editor boolean type") {
            let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if normalized == "1" || normalized == "true" || normalized == "yes" {
                entry.value.scalarValue = "1"
            } else if normalized == "0" || normalized == "false" || normalized == "no" || normalized.isEmpty {
                entry.value.scalarValue = "0"
            } else {
                if showError {
                    showPHPSerializedTooltip(NSLocalizedString("Boolean values must be true/false or 1/0.", comment: "PHP serialized editor boolean validation error"))
                }
                return false
            }
            entry.value.type = .boolean
        } else if selectedType == NSLocalizedString("Array", comment: "PHP serialized editor array type") {
            if phpSerializedRootEntry?.value.containsReference() == true {
                if showError {
                    showPHPSerializedTooltip(NSLocalizedString("Cannot change serialized structure while PHP references are present.", comment: "PHP serialized editor reference structure validation error"))
                }
                return false
            }
            entry.value.type = .array
            entry.value.scalarValue = ""
            entry.value.serializedClassName = nil
            entry.value.referenceType = nil
            entry.value.children.removeAllObjects()
        } else {
            entry.value.type = .null
            entry.value.scalarValue = ""
        }

        return true
    }

    @objc(updatePHPSerializedSelectedValue:)
    func updatePHPSerializedSelectedValue(_ sender: Any?) {
        guard commitPHPSerializedSelectedValue(showingError: true) else {
            return
        }

        phpSerializedOutlineView?.reloadData()
        if let selectedEntry = phpSerializedSelectedEntry {
            updatePHPSerializedInspector(for: selectedEntry)
        }
    }

    @objc(addPHPSerializedChild:)
    func addPHPSerializedChild(_ sender: Any?) {
        guard let selectedEntry = phpSerializedSelectedEntry,
              selectedEntry.value.isContainer()
        else {
            return
        }
        if phpSerializedRootEntry?.value.containsReference() == true {
            showPHPSerializedTooltip(NSLocalizedString("Cannot add entries while PHP references are present.", comment: "PHP serialized editor reference add validation error"))
            return
        }

        let newEntry = SAPHPSerializedEntry()
        newEntry.parent = selectedEntry
        newEntry.value = SAPHPSerializedValue.value(with: .string)
        newEntry.value.scalarValue = ""

        if selectedEntry.value.type == .array {
            newEntry.keyIsInteger = true
            newEntry.key = selectedEntry.value.nextAvailableArrayKey()
        } else {
            newEntry.keyIsInteger = false
            newEntry.key = selectedEntry.value.uniqueObjectPropertyName()
        }

        selectedEntry.value.children.add(newEntry)
        phpSerializedOutlineView?.reloadData()
        phpSerializedOutlineView?.expandItem(selectedEntry)
        let row = phpSerializedOutlineView?.row(forItem: newEntry) ?? -1
        if row >= 0 {
            phpSerializedOutlineView?.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
    }

    @objc(deletePHPSerializedEntry:)
    func deletePHPSerializedEntry(_ sender: Any?) {
        guard let selectedEntry = phpSerializedSelectedEntry,
              selectedEntry !== phpSerializedRootEntry,
              let parent = selectedEntry.parent
        else {
            return
        }
        if phpSerializedRootEntry?.value.containsReference() == true {
            showPHPSerializedTooltip(NSLocalizedString("Cannot delete entries while PHP references are present.", comment: "PHP serialized editor reference delete validation error"))
            return
        }

        parent.value.children.remove(selectedEntry)
        phpSerializedSelectedEntry = parent
        phpSerializedOutlineView?.reloadData()
        let parentRow = phpSerializedOutlineView?.row(forItem: parent) ?? -1
        if parentRow >= 0 {
            phpSerializedOutlineView?.selectRowIndexes(IndexSet(integer: parentRow), byExtendingSelection: false)
        }
    }

    @objc(applyPHPSerializedEditor:)
    func applyPHPSerializedEditor(_ sender: Any?) {
        guard commitPHPSerializedSelectedValue(showingError: true) else {
            return
        }

        var errorMessage: NSString?
        guard let serialized = phpSerializedRootEntry?.value.serializedString(errorMessage: &errorMessage) else {
            showPHPSerializedTooltip(errorMessage as String? ?? NSLocalizedString("Unable to serialize PHP data.", comment: "PHP serialized editor output error"))
            return
        }

        phpSerializedEditTextView?.string = serialized
        setPHPSerializedSheetEditData(serialized)
        setPHPSerializedEditTextViewWasChanged(true)
        phpSerializedHexTextView?.string = ""
        refreshPHPSerializedEditorAvailability()

        if let editSheet = phpSerializedEditSheet,
           let editorSheet = phpSerializedEditorSheet {
            editSheet.endSheet(editorSheet, returnCode: .OK)
            editorSheet.orderOut(self)
        }
    }

    @objc(cancelPHPSerializedEditor:)
    func cancelPHPSerializedEditor(_ sender: Any?) {
        if let editSheet = phpSerializedEditSheet,
           let editorSheet = phpSerializedEditorSheet {
            editSheet.endSheet(editorSheet, returnCode: .cancel)
            editorSheet.orderOut(self)
        }
    }

    public func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard outlineView === phpSerializedOutlineView else {
            return 0
        }
        guard let item else {
            return phpSerializedRootEntry == nil ? 0 : 1
        }
        guard let entry = item as? SAPHPSerializedEntry else {
            return 0
        }

        return entry.value.children.count
    }

    public func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        guard outlineView === phpSerializedOutlineView else {
            return NSNull()
        }
        guard let item else {
            return phpSerializedRootEntry as Any
        }
        guard let entry = item as? SAPHPSerializedEntry else {
            return NSNull()
        }

        return entry.value.children.object(at: index)
    }

    public func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard outlineView === phpSerializedOutlineView,
              let entry = item as? SAPHPSerializedEntry
        else {
            return false
        }

        return entry.value.children.count > 0
    }

    public func outlineView(_ outlineView: NSOutlineView, objectValueFor tableColumn: NSTableColumn?, byItem item: Any?) -> Any? {
        guard outlineView === phpSerializedOutlineView,
              let entry = item as? SAPHPSerializedEntry
        else {
            return ""
        }

        let identifier = tableColumn?.identifier.rawValue ?? ""
        if identifier == "key" {
            return keyLabel(for: entry)
        }
        if identifier == "type" {
            return entry.value.typeLabel()
        }
        if identifier == "value" {
            return entry.value.displayValue()
        }
        return ""
    }

    public func selectionShouldChange(in outlineView: NSOutlineView) -> Bool {
        guard outlineView === phpSerializedOutlineView else {
            return true
        }

        return commitPHPSerializedSelectedValue(showingError: true)
    }

    public func outlineViewSelectionDidChange(_ notification: Notification) {
        guard notification.object as? NSOutlineView === phpSerializedOutlineView else {
            return
        }

        let row = phpSerializedOutlineView?.selectedRow ?? -1
        let entry = row >= 0 ? phpSerializedOutlineView?.item(atRow: row) as? SAPHPSerializedEntry : phpSerializedRootEntry
        if let entry {
            updatePHPSerializedInspector(for: entry)
        }
    }
}
