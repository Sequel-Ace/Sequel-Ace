//
//  SAFavoritesListDataSource.swift
//  Sequel Ace
//
//  Created as part of the modernization effort.
//  Extracts the NSOutlineView data source and delegate for the favorites
//  sidebar from SPConnectionController into a standalone Swift object.
//  This enables reuse (standalone connection window) and future SwiftUI migration.
//

import AppKit

// Image name constants (mirrored from SPConnectionController.m)
private let kSPDatabaseImage = "database-small"
private let kSPQuickConnectImage = "quick-connect-icon.pdf"
private let kSPQuickConnectImageWhite = "quick-connect-icon-white.pdf"

/// Manages the favorites outline view as its data source and delegate.
///
/// Owns the tree data (`favoritesRoot`, `quickConnectItem`) and handles
/// all outline view interactions. Delegates user-intent actions (selection,
/// double-click, rename) to its `SAFavoritesListDelegate`.
@objc class SAFavoritesListDataSource: NSObject {

    // MARK: - Properties

    /// The root of the favorites tree. Set from SPFavoritesController.
    @objc var favoritesRoot: SPTreeNode

    /// Virtual Quick Connect entry displayed at the top of the list.
    @objc let quickConnectItem: SPTreeNode

    /// The custom cell used for the Quick Connect entry.
    @objc var quickConnectCell: SPFavoriteTextFieldCell

    /// Folder icon for group nodes.
    @objc var folderImage: NSImage

    /// Nodes currently being dragged (for internal drag & drop).
    @objc var draggedNodes: [SPTreeNode] = []

    /// Callback delegate for selection changes and user actions.
    @objc weak var delegate: SAFavoritesListDelegate?

    /// Reference to favorites controller for save operations.
    @objc var favoritesController: SPFavoritesController

    // MARK: - Initialization

    @objc init(favoritesRoot: SPTreeNode, favoritesController: SPFavoritesController) {
        self.favoritesRoot = favoritesRoot
        self.favoritesController = favoritesController

        // Create the "Quick Connect" placeholder group
        let groupNode = SPGroupNode(
            name: NSLocalizedString("Quick Connect", comment: "Quick connect item label").uppercased()
        )
        self.quickConnectItem = SPTreeNode(representedObject: groupNode)
        self.quickConnectItem.isGroup = true

        // Custom cell for Quick Connect
        self.quickConnectCell = SPFavoriteTextFieldCell()
        self.quickConnectCell.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)

        // Folder icon
        self.folderImage = NSWorkspace.shared.icon(forFileType: NSFileTypeForHFSTypeCode(OSType(kGenericFolderIcon)))
        self.folderImage.size = NSSize(width: 16, height: 16)

        super.init()
    }

    // MARK: - Public API

    /// Sets up the outline view with this object as its data source and delegate.
    @objc func attach(to outlineView: NSOutlineView) {
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.registerForDraggedTypes([NSPasteboard.PasteboardType(SPFavoritesPasteboardDragType)])
        outlineView.setDraggingSourceOperationMask(.move, forLocal: true)
    }

    /// Reloads the outline view data and expands the root node.
    @objc func reloadData(in outlineView: NSOutlineView) {
        outlineView.reloadData()
        outlineView.expandItem(outlineView.item(atRow: 0), expandChildren: false)
    }

    /// Recursively restores expand/collapse state from stored node preferences.
    @objc func restoreOutlineViewState(_ node: SPTreeNode, in outlineView: NSOutlineView) {
        guard node.isGroup else { return }

        for child in node.children ?? [] {
            guard child.isGroup else { continue }
            if let groupObj = child.representedObject as? SPGroupNode, groupObj.nodeIsExpanded {
                outlineView.expandItem(child)
            } else {
                outlineView.collapseItem(child)
            }
            restoreOutlineViewState(child, in: outlineView)
        }
    }
}

// MARK: - NSOutlineViewDataSource

extension SAFavoritesListDataSource: NSOutlineViewDataSource {

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        let node = (item as? SPTreeNode) ?? favoritesRoot

        // Add 1 at root level for the Quick Connect entry
        if item == nil {
            return (node.children?.count ?? 0) + 1
        }
        return node.children?.count ?? 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        var adjustedIndex = index

        // At root level, index 0 is Quick Connect; shift others down
        if item == nil {
            if adjustedIndex == 0 {
                return quickConnectItem
            }
            adjustedIndex -= 1
        }

        let node = (item as? SPTreeNode) ?? favoritesRoot
        guard let children = node.children, adjustedIndex < children.count
        else { return NSNull() }
        return children[adjustedIndex]
    }

    func outlineView(_ outlineView: NSOutlineView, objectValueFor tableColumn: NSTableColumn?, byItem item: Any?) -> Any? {
        guard let node = item as? SPTreeNode else { return nil }

        if !node.isGroup {
            return (node.representedObject as? SPFavoriteNode)?.nodeFavorite?[SPFavoriteNameKey]
        }
        return (node.representedObject as? SPGroupNode)?.nodeName
    }

    func outlineView(_ outlineView: NSOutlineView, setObjectValue object: Any?, for tableColumn: NSTableColumn?, byItem item: Any?) {
        guard let newName = (object as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !newName.isEmpty,
              let node = item as? SPTreeNode else { return }

        delegate?.favoritesListDidRenameNode(node, to: newName)
    }

    // MARK: Drag & Drop

    func outlineView(_ outlineView: NSOutlineView, writeItems items: [Any], to pasteboard: NSPasteboard) -> Bool {
        // Check with delegate if drag is allowed (e.g. not during name editing)
        if delegate?.favoritesListShouldBeginDrag?() == false {
            return false
        }

        // Prevent dragging root-level items
        for item in items {
            guard let node = item as? SPTreeNode,
                  node.parent?.parent != nil else { return false }
        }

        pasteboard.declareTypes([NSPasteboard.PasteboardType(SPFavoritesPasteboardDragType)], owner: self)
        pasteboard.setData(Data(), forType: NSPasteboard.PasteboardType(SPFavoritesPasteboardDragType))

        draggedNodes = items.compactMap { $0 as? SPTreeNode }
        return true
    }

    func outlineView(_ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo, proposedItem item: Any?, proposedChildIndex index: Int) -> NSDragOperation {
        // Prevent dropping on top level or Quick Connect
        guard let targetNode = item as? SPTreeNode,
              targetNode !== quickConnectItem else { return [] }

        // Prevent dropping on non-groups
        if index == NSOutlineViewDropOnItemIndex && !targetNode.isGroup { return [] }

        // Prevent circular drops
        var check: NSTreeNode? = targetNode
        while let current = check {
            if draggedNodes.contains(where: { $0 === current }) { return [] }
            check = current.parent
        }

        if info.draggingSource as? NSOutlineView === outlineView {
            outlineView.setDropItem(item, dropChildIndex: index)
            return .move
        }
        return []
    }

    func outlineView(_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo, item: Any?, childIndex: Int) -> Bool {
        guard item != nil, info.draggingSource as? NSOutlineView === outlineView else { return false }

        let targetNode = (item as? SPTreeNode) ?? favoritesRoot.children?.first
        guard let targetNode = targetNode else { return false }

        var insertIndex = childIndex
        if targetNode.isGroup && insertIndex == NSOutlineViewDropOnItemIndex {
            insertIndex = 0
            outlineView.expandItem(targetNode)
        }

        let childArray = targetNode.mutableChildren
        guard !draggedNodes.isEmpty else { return false }

        // Cache selection for restoration
        let preDragSelection = outlineView.selectedRowIndexes.map { outlineView.item(atRow: $0) as? SPTreeNode }

        for draggedNode in draggedNodes {
            let oldIndex = childArray.index(of: draggedNode)
            var newIndex = insertIndex

            if oldIndex != NSNotFound {
                childArray.removeObject(at: oldIndex)
                if insertIndex > oldIndex { newIndex -= 1 }
            } else {
                (draggedNode.parent as? SPTreeNode)?.mutableChildren.remove(draggedNode)
            }

            childArray.insert(draggedNode, at: newIndex)
            insertIndex = newIndex + 1
        }

        favoritesController.saveFavorites()
        reloadData(in: outlineView)

        // Notify delegate to handle sort state reset and notifications
        delegate?.favoritesListDidReorderNodes?()

        // Restore selection
        let restoredIndexes = NSMutableIndexSet()
        for node in preDragSelection {
            guard let node = node else { continue }
            let row = outlineView.row(forItem: node)
            if row >= 0 { restoredIndexes.add(row) }
        }
        outlineView.selectRowIndexes(restoredIndexes as IndexSet, byExtendingSelection: false)

        return true
    }
}

// MARK: - NSOutlineViewDelegate

extension SAFavoritesListDataSource: NSOutlineViewDelegate {

    func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
        guard let node = item as? SPTreeNode else { return false }
        return node.parent?.parent == nil
    }

    func outlineViewSelectionIsChanging(_ notification: Notification) {
        // Notify delegate to stop editing during selection change (prevents visual glitches)
        delegate?.favoritesListEditingStateChanged?(isEditing: false)
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard let outlineView = notification.object as? NSOutlineView else { return }
        let selectedRow = outlineView.selectedRow
        let selectedNode = selectedRow >= 0 ? outlineView.item(atRow: selectedRow) as? SPTreeNode : nil
        delegate?.favoritesListSelectionDidChange(selectedNode)
    }

    func outlineView(_ outlineView: NSOutlineView, dataCellFor tableColumn: NSTableColumn?, item: Any) -> NSCell? {
        if (item as? SPTreeNode) === quickConnectItem {
            return quickConnectCell
        }
        return tableColumn?.dataCell(forRow: outlineView.row(forItem: item)) as? NSCell
    }

    func outlineView(_ outlineView: NSOutlineView, willDisplayCell cell: Any, for tableColumn: NSTableColumn?, item: Any) {
        guard let node = item as? SPTreeNode,
              let favoriteCell = cell as? SPFavoriteTextFieldCell else { return }

        if node.parent?.parent == nil {
            // Top-level items
            if node === quickConnectItem {
                let isSelected = outlineView.row(forItem: item) == outlineView.selectedRow
                favoriteCell.image = NSImage(named: isSelected ? kSPQuickConnectImageWhite : kSPQuickConnectImage)
            } else {
                favoriteCell.image = nil
            }
            favoriteCell.labelColor = nil
        } else if node.isGroup {
            favoriteCell.image = folderImage
            favoriteCell.labelColor = nil
        } else {
            favoriteCell.image = NSImage(named: kSPDatabaseImage)
            let colorIndex = (node.representedObject as? SPFavoriteNode)?.nodeFavorite?[SPFavoriteColorIndexKey] as? Int
            favoriteCell.labelColor = colorIndex.flatMap { SPFavoriteColorSupport.sharedInstance().color(for: $0) }
        }
    }

    func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
        let tableFont = UserDefaults.getFont()
        let textHeight = "{ǞṶḹÜ∑zgyf".size(withAttributes: [.font: tableFont]).height
        return max(24.0, textHeight + 8.0)
    }

    func outlineView(_ outlineView: NSOutlineView, toolTipFor cell: NSCell, rect: NSRectPointer, tableColumn: NSTableColumn?, item: Any, mouseLocation: NSPoint) -> String {
        guard let node = item as? SPTreeNode else { return "" }

        if !node.isGroup {
            let name = (node.representedObject as? SPFavoriteNode)?.nodeFavorite?[SPFavoriteNameKey] as? String ?? ""
            let host = (node.representedObject as? SPFavoriteNode)?.nodeFavorite?[SPFavoriteHostKey] as? String ?? ""
            return host.isEmpty ? name : "\(name) (\(host))"
        } else if node.parent?.parent != nil {
            var favCount = 0
            var groupCount = 0
            for child in node.children ?? [] {
                if child.isGroup { groupCount += 1 } else { favCount += 1 }
            }
            let groupName = (node.representedObject as? SPGroupNode)?.nodeName ?? ""
            var parts: [String] = []
            if favCount > 0 || groupCount == 0 {
                let fmt = favCount == 1
                    ? NSLocalizedString("%lu favorite", comment: "favorite singular label (%d == 1)")
                    : NSLocalizedString("%lu favorites", comment: "favorites plural label (%d != 1)")
                parts.append(String(format: fmt, favCount))
            }
            if groupCount > 0 {
                let fmt = groupCount == 1
                    ? NSLocalizedString("%lu group", comment: "favorite group singular label (%d == 1)")
                    : NSLocalizedString("%lu groups", comment: "favorite groups plural label (%d != 1)")
                parts.append(String(format: fmt, groupCount))
            }
            return "\(groupName) - \(parts.joined(separator: ", "))"
        }
        return ""
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        guard let node = item as? SPTreeNode else { return false }
        // At root level, only Quick Connect is selectable
        if node.parent?.parent == nil {
            return node === quickConnectItem
        }
        return true
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let node = item as? SPTreeNode else { return false }
        return node !== quickConnectItem && !node.isLeaf
    }

    func outlineView(_ outlineView: NSOutlineView, shouldShowOutlineCellForItem item: Any) -> Bool {
        guard let node = item as? SPTreeNode else { return false }
        return node.parent?.parent != nil
    }

    func outlineView(_ outlineView: NSOutlineView, shouldCollapseItem item: Any) -> Bool {
        guard let node = item as? SPTreeNode else { return false }
        return node.parent?.parent != nil
    }

    func outlineView(_ outlineView: NSOutlineView, shouldEdit tableColumn: NSTableColumn?, item: Any) -> Bool {
        guard let node = item as? SPTreeNode else { return false }

        if let event = NSApp.currentEvent,
           event.type == .keyDown,
           let chars = event.characters,
           chars.first == Character(UnicodeScalar(NSBackTabCharacter)!),
           (outlineView as? SPFavoritesOutlineView)?.justGainedFocus == true {
            return false
        }

        return node !== quickConnectItem
    }

    func outlineViewItemDidCollapse(_ notification: Notification) {
        setNodeIsExpanded(false, from: notification)
    }

    func outlineViewItemDidExpand(_ notification: Notification) {
        setNodeIsExpanded(true, from: notification)
    }

    // MARK: - Private Helpers

    private func setNodeIsExpanded(_ expanded: Bool, from notification: Notification) {
        guard let node = notification.userInfo?["NSObject"] as? SPTreeNode,
              node.isGroup,
              let groupObj = node.representedObject as? SPGroupNode else { return }
        groupObj.nodeIsExpanded = expanded
    }
}
