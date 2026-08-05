//
//  SARecordView.swift
//  Sequel Ace
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import SwiftUI

struct SARecordField: Identifiable, Equatable {
    let id: Int
    let name: String
    let value: String

    var previewValue: String {
        let prefix = value.prefix(4_097)
        let isTruncated = prefix.count > 4_096
        let flattened = String(prefix.prefix(4_096))
            .components(separatedBy: .newlines)
            .joined(separator: " ")
            .replacingOccurrences(of: "\t", with: " ")
        return isTruncated ? flattened + "…" : flattened
    }
}

final class SARecordViewModel: ObservableObject {
    @Published private(set) var selectedRowCount = 0
    @Published private(set) var fields: [SARecordField] = []
    @Published var searchText = ""
    @Published var selectedFieldID: SARecordField.ID?
    @Published var editingFieldID: SARecordField.ID?
    @Published var focusedFieldID: SARecordField.ID?
    @Published var editDraft = ""

    var beginEditing: ((Int) -> Bool)?
    var commitEditing: ((Int, String) -> Bool)?

    var visibleFields: [SARecordField] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return fields
        }
        return fields.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    func update(fields: [SARecordField], selectedRowCount: Int) {
        cancelEdit()
        self.selectedRowCount = selectedRowCount
        self.fields = selectedRowCount == 1 ? fields : []
        selectedFieldID = nil
    }

    func clear() {
        cancelEdit()
        selectedRowCount = 0
        fields = []
        searchText = ""
        selectedFieldID = nil
    }

    func requestEdit(_ field: SARecordField) {
        guard beginEditing?(field.id) == true else {
            return
        }
        editingFieldID = field.id
        focusedFieldID = field.id
        editDraft = field.value
    }

    func commitEdit() {
        guard let fieldID = editingFieldID,
              commitEditing?(fieldID, editDraft) == true else {
            return
        }
        cancelEdit()
    }

    func cancelEdit() {
        editingFieldID = nil
        focusedFieldID = nil
        editDraft = ""
    }
}

private struct SARecordView: View {
    @ObservedObject var model: SARecordViewModel
    @FocusState private var focusedFieldID: SARecordField.ID?

    var body: some View {
        VStack(spacing: 0) {
            TextField("Filter fields", text: $model.searchText)
                .textFieldStyle(.roundedBorder)
                .padding(8)
                .accessibilityLabel("Filter record fields")

            content
        }
        .frame(minWidth: 240, idealWidth: 320)
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: model.focusedFieldID) { focusedFieldID = $0 }
    }

    @ViewBuilder
    private var content: some View {
        if model.selectedRowCount == 0 {
            emptyState("Select one row to view it", systemImage: "rectangle.and.hand.point.up.left")
        } else if model.selectedRowCount > 1 {
            emptyState("Select only one row", systemImage: "rectangle.stack")
        } else if model.fields.isEmpty {
            emptyState("This record has no fields", systemImage: "list.bullet.rectangle")
        } else {
            Table(model.visibleFields, selection: $model.selectedFieldID) {
                TableColumn("Field") { field in
                    Text(field.name)
                        .help(field.name)
                }
                TableColumn("Value") { field in
                    if model.editingFieldID == field.id {
                        TextField("Value", text: $model.editDraft)
                            .textFieldStyle(.plain)
                            .onSubmit(model.commitEdit)
                            .focused($focusedFieldID, equals: field.id)
                            .onExitCommand(perform: model.cancelEdit)
                            .onAppear {
                                DispatchQueue.main.async {
                                    focusedFieldID = field.id
                                }
                            }
                    } else {
                        Text(field.previewValue)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) {
                                model.requestEdit(field)
                            }
                            .contextMenu {
                                Button("Copy Value") {
                                    copy(field.value)
                                }
                                Button("Edit Value") {
                                    model.requestEdit(field)
                                }
                            }
                    }
                }
            }
        }
    }

    private func emptyState(_ title: LocalizedStringKey, systemImage: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.title2)
            Text(title)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}

private final class SARecordViewResizeHandle: NSView {
    weak var overlayView: SARecordViewOverlayView?

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override func mouseDown(with event: NSEvent) {
        overlayView?.mouseDown(with: event)
    }
}

private final class SARecordViewOverlayView: NSView {
    weak var resizedView: NSView?
    weak var resizeHandle: NSView?
    var resizedViewRightInset: CGFloat = 0
    var widthDefaultsKey = ""
    var recordViewWidth: CGFloat = 320

    override func mouseDown(with event: NSEvent) {
        guard let window else {
            return
        }
        let startX = event.locationInWindow.x
        let startWidth = frame.width

        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if next.type == .leftMouseUp {
                UserDefaults.standard.set(recordViewWidth, forKey: widthDefaultsKey)
                return
            }
            resize(to: startWidth + startX - next.locationInWindow.x)
        }
    }

    func show() {
        isHidden = false
        resize(to: recordViewWidth)
        if let resizeHandle {
            window?.invalidateCursorRects(for: resizeHandle)
        }
    }

    func hide() {
        guard let parent = superview, let resizedView else {
            return
        }
        var resizedFrame = resizedView.frame
        resizedFrame.size.width = parent.bounds.width - resizedFrame.minX - resizedViewRightInset
        resizedView.frame = resizedFrame
        isHidden = true
    }

    private func resize(to proposedWidth: CGFloat) {
        guard let parent = superview, let resizedView else {
            return
        }
        recordViewWidth = min(max(proposedWidth, 240), parent.bounds.width)

        frame = NSRect(
            x: parent.bounds.width - recordViewWidth,
            y: frame.minY,
            width: recordViewWidth,
            height: frame.height
        )

        var resizedFrame = resizedView.frame
        resizedFrame.size.width = max(frame.minX - resizedFrame.minX - 1, 0)
        resizedView.frame = resizedFrame
    }
}

@objc final class SARecordViewToolbarSupport: NSObject {
    private static let contentIdentifier = "SwitchToTableContentToolbarItemIdentifier"
    private static let queryIdentifier = "SwitchToRunQueryToolbarItemIdentifier"
    private static let migrationDefaultsKey = "SARecordViewToolbarItemMigrationV1"

    @objc static var itemIdentifier: String {
        "RecordViewToolbarItemIdentifier"
    }

    @objc(isEnabledForSelectedIdentifier:)
    static func isEnabled(for selectedIdentifier: String?) -> Bool {
        selectedIdentifier == contentIdentifier || selectedIdentifier == queryIdentifier
    }

    static func insertionIndex(in identifiers: [String]) -> Int {
        identifiers.firstIndex(of: queryIdentifier).map { $0 + 1 } ?? identifiers.count
    }

    static func shouldAutoInsert(hasMigrated: Bool, containsItem: Bool) -> Bool {
        !hasMigrated && !containsItem
    }

    @objc(makeToolbarItemWithTarget:)
    static func makeToolbarItem(target: AnyObject) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: NSToolbarItem.Identifier(itemIdentifier))
        item.label = NSLocalizedString("Record View", comment: "record view toolbar item label")
        item.paletteLabel = item.label
        item.toolTip = NSLocalizedString("Toggle Record View", comment: "record view toolbar item tooltip")
        item.image = NSImage(systemSymbolName: "sidebar.right", accessibilityDescription: nil)
            ?? NSImage(named: NSImage.Name("NSListViewTemplate"))
        item.target = target
        item.action = NSSelectorFromString("toggleRecordView:")
        return item
    }

    @objc(installIfNeededInToolbar:defaults:)
    static func installIfNeeded(in toolbar: NSToolbar, defaults: UserDefaults) {
        let identifiers = toolbar.items.map { $0.itemIdentifier.rawValue }
        let hasMigrated = defaults.bool(forKey: migrationDefaultsKey)

        if shouldAutoInsert(hasMigrated: hasMigrated, containsItem: identifiers.contains(itemIdentifier)) {
            toolbar.insertItem(
                withItemIdentifier: NSToolbarItem.Identifier(itemIdentifier),
                at: insertionIndex(in: identifiers)
            )
        }

        if !hasMigrated {
            defaults.set(true, forKey: migrationDefaultsKey)
        }
    }
}

@objc final class SARecordViewController: NSObject {
    private let model = SARecordViewModel()
    private lazy var hostingView = NSHostingView(rootView: SARecordView(model: model))
    private weak var overlayView: SARecordViewOverlayView?

    @objc(installOverlayInView:resizingView:bottomInset:topInset:autosaveName:)
    func installOverlay(in parentView: NSView,
                        resizing targetView: NSView,
                        bottomInset: CGFloat,
                        topInset: CGFloat,
                        autosaveName: String) {
        let savedWidth = UserDefaults.standard.double(forKey: autosaveName)
        let width = min(savedWidth >= 240 ? savedWidth : 320, parentView.bounds.width)
        let container = SARecordViewOverlayView(frame: NSRect(
            x: parentView.bounds.width - width,
            y: bottomInset,
            width: width,
            height: max(parentView.bounds.height - bottomInset - topInset, 0)
        ))
        container.autoresizingMask = [.minXMargin, .height]
        container.wantsLayer = true
        container.layer?.borderColor = NSColor.separatorColor.cgColor
        container.layer?.borderWidth = 1
        container.layer?.masksToBounds = true
        container.resizedView = targetView
        container.resizedViewRightInset = parentView.bounds.width - targetView.frame.maxX
        container.widthDefaultsKey = autosaveName
        container.recordViewWidth = width

        hostingView.frame = container.bounds
        hostingView.autoresizingMask = [.width, .height]
        container.addSubview(hostingView)

        let resizeHandle = SARecordViewResizeHandle(frame: NSRect(x: 0, y: 0, width: 10, height: container.bounds.height))
        resizeHandle.autoresizingMask = [.height]
        resizeHandle.overlayView = container
        container.addSubview(resizeHandle, positioned: .above, relativeTo: nil)
        container.resizeHandle = resizeHandle

        container.isHidden = true
        parentView.addSubview(container, positioned: .above, relativeTo: nil)
        overlayView = container
    }

    @objc var isVisible: Bool {
        overlayView?.isHidden == false
    }

    @objc func toggle() {
        guard let overlayView else {
            return
        }
        overlayView.isHidden ? overlayView.show() : overlayView.hide()
    }

    @objc(updateWithFields:selectedRowCount:)
    func update(with dictionaries: [NSDictionary], selectedRowCount: Int) {
        assert(Thread.isMainThread)
        model.update(fields: Self.fields(from: dictionaries), selectedRowCount: selectedRowCount)
    }

    static func fields(from dictionaries: [NSDictionary]) -> [SARecordField] {
        dictionaries.enumerated().map { index, dictionary in
            SARecordField(
                id: (dictionary["id"] as? NSNumber)?.intValue ?? index,
                name: dictionary["name"] as? String ?? "",
                value: dictionary["value"] as? String ?? ""
            )
        }
    }

    @objc func clear() {
        assert(Thread.isMainThread)
        model.clear()
    }

    @objc(setEditingHandlersWithBegin:commit:)
    func setEditingHandlers(
        begin: @escaping (Int) -> Bool,
        commit: @escaping (Int, String) -> Bool
    ) {
        model.beginEditing = begin
        model.commitEditing = commit
    }
}
