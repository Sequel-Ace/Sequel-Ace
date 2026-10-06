import SwiftUI

/// The Check Constraints section of the Relations tab: a list with add and
/// delete buttons. There is deliberately no edit in place; a check is changed
/// by deleting it and adding it again.
struct SACheckConstraintsView: View {
    @ObservedObject var model: SACheckConstraintsModel
    @State private var isAddSheetPresented = false

    // Section title colour used for "INDEXES" in the Structure tab (see DBView.xib)
    private static let titleColor = Color(nsColor: NSColor(calibratedRed: 0.36078432, green: 0.4313725531, blue: 0.50588238, alpha: 1))

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Text(NSLocalizedString("Check Constraints", comment: "check constraints : section title in the Relations tab"))
                    .textCase(.uppercase)
                    .font(.system(size: NSFont.smallSystemFontSize, weight: .bold))
                    .foregroundColor(Self.titleColor)

                Spacer(minLength: 0)

                // Same drag-handle image the Structure tab shows at the right of INDEXES, at its
                // native 10x8 (the XIB's image cell scales it proportionally, never stretching it)
                if let grabber = NSImage(named: "grabber-horizontal") {
                    Image(nsImage: grabber)
                }
            }
            .padding(.leading, 14)
            .padding(.trailing, 10)
            .frame(height: 20)

            // Inset like the foreign key table above it
            SACheckConstraintsTable(model: model)
                .padding(.leading, 6)
                .padding(.trailing, 3)

            // Same look and spacing as the foreign key buttons above (see DBView.xib)
            HStack(spacing: 5) {
                SACheckConstraintsToolbarButton(
                    image: NSImage.addTemplateName,
                    help: NSLocalizedString("Add check constraint", comment: "check constraints : add button tooltip")
                ) {
                    isAddSheetPresented = true
                }
                .disabled(!model.isEnabled)

                SACheckConstraintsToolbarButton(
                    image: NSImage.removeTemplateName,
                    help: NSLocalizedString("Delete selected check constraint(s)", comment: "check constraints : delete button tooltip")
                ) {
                    model.deleteHandler?(model.selectedNames)
                }
                .disabled(!model.canDelete)

                SACheckConstraintsToolbarButton(
                    image: NSImage.refreshTemplateName,
                    help: NSLocalizedString("Refresh check constraints", comment: "check constraints : refresh button tooltip")
                ) {
                    model.refreshHandler?()
                }
                .disabled(!model.isEnabled)
            }
            .padding(.leading, 10)
            .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(isPresented: $isAddSheetPresented) {
            SACheckConstraintAddSheet(model: model) {
                isAddSheetPresented = false
            }
        }
    }
}

/// The small square image button used under the foreign key table in
/// DBView.xib. It wraps a real `NSButton` configured the same way, since a
/// SwiftUI button draws the same template image heavier and larger.
private struct SACheckConstraintsToolbarButton: NSViewRepresentable {
    let image: NSImage.Name
    let help: String
    let action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton()
        button.bezelStyle = .smallSquare
        button.setButtonType(.momentaryPushIn)
        // The foreign key buttons draw as bare glyphs; without this a bezel is drawn around ours
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.image = NSImage(named: image)
        button.contentTintColor = .labelColor
        button.toolTip = help
        button.target = context.coordinator
        button.action = #selector(Coordinator.buttonClicked)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        button.isEnabled = context.environment.isEnabled
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSButton, context: Context) -> CGSize? {
        CGSize(width: 25, height: 25)
    }

    final class Coordinator: NSObject {
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func buttonClicked() {
            action()
        }
    }
}

/// `SPTableView` is the class behind the foreign key and Indexes tables. Deleting
/// is handled here because there is no menu item to route it through.
private final class SACheckConstraintsNSTableView: SPTableView {
    var onDelete: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        // Delete and forward delete; everything else (Return, Tab...) stays with SPTableView
        if event.keyCode == 51 || event.keyCode == 117 {
            onDelete?()
        } else {
            super.keyDown(with: event)
        }
    }
}

/// The constraint list, built like the foreign key and Indexes tables rather than
/// with SwiftUI's `Table`: a cell-based `SPTableView` with alternating rows, the
/// user's table font and the same row height. SwiftUI's version draws inset,
/// rounded rows and larger text.
private struct SACheckConstraintsTable: NSViewRepresentable {
    @ObservedObject var model: SACheckConstraintsModel

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let coordinator = context.coordinator

        let table = SACheckConstraintsNSTableView(frame: .zero)
        table.focusRingType = .none
        table.allowsExpansionToolTips = true
        table.usesAlternatingRowBackgroundColors = true
        table.allowsMultipleSelection = true
        table.dataSource = coordinator
        table.delegate = coordinator
        table.onDelete = { [weak coordinator] in coordinator?.deleteSelection() }

        let columns: [(id: String, title: String, width: CGFloat, minWidth: CGFloat, resizing: NSTableColumn.ResizingOptions)] = [
            ("name", NSLocalizedString("Name", comment: "check constraints : name column"), 200, 80, .userResizingMask),
            ("expression", NSLocalizedString("Expression", comment: "check constraints : expression column"), 300, 100, [.autoresizingMask, .userResizingMask]),
            ("enforced", NSLocalizedString("Enforced", comment: "check constraints : enforced column"), 70, 50, .userResizingMask)
        ]
        for definition in columns {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(definition.id))
            column.title = definition.title
            column.width = definition.width
            column.minWidth = definition.minWidth
            column.resizingMask = definition.resizing

            let cell = NSTextFieldCell()
            cell.controlSize = .small
            cell.lineBreakMode = .byTruncatingTail
            column.dataCell = cell

            table.addTableColumn(column)
        }

        coordinator.table = table
        coordinator.applyAppearance()

        let scrollView = NSScrollView()
        scrollView.documentView = table
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.sync()
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        private let model: SACheckConstraintsModel
        weak var table: NSTableView?

        private var items: [SACheckConstraintItem] = []
        private var isSyncing = false
        private var appliedFont: NSFont?
        private var appliedGridlines: Bool?
        private var defaultsObserver: NSObjectProtocol?

        init(model: SACheckConstraintsModel) {
            self.model = model
            super.init()

            // The foreign key table follows the font and gridline preferences live; so does this one
            defaultsObserver = NotificationCenter.default.addObserver(
                forName: UserDefaults.didChangeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                self?.applyAppearance()
            }
        }

        deinit {
            if let defaultsObserver {
                NotificationCenter.default.removeObserver(defaultsObserver)
            }
        }

        /// Same font, row height and gridline handling as the foreign key table.
        func applyAppearance() {
            guard let table else { return }

            let font = UserDefaults.getFont()
            let gridlines = UserDefaults.standard.bool(forKey: SPDisplayTableViewVerticalGridlines)
            guard font != appliedFont || gridlines != appliedGridlines else { return }
            appliedFont = font
            appliedGridlines = gridlines

            table.gridStyleMask = gridlines ? .solidVerticalGridLineMask : []
            table.rowHeight = 4 + NSAttributedString(string: "{ǞṶḹÜ∑zgyf", attributes: [.font: font]).size().height
            for column in table.tableColumns {
                (column.dataCell as? NSCell)?.font = font
            }
            table.reloadData()
        }

        /// Pushes the model's rows, selection and enabled state into the table.
        func sync() {
            guard let table else { return }

            isSyncing = true
            defer { isSyncing = false }

            if items != model.items {
                items = model.items
                table.reloadData()
            }
            table.isEnabled = model.isEnabled

            let wanted = IndexSet(items.indices.filter { model.selection.contains(items[$0].id) })
            if table.selectedRowIndexes != wanted {
                table.selectRowIndexes(wanted, byExtendingSelection: false)
            }
        }

        func deleteSelection() {
            if model.canDelete {
                model.deleteHandler?(model.selectedNames)
            }
        }

        // MARK: NSTableViewDataSource

        func numberOfRows(in tableView: NSTableView) -> Int {
            items.count
        }

        func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
            guard items.indices.contains(row) else { return nil }
            let item = items[row]

            switch tableColumn?.identifier.rawValue {
            case "name":
                return item.name
            case "expression":
                return item.expression
            case "enforced":
                return item.isEnforced
                    ? NSLocalizedString("Yes", comment: "yes")
                    : NSLocalizedString("No", comment: "no")
            default:
                return nil
            }
        }

        // MARK: NSTableViewDelegate

        func tableView(_ tableView: NSTableView, shouldEdit tableColumn: NSTableColumn?, row: Int) -> Bool {
            false
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            // Selection set by sync() must not be echoed back into the model mid-update
            guard !isSyncing, let table else { return }

            model.selection = Set(table.selectedRowIndexes.compactMap { items.indices.contains($0) ? items[$0].id : nil })
        }
    }
}

private struct SACheckConstraintAddSheet: View {
    @ObservedObject var model: SACheckConstraintsModel
    let close: () -> Void

    @State private var name = ""
    @State private var expression = ""
    @State private var isEnforced = true
    @State private var serverError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(NSLocalizedString("Add Check Constraint", comment: "check constraints : add sheet title"))
                .font(.headline)

            VStack(alignment: .leading, spacing: 2) {
                TextField(NSLocalizedString("Name (optional)", comment: "check constraints : add sheet : name field placeholder"), text: $name)
                if let problem = model.nameProblem(for: name) {
                    Text(problem)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }

            Text(NSLocalizedString("Expression", comment: "check constraints : expression column"))
                .font(.subheadline)
            TextEditor(text: $expression)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 80)
                .border(Color(nsColor: .separatorColor))

            if model.supportsNotEnforced {
                Toggle(NSLocalizedString("Enforced", comment: "check constraints : enforced column"), isOn: $isEnforced)
            }

            if let serverError {
                Text(serverError)
                    .font(.caption)
                    .foregroundColor(.red)
                    .textSelection(.enabled)
            }

            HStack {
                Spacer()
                Button(NSLocalizedString("Cancel", comment: "cancel button"), action: close)
                    .keyboardShortcut(.cancelAction)
                Button(NSLocalizedString("Add", comment: "add button"), action: add)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canAdd(name: name, expression: expression))
            }
        }
        .padding(16)
        .frame(width: 440)
    }

    private func add() {
        // The checkbox is only offered where NOT ENFORCED exists; elsewhere the check is always enforced
        let enforced = model.supportsNotEnforced ? isEnforced : true

        if let error = model.addHandler?(name, expression, enforced) {
            serverError = error
        } else {
            close()
        }
    }
}
