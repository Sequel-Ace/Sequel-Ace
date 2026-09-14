//
//  SATextViewDelegate.swift
//  Sequel Ace
//
//  The accessors an SPTextView delegate can offer so the view reaches the
//  document and tables list it edits against through a declared contract
//  instead of valueForKeyPath:. Part of the KVC clean-up tracked in #2641.
//

import AppKit

/// Delegates of an `SPTextView` can hand the view the document and tables list the
/// text is edited against. Both are optional; a view whose delegate provides neither
/// still works, it just has no structure data to offer for completion and printing.
@objc protocol SATextViewDelegate: NSTextViewDelegate {
    @objc optional var tableDocumentInstance: SPDatabaseDocument? { get }
    @objc optional var tablesListInstance: SPTablesList? { get }
}

extension SPTextView {
    /// The document the delegate works against, or nil if the delegate provides none.
    @objc var delegateDocument: SPDatabaseDocument? {
        (delegate as? SATextViewDelegate)?.tableDocumentInstance ?? nil
    }

    /// The tables list the delegate works against, or nil if the delegate provides none.
    @objc var delegateTablesList: SPTablesList? {
        (delegate as? SATextViewDelegate)?.tablesListInstance ?? nil
    }
}
