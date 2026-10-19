//
//  SAManagerDocumentSection.swift
//  Sequel Ace
//
//  The Query Favorites and Content Filter managers list "Global" and its items, then this connection's document
//  section: a header row named after the connection's .spf file, then the items stored in that file. The document
//  section is always last (the managers add it last, and nothing — add, duplicate, import, drop — puts an item after its
//  items).
//
//  For a window that was never saved as an .spf file the header reads "Untitled N" and its items live only in memory
//  (they are kept only if the connection is saved as a file). Empty, it is a heading with no purpose: the list hides it
//  (walkthrough fix 2). The model keeps the header — the managers' loops walk to it, and saving reads the sections from
//  it — and the list leaves it out only while it is the last item, so row i is always item i. Kept as is when the window
//  came from a saved file or when the section already has items.
//
//  Shared with the unit tests.
//

import AppKit

@objc(SAManagerDocumentSection) final class SAManagerDocumentSection: NSObject {

    /// The key marking a section header item (keep in sync with SPQueryFavoriteManager.m / SPContentFilterManager.m).
    static let headerKey = "headerOfFileURL"

    private static var hiddenHeaderKey: UInt8 = 0

    /// The document section's header when the list hides it: the window isn't a saved file and the section is empty —
    /// its header is the last item and isn't the first (Global's). Nil otherwise.
    static func emptyUntitledHeader(in items: NSArray, documentIsUntitled: Bool) -> AnyObject? {
        guard documentIsUntitled, items.count > 1, let last = items.lastObject as? NSDictionary,
              last.object(forKey: headerKey) != nil else { return nil }
        return last
    }

    /// Hides `items`' document section in the list bound to `controller` when it is empty and the window isn't a saved
    /// file (`emptyUntitledHeader`): the controller's arranged objects leave the header out while it is the last of
    /// `items`. Call once, before the controller gets its content. True when the section is hidden.
    @discardableResult
    @objc(hideEmptySectionIn:items:documentIsUntitled:)
    static func hideEmptySection(in controller: NSArrayController, items: NSMutableArray, documentIsUntitled: Bool) -> Bool {
        guard let header = emptyUntitledHeader(in: items, documentIsUntitled: documentIsUntitled) else { return false }
        objc_setAssociatedObject(items, &hiddenHeaderKey, header, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        controller.clearsFilterPredicateOnInsertion = false
        controller.filterPredicate = NSPredicate { [weak items] object, _ in
            guard let items else { return true }
            return !isHidden(object as AnyObject?, in: items)
        }
        return true
    }

    /// The rows the list shows for `items`: all of them, less the hidden header while it is the last.
    @objc(visibleRowCountOf:)
    static func visibleRowCount(of items: NSArray) -> Int {
        items.count > 0 && isHidden(items.lastObject as AnyObject?, in: items) ? items.count - 1 : items.count
    }

    /// Whether `object` is `items`' hidden header and still its last item.
    private static func isHidden(_ object: AnyObject?, in items: NSArray) -> Bool {
        guard let object, let header = objc_getAssociatedObject(items, &hiddenHeaderKey) as AnyObject? else { return false }
        return object === header && (items.lastObject as AnyObject?) === header
    }
}
