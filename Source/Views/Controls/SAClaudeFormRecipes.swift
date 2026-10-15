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
        case .renameDatabase: return renameDatabase(m)
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
}
