//
//  SAClaudeFormRecipes.swift
//  Sequel Ace
//
//  One recipe per table/database sheet for the shared Claude form (`SAClaudeFormSheet`): which of the sheet's own
//  XIB views form its rows, sections, blocks and footer, found through the owner's outlets by KVC or, where a view
//  has no outlet, by its neighbour, action or key equivalent; plus the sheet's title and context line. A recipe that
//  can't find a view returns nil and the sheet keeps the generic skin. App target only.
//

import AppKit

// MARK: - Strings

enum SAClaudeFormStrings {
    static var renameDatabase: String { NSLocalizedString("ClaudeFormRenameDatabase", value: "Rename database", comment: "Claude sheet title: the Rename Database sheet") }
    static var newDatabase: String { NSLocalizedString("ClaudeFormNewDatabase", value: "New database", comment: "Claude sheet title: the New Database sheet") }
    static var alterDatabase: String { NSLocalizedString("ClaudeFormAlterDatabase", value: "Alter database", comment: "Claude sheet title: the Alter Database sheet (encoding and collation)") }
    static var duplicateDatabase: String { NSLocalizedString("ClaudeFormDuplicateDatabase", value: "Duplicate database", comment: "Claude sheet title: the Duplicate Database sheet") }
    static var newTable: String { NSLocalizedString("ClaudeFormNewTable", value: "New table", comment: "Claude sheet title: the New Table sheet") }
    static var duplicateTable: String { NSLocalizedString("ClaudeFormDuplicateTable", value: "Duplicate table", comment: "Claude sheet title: the Duplicate Table sheet (also used for views, procedures and functions)") }
    static var addKey: String { NSLocalizedString("ClaudeFormAddKey", value: "Add a key?", comment: "Claude sheet title: asks which index to add so a column can be AUTO_INCREMENT") }
    static var keyType: String { NSLocalizedString("ClaudeFormLabelKeyType", value: "Key type", comment: "Claude sheet row label: the pop-up choosing PRIMARY KEY, INDEX or UNIQUE") }
    static var resetAutoIncrement: String { NSLocalizedString("ClaudeFormResetAutoIncrement", value: "Reset auto increment", comment: "Claude sheet title: the Reset AUTO_INCREMENT sheet") }
    static var password: String { NSLocalizedString("ClaudeFormLabelPassword", value: "Password", comment: "Claude sheet row label: the password field of the encrypted connection file sheet") }
    static var newName: String { NSLocalizedString("ClaudeFormLabelNewName", value: "New name", comment: "Claude sheet row label: the field with the new name of a database or table being renamed or duplicated") }
    static var contextCurrently: String { NSLocalizedString("ClaudeFormContextCurrently", value: "Currently %@", comment: "Claude sheet context line under the Rename Database title: the database's current name") }
    static var contextFrom: String { NSLocalizedString("ClaudeFormContextFrom", value: "From %@", comment: "Claude sheet context line under a Duplicate title: the database or table being duplicated") }
    static var contextIn: String { NSLocalizedString("ClaudeFormContextIn", value: "In %@", comment: "Claude sheet context line under the New Table title: the database the table is created in") }
    static var newIndex: String { NSLocalizedString("ClaudeFormNewIndex", value: "New index", comment: "Claude sheet title: the New Index sheet") }
    static var newRelation: String { NSLocalizedString("ClaudeFormNewRelation", value: "New relation", comment: "Claude sheet title: the New Relation (foreign key) sheet") }
    static var columnSection: String { NSLocalizedString("ClaudeFormSectionColumn", value: "Column", comment: "Claude sheet section title in New Relation: the column of this table the foreign key is on") }
    static var nameAndActions: String { NSLocalizedString("ClaudeFormSectionNameAndActions", value: "Name and actions", comment: "Claude sheet section title in New Relation: the constraint name and its ON UPDATE / ON DELETE actions") }
    static var references: String { NSLocalizedString("ClaudeFormSectionReferences", value: "References", comment: "Claude sheet section title in New Relation: the referenced database, table and column") }
    static var fields: String { NSLocalizedString("ClaudeFormSectionFields", value: "Fields", comment: "Claude sheet section title: the columns an index is built on") }
}

// MARK: - Context lines

enum SAClaudeFormContext {

    /// The server: the connection's host, or its name when there is no host.
    static func server(_ doc: SPDatabaseDocument?) -> String? {
        guard let doc else { return nil }
        let host = doc.host()
        return host.isEmpty ? doc.name() : host
    }

    static func from(_ name: String?) -> String? { format(SAClaudeFormStrings.contextFrom, name) }
    static func currently(_ name: String?) -> String? { format(SAClaudeFormStrings.contextCurrently, name) }
    static func inside(_ name: String?) -> String? { format(SAClaudeFormStrings.contextIn, name) }

    /// The table a field editor edits: the document's table when the editor was opened from the table content view
    /// (its caller is an `SPTableContent`); nil for a query result.
    static func fieldEditorTable(_ editor: NSObject, _ doc: SPDatabaseDocument?) -> String? {
        guard let caller: NSObject = SAClaudeFormRecipes.outlet(editor, "callerInstance"),
              SAClaudeFormOwners.className(of: caller) == "SPTableContent" else { return nil }
        return doc?.table()
    }

    private static func format(_ format: String, _ name: String?) -> String? {
        guard let name, !name.isEmpty else { return nil }
        return String(format: format, name)
    }
}

// MARK: - Recipes

enum SAClaudeFormRecipes {

    typealias Kind = SAClaudeFormLayout.ControlKind

    static func recipe(for m: SAClaudeFormMatch) -> SAClaudeFormRecipe? {
        switch m.kind {
        case .newDatabase: return newDatabase(m)
        case .alterDatabase: return alterDatabase(m)
        case .duplicateDatabase: return duplicateDatabase(m)
        case .renameDatabase: return renameDatabase(m)
        case .password: return password(m)
        case .newTable: return newTable(m)
        case .duplicateTable: return duplicateTable(m)
        case .addKey: return addKey(m)
        case .resetAutoIncrement: return resetAutoIncrement(m)
        case .newIndex: return newIndex(m)
        case .newRelation: return newRelation(m)
        default: return nil
        }
    }

    /// `key`'s value on `object` by KVC, when it has such an ivar or accessor (nil otherwise, never an exception).
    /// The one outlet reader of the form (owners, context lines and recipes).
    static func outlet<T>(_ object: NSObject?, _ key: String) -> T? {
        guard let object else { return nil }
        return SAClaudeExportStyler.outlet(object, key)
    }

    /// A row for `control` with the static label beside it in the XIB; nil when either is missing.
    static func row(_ control: NSView?, _ kind: Kind) -> SAClaudeFormItem? {
        guard let control, let label = SAClaudeFormFind.label(beside: control) else { return nil }
        return .row(.existing(label), control, kind)
    }

    /// [Cancel (Escape), primary (the given one, else the Return button)] from `window`'s content view.
    static func footer(_ window: NSWindow, primary: NSButton? = nil) -> [NSButton]? {
        guard let contentView = window.contentView,
              let primary = primary ?? SAClaudeFormFind.button(in: contentView, keyEquivalent: "\r"),
              let cancel = SAClaudeFormFind.button(in: contentView, keyEquivalent: "\u{1b}") else { return nil }
        return [cancel, primary]
    }

    /// Rename database (SPDatabaseDocument · databaseRenameSheet): New name; context "Currently <db>". The XIB's
    /// prompt ("Rename database 'x' to:") is hidden as an unused static label.
    private static func renameDatabase(_ m: SAClaudeFormMatch) -> SAClaudeFormRecipe? {
        guard let name: NSTextField = outlet(m.owner, "databaseRenameNameField"),
              let footer = footer(m.window, primary: outlet(m.owner, "renameDatabaseButton")) else { return nil }
        let items: [SAClaudeFormItem] = [.row(.text(SAClaudeFormStrings.newName), name, .field)]
        return SAClaudeSimpleFormRecipe { [weak doc = m.document] in
            SAClaudeFormContent(title: SAClaudeFormStrings.renameDatabase, context: SAClaudeFormContext.currently(doc?.database()),
                                items: items, footerTrailing: footer)
        }
    }

    /// New database (SPDatabaseDocument · databaseSheet): Name / Encoding / Collation; context: the server.
    private static func newDatabase(_ m: SAClaudeFormMatch) -> SAClaudeFormRecipe? {
        guard let name = row(outlet(m.owner, "databaseNameField") as NSTextField?, .field),
              let encoding = row(outlet(m.owner, "databaseEncodingButton") as NSPopUpButton?, .popUp),
              let collation = row(outlet(m.owner, "databaseCollationButton") as NSPopUpButton?, .popUp),
              let footer = footer(m.window, primary: outlet(m.owner, "addDatabaseButton")) else { return nil }
        let items = [name, encoding, collation]
        return SAClaudeSimpleFormRecipe { [weak doc = m.document] in
            SAClaudeFormContent(title: SAClaudeFormStrings.newDatabase, context: SAClaudeFormContext.server(doc), items: items, footerTrailing: footer)
        }
    }

    /// Alter database (· databaseAlterSheet): Encoding / Collation; context: the database.
    private static func alterDatabase(_ m: SAClaudeFormMatch) -> SAClaudeFormRecipe? {
        guard let encoding = row(outlet(m.owner, "databaseAlterEncodingButton") as NSPopUpButton?, .popUp),
              let collation = row(outlet(m.owner, "databaseAlterCollationButton") as NSPopUpButton?, .popUp),
              let footer = footer(m.window) else { return nil }
        let items = [encoding, collation]
        return SAClaudeSimpleFormRecipe { [weak doc = m.document] in
            SAClaudeFormContent(title: SAClaudeFormStrings.alterDatabase, context: doc?.database(), items: items, footerTrailing: footer)
        }
    }

    /// Duplicate database (· databaseCopySheet): the new name ("Destination") and "Duplicate database content";
    /// context "From <db>".
    private static func duplicateDatabase(_ m: SAClaudeFormMatch) -> SAClaudeFormRecipe? {
        guard let name = row(outlet(m.owner, "databaseCopyNameField") as NSTextField?, .field),
              let copyContent: NSButton = outlet(m.owner, "copyDatabaseDataButton"),
              let footer = footer(m.window, primary: outlet(m.owner, "copyDatabaseButton")) else { return nil }
        let items: [SAClaudeFormItem] = [name, .control(copyContent, .checkbox)]
        return SAClaudeSimpleFormRecipe { [weak doc = m.document] in
            SAClaudeFormContent(title: SAClaudeFormStrings.duplicateDatabase, context: SAClaudeFormContext.from(doc?.database()),
                                items: items, footerTrailing: footer)
        }
    }

    /// Password needed (· inputTextWindow): the header's text as the title, the message as the context, Password.
    private static func password(_ m: SAClaudeFormMatch) -> SAClaudeFormRecipe? {
        guard let header: NSTextField = outlet(m.owner, "inputTextWindowHeader"),
              let message: NSTextField = outlet(m.owner, "inputTextWindowMessage"),
              let field: NSSecureTextField = outlet(m.owner, "inputTextWindowSecureTextField"),
              let footer = footer(m.window) else { return nil }
        let items: [SAClaudeFormItem] = [.row(.text(SAClaudeFormStrings.password), field, .field)]
        return SAClaudeSimpleFormRecipe {
            SAClaudeFormContent(title: header.stringValue, context: message.stringValue, items: items, footerTrailing: footer,
                                hidden: [header, message])
        }
    }

    /// New table (SPTablesList · tableSheet): Name / Encoding / Collation / Type; context "In <db>".
    private static func newTable(_ m: SAClaudeFormMatch) -> SAClaudeFormRecipe? {
        guard let name = row(outlet(m.owner, "tableNameField") as NSTextField?, .field),
              let encoding = row(outlet(m.owner, "tableEncodingButton") as NSPopUpButton?, .popUp),
              let collation = row(outlet(m.owner, "tableCollationButton") as NSPopUpButton?, .popUp),
              let type = row(outlet(m.owner, "tableTypeButton") as NSPopUpButton?, .popUp),
              let footer = footer(m.window, primary: outlet(m.owner, "addTableButton")) else { return nil }
        let items = [name, encoding, collation, type]
        return SAClaudeSimpleFormRecipe { [weak doc = m.document] in
            SAClaudeFormContent(title: SAClaudeFormStrings.newTable, context: SAClaudeFormContext.inside(doc?.database()),
                                items: items, footerTrailing: footer)
        }
    }

    /// Duplicate table (SPTablesList · copyTableSheet): New name / Database; "Duplicate table content"; context
    /// "From <table>". The XIB's centred title and its "Duplicate table 'x' to:" prompt (rewritten by the controller
    /// at every open) are unused statics, hidden at every apply.
    private static func duplicateTable(_ m: SAClaudeFormMatch) -> SAClaudeFormRecipe? {
        guard let name: NSTextField = outlet(m.owner, "copyTableNameField"),
              let databaseLabel: NSTextField = outlet(m.owner, "copyTableToNewDatabaseMessageField"),
              let database: NSPopUpButton = outlet(m.owner, "chooseDatabaseButton"),
              let copyContent: NSButton = outlet(m.owner, "copyTableContentSwitch"),
              let footer = footer(m.window, primary: outlet(m.owner, "copyTableButton")) else { return nil }
        let items: [SAClaudeFormItem] = [.row(.text(SAClaudeFormStrings.newName), name, .field),
                                         .row(.existing(databaseLabel), database, .popUp),
                                         .control(copyContent, .checkbox)]
        return SAClaudeSimpleFormRecipe { [weak doc = m.document] in
            SAClaudeFormContent(title: SAClaudeFormStrings.duplicateTable, context: SAClaudeFormContext.from(doc?.table()),
                                items: items, footerTrailing: footer)
        }
    }

    /// Add a key? (SPTableStructure · keySheet): Key type. Context: the edited column's name, the explanation then
    /// staying as a wrapped note above the row; without a column name the explanation is the context line.
    private static func addKey(_ m: SAClaudeFormMatch) -> SAClaudeFormRecipe? {
        guard let contentView = m.window.contentView,
              let keyType: NSPopUpButton = outlet(m.owner, "chooseKeyButton"),
              let explanation = contentView.subviews.compactMap({ $0 as? NSTextField }).first(where: { !$0.isEditable && !$0.stringValue.isEmpty }),
              let footer = footer(m.window) else { return nil }
        return SAClaudeSimpleFormRecipe(didAttach: { _ in
            explanation.font = SAClaudeFormSheet.labelFont
            explanation.lineBreakMode = .byWordWrapping
            explanation.maximumNumberOfLines = 0
            return nil
        }, content: { [weak structure = m.owner, weak doc = m.document, weak window = m.window] in
            let column = structure.flatMap { SAClaudeFormRecipes.editedColumnName($0) }
            var items: [SAClaudeFormItem] = []
            if column != nil {
                if explanation.isHidden { explanation.isHidden = false }
                let width = max(SAClaudeFormLayout.minimumWidth, window?.contentView?.bounds.width ?? 0) - 2 * SAClaudeFormLayout.sideMargin
                let height = ceil(explanation.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: .greatestFiniteMagnitude)).height ?? 30)
                items.append(.wide(explanation, .custom(height: height)))
            }
            items.append(.row(.text(SAClaudeFormStrings.keyType), keyType, .popUp))
            let note = explanation.stringValue.replacingOccurrences(of: "\n", with: " ")
            return SAClaudeFormContent(title: SAClaudeFormStrings.addKey, context: column ?? SAClaudeFormText.joined([note]) ?? doc?.table(),
                                       items: items, footerTrailing: footer, hidden: column == nil ? [explanation] : [])
        })
    }

    /// The name of the column being edited in the structure view (the row whose Extra became auto_increment).
    static func editedColumnName(_ structure: NSObject) -> String? {
        guard let table: NSTableView = outlet(structure, "tableSourceView"),
              let column = table.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("name")) else { return nil }
        let row = table.editedRow >= 0 ? table.editedRow : table.selectedRow
        guard row >= 0, row < table.numberOfRows,
              let name = table.dataSource?.tableView?(table, objectValueFor: column, row: row) as? String,
              !name.isEmpty, name != "..." else { return nil }
        return name
    }

    /// Reset auto increment (SPTableStructure · resetAutoIncrementSheet): the value row; context: the table. The
    /// separator line, which the controller un-hides in the Structure view, is hidden at every apply.
    private static func resetAutoIncrement(_ m: SAClaudeFormMatch) -> SAClaudeFormRecipe? {
        guard let value = row(outlet(m.owner, "resetAutoIncrementValue") as NSTextField?, .field),
              let footer = footer(m.window) else { return nil }
        let line: NSView? = outlet(m.owner, "resetAutoIncrementLine")
        return SAClaudeSimpleFormRecipe { [weak doc = m.document] in
            SAClaudeFormContent(title: SAClaudeFormStrings.resetAutoIncrement, context: doc?.table(), items: [value],
                                footerTrailing: footer, hidden: line.map { [$0] } ?? [])
        }
    }

    /// New index (SPIndexesController window): Name / Type; section "Fields" with the indexed-fields table as a
    /// growing block and its +/− in the strip under it; the Advanced disclosure folding Storage / Block size. The
    /// advanced rows and the +/− move out of their boxes into the sheet once; the emptied Advanced view stays in the
    /// hierarchy (the controller toggles it) at a zero frame, and its toggling re-lays the form out. The controller
    /// animates its own resize at each toggle and at close: the form owns the height (`ownHeight`), re-fitting once
    /// that animation is over and dropping any dragged-in height at every begin.
    private static func newIndex(_ m: SAClaudeFormMatch) -> SAClaudeFormRecipe? {
        let o = m.owner
        guard let contentView = m.window.contentView,
              let nameField: NSTextField = outlet(o, "indexNameTextField"), let nameLabel: NSTextField = outlet(o, "indexNameLabel"),
              let typePopUp: NSPopUpButton = outlet(o, "indexTypePopUpButton"), let typeLabel: NSTextField = outlet(o, "indexTypeLabel"),
              let scrollView: NSScrollView = outlet(o, "indexedColumnsScrollView"),
              let addButton: NSButton = outlet(o, "addIndexedColumnButton"), let removeButton: NSButton = outlet(o, "removeIndexedColumnButton"),
              let buttonBar: NSBox = outlet(o, "anchoredButtonBar"),
              let triangle: NSButton = outlet(o, "indexAdvancedOptionsViewButton"),
              let disclosureLabel: NSButton = outlet(o, "indexAdvancedOptionsViewLabelButton"),
              let advancedView: NSView = outlet(o, "indexAdvancedOptionsView"),
              let storage: NSPopUpButton = outlet(o, "indexStorageTypePopUpButton"),
              let blockSize: NSTextField = outlet(o, "indexKeyBlockSizeTextField"),
              let storageLabel = SAClaudeFormFind.label(beside: storage),
              let blockSizeLabel = SAClaudeFormFind.label(beside: blockSize),
              let advancedBox = SAClaudeFormFind.box(around: storage),
              let footer = footer(m.window, primary: outlet(o, "confirmAddIndexButton")),
              ([nameField, nameLabel, typePopUp, typeLabel, scrollView, buttonBar, triangle, disclosureLabel, advancedView] as [NSView])
                .allSatisfy({ $0.superview === contentView })
        else { return nil }
        let advanced: [NSView] = [storageLabel, storage, blockSizeLabel, blockSize]
        return SAClaudeSimpleFormRecipe(install: { contentView in
            SAClaudeFormFind.reparent(advanced + [addButton, removeButton], into: contentView)
        }, didAttach: { sheet in
            sheet.ownHeight()
            // The controller's own (animated) resize runs first; re-fit on the next turn.
            return advancedView.observe(\.isHidden) { [weak sheet] _, _ in
                SAClaudeFormSheet.onMain { sheet?.setNeedsApply() }
            }
        }, content: { [weak indexes = o] in
            let open = !advancedView.isHidden
            // Moved out of the Advanced box, the advanced rows show while the fold is open. Not before: attach reads
            // the content to check the sheet before anything is changed.
            if storage.superview === contentView {
                for view in advanced where view.isHidden == open { view.isHidden = !open }
            }
            var items: [SAClaudeFormItem] = [
                .row(.existing(nameLabel), nameField, .field),
                .row(.existing(typeLabel), typePopUp, .popUp),
                .section(SAClaudeFormStrings.fields),
                .block(scrollView, minHeight: 104, grows: true, strip: [(addButton, .add), (removeButton, .remove)]),
                .disclosure(triangle: triangle, label: disclosureLabel),
            ]
            if open {
                items += [.row(.existing(storageLabel), storage, .popUp), .row(.existing(blockSizeLabel), blockSize, .field)]
            }
            return SAClaudeFormContent(title: SAClaudeFormStrings.newIndex,
                                       context: indexes.flatMap { SAClaudeFormRecipes.outlet($0, "table") as String? },
                                       items: items, footerTrailing: footer, hidden: [buttonBar, advancedBox], collapsed: [advancedView])
        })
    }

    /// New relation (SPTableRelations · addRelationPanel): sections Column / Name and actions / References; the
    /// spinner and its status at the footer's left. The XIB's four boxes (Name, Table:, References, Action) are
    /// hidden and their labels and controls lifted into the sheet by the engine. The reference pop-ups are refilled
    /// by the controller as the user picks; they fill their frames, so that never moves the layout. All views are
    /// found, and checked to be in the sheet, before anything is moved.
    private static func newRelation(_ m: SAClaudeFormMatch) -> SAClaudeFormRecipe? {
        let o = m.owner
        guard let contentView = m.window.contentView,
              let column: NSPopUpButton = outlet(o, "columnPopUpButton"),
              let name: NSTextField = outlet(o, "constraintName"),
              let onUpdate: NSPopUpButton = outlet(o, "onUpdatePopUpButton"),
              let onDelete: NSPopUpButton = outlet(o, "onDeletePopUpButton"),
              let refDatabase: NSPopUpButton = outlet(o, "refDatabasePopUpButton"),
              let refTable: NSPopUpButton = outlet(o, "refTablePopUpButton"),
              let refColumn: NSPopUpButton = outlet(o, "refColumnPopUpButton"),
              let spinner: NSProgressIndicator = outlet(o, "dataProgressIndicator"),
              let status: NSTextField = outlet(o, "progressStatusTextField"),
              let primary: NSButton = outlet(o, "confirmAddRelationButton"),
              let cancel = SAClaudeFormFind.button(in: contentView, action: "closeRelationSheet:"),
              spinner.superview === contentView, status.superview === contentView
        else { return nil }
        let controls: [NSView] = [column, name, onUpdate, onDelete, refDatabase, refTable, refColumn]
        let labels = controls.compactMap(SAClaudeFormFind.label(beside:))
        let enclosing = controls.compactMap(SAClaudeFormFind.box(around:))
        guard labels.count == controls.count, enclosing.count == controls.count else { return nil }
        var boxes: [NSBox] = []
        for box in enclosing where !boxes.contains(where: { $0 === box }) { boxes.append(box) }
        func item(_ index: Int, _ kind: Kind) -> SAClaudeFormItem { .row(.existing(labels[index]), controls[index], kind) }
        let items: [SAClaudeFormItem] = [
            .section(SAClaudeFormStrings.columnSection), item(0, .popUp),
            .section(SAClaudeFormStrings.nameAndActions), item(1, .field), item(2, .popUp), item(3, .popUp),
            .section(SAClaudeFormStrings.references), item(4, .popUp), item(5, .popUp), item(6, .popUp),
        ]
        return SAClaudeSimpleFormRecipe(didAttach: { _ in
            spinner.controlSize = .small
            spinner.setFrameSize(NSSize(width: 16, height: 16))
            return nil
        }, content: { [weak doc = m.document] in
            SAClaudeFormContent(title: SAClaudeFormStrings.newRelation, context: doc?.table(), items: items,
                                footerLeading: [spinner, status], footerTrailing: [cancel, primary], hidden: boxes)
        })
    }
}
