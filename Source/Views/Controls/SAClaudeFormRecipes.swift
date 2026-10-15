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
    static var password: String { NSLocalizedString("ClaudeFormLabelPassword", value: "Password", comment: "Claude sheet row label: the password field of the encrypted connection file sheet") }
    static var newName: String { NSLocalizedString("ClaudeFormLabelNewName", value: "New name", comment: "Claude sheet row label: the field with the new name of a database or table being renamed or duplicated") }
    static var contextCurrently: String { NSLocalizedString("ClaudeFormContextCurrently", value: "Currently %@", comment: "Claude sheet context line under the Rename Database title: the database's current name") }
    static var contextFrom: String { NSLocalizedString("ClaudeFormContextFrom", value: "From %@", comment: "Claude sheet context line under a Duplicate title: the database or table being duplicated") }
    static var contextIn: String { NSLocalizedString("ClaudeFormContextIn", value: "In %@", comment: "Claude sheet context line under the New Table title: the database the table is created in") }
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
}
