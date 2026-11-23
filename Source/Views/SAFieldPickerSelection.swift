import AppKit

/// Resolves the single column child advertised for a searchable field picker.
/// Keys use identity: different rows' enable criteria can compare equal.
@objc public final class SAFieldPickerSelection: NSObject {
    private weak var indexedEditor: NSRuleEditor?
    private let rows = NSMapTable<AnyObject, NSNumber>(
        keyOptions: [.weakMemory, .objectPointerPersonality], valueOptions: .strongMemory)

    /// Reads the current column from the editor, never from a cached selection.
    /// A reload indexes rows once, then validates each cached row in constant time.
    @objc(selectedColumnInEditor:criterion:columns:fallbackIndex:)
    public func selectedColumn(in editor: NSRuleEditor, criterion: AnyObject,
                        columns: [NSObject], fallbackIndex: Int) -> NSObject? {
        var criteria = indexedCriteria(in: editor, for: criterion)
        if criteria == nil {
            rows.removeAllObjects()
            indexedEditor = editor
            for row in 0..<editor.numberOfRows {
                if let first = editor.criteria(forRow: row).first {
                    rows.setObject(NSNumber(value: row), forKey: first as AnyObject)
                }
            }
            criteria = indexedCriteria(in: editor, for: criterion)
        }
        if let criteria, let column = columns.first(where: { $0.isEqual(criteria[1]) }) {
            return column
        }
        return columns.indices.contains(fallbackIndex) ? columns[fallbackIndex] : nil
    }

    private func indexedCriteria(in editor: NSRuleEditor, for criterion: AnyObject) -> [Any]? {
        guard indexedEditor === editor, let row = rows.object(forKey: criterion)?.intValue,
              row < editor.numberOfRows else { return nil }
        let criteria = editor.criteria(forRow: row)
        // Rows may move or be replaced without changing the row count. Rebuild
        // on an identity mismatch, and don't retain removed criteria in the index.
        guard criteria.count > 1, (criteria[0] as AnyObject) === criterion else { return nil }
        return criteria
    }
}
