//
//  SAPinnedTableGroupsController.swift
//  Sequel Ace
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//
//  More info at <https://github.com/Sequel-Ace/Sequel-Ace>
//

import AppKit

/// Builds the pin menus of the table list and runs their actions for the groups of
/// pinned tables: pin globally or into a group, create, rename, collapse and delete
/// groups, move tables between groups and take them out of one.
///
/// `SPTablesList` owns one instance and only forwards to it: it hands over the
/// selected tables when the menus are configured and refreshes the list when
/// `onChange` fires.
@objc final class SAPinnedTableGroupsController: NSObject {

    private let manager: SQLitePinnedTableManager
    private var hostName = ""
    private var databaseName = ""
    private var tableNames: [String] = []

    /// Called after a change to the pins or groups so the list can be rebuilt.
    @objc var onChange: (() -> Void)?

    @objc init(manager: SQLitePinnedTableManager) {
        self.manager = manager
        super.init()
    }

    // MARK: - Menus

    /// Rebuilds the submenu of each pin menu item for the selected tables.
    ///
    /// - Parameters:
    ///   - menuItems: The pin items of the Table menu and of the context menu.
    ///   - tableNames: The selected tables and views.
    ///   - connectionIdentifier: The key the pins of this connection are stored under.
    ///   - databaseName: The selected database.
    @objc(configureMenuItems:tableNames:connectionIdentifier:databaseName:)
    func configure(menuItems: [NSMenuItem], tableNames: [String], connectionIdentifier: String, databaseName: String) {
        guard tableNames.isNotEmpty else {
            return
        }
        hostName = connectionIdentifier
        self.databaseName = databaseName
        self.tableNames = tableNames

        for menuItem in menuItems {
            menuItem.submenu = makePinMenu()
        }
    }

    private func makePinMenu() -> NSMenu {
        let groupNames = manager.pinnedTableGroupNames(hostName: hostName, databaseName: databaseName)
        let currentGroups = tableNames.map { manager.groupNameForPinnedTable(hostName: hostName, databaseName: databaseName, tableName: $0) }
        let allTablesPinned = currentGroups.allSatisfy { $0 != nil }
        let allTablesInAGroup = allTablesPinned && currentGroups.allSatisfy { ($0 ?? "").isNotEmpty }

        let menu = NSMenu(title: "")
        menu.autoenablesItems = false

        addItem(to: menu, title: NSLocalizedString("Pin Globally", comment: "Table list pin menu: pin the selected tables in the global pinned section"), action: #selector(pinGlobally(_:)))

        let pinToGroupItem = NSMenuItem(title: NSLocalizedString("Pin to Group", comment: "Table list pin menu: submenu listing the groups the selected tables can be pinned to"), action: nil, keyEquivalent: "")
        let groupsMenu = NSMenu(title: pinToGroupItem.title)
        for groupName in groupNames {
            addItem(to: groupsMenu, title: groupName, action: #selector(pinToGroup(_:)), representedObject: groupName)
        }
        pinToGroupItem.submenu = groupsMenu
        pinToGroupItem.isEnabled = groupNames.isNotEmpty
        menu.addItem(pinToGroupItem)

        addItem(to: menu, title: NSLocalizedString("New Pinned Group…", comment: "Table list pin menu: ask for a name, then pin the selected tables in a new group"), action: #selector(pinToNewGroup(_:)))

        if allTablesPinned {
            menu.addItem(.separator())
            addItem(to: menu, title: NSLocalizedString("Unpin", comment: "Table list pin menu: stop pinning the selected tables"), action: #selector(unpin(_:)))
            if allTablesInAGroup {
                addItem(to: menu, title: NSLocalizedString("Remove from Group", comment: "Table list pin menu: take the selected tables out of their group; they stay pinned in the global section"), action: #selector(removeFromGroup(_:)))
            }
        }

        let manageItem = NSMenuItem(title: NSLocalizedString("Manage Pinned Groups", comment: "Table list pin menu: submenu to rename, collapse or delete a group of pinned tables"), action: nil, keyEquivalent: "")
        let manageMenu = NSMenu(title: manageItem.title)
        for groupName in groupNames {
            let groupItem = NSMenuItem(title: groupName, action: nil, keyEquivalent: "")
            let actionsMenu = NSMenu(title: groupName)
            addItem(to: actionsMenu, title: NSLocalizedString("Rename…", comment: "Table list pin menu: rename a group of pinned tables"), action: #selector(renameGroup(_:)), representedObject: groupName)
            let isCollapsed = manager.isPinnedTableGroupCollapsed(hostName: hostName, databaseName: databaseName, groupName: groupName)
            let toggleTitle = isCollapsed
                ? NSLocalizedString("Expand", comment: "Table list pin menu: show the tables of a collapsed group of pinned tables")
                : NSLocalizedString("Collapse", comment: "Table list pin menu: hide the tables of a group of pinned tables")
            addItem(to: actionsMenu, title: toggleTitle, action: #selector(toggleCollapsed(_:)), representedObject: groupName)
            actionsMenu.addItem(.separator())
            addItem(to: actionsMenu, title: NSLocalizedString("Delete Group", comment: "Table list pin menu: delete a group of pinned tables; its tables stay pinned in the global section"), action: #selector(deleteGroup(_:)), representedObject: groupName)
            groupItem.submenu = actionsMenu
            manageMenu.addItem(groupItem)
        }
        manageItem.submenu = manageMenu
        manageItem.isEnabled = groupNames.isNotEmpty
        menu.addItem(manageItem)
        return menu
    }

    @discardableResult
    private func addItem(to menu: NSMenu, title: String, action: Selector, representedObject: String? = nil) -> NSMenuItem {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = representedObject
        return item
    }

    // MARK: - Header rows

    /// The title of the header row of the global pinned section (empty group name) or of a group.
    @objc(headerTitleForGroupName:pinnedHeader:)
    static func headerTitle(forGroupName groupName: String, pinnedHeader: String) -> String {
        SAPinnedTableGroupPlanner.headerTitle(pinnedHeader: pinnedHeader, groupName: groupName)
    }

    /// Whether a title is the pinned header of the global section or of a group. Only
    /// meaningful for a row that has no table type; a table can be called the same.
    @objc(isPinnedHeaderTitle:pinnedHeader:)
    static func isPinnedHeader(title: String, pinnedHeader: String) -> Bool {
        title == pinnedHeader || SAPinnedTableGroupPlanner.groupName(fromHeaderTitle: title, pinnedHeader: pinnedHeader) != nil
    }

    /// Collapses or expands the group of a header row of the table list.
    ///
    /// - Parameters:
    ///   - title: The title of the row.
    ///   - pinnedHeader: The localized "PINNED" header the group headers start with.
    ///   - connectionIdentifier: The key the pins of this connection are stored under.
    ///   - databaseName: The selected database.
    /// - Returns: `true` when the title was a group header. The caller only asks for
    ///   rows that are headers, never for a table that happens to be called like one.
    @objc(toggleCollapsedForHeaderTitle:pinnedHeader:connectionIdentifier:databaseName:)
    @discardableResult
    func toggleCollapsed(forHeaderTitle title: String, pinnedHeader: String, connectionIdentifier: String, databaseName: String) -> Bool {
        guard let groupName = SAPinnedTableGroupPlanner.groupName(fromHeaderTitle: title, pinnedHeader: pinnedHeader) else {
            return false
        }
        let isCollapsed = manager.isPinnedTableGroupCollapsed(hostName: connectionIdentifier, databaseName: databaseName, groupName: groupName)
        manager.setPinnedTableGroupCollapsed(hostName: connectionIdentifier, databaseName: databaseName, groupName: groupName, isCollapsed: !isCollapsed)
        onChange?()
        return true
    }

    // MARK: - Actions

    @objc private func pinGlobally(_ sender: NSMenuItem) {
        move(tableNames, toGroup: "")
    }

    @objc private func pinToGroup(_ sender: NSMenuItem) {
        guard let groupName = sender.representedObject as? String else { return }
        move(tableNames, toGroup: groupName)
    }

    @objc private func pinToNewGroup(_ sender: NSMenuItem) {
        guard let groupName = promptForGroupName(
            title: NSLocalizedString("New Pinned Group", comment: "Title of the dialog asking for the name of a new group of pinned tables"),
            message: NSLocalizedString("Enter a name for the pinned-table group.", comment: "Message of the dialog asking for the name of a new group of pinned tables"),
            confirmTitle: NSLocalizedString("Create", comment: "Button creating a new group of pinned tables"),
            initialName: ""
        ) else { return }
        move(tableNames, toGroup: groupName)
    }

    @objc private func removeFromGroup(_ sender: NSMenuItem) {
        move(tableNames, toGroup: "")
    }

    @objc private func unpin(_ sender: NSMenuItem) {
        for tableName in tableNames {
            manager.unpinTable(hostName: hostName, databaseName: databaseName, tableToUnpin: tableName)
        }
        onChange?()
    }

    @objc private func renameGroup(_ sender: NSMenuItem) {
        guard let groupName = sender.representedObject as? String,
              let newName = promptForGroupName(
                title: NSLocalizedString("Rename Pinned Group", comment: "Title of the dialog asking for the new name of a group of pinned tables"),
                message: NSLocalizedString("Enter a new name for the pinned-table group.", comment: "Message of the dialog asking for the new name of a group of pinned tables"),
                confirmTitle: NSLocalizedString("Rename", comment: "Button renaming a group of pinned tables"),
                initialName: groupName
              ) else { return }

        let result = manager.renamePinnedTableGroup(hostName: hostName, databaseName: databaseName, groupName: groupName, toGroupName: newName)
        if result != .renamed {
            let alert = NSAlert()
            alert.messageText = NSLocalizedString("The group could not be renamed.", comment: "Title of the alert shown when a group of pinned tables could not be renamed")
            switch result {
            case .duplicateName:
                alert.informativeText = NSLocalizedString("Another group already has this name.", comment: "Message of the alert shown when renaming a group of pinned tables to the name of another group")
            case .invalidName:
                alert.informativeText = NSLocalizedString("The name is empty or the group no longer exists.", comment: "Message of the alert shown when renaming a group of pinned tables with an unusable name")
            default:
                alert.informativeText = NSLocalizedString("The pinned tables could not be saved. Please try again.", comment: "Message of the alert shown when the store refused to save a renamed group of pinned tables")
            }
            alert.addButton(withTitle: NSLocalizedString("OK", comment: "OK button"))
            alert.runModal()
        }
        onChange?()
    }

    @objc private func toggleCollapsed(_ sender: NSMenuItem) {
        guard let groupName = sender.representedObject as? String else { return }
        let isCollapsed = manager.isPinnedTableGroupCollapsed(hostName: hostName, databaseName: databaseName, groupName: groupName)
        manager.setPinnedTableGroupCollapsed(hostName: hostName, databaseName: databaseName, groupName: groupName, isCollapsed: !isCollapsed)
        onChange?()
    }

    @objc private func deleteGroup(_ sender: NSMenuItem) {
        guard let groupName = sender.representedObject as? String else { return }
        manager.deletePinnedTableGroup(hostName: hostName, databaseName: databaseName, groupName: groupName)
        onChange?()
    }

    private func move(_ tableNames: [String], toGroup groupName: String) {
        manager.movePinnedTables(hostName: hostName, databaseName: databaseName, tableNames: tableNames, toGroupName: groupName)
        onChange?()
    }

    /// Asks for a group name in a modal alert.
    ///
    /// - Returns: The trimmed name, or `nil` when the user cancelled or left it empty.
    private func promptForGroupName(title: String, message: String, confirmTitle: String, initialName: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: confirmTitle)
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "Cancel button"))
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = initialName
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else {
            return nil
        }
        let name = SAPinnedTableGroupPlanner.normalizedGroupName(field.stringValue)
        return name.isNotEmpty ? name : nil
    }
}

// MARK: - Drag and drop

/// Where a drop of pinned tables lands: the header row of a pinned section and its group.
@objc(SAPinnedDropTarget) final class SAPinnedDropTarget: NSObject {
    /// The row of the section's header, which the list highlights while dragging.
    @objc let headerRow: Int
    /// The group of the section; empty for the global pinned section.
    @objc let groupName: String

    init(headerRow: Int, groupName: String) {
        self.headerRow = headerRow
        self.groupName = groupName
        super.init()
    }
}

/// The rows of the table list once the pinned sections are on top.
@objc(SAPinnedTableRows) final class SAPinnedTableRows: NSObject {
    @objc let titles: [String]
    @objc let types: [NSNumber]
    /// The pinned tables that are shown (those of collapsed groups are not).
    @objc let pinnedTables: [String]

    init(titles: [String], types: [Int], pinnedTables: [String]) {
        self.titles = titles
        self.types = types.map { NSNumber(value: $0) }
        self.pinnedTables = pinnedTables
        super.init()
    }
}

extension SAPinnedTableGroupsController {

    /// Puts the pinned sections on top of the regular tables.
    @objc(rowsForTables:types:sections:pinnedHeader:)
    static func rows(forTables tables: [String], types: [NSNumber], sections: [SAPinnedTableSection], pinnedHeader: String) -> SAPinnedTableRows {
        let result = SAPinnedTableGroupPlanner.rows(
            tables: tables,
            types: types.map { $0.intValue },
            headerType: Int(SPTableTypeNone.rawValue),
            sections: sections.map { ($0.groupName, $0.tableNames, $0.isCollapsed) },
            pinnedHeader: pinnedHeader
        )
        return SAPinnedTableRows(titles: result.titles, types: result.types, pinnedTables: result.pinned)
    }

    /// The pasteboard type of tables dragged to be pinned or moved between groups.
    @objc static let pinnedTableType = "com.sequel-ace.pasteboard.pinned-table"

    /// The pasteboard item that drags one table of the list.
    @objc(pasteboardItemForTableName:)
    static func pasteboardItem(forTableName tableName: String) -> NSPasteboardItem {
        SADragPasteboard.item(string: tableName, forType: pinnedTableType)
    }

    /// The pinned section a drop at a row lands in, or `nil` when the row is outside the
    /// pinned sections. Dropping on a header, on a pinned table, or just below one all
    /// target the section they belong to.
    ///
    /// - Parameters:
    ///   - row: The proposed row.
    ///   - isDropOn: Whether the drop is on the row rather than above it.
    ///   - titles: The rows of the list.
    ///   - types: The table type of each row; header rows have no type.
    ///   - pinnedHeader: The localized "PINNED" header.
    @objc(dropTargetForRow:isDropOn:titles:types:pinnedHeader:)
    static func dropTarget(forRow row: Int, isDropOn: Bool, titles: [String], types: [NSNumber], pinnedHeader: String) -> SAPinnedDropTarget? {
        let isHeader = types.map { $0.intValue == Int(SPTableTypeNone.rawValue) }
        guard let target = SAPinnedTableGroupPlanner.dropTarget(row: row, isDropOn: isDropOn, titles: titles, isHeader: isHeader, pinnedHeader: pinnedHeader) else {
            return nil
        }
        return SAPinnedDropTarget(headerRow: target.headerRow, groupName: target.groupName)
    }

    /// Pins the dragged tables in the target group, or moves them there when pinned already.
    ///
    /// - Returns: Whether the tables are in the group afterwards.
    @objc(acceptDropOfPasteboard:groupName:connectionIdentifier:databaseName:)
    func acceptDrop(pasteboard: NSPasteboard, groupName: String, connectionIdentifier: String, databaseName: String) -> Bool {
        let type = NSPasteboard.PasteboardType(Self.pinnedTableType)
        let tableNames = (pasteboard.pasteboardItems ?? []).compactMap { $0.string(forType: type) }
        guard tableNames.isNotEmpty else {
            return false
        }
        let moved = manager.movePinnedTables(hostName: connectionIdentifier, databaseName: databaseName, tableNames: tableNames, toGroupName: groupName)
        onChange?()
        return moved
    }
}
